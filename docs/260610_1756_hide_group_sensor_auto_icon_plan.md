# Hide Group Sensor Auto State Icon Plan

## 背景

在 daylight harvesting (closed loop) 的 group profile 中，进入 group 详情页后，传感器区域会根据旧状态链路显示 `group_auto` 状态小图标。该图标用于表达当前光照控制处于 AUTO 状态。

现已确认：当前固件未实现这套状态展示所依赖的功能，因此 App 继续展示该图标会给用户错误反馈。后续可能通过新协议重新实现 AUTO 状态展示，所以本次不做删除式改造。

## 当前代码判断

涉及代码集中在：

- `SunSmart/Main/Group/View/GroupSensorView.swift`
  - `controlStateImageView` 使用 `group_auto` 图片。
  - 当前会根据 `sensor.lightControlOn` 控制显示与隐藏。
- `SunSmart/Main/Group/Controller/GroupViewController.swift`
  - `refreshAutoState()` 会发送 `LightLCLightOnOffGet()`。
  - 收到 `LightLCLightOnOffStatus` 后写入 `sensorNode.lightControlOn`。
  - `updataSensorAutoStateUI()` 会根据 `lightControlOn` 更新传感器区域状态图标。

右下角 `autoBtn` 是主动控制入口，会向 group 地址下发 `LightLCLightOnOffSetUnacknowledged(true)`，用于让 group 内设备进入 AUTO 状态。本次不能隐藏或禁用它。

## 目标

- 在 group 详情页传感器区域，永远不展示 `group_auto` 状态小图标。
- 无论当前设备状态是 AUTO 还是非 AUTO，都不展示该状态图标。
- 保留右下角 `autoBtn`，不改变其可见性和点击行为。
- 保留旧状态刷新链路，避免影响后续新协议接入时的恢复入口。

## 非目标

- 不删除 `group_auto` 资源。
- 不删除 `refreshAutoState()`、`LightLCLightOnOffStatus` 处理或 `Node.lightControlOn` 扩展。
- 不改变 group 右下角 `autoBtn` 的命令发送。
- 不改变 group 列表双击菜单里的 `AUTO` 快捷操作。
- 不调整 daylight calibration、profile save 或 group sync 逻辑。

## 推荐方案

采用 UI 层隐藏方案：

1. 在 `GroupSensorView` 内，让 `controlStateImageView` 初始化后默认隐藏。
2. 在传感器刷新逻辑中，不再因为 `sensor.lightControlOn == true` 展示 `controlStateImageView`。
3. 在 `GroupViewController.updataSensorAutoStateUI()` 中，继续把 `controlStateImageView` 强制隐藏。

该方案改动最小，只屏蔽错误的用户反馈，不破坏后续恢复状态展示的代码入口。

## 备选方案

### 方案 A：只在 `GroupSensorView` UI 层强制隐藏

优点：

- 改动最小。
- 风险最低。
- 保留全部旧状态链路，便于后续新协议恢复。

缺点：

- 旧状态字段仍会更新，只是不展示。

### 方案 B：停止 `refreshAutoState()` 状态刷新

优点：

- 减少当前固件不支持状态查询时的无效通信。

缺点：

- 影响范围更大。
- 后续新协议或旧逻辑恢复时需要重新梳理调用链。
- 可能改变现有日志和刷新行为，不符合本次“只隐藏图标”的范围。

### 方案 C：删除旧状态展示链路

优点：

- 当前无效功能清理彻底。

缺点：

- 与“后续可能用新协议实现，不考虑当前全部删除”的约束冲突。
- 改动范围过大，恢复成本高。

## 开发计划

1. 修改 `GroupSensorView`：
   - 初始化 `controlStateImageView` 后设置隐藏。
   - 在 ambient light 传感器刷新分支中，保持 `controlStateImageView` 隐藏，不再基于 `sensor.lightControlOn` 显示。

2. 修改 `GroupViewController`：
   - 在 `updataSensorAutoStateUI()` 中强制隐藏 `sensorView?.controlStateImageView`。
   - 不修改 `autoBtnAction(sender:)` 和右下角 `autoBtn` 布局。

3. 验证：
   - 进入 daylight harvesting (closed loop) group，传感器区域不显示 `group_auto` 状态小图标。
   - 收到 AUTO 或非 AUTO 状态后，传感器区域仍不显示 `group_auto` 状态小图标。
   - 右下角 `autoBtn` 仍显示并保持原有点击行为。
   - 运行 iPhoneOS 构建：
     `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

## 风险与回滚

- 风险：旧状态链路仍保留，代码阅读者可能误以为状态仍会展示。
- 缓解：改动点集中在 UI 显示层，并在计划中明确本次是临时隐藏，不删除旧链路。
- 回滚：恢复 `GroupSensorView` 中基于 `sensor.lightControlOn` 的显示逻辑，并恢复 `updataSensorAutoStateUI()` 的原判断。
