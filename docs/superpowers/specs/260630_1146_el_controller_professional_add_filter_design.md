# EL Controller Professional Add Mode 展示过滤设计

## 背景

Professional Add Mode 包含四个分类：

- Add based on manual
- Add based on motion sensing
- Add based on light sensing
- Add based on RSSI range

`CID 0x0A78 / PID 0x24C1` 的 EL Controller 在 `devices_config.json` 中配置为 `deviceCategory: Lighting`，因此当前会被 Professional mode 中按 `.light` 展示的逻辑带入 motion sensing 和 light sensing 分类。

该设备已通过 `Node.isEmergencySignController(companyIdentifier:productIdentifier:)` 精确识别为 `isEmergencySignController = true`。业务约束是：这类设备没有传感器功能，仅能展示在 Add based on RSSI range 中，不应展示在 manual、motion sensing、light sensing 分类中。

## 目标

- `isEmergencySignController = true` 的设备只在 Add based on RSSI range 中展示。
- Add based on manual 不展示这类设备。
- Add based on motion sensing 不展示这类设备。
- Add based on light sensing 不展示这类设备。
- 不改变普通 light / sensor 设备在 motion sensing 和 light sensing 中的现有展示规则。
- 不改变 EL Controller 已有的设备身份、Lights 页面归属、详情页特例和 EMSign 相关逻辑。

## 非目标

- 不修改 `devices_config.json` 中 `0x0A78 / 0x24C1` 的 `deviceCategory: Lighting`。
- 不修改 `Node.isEmergencySignController` 的判定范围或语义。
- 不调整 RSSI range 的自动预选、信号范围滑条、扫描逻辑或添加流程。
- 不新增或修改本地化文案。
- 不重构 Professional Add Mode 页面结构。

## 推荐方案

在 `DeviceAddProfessionalModeController` 的当前模式展示判断中收口：

- `addMode == .rssiRange` 时，允许展示 `isEmergencySignController = true` 的设备。
- `addMode == .manual`、`.motionSensing`、`.lightSening` 时，过滤 `isEmergencySignController = true` 的设备。
- motion sensing 和 light sensing 继续保留现有的 `.light || .sensor` 过滤条件。

优先复用现有入口 `isVisibleDeviceInCurrentAddMode(_:)`，因为它已经被以下路径使用：

- `setupDevicesData()` 的扫描列表分区生成。
- `displayedCandidateDevices` 的 candidate 面板展示。
- candidate count 的显示。
- candidate 撤销后的回流判断。
- 扫描设备自动进入 candidate 前的可见性判断。

## 数据流

扫描设备进入 `MeshAPI.startScanDevice` 回调后，App 会根据 `supportDeviceInfos` 写入 `device.deviceType`。EL Controller 因 `deviceCategory: Lighting` 被映射为 `.light`。

修复后，Professional mode 的展示判断会先看当前 add mode，再看 `device.isEmergencySignController`：

- RSSI range：保持可见，可被正常选择和添加。
- 其他三个模式：不可见，不进入列表分区，也不展示在 candidate 面板计数中。

底层 `scanDevices` 和 `candidateDevices` 缓存不需要强制删除该设备。这样切换回 RSSI range 后仍可显示设备，避免改变添加状态和扫描缓存行为。

## 风险与边界

- 如果未来新增更多 `isEmergencySignController` PID，本规则会自动适用，因为业务语义是这类设备无传感器功能，只能 RSSI range 添加。
- 如果将来出现带传感器能力的 emergency sign controller，应先拆出更窄的 capability predicate，而不是弱化本规则。
- 因为不改 `devices_config.json`，已存在的 Lights 页面和 EL Controller 详情页行为不会被本次修复影响。

## 验证方案

代码验证：

- 检查 `isVisibleDeviceInCurrentAddMode(_:)` 是否覆盖 manual、motion sensing、light sensing、RSSI range 四个分支。
- 检查调用路径仍统一经过该 helper，避免 scan list、candidate view、count 三者不一致。
- 运行 `git diff --check`。

构建验证：

- 运行 iPhoneOS 构建：

`xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

手工验证：

- Professional mode 切到 Add based on RSSI range，`CID 0x0A78 / PID 0x24C1` 可展示。
- Professional mode 切到 Add based on manual，该设备不展示。
- Professional mode 切到 Add based on motion sensing，该设备不展示。
- Professional mode 切到 Add based on light sensing，该设备不展示。
- 普通 light / sensor 设备在 motion sensing 和 light sensing 的展示行为保持不变。
