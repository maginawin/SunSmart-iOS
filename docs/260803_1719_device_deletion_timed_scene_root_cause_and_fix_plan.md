# 删除设备后重新添加出现 Timed 删除任务：根因分析与待确认修复计划

## 1. 分析范围

本报告分析以下完整生命周期：

1. Space 中已有 0～16 个 Timed，目标覆盖 Device、Group、Scene；
2. 灯 A 已经属于某个 Group，并已在设备侧保存相关 Scheduler Entry 和 Scene；
3. 通过正常 Reset 或 Force Delete 从 Space 删除灯 A；
4. 将已经重置为未配网状态的灯 A 重新添加到 Space，但不直接加入 Group；
5. 对比 Add 页面和 Lights 页面显示的同步状态；
6. 判断 Timed 与 Scene 是否保留了不应存在的设备关联或删除任务。

本报告只做当前 `fix` worktree、本地 `NordicSigMeshSDK`、Git 历史和现有聚焦测试的源码分析，没有修改业务代码，也没有进行真机、真实 Mesh、设备固件或服务器验收。

## 2. 总结论

### 2.1 当前删除流程只完成了一部分正确清理

删除一个 Node 时需要区分三层数据：

| 数据层 | 当前是否删除 | 结论 |
| --- | --- | --- |
| 设备硬件中的 Scheduler/Scene | 正常 Reset 会由设备恢复出厂；Force Delete 本身只删本地，设备必须随后真正重置才能重新配网 | 正常删除成立；Force Delete 不能单独证明硬件已清空 |
| SDK 中旧 Node 的 `schedulerActions`、`allSchedulerModelEntrys`、`sceneExecuteDatas` 持久化 | `MeshNetwork.remove → Node.delete` 会删除 Node 属性表记录 | 正常删除和本地 Force Delete 都会清理 |
| App 的 Space 级 `Schedule.nodeAddresses`、`Schedule.needDeleteNodeAddresses` | 当前 `Node.deleteExtension()` 没有处理 | 存在确定的直接设备目标地址残留 |

因此，“设备相关联的定时数据有没有删除”不能简单回答为全部删除或全部未删除：

- 旧 Node 的设备侧缓存会删除；
- App 的 Direct Device Timed 地址关联不会删除；
- Group/Scene Target 的全局 Timed 定义不应因为删除一个成员而被删除，只应让被删设备不再参与；
- Scene 的 Group 定义同样应保留，旧 Node 自己的 Scene 缓存随 Node 删除。

### 2.2 本次 16 个删除任务的直接根因不是旧 Node 缓存残留

重新配网得到的是一个新的 Node。它的 `allSchedulerModelEntrys` 初始为空字典，但“字典中没有某个 Scheduler Model 的 key”在当前严格判定中代表 unknown，而不是“该 Model 已权威确认没有 Entry”。

当前状态链如下：

1. 新 Node 完成基础配网和 Key Bind；
2. 新 Node 支持一个或多个 Scheduler Setup Model，但每个 Model 的缓存都还没有 known-empty key；
3. `Schedule.needsDelete` 发现任一 Scheduler Model 为 unknown，保守返回需要删除；
4. `Schedule.getNeedSyncDatas()` 的 orphan 扫描遍历 Space 的所有真实 Node；
5. 新 Node 不是任一 Group/Scene Target，且没有 Direct Device Target，于是被每一个 Timed 收为 `deleteNodes`；
6. Space 有 16 个 Timed 时，最终恰好生成 16 个删除任务。

这条规则原本用于保护真实的未知状态：历史缓存缺失、权威读取未完成或某个 cleanup Model 未确认时，不能假装已经删除成功。因此不能在 `needsDelete` 中把 unknown 全局改为 false。

### 2.3 Add 页面与 Lights 页面不一致的原因

普通 Add to Space 没有目标 Group，Classic/Professional Add 页只根据配网、Key Bind、附加配置和 Group Fast Add 结果设置成功状态。没有 Group 时，不会运行 Group deferred sync 的 Schedule 差异闭环。

