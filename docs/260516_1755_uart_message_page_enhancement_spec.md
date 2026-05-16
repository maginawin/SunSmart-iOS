# UART 消息页功能增强规格

## 背景

当前 Debug 设备连接成功后，可以进入 UART 消息页接收并展示 UART 消息。现有页面的消息缓存保存在 `SpaceDebugUARTViewController` 内，退出 UART 页面后缓存会随页面释放；断线提示主要由上级设备 Debug 页面处理。

本次增强目标是让 UART 消息页更适合长时间真机调试：页面常亮、UART 页面接管断线提示和重连、消息缓存跟随设备 Debug 会话保留，并支持把完整缓存导出为 txt 文件。

## 目标

- UART 消息页显示期间保持屏幕常亮。
- 进入 UART 页面后，上级设备 Debug 页面不再处理设备断开事件，由 UART 页面接管。
- 设备意外断线时，UART 页面提示用户设备断开连接，可选择 `Cancel` 或 `Re-connect`。
- `Re-connect` 失败后继续提示，可再次选择 `Cancel` 或 `Re-connect`。
- 只要不退出设备 Debug 页面，UART 消息缓存不清除。
- 退出 UART 页面后停止接收 UART 消息，但保留已缓存消息；重新进入 UART 页面时先展示缓存，再继续接收新消息。
- 退出设备 Debug 页面后清除 UART 消息缓存。
- 文字过滤仅影响 UI 展示，不影响缓存和导出。
- 右上角增加分享按钮，分享时自动停止接收并导出完整缓存。
- 导出的 txt 文件包含设备基础信息和全部缓存消息。
- 缓存超过 `100000` 条后裁剪最旧消息，保留最新 `80000` 条，并记录被丢弃数量。

## 非目标

- 不做 UART 发送。
- 不做预设命令。
- 不做日志持久化到数据库或用户文档目录。
- 不做导入功能。
- 不改变 SDK 的 UART 服务发现和通知协议。
- 不在筛选状态下只导出可见消息，导出始终使用完整缓存。

## 方案对比

### 方案 A：缓存继续放在 UART 页面

优点：

- 改动最小。
- 页面内部逻辑直接。

缺点：

- 退出 UART 页面后缓存自然释放，不满足“重新进入先展示缓存”。
- 上级 Debug 页面无法在退出设备 Debug 页面时统一清理缓存。
- 导出需要额外从页面状态拼装，后续生命周期更容易混乱。

结论：不推荐。

### 方案 B：缓存上移到 `DebugBluetoothSession`

优点：

- 缓存生命周期天然跟随设备 Debug 会话。
- 退出 UART 页面时可以停止接收但保留缓存。
- 退出设备 Debug 页面时由 `finish()` 统一停止接收并清空缓存。
- UART 页面重新进入后可以直接读取缓存并展示。
- 分享导出能从同一份 session 缓存生成完整文件。

缺点：

- `DebugBluetoothSession` 需要承担少量 UART 缓存状态和裁剪逻辑。
- 需要明确页面接收状态与 session 缓存状态的边界。

结论：推荐。

### 方案 C：缓存落库或写文件

优点：

- App 被杀后仍可能保留日志。
- 超长调试场景容量更大。

缺点：

- 本需求明确退出设备 Debug 页面后清除缓存，持久化反而增加清理和隐私成本。
- 写入频繁 UART 消息会增加 I/O 风险和实现复杂度。

结论：不推荐。

## 推荐设计

采用方案 B：在 `DebugBluetoothSession` 中维护本次设备 Debug 会话的 UART 消息缓存、接收状态、裁剪计数和当前消息监听者。`SpaceDebugUARTViewController` 负责 UI 展示、过滤、滚动、Stop/Start、Clear、断线弹窗、重连和分享。

### 页面生命周期

- 进入 UART 页面：
  - 保存当前 `UIApplication.shared.isIdleTimerDisabled` 状态。
  - 设置 `UIApplication.shared.isIdleTimerDisabled = true`。
  - 读取 `DebugBluetoothSession` 中已有 UART 缓存并展示。
  - 若当前没有停止接收，则调用 session 开始接收 UART。
  - 临时接管 `session.onUnexpectedDisconnect`。
