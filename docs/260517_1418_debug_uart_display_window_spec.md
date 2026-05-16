# Debug UART UI 展示窗口优化设计

## 背景

当前 Debug / UART 消息页已经把会话缓存和 UI 展示数组分开：

- `DebugBluetoothSession` 负责缓存 UART 消息，缓存用于重新进入 UART 页面、Clear、Share 导出等行为。
- `SpaceDebugUARTViewController` 使用 `displayMessages` 作为 table view 的 UI 数据源。
- 当前 UI 层最多展示 `1000` 条消息，超过后会删除最旧消息，使 table view 保持在展示上限内。

在高频 UART 消息场景下，如果用户处于 `Manual` 模式查看旧消息，新消息仍会持续进入 UI 展示数组并触发 table view 刷新。虽然 `Manual` 模式不会自动滚动到底部，但频繁裁剪旧消息和刷新 UI 仍会影响查看体验。

## 目标

- 将 UART 消息页 UI 层最多展示数量从 `1000` 条提升到 `2000` 条。
- 当 UI 展示数组超过 `2000` 条后，一次性删除最旧的 `500` 条，使展示数组回到约 `1500` 条。
- 降低达到展示上限后的频繁裁剪频率。
- 保持现有 UART 接收、缓存、过滤、分享导出、Stop / Start、Clear、Auto / Manual 行为不变。

## 非目标

- 不修改 Session 级 UART 缓存上限。
- 不修改分享导出的消息来源，Share 仍导出 Session 缓存中的完整可用消息。
- 不改变 Contain / Ignore 过滤规则。
- 不改变 `Manual` 模式下是否刷新 table view 的现有语义。
- 不新增批量刷新、节流刷新、未读计数或冻结列表能力。

## 设计方案

采用 UI 展示层高低水位裁剪方案：

- 展示上限：`2000` 条。
- 每次裁剪数量：`500` 条。
- 收到新消息且新消息符合当前 UI 过滤条件时，先追加到 `displayMessages`。
- 如果追加后数量超过 `2000` 条，则从头部删除最旧的 `500` 条。
- 重新构建展示数组时，从 Session 缓存中倒序扫描，最多取最新的 `2000` 条匹配消息。

这个方案只影响 table view 当前持有的 UI 数据，不影响后台缓存。用户切换过滤条件、重新进入 UART 页面、分享导出时，仍以 Session 缓存作为真实数据来源。

## 行为说明

### Auto

- 新消息符合过滤条件时追加到 UI 展示数组。
- 如展示数组超过 `2000` 条，则一次性删除最旧的 `500` 条。
- 继续按现有逻辑自动滚动到最新可见消息。

### Manual

- 新消息符合过滤条件时追加到 UI 展示数组。
- 如展示数组超过 `2000` 条，则一次性删除最旧的 `500` 条。
- 继续按现有逻辑刷新 table view，但不自动滚动到底部。

这意味着方案 A 可以减少超过上限后的裁剪频率，但不会完全避免 `Manual` 模式下的新消息刷新 UI。

### 过滤

- Contain / Ignore 仍只影响 UI 展示层。
- 修改过滤条件后，重新从 Session 缓存中取最新 `2000` 条匹配消息。
- 过滤条件不影响 Session 缓存和分享导出。

### Share

- Share 仍使用 `session.cachedUARTMessages()`。
- UI 展示窗口为 `2000 / 1500` 不影响 txt 文件中的消息范围。

## 可行性

当前代码已经具备所需边界：

- `messages` 保存页面读取到的 Session 缓存快照。
- `displayMessages` 是 table view 的唯一数据源。
- `rebuildDisplayMessages()` 已经按 UI 展示上限重建展示数组。
- `appendDisplayMessageIfNeeded(_:)` 已经负责新消息追加和超过上限后的裁剪。

因此本次只需要在 `SpaceDebugUARTViewController` 中调整 UI 展示窗口常量和裁剪逻辑，不需要修改 SDK、Session 缓存、导出 helper 或本地化文案。

## 验证计划

- 静态检查 `visibleMessageLimit` 已调整为 `2000`。
- 静态检查追加新消息后超过上限时删除最旧 `500` 条，而不是每次只删除超出的条数。
- 构建 `SunSmart` Debug iOS target，确认无编译错误。
- 真机验证高频 UART 消息：
  - 无过滤时 UI 最多展示约 `1500` 到 `2000` 条之间的最新消息。
  - Auto 模式仍会滚动到最新消息。
  - Manual 模式仍不自动滚动到底部。
  - Share 导出仍包含 Session 缓存中的完整可用消息，而不是只导出 UI 展示窗口。
