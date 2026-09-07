# 删除全部设备后 Space 同步保护无法恢复：原因分析与修复方案

日期：2026-09-07。工作区：`trigger-zone-sep`。分析开始时 HEAD：`6c496837`；结束时观察到外部提交 `3e7c9a37`（原有 Disable 任务修复），未改变本文分析的保护/删除分支。

本轮仅分析、临时诊断验证及方案记录，未修改业务代码、仓库测试、SDK 或服务端。未操作 Git 提交；开始时已有的 SpaceViewController、两份测试及测试脚本改动已由外部提交收录，本轮未改动这些内容。

## 1. 结论

问题与 `d4e4e43` 有关，但不能全部归因于该提交：

| 行为 | 引入提交 | 当前源码位置 |
| --- | --- | --- |
| 持久化配置保护、恢复弹窗、阻止受保护配置上传 | `d4e4e43` | SpaceConfigurationSafety；SpaceViewController；ExportData |
| 导出遇到尚未应用的拓扑修复时拒绝，不再通过导出自动清理 | `d4e4e43` | ExportData.swift:394 |
| 普通生命周期 commit 遇到保护状态直接失败 | `d4e4e43` | ProximityLightingLifecycleCoordinator.swift:170 |
| 将 hasDestructiveRepairs 纳入导入预检失败条件 | **`6c49683`** | ImportData.swift:116 |
| 进入 Space 时发现失效拓扑则记录 entryTopologyNeedsReview | **`6c49683`** | SpaceViewController.swift:746 |
| 导入应用阶段再次禁止破坏性修复 | **`6c49683`** | ImportData.swift:2430；ProximityLightingLifecycleCoordinator.swift:168 |

本次日志直接对应最后三项与原有保护机制的组合。应修复明确删除与异常恢复之间的衔接，不能仅删一个 guard 或清掉保护标记。

## 2. 日志已经证明什么

### 2.1 云端返回的不是“删除完成后的空 Space”

两次 GET 都成功，返回相同大小的响应及相同的已展示内容：

- `deviceCount=9`，但 DeviceParameterNodeProbe 显示实际 `nodes` 为 4 个。
- Primary addresses 为 `0031、0028、0040、0037`。
- C000 的 Path 仍为 `[43,49,61,64,46,40]` 和 `[46,61,0,0,0]`。
- 两个普通 Group 仍在，Profile 为 type 7、8。

这证明当前云端快照仍含设备及旧 Path；不能仅凭这段日志确定是删除上传未发出、上传失败、旧端覆盖还是服务端处理错误。`deviceCount` 与数组计数不一致是待核查的摘要异常，不是当前 invalidRemoteTopology 的直接判断条件。

Path 中 0 是合法空槽，不应按坏数据处理。实际拓扑使用 Sunricher vendor model 所在 Element 地址，不能仅将 Primary address 列表与 Path 对比后断定具体哪些地址不存在。第一条 Path 有 6 个不同的非零引用，而输入只有 4 个 Node，每个 Node 只生成一个标准化拓扑地址，已足以说明它无法全部对应当前 Group 成员；具体修复位置仍需要完整 elements、subscribe、groupState 数据确认。

### 2.2 warnings 和 hardErrors 为空，仍然会失败

ImportData.swift:115–116 的条件由三个部分组成：warnings 非空、hardErrors 非空、存在 hasDestructiveRepairs。

Reconciler 把清除无效 Sequence 地址、移除无效 Group/Space Zone 成员等归为 destructive repair；去除 Zone 重复成员不属于这一类。当前日志只打印前两部分，遗漏 repairs，所以看起来“没有错误却拒绝”。

在日志对应当前代码的前提下，`preserved local snapshot warnings=[] hardErrors=[:]` 可以直接推断第三项为真。不是猜测 HTTP 故障，也不是 Profile 校验失败；Profile 失败会记录另一种 reason。

### 2.3 删除全部设备仍满足“存在本地快照”条件

ImportData.swift:1499–1506 使用“有真实 Node **或** 有普通 Group”判断 hasUsableLocalSnapshot，并没有验证这份本地拓扑确实完整。因此即使本地所有设备已删除，只要 Group 还在，就会走 preserveLocalSnapshot，然后设置 invalidRemoteTopology。

这个变量的名称容易误导：日志表示保留现有本地数据，不代表它是已经验证的最后完整副本。

## 3. Reload 为什么无法解决

完整链路如下：

1. 进入 Space 获取云端快照。
2. 预检发现需要清除失效引用，保持本地内容，记录持久化保护状态。
3. 加载本地网络后，入口发现本地 context 无效、硬错误或 destructive repairs，记录 entryTopologyNeedsReview。此 reason 会覆盖此前的保护原因，无法直接看出最早失败点。
4. 点击失败图标，恢复弹窗尝试保护状态下检查本地导出。
5. 日志中的 `rejected unapplied topology repairs` 证明该次本地导出也存在尚未处理的 repairs，因而不能作为完整本地恢复副本。该日志本身不区分 repair 类别。
6. Reload cloud data 只是重新 GET 后调用同一个 space.update，没有清理失效引用或选择恢复来源的逻辑。
7. 云端数据仍然无效，再次走原分支；只有成功完成校验和导入，或明确授权完整本地恢复，保护才会解除。

