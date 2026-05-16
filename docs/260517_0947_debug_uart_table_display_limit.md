# Debug UART Table 展示上限设计

## 背景

Debug / UART 消息页当前由 `SpaceDebugUARTViewController` 展示 `DebugBluetoothSession` 缓存的 UART 消息。Session 仍需要保留最多 100000 条消息，方便用户通过 Share 导出完整调试日志。

问题在于 table 的数据源目前会直接使用全量缓存。设备每秒大约发送 3 到 5 条消息，消息速率本身不高，但当缓存增长到数万甚至 100000 条后，table 行数和 `reloadData()` 成本会让页面明显卡顿。

## 目标

- UI 层最多展示最新 1000 条消息。
- 有过滤条件时，UI 层最多展示最新 1000 条符合条件的消息。
- 保留现有 100000 条 session 缓存能力。
- Share 导出继续包含 session 当前缓存内的全部消息，而不是 UI 展示的 1000 条。
- 不新增提示文案、本地化、资源或用户设置项。

## 非目标

- 不改变 UART 消息接收、蓝牙连接或重连逻辑。
- 不改变 `DebugBluetoothSession` 的缓存上限和 trim 策略。
- 不实现分页、加载更早消息或虚拟列表。
- 不重构 Debug flow 的其他页面。

## 方案

采用 UI 数据源限制方案，只在 `SpaceDebugUARTViewController` 内维护 table 展示快照。

Controller 区分两类数据：

- `messages`：页面持有的全量缓存快照，来源仍是 `session.cachedUARTMessages()`。
- `displayMessages`：table 实际展示的数据，最多 1000 条。

`UITableViewDataSource` 只读取 `displayMessages`。Share 按钮继续读取 `session.cachedUARTMessages()`，不读取 `displayMessages`。

## 数据流

进入页面时：

1. 从 `session.cachedUARTMessages()` 读取当前缓存到 `messages`。
2. 根据当前过滤词重建 `displayMessages`。
3. table reload 后最多展示 1000 行。

收到新 UART 消息时：

1. 更新 `messages` 快照，保持它代表 session 当前缓存。
2. 根据当前过滤词判断新消息是否应进入 `displayMessages`。
3. 无过滤时，新消息直接追加到 `displayMessages`。
4. 有过滤时，只有新消息匹配过滤词才追加到 `displayMessages`。
5. `displayMessages` 超过 1000 条时移除最旧展示项。
6. 新消息不匹配过滤词时，不刷新 table。

修改过滤词时：

1. 从 `messages` 末尾倒序扫描。
2. 找到最多 1000 条匹配消息后停止。
3. 将结果反转为时间正序，赋值给 `displayMessages`。
4. reload table，并在自动滚动模式下滚到最新展示消息。

清空消息时：

1. 调用 `session.clearUARTMessages()`。
2. 清空 `messages`。
3. 清空 `displayMessages`。
4. reload table。

分享日志时：

1. 若正在接收消息，沿用当前逻辑先停止接收。
2. 读取 `session.cachedUARTMessages()`。
3. 使用 `SpaceDebugUARTLogExporter` 导出完整缓存。

## 性能影响

常态接收每秒 3 到 5 条消息时，UI 处理成本保持稳定：

- table 行数最多 1000。
- 无过滤时每条新消息只需要追加 1 条展示数据，并在超过上限时移除最旧 1 条。
- 有过滤时每条新消息只做一次字符串匹配；不匹配时不刷新 table。
- 只有用户修改过滤词时才扫描最多 100000 条缓存。该操作由用户输入触发，频率低，并且扫描找到 1000 条匹配项后即可停止。

内存方面会额外持有最多 1000 条 `SpaceDebugUARTMessage` 的展示数组，远小于已有 100000 条缓存规模。

## 边界行为

- `displayMessages` 固定最多 1000 条。
- 无过滤时展示最新 1000 条消息。
- 有过滤时展示最新 1000 条匹配消息。
- 过滤无结果时 table 为空。
- 自动滚动只滚到 `displayMessages` 的最后一行。
- session 超过 100000 条触发 trim 后，Share 仍导出 session 当前缓存内的全部消息，并保留现有 `Dropped Messages` 字段。

## 测试建议

- 无过滤、缓存超过 1000 条时，table 最多展示最新 1000 条。
- 有过滤、匹配结果超过 1000 条时，table 最多展示最新 1000 条匹配消息。
- 有过滤、新消息不匹配时，不触发 table 数据刷新。
- Share 导出的消息数量来自 `session.cachedUARTMessages()`，不是 `displayMessages`。
- 清空后 session 缓存、页面快照和 table 展示都为空。

## 实施范围

预计只修改：

- `SunSmart/Main/Space/Debug/SpaceDebugUARTViewController.swift`

若实现时发现需要增加小型 helper，应保持在该文件内，避免把 UI 展示策略下沉到 `DebugBluetoothSession`。
