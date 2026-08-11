# Time Zone 页面禁止下拉关闭模态导航栈设计

## 背景

Edit Site 通过模态 `NavigationViewController` 展示，Time Zone 选择页被 push 到同一个导航栈。当前在 Time Zone 页面向下拖动，可以关闭整个模态导航栈，导致 Edit Site 草稿和页面上下文一起退出。

## 已确认需求

- Time Zone 选择页显示期间，禁止通过下拉手势关闭整个模态导航栈。
- 导航栏返回、左滑返回以及选择时区后自动返回保持现状。
- 返回 Edit Site 后，恢复进入 Time Zone 页面前的下拉关闭状态。
- 如果进入 Time Zone 页面前，导航栈已经禁止下拉关闭，返回后仍保持禁止。
- 不改变其他 Edit Site、Time Zone 或保存同步流程。

## 采用方案

由 `SiteEditViewController` 管理受保护的子流程生命周期：

1. push Time Zone 页面前，读取并保存 `navigationController.isModalInPresentation`。
2. 将导航控制器的 `isModalInPresentation` 设置为 `true`，阻止下拉关闭整个模态栈。
3. Time Zone 页面通过返回按钮、左滑或选择时区返回后，Edit Site 再次进入 `viewDidAppear`。
4. Edit Site 恢复先前保存的状态并清空快照。

只有存在状态快照时才执行恢复，因此 Edit Site 初次显示不会修改导航控制器状态。该实现沿用项目中 WiFi Gateway 受保护 push 流程的现有模式。

## 未采用方案

- 不由 Time Zone 页面在 `viewWillAppear/viewWillDisappear` 中直接恢复状态，避免交互式返回取消时出现恢复时序反复。
- 不增加全局 `UIAdaptivePresentationControllerDelegate` 或修改 `NavigationViewController`，避免扩大到其他模态页面。

## 状态与异常边界

- 重复触发进入操作时，只保存第一次读取的原状态，避免把已经锁定的 `true` 覆盖为恢复目标。
- 如果没有导航控制器，则保持当前 push 失败前的行为，不创建无效状态。
- Time Zone 页面不负责恢复状态；恢复职责始终由发起 push 的 Edit Site 页面承担。

## 测试设计

在现有 `SiteTimeZoneUIContractTests` 中增加回归断言：

- Edit Site 具有可选的模态关闭状态快照。
- push Time Zone 前保存原状态并将导航控制器锁定为 `true`。
- Edit Site 再次显示时恢复保存值并清空快照。
- 不直接写死恢复为 `false`。

完成实现后运行 Time Zone 相关 7 个测试，并构建 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 四个 scheme。

## 验收标准

- 从 Edit Site 进入 Time Zone 页面后，下拉手势不能关闭整体模态导航栈。
- Time Zone 页面仍可正常返回或选择时区。
- 返回 Edit Site 后，下拉关闭能力恢复到进入前状态。
- 其他页面的模态关闭行为不受影响。
