# Profile Power Up CCT Range 设计

## 背景

在 `Site - Space - Group - Profile UI` 页面中，`Power up behavior` 选择 `Defined light level` 时可以配置上电默认亮度和目标色温。组内设备的 `Absolute CCT Range` 可以通过 `Site - Space - More - Device Parameter Settings` 单独修改，例如某些设备最大色温从 `6500K` 改为 `5000K`。

用户期望 `Profile.powerUpCct` 保持组级统一配置语义。例如 Profile 仍可保存 `6500K`，但同步到不同设备时应按设备自身有效 CCT 范围转换实际目标值。

## 问题真实性

当前代码中，Profile 的发送层已经有部分保护：`ProfileType.getMessageHandles(node:)` 在发送 `LightCTLDefaultSet` 时使用 `node.clampEffectiveCct(defaultCct)`，因此这份代码不一定会直接把 `6500K` 发送给最大 `5000K` 的设备。

但问题仍然真实存在于同步目标和成功判定层：

- `Node+SyncData.swift` 生成 `.powerOnState` 同步项时，仍把组级 `groupProfile.powerUpCct` 原值放入同步类型。
- `SyncDevicesCellModel.swift` 判断 `.powerOnState` 是否成功时，直接比较 `cct == node.defaultCct`。
- `EmerFireAlarmSyncCellModel.swift` 也有同样的直接比较逻辑。

因此，如果组级 Profile 保存 `6500K`，某台设备有效范围上限为 `5000K`，发送层可能实际写入 `5000K`，但 UI 成功判定仍拿 `6500K` 与设备缓存的 `5000K` 比较，导致 Profile 或 Sync device(s) 持续显示失败或需要同步。

这与场景保存曾遇到的问题一致：组级场景 CCT 需要在应用到具体设备时转换为设备目标值，不能用组级原始 CCT 直接比较设备缓存值。

## 目标

- `Profile.powerUpCct` 继续保存组级统一值，不因为某台设备范围较窄而被改写。
- Profile 同步到设备时，CCT 目标值按设备 `effectiveCctRange` 夹紧。
- 不支持有效 CCT 的设备不参与 Power Up CCT 同步和比较，只同步上电状态与默认亮度。
- 同步任务生成、消息发送、成功判定使用一致的设备目标值。
- 修复范围聚焦在 Profile Power Up CCT，不改变场景、Group 控制、Device Parameter Settings 的既有 UI 策略。

## 非目标

- 不把组级 `Profile.powerUpCct` 改成所有设备 CCT range 的交集。
- 不改变 `Power up behavior` 页面当前基于组有效 CCT 范围展示滑块的策略。
- 不修改设备的 `Absolute CCT Range` 配置规则。
- 不重构 Profile、SyncDevices 或 Fire Alarm 同步模型的整体结构。

## 参考实现模式

场景同步已有类似的正确模式：

- `SceneExecuteData.deviceTarget(for:)` 按设备能力计算目标值。
- 支持 CCT 的设备使用 `node.clampEffectiveCct(cct)`。
- 不支持 CCT 的设备跳过 CCT 比较。
- `SceneExecuteData.isSynced(with:for:)` 按设备目标值判断同步成功。

Profile Power Up 应采用同样思路，为组级 Profile 配置派生出每台设备的实际目标值。

## 推荐方案

增加一个小型 helper 表达 Profile Power Up 的设备目标 CCT 语义，并让同步生成和成功判定共用它。

建议行为：

- 输入组级 `powerUpCct` 和目标 `node`。
- 如果 `node.effectiveSupportCct == true`，返回 `node.clampEffectiveCct(powerUpCct)`。
- 如果 `node.effectiveSupportCct == false`，返回 `nil`。
- 对 `Defined light level`：
  - 默认亮度继续按 `Node.getLightness(lightness100:)` 计算。
  - CCT 只在 helper 返回非 nil 时参与同步项和比较。

## 数据流

1. 用户在 Profile UI 中保存 `Defined light level`，例如 `powerUpCct = 6500K`。
2. `Profile.powerUpCct` 保持 `6500K` 并保存到组 Profile。
3. 生成某台设备的同步任务时，按该设备计算目标 CCT：
   - 设备 A range `2700K...6500K`，目标 CCT 为 `6500K`。
   - 设备 B range `2700K...5000K`，目标 CCT 为 `5000K`。
   - 设备 C 不支持有效 CCT，目标 CCT 为 `nil`。
4. 发送消息时继续使用设备目标值；如果发送层仍保留 `node.clampEffectiveCct`，它作为最后防线。
5. 同步成功判定比较设备缓存值与设备目标值，而不是组级原始 CCT。

## 受影响位置

- `SunSmart/Common/Data/Node+SyncData.swift`
  - 生成 `.powerOnState` 同步项时使用设备目标 CCT。
  - 判断是否需要设置 CCT 时，比较设备目标 CCT 与 `node.defaultCct`。

- `SunSmart/Common/Data/Node+MessageHandles.swift`
  - 保留发送层 clamp。
  - 如同步项已传入设备目标值，发送层 clamp 仍可作为防御性保护。

- `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift`
  - `.powerOnState` 成功判定改为按设备目标 CCT 比较。

- `SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmerFireAlarmSyncCellModel.swift`
  - 同步成功判定保持与普通 Sync device(s) 一致。

## 错误处理

- 如果设备不支持有效 CCT，不应因为组级 Profile 有 CCT 值而判定失败。
- 如果设备有 CTL Setup model 但 `effectiveSupportCct == false`，应退化为只设置默认亮度。
- 如果设备缓存的 `defaultCct` 为空或未读取到，应维持现有缓存语义，不引入新的读取流程。

## 测试计划

优先增加或调整聚焦测试，覆盖以下场景：

1. 组级 Profile `powerUpCct = 6500K`，设备有效 CCT range 为 `2700K...5000K`：
   - 同步目标 CCT 应为 `5000K`。
   - 当 `node.defaultCct == 5000K` 时成功判定为 true。

2. 组级 Profile `powerUpCct = 6500K`，设备有效 CCT range 为 `2700K...6500K`：
   - 同步目标 CCT 应为 `6500K`。
   - 当 `node.defaultCct == 6500K` 时成功判定为 true。

3. 设备不支持有效 CCT：
   - 同步项不应要求 CCT。
   - 成功判定只比较 `powerUpState` 与默认亮度。

4. 现有场景同步测试或行为不变：
   - 场景仍按 `SceneExecuteData.deviceTarget(for:)` 处理 CCT。

## 验证

实现后至少运行：

- `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

如有针对 Sync/Profile 的单元测试 target，应同时运行相关测试。
