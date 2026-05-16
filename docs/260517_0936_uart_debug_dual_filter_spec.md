# UART Debug 消息页双过滤规格

## 背景

当前 UART 消息页只有一个 `Filter messages` 输入框，只能展示包含指定文本的消息。真机调试时常见需求是同时保留某类关键消息，并排除某些噪声消息，因此需要把单输入框扩展为包含条件和排除条件两个输入框。

本次优化只调整 UART 消息页的 UI 层筛选能力，不改变 UART 消息接收、缓存、清除、分享导出、断线重连和 Stop / Start 的现有语义。

## 目标

- 将当前单个过滤输入框拆分为 `Contain text` 和 `Ignore text` 两个过滤输入框。
- 支持同时配置包含条件和排除条件。
- 保持过滤只影响页面展示，不影响缓存中的 UART 消息。
- 保持输入体验适合调试文本：ASCII 键盘，无联想、无纠正、无拼写检查。
- 为每个输入框提供永远可见的 `[x]` 清除按钮。

## 非目标

- 不新增日志级别过滤。
- 不新增正则表达式、通配符或多关键词语法。
- 不改变 UART 消息缓存策略。
- 不改变分享导出的内容范围。
- 不改变 Stop / Start、Clear、Auto / Manual 的既有行为。

## 页面结构

UART 页面顶部功能区保持现有第一行控制项，第二行开始改为两个紧凑过滤行。

UI 原型中的内容使用英文：

```text
Navigation Bar
┌────────────────────────────────────────┐
│ UART Messages                   Share  │
├────────────────────────────────────────┤
│ Auto | Manual  [ Stop ]    [ Clear ]   │
│ Contain [ message must contain     ][x]│
│ Ignore  [ message must not contain ][x]│
├────────────────────────────────────────┤
│ 2026-05-17 09:36:12.123                │
│ [ UART message text ]                  │
└────────────────────────────────────────┘
```

## 过滤规则

### 输入归一化

- `Contain text` 和 `Ignore text` 在参与过滤前都需要 trim 前后空白。
- 输入内容中间的空格保留。
- trim 后为空字符串表示该条件未配置。
- 匹配时忽略大小写。
- 当前代码已有的变音符忽略逻辑可以继续保留；因为输入要求为 ASCII，此行为不会影响主要调试路径。

### 展示判断

每条消息的展示必须满足以下规则：

- `Contain text` 非空、`Ignore text` 为空：消息内容必须包含 `Contain text`。
- `Contain text` 为空、`Ignore text` 非空：消息内容必须不包含 `Ignore text`。
- `Contain text` 和 `Ignore text` 都非空：消息内容必须包含 `Contain text`，并且必须不包含 `Ignore text`。
- 两者都为空：不过滤，展示全部缓存消息。

过滤只作用于页面的可见消息数组，不删除、不修改、不重排缓存中的 UART 消息。

## UI 行为

- 两个输入框都使用 ASCII 键盘。
- 两个输入框都关闭联想、自动纠正、拼写检查、smart quotes、smart dashes、smart insert/delete。
- 两个输入框都需要占位提示。
- `Contain text` 为空时，简体中文环境占位提示为 `消息必须包含`，英文环境占位提示为 `Message must contain`。
- `Ignore text` 为空时，简体中文环境占位提示为 `消息必须不包含`，英文环境占位提示为 `Message must not contain`。
- `[x]` 清除按钮永远展示，即使输入框为空也保持可见。
- 点击某个 `[x]` 只清除对应输入框，并立即刷新消息列表。
- 点击 `[x]` 不改变 Auto / Manual、Stop / Start、Clear、Share、缓存和接收状态。
- 点击 Auto、Manual、Stop、Start、Clear、Share 时继续收起键盘，沿用当前页面行为。
- 修改任一过滤条件后立即刷新列表。
- Auto 模式下，过滤条件变化后如果存在可见消息，应滚动到最新可见消息。
- Manual 模式下，过滤条件变化后只刷新列表，不主动滚动。

## 缓存与导出

- `Contain text` 和 `Ignore text` 都只作为 UI 层筛选条件。
- `DebugBluetoothSession` 中缓存的 UART 消息仍记录所有已接收消息。
- Stop 期间仍按既有逻辑不接收、不缓存消息。
- Clear 仍清除全部缓存消息，不只清除当前可见消息。
- Share 导出的 txt 文件仍包含缓存中的全部 UART 消息，不受当前 UI 过滤条件影响。

## 可行性结论

此优化可以完全在 App 侧 UART 页面完成，不需要修改 SDK，也不需要改变设备端 UART 协议。

推荐做法是把当前单个 `filterText` 状态扩展为 `containText` 和 `ignoreText` 两个状态，并集中在一个消息匹配函数中处理组合判断。这样改动范围小，能保持现有 `visibleMessages`、Auto 滚动、UITableView 刷新、缓存和导出路径的清晰边界。

不建议把过滤逻辑下沉到 `DebugBluetoothSession`，因为这会让缓存语义变复杂，也容易误影响分享导出内容。

## 验证范围

- 构建验证：至少验证 `SunSmart` Debug iOS 真机构建。
- 手动验证：
  - 两个输入框都能输入 ASCII 文本，且不出现联想和纠正。
  - `Contain text` 单独配置时，只展示包含该文本的消息。
  - `Ignore text` 单独配置时，只展示不包含该文本的消息。
  - 两者同时配置时，展示同时满足包含和排除条件的消息。
  - 两者都为空时展示全部缓存消息。
  - 输入前后空格被忽略，中间空格保留。
  - 匹配忽略大小写。
  - 点击任一 `[x]` 只清除对应输入框并刷新列表。
  - Auto 模式下过滤变化后滚动到最新可见消息。
  - Manual 模式下过滤变化后不主动滚动。
  - Share 导出内容包含全部缓存消息，不受 UI 过滤条件影响。
  - Clear 清除全部缓存消息，不只清除当前可见消息。