- 退出 UART 页面：
  - 恢复进入前的 `isIdleTimerDisabled` 状态。
  - 停止接收 UART 消息。
  - 保留 session 中已缓存消息。
  - 还原上级设备 Debug 页的断线处理。
- 退出设备 Debug 页面：
  - `DebugBluetoothSession.finish()` 停止扫描、停止 UART、断开 Mesh，并清空 UART 缓存和 dropped 计数。

### 断线与重连

进入 UART 页面后，上级设备 Debug 页面不直接响应断线事件。UART 页面收到断线后：

- 设置接收状态为停止。
- 更新 `Stop/Start` 按钮为 `Start`。
- 弹窗内容说明设备连接已断开。
- 弹窗按钮：
  - `Cancel`：只关闭弹窗，不返回页面，不清除缓存。
  - `Re-connect`：调用当前 `DebugBluetoothSession.reconnect`。
- 重连成功：
  - 重新检查或恢复 UART 接收。
  - 如果用户之前处于接收状态，则继续接收新消息。
  - 缓存继续保留。
- 重连失败：
  - 再次弹出同样提示，允许 `Cancel` 或 `Re-connect`。

### 缓存策略

缓存只在内存中保存，范围是当前设备 Debug 会话。

- `uartMessages`: 保存所有尚未被裁剪的 `SpaceDebugUARTMessage`。
- `droppedUARTMessageCount`: 保存因超过上限而丢弃的旧消息数量。
- 上限策略：
  - 每次追加新消息后，如果缓存数量 `> 100000`，删除最旧消息，保留最新 `80000` 条。
  - 每次裁剪时，`droppedUARTMessageCount += 删除数量`。
- `Clear`：
  - 清空当前缓存。
  - 清空 UI。
  - 将 `droppedUARTMessageCount` 重置为 `0`。
- `Stop`：
  - 停止接收新 UART 消息。
  - Stop 期间收到的消息不缓存。
- `Start`：
  - 恢复接收新 UART 消息。
  - 不补回 Stop 期间忽略的消息。

这个策略避免极端长时间调试时无限增长，同时不会在超过上限后每条消息都触发频繁删除。保留最新 `80000` 条更符合 Debug 场景中“最近日志更有价值”的实际使用方式。

### UI 筛选

文字过滤只作用于当前页面的可见列表：

- 用户输入前后空格会被忽略。
- 中间空格保留。
- 忽略大小写比较。
- 缓存仍记录所有收到且未被裁剪的消息。
- 分享导出不受筛选影响，始终导出完整缓存。

### 分享导出

右上角增加分享按钮，建议使用系统分享图标或现有 `menu_share` 资源。

点击分享时：

- 若当前正在接收 UART 消息，先自动 Stop。
- 从 session 缓存读取完整消息列表。
- 在 temporaryDirectory 生成 txt 文件。
- 使用 `UIActivityViewController` 调起 iOS 默认分享。
- iPad 上设置 `popoverPresentationController.barButtonItem` 或 `sourceView/sourceRect`。

如果缓存为空，仍允许导出，文件中包含设备基础信息和空日志区；也可以用 HUD 提示没有消息。推荐仍允许导出，便于保存设备信息。

### 导出文件内容

txt 文件使用 UTF-8，换行使用 `\n`。内容格式：

```text
UART Debug Log

Site Name: <site name>
Space Name: <space name>
Group Name: <group name or empty>
Device Name: <device name>
MAC Address: <mac address>
Company ID: <company id>
Product ID: <product id>
Address: <address>
Version Identifier: <version identifier>
Model: <model>
Device Type: <device type>
Firmware Version: <firmware version>
Dropped Messages: <count>
Generated At: <yyyy-MM-dd HH:mm:ss.SSS>

Messages:
[yyyy-MM-dd HH:mm:ss.SSS] <message text>
[yyyy-MM-dd HH:mm:ss.SSS] <message text>
```

