# WiFi/4G Gateway 子页面下滑关闭保护实施总结

## 改动

- `WiFi DFU` 与 `Information` 两个指定菜单入口 push 前保护外层模态导航栈。
- 进入保护流程时保存 `isModalInPresentation` 原值，避免覆盖调用方已有设置。
- 保护状态覆盖目标页面继续进入的子页面。
- Gateway 主页面完整返回后恢复进入前的下滑关闭状态。
- 共享 `DeviceInformationViewController`、`NavigationViewController` 及其他入口保持不变。

## 验证

- TDD RED：聚焦 contract 在实现前按预期报告缺少状态保存逻辑。
- 聚焦 contract：通过。
- 既有 WiFi Gateway firmware contract：通过。
- `git diff --check`：通过。
- SunSmart iPhoneOS Debug build：通过。
- Archipelago iPhoneOS Debug build：通过。
- SLG Sync Plus iPhoneOS Debug build：通过。
- SylSmart iPhoneOS Debug build：通过。

## 手工验收边界

编译与静态 contract 不能替代真机手势验证。需要在 WiFi Gateway 与 4G Gateway 上分别确认：

1. 进入 `WiFi DFU` 后不能下滑关闭整个页面栈。
2. 进入 `Information` 后不能下滑关闭整个页面栈。
3. 从上述页面返回 Gateway 主页面后恢复下滑关闭。
