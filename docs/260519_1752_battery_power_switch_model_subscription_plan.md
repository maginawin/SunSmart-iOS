# Battery Power Switch Model Subscription Analysis And Fix Plan

## 背景

Battery Power Switch 在 SAVE 时会为 target groups 中的设备订阅 BPS 的虚拟组地址。当前测试发现：按键 5/6 执行亮度增加/减少时，部分支持 CCT 的灯具会同时改变色温。

本问题只针对 BPS 的 target group model subscription。BPS 面板本身不支持 CCT 功能，button 5/6 的 `LEVEL_DELTA` / `LEVEL_MOVE` 只能表达亮度调节。

## 当前实现

现有实现位于：

- `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`
- `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift`
- `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`

当前 `Node.batteryPowerSwitchTargetCapabilityModelIdentifiers` 包含：

- Generic OnOff Server
- Generic Level Server
- Scene Server
- Light Lightness Server
- Light LC Server

`batteryPowerSwitchTargetCapabilityModels` 会遍历 target node 的所有 element，并按上述 model id 收集所有匹配 model。因此只要某个 element 上存在 Generic Level Server，就会订阅 BPS 虚拟组。

## 根因

根因不是 BPS button config 的 `LEVEL_DELTA` / `LEVEL_MOVE` 值错误，而是 target 设备侧 Generic Level Server 的订阅范围过宽。

在 BLE Mesh 中，Generic Level Server 不只用于亮度：

- Light Lightness Server 关联的 Generic Level Server 表示 brightness level。
- Light CTL Temperature Server 关联的 Generic Level Server 表示 color temperature level。
- HSL Hue / Saturation 等功能也可能复用 Generic Level Server 语义。

SDK 已经有这个语义区分：

- `Node.levelModel`：优先取 `lightnessModel.parentElement` 上的 Generic Level Server，用作亮度 level。
- `Node.ctlTemperatureLevelModel`：取 `temperatureModel.parentElement` 上的 Generic Level Server，用作色温 level。
- Kinetic Switch 的订阅实现也按 action 区分：`dimUp/dimDown` 订阅 `levelModel`，`cctUp/cctDown` 订阅 `ctlTemperatureLevelModel`。

BPS 当前实现没有做这个语义区分，而是订阅所有 Generic Level Server。对于 CTL 灯，BPS 虚拟组同时被亮度 level model 和色温 level model 订阅；当 BPS button 5/6 发出 Generic Level Delta/Move 消息时，两个 model 都会响应，所以亮度和色温一起变化。

## 修复目标

1. BPS button 5/6 只影响亮度，不影响 CCT。
2. BPS 仍支持现有功能：On/Off、Scene Recall、absolute Lightness Set、Light LC AUTO。
3. 已经被旧版本错误订阅到 BPS 虚拟组的 CCT level model，需要在下一次 SAVE/重同步时清理。
4. 不改变 Kinetic Switch 的 CCT 能力；本次修复只作用于 BPS。
5. 不修改 BPS button config 协议；仍使用 `LEVEL_DELTA` / `LEVEL_MOVE`，因为固件当前就是通过 Generic Level 消息实现 step/move。

## 可选方案

### 方案 A：BPS 专属语义化订阅，推荐

将 BPS target capability 从“按 model id 遍历所有 element”改成“按 BPS 功能语义选 model”：

- On/Off：`node.onoffModel`
- Brightness step/move：只取 Light Lightness 所在 element 上的 Generic Level Server
- Scene：`node.sceneModel`
- Absolute brightness：`node.lightnessModel`
- AUTO：`node.lightLCModel`

新增 BPS 专属 cleanup models：

- 删除所有不是 brightness level model 的 Generic Level Server 对 BPS 虚拟组的订阅。
- removed target groups 的 unsubscription 仍删除所有 BPS 相关 model 订阅，包含旧版本可能留下的所有 Generic Level Server。

优点：

- 精确表达 BPS 不支持 CCT 的产品约束。
- 保留 Generic Level step/move 的现有协议，不需要固件改动。
- 能修复已经保存过的错误订阅。
- 不影响 Kinetic Switch。

缺点：

- target subscription helper 需要从单纯 id 列表改成 BPS 专属 model 选择逻辑。

### 方案 B：直接从 capability list 移除 Generic Level Server

只订阅 OnOff、Scene、Light Lightness、Light LC，不再订阅 Generic Level Server。

优点：

- 改动小。
- 不会再触发 CCT level。

缺点：

- BPS button 5/6 发出的 Generic Level Delta/Move 可能没有目标 model 响应，step/move 调光功能会失效或依赖不明确的模型扩展行为。
- 不能稳定满足“按键 5/6 增加/减少亮度”的需求。

