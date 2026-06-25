# Information Push 动画问题分析与修复方案

## 背景

设备：Up Down Light

- CID：`0x0A78`
- PID：`0x2491`

现象：在设备页右上角选项菜单中点击 Information 后，会进入 Information 页面，但用户感知没有正常 push 动画。

## 代码事实

`SunSmart/devices_config.json` 中 `0x0A78 / 0x2491` 的 `deviceCategory` 是 `Lighting`，所以它走普通 `DeviceLightViewController`，不是 up/down ratio 专用页面。

`DeviceLightViewController.information()` 已经使用 `navigationController?.pushViewController(..., animated: true)`，所以问题不是 push 参数写错。

真实差异在 `MenuPopView` 的点击生命周期。原始 `tableView(_:didSelectRowAt:)` 是先执行 `item.tapItemBack?(item)`，再执行 `dismiss(animation: item.hideAnimation)`。Information 回调里立刻 push 新页面，但菜单视图还挂在 keyWindow 上，同一轮事件里再被移除，视觉上容易表现为目标页面已经出现而没有正常 push 动画。

`hideAnimation: false` 只能关闭菜单 fade out，不会改变“先 push、后移除菜单”的顺序，所以它不是完整修复。即使把 action 放进 dismiss completion，如果 completion 在 `hideAnimation: false` 时同步执行，push 仍然发生在同一轮 table selection 事件里；Light 页面仍可能表现为无 push 动画。因此设备 Information action 需要在菜单移除后的下一轮主队列执行。

复测后 Light 类型仍无可见 push 动画，说明 UIKit 默认 `pushViewController(..., animated: true)` 在该设备页场景下仍不可靠。项目内已有 `CALayer.addMoveInAnimation(duration:type:animationOrientation:)`，可以为设备 Information 入口添加显式 `.push / .fromRight` 转场，再用 `pushViewController(..., animated: false)` 入栈，保证所有设备页进入 Information 都有可见 push 动画。

## 同类影响面

需要同步处理的设备页：

1. 普通 Light 设备页：`SunSmart/Main/Device/Controller/DeviceLightViewController.swift`
2. DALI 设备页：`SunSmart/Main/Device/Dali/Controller/DaliMasterViewController.swift`
3. WiFi Gateway 设备页：`SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift`
4. Emergency Fire Controller 设备页：`SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorRouting.swift`
5. Battery / AC Power Switch Monitor 页：`SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift`
6. 潜在复用 base 实现：`SunSmart/Main/Device/Controller/DeviceBaseViewController.swift`

本轮不扩展到 Group / Scene 菜单跳转，也不改变 Delete、Refresh、Identify 等非 Information 操作。

## 推荐方案 A

给 `MenuPopView.MenuItem` 增加一个默认关闭的 opt-in 参数，用来声明该 item 需要先 dismiss 菜单，再执行 action。

实施方式：

1. `MenuPopView.dismiss` 增加 completion 参数。
2. `MenuPopView.MenuItem` 增加 `performsActionAfterDismiss`，默认 `false`。
3. `didSelectRowAt` 中保持默认行为兼容：普通 item 仍然先 action 再 dismiss。
4. 只有 `performsActionAfterDismiss == true` 的 item 先 dismiss，再在下一轮主队列执行 action。
5. 设备 Information item 统一设置 `hideAnimation: false, performsActionAfterDismiss: true`。
6. 设备 Information 页面统一通过 `pushDeviceInformationController(_:)` 入栈，该 helper 先对 navigation view 添加 `.push / .fromRight` 转场，再执行 `pushViewController(..., animated: false)`。

这样可以精确修复 Information 页面进入动画，同时不改变现有 Edit / Delete / Refresh / Identify 的点击时序。

## 验证计划

1. 新增静态 contract，确认 `MenuPopView` 有 opt-in 顺序，并确认设备 Information item 都开启该能力。
2. 运行 contract。
3. 运行 `git diff --check`。
4. 运行 iPhoneOS build：
   `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