设备基础信息来源与设备 Information 页面保持一致。当前 Debug 设备页已经能直接提供或间接取得以下字段：

- site name：`SiteData.load(siteId: space.siteId)?.name`
- space name：`space.name`
- group name：`item.node.group?.name`
- device name：`item.node.name`
- mac address：`item.node.macAddressResult ?? item.node.macAddress`
- company id：`item.node.companyIdentifier`
- product id：`item.node.productIdentifier`
- address：`item.node.primaryUnicastAddress`
- version identifier：优先使用现有节点版本标识字段；若项目内 Information 页面实际展示的是 `versionSEQ`，则保持同源。
- model：`item.node.modelName`
- device type：`item.category.title` 或 Information 页面同源字段。
- firmware version：`item.node.firmwareVersion`

实施前需要对照设备 Information 页确认 `version identifier`、`model`、`device type`、`firmware version` 的现有展示来源，避免导出字段和页面展示不一致。

### 导出文件名

推荐格式：

```text
<site name>-<space name>-<group name>-<device name>-uart-yyMMddHHmmss.txt
```

规则：

- `group name` 为空时跳过该段。
- 文件名中的 `/ \ : * ? " < > |` 和换行替换为 `_`。
- 连续空格压缩为单个空格。
- 每段前后空格 trim。
- 如果某段为空，跳过该段。
- 如果全部名称都为空，使用 `uart-log-yyMMddHHmmss.txt`。

相比原建议增加 `uart` 字段，可以在分享后的文件列表中更容易识别用途。

## 本地化

新增或复用以下 UI 文案，文档中 UI 标签保持英文：

- `Share`
- `Cancel`
- `Re-connect`
- `UART Debug Log`
- `The device connection was disconnected.`
- `Re-connect failed.`

现有中文本地化文件中的 `Auto`、`Manual`、`Stop`、`Start`、`Clear`、`Filter messages` 保持英文。

## 风险与处理

- **断线事件重复弹窗**：UART 页面需要用状态标记避免同一次断线显示多个弹窗。
- **上级页面断线处理冲突**：进入 UART 页面时替换 session 的断线处理，退出时恢复。避免上级页面同时弹窗或 pop。
- **重连成功但 UART notify 未恢复**：重连成功后需要重新启动 UART 接收流程，不假设旧 notify 仍有效。
- **缓存裁剪后用户误解日志完整性**：导出头部写入 `Dropped Messages`。
- **大列表刷新性能**：消息很多时应避免每次都全量 reload 可见列表。实施时优先使用追加行或在裁剪/筛选变化时全量刷新。
- **文件名非法字符**：统一清理文件名片段，避免写文件失败。
- **常亮状态污染其他页面**：记录进入前状态，退出时恢复，而不是简单设置为 `false`。

## 验收标准

- 进入 UART 页面后屏幕不会自动熄灭，退出后恢复原常亮状态。
- UART 页面打开时设备断线，只显示 UART 页面的 `[Cancel] / [Re-connect]` 弹窗，上级页不处理该断线弹窗。
- 点击 `Cancel` 仅关闭弹窗，当前页面和缓存保留。
- 点击 `Re-connect` 成功后可继续接收 UART 消息，已有缓存不清除。
- 点击 `Re-connect` 失败后继续提示，可再次重连。
- 退出 UART 页面后停止接收新消息，重新进入 UART 页面先展示原缓存。
- 退出设备 Debug 页面后再次进入同一设备 Debug 流程，旧 UART 缓存已清除。
- 文字过滤只改变可见消息，不影响缓存数量和导出内容。
- 缓存超过 `100000` 条后保留最新 `80000` 条，导出头部记录正确 dropped 数量。
- 点击分享时若正在接收会自动 Stop，并导出完整缓存。
- 导出 txt 文件头包含设备基础信息，消息按旧到新排列。
- 四个品牌 target 编译通过：`SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart`。
