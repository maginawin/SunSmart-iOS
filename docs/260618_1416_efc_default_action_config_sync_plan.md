# EFC Default Action Config Sync 分析与修复方案

## 背景

现象：添加 EFC 设备后，如果没有配置 `Associate with group(s)`，EFC 设备的应急状态变化不会在 App 的 EFC 设备页面同步展示，表现为 App 没有监听到 EFC 设备应急状态变化。

预期：即使 EFC 没有关联用户灯组，App 也应能监听并展示 EFC 自身的应急状态变化。

用户建议：添加 EFC 成功后，立即把 EFC 默认配置通过 `0x4D/0x07` 动作配置下发给 EFC 设备，不要等到用户配置 `Associate with group(s)` 并 SAVE 后才下发。

## 代码事实

### 1. 底层同步规划器本身支持无 associated group 的 controller 同步

`EmergencyFireControllerSyncPlanner.makeItems()` 会先确保内部 virtual publish group 存在，然后调用 `DeviceEmerFireData.makeControllerSyncTasks(...)` 生成控制器自身任务，最后才追加 associated group 订阅和 cleanup 任务。

这说明底层 planner 并不要求存在用户可见 group 才能生成 EFC controller 自身配置。

关键文件：

- `SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmergencyFireControllerSyncPlanner.swift`
- `SunSmart/Main/Device/Device1.5/FireAlarm/Model/DeviceEmerFireData+Sync.swift`

### 2. 当前上层触发条件会漏掉默认配置

`DeviceEmerFireData.hasSyncableConfiguration` 只看：

- `configuration.hasSyncIntent`
- `requiresControllerPublicationSync`

而 `configuration.hasSyncIntent` 只在存在 active associated group 或 pending cleanup 时为 true。默认 EFC 配置下两个 associated group 数组都为空，因此 add/bind 成功后的默认 controller 配置任务可能被挡掉。

`LinkedEmerFireEditVC.openSyncAfterLinkedDeviceIfNeeded()` 也用 `device.hasSyncableConfiguration` 作为打开同步页的前置条件。这个方向不适合 add-device 场景：添加设备应保持无感，不能因为单个 EFC 的默认配置打断当前 Add Device 流程。

Classic 和 Professional 添加流程都已有 `MeshAPI.startFastAddDevices(... appendMessagesBack:)`，当前也已经在 EFC 分支里静默追加 Scene Client publication 消息。这个位置更适合承载 EFC 默认 controller 配置，因为它按每个新增节点生成附加消息，能自然处理同时添加多个设备。

### 3. 当前 `0x4D/0x07` 默认 action config 会被置为 invalid

`EmergencyFireControllerConfiguration.actionConfig(...)` 目前要求 `!activeLightLCGroupAddresses.isEmpty`，否则直接返回 `.invalid`。

如果固件需要通过 `0x4D/0x07` 获得 EFC 状态事件的目标地址、App Index、TTL 等配置，那么仅仅静默追加现有 publication 消息还不够；还必须允许无 associated group 时生成指向 EFC 内部 publish group 的默认 action config。

### 4. `app_idx` 保持现状

当前 `0x4D/0x07 app_idx` 不作为本次问题处理范围。本次修复不调整 `app_idx` 的取值逻辑，只收口默认 action config 是否下发、以及 add/bind 成功后是否触发 controller-only 同步。

## 结论

用户建议方向基本正确，但需要补全两个条件才足以解决问题：

1. 添加或绑定真实 EFC 成功后，需要静默追加 controller-only 默认配置任务，不应因为没有 `Associate with group(s)` 被 `hasSyncIntent` 挡掉。
2. 默认 `0x4D/0x07` 不能在无 associated group 时继续生成 `.invalid`；它应至少配置 EFC 内部 publish group，让 EFC 的状态事件能发布到 App/网关监听的内部组。

如果只做“提前调用现有同步页”，不仅会打断批量添加体验，而且在 `actionConfig(...)` 仍因空 associated group 返回 `.invalid` 时，很可能只能补齐 publication/resend/restore delay，不能真正解决状态变化不上报或 App 不刷新的问题。

## 修复方案

### 方案 A：收口为 EFC controller 默认同步能力

推荐采用。

改动点：

