# EFC 模拟触发不应限制组控制修复计划

## 背景

EFC 设备页点击模拟触发应急或模拟触发火警后，进入关联组页面控制设备会提示 `在紧急情况下无法控制`。预期是：模拟触发只用于验证联动效果，不应进入全局手动控制限制；只有 EFC 设备真实上报应急或火警 active 状态时，才限制控制设备，并在真实恢复或正常状态下移除限制。

## 根因

`EmerFireAlarmMonitorVC.recallEmergencyScene(_:)` 在发送模拟 `SceneRecallUnacknowledged` 后，直接调用 `EmergencyFireControllerSceneEventManager.updateManualControlBlocked(..., blocked: true)`。这会把模拟触发写入 `activeEmergencyControllerIds`，随后组页面调用 `isManualControlBlocked(for:)` 时会认为关联灯组处于真实紧急状态。

`lightLCOnAction()` 也会直接调用 `updateManualControlBlocked(..., blocked: false)`，这会让模拟恢复误清除真实上报建立的限制状态。

## 方案 B

1. 移除 EFC 页面模拟触发和模拟恢复对 `updateManualControlBlocked` 的直接调用。
2. 保留 `EmergencyFireControllerSceneEventManager.handle(...)` 对真实 EFC `SceneRecall` 上报的限制更新。
3. 在 EFC 页面刷新真实设备状态时，根据 `emergencyCurrentModeStatus` 返回的真实 display state 同步限制状态：
   - `.emergencyTriggered`、`.fireTriggered` 设置限制；
   - `.emergencyNormal`、`.fireNormal`、`.disabled`、`.offline`、`.repair` 等非触发状态清除限制。
4. 避免纯 UI loading 状态提前清除限制，防止刷新中的短暂 loading 误解除真实紧急限制。

## 修改文件

- `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorVC.swift`
  - 删除模拟触发/恢复中的全局限制写入。
- `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorRendering.swift`
  - 在真实状态渲染路径中同步全局手动控制限制。

## 验证

当前工程没有明显 test target。本次验证使用：

1. 静态检查：确认模拟触发/恢复不再调用 `updateManualControlBlocked`。
2. 状态流检查：确认真实 scene event 和真实 status query 仍会设置或清除限制。
3. `git diff --check`。
4. 指定 iOS 构建命令：
   `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
