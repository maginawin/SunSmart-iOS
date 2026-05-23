# `dev1` Toast 触发分析

## 结论

当前项目内只有一个明确的 `dev1` toast 来源：

- `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorVC.swift`
- `groupPreviousSwipeAction()` 中直接调用 `XWHUDManager.showTipHUD("dev1", isLineFeed: true)`

触发操作为：

1. 进入 Others 设备列表。
2. 点选一个应急火警控制器设备，并且该设备不是 `unboundDevice` 或 `syncIssueDevice` 状态。
3. 页面进入 `EmerFireAlarmMonitorVC`。
4. 在监控页任意位置执行向右滑动手势。

向右滑动会触发 `groupPreviousSwipeAction()`，因此显示 `dev1`。

## 证据

`EmerFireAlarmMonitorVC.viewDidLoad()` 注册了两个全页滑动手势：

- `.right` 绑定到 `groupPreviousSwipeAction`
- `.left` 绑定到 `groupNextSwipeAction`

其中 `groupPreviousSwipeAction()` 目前只有一行调试 toast：

```swift
@objc private func groupPreviousSwipeAction() {
    XWHUDManager.showTipHUD("dev1", isLineFeed: true)
}
```

`rg "dev1"` 在主工程和本地 `NordicSigMeshSDK` 中未发现其它业务来源；SDK 中没有命中，主工程只有上述一处。

`EmerFireAlarmMonitorVC` 的直接入口目前只在 `DeviceOthersViewController`：

- `showItems` 由 `DeviceEmerFireStore.shared.devices(in: space)` 生成应急火警设备项。
- 点选 `.emergencyFireController` 时，如果状态是 `unboundDevice` 或 `syncIssueDevice`，进入 `LinkedEmerFireEditVC`。
- 其它状态进入 `EmerFireAlarmMonitorVC`。

## 根因判断

`dev1` 是未清理的开发调试文案。它不经过本地化，也没有业务语义。结合方法名 `groupPreviousSwipeAction()`、同页横向分页 collection view、以及空实现的 `groupNextSwipeAction()`，这里大概率是开发期间用于验证左右滑手势的临时 toast。

## 影响范围

只要进入应急火警控制器监控页，向右滑动都可能触发该 toast。由于手势加在 `view` 上，滑动发生在 collection view 区域或页面其它区域时都有机会被识别。

不受影响的路径：

- 未绑定或同步异常的应急火警控制器卡片会进入编辑页，不进入监控页。
- 左滑手势目前绑定到空实现，不会显示 `dev1`。

## 建议修复

删除 `groupPreviousSwipeAction()` 内的 `XWHUDManager.showTipHUD("dev1", isLineFeed: true)`。如果后续确实需要左右滑切换分页，应实现真实的上一页/下一页逻辑；否则也可以移除这两个全页 `UISwipeGestureRecognizer`，避免和 collection view 的横向分页手势产生冲突。