1. 拆分同步意图：
   - `hasAssociatedGroupSyncIntent`：只表示 associated group 订阅或 pending cleanup。
   - `hasControllerSyncIntent`：绑定了真实 EFC 节点后，controller publication 和 vendor 默认参数都需要同步。
   - `hasSyncableConfiguration` 改为覆盖 controller 默认配置，而不只看 associated group。

2. 调整 add/bind 成功后的默认配置触发：
   - 不在添加设备后自动进入 EFC 同步页。
   - 在 Classic / Professional Add Device 的 `appendMessagesBack` EFC 分支中，静默追加 EFC controller 默认配置消息。
   - 每个新增 EFC 节点只追加自己的 controller 默认配置消息，跟随当前 fast-add 队列执行，避免批量添加时页面跳转和流程中断。
   - `LinkedEmerFireEditVC.openSyncAfterLinkedDeviceIfNeeded()` 不作为新增设备后的主方案；如果保留，也只作为手动修复或非 add-device 场景的兜底入口。
   - 如果默认配置附加消息全部成功，且该 EFC 没有 associated group / pending cleanup 意图，则可把本地 `isSynced` 标记为 true。
   - 如果默认配置附加消息失败，不改变 Add Device 成功状态，只保留 EFC 本地未同步状态，后续由 repair/sync 处理。

3. 调整 `actionConfig(...)`：
   - 无 associated group 时仍允许生成指向 `publishGroupAddress` 的默认 action config。
   - associated group 为空只表示“不让灯组订阅 EFC group”，不应等同于“EFC 自身没有状态事件 action config”。
   - 如果产品/固件要求无灯组时不控制灯，应由灯端订阅为空保证无灯响应，而不是把 EFC controller action config 置为 invalid。

4. 保持 `0x4D/0x07 app_idx` 现有逻辑：
   - 不修改 `app_idx` 的取值。
   - 不把 `app_idx` 纳入本次问题的风险项或验证项。

5. 保持 associated group 订阅逻辑不变：
   - 有 associated group 时，仍由 `EmergencyFireControllerSyncPlanner.makeAssociatedGroupItems()` 为组内设备补订阅。
   - 无 associated group 时，不生成灯组订阅任务。

## 影响范围

主要影响：

- EFC 添加后绑定真实设备的静默附加配置任务。
- EFC controller 默认 vendor 参数和 Scene publication 初始化。
- `0x4D/0x07` action config 是否在默认配置下下发。

不应影响：

- 普通灯组同步。
- Associated group 的固定 Model 订阅集合。
- EFC 删除 cleanup。
- EFC 设备页主动 `emergencyComprehensiveStatus` GET 逻辑。
- SDK AppKey bind 初始化流程。

## 验证计划

1. 静态检查：
   - 确认 add/bind 成功后无 associated group 不会自动进入 EFC 同步页。
   - 确认 Classic / Professional Add Device 的 EFC `appendMessagesBack` 会静默追加 controller 默认配置消息。
   - 确认静默附加消息来自完整 controller 默认配置，而不是只附加 Scene publication。
   - 确认无 associated group 时 `0x4D/0x07` action config 不再被强制置为 invalid。
   - 确认无 associated group 时不生成灯组 subscription add 任务。
   - 确认本次没有修改 `0x4D/0x07 app_idx` 取值逻辑。

2. Contract 检查：
   - 更新 `scripts/check_efc_controller_flows.sh`，增加无 associated group 默认 sync/action config 防回退检查。

3. 构建验证：
   - 运行 `git diff --check`。
   - 运行 `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`。

4. 手工 BLE 验证：
   - 新增 EFC，不配置 associated group。
   - 添加流程不跳转 EFC 同步页。
   - 添加流程中静默完成 EFC 默认 controller 配置。
   - 触发 Power Loss / Fire Alarm / Restore 状态变化。
   - EFC 设备页应能同步显示对应状态变化。
   - 同时添加多个设备时，EFC 默认配置任务跟随各自设备的 add 流程执行，不阻塞或打断其他设备添加。
   - 再配置 associated group 后 SAVE，确认灯组订阅和灯控行为仍正常。

## 待确认点

1. 无 associated group 时，`0x4D/0x07` 默认 action config 是否应对三种 state 都下发有效 action，目标都指向内部 publish group。
2. 静默附加任务失败时是否仅标记 EFC `isSynced = false` 并允许用户后续手动 repair/sync。建议失败不打断 Add Device 主流程。