退出 Add 页面后，Lights 页通过 `Node.needSync → getNeedSync() → getNodeNeedDeleteSchedules()` 重新计算全局差异。此时严格 Scheduler Model unknown 判定和每个 Timed 的 orphan 扫描生效，因此底部出现同步提示。

所以 Add 页面并不是已经证明“无需同步”，Lights 页面也不是凭空误报；两个页面使用了不同阶段、不同范围的真值。

### 2.4 Scene 不存在相同的 16 条删除任务问题

Scene 的模型与 Timed 不同：

- App Scene 通过 `GroupInfo.sceneExecuteDatas` 绑定 Group，没有 `Schedule.nodeAddresses` 这种直接设备目标地址列表；
- SDK 删除 Node 时会从 Mesh Scene 地址集合移除该 Node 的所有 Element；
- `Node.delete()` 会删除旧 Node 属性记录，其中包括 `sceneExecuteDatas`；
- 新 Node 只添加到 Space、尚未加入 Group 时，`getNodeSyncSceneDatas` 和 `getNodeNeedDeleteSceneDatas` 都因没有 Group 而返回空；
- Scene 没有类似 Timed 的“遍历全网所有 Node 并把 unknown Node 当 orphan delete”的逻辑。

因此，只执行“删除灯 A → 重置后重新添加到 Space”，当前源码不会生成与 16 个 Timed 同型的 Scene Delete 任务。

如果新 Node 直接加入一个配置了 Scene 的 Group，出现 Scene Store/Sync 任务是正确行为：新设备已重置，需要把目标 Group 的 Scene 重新写入；这不是旧 Scene 删除任务残留。

### 2.5 Scene 审计发现一个相邻但独立的问题

`Node.getNodeNeedDeleteSceneDatas()` 当前用 `schedulerSetupModel != nil` 作为删除 Scene 的能力门槛，而同文件的 Scene Sync 路径使用的是 `sceneSetupModel != nil`。

这不会制造本次“重新添加到 Space 后出现删除 Scene”问题，但会导致“支持 Scene、没有 Scheduler 的设备”可能漏报真正需要执行的 Scene Delete。它是独立的 capability guard 错误，建议在本次 Scene 生命周期回归测试中一并修正，但必须作为独立小任务验收，不能拿它解释当前 Timed 现象。

## 3. 源码证据链

### 3.1 正常删除和强制删除最终都会删除旧 Node 持久化

- `DeviceProtocol.deleteNodes`：正常路径收到 Reset 成功后调用业务扩展清理；Force Delete 路径调用业务扩展清理并显式 `meshNetwork.remove(node:)`。
- `DeviceLightsViewController.deleteNodes` 和 `DeviceLightViewController.deleteNode` 使用相同的正常/强制两分支。
- SDK `ConfigurationClientHandler` 收到 `ConfigNodeResetStatus` 后调用 `meshNetwork.remove(node:)`，所以正常删除不需要 App 再重复 remove。
- SDK `MeshNetwork.remove(nodeWithUuid:)` 会从 Mesh Scene 移除 Node Element、加入 Network Exclusion，并调用 `node.delete()`。
- SDK `Node.delete()` 会删除 `nodes` 与 `nodePropertys` 对应记录；`nodePropertys` 中包含 `scenesData`、`schedulesData` 和 `allSchedulerModelActions`。

这证明旧 Node 的 Scene/Scheduler 本地缓存不是本次 16 个删除任务的来源。

### 3.2 App 的永久删除扩展没有清理 Timed 地址

`MeshNetwork+SunSmart.swift` 中现有 `Node.deleteExtension()` 只清理：

- Kinetic Switch Proxy 引用；
- Group Ambient Light Sensor 引用；
- OTA Distributor 缓存；
- Gateway 映射；
- Change Control Page 和 Absolute CCT Range。

它没有遍历 `MeshNetworkManager.instance.schedules`，也没有移除：

