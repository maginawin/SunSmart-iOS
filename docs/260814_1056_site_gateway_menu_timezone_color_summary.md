# Site Gateway 菜单待同步名称颜色优化总结

## 结果

- `SiteGatewaysMenuView` 中需要同步时区的 Gateway 名称改为 `#FFD230`。
- Site 页面 `Overview` 右侧横向 Gateway 列表继续使用 `#BB4D00`。
- 菜单中不需要同步时区的 Gateway、Add Gateway 及其他控件保持原有行为。
- 未修改待同步 Gateway 的业务判定、状态传递或 `SyncGatewayCell`。

## 实现

- 在现有 Site Gateway 时区同步外观定义中增加菜单专用待同步名称颜色。
- `SiteGatewaysMenuView` 的待同步分支改用菜单专用颜色；普通 Gateway 继续恢复原有 `titleColor`。
- 更新名称颜色契约，分别约束横向列表 `#BB4D00` 与菜单 `#FFD230`，避免两种背景场景再次误用同一颜色。

## TDD 证据

- RED：更新契约后，测试因缺少菜单专用 `#FFD230` 明确失败。
- GREEN：最小实现后，单项名称颜色契约和完整 Site 时区同步契约均通过。

## 验证

- `scripts/check_site_sync_gateways.sh`：通过。
- `git diff --check`：通过。
- generic iPhoneOS、禁用签名构建：`SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 均通过。
- 未修改本地化、资源、target 配置或依赖。

## 验收边界

当前完成的是契约测试与编译验证；黑色背景下的实际对比度和最终视觉效果仍需真机界面验收。
