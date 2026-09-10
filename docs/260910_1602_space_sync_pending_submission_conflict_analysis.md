# Space 同步失败：旧提交与云端空配置冲突

## 结论

本次失败发生在云配置回读校验阶段。三次 `/sitespace/get/spaceprops` 均返回 HTTP 200、业务 200，JSON 解码成功；但云端配置与本机持久化的待确认提交不一致，最终触发 `uploadReadbackConflict`。这是实际节点成员与 Group Path/Zone 差异，不能仅通过放宽空 Trigger Zone 比较解决。

本段点击 SYNC 后只执行旧提交的回读，没有重新上传配置。当前 App 的列表失败入口没有转入冲突处理流程，因此远端数据不变时，反复点击会再次失败。

尚不能确定云端为何变成空设备配置：日志缺少原始上传请求、当时回读以及后续写入记录，不能直接认定是服务端丢数据、另一台手机覆盖或本机快照错误。

分析依据为用户提供日志及当前 `site-trigger-zone` 工作区源码，HEAD `8e2bc9b0`。本轮仅新增此文档，未修改业务代码、访问生产接口、执行构建或真机测试。文档不保存日志中的密码与 Mesh Key。

## 现场证据

- Site：`15C98668-A4B7-4F90-B970-D662ACC4CF00`。
- Space：`AD3F16B9-FBD1-4728-B79A-3A53BDBD0432`。
- 待确认提交：`E2246B22-0018-41EE-B491-20175640AB01`，阶段为 `accepted`。

| 项目 | 待确认提交 | 云端回读 | 判断 |
| --- | --- | --- | --- |
| 版本时间戳 | 1788859046 | 1789011179 | 云端版本时间更晚 |
| 时间（UTC+8） | 2026-09-08 17:17:26 | 2026-09-10 11:32:59 | 相差 42 小时 15 分 33 秒 |
| 节点数量 | 2 | 0，deviceCount 也为 0 | 两个已提交节点均不在当前回读中 |
| Group 第一条 Path 前两个槽位 | 5、2 | 0、0 | 真实设备引用差异 |
| Group zones[2].addresses | [5, 2] | [] | 真实区域成员差异 |
| memberships | 2 项 | 0 项 | 源自 nodes 的配置身份与归属信息 |
| Space triggerZones | 0 项 | 32 项 | 另外存在空区域表示差异；已展示项为 items=[] |

`submittedNodes=2` 来自持久化提交的逻辑配置，不是这次重新导出的设备列表。`localTimestamp` 等于提交时间，只能说明日志中的本地版本时间仍相同，不能单凭该字段保证当前本地完整配置与旧提交逐字段一致。

三次提交侧 SHA256 摘要均为 `e0b07cd2bd6424e8`，云端侧均为 `dcc1f390dc124c16`，且远端时间戳相同，说明本轮读取稳定得到同一份不同配置。`differencesShown=24 scanLimited=true` 是诊断行数上限，不表示总共只有 24 个差异。HTTP 正文的截断也是日志输出截断；比较使用已解码配置，并非截断文本。

云端版本时间明显较晚，使“这次刚上传后短暂还没读到”不足以解释现象；但这些是载荷版本时间，不是服务端事务审计时间，不能证明具体覆盖操作、写入人或实际提交顺序。每轮只有三次回读、间隔约 0.5 秒，也不能独立排除较长的异步一致性延迟。

## 当前源码如何产生该结果

1. `SunSmart/Main/Space/View/SpacesViewCell.swift:190` 将失败按钮操作转给 delegate。
2. `SunSmart/Main/Site/Controller/SiteViewController.swift:3530` 显示 Cancel/SYNC 通用弹窗；SYNC 排入 syncSpace，或 Site 尚未上传时排入 syncSite。这里没有判断 `requiresConfigurationReview`。
3. `SunSmart/Common/Cloud/CloudSynchronizationManager.swift:977` 在生成上传 API 之前先调用 `resumeUpload`。一旦恢复失败，立即结束任务，不会执行后续重新导出与上传。
4. `SunSmart/Common/Data/SpaceConfigurationSafety.swift:581` 从恢复状态读取原提交，最多执行三次 spaceInfo 查询。它要求 Mesh Key 指纹和规范化后的配置一致；本段没有出现密钥不一致诊断，但配置差异本身已经足够失败。
5. 同文件 `:648` 输出日志中的 submissionId、phase、时间戳和配置差异；`:668` 在三次不一致后记录 `uploadReadbackConflict` 并返回 `configurationUploadUnconfirmed`。
6. 同文件 `:552` 的完成逻辑只在 verified 后清除待确认提交、更新已上传时间及相应冲突标记。本次没有达到此分支，所以旧提交继续保留。

