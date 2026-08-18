# Gateway Delete 服务器优先最终决策

## 最终结论

Gateway Delete 最终采用服务器优先顺序：先调用服务器 `gatewayDelete`，服务器明确成功后才尝试蓝牙 Reset。

该决策替代此前“蓝牙 Reset 优先”的方案。后续开发不需要为 NordicSigMeshSDK 增加延迟删除 Node 的 Reset 模式，因为 SDK 自动删除本地 Node 只会发生在服务器删除已经确认成功之后。

本轮只确认流程，不修改业务代码。

## 最终状态链

### 删除前权限检查

- Owner 可继续。
- 非 Owner 必须对服务器当前返回的全部 Associated Spaces 都有 Editor 权限。
- 权限预检失败时，不调用 `gatewayDelete`，不发送蓝牙 Reset，不修改本地数据。
- 服务器仍在 `gatewayDelete` 中做最终权限裁决。

### 服务器删除

对所有 Gateway 统一调用 `gatewayDelete`，不再根据本地 `mqttServerInfo` 或 `lastUploadCloudTimestamp` 绕过服务器。

服务器 `gatewayDelete` 负责在同一事务中：

- 删除 Gateway。
- 清空该 Gateway 的全部 Associated Spaces。
- Gateway 已不存在时按幂等成功处理。

结果处理：

- 成功：记录本次删除会话的 `serverDeletionConfirmed`，然后开始蓝牙 Reset。
- 明确失败或 30 秒无最终成功：不发送蓝牙 Reset、不清除本地数据，使用 `ToastStatusView` 的 `.siteUpdate` 失败样式显示 `Failed to delete gateway from server`。
- 超时后的迟到回调不得继续触发蓝牙 Reset；用户重试时依赖服务器幂等性重新确认成功。

### 蓝牙 Reset

只有 `serverDeletionConfirmed` 成立才允许调用蓝牙 Reset。

- Reset 成功：按现有永久删除成功路径清理 Node 扩展数据、GatewayModel、本地 Mesh 数据，关闭 Gateway 页面并刷新 Site。
- Reset 失败或超时：显示现有 FORCE DELETE 确认弹窗。

### FORCE DELETE

进入该弹窗时，删除会话必须已经持有服务器成功确认，因此不再调用 `gatewayDelete` 或 `/gateway/unbind`。

- CANCEL：关闭弹窗，不提交本地永久删除。
- FORCE DELETE：提交本地永久删除并从 Mesh Network 移除 Node，然后关闭页面、刷新 Site。

FORCE DELETE 的通用执行入口仍应显式校验 `serverDeletionConfirmed`，避免未来其他调用路径绕过服务器前置条件。

## 本地数据清理时机

虽然服务器先删除，但不应像当前代码一样在蓝牙 Reset 前立即清空并保存本地 MQTT、Associated Spaces 和上传时间戳。推荐将所有永久本地清理统一延后到：

- 蓝牙 Reset 成功，或
- 用户确认 FORCE DELETE。

原因如下：

- 蓝牙失败进入确认弹窗时，页面仍需要稳定的删除会话上下文。
- 用户选择 CANCEL 时，不能触发普通 Gateway 配置同步重新注册已被服务器删除的 Gateway。
- 统一提交点可以避免 GatewayModel、Node、Schedule 引用和 Mesh Network 处于不同步的半删除状态。

## CANCEL 后的状态

服务器已删除成功但蓝牙 Reset 失败时，如果用户选择 CANCEL：

- 不做本地永久删除。
- 不发送 `siteGatewayDataChanged`，避免触发 `syncGateway` 把 Gateway 重新注册到服务器。
- 本地 Gateway 暂时保留，供用户再次发起删除。
- 再次删除时仍先调用幂等 `gatewayDelete`；服务器返回成功后重试蓝牙 Reset。

本地 Associated Spaces 在此时可能比服务器状态旧，但不能通过普通云同步上传。后续页面刷新应避免把该删除中的 Gateway 当作普通待上传 Gateway；开发计划中需设计删除会话或待删除状态的生命周期。

## 与当前代码的差异

当前已注册 Gateway 分支已经是服务器先于蓝牙，但仍需修正以下行为：

1. 删除本地“已注册/未注册”分支，所有 Gateway 都先调用幂等 `gatewayDelete`。
2. 服务器失败时改用固定的 Site Update Toast，而不是显示 `error.localizedDescription` 的通用 HUD。
3. 服务器成功后不立即清空并保存本地 MQTT、Associated Spaces 和上传时间戳。
4. 蓝牙失败选择 CANCEL 时，不发送会触发 `syncGateway` 的 `siteGatewayDataChanged` 通知。
5. FORCE DELETE 只负责本地永久清理，但必须由服务器已确认的删除会话触发。
6. 服务器成功前不能显示 Done、不能关闭页面、不能提交任何永久本地删除。

## 独立 Force Clear Spaces 不变

右上角独立 `Force clear spaces` 继续使用：

- `POST /sitespace/sapce/gateway/unbind`
- 只传 `gatewayId` 与 `userId`。
- 请求体中不包含 `spaceId`。

该操作只清空服务器 Associated Spaces，不删除 Gateway。服务器成功后才清空本地 Associated Spaces；失败或 30 秒超时不修改本地。

Gateway Delete 路径不额外调用该接口，因为 `gatewayDelete` 已负责清空全部 Associated Spaces。

## 后续开发验证边界

- 权限预检失败时没有服务器删除和蓝牙 Reset。
- `gatewayDelete` 失败/超时时没有蓝牙 Reset和本地变化。
- `gatewayDelete` 成功后才发送 Config Node Reset。
- Reset 成功后完成本地永久删除。
- Reset 失败 + CANCEL：保留本地且不重新注册服务器 Gateway。
- Reset 失败 + FORCE DELETE：只提交本地删除，不重复请求服务器。
- Gateway 不存在时 `gatewayDelete` 幂等成功并继续蓝牙 Reset。
- 服务器成功前不显示最终 Done。
- 删除会话期间不进入普通 `syncGateway` 上传路径。
- 独立 Force Clear 的请求体严格不包含 `spaceId`。

## 当前确认状态

服务器优先顺序、幂等语义、失败 Toast、30 秒上限和 Associated Spaces 清理职责均已确认。后续开发计划应以本文件为最终依据；此前蓝牙优先方案不再实施。
