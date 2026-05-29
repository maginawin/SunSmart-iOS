# Light Add Group Deferred Sync 设计

## 背景

在 `Site - Space` 中进入添加设备页面，选择将新设备添加到某个 group 后，扫描并添加 light 设备。当前添加流程会在 provision append 阶段调用 `node.getSyncData(type: .group(group))`，把入组、Profile、Scene、Schedule、Switch target subscription、Proximity Lighting 等组关联配置一次性展开为 Mesh 命令。

这说明现有代码已经有“自动入组后补组配置”的意图，但它与设备修复流程不同。设备修复会把 Profile、Scene、Schedule、Switch 等配置拆成 deferred restore tasks，逐项执行、过滤不适合直接触发的 `SceneRecall`，并按任务结果更新本地缓存和失败状态。普通添加流程则把这些配置混在 append messages 大包里发送；如果组关联配置失败，添加结果仍可能显示成功，且 group/node 的待同步状态不一定可靠保留。

本次目标是让 light 设备成功添加并自动加入 group 后，组相关功能也像设备修复时一样下发给新设备。若后续补发失败，设备添加仍允许成功，但 group 必须进入需要同步状态，用户可通过现有同步入口补齐。

## 已确认范围

只覆盖 light 设备自动加入 group 的添加路径：

- `DeviceAddClassicModeController`
- `DeviceAddProfessionalModeController`

不覆盖：

- 未选择 group 的 light 添加。
- gateway、dongle、switch、Battery Power Switch、Emergency Fire Controller 等非 light 添加。
- 设备修复入口的业务语义变更。
- 历史已添加但未补齐的旧设备批量修复。
- 本地化、资源、target 配置、依赖或 Auth 信息。

## 当前实现结论

当前 light + group 添加分支会执行：

- 默认最大亮度设置。
- `node.getSyncData(type: .group(group))`。
- `LightCTLTemperatureRangeGet`。
- `AttentionSet`。

`getSyncData(type: .group(group))` 会收集：

- `.deviceInitialize`
- `.subscribeGroup`
- `.profile`
- `.syncScenes` / `.deleteScenes`
- `.syncSchedules` / `.deleteSchedules`
- `.syncSwitchProxy` / `.deleteSwitchProxy`
- `.syncSwitchs` / `.deleteSwitchs`
- Proximity Lighting 相关 sync data

问题不在于完全没有生成命令，而在于所有组关联命令被扁平化进 append 阶段，缺少 restore 流程已有的任务边界、状态确认、失败保留和后续补同步语义。

## 方案

采用 deferred group sync 方案。

light 自动入组时，把配置拆成两段：

1. Provision append 阶段只保留必须立即完成的基础配置。
2. Add success 后执行 group deferred sync，逐项补发组关联功能。

### 1. 复用型规划器

新增一个轻量 helper，例如 `DeviceGroupDeferredSyncPlanner`。它负责把 `NodeSyncData` 拆成 immediate 与 deferred 两类，并把 deferred sync data 转成可执行任务。

职责：

- 根据 `node.getSyncData(type: .group(group))` 得到完整同步项。
- 将入组订阅、初始化等基础项归入 immediate。
- 将 Profile、Scene、Schedule、Switch target、Proximity Lighting 等归入 deferred。
- 为 deferred 项生成 `DeviceOperationType` 任务。
- 对任务中的 `SceneRecall` 做过滤，避免添加后触发 profile 场景切换。

这个 helper 不持有 UI 状态，不直接依赖具体添加页控制器。添加页负责调用它并更新当前 UI 状态。

### 2. Provision append 阶段

light + group 添加时，append messages 保留：

- 当前已有的默认最大亮度设置。
- `.deviceInitialize`，如果设备尚未完成 key bind/config。
- `.subscribeGroup(group)`，保证设备成为 group member。
- `LightCTLTemperatureRangeGet`。
- `AttentionSet`。

append 阶段不再直接发送以下组关联功能：

