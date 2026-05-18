# 全局 Debug UART 接收与缓存设计

## 背景

当前 Debug UART 消息接收、缓存、分享和清理主要绑定在 `DebugBluetoothSession` 与 `SpaceDebugUARTViewController` 的页面生命周期中。进入 UART 消息页会主动开始接收，分享前会停止接收，退出 UART 页或结束 Debug flow 时也会停止并清理缓存。

新的目标是把 UART 调试能力从页面生命周期中解耦出来：只要用户在当前 Site 运行期内启用了 UART 接收，并且 App 连接到支持 UART 的 Proxy Node，就持续接收并按设备缓存消息。Debug 页、UART 页和回到 Space 后都使用同一个接收状态与缓存。

## 目标

- UART 接收是 App 运行期内、当前 Site 作用域下的全局调试功能。
- 接收开关默认关闭，Debug 列表页头部开关与 UART 消息页 `Start` / `Stop` 共享同一状态。
- 进入 UART 消息页不主动 Start，只根据全局接收状态执行。
- 点击 Share 不主动 Stop，分享点击前当前设备的 UART 缓存快照。
- 退出 UART 消息页、退出 Debug 页、回到 Space 后，若全局接收开启，仍持续按当前 Proxy 接收 UART 消息。
- 退出 Site 到站点列表或切换 Site 时，停止 UART 通知、关闭接收开关并清空全部 UART 缓存。
- App 关闭时清空内存缓存并关闭接收。
- UART 消息按设备分类缓存，缓存 key 为 `siteId + spaceId + node address`。
- 单设备最多缓存 `100000` 条 UART 消息。
- 最多保留 30 个设备的 UART 缓存；第 31 个新设备真正开始缓存时，按最近一次活跃时间淘汰最久未活跃设备。
- Debug 列表页每个有 UART 缓存的设备行展示分享按钮，使用 SF Symbol `square.and.arrow.up`。
- UART 消息页右上角分享按钮也改为 SF Symbol `square.and.arrow.up`。
- 点击未连接但已扫描到的设备行时，先确认再切换 Proxy，避免误触分享区域导致连接切换。

## 非目标

- 不做 UART 发送。
- 不做日志持久化到数据库或用户文档目录。
- 不改变 SDK 的 UART 服务 UUID、发现和通知协议。
- 不改变正常控制页的 Mesh 自动连接策略。
- 不为未扫描到的设备发起连接尝试。
- 不合并多个设备的 UART 日志分享。

## 推荐方案

采用新增全局 UART Debug 管理层的方案。

新增 `SpaceDebugUARTManager` 作为 Debug UART 的唯一状态源。它负责全局接收意图、当前 Site 作用域、按设备缓存、当前 Proxy 的 UART 支持状态、通知订阅和页面观察回调。

`DebugBluetoothSession` 保留扫描、连接、断线、重连等职责，不再持有 UART 消息数组，也不在 `finish()` 中停止全局 UART 接收或清空 UART 缓存。它只在 Proxy 连接成功、重连成功、当前 Proxy 变化时触发 manager 重新评估当前 Proxy。

这种边界把蓝牙连接生命周期和 UART 日志生命周期分开，避免退出 UART 页或 Debug 页时误停接收。

## 核心状态

`SpaceDebugUARTManager` 维护以下运行期状态：

- `isReceiveEnabled`：用户是否希望接收 UART 消息。默认 `false`，Debug 页开关和 UART 页 `Start` / `Stop` 读写同一个值。
- `activeSiteId`：当前 UART 调试作用域的 Site。
- `activeSpaceId`：当前可评估 Proxy 所属 Space。缓存 key 仍包含每条消息对应的 `spaceId`。
- `currentNodeKey`：当前 Proxy Node 对应的缓存 key。
- `currentSupportState`：当前 Proxy 的 UART 支持状态。
- `currentNotificationState`：当前 Proxy 是否已开始 UART 通知。
- `buffers`：按 `siteId + spaceId + node address` 保存的设备缓存。
- `observers`：页面订阅者，用于刷新 Debug 列表、UART 页和分享按钮状态。

每个设备缓存包含：

- `messages`：最多 `100000` 条 `SpaceDebugUARTMessage`。
- `droppedMessageCount`：因超过单设备上限被丢弃的旧消息数量。
- `lastActiveAt`：最近一次活跃时间。
- `nodeSnapshot`：用于分享导出时构建设备基础信息的节点快照或必要元数据。

