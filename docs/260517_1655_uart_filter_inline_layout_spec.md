# UART 消息页筛选输入框并排布局规格

## 背景

UART 消息页顶部当前有两组筛选控件：

- `Contain` Label + 输入框 + 外置清除按钮
- `Ignore` Label + 输入框 + 外置清除按钮

这套布局可读性明确，但占用两行高度，并且 Label 与占位文案表达重复。此前外置清除按钮已经改为 SF Symbol `xmark`，现在进一步优化为直接使用输入框自带清除按钮，让筛选区更紧凑。

本次优化只调整 UART 消息页顶部筛选区的 UI 布局和清除入口，不改变 UART 消息接收、缓存、过滤规则、分享、清空消息、Auto / Manual 滚动语义。

## 目标

- 去掉 `Contain` 与 `Ignore` 两个 Label。
- 去掉两个输入框右侧的外置清除按钮。
- 将 `Contain` 与 `Ignore` 两个输入框放在同一行。
- 两个输入框平分可用屏幕宽度。
- 筛选行左右边距与页面顶部控制区保持一致。
- 两个输入框中间间隔固定为 8。
- 两个输入框都使用系统自带清除按钮，并且清除按钮一直展示。
- 保留现有占位文案、输入行为、过滤逻辑和消息列表刷新逻辑。

## 非目标

- 不改变 `Contain` 与 `Ignore` 的过滤语义。
- 不调整 UART 消息缓存、接收、停止接收、分享导出或清空消息逻辑。
- 不新增正则、通配符、多关键词或大小写敏感选项。
- 不新增自定义输入框组件。
- 不使用 `UITextField.rightView` 自定义清除按钮。
- 不修改本地化文案内容。
- 不处理 `user-temp/`。

## 页面结构

采用已确认的方案一：最小结构调整。

UI 原型中的内容使用英文：

```text
Navigation Bar
┌────────────────────────────────────────┐
│ UART Messages                   Share  │
├────────────────────────────────────────┤
│ Auto | Manual  [ Stop ]    [ Clear ]   │
│ [ Message must contain  x ][ Message must not contain  x ] │
├────────────────────────────────────────┤
│ 2026-05-17 16:55:12.123                │
│ [ UART message text ]                  │
└────────────────────────────────────────┘
```

布局要求：

- 顶部第一行控制项保持现状：Auto / Manual、Stop / Start、Clear。
- 第二行只保留两个筛选输入框。
- 左输入框为 `Contain` 筛选。
- 右输入框为 `Ignore` 筛选。
- 左右页面边距沿用当前筛选区边距：16。
- 两个输入框之间间隔为 8。
- 两个输入框等宽。
- 两个输入框高度沿用当前高度：36。
- 即使在较窄屏幕上，也保持两个输入框并排，不降级为上下两行。

## UI 行为

- 两个输入框继续使用现有 placeholder：
  - Contain：`消息必须包含` / `Message must contain`
  - Ignore：`消息必须不包含` / `Message must not contain`
- 两个输入框继续使用 ASCII 键盘。
- 两个输入框继续关闭自动纠正、拼写检查、联想相关输入辅助。
- 两个输入框的系统清除按钮一直展示。
- 点击系统清除按钮后，必须清空对应输入框，刷新过滤文本，并立即刷新消息列表。
- 点击系统清除按钮只影响对应筛选条件，不影响另一个输入框。
- 修改任一输入框内容后，过滤结果立即刷新。
- Auto 模式下，过滤条件变化后继续滚动到最新可见消息。
- Manual 模式下，过滤条件变化后只刷新列表，不主动滚动。
- 点击 Auto、Manual、Stop、Start、Clear、Share 时继续收起键盘，沿用当前行为。

## 过滤规则

过滤规则保持现状：

- `Contain` 输入 trim 前后空白后参与匹配。
- `Ignore` 输入 trim 前后空白后参与匹配。
- 输入内容中间空格保留。
- trim 后为空字符串表示该条件未配置。
- 匹配忽略大小写，继续沿用当前变音符忽略逻辑。
- `Contain` 非空时，消息内容必须包含该文本。
- `Ignore` 非空时，消息内容必须不包含该文本。
- 两者都为空时展示全部缓存消息。
- 过滤只影响页面可见消息，不删除、不修改、不重排缓存消息。

## 代码影响范围

预计只修改 `SunSmart/Main/Space/Debug/SpaceDebugUARTViewController.swift`：

- 移除 `containFilterLabel`、`ignoreFilterLabel` 的属性和配置使用。
- 移除 `containFilterClearButton`、`ignoreFilterClearButton` 的属性和配置使用。
- 移除外置清除按钮的约束。
- 移除外置清除按钮的 action 方法。
- 调整两个输入框的 SnapKit 约束为同一行、等宽、中间 8 间隔。
- 将输入框 `clearButtonMode` 从 `.never` 改为 `.always`。

本次不需要修改 SDK、资源图片、Pod 依赖、Swift Package 配置或本地化字符串。

## 风险与处理

### 窄屏占位文案截断

两个输入框始终并排，英文 `Message must not contain` 在较窄屏幕上可能显示不完整。该风险已接受，因为用户确认较窄屏幕也保持并排，且输入框的过滤含义可由 placeholder 和页面使用上下文共同表达。

### 系统清除按钮事件触发

需要验证点击 `UITextField` 自带清除按钮后是否稳定触发现有 `editingChanged` 回调。如果验证发现没有触发，应在实现计划中补充轻量兜底，确保清除后同步更新过滤状态并刷新列表。

### 图标样式不可控

系统清除按钮样式由 `UITextField` 管理，不能像外置按钮一样精确控制 SF Symbol、颜色和尺寸。该风险可接受，因为本次目标是减少额外按钮并采用输入框自带清除入口。

## 验证范围

- 静态检查：
  - 不再创建或添加 `containFilterLabel`、`ignoreFilterLabel`。
  - 不再创建或添加 `containFilterClearButton`、`ignoreFilterClearButton`。
  - `containFilterTextField` 与 `ignoreFilterTextField` 使用 `.always` 的系统清除按钮。
  - 两个输入框约束为同一行、等宽、中间间隔 8。
- 构建验证：
  - 构建 `SunSmart` Debug iOS target，确认无编译错误。
- 手动验证：
  - UART 消息页不再展示 `Contain` 与 `Ignore` Label。
  - 两个筛选输入框并排展示，左右边距与页面顶部控制区一致。
  - 两个输入框中间间隔为 8。
  - 输入框为空时也展示系统清除按钮。
  - 点击 Contain 输入框清除按钮只清空 Contain 条件并刷新列表。
  - 点击 Ignore 输入框清除按钮只清空 Ignore 条件并刷新列表。
  - Contain 单独配置、Ignore 单独配置、两者同时配置、两者都为空时，过滤结果保持现有语义。
  - Auto 模式下过滤变化后滚动到最新可见消息。
  - Manual 模式下过滤变化后不主动滚动。
  - Share 导出仍包含全部缓存消息，不受 UI 过滤条件影响。
  - Clear 仍清除全部缓存消息，不只清除当前可见消息。
