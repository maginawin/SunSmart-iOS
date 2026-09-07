# Site / Space 持续同步失败日志分析

## 结论与证据边界

本次失败停在 App 对持久化待确认提交的云端回读校验：连续三次比较不一致，进入 `uploadReadbackConflict`。自动同步和手动 SYNC 均会先恢复这条旧提交，失败后退出，尚未进入新的配置上传。再次导入又因待确认提交而保留本地配置，因此重复进入相同循环。

能够确认“为什么持续失败”的控制流程，尚不能从这份日志确定“最初哪个字段不同”。日志没有提供本地待确认配置，远端 JSON 又被截断；不能直接认定服务端丢失设备、未保存配置，或本机比较一定误判。

分析依据为用户提供的现场日志、当前工作区源码和生产比较函数的合成探针。HEAD 为 `129444b199ef958cdba30744693f60d53be0605a`，工作区还包含上一轮已实施的恢复改动。本轮只新增分析文档，没有继续修改业务代码，没有请求生产接口或执行真机验收。本文不保存原日志中的 Mesh 密钥。

## 两个 Space 必须分别判断

| 对象 | 日志证据 | 判断 |
| --- | --- | --- |
| Site `BBEE852F-DFC0-41C1-AFB3-C28BF17633EE` | siteInfo HTTP 200、业务 200 | Site 查询成功；子 Space 失败可以使 Site 显示同步异常 |
| wifi，`518352B8-7B67-46BD-9FCC-EBADC6B05D56` | 本地/远端版本均为 1788779646，nodes=0、switches=1、groups=2；skipped=serverUpdateTimestampNotNewer | 此段是没有更新版本的跳过，不是目标 Space 的冲突 |
| Space 1，`34B05AF1-8207-45BA-82FE-68B0CF405CE5` | submitted=1788779974，三次 mismatch，随后 uploadReadbackConflict | 本次持续同步失败的目标 |

前面的 `schema=1 groups=2 spaceZones=2` 不能当作 Space 1 本地提交的拓扑证据。Space 1 远端响应显示 groups=[]、nodes=1；本地提交的 groups / triggerZones 未打印。

## 持续失败的调用链

1. 导入目标 Space 时输出 `preserved pending local deletion/recovery`。当前 `preservesLocalChanges` 在存在 submission 时即成立，这句话不代表一定残留删除日志，也不能证明用户刚执行过删除。
2. 同步任务先调用 `SpaceConfigurationSafety.resumeUpload`，加载持久化提交，版本始终为 1788779974。该版本不是本次请求时间，也不代表日志已经证明原上传被服务器接受。
3. 每轮调用三次 spaceInfo，均 HTTP 200 / 业务 200。代码已通过 Space 身份、nodes 数组、配置可解析及权限条件，随后发现逻辑配置不相等。
4. 三次之后记录 `uploadReadbackConflict` 并返回失败，保留待确认提交。只有 prepared 提交且远端仍精确等于已确认基线时，现有实现才有取消旧待提交的特殊出口；本次没有走到该出口。
5. `CloudSynchronizationManager` 收到恢复失败立即结束。日志中没有新的 `/sync/spaceprops`、`/sync/siteprops` 或 `[CloudSync][Request]`，与此路径一致。
6. 用户在 Site 列表点失败图标，再点 SYNC，只是再次加入同一个同步任务；进入 Space 后自动同步也先恢复同一提交。远端没有变化时，每轮仍是相同的三次读取和失败。
7. 下一次导入继续保留本地逻辑配置，避免用未确认的云数据覆盖本地；这个保护不能自行解决配置冲突。

源码位置：

- `SunSmart/Common/Data/SpaceConfigurationSafety.swift`：160–165（保留条件）、448–503（持久提交回读及失败）。
- `SunSmart/Common/Cloud/CloudSynchronizationManager.swift`：327–344（恢复调度）、921–946（先恢复、失败即退出、之后才生成新上传）。
- `SunSmart/Main/Site/Controller/SiteViewController.swift`：3504–3529（列表 SYNC 仅重新排队）。
- `SunSmart/Main/Space/Controller/SpaceViewController.swift`：1515–1519（Space 内配置冲突进入恢复入口）。
- `SunSmart/Common/Data/ImportData.swift`：1561–1564（保留待确认本地配置）。

## 双方都是一个设备，为何还能 mismatch

`SpaceConfigurationIntegrityPolicy.configurationData` 比较的内容包括：

