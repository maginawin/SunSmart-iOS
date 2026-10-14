# 空目标定时重进丢失：原因分析与修复记录

日期：2026-10-14。工作树：`feat-timed-limited-261008`；分支：`feat/timed-limited-261008`；HEAD：`2430962e`。调查开始时工作树干净。用户已确认按本方案实施；App 修复、相关回归及代表品牌构建已完成，真机与实际云端验收待用户执行。改动未提交。

## 结论

已证实 App 新增无设备定时的成功分支遗漏 Space 配置变更通知：定时落库、列表刷新，但没有推进待上传版本或安排新一轮云同步。空 Group 与空 Scene 定时均受影响。这与设备每台 16 个槽位的限制无关。

重进时，本地若仍被判断为已同步，云端同时间戳且数量不同的快照可以覆盖本地。因此云端若仅保存过 1 条，就能将本地 17 条替换成 1 条。隔离探针已验证这些代码条件；本轮没有现场日志、数据库或实际 POST/GET，尚不能证明现场云端最后快照恰好为 1 条、由哪次请求上传。剩余数量取决于上传时机，并非代码固定保留一条。

同类关联问题：编辑页直接删除无设备定时也只刷新列表，没有通知云同步，重进可能重新出现。该分支还忽略数据库删除失败，并跳过关联 Group 的 bindSchedules 清理，建议一并补齐成功/失败一致性。

## 端到端证据

### 新增、保存和显示

- `SunSmart/Main/Timed/Controller/ScheduleAddViewController.swift` 的 `saveBtnAction`：Group 无节点，或 Scene 关联的 Group 均无节点时，`needSync=false`。这类配置允许离线保存。
- 新定时使用独立递增业务 ID，`nodeSlots=[]`；`TimedSchedulerBindings.prepare/commit` 保存完整候选数组。无目标设备不占物理槽位，不应限制 Space 只能有 16 条。
- `SunSmart/Common/Data/Database.swift` 的 Schedule 表按 Mesh、子网和业务 ID 唯一；保存/加载没有按目标节点数过滤记录。
- `needSync=false` 成功分支仅在 1.5 秒后关闭页面并发送 `schedulesRefreshNotificationName`，没有发送 `spaceDataChangedNotificaitonName`。
- `TimedViewController` 的刷新观察者更新列表、数量并调用 `space.save()`；普通 save 只保存现有值，不推进 lastUpdate，也不创建上传任务。

### 云同步与重新进入

- `SpaceViewController` 接收 `spaceDataChangedNotificaitonName` 后，调用已有 `commitLocalChangeForCloudSync`：刷新数量、单调推进 lastUpdate、落库并按 common/device 类型安排上传。
- `SpaceData.needUploadCloud` 由 lastUpdate 与 lastUploadCloudTimestamp 比较得出。漏发通知使新定时可能继续沿用已确认的版本。
- 非空定时进入 `SyncExecutionSession`，其完成处理会发设备配置变更通知；空目标绕过设备同步，不能依赖这一出口。
- `ExportData.swift` 从 SQLite 读取完整 schedules 并编码；没有删除空目标定时。只有确实再次上传当前快照，才能把后续新增条目带上云。
- 新建 G1 等操作本身会安排云同步。若某次已排队上传捕获了第一条定时，后续新增却没有标记新版本，界面可能显示上一批成功，但这不证明其余 16 条已被上传确认。这是解释现场数量的一条可行时序，尚未由现场日志确认。
- 在线进入经 Site 的 Space GET/恢复入口进入 `SpaceData.update`。其 `shouldApplyServerData` 接受“同时间戳 + 数量/配置差异 + 本地无需上传”等条件。
- 当云为 1 条、本地为 17 条、时间戳相同且无其他恢复保护时，数量差异使导入成立；随后删除该 Space 本地 Schedule 表记录、保存云端数组，并更新活动内存。重新显示 1 条因此属于配置替换，不只是列表展示错误。
- 同步清理会清理失效引用，但已核对其并不以空 Group/Scene 为由删除整条定时。

### 空 Scene 及相关入口

| 入口 | 当前行为 | 本次判断 |
| --- | --- | --- |
| 新增以空 Group 为目标的定时 | 本地保存，只有列表通知 | 确定漏云同步通知 |
| 新增以空 Scene 为目标的定时 | 进入同一个 needSync=false 分支 | 相同问题 |
| Scene 有 Group，但这些 Group 均为空 | 同样无需设备同步 | 相同问题 |
| 新增 Scene 对象本身 | SceneAddViewController 已发送 common 配置通知 | 不应与“以空 Scene 为目标的定时”混同 |
| 编辑无设备/无需下发的定时 | 已发送 common 通知，但位于延迟 UI 回调内 | 保留行为，建议把配置通知前移到保存成功后 |
| 无设备定时启用/停用 | TimedViewController 已发送 common 通知 | 作为回归对照，不重写 |
| 编辑页删除无设备定时 | 本地删除，只发送列表通知 | 本次必要关联修复 |
| 非空定时设备同步 | 通过 SyncExecutionSession 通知配置变更 | 保留设备同步路径，避免重复安排 |

