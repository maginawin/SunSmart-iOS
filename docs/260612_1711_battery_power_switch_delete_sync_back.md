# Power Switch Delete Sync Back Failure

## 问题

Battery Power Switch 绑定一个组，组内设备离线后，从 switch edit 右上角菜单删除该 Battery Power Switch，会进入 Sync Device(s) 页面。删除同步失败后点击左上角返回按钮，按钮事件触发，但页面不返回。

## 根因

`SyncDevicesViewController.backAction()` 在存在 `backActionCallback` 时只收集同步结果并调用 callback，不会执行默认的 `closeAfterSync()`。

删除开关入口位于 `DeviceSwitchesViewController.deleteSwitchData(_:source:)`。该入口给 SyncDevices 页设置了：

```swift
vc.backActionCallback = { _ in }
```

因此失败后点击返回时，SyncDevices 页只执行空 callback，既不 pop 也不 dismiss。

## 覆盖范围

同类风险存在于 `DeviceSwitchesViewController.deleteSwitchData(_:source:)` 这个共享删除入口：

- Battery Power Switch 从 Main Switches 的 monitor/edit 删除会走这里。
- AC Power Switch 从 Main Switches 的 monitor/edit 删除也会走这里。
- Kinetic Switch 从 Main Switches 列表编辑态删除也会走这里。

Group 页面内的删除入口不属于这次问题：

- `GroupPowerSwitchesViewController` 的 Battery/AC 删除失败返回 callback 已经会 pop。
- `GroupSwitchsViewController` 的 Kinetic 删除失败返回 callback 已经会 pop。
- Kinetic 旧详情页 `DeviceSwitchViewController` 的删除失败返回 callback 也已经会 pop。

## 修复

将删除同步失败返回的 callback 改为只关闭 SyncDevices 页：

- 如果 SyncDevices 是通过 source 的 navigationController push 的，则 pop 当前 SyncDevices 页，返回 edit/monitor 上级页面。
- 如果 SyncDevices 是以独立 NavigationViewController modal 形式展示的，则 dismiss。
- 成功路径保持原逻辑：先关闭 SyncDevices，再完成删除缓存和来源页关闭。

## 验证

- RED：确认旧代码仍存在空 `vc.backActionCallback = { _ in }`。
- GREEN：确认空 callback 已移除，并存在 `closeSwitchDeleteSyncController` 关闭逻辑。
- iPhoneOS 编译验证通过：`xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`。