- `Schedule.nodeAddresses` 中被删 Node 的地址；
- `Schedule.needDeleteNodeAddresses` 中已不再需要向硬件清理的地址。

对比 `Group.deleteExtension()`：删除 Group 时会明确从每个 Schedule 的 active/pending Group 地址数组移除该 Group 并保存。Node 生命周期缺少对称处理。

注意：不能直接把永久删除逻辑塞进现有 `Node.deleteExtension()`。该方法还用于 Fast Add 的 replace-node 清理等非“用户确认永久删除”场景；若无条件移除 Schedule 地址，会破坏 Restore/Replacement 语义。

### 3.3 严格 per-Model delete 判定把新 Node 解释为 unknown

`Schedule.needsDelete(from:contextGroup:)` 的当前契约：

1. 如果 Node 仍是当前 Schedule Target，则不删除；
2. 只要 Node 任一 Scheduler Setup Model 不存在于 `allSchedulerModelEntrys`，返回 true；
3. Model 全部 known 后，只有任一 Model 仍有有效 Entry或兼容缓存仍有有效 Entry时才返回 true。

`TimedSchedulerSingleOwnerContractTests` 还明确断言 unknown Model 必须继续 Retry，说明这是有意的安全语义，不能直接删除。

### 3.4 orphan 扫描把影响放大到所有 Timed

`Schedule.getNeedSyncDatas()` 最后会遍历 `MeshNetworkManager.instance.realNodes`，把满足以下条件的 Node 追加到 `deleteNodes`：

- `needsDelete` 为 true；
- 不是当前 Target；
- 尚未出现在 Direct/Group delete 集合。

因此一个 fresh-but-unknown Node 会对每个 Schedule 分别命中一次。容量为 16 时就会看到 16 个删除任务。

### 3.5 Git 历史定位

- 全网 orphan 删除扫描来自 2026-06-03 的 `4b7bed6d`，用途是发现未保存在 pending target 列表里的真实残留 Entry；
- 2026-07-27 的 `2891ec03` 将 `needsDelete` 从扁平 `schedulerActions` 切换为严格 per-Model 状态，并规定 unknown 必须继续清理；
- 2026-07-31 的缓存持久化修复解决的是既有 Node 重载后 known 状态丢失，没有覆盖“fresh provisioning 应初始化为 known empty”的生命周期；
- 2026-08-03 的 `13a61ce9` 主要修改单次 Time Sync 与 Restore/Fast Add 排队，没有改动本次 `needsDelete` 和 orphan 扫描，不是本问题的新引入提交。

准确归因是：

> 严格 per-Model 真值修复是正确方向，但 fresh provisioning 没有建立“设备已重置、各 Scheduler Model 权威为空”的初始状态；同时永久删除没有清理 App 的 Direct Device Timed 地址关联，形成两个生命周期覆盖缺口。

## 4. 修复方案比较

### 4.1 方案 A：修复生命周期真值，保留严格差异判定（推荐）

包含两项互补修改：

1. 在 SDK fresh provisioning 完成 Composition/基础 Key Bind、准备调用 App append-messages 之前，为新 Node 的每个 Scheduler Setup Model建立 known-empty 缓存，并清空扁平兼容缓存与损坏标记后持久化；
2. 在 App 的“用户确认永久删除”成功提交点，移除该 Node 地址在所有 Schedule active/pending Direct Device 数组中的引用并保存。

优点：

- 修复状态源头，Lights 不再把 fresh Node 识别为 16 个删除目标；
- Add to Group 时，known-empty 状态会让真正需要的 Group/Scene/Timed 配置正常生成，随后成功消息逐步写入 per-Model 缓存；
- 历史 Node、导入 Node、读取未完成 Node 仍保持 unknown，现有严格 Retry 安全性不变；
- Classic、Professional、Site Add、Restore 共用 SDK fresh-provisioning 边界，不依赖各页面重复初始化；
- Direct Device Timed 不再保留已删除地址；Group/Scene 全局定义保持不变。

