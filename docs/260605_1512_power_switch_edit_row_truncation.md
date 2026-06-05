# Power Switch Edit Row Truncation

## 背景

Battery power switch 和 AC power switch 共用 8-key switch 的 Edit Switch 页面。Group 和 Scene 行右侧 Details 在内容过多时，会挤压左侧标题，导致 `Group` / `Scene` 标题显示不稳定。

## 方案

- 在 `PJEightKeySwitchInfoRowView` 中提高左侧 title label 的 horizontal hugging 与 compression resistance，确保 title 不被右侧 Details 压缩。
- 右侧 value label 固定单行并使用 tail truncation，Details 过长时由系统在右侧展示省略号。
- 将 title 与 Details 的最小间隔从 16 调整为 8。
- Group 与 Scene 多项展示由逗号直接连接调整为 `, ` 分隔，例如 `group1, group 2, group 3, ...`。

## 影响范围

- 主要影响 battery/ac power switch 的 Edit Switch 页面中 Panel、Group、Scene 等 `valueWithArrow` 行。
- `PJEightKeySwitchInfoRowView` 是当前 8-key switch 编辑页内部组件，未改动全局通用 Cell。
- 未修改本地化、资源、target 配置或依赖。

## 验证

已执行并通过：

`xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination generic/platform=iOS CODE_SIGNING_ALLOWED=NO build`

