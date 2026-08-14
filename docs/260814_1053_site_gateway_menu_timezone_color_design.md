# Site Gateway 菜单待同步名称颜色优化设计

## 目标

仅优化 `SiteGatewaysMenuView` 在黑色背景下的可读性：需要同步时区的 Gateway 名称由 `#BB4D00` 改为 `#FFD230`。

## 已确认规则

- Site 页面 `Overview` 右侧横向 Gateway 列表继续使用 `#BB4D00`。
- `SiteGatewaysMenuView` 中需要同步时区的 Gateway 名称使用 `#FFD230`，即 RGB `(255, 210, 48)`。
- 菜单中不需要同步时区的 Gateway 继续使用现有 `titleColor`。
- Add Gateway、状态图标、选中背景、字体、布局、行高、分隔线和选择回调保持现状。
- 时区待同步 Gateway 的业务判定和数据传递保持现状。
- 不修改 Time Zone Sync 页面中的 `SyncGatewayCell`。

## 方案

保留现有横向列表待同步颜色常量，新增菜单专用待同步名称颜色常量。`SiteGatewaysMenuView` 的待同步分支只引用菜单专用颜色，避免两个不同背景场景继续共用同一个颜色语义。

不把颜色放入 Controller 或 `GatewayMenuData`，因为 Controller 只负责传递 `needsTimeZoneSync`，View 继续负责视觉表现。

## 测试与验收

- 更新现有 Site Gateway 名称颜色契约，分别锁定横向列表 `#BB4D00` 与菜单 `#FFD230`。
- 契约需确保菜单待同步分支引用菜单专用颜色，普通 Gateway 和 Add Gateway 仍恢复 `titleColor`。
- 运行完整 `scripts/check_site_sync_gateways.sh`、`git diff --check` 和四个品牌 target 的 generic iPhoneOS 构建。
- 自动化验证不替代黑色背景下的真机视觉验收。

