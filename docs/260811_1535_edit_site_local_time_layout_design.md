# Edit Site Local time 布局优化设计

## 文档状态

- 日期：2026-08-11
- 状态：已确认
- 参考设计：One-SunSmart Figma `Screen/SiteEditTimeZone`，节点 `399:13589`
- 目标节点：`ListItem/TimeZone/AsiaShanghai`，节点 `399:13620`

## 目标

优化 Edit Site 页面中的 Local time 展示，使其符合 Figma：Local time 不使用背景，并且不属于 Time Zone 选择行。

## 当前问题

当前 `SiteEditViewController` 将 Time Zone 选择内容、分隔线和 Local time 都放在同一个 80pt 高的白色圆角容器中。因此 Local time 视觉上属于 Time Zone 行，并继承了白色背景。

## 已确认方案

- Time Zone 选择行继续使用白色圆角容器，高度固定为 44pt。
- Time Zone 行继续展示 IANA 名称、UTC offset 和右侧箭头，整行保持可点击。
- Local time 从 Time Zone 容器移到页面透明内容区域。
- Local time 位于 Time Zone 行下方 8pt，高度 20pt。
- Site Icon 标题位于 Local time 下方 16pt。
- timezone 未配置时继续隐藏 Local time，并收起其占用的垂直空间，使 Site Icon 与 Time Zone 行之间保持原有 20pt 间距。
- 删除只服务于旧布局的 Time Zone 内部分隔线。

## 保持不变

- Local time 的本地化文案、字体、颜色和日期格式。
- 每 0.5 秒刷新以及前后台、页面显示生命周期。
- timezone 未配置、选择和草稿更新行为。
- Site props retrieve、update、pending、确认弹窗及同步状态逻辑。
- Time Zone 选择页、Site Icon 列表以及四个品牌 target 配置。

## 验证范围

- 更新 `SiteTimeZoneUIContractTests`，约束 Local time 必须属于透明内容区域，而不是 Time Zone 容器。
- 验证 Time Zone 容器固定为 44pt，且 Site Icon 的布局锚点位于 Local time 之后。
- 运行完整 UI contract、`git diff --check` 和四个品牌 target 的 generic iPhoneOS Debug 构建。
- 构建通过不替代四品牌真机上的实际视觉验收。
