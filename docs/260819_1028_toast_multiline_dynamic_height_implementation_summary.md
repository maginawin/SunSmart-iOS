# ToastStatusView 多行文字与动态高度实施总结

## 1. 实施结果

- Standard 与 Site Update 两种外观均改为不限行、按词换行，不再使用尾部省略号。
- 两种外观都降低 UILabel 的横向压缩阻力，使文字在既有最大内容宽度内优先换行。
- Toast 的 44pt 固定或局部最小高度收敛为两个外观共用的最小高度。
- Site Update 移除了 UILabel 的 22pt 固定高度以及 Toast 的 44pt 固定高度。
- Standard 使用 12pt 上下内容约束，Site Update 使用 7pt 上下内容约束，由 StackView 和 UILabel intrinsic content size 反推实际 Toast 高度。
- 图标尺寸、图标文字间距、水平安全间距、短文案整体居中、字体、颜色、圆角、阴影、动画、位置和默认展示时长均保持不变。
- 未修改调用 API、业务调用点、本地化、Asset Catalog、target 配置或依赖。

## 2. 修改文件

- `SunSmart/Common/View/ToastStatusView.swift`
- `Tests/Site/SiteUpdateToastUIContractTests.swift`
- `docs/260819_1014_toast_multiline_dynamic_height_development_plan.md`
- `docs/260819_1028_toast_multiline_dynamic_height_implementation_summary.md`

## 3. 测试证据

### 3.1 RED / GREEN

- 更新契约后在旧生产实现上运行：按预期失败，失败点为 Standard 仍限制两行且纵向约束未闭合。
- 完成生产布局修改后重跑：Toast component contract 通过。

### 3.2 Focused contracts

以下契约均通过：

- Site Update Toast component
- Site Update Toast routing
- Site Time Zone UI
- Site Time Zone localization 与 target membership
- Sync Gateways UI
- Gateway Force Clear Spaces
- Gateway Detail Clock runtime

### 3.3 静态检查

- `git diff --check` 通过，无空白错误。
- 最终业务改动只涉及 `ToastStatusView.swift` 和对应 Toast contract；其余新增文件为方案与实施总结。

## 4. 四品牌构建

以下 scheme 均使用 Debug、generic iPhoneOS、关闭代码签名直接构建成功：

- SunSmart
- Archipelago
- SLG Sync Plus
- SylSmart

构建过程中只有既有的 App Intents metadata 跳过提示，没有与本次改动相关的编译错误。

## 5. 尚未证明的验收项

自动契约和 generic iPhoneOS 构建不能证明实际 UI 视觉结果，仍需真机确认：

- Standard 与 Site Update 的成功、失败图标在两行及三行以上文案旁视觉垂直居中。
- English 与简体中文长文案完整换行且无省略号。
- 超长 Gateway display name 在窄屏设备上没有横向溢出或 Auto Layout 告警。
- 单行 Toast 仍保持 44pt 高度和既有水平位置。
- top、center、bottom 三种展示位置在高度增长后不越过安全区。
- 1.5 秒默认展示时长是否足以阅读多行长文案不在本次需求范围内。

## 6. Git 边界

- 未执行 commit、push 或 merge。
