# 空 groupAddress 导致持续同步失败的现场分析

## 已定位的直接原因

目标为 Space `34B05AF1-8207-45BA-82FE-68B0CF405CE5`。新增字段级诊断在每轮均报告：

| 字段 | 本地待确认提交 | 云端回读 |
| --- | --- | --- |
| memberships[0].groupAddress | missing：没有该字段 | 长度为 0 的字符串，即空字符串 |
| 比较版本 | 1788779974 | 1788779974 |
| Node 数量 | 1 | 1 |
| 增减设备 UUID | 无 | 无 |

`differencesShown=1 scanLimited=false` 表明本次诊断未截断，在当前逻辑配置比较范围内只报告这一项差异。多轮 submittedSHA256 均为 d879ddfd076fe707，remoteSHA256 均为 e1309631e5c813b9；同一 submissionId 也未变化。它们持续重现同一对配置的比较失败。

因此，本次可以把原因收敛为 App 对“未提供 Group 地址”与“Group 地址为空字符串”的兼容处理缺失，导致表示差异触发 `uploadReadbackConflict`。不是上一轮仍待确认的 Trigger Zone、groupState 或设备增减假设。没有证据表明本次设备成员丢失。

日志只证明服务端查询返回空字符串，尚不能判断它来自写入补默认、数据库默认值还是响应序列化。处理本次 App 比较兼容不必先确定这个服务端内部实现位置。

## 源码如何产生误判

1. `ExportData.swift` 480–493：导出节点时，仅在 `node.group` 存在时补充 groupAddress；本次持久提交明确没有这个键。
2. 同文件 102–107 的既有地址处理，把缺省和空字符串均识别为没有可用地址；但这套语义未应用到回读比较。
3. `SpaceConfigurationIntegrityPolicy.swift` 137–144：把 uuid、unicastAddress、groupAddress、groupState 按键是否存在原样放进 memberships，随后序列化。缺少键和带空字符串的键生成不同 Data。
4. `SpaceConfigurationSafety.resumeUpload` 比较新生成的远端 Data 与持久化 submission.configuration。比较失败三次后 block，旧提交一直保留。
5. `CloudSynchronizationManager.swift` 921–946 在恢复失败时直接结束，尚未进入下一次配置导出和上传。

保护流程原本用于阻止真正的配置冲突，本次被一个未规范化的空值表示触发。缺少键与空字符串均没有有效 Group 地址，不应仅凭这一点要求用户在本地和云端配置之间选择。若节点声明已入组却没有有效地址，仍应由既有成员完整性检查处理，不能借此次兼容把不完整成员关系改为有效。

## 新日志还揭示了较新的本地修改被阻塞

- pending phase 为 accepted：本地记录认为该提交已被接受，但尚未完成回读确认；仅该状态本身不能代替服务器配置验证。
- submitted 与 remoteTimestamp 同为 1788779974，远端版本字段已与待确认版本相同。
- localTimestamp 为 1788781814，比上述版本新 1840 秒，即 30 分 40 秒。
- 当前比较目标是旧 submission，不是最新本地配置。本地新版本的具体修改内容没有记录在本段日志中，不能据此推断修改了哪个业务字段。

误判会同时阻止两件事：结束旧提交，以及继续上传最新本地修改。修复后的预期顺序应为：

1. 对旧提交与回读配置做一致的空 Group 地址规范化；完整校验仍通过后确认旧版本 1788779974。
2. 完成该版本对应的回执处理、移除该待确认提交及相应回读阻塞标记。
3. 保留本地 lastUpdate=1788781814，仍由 needUploadCloud 判定为待上传；随后导出最新配置并继续原上传与确认流程。
4. 新版本也通过上传和确认后，才认为最新修改同步完成。

不能把旧提交的成功直接确认到最新本地版本，也不能导入较旧远端配置覆盖新修改。当前 finishSubmission 按 submission.timestamp 更新上传版本，后续 manager 检查 needUploadCloud 的方向是正确的；本次需解除前面的表示误判，而不是跳过这套版本保护。

## 推荐的最小修复边界

1. 在共享逻辑配置规范化入口，统一 memberships.groupAddress 的缺省与精确空字符串，采用同一种无地址表示。保留真实非空地址和 groupState 比较。
2. 同时考虑磁盘已有的 submission.configuration 和 authorizationBaseline。它们是提取后的配置 Data，使用 memberships 而非原始 nodes；不能直接当成原始上传 payload 再传给 configurationData，否则可能遗漏设备成员。需要对这种持久配置做相同规范化，或由统一等价比较入口处理两侧数据。
3. 仅改未来导出字段不足以保证当前旧 pending 自动恢复，尤其是老快照中本来包含空字符串的反向情况。验证两种方向，并保留代际、权限及回执版本约束。
4. 本轮证据只覆盖 missing 与精确空字符串。不要顺便把 null、空白字符串、0000、非法地址、不同有效地址等全部视为等价，也不要放宽 Trigger Zones、groupState 或设备成员比较。
5. 日志继续保留。真实字段差异仍应阻止确认；本次不需要通过强制采用某一侧配置或清除全部恢复状态解决。

建议回归覆盖：未分组节点的新上传、已有 accepted pending 的双向空值表示、旧 authorizationBaseline、新本地版本继续上传、真实 Group 地址变化仍不相等、groupState 和拓扑差异仍不相等，以及旧版本回执确认不吞掉后续操作。

## 其他日志的判断

| 日志 | 与本次同步失败的关系 |
| --- | --- |
| wifi Space serverUpdateTimestampNotNewer | 另一 Space 本地与远端版本相同的跳过，与目标冲突无关 |
| HTTP 200 / 业务 200 | 查询成功；本次错误在成功响应之后的配置等价判断 |
| activeUsers=[]，随后 owner heartbeat | 空的活跃用户列表不能等同于权限被移除；本段没有权限拒绝证据 |
| BLE 白名单成功、LightCTLStatus、TimeStatus 返回 | 该段设备通信可完成，不能解释或消除此前云配置比较失败 |
| currentActiveDistribution timeout | 固件分发状态查询未在超时内完成，是独立现象；不足以认定普通灯控或云同步失败 |
| TimeSet / TimeStatus 的 GMT(-28800) | 下发和回复均为 UTC-8；是否符合预期须核对 Site 配置，不能仅以开发环境时区判为错误 |
| secondary beacon、重复包丢弃、App 本地模型未绑定提示 | 与本次确定的 groupAddress 比较失败没有因果证据 |
| XPC、nw_connection 时间戳计数提示 | 不足以解释本次稳定的单字段差异；未见本段请求因此失败 |
| Content-Encoding=gzip 但实际未压缩 | 独立的请求编码不一致，当前成功响应后的单字段比较仍足以解释故障 |
| HTTP body 仍打印 Mesh Key | 既有 HTTP 全量日志的实际脱敏缺口；新增 SpaceConfigurationDiff 已脱敏不代表整个日志链路都已脱敏，建议单独收敛 HTTP 日志输出 |

本文未复制原始 Mesh 密钥。

## 验证与本轮范围

- 读取当前工作区相关源码；HEAD 仍为 129444b，保留此前所有未提交改动。
- 使用当前生产比较函数构造“一个节点、无 Group、唯一差异为 groupAddress 缺省与空字符串”的无敏感数据探针，得到与现场相同的单字段诊断。
- 仅在探针输入中移除远端空 groupAddress 后，两侧配置相等；替换为真实地址 C000 后仍不相等，探针退出码 0。
- 本轮仅分析并新增本文档，没有修改业务代码、运行生产请求或宣称真机修复完成。
