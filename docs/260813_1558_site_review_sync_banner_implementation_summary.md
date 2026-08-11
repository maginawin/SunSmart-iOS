# Site Review Sync 提示组件实施总结

## 结果

已按确认的方案 A 完成 Site 页面 `Review sync` 后续流程：

- 首次进入 Site 的 `Sync status` 弹窗保持一次性语义；`LATER` 和弹窗内的 `REVIEW SYNC` 都只关闭弹窗并返回 Site 页面。
- 每次成功解析并导入 Site 服务器快照后，都会以服务器 Site time zone 为真值，重新比较当前用户可管理范围内 Gateway 的 `timezoneOffset`。
- 没有 Gateway 需要同步时保持现状；有 Gateway 需要同步时，在 Site 页面两个 collection header 中展示 `Review sync` 提示组件。
- 页面提示组件展示服务器 UTC offset 和待同步 Gateway 数量，支持单数、复数及英文、简体中文本地化。
- 点击页面提示组件的 `Review sync` 按钮，会 push 到当前仅包含导航标题的空白 `Sync gateways` 页面。
- 下拉刷新仍沿用原有 `/sitespace/get/siteprops` 数据获取及导入链路；刷新不会再次展示 `Sync status` 弹窗，但会更新页面提示组件状态。

## 状态与权限规则

- Owner：按去重后的全部 Site Gateway 计算；无标识 Gateway 独立计数。
- Editor：只计算绑定到 Editor Space 的 Gateway；同一 Gateway 多次绑定只计一次。
- Visitor：接受服务器 Site props 真值，但不展示可操作的 Gateway 同步提示。
- 服务器时区无效或响应无法形成可信快照时，不使用无效结果覆盖页面上一次可信状态。
- App time zone 成功上传服务器后，立即以本次上传成功的时区重新计算提示状态。

## UI 实现

`Review sync` 组件按 Figma `Actions/ServerTimeZoneUTC08` 图层实现：

- 浅黄色背景、14pt 圆角、复用既有 warning 矢量图标。
- 两行以内的 12pt 描述文案。
- 白色圆角 `Review sync` 按钮。
- 与上方 Gateway list/status 组件及下方 Cell 均保留 8pt 间距。

新增源码已同步加入 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 四个 target。

## 自动验证

以下聚焦测试与回归入口均通过：

- `SiteEntryTimeZoneSyncPolicyTests`
- `SiteEntryTimeZoneSyncCoordinatorTests`
- `SiteEntryTimeZoneSyncContractTests`
- `SiteTimeZoneReviewSyncContractTests`
- `SiteTimeZoneValueTests`
- `SiteTimeZoneCatalogTests`
- `SitePropsEditPolicyTests`
- `SiteTimeZonePersistenceContractTests`
- `SitePropsAPIContractTests`
- `SiteTimeZoneUIContractTests`：页面路由与本地化/资源两种入口
- `SiteUpdateToastUIContractTests`：component 与 routing
- `SiteEditAlertTransitionContractTests`：component 与 edit-site
- `SiteGatewayOnlineStateContractTests`

其他检查：

- English、简体中文 `Localizable.strings`：`plutil -lint` 通过。
- `git diff --check`：通过。
- 新提示组件和空白页面范围扫描：未引入 BLE、Mesh 或 Gateway 同步行为。

四个 scheme 均使用 Debug、generic iPhoneOS、关闭签名直接构建通过：

- `SunSmart`：`BUILD SUCCEEDED`
- `Archipelago`：`BUILD SUCCEEDED`
- `SLG Sync Plus`：`BUILD SUCCEEDED`
- `SylSmart`：`BUILD SUCCEEDED`

构建仍输出工程原有警告，包括部分品牌 target 的 Info.plist 位于 Copy Bundle Resources，以及 FSCalendar 重复 Compile Sources；本次未扩大范围处理。

## 待真机与真实环境验收

- 真实 `/sitespace/get/siteprops` 响应中的 `timezone`、`spaces`、`gateways.timezoneOffset` 字段完整性与单位。
- Owner、Editor、Visitor 的真实服务器权限和 Space/Gateway 绑定数据。
- 真机上提示组件动态文案、两行布局、8pt 间距与按钮触感。
- 下拉刷新期间服务器时区变化、Gateway offset 变化时的显示/隐藏切换。
- `Sync gateways` 的真实 Gateway/BLE/Mesh 同步能力不在本期范围内。
