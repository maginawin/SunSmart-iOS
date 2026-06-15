# Tunable White 控制页 OnOff 背景变色逻辑分析

## 结论

当前色温灯控制页顶部展示的 OnOff 区域背景会跟随 Color temp 滑条变色，是一条本地 UI 即时刷新链路，不需要等待设备回包。

核心链路是：

1. Device Parameter Settings 将设备的 Change Control Page 设置为 Tunable White。
2. SDK 中 `Node.singleDeviceDisplaySupportCct` 变为 `true`。
3. `DeviceLightViewController` 因此显示 CCT 信息区域，并把 CCT slider 加入 `DeviceLightControlPanelView`。
4. 用户拖动 Color temp slider 时，slider 的 valueChanged 回调先更新本地 `node.temperature`。
5. 控制页立刻调用 `updateData(refreshControlPanel: false)`。
6. `updateData()` 在灯处于 On 状态时，用 `node.temperature` 计算 CCT 百分比，再用 `Node.getCctMixColor(...)` 给顶部 `lightBgView` 的 `device_light_bg` 图片 tint color。

所以看到的效果是：滑条变化 -> 本地 `node.temperature` 变化 -> 顶部背景图片重新 tint -> 背景颜色实时变化。

## Tunable White 如何影响控制页

相关文件：

- `SunSmart/Main/Device/Parameter/Controller/DeviceParameterSettingsController.swift`
- `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Node/Node+Propertys.swift`
- `SunSmart/Main/Device/Controller/DeviceLightViewController.swift`

Device Parameter Settings 里启用 Change Control Page 并选择 Tunable White 后，会把 `node.changeControlPage` 保存为 `.tunableWhite`，同时保存节点属性并发出 `spaceDataChangedNotificaitonName`。

SDK 里的判断是：

- `rawSupportCct`：设备有 `temperatureModel`。
- `effectiveChangeControlPage`：优先使用本地保存的 `changeControlPage`，没有则用默认值。
- `singleDeviceDisplaySupportCct`：设备原始支持 CCT，并且 `effectiveChangeControlPage != .singleWhite`。

因此当设备原始支持 CCT，且控制页属性是 Tunable White 时，单灯控制页会认为这个设备需要显示色温控制。

## 控制页如何显示 CCT 控件

`DeviceLightViewController.updateUI()` 会根据 `node.singleDeviceDisplaySupportCct` 控制 CCT UI：

- `cctView` 显示或隐藏。
- 如果亮度也支持，会把 brightness 信息区域让出位置给 CCT。
- `controlPanelView` 在设备支持亮度或支持 CCT 时显示。

`DeviceLightViewController.updateControlPanel()` 会把 `showsCCT: node.singleDeviceDisplaySupportCct` 传给 `DeviceLightControlPanelView.Configuration`。

`DeviceLightControlPanelView.rebuildArrangedViews(...)` 根据 `showsCCT` 决定是否加入 CCT slider：

- simple 模式加入 `simpleCCTSlider`。
- detailed 模式加入 `detailedCCTView`。
- 如果开启 CCT quick buttons，并且 `showsCCT == true`，再显示 quick buttons。

## Slider 如何触发顶部背景即时变色

`DeviceLightControlPanelView` 的 CCT slider 回调分成两类：

- `valueChangedCallback`：UI 值变化时触发，用于本地即时刷新。
- `valueThrottleChangedCallback`：节流触发，用于向设备发送色温命令，`ended` 时带 ACK。

在 `DeviceLightViewController.bindSliderAction()` 中：

- `cctValueChanged` 调用 `applyCCTValue(value)`。
- `applyCCTValue(value)` 把值 clamp 到有效 CCT 范围后写入 `node.temperature`。
- 随后调用 `updateData(refreshControlPanel: false)`。

这里的 `refreshControlPanel: false` 很关键：它避免 slider 正在拖动时重新 configure 整个控制面板，但仍然会刷新顶部灯图、亮度文字、CCT 文字和 OnOff 状态。

实际发设备命令是在另一条回调：

- `cctThrottleValueChanged` 将 slider 值 clamp 后调用 `MeshAPI.setNodeColorTemperatureState(...)`。
- 拖动过程中按节流发送，结束时使用 ACK。

所以 UI 变色和设备命令是并行但分层的：UI 先根据本地状态立即变，设备状态后续通过 Mesh 命令同步。

## 顶部 ImageView 的着色规则

顶部相关视图在 `DeviceLightViewController.setupUI()` 中创建：

- `lightGrayBgView`：灰白背景叠层，默认透明。
- `lightBgView`：真正被 tint 的背景图片，默认图片是 `device_light_bg`。
- `lightImageBtn`：中间灯图按钮。
- `onoffBtn`：下方 OnOff 按钮。

`DeviceLightViewController.updateData()` 中的规则：

- 只有 `node.isOn && node.lightness > 0` 时才按亮灯逻辑处理。
- 如果 `node.singleDeviceDisplaySupportCct == true`：
  - 用 `node.getEffectiveTemperature100(temperature: node.temperature)` 将实际 K 值转成 0-100 的色温百分比。
  - 用 `Node.getCctMixColor(temperature100:)` 计算颜色。
  - 把 `device_light_bg` 图片 tint 成该颜色后赋给 `lightBgView.image`。
- 如果不支持单灯 CCT 显示：
  - 直接使用未 tint 的 `device_light_bg`。
- 如果灯是 Off：
  - 使用 `device_light_off_bg`。
  - `lightGrayBgView.alpha` 归零。

`Node.getCctMixColor(...)` 的颜色插值规则：

- 0-50：从暖色 `RGB(255, 108, 0)` 过渡到白色。
- 50-100：从白色过渡到冷色 `RGB(114, 179, 255)`。

此外，当色温百分比在 45-55 之间时，`lightGrayBgView.alpha` 会变为 0.5，`lightBgView.alpha` 强制为 1，用灰白叠层弱化接近白光时的视觉边界。

## 回包刷新路径

虽然拖动 slider 时 UI 会本地即时变色，但设备回包仍会再次走同一套刷新逻辑：

- `meshNetworkManager(_:deviceDataUpdate:)` 命中当前 node 后调用 `updateData()`。
- `meshNetworkManager(_:didReceiveMessage:sentFrom:to:)` 里先 `node.updateData(message:)`，再调用 `updateData()`。

因此设备实际状态回写后，顶部背景会再次根据最新的 `node.temperature` 和 `node.isOn` 刷新。

## 边界说明

- 这个逻辑不是 `DeviceAllOnOffViewCell` 的列表 cell 背景逻辑。
- 也不是旧的 `DeviceLightHeaderView` 直接负责当前页面顶部背景。`DeviceLightHeaderView` 里存在类似的 CCT tint 逻辑，但当前新控制页的实际顶部背景在 `DeviceLightViewController` 内部维护。
- Tunable White 只影响单灯页面是否展示 CCT 控制；跨设备或自动化层面的 CCT 能力仍由 `effectiveSupportCct` / `rawSupportCct` 这类能力判断处理。