## 已执行的验证与限制

1. 使用现有 `check_timed_slot_persistence.py` 的生产 SQLite 扩展、生产 Codable 和绑定实现，在临时 harness 中加入两组各 17 条的空 Group/Scene 记录；数据库连接重开后仍为 17 条，ID 唯一，编解码往返保留空 bindings。现有该脚本的全部行为回归也通过。
2. 抽取生产新增成功分支执行 17 次，通知替身记录到 17 次列表刷新、0 次 Space 变更。再执行生产导入判断表达式，确认同时间戳时云 1/本地 17、localNeedsUpload=false 会应用云端；改为 true 则不因该数量差异覆盖。
3. 探针只替代 UI、通知调度与外部状态边界，不运行完整 UIKit、云请求或设备。它证明分支行为和触发条件，不冒充现场端到端复现。
4. 首次临时 SQLite 探针切换连接后未恢复既有夹具连接，使后续 query_only 失败注入作用到错误连接；修正临时夹具连接后整套通过。Swift 解释器默认缓存写入受环境限制，改用临时可写 module cache 后通过。均未修改生产代码或共享缓存。
5. 本轮未构建 App，未操作真机或服务器。此前记忆只用于定位历史格式兼容问题，当前结论已重新核对当前源码；不将旧审查或构建结果当作本次验证。

## 已确认的实施范围

1. **新增空目标定时**：在数据库提交、活动内存及 Group 绑定更新成功后，立即复用现有 common 配置变更机制，推进 Space 待上传版本并安排云同步；列表通知仍负责 UI。不能把数据变更标记放在 1.5 秒提示结束或页面退出之后。Group、Scene 共用现有分支即可，不分别实现两套逻辑。
2. **删除无设备定时**：检查真实删除结果，失败保留内存和页面、不宣告成功；成功后同步清理活动列表和相关 Group 的 bindSchedules，再立即通知 common 配置变更，保证云端也删除。同类已有清理逻辑优先复用，不新增通用同步框架。
3. **无需下发的编辑**：把已有 common 配置通知从延迟 UI 收尾前移到保存成功点，防止提示期间退出/重进造成同类未标记窗口。不扩大到其他模块的通知重构。
4. **保留现有保护**：不修改单设备 16 槽限制、不限制合法空目标、不推断物理 slot、不放宽导入身份/权限/格式检查，也不通过总是拒绝云导入掩盖漏标记。相关目标稍后加入设备仍必须进行现有容量预检。
5. **范围**：主要为共享 ScheduleAddViewController 的三个成功出口和必要回归；五品牌共享行为，无新增资源、国际化或依赖需求，不需要 SDK API、固件或服务端改动。不新增恢复流程。

## 实施后验证与验收

自动验证优先在现有 harness 中执行实际生产成功出口和保存边界，不能只检查源码中是否出现通知字符串：

- 空 Group、完全空 Scene、仅关联空 Group 的 Scene：新增 1/17 条后立即标记待上传；上传快照完整，确认后数量与业务字段不变。
- 首次上传只包含 1 条，上传/确认期间继续新增其余条目：旧批次完成后仍应保留待上传状态；失败、重试、退出重进不覆盖新增条目。
- 无设备定时删除后上传、重进不复活；数据库删除失败不删内存、不通知成功；Group 绑定缓存同步清理。
- 编辑无需设备下发时，提示尚未结束也已标记变更；开关原有通知路径继续生效；非空目标不重复通知设备同步。
- 空组 17 条保存合法，后续加入支持 Scheduler 的设备应按现有容量限制拒绝，不能只下发前 16 条。
- 运行相关持久化、上传回执/恢复与删除回归；稳定后核对实际本地 workspace、SDK realpath，使用 SunSmart / Debug / generic iOS 无签名构建一次。共享逻辑没有品牌条件差异时不机械重复五品牌。

人工最短验收：分别用空 G1、空 Scene S1 创建 17 条，等本次云同步完成，退出重进并重启 App，均保留 17 条和原参数；删除其中一条后重进为 16 条；模拟上传失败后恢复网络仍能补传。真实云读回和界面结果由用户验收，本轮未自动执行。

## 已经只剩 1 条的数据

本修复防止继续丢失，不会凭空生成其余 16 条。如果 SQLite 已被导入覆盖，只能从仍完整的其他客户端、历史副本或诊断材料核对恢复来源；不能仅凭“原有 17 条”推测时间、名称和动作。未获授权不执行数据恢复。

要把现场“1 条”时序进一步坐实，只需对应 Space 的最后一次上传/GET 的 schedules 数量与 ID 摘要、updateTimestamp，以及重进日志中的 SpaceImport received/applyDecision；无需提供密钥或完整凭据。缺少这些材料不妨碍修复上述已证实的 App 缺陷。


