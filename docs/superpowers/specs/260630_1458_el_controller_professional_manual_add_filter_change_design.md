# EL Controller Professional Manual Add 展示变更设计

## 背景

Professional Add Mode 包含四个分类：

- Add based on manual
- Add based on motion sensing
- Add based on light sensing
- Add based on RSSI range

前一版设计将 `isEmergencySignController = true` 的设备限制为只在 Add based on RSSI range 中展示。现在需求变更为：这类设备需要展示在 Add based on manual 和 Add based on RSSI range 中，不展示在 motion sensing 和 light sensing 中。

当前代码中，`DeviceAddProfessionalModeController.isVisibleDeviceInCurrentAddMode(_:)` 已经是 Professional mode 展示过滤的统一入口。它当前对 `.manual` 返回 `!isEmergencySignController`，因此不满足新需求。

## 目标

- `isEmergencySignController = true` 的设备在 Add based on manual 中展示。
- `isEmergencySignController = true` 的设备在 Add based on RSSI range 中展示。
- `isEmergencySignController = true` 的设备不在 Add based on motion sensing 中展示。
- `isEmergencySignController = true` 的设备不在 Add based on light sensing 中展示。
- 普通 light / sensor 设备在 motion sensing 和 light sensing 中的现有展示规则保持不变。

## 非目标

- 不修改 `devices_config.json`。
- 不修改 `Node.isEmergencySignController` 的判定语义。
- 不改变 motion sensing / light sensing 的触发逻辑。
- 不改变 RSSI range 的自动预选逻辑。
- 不新增或修改本地化文案。
- 不重构 Professional Add Mode 页面结构。

## 推荐方案

继续复用 `DeviceAddProfessionalModeController.isVisibleDeviceInCurrentAddMode(_:)` 作为唯一展示真值层，仅调整 `.manual` 分支：

- `.manual`：返回 `true`，允许 `isEmergencySignController = true` 设备按 manual 模式展示。
- `.rssiRange`：保持返回 `true`，继续展示该设备。
- `.motionSensing` / `.lightSening`：继续过滤 `isEmergencySignController = true`，并保持普通 `.light || .sensor` 条件。

该 helper 已覆盖以下路径，因此无需在 view 层或 candidate view 内重复判断：

- 扫描列表分区生成。
- candidate 面板展示和计数。
- 扫描自动加入 candidate 前的可见性检查。
- candidate 撤销后的回流判断。

## 数据流

扫描到设备后，App 仍根据 `devices_config.json` 将 `0x0A78 / 0x24C1` 映射为 `.light`，并通过 `Node.isEmergencySignController(companyIdentifier:productIdentifier:)` 识别为 EL Controller。

修复后：

- manual：设备可见，但不会因为 manual 模式自动加入 candidate。
- RSSI range：设备可见，并保持原有 RSSI range 自动预选行为。
- motion sensing / light sensing：设备不可见，也不会进入 candidate 面板展示计数。

## 风险与边界

- 这次变更只放开 manual 展示，不恢复 motion/light 展示，避免把没有传感器功能的 EL Controller 当成 sensor-flow 设备。
- 因为不改设备配置和 shared predicate，EL Controller 在 Lights、详情页、EMSign 特例中的既有行为不受影响。
- 如果未来出现具备传感器能力的 emergency sign controller，应新增更窄的 capability predicate，而不是直接放宽 motion/light 分类。

## 验证方案

代码验证：

- 检查 `isVisibleDeviceInCurrentAddMode(_:)` 的 `.manual` 与 `.rssiRange` 分支均允许展示。
- 检查 `.motionSensing` / `.lightSening` 分支仍过滤 `isEmergencySignController = true`。
- 运行 `git diff --check`。

构建验证：

- 运行 iPhoneOS 构建：

`xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

手工验证：

- Professional mode 切到 Add based on manual，`CID 0x0A78 / PID 0x24C1` 可展示。
- Professional mode 切到 Add based on RSSI range，`CID 0x0A78 / PID 0x24C1` 可展示。
- Professional mode 切到 Add based on motion sensing，该设备不展示。
- Professional mode 切到 Add based on light sensing，该设备不展示。
- 普通 light / sensor 设备在 motion sensing 和 light sensing 的展示行为保持不变。