缓存懒创建。只有设备真正开始缓存 UART 消息时才创建缓存槽位；Site 内未收到 UART 的设备不会预分配数组。

## 缓存策略

缓存 key 使用 `siteId + spaceId + node address`。这样可以避免同一 Site 下不同 Space 子网的节点地址冲突，也符合当前 Debug 从 Space 进入的语义。

单设备缓存上限为 `100000` 条。追加消息后如果超过上限，删除最旧消息并更新 `droppedMessageCount`。具体裁剪目标可沿用现有实现中的批量裁剪策略，避免超过上限后每条消息都触发大数组移动。

设备缓存数量上限为 30 个。淘汰规则为 LRU：

1. 连接到支持 UART 的新 Proxy Node，但 `isReceiveEnabled == false` 时，不创建缓存槽位，不触发淘汰。
2. 后续用户启用接收时，如果当前 Proxy 支持 UART 且该设备没有缓存，先确保缓存槽位可用。
3. 如果已有 30 个其它设备缓存，则删除 `lastActiveAt` 最早的设备缓存与 dropped count。
4. 创建当前设备缓存并开始接收。
5. 连接已有缓存设备并开始或恢复接收时，只更新该设备 `lastActiveAt`，不淘汰其它设备。
6. 收到 UART 消息时更新当前设备 `lastActiveAt`。

`Clear` 只清当前连接 Proxy Node 对应设备的缓存和 dropped count，不影响其它设备缓存，也不改变 `isReceiveEnabled`。

## Proxy 评估流程

manager 提供 `evaluateCurrentProxy(space:)` 或等价接口，由 Debug flow、Space 自动连接回调、Proxy 连接状态观察触发。

评估规则：

1. 无 Proxy：停止当前 UART 通知，保留接收开关和所有缓存。
2. 有 Proxy 但不属于当前 Site / Space：不缓存该设备，必要时停止当前 UART 通知。
3. 有 Proxy 且属于当前 Space：检查 UART 支持状态。
4. 支持 UART 且 `isReceiveEnabled == true`：确保当前设备缓存存在，必要时按 LRU 淘汰，然后开始 UART 通知并缓存消息。
5. 支持 UART 但 `isReceiveEnabled == false`：记录支持状态，但不创建缓存、不淘汰、不开始通知。
6. 不支持 UART：保持接收开关状态，不创建缓存，不缓存消息。

如果用户开启了接收，但当前 Proxy 不支持 UART，开关仍保持开启。它表达的是用户的全局接收意图；后续切换或自动连接到支持 UART 的 Proxy Node 时，再自动开始接收。

## 页面交互

### Debug 列表页

Debug 列表页顶部在固定摘要区域附近增加“接收 UART 消息”开关，默认关闭。开关读写 `SpaceDebugUARTManager.isReceiveEnabled`。

- 开启：立即评估当前 Proxy。若当前 Proxy 支持 UART，则开始接收并缓存；若不支持或未连接，开关保持开启并等待后续 Proxy 连接。
- 关闭：停止当前 Proxy 的 UART 通知；保留已有缓存。
- 离开 Debug 页回 Space：不关闭开关，不清缓存；Space 自动连接 Proxy 成功后继续按开关状态评估 UART 接收。

设备行新增分享按钮：

- 有缓存的设备展示 SF Symbol `square.and.arrow.up`。
- 没有缓存的设备不展示分享按钮。
- 点击分享按钮只分享该设备缓存，不触发行选择或连接切换。
- 分享使用该设备缓存的当前快照，不停止 UART 接收。

设备行点击规则：

- 点击已连接 Proxy Node 行：不弹确认，直接进入 Debug 设备页。
- 点击未连接但已扫描到的设备行：先弹确认框，确认后才停止扫描、断开当前 Proxy 并连接目标设备。
- 点击未扫描到设备行：不可点击，不发起连接。
- 取消确认时不停止扫描、不切换连接，列表保持当前状态。

### UART 消息页

UART 消息页不再拥有独立接收状态，只展示和修改 manager 的全局接收状态。