因此两条现有恢复路径在本场景中都不可用。Reload 不是数据修复工具，无限重试不会改变输入。

还有一个需随修复处理的顺序问题：远端无效拓扑会在版本/是否应采用远端的判断之前设置全 Space 保护（ImportData.swift:1518 对比 1686）。即使本地有较新的明确删除操作，也可能先被旧远端拦住。反过来，当前 blocked 又是强制采用远端的条件之一，不能通过简单解除预检来导入旧设备、覆盖尚未上传的删除。

## 4. 已确认的删除流程缺口

DevicePermanentDeletionCleanup.swift:49–71：

- 设备删除完成后，尝试通过统一生命周期清理 Node 的所有 Element 地址对应的 Group Path、Group Zone、Space Zone 引用。
- `d4e4e43` 之后，只要 Space 已 blocked，普通生命周期 commit 就返回 nil；context、持久化或加载失败也会使提交失败。
- 调用方随后仍执行 markLocalChangePendingCloudSync 和 applyDeletion，后者清理日程及设备扩展，却不清理三类拓扑引用。
- didCommit 在尝试开始时已经设置为 true，失败也没有可重试状态。
- 删除页据 Reset/强制移除结果删除列表项、更新云同步状态，未区分“硬件删除成功”与“拓扑清理未完成”。

SDK 的锁定版本 `86f5ec9e40148b9cd93e0512702337fcec41dd40` 也已只读核对：ConfigNodeResetStatus 会移除 Node；MeshNetwork.remove 会删除 Node 数据并解除其 network 引用。强制删除入口同样先 remove 再执行 App 清理。因此清理失败时不能假装整个删除已回滚，必须保留后续完成清理的任务。

这是一条已确认能够产生或维持“节点已删除，拓扑仍引用旧设备”的代码路径。当前提供的日志没有删除阶段的 Reset、DevicePermanentDeletion、CloudSync 请求和回读，所以还不能断定它就是这次最初的数据损坏来源。

## 5. 跨 Site 重复添加的关联

同一物理设备重新配网后继续使用真实 Device UUID，是需要支持的输入，不能随机更换 UUID 规避冲突。

当前 `6c49683` 已引入 ProximityLightingTopologyContext，按目标 Mesh UUID、Network ID 读取成员；已有适配层用例覆盖不同 Site/Space 复用设备 UUID 和地址。当前日志在远端预检阶段就失败，并不需要读取其他 Site 的 Node 才能触发。

仍需核查两类问题：

1. App 删除 context 仅用 subNetworkId 查 Space，且缓存/部分扩展清理依赖当前 manager。SpaceData.load(subNetworkId:) 的查询没有附加 meshUUID/siteId；只有 NetKey/Network ID 也相同或上下文发生切换等情况下才可能选错，不能仅凭同 UUID 就断言该缺口已触发。删除流程应捕获完整身份和网络，避免 Reset 后再依赖可切换的全局对象。
2. 如果 A 的完整上传后，B 的 GET 因同 UUID 而减少成员，需要服务端检查 Space 归属、UUID upsert/delete、缓存和异步任务。现有日志不足以证明服务端有 UUID 全局冲突；本轮 App 修复不以服务端改造为前置条件。

## 6. 是否可以移除判断

不建议直接移除，原因具体如下：

- 仅移除 ImportData.swift:116 的第三项，仍会在导入提交阶段遇到 destructive repair 限制，可能变为配置持久化失败及待恢复导入。
- 仅移除 Space 入口判断，之前持久化的 invalidRemoteTopology 仍然存在，生命周期和导出继续拒绝。
- 仅清除 blocked 标记，本地 ExportData 仍拒绝 unapplied repairs。
- 把所有限制一起删除，相当于恢复“将缺失节点/成员当成已经删除，自动清除 Path/Zone 并可能生成 Disable 或缩减邻居任务”，会重新暴露 `6c49683` 防范的数据丢失问题。

合理调整是把“明确完成的用户删除”“用户审阅同意的历史数据修复”和“外部快照不明缺失”分开处理。前两类在限定范围内完成清理；第三类继续保护，不因 Reload 或 GET 200 自动推断删除意图。

## 7. 建议修复方案

### P0：补齐明确删除生命周期，防止继续产生残留