### 方案 C：让固件增加 brightness-only delta/move 类型

新增类似 Lightness Delta/Move 的私有动作类型，让 BPS 直接发送 Light Lightness 语义的调光命令。

优点：

- 从协议层彻底避免 Generic Level 多语义问题。

缺点：

- 需要固件协议更新，不适合当前 App 侧修复。
- 仍需要兼容已出货或当前协议版本。

## 推荐方案

采用方案 A。

关键设计是把 “capability models” 重新定义为 BPS 功能语义下的 server models，而不是 raw model id 扫描结果。Generic Level Server 仍然是 capability 的一部分，但只允许选择亮度语义的 level model。

建议新增两个 helper：

- `batteryPowerSwitchDesiredTargetModels`：返回 BPS 当前应该订阅的 target models。
- `batteryPowerSwitchObsoleteTargetModels`：返回已知旧实现可能错误订阅、但当前 BPS 不应该保留的 models，主要是非亮度语义的 Generic Level Server。

## 实施计划

### 任务 1：重写 BPS target model 选择

修改 `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`。

将当前 `batteryPowerSwitchTargetCapabilityModelIdentifiers` / `batteryPowerSwitchTargetCapabilityModels` 替换或收敛为 BPS 专属语义选择：

- `onoffModel`
- `sceneModel`
- `lightnessModel`
- `lightLCModel`
- `batteryPowerSwitchBrightnessLevelModel`

`batteryPowerSwitchBrightnessLevelModel` 应只从 `lightnessModel.parentElement` 获取 Generic Level Server；不要 fallback 到 `levelModels.first`，避免 CCT-only 或非亮度 Generic Level 被误订阅。

### 任务 2：增加旧错误订阅清理

在同一文件中增加 obsolete model helper：

- 遍历 `levelModels`
- 排除 `batteryPowerSwitchBrightnessLevelModel`
- 返回仍订阅 BPS 虚拟组、但当前 BPS 不应使用的 Generic Level Server

在 `getBatteryPowerSwitchSubscriptionMessageHandles` 中，生成顺序建议为：

1. 删除 obsolete Generic Level subscriptions。
2. 添加 desired target subscriptions。

这样用户对同一个 target group 再 SAVE 或在详情页 retry sync 时，不需要先移除 group，也能清理旧的 CCT level 订阅。

### 任务 3：removed group 清理保持向后兼容

`getBatteryPowerSwitchUnsubscriptionMessageHandles` 不应只按新的 desired target models 删除，否则旧版本已经订阅的 CCT level model 会残留。

removed group 的 unsubscription 应删除：

- 当前 desired target models
- obsolete Generic Level models
- 旧实现中可能订阅过的所有 Generic Level Server

这只发生在 BPS removed target group 的同步流程中，不影响普通 group 订阅。

### 任务 4：同步页无需改变整体顺序

保留现有 SAVE 同步顺序：

1. Reset BPS config
2. Configure BPS buttons
3. Subscribe target groups
4. Unsubscribe removed groups

只调整每个 target device 在 “Subscribe target groups” task 里生成的 message handles：先 cleanup obsolete，再 add desired。

### 任务 5：验证

静态验证：

- `rg` 检查 BPS target subscription 不再遍历所有 Generic Level Server。
- `rg` 检查 BPS button 5/6 仍使用 `LEVEL_DELTA` / `LEVEL_MOVE`。
- `rg` 检查 Kinetic Switch 的 `dimUp/dimDown` 与 `cctUp/cctDown` 逻辑未被修改。

构建验证：

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

手动验证：

1. 选择一个包含 CTL 灯的 target group。
2. 保存 BPS 配置并完成同步。
3. 检查同步 message handles 中：
   - Lightness element 的 Generic Level Server 订阅 BPS 虚拟组。
   - CTL Temperature element 的 Generic Level Server 不订阅 BPS 虚拟组，若旧版本已订阅则被删除。
4. 按 button 5/6 短按和长按：
   - 亮度变化。
   - 色温保持不变。
5. 验证 button 0...3 absolute Lightness、button 6 ON/AUTO、button 7 OFF 不回归。

## 风险与注意事项

- 如果某类灯只有 Generic Level Server、没有 Light Lightness Server，本方案不会把它当成 BPS 亮度目标。这个取舍符合 App 现有 `supportLightness` 对 Light Lightness Server 的判断，也避免误控 CCT。
- 已经错误订阅过的设备必须依赖下一次 SAVE/重同步清理；只升级 App 但不重同步，不会改变设备端已有订阅状态。
- 不建议修改 SDK 的通用 `levelModel` / `levelModels` 语义，因为 Kinetic Switch 仍有 CCT long press 能力，本问题是 BPS 订阅选择过宽。