## 实施结果（2026-10-14）

生产改动仅在 `SunSmart/Main/Timed/Controller/ScheduleAddViewController.swift`，新增 10 行、删除 4 行：

- 新增无设备定时：完成本地保存及活动列表/组绑定更新后，立即发送现有 common 配置变更通知。
- 删除无设备定时：检查数据库删除结果；失败保留内存及关联缓存，使用已有国际化错误提示；成功后从当前 Group 的 bindSchedules 清理同 ID 记录并通知云同步。
- 编辑无需下发的定时：将已有 common 通知移到成功点，早于延迟关闭页面。
- 非空目标继续由既有设备同步流程通知，不新增重复通知。未修改格式、容量、导入规则、SDK、资源或依赖。

### 当前验证结果

| 验证入口 | 本次结果与边界 |
| --- | --- |
| `scripts/check_timed_empty_target_cloud_sync.py` | 新增行为夹具，执行生产控制器保存成功后的完整收尾、空目标删除分支、Space 变更处理及导入判断。空 Group、完全空 Scene、关联空 Group 的 Scene 各 17 条均立即推进待上传版本；旧批次确认后仍待上传；删除失败/成功、编辑提示期及设备同步分工通过。对未修改 HEAD 执行同一回归，在首条新增未标记待上传处按预期失败。UI 调度、对象存储及上传队列为替身，上传回执由下述实际状态机另测。 |
| `scripts/check_timed_slot_persistence.py` | 原有回归及新增空目标场景通过。使用生产绑定事务、实际 SDK SQLite 和生产 Codable 验证 17 条逐次新增、独立连接重开、完整目标字段；后续给同一设备分配 17 条被容量策略拒绝；真实 SQL 删除失败保留记录、恢复写入后删除成功。新场景使用独立数据库，以免继承既有失败注入的未释放事务，详见下方独立问题。 |
| `scripts/check_space_recovery_receipts.py` | 原有回归及新增 Scene 1→17 上传时序通过。第一条被接收后继续新增 16 条，断网保留回执，重读持久回执后只确认第一版，新版仍待上传；第二版完整读回后确认 17 条。使用生产回执状态机，网络和 App 数据库为受控边界。 |
| `scripts/check_timed_delete_result.py` | 现有设备删除预留失败、空消息与未清空回执保护通过。 |
| `scripts/check_timed_device_slots.py` | 业务 ID 与每设备槽位独立、合法/损坏 payload、完整 canonical 及旧字段兼容通过。 |
| `git diff --check` | 通过。 |

本地入口：`SunSmartLocal.xcworkspace`；SDK realpath 为 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`，revision `2598bd1`，SDK 工作树干净。

构建：SunSmart / Debug / iphoneos / generic iOS / `CODE_SIGNING_ALLOWED=NO`，DerivedData 固定为 `SunSmart-feat-timed-limited-261008`，最终输出 `BUILD SUCCEEDED`。首轮 quiet 输出曾混有“command failed with exit code 0”的诊断及既有 weak capture 警告，故对同一代码和缓存补做一次非 quiet 增量确认，明确成功。未 clean 或修改代码规避环境。此为五品牌共享控制器逻辑，无品牌条件、资源或依赖变化，采用 SunSmart 代表构建。

未执行自动真机、Simulator、真实云请求或其他客户端联调。不能将隔离测试和构建等同于真实重进及云同步验收；人工步骤见前文。修复不会自动找回已经被覆盖的记录。

### 独立发现：SDK SQLite savepoint 失败后可能残留事务（未纳入本次修复）

新增重开数据库验证最初接在既有失败注入测试之后，第二连接读到旧的 32 条记录，而原连接看到新数据。只读追踪并单独编译当前 SDK 的实际 SQLite 源码后，已复现以下最小条件：

1. 调用 `Connection.savepoint`，在 block 内注入异常。
2. SDK 异常分支执行 `ROLLBACK TO SAVEPOINT` 后直接抛出，没有 `RELEASE` 该 savepoint。
3. 下一次 savepoint 写入成功返回，写连接查询数量为 1，独立连接仍为 0；外层遗留 savepoint 尚未结束，后续成功操作不能据此视为已经持久提交。

证据位置：SDK `Sources/SQLite/Core/Connection.swift` 的 `savepoint` 及共用 `transaction` 异常处理。该行为存在于本次未修改的 `2598bd1`，并非本修复新增；触发需要此前存在 savepoint 异常，不能直接认定为用户本次无异常操作的现场原因。

本次把正常空目标持久化回归放入独立测试数据库，不修改 SDK 或隐藏此风险。现有失败注入测试只在同一连接内检查回滚，不能证明异常之后重启仍保留后续写入。建议后续单独分析所有相关调用方，修正 savepoint 生命周期并补“失败→成功重试→关闭/重开”验证；遵循共享 SDK 单写入负责人及正式依赖发布约束。本任务的通知漏发修复已经完成，此独立风险仍开放。
