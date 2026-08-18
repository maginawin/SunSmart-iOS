# ToastStatusView 多行文字与动态高度开发方案

## 1. 目标

当 `ToastStatusView` 的文案超过一行可用宽度时完整换行展示，不再以省略号截断；左侧图标保留现有水平间距，并相对多行文字内容垂直居中。Toast 高度由 Auto Layout 根据内容计算，单行时继续保持现有最小高度和视觉样式。

本方案只规划开发与验证范围，确认前不修改生产代码、测试契约、本地化、资源或工程配置。

## 2. 当前实现与根因

### 2.1 Site Update 外观

- `messageLabel.numberOfLines` 固定为 1，直接导致超宽文案使用尾部省略号。
- `messageLabel` 高度固定为 22pt，Toast 高度固定为 44pt，当前纵向约束不允许文本增长到多行。
- 内容使用水平 `UIStackView`，图标容器为 30 × 30pt，实际图标为 16 × 16pt，StackView 已使用垂直居中对齐。
- 内容行当前整体水平居中，并保留左右至少 22pt 的安全间距；该规则应继续保留，避免短文案样式发生无关变化。

### 2.2 Standard 外观

- 当前最多显示两行，因此一行以上可以换行，但超过两行仍可能被截断。
- Toast 已声明最小高度 44pt，但内容区的顶部、底部不等式约束没有形成清晰的自适应高度闭环。
- 图标为 14 × 14pt，StackView 已使用垂直居中对齐。

### 2.3 影响范围

- `ToastStatusView.swift` 被 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 四个 target 共用。
- 当前共有 11 个生效调用点：4 个使用默认 Standard 外观，7 个使用 Site Update 外观。
- 较长的 Gateway 英文文案及带 Gateway display name 的同步结果最容易触发 Site Update 截断。
- 当前 focused component contract 通过，工作区基线干净。

## 3. 建议方案

### 3.1 统一换行规则

- Standard 与 Site Update 两种外观都允许按实际内容换行，不设置两行上限。
- 明确使用按词换行模式，消除尾部省略号行为；中文仍按系统可用断行位置换行。
- 不改变字体、字号、颜色、图标资源、圆角、阴影、动画、位置和默认展示时长。

### 3.2 由约束反推高度

- Site Update 将固定 44pt 高度改为最小 44pt。
- 移除 Site Update 文本 22pt 固定高度，让 UILabel 的多行 intrinsic content size 参与布局。
- 为 Site Update 内容行建立确定的顶部和底部内边距；单行时由 30pt 图标容器加上下内边距维持 44pt，高度超过图标时由多行文字自然撑高。
- Standard 继续保持最小 44pt，并将内容行顶部、底部约束调整为可闭合的等距约束，使多行文字能够反推 Toast 高度。
- 两种外观继续使用水平 StackView 的垂直居中对齐；图标尺寸固定，不随文字增高拉伸，最终位于多行文字块的垂直中心。

### 3.3 保持现有水平布局

- Standard 保持现有左右 16pt 内容安全间距、14pt 图标和现有图标文字间距。
- Site Update 保持左右至少 22pt 的内容安全间距、30pt 图标容器、16pt 图标和 10pt 图标文字间距。
- 保留短文案时“图标与文字作为整体居中”的现有行为；多行内容达到可用宽度后，图标左侧仍不会小于既有间距。
- 不把图标改为绝对贴左，也不改变 Site Update 当前文字对齐方式，以免本次换行修复扩大为视觉重设计。

## 4. 计划修改

### 4.1 先更新布局契约

修改 `Tests/Site/SiteUpdateToastUIContractTests.swift`：

- 去除 Site Update 必须固定 44pt 高度、文字必须固定 22pt 高度的旧契约。
- 增加两种外观都允许不限行换行、使用按词换行且不使用省略号的契约。
- 增加 Site Update 最小 44pt、Standard 最小 44pt 的契约。
- 增加内容区顶部和底部约束闭合、StackView 垂直居中、图标尺寸固定、既有水平间距保留的契约。
- 先在当前生产实现上运行并确认契约按预期失败，证明测试能够捕获本问题。

### 4.2 最小修改生产布局

修改 `SunSmart/Common/View/ToastStatusView.swift`：

- 调整两个外观的 UILabel 换行设置。
- 移除 Site Update 文本固定高度和 Toast 固定高度。
- 以最小高度加内容区上下约束形成完整纵向布局链。
- 保留公开展示 API 和所有调用点，不要求业务页面传入额外高度或行数参数。

### 4.3 回归契约

- 重新运行 Site Update Toast component 与 routing contract。
- 回归 Site Time Zone、Sync Gateways、Gateway Force Clear、Gateway Detail Clock 等引用 Site Update Toast 的 focused contracts。
- 运行 `git diff --check` 并核对改动只包含 Toast、对应测试和实施总结文档。

### 4.4 四品牌构建

按项目规则直接使用 generic iPhoneOS、关闭签名，依次构建：

- SunSmart
- Archipelago
- SLG Sync Plus
- SylSmart

不使用 shell 包装、日志重定向或 Simulator。四个构建成功只证明共享源码和 target 集成有效，不代表视觉验收完成。

## 5. 人工验收建议

- Standard 与 Site Update 各检查成功、失败状态。
- English 与简体中文各检查单行、两行及三行以上文案。
- 检查包含超长 Gateway display name 的同步成功和失败文案。
- 在窄屏设备宽度下确认不出现省略号、横向溢出或约束告警。
- 确认单行 Toast 仍为 44pt，短文案整体水平位置与当前一致。
- 确认多行 Toast 仅向垂直方向增长，图标左侧间距不变且相对文字块垂直居中。
- 检查 top、center、bottom 三种位置的增长方向不会越过安全区。

## 6. 明确不包含

- 不调整 Toast 的 1.5 秒默认展示时长。
- 不新增最大高度、滚动或交互行为。
- 不修改任何文案或国际化 Key。
- 不修改图标、本地化资源、target 配置、依赖或业务成功失败逻辑。
- 不重构 Toast 展示 API、调用页面或动画实现。
- 不执行 Git commit、push 或 merge。

## 7. 待确认决策

建议按 `ToastStatusView` 类级别统一处理：Standard 与 Site Update 都改为不限行完整换行；44pt 仅作为最小高度，短文案布局保持不变。

如果需求实际只针对 Site Update 外观，或希望最多只显示两行，需要在实施前缩小范围并保留另一外观的现状。