风险与控制：

- known-empty 初始化必须发生在 App append Schedule 消息之前，不能放在 Add Success 之后，否则会擦掉本次 Fast Add 已成功写入的 Schedule 缓存；
- 只能用于真正完成新 provisioning 的 Node，不能用于 Space Reload、普通 Repair 或权威读取失败；
- 永久删除提交必须发生在 Reset 成功或用户确认 Force Delete 之后，不能在发送 Reset 前提前修改 Schedule。

### 4.2 方案 B：新配网后权威读取全部 Scheduler Model

在 Add 完成前，对每个 Scheduler Model 发送 Scheduler Register Get；非空时继续读取对应 Action，直到得到完整状态。

优点：

- 不依赖“恢复出厂必为空”的假设；
- 可以发现固件未正确清除 Scheduler 的异常。

缺点：

- 增加每个新设备的 Mesh 消息、耗时和失败面；
- Add 成功可能被权威读取超时拖延；
- 空设备本应可以由已完成 provisioning 的生命周期事实直接确定；
- 仍需另外实现 App Direct Device Timed 地址清理。

建议：不作为默认修复，可作为调试或异常固件的校验手段。

### 4.3 方案 C：在 `needsDelete` 或 orphan 扫描中忽略 fresh/unknown Node

优点是代码表面改动少。

不推荐，原因是：

- 容易掩盖真实的非 Owner 残留、历史缓存损坏和权威读取未完成；
- 破坏现有“unknown 必须可重试”的测试契约；
- 只压掉 Lights 提示，没有修复 Direct Device Timed 地址残留；
- 以后无法区分“fresh known empty”和“existing unknown”。

## 5. 推荐方案的文件与职责规划

### 5.1 本地 NordicSigMeshSDK：建立 fresh provisioning 的权威空状态

计划修改：

- `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Node/Node+Messages.swift`
  - 增加一个职责单一、幂等的 fresh-provisioning Scheduler 状态初始化接口；
  - 为 `schedulerSetupModels` 的每个 Model建立空 Entry 字典；
  - 重建兼容 `schedulerActions/scheduleIds`；
  - 清除只属于历史坏缓存的 preserved blob/decode error；
  - 保存 Node 属性。

- `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Manager/MeshFastAddDeviceManager.swift`
  - 在基础配置已经收敛、Composition 已可用、App append-messages 回调尚未执行的唯一边界调用初始化；
  - 确保每个 provisioning operation 只初始化一次；
  - Restore 的 append tasks 随后按旧目标重建状态，失败仍由既有任务结果暴露。

不修改：

- `Schedule.needsDelete` 的 unknown 语义；
- Timed 权威读取和缓存修复策略；
- Scheduler Owner、cleanup Model、Group/Profile 路由规则。

### 5.2 App：增加明确的永久删除提交上下文

计划新增：

- `SunSmart/Common/Data/DevicePermanentDeletionCleanup.swift`
  - 在发 Reset 前只捕获 Node Address、Mesh UUID、Subnetwork ID 和 Node 引用，不改变业务数据；
  - 在 Reset 成功或用户确认 Force Delete 后执行 commit；
  - 一次遍历所有 Schedule，同时移除 `nodeAddresses` 和 `needDeleteNodeAddresses` 中的目标地址；
  - 每个发生变化的 Schedule 只保存一次；
  - 继续调用现有业务扩展清理；
  - 发出必要的 Schedule refresh，但复用现有设备删除的 Cloud dirty/上传链，不新增用户文案。

此文件需要加入 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 四个 target。

计划修改永久删除入口：

- `SunSmart/Main/Device/Model/DeviceProtocol.swift`
  - 批量正常删除和 Force Delete 共用同一组预捕获 context；
  - 只对成功或确认强制删除的 Node commit。

- `SunSmart/Main/Device/Lights/Controller/DeviceLightsViewController.swift`
  - 多灯删除正常/强制分支改用相同 context commit。