`accepted` 是本地恢复状态，不是服务端证明“完整配置已持久化且仍为当前版本”的回执。正常路径在上传成功响应后标记 accepted；旧恢复数据迁移也可产生 accepted，因此仅凭本段 phase 无法还原最初上传全过程。

## 配置比较是否误判

`SpaceConfigurationIntegrityPolicy.configurationData`（`:271`）提取非虚拟 Group 的 Profile、Path/Zone，nodes 的 uuid/unicastAddress/groupAddress/groupState，以及 Space triggerZones；`:313` 只对已确认兼容的空 groupAddress 表示做规范化，`:336` 再比较配置。

因此，本案有两类不同问题：

- **确定的真实配置冲突**：2 个节点及对应 Group 引用在远端消失。即使忽略 triggerZones 的空数组表示，仍然必须判定不一致。
- **待核实的表示兼容问题**：triggerZones 的 [] 与 32 个空槽目前不同。当前导出直接编码本地 triggerZones（`ExportData.swift:575`），本地默认值为 []（`SpaceData.swift:230`）。需要核对完整远端 32 项、槽位编号语义及生成来源后，才能决定是否将“全空固定槽”和“无区域”统一，不能过滤中间空槽或忽略有内容的区域。

HTTP、业务响应和解码均成功，本段请求也明确 `declaredContentEncodingGzip=false actualBodyGzip=false`，响应 gzip 已成功解码，没有证据将此失败归因于请求压缩。日志没有 BLE/Mesh 配置发送失败链，也没有 HTTP 500 或权限拒绝；role=editor 本身不是本次失败原因。

## 为什么界面重试不能恢复

Site 列表失败入口只有通用 SYNC；Space 内的 `SpaceViewController.updateSyncState`（`:1507`）才会将已阻止且需要审核的状态导向 `showConfigurationRecovery`（`:1533`）。两处入口处理不一致是当前可确认的 App 行为缺口，解释了列表反复 SYNC 的现象，但不能解释最初云端为何缺少节点。

Space 内的“使用本机数据”调用 `authorizeLocalRecovery`（`SpaceConfigurationSafety.swift:1001`）：审核当前完整本地导出、校验权限和生命周期、读取并备份远端、建立新版本、取代旧待确认提交，再触发新上传。它代表明确选择整份本机配置替换云端，需要先判断哪份配置才是用户希望保留的版本；不是普通重试的等价操作，也不保证服务端之后的回读必然一致。

此外，“重新加载云端数据”当前仍调用普通 `space.update`（`SpaceViewController.swift:1599`）。`ImportData.swift:1649` 会保护 pending submission 等本地未完成状态，因此此 accepted 冲突下存在重载仍被保护拦住、无法完成恢复的源码路径。此为静态分析；给定日志没有展示该选项的执行结果，不能声称现场已验证。

最后几条 PJUIDebug 点击记录不包含配置恢复动作或网络结果，无法据此推断用户选择了哪份数据或恢复成功。

## 后续排查与修复方向

1. 先取原始提交时间附近的上传请求及响应、首次回读诊断。确认当时实际发出的目标 Site/Space、nodes 数量及 Group Path/Zone，关联本次 submissionId；避免把本轮只读重试误当成再次上传失败。
2. 服务端按上述 Site/Space 和两个版本查询写入历史，核对 nodes/成员关系、Group 拓扑及 spaceData 是否同批保存；追踪 1789011179 对应版本的来源、调用端和请求内容。当前 editor/owner 字段不是最后一次写入者的审计证明。
3. 若写入内容完整，核对 spaceInfo 的关系查询、缓存键、读副本和异步任务；若有后续空配置写入，继续定位其客户端导出或覆盖流程。不能仅依据时间戳更新判定所有配置都已同步。
4. App 统一列表与 Space 内的冲突入口，将“继续回读确认”和“处理已确认冲突”分开；保留真实成员/拓扑校验。云端重载需有明确放弃本地旧提交的恢复流程，不能只绕过保护或删除标记。
5. 若确认 [] 与全空 32 槽在产品语义上等价，再做局部规范化并覆盖旧持久化提交、真实非空区域和槽位位置的回归。它只能修复表示差异，不能修复本案设备缺失。

本轮结论是：**云端当前配置与旧提交存在实质冲突，App 正确拒绝确认成功；通用重试入口又无法解决冲突。最初是谁产生了云端空配置，还需要上传与服务端写入证据。**