- 进入页面不主动 Start，只根据 `isReceiveEnabled` 和当前 Proxy 状态刷新按钮。
- `Start` / `Stop` 等价于修改 Debug 列表页头部开关，两边联动。
- 页面退出不 Stop，不清缓存。
- 点击 Share 不 Stop，只对当前设备缓存做一次快照并分享。
- `Clear` 只清当前设备缓存和 dropped count。
- 页面仍只展示当前设备缓存的最多 2000 条窗口，过滤只影响展示，不影响缓存和分享。
- 右上角分享按钮使用 SF Symbol `square.and.arrow.up`。

## 生命周期

- 进入 UART 页：展示当前设备缓存，根据全局接收状态刷新 UI，不主动改变接收状态。
- 退出 UART 页：不停止 UART，不清缓存，只取消页面观察回调。
- 退出 Debug 页回 Space：不停止 UART，不清缓存；恢复 Space 自动连接 Proxy 逻辑。
- 退出 Space 回 Site：不停止 UART，不清缓存。
- 返回站点列表或切换 Site：停止 UART 通知，关闭接收开关，清空所有 UART 缓存。
- App 关闭：内存自然释放，同时在生命周期通知中主动 stop / clear，避免蓝牙通知残留。

## 分享导出

分享始终基于单设备缓存快照。

Debug 列表页分享时，需要从设备行对应 key 读取缓存和 dropped count，并使用该设备 metadata 生成导出上下文。UART 消息页分享时，读取当前设备 key 的缓存。

分享不影响接收状态。如果分享期间又收到新消息，新的消息可以进入缓存，但不会进入本次已经生成的分享文件。

如果设备没有缓存，Debug 列表页不展示分享按钮。UART 消息页在无缓存时仍可显示分享按钮，但分享内容只包含设备基础信息和空日志区，或提示无可分享消息；实现时优先保持现有可导出行为。

## 错误处理

UART 服务不支持：

- 保持接收开关状态。
- 不创建缓存，不展示该设备分享按钮。
- UART 消息页展示当前设备不支持 UART 的提示。

Proxy 断开：

- 停止当前 UART 通知状态。
- 保留全局接收开关与所有缓存。
- Debug 页内不自动连接新的 Proxy；退出 Debug 后由 Space 自动连接逻辑恢复。
- Space 自动连接成功后，manager 重新评估当前 Proxy。

连接目标失败：

- 不改变全局 UART 接收开关。
- 如果旧 Proxy 已在手动切换中断开，不为了 UART 自动恢复旧 Proxy。
- 不为失败目标创建设备缓存。

分享失败：

- 使用现有导出失败 HUD。
- 不停止接收，不清缓存。

## 验证范围

功能验证：

- Debug 列表页开关默认关闭。
- Debug 列表页开关开启后，当前支持 UART 的 Proxy 开始接收并缓存。
- 当前 Proxy 不支持 UART 时，开关保持开启但不创建缓存。
- 第 31 个支持 UART 的新设备在接收开启并真正开始缓存时，淘汰 `lastActiveAt` 最早的设备缓存。
- 第 31 个支持 UART 的新设备在接收关闭时不淘汰；后续启用接收时再淘汰。
- UART 页 `Start` / `Stop` 与 Debug 列表页开关双向同步。
- 进入 UART 页不主动 Start，只按全局接收状态执行。
- 点击 Share 不 Stop，分享内容来自点击前当前设备缓存快照。
- UART 页退出后仍持续接收。
- Debug 页退出回 Space 后仍按开关状态持续接收。
- Space 自动连接 Proxy 成功后，若开关开启且 Proxy 支持 UART，则自动接收。
- Clear 只清当前连接 Proxy Node 的缓存。
- Debug 列表页有缓存设备展示分享按钮，无缓存设备不展示。
- 点击分享按钮不触发行连接。
- 点击未连接但已扫描到的设备行会弹连接确认；取消不切换，确认才连接。
- 返回站点列表或切换 Site 后，停止接收、关闭开关、清空缓存。

编译验证：

- 执行 `SunSmart` target 的 Debug iphoneos 编译。
- 如果修改本地化字符串，需要同步检查中英文文案。
- 如果改动公共 Debug 文件，需关注共享品牌 target 的编译影响。

## 实施约束

- 保持改动聚焦，不重构正常控制页自动连接机制。
- 不把 UART 缓存落库。
- 不让页面对象持有全局接收生命周期。
- 不在未扫描到设备时尝试连接。
- 不因为分享、页面退出、Debug flow 结束而主动停止全局 UART 接收。
- 不在 Git commit 中添加 codex 相关行。