- `SunSmart/Main/Device/Controller/DeviceLightViewController.swift`
  - 单灯详情正常/强制分支改用相同 context commit。

- `SunSmart/Main/Device/Dongle/Controller/DeviceDongleViewController.swift`
  - 统一永久删除生命周期，避免该独立入口绕过 App 扩展清理；Dongle collection schedule 语义保持不变。

不修改现有 `Node.deleteExtension()` 的通用语义，Fast Add replace-node 和 Device Restore 路径继续使用原清理方法，不误删需要迁移的 Schedule 目标。

### 5.3 Scene capability guard 的独立小修正

计划修改：

- `SunSmart/Common/Data/Node+SyncData.swift`
  - `getNodeNeedDeleteSceneDatas` 使用 `sceneSetupModel` 作为能力门槛；
  - 不引入 fresh Node 的 Scene orphan 扫描；
  - 不改变新设备加入 Group 后 Scene Store/Sync 的正确行为。

该项建议包含在同一实施批次，但作为独立测试和独立审查点；若只批准本次 Timed 根因修复，也可以暂不修改此项。

## 6. TDD 与验证计划

### 6.1 先建立失败用例

新增聚焦测试需要覆盖：

1. fresh Node 有 1 个 Scheduler Model、0 个 Timed：无需删除；
2. fresh Node 有 1～多个 Scheduler Model、1 个非目标 Timed：初始化前能复现 unknown delete，初始化后不删除；
3. fresh Node、16 个 Device/Group/Scene Target 混合 Timed：只添加到 Space 后 0 个 delete task；
4. fresh Node 直接加入目标 Group：只生成该 Group/Scene/Timed 的正向同步任务；
5. Direct Device Timed 删除其中一个 Node：只移除该地址，其他 Direct Device 地址和全局 Schedule 定义保留；
6. 被删地址同时处于 active 和 pending 数组：两个数组都清理；
7. Reset 失败且用户取消 Force Delete：Schedule 地址保持不变；
8. Force Delete 确认：本地 Schedule 地址清理；硬件状态不宣称已重置；
9. existing/imported Node 的 Model 状态 unknown：仍需权威读取或 delete retry，不能被 fresh 初始化逻辑误处理；
10. Restore：known-empty 初始化发生在 restore append tasks 之前，成功任务重建正确 Owner，失败任务保持可见；
11. Scene-only Node：有 `sceneSetupModel`、没有 Scheduler Model 时，真实 waitDelete Scene 仍生成删除任务；
12. fresh ungrouped Node：不会凭空生成 Scene Delete；加入含 Scene 的 Group 后生成 Scene Sync。

### 6.2 聚焦静态与契约验证

计划新增 Device lifecycle 聚焦脚本，并继续运行：

- `scripts/check_timed_scheduler_single_owner.sh`；
- `scripts/check_timed_scheduler_persistence.sh`；
- `scripts/check_fast_add_task_checkpoint_tracker.sh`；
- Scene lifecycle/capability guard 聚焦测试；
- App 与 SDK 两个仓库的 `git diff --check`。

当前修改前基线已验证：

- Timed Scheduler Owner Policy：通过；
- Timed Scheduler Single Owner Contract：通过；
- Scheduler Model Cache Persistence：通过；
- Scheduler Model Read Completion：通过；
- Fast Add Task Checkpoint Tracker：通过；
- App 与 SDK `git diff --check`：通过。

这些基线证明现有单 Owner、unknown Retry、持久化和 Fast Add checkpoint 契约当前未破坏，但现有测试尚未覆盖 fresh-provisioning known-empty 生命周期。

### 6.3 四品牌 iPhoneOS 构建

完成代码后按项目要求直接使用 `xcodebuild`，不使用 shell 包装、不重定向日志、不使用 Simulator，分别验证：

- SunSmart；
- Archipelago；
- SLG Sync Plus；
- SylSmart。

