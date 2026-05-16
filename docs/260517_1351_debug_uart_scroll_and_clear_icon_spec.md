# Debug UART 清除图标与手动滚动切换设计

## 背景

Debug / UART 消息页目前包含两行过滤输入：

- `Contain`
- `Ignore`

每行右侧都有一个常显清除按钮，但当前使用文字 `x` 展示，视觉上不符合 iOS 原生控件习惯。

页面当前支持 `Auto` 与 `Manual` 两种滚动模式。`Auto` 模式下收到匹配当前 UI 过滤条件的新 UART 消息会自动滚动到最新可见消息；`Manual` 模式下不自动滚动。现在用户手动拖动消息列表时，不会自动切换到 `Manual`，容易出现用户想查看旧消息但新消息继续把列表滚到底部的问题。

## 目标

- 将 `Contain` 与 `Ignore` 输入行右侧的文字 `x` 清除按钮替换为 Apple SF Symbols 关闭图标。
- 清除按钮仍然保持常显，点击后只清除对应输入框内容。
- 用户真实拖动消息列表，且纵向拖动位移超过 `30pt` 后，自动切换为 `Manual` 模式。
- 程序触发的自动滚动、进入页面初始滚动、过滤刷新、`reloadData()` 后的 offset 变化，都不能触发自动切换 `Manual`。
- 不改变 UART 消息接收、缓存、导出、过滤匹配、断线重连、Stop / Start / Clear / Share 的既有行为。

## 非目标

- 不新增用户设置项。
- 不新增本地化文案。
- 不改变 `Auto` / `Manual` 分段控件的文案和布局。
- 不改变 table 展示上限、session 缓存上限或 Share 导出数据来源。
- 不引入自定义图标资源。

## UI 设计

清除按钮使用 SF Symbols 的 `xmark.circle.fill`。

展示要求：

- 按钮点击区域保持当前约 `30 x 30`。
- 图标颜色沿用当前次级文字色 `SubText_Color`。
- 图标使用系统模板渲染，保持和 iOS 原生输入清除按钮相近的视觉风格。
- 按钮继续永远展示，即使输入框内容为空也可见。

交互要求：

- 点击 `Contain` 行清除按钮，只清空 `Contain` 输入框和对应过滤状态。
- 点击 `Ignore` 行清除按钮，只清空 `Ignore` 输入框和对应过滤状态。
- 清除后重新计算 UI 层展示消息。
- 如果当前是 `Auto` 模式，清除后滚动到最新可见消息。
- 如果当前是 `Manual` 模式，清除后不自动滚动。

## 滚动切换设计

采用用户拖动阈值方案。

页面新增一组仅用于拖动检测的状态：

- 用户是否正在拖动消息列表。
- 用户开始拖动时的 `contentOffset.y`。

行为规则：

1. 用户开始拖动 table 时，记录当前 `contentOffset.y`。
2. 用户拖动过程中，计算当前 `contentOffset.y` 与起始值的绝对差值。
3. 如果差值大于 `30pt`，并且当前模式是 `Auto`，则自动切换到 `Manual`。
4. 切换时同步更新 `modeControl.selectedSegmentIndex`，让 UI 状态与内部滚动模式一致。
5. 切换后，本次拖动不需要重复切换。

这个判断只在用户真实拖动时执行。程序调用 `scrollToLatestVisibleMessage`、过滤刷新、初始加载、收到新消息后的自动滚动，都不会进入用户拖动判断。

## 边界行为

- 当前已经是 `Manual` 时，用户继续拖动不重复执行切换逻辑。
- 用户手动点击 `Auto` 后，保持现有行为：立即滚动到最新可见消息。
- 用户再次从 `Auto` 状态手动拖动超过 `30pt` 时，再自动切回 `Manual`。
- 如果列表内容不足以滚动，用户无法产生超过阈值的有效拖动，不触发切换。
- 过滤条件变化造成列表高度或 offset 改变时，不触发切换。
- Stop / Start、Clear、Share 触发的列表变化不触发切换。

## 实施范围

预计只修改：

- `SunSmart/Main/Space/Debug/SpaceDebugUARTViewController.swift`

不需要修改 SDK、本地化文件、资源文件或工程配置。

## 验证建议

- `Contain` 与 `Ignore` 两个清除按钮显示为 SF Symbols 关闭图标，不再显示文字 `x`。
- 输入框为空时，清除按钮仍然可见。
- 点击 `Contain` 清除按钮只清除 `Contain` 输入，不影响 `Ignore` 输入。
- 点击 `Ignore` 清除按钮只清除 `Ignore` 输入，不影响 `Contain` 输入。
- `Auto` 模式下，用户轻微拖动不超过 `30pt` 时仍保持 `Auto`。
- `Auto` 模式下，用户拖动超过 `30pt` 后自动切换到 `Manual`。
- 自动滚动到最新消息时不会误切换到 `Manual`。
- 点击 `Auto` 后仍会滚动到最新可见消息。
- Share 导出仍然使用 session 缓存中的全部消息，不受 UI 展示和滚动模式影响。
