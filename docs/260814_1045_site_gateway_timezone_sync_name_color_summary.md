# Site Gateway 时区同步名称颜色变更总结

## 结果

- Site 页面 `Overview` 右侧的 Gateway 名称：需要同步时区时显示 `#BB4D00`。
- 不需要同步时区的 Gateway 保持原有颜色规则：选中时使用 `Bar_Color`，未选中时使用 `ImportantText_Color`。
- 需要同步时区的 Gateway 被选中时仍保留原有下划线。
- `SiteGatewaysMenuView` 中需要同步时区的 Gateway 名称显示 `#BB4D00`；其他 Gateway 保持原有 `titleColor`。
- `Overview`、Add Gateway、Gateway 状态图标、背景、布局和 Time Zone Sync 页面中的 `SyncGatewayCell` 均保持现状。

## 实现范围

- 从现有 `SyncGatewaysContextBuilder` 提取可复用的目标 Gateway 计算入口，UI 与同步页面共用同一套待同步判定。
- `SiteViewController` 统一生成横向 Gateway 列表数据，并为横向列表和 Gateway 菜单注入待同步状态。
- `GatewayListView` 和 `SiteGatewaysMenuView` 只调整 Gateway 名称颜色优先级。
- 新增源代码契约测试，并接入 `scripts/check_site_sync_gateways.sh`。
- 按用户确认，将 `SyncGatewaysBottomActionBar` 的 0.5pt 分割线更新为契约测试基线。

## 验证结果

- `scripts/check_site_sync_gateways.sh`：通过，包含新增名称颜色契约及既有 Site 时区同步契约。
- `git diff --check`：通过。
- generic iPhoneOS、禁用签名构建：`SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 均通过。
- 未修改本地化、资源、target 配置或依赖。

## 验收边界

当前完成的是静态契约测试与四个 target 的编译验证；尚未替代真机界面、真实服务器数据及 Gateway/Mesh 端到端验收。