1. 删除前捕获目标 Site/Space、meshUUID、networkId、Node UUID 和完整 Element 地址，保留强网络上下文；对可继续的删除建立持久化清理记录。
2. 按 Reset 成功或用户强制移除的结果，记录实际删除集合；失败且未强删的设备保留。所有删除入口共享同一完成逻辑。
3. 对可验证且加载完整的逻辑数据，只清理本次已确认删除的地址引用，并验证差异严格落在授权删除集合内。不要借这次删除顺便清理来源不明的其他坏引用，也不要对普通 import 关闭保护。
4. 将“清理提交失败”作为独立结果，保留待处理记录并允许重试；重启后可继续。已 Reset 的硬件无法回滚，页面应准确表达数据清理未完成，禁止把半成品上传。
5. App 事务、SDK 持久化和回读需分别核验，不能声称跨两个数据库天然原子。成功后记录待云同步版本，再更新剩余设备的完整拓扑任务。
6. 全部删除后允许 nodes 为空、原 Group/Profile 仍在；Path 保留既有槽位且全部为空，Group/Space Zone 无失效成员，不要求删除 Group 或改成普通 Profile。

### P0：让现存卡死数据有可执行的恢复路径

1. 先保存当前原始本地及云端副本，再生成只读差异预览；不能要求“导出已经完全合法”才能备份待修复输入。
2. 有持久化删除证据时，先重放该 Space 的明确删除清理，防止旧云端设备复活；完整性校验和云端回读通过后结束恢复。
3. 历史问题没有删除记录时，展示本地/云端设备差异、失效引用及选定来源，提供明确的修复确认。若用户选择保留已删除全部设备的本地结果，保持本地设备列表为零，只清理失效引用，保留 Group/Profile 和其他有效配置。
4. 缺失/损坏 Profile、无法解码数据、身份冲突、超容量或未完成导入不能借此路径强制放行；需要完成导入恢复或选择可用副本。
5. 将普通 Reload 与显式修复区分。Reload 得到相同无效数据时给出具体失败原因，不再暗示重载必定能解决。
6. 本地修复提交、保护解除、待上传、上传回读确认按阶段记录。不能先全局清 blocked 再尝试保存；云端最终确认前也不能显示整个同步已经完成。

### P1：修正输入采用顺序和诊断

1. 明确记录本地待上传删除、远端版本、导入/修复模式；不要因为无效旧远端就把可验证的合法本地删除永久封锁，也不能仅凭客户端时间戳忽略真实冲突。
2. 保留首次保护原因及阶段，不让入口的泛化 reason 覆盖全部诊断；日志补齐 repairs 类别、Group/设备地址、context 是否完整、本地/远端 Node 数及版本，不打印密钥或认证信息。
3. 导入 outcome 区分“版本无需应用”和“无效输入已保留本地”；避免都用不带原因的 skipped。
4. Node/拓扑/扩展清理全程用捕获的目标身份，测试在不同 Site 复用 UUID、地址、Group 地址以及 Network ID 的情况。

实施范围优先 App 的删除 context、共享生命周期、导入保护/恢复、页面恢复状态及相关测试。不默认改 SDK、服务端 schema 或真实 Mesh UUID。新增可见文案同步 English 和简体中文；如增加恢复预览 UI，必须真机走完布局和交互验收。

## 8. 本轮诊断验证与后续验收

临时脚本：`/tmp/space_deletion_review_probe.py`。它复用现有适配层 runner，编译生产 preflight、Context、Planner、Coordinator、Reconciler 和 Node 任务方法；SDK、数据库、保护状态使用测试替身，不修改仓库测试。

本轮执行结果：

- 模拟日志的旧格式 Path 和 4 个 Node，假定 vendor 地址等于 Primary：warnings=0、hardErrors=0、repairs=5，策略为 preserveLocalSnapshot。
- 相同 Path 将 nodes 改为空：repairs=8，仍被拒绝。
- 模拟 Node 已从网络移除，在 blocked 状态下，完整 context 的明确删除 commit 返回 nil，旧 Path/Space Zone 引用保留；同一输入未 blocked 时能够清理。
- 现有 scoped import 适配层用例同时通过，包括跨 Site/Space 相同 UUID 与地址、禁止破坏性导入及正常显式删除。

这是合成数据和真实 App 逻辑的机制复现，不是用户完整服务端快照回放，不证明实际异常地址恰为 43、46、61，也不证明手机上的删除曾因 blocked 失败。

实现后必须增加：受保护/未保护状态删除、单个/全部/部分成功/强制删除、提交失败重启重试、旧云端不得复活明确删除、历史失效引用修复预览及确认、损坏 Profile 继续拦截、跨 Site UUID/地址/Network ID 碰撞隔离、修复后上传回读与再导入幂等性等行为用例。

随后直接运行 generic iPhoneOS 的共享品牌构建，覆盖所有 SDK 引用 target；本轮仅分析，未运行构建或 Simulator。真机验收必须完成：删全部 → 离开 → 重入 → 恢复（历史坏数据）→ 云端回读零设备 → 再入无保护失败；另一个 Site 重配同一设备后，原 Space 仍为空且新 Space 正常。保留部分设备时还需读回 Enabled、Relay、Neighbors。构建或 HTTP 200 不能替代这些验收。

进一步确认最初来源所需证据为删除前后日志中的 Reset/强制删除结果、DevicePermanentDeletion 清理结果、实际上传快照和 GET 回读，并带目标 Site/Space 与版本。无需提供认证字段或 Mesh 密钥。
