# Edit Site Local time 布局优化总结

## 完成范围

已按 One-SunSmart Figma 节点 `399:13620` 优化 Edit Site 的 Local time 展示：

- Time Zone 白色圆角选择行固定为 44pt。
- Local time 已从 Time Zone 行移到页面透明内容区域，不再继承选择行背景。
- Local time 位于选择行下方 8pt，高度 20pt。
- Site Icon 标题位于 Local time 下方 16pt。
- timezone 未配置时继续隐藏 Local time，并将高度收为 0，使 Site Icon 与 Time Zone 行保持 20pt 间距。
- 删除旧布局中位于 Time Zone 行内部、仅用于分隔 Local time 的横线。

## 保持不变

- Local time 文案、本地化、字体、颜色和日期格式。
- 0.5 秒刷新以及页面显示、前后台生命周期。
- Time Zone 选择、草稿、retrieve、update、pending 和同步状态流程。
- Site Icon 数据和四列布局。
- 四个品牌 target 的资源、依赖和配置。

## TDD 与静态验证

- 先扩展 `SiteTimeZoneUIContractTests`，确认旧实现因 Local time 仍位于 Time Zone 容器而失败。
- 完成最小布局修改后，同一 focused contract 通过。
- 完整 UI 路由 contract 通过。
- 本地化、资源与四 target 归属 contract 通过。
- `git diff --check` 通过。

## 构建验证

以下 scheme 均使用 Debug、generic iPhoneOS、关闭签名方式构建成功：

- SunSmart
- Archipelago
- SLG Sync Plus
- SylSmart

构建输出仍包含工程既有警告，例如未使用 AppIntents 时跳过 metadata extraction；未出现本次 Local time 布局改动导致的编译错误。

## 验证边界

上述结果证明源码 contract、静态检查和四品牌 generic iPhoneOS 编译成立，不替代四品牌真机上的实际视觉验收。仍建议在已配置和未配置 timezone 两种状态下检查背景、纵向间距、滚动内容高度及中英文显示。

本次未创建 Git commit。