- Profile。
- Scene store/delete。
- Schedule set/delete。
- Switch target subscription/unsubscription。
- Proximity Lighting 参数。
- 其它不属于立即入组所必需的 group sync data。

### 3. Add success 后 deferred group sync

当 light 设备 provision 成功并完成自动入组后，如果存在 deferred sync tasks：

- 按任务顺序逐项发送。
- 使用 `DeviceOperationType.messageHandles` 生成 Mesh message handles。
- successful callback 中保留 restore 已有的场景状态更新语义：SceneStore 前的灯状态响应需要更新到 node 状态。
- finished callback 中逐个调用 `node.updateData(message:isSuccess:)`。
- 每个任务完成后调用 `node.clearSyncStateCache()`。

覆盖的组关联功能包括：

- group Profile 是否在新 light 上生效。
- group 相关 Scene 是否写入新 light。
- group 相关 Schedule 是否写入新 light。
- 以该 group 为控制目标的 Switches、Sensors 是否能控制新 light。
- Proximity Lighting 等其它 group 关联功能是否下发给新 light。

## 失败处理

deferred group sync 失败时，不回滚设备添加，也不从 group 移除设备。

失败语义：

- Provision 成功且入组订阅成功后，设备添加仍算成功。
- 任一 deferred task 失败时，对失败 handle 调用 `node.updateData(message:isSuccess:false)`。
- 调用 `node.clearSyncStateCache()`，让后续 `getNeedSync()` / `getNeedSyncGroup(group:)` 重新计算。
- 调用或复用 `group.updateGroupSyncState()`，让 group 进入需要同步状态。
- 后续进入现有 Sync Devices / group sync 入口时，应能重新生成失败项并补齐。

成功语义：

- 每个成功 task 更新本地缓存。
- 全部 deferred tasks 成功后，group 不应因本次添加残留 need sync。
- 入组订阅成功仍由现有 `ConfigModelSubscriptionAdd` 缓存更新逻辑设置 `node.groupState = .inGroup` 并清理 `restoreData.addGroupAddress`。

## UI 行为

本次不新增复杂 UI。

- 添加页可以继续把 provision 成功的设备显示为添加成功。
- 如果 deferred group sync 失败，优先通过 group 的需要同步状态暴露问题。
- 如果现有添加页已有部分同步失败展示能力，可以复用；没有则不新增新的文案或本地化。

## 数据一致性

规划器应以同一份 `node.getSyncData(type: .group(group))` 为源，避免添加流程和同步流程对“应该补什么”产生分歧。

deferred 执行后必须更新本地缓存，否则后续 group sync 会反复认为同一配置未同步。失败时不能把缓存伪造成成功，否则 group 无法进入待同步状态。

## 影响范围

预计改动集中在：

- `SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift`
- `SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift`
- 新增一个 light group deferred sync helper
- 如需复用 restore 的任务规划能力，可调整 `SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift` 的私有规划逻辑，将其迁移到 helper；restore 行为保持不变

不修改 SDK、本地化、资源、target 配置或依赖。

## 验收标准

手工验证：

1. 添加 light 到带 Profile 的 group，添加完成后 Profile 在新 light 上生效。
2. group 绑定的 Scene 包含新 light，Scene recall 后新 light 响应。
3. group 相关 Schedule 写入新 light。
4. 以该 group 为 target 的 BPS / EnOcean switch / sensor 相关订阅可控制新 light。
5. 人为制造 deferred 失败时，设备仍添加成功，group 显示需要同步。
6. deferred 失败后进入现有同步入口，可以重新生成并补齐失败项。
7. 未选择 group 的 light 添加行为不变。
8. 非 light 添加行为不变。

静态验证：

- light + group 添加不再把 Profile / Scene / Schedule / Switch target 等组关联功能直接混入 append messages 大包。
- immediate 阶段仍包含入组订阅。
- deferred 阶段过滤 `SceneRecall`。
- deferred 失败不会伪造本地同步成功。
- deferred 失败会触发 group 待同步状态。

构建验证：

使用项目要求的命令：

`xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