因为 App Common 文件和本地 NordicSigMeshSDK 被多个 target 共享，四个 target 都属于必要验证范围。

### 6.4 真机验证矩阵

至少覆盖以下维度：

| 维度 | 用例 |
| --- | --- |
| 删除方式 | 正常 Reset；Reset 失败后 Force Delete；Force Delete 后设备真正恢复为未配网再重新添加 |
| 添加方式 | Classic；Professional |
| 添加目标 | 只添加到 Space；直接添加到 Manual Group；直接添加到 Automatic Profile Group |
| Timed 数量 | 0；1；16 |
| Timed Target | Direct Device；Group；Scene；混合 |
| Action | Turn On；Turn Off；Scene Recall；Disabled |
| Scheduler Owner | ordinary；Light LC；多 Model cleanup |
| 生命周期 | 当前页面；返回 Lights；进入 Timed；退出重进 Space；杀进程重启 |
| Scene | 无 Scene；Group Scene；Scene waitDelete；Scene-only capability Node（如有设备） |

关键验收条件：

1. 永久删除成功后，App Schedule 中不再保存被删 Node 的 active/pending Direct Device 地址；
2. Group/Scene Target 的全局 Timed 和 Scene 定义不因删除一个设备而消失；
3. 重新只添加到 Space 后，Add 页面成功，Lights 页不显示由 Timed/Scene 产生的同步提示；
4. 新 Node 每个 Scheduler Setup Model 都是 known empty，而不是 unknown；
5. 不向 fresh ungrouped Node 发送 0～15 的 Scheduler delete；
6. 直接加入 Group 时，只同步实际目标 Scene/Timed；成功后每个 Scheduler index 只有一个有效 Owner Entry；
7. Restore、旧缓存迁移、权威读取失败仍能显示真实 Need Sync，不被 known-empty 初始化掩盖；
8. Force Delete 只代表本地删除；只有设备重新以 unprovisioned 状态完成 provisioning 后，才使用 fresh known-empty 事实。

建议日志增加或保留以下可核对信息：

- permanent deletion context 的地址和被修改 Schedule id；
- fresh Scheduler state 初始化时的 Node 和 Scheduler Model Element 地址；
- `[schedule-sync] reason=`；
- `[node-scheduler-model]`；
- Add append task 中实际生成的 Scene/Schedule set/delete 数量；
- Scheduler Register/Action 和 Scene Register 的真机读取结果。

不能只用以下结果宣称业务闭环：

- Add 页面显示 Success；
- Mesh ACK/Status 成功；
- Lights 提示暂时消失；
- 聚焦脚本或 generic iPhoneOS build 通过。

## 7. 方案边界

本方案明确不做：

- 不删除仍被其他 Device/Group/Scene 使用的全局 Schedule；
- 不自动删除因为唯一 Direct Device 被删而变成空目标的 Schedule 对象，保持与 Group 删除现有语义一致；如果产品希望自动删除空 Schedule，需要单独确认；
- 不放宽 unknown Scheduler Model 的 Retry 规则；
- 不改变 Scheduler Owner、Time Set、Group exit migration 或 Scene Store 协议；
- 不新增本地化文案、资源、Auth、依赖；
- 不顺手重构 Device Add、Delete 或 Sync Devices 大文件；
- 未经明确授权不执行 Git commit、push 或 merge。

## 8. 待确认项与推荐审批范围

推荐批准“方案 A + Scene capability guard 小修正”，原因是：

- 方案 A直接修复本次 Timed 根因和永久删除地址缺口；
- Scene 当前没有同型残留问题，但 capability guard 是本次审计发现的明确独立错误；
- 两者可以用独立测试和审查点隔离，不需要扩大到 Scene/Timed 架构重构。

若确认后实施，默认按 AGENTS.md 的 Inline Execution 在当前会话执行，不使用 subagents；先补失败测试，再修改 SDK/App，随后完成聚焦测试、四品牌 iPhoneOS 构建，并把真机验收边界单独列出。