| 比较对象 | 实际字段或规则 |
| --- | --- |
| 非虚拟 Group | address、选定 profile 字段、proximityLightingPath |
| Node 成员关系 | uuid、unicastAddress、groupAddress、groupState |
| Space Trigger Zones | 优先 spaceData.triggerZones，否则在没有 spaceData 字典时读取根级 triggerZones |
| 比较方式 | 提取配置后，JSON 字典按键排序，再比较 Data；字段缺省、值类型以及未规范化数组的顺序仍可产生差异 |

`submittedNodes=1 remoteNodes=1` 只证明成员数相同。远端探针打印 UUID `D1C00EDA-6FDD-4036-AE3F-F12590223FC9`、地址 0046，但没有对应本地提交成员字段，不能证明两边成员完全相同。

这份日志缺少两侧完整的比较输入，尤其是本地 memberships / groups / triggerZones，以及远端截断部分中的 groupState、groupAddress、spaceData。应优先检查这些字段，不能从可见的 configComplete=false、CCT 或亮度默认值推断冲突：它们不参与此比较。updateTimestamp 本身也不参与配置 Data 比较。

合成探针直接调用当前生产比较函数，使用一个设备、零 Group 的无敏感数据，结果如下：

| 人工构造的唯一差别 | 比较结果 |
| --- | --- |
| triggerZones 缺省与显式 [] | 不相等 |
| groupState 缺省与显式 0 | 不相等 |
| groupAddress 缺省与显式 "0000" | 不相等 |
| 仅 configComplete、defaultLightness、updateTimestamp 改变 | 相等 |

这些探针证明当前比较对字段表示的敏感性，不证明现场一定出现了对应差异，也不证明这些差异在所有业务状态下都可安全视为等价。特别是旧客户端缺少 Trigger Zone 字段时，仍需保护已有非空拓扑。

## 与 129444b 及上一轮改动的关系

`129444b` 已加入 `readbackDiagnostic`，包含远端版本、设备增减 UUID 等信息；原直接回读路径仍调用它。当前持久恢复的 `resumeUpload` 路径新增了自己的日志，只打印提交版本与双方节点数，没有复用原诊断能力。这是上一轮实现留下的诊断缺口，即使数量相同也无法继续定位差异。

此外，列表失败入口仍只有通用 SYNC；Space 内失败入口才识别配置冲突并进入恢复。两个入口处理不一致，使用户在列表反复重试却没有解决差异的路径。

自动同步策略确实存在，本次也有恢复执行证据，但自动执行“回读确认”不等于自动解决真实配置冲突。上一轮自动化与构建结果不能证明这台手机的旧提交已经恢复。当前日志也不能套用先前“提交 0 台、回读 4 台”的诊断：本次为 1 对 1，缺少同样的设备残留证据。

## 其他日志的相关性

- gzip 声明与实际请求体不符是可单独排查的传输问题；本段查询均业务成功并返回可比较配置，不能直接归因为本次 mismatch。
- 当前 activeUsers 和 heartbeat 显示 owner，没有展示权限拒绝；失败发生在配置比较分支。
- BLE 后续连接成功、白名单配置成功，并从 0046 收到 LightCTLStatus，说明该段设备通信能完成；它与此前云配置回读冲突是不同阶段。
- secondary beacon、重复包丢弃、本地 Client model 未绑定提示及 XPC 日志，均没有证据构成此次 `uploadReadbackConflict` 的原因。云端失败已发生在这些 BLE 交互之前。

## 推荐后续处理

1. 先补持久恢复回读的字段级差异诊断：提交 ID / phase / timestamp、远端 timestamp、最新本地版本；对规范化后的 memberships / groups / triggerZones 输出有限数量的不同字段路径、缺失/类型差别及安全摘要。禁止打印密码、Mesh Key 或完整网络载荷。
2. 用该手机持久化的 submission.configuration 与同次回读生成的 configurationData 对比，才能确定首个真实差异。这两份逻辑配置不需要包含原始 Mesh 密钥；若需服务端排查，再关联对应上传版本和读取版本。
3. 若只是已确认语义等价的默认值或表示格式差异，集中修正比较规范化并覆盖老数据、空拓扑、真实拓扑差异。不能统一忽略缺失字段，也不能删除成员比较。
4. 若存在真实成员或拓扑差异，保留两侧证据，统一 Site 列表与 Space 内的配置恢复入口，明确选择如何处理冲突；不能通过清除 pending / blocked 或盲目重传旧快照把状态改为成功。
5. 对已经确认的冲突，自动调度应有稳定的冲突状态及受控重查，避免每次页面出现都重复同一组请求。保留网络中断后的自动恢复能力，并区分“尚待确认”与“需要处理配置冲突”。

本轮探针退出码为 0；仅验证生产比较函数的合成输入，没有重现该手机的完整配置，也没有宣称服务器或真机验收通过。
