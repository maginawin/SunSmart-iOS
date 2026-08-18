# Gateway Delete 顺序修正确认与技术边界

> 状态：已被 `260817_1820_gateway_delete_server_first_final_decision.md` 替代。本文件仅保留“蓝牙 Reset 优先”方案的历史分析，不作为后续开发依据。

## 修正后的产品流程

本次修正替代此前“先 gatewayDelete、再蓝牙 Reset”的删除顺序。最终确认的 Gateway Delete 流程为：

1. 先尝试蓝牙 Reset。
2. 蓝牙 Reset 成功后，调用服务器 `gatewayDelete`；服务器同时删除 Gateway 并清空全部 Associated Spaces。
3. `gatewayDelete` 成功后，才清除 App 本地 Gateway 数据、Mesh Node 和业务扩展数据，并完成现有页面关闭及 Site 刷新流程。
4. `gatewayDelete` 失败或 30 秒无最终成功时，不提交 App 本地清理，使用 `ToastStatusView` 的 `.siteUpdate` 失败样式显示 `Failed to delete gateway from server`。
5. 蓝牙 Reset 失败或超时，展示现有 FORCE DELETE 确认弹窗。
6. 用户取消 FORCE DELETE：不调用 `gatewayDelete`，不清除服务器或本地数据。
7. 用户选择 FORCE DELETE：调用 `gatewayDelete`；成功后提交本地永久删除，失败或超时则保留本地数据并显示相同失败 Toast。

服务器已确认 `gatewayDelete` 对不存在的 Gateway 按幂等成功处理，因此 App 可以对所有 Gateway 统一调用服务器，不再依赖 `mqttServerInfo` 或 `lastUploadCloudTimestamp` 判断是否跳过服务器。

## 方案可行性结论

产品状态链完整、合理，可以作为后续开发的最终业务边界。但当前 App 与 SDK 不能直接按该顺序复用，必须拆分“蓝牙 Reset 成功”和“本地永久删除提交”。

本轮只确认分析，不修改业务代码。

## 当前实现与新要求的关键冲突

### SDK 在 Reset Status 到达时自动删除本地 Node

当前 `MeshAPI.resetNodes` 发送 `ConfigNodeReset`，默认每个 Node 等待 10 秒。收到 `ConfigNodeResetStatus` 后，SDK 的 `ConfigurationClientHandler` 会立即调用 `meshNetwork.remove(node:)`。

也就是说，当前的“蓝牙 Reset 成功”不仅证明设备响应，还会直接从本地 Mesh Network / 数据库移除 Node。此动作发生在 App 有机会调用服务器 `gatewayDelete` 之前。

因此若保持现有 SDK 行为：

- 蓝牙 Reset 成功。
- 本地 Node 已被 SDK 删除。
- 随后 `gatewayDelete` 失败。
- App 已无法满足“不清除本地数据”。

### App 通用删除还会立即提交业务扩展清理

`DeviceProtocol.deleteNodes` 收到蓝牙成功列表后会立即调用 `DevicePermanentDeletionContext.commit()`，清理 Schedule 引用、GatewayModel 等业务扩展数据，并提前显示 Done。

FORCE DELETE 按钮当前也会直接执行永久清理与 `meshNetwork.remove(node:)`，没有服务器前置步骤。

因此 Gateway 后续不能继续直接使用当前通用删除完成语义，否则服务器失败前本地数据已经被删除。

## 必需的技术调整方向

### 1. SDK 支持延迟本地 Node 删除

Gateway Reset 需要一种受控模式：

- 仍发送标准 `ConfigNodeReset`。
- 仍等待并返回 `ConfigNodeResetStatus`，用于判断蓝牙 Reset 成功。
- 收到 Status 时不自动执行 `meshNetwork.remove(node:)`。
- App 在 `gatewayDelete` 成功后显式提交本地 Node 删除。

推荐在 NordicSigMeshSDK 增加作用域明确的 Reset 选项或专用 API，默认行为保持不变，仅 Gateway Delete 使用延迟删除模式。不能全局取消 `ConfigNodeResetStatus` 的自动删除，否则会改变 Light、Switch、Fire Alarm 等所有设备的现有删除语义。

修改 SDK 前需按工程规则把 `NordicSigMeshSDK` Swift Package 切换到本地路径 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk`，并检查所有引用 SDK 的品牌 target。

不建议在服务器失败后重新插入 Node 快照来补偿，因为设备已经物理 Reset，恢复一份旧的 Mesh Node 数据既不代表设备仍在网，也容易遗漏数据库和业务引用。

### 2. Gateway 专用删除会话

建议为 Gateway 建立独立删除协调器，至少维护以下状态：

- 等待蓝牙 Reset。
- 蓝牙 Reset 已确认，等待服务器删除。
- 蓝牙 Reset 失败，等待用户 Cancel / FORCE DELETE。
- FORCE DELETE 等待服务器删除。
- 服务器删除已确认，正在提交本地永久删除。
- 失败或完成终态。

协调器需要保证服务器成功、失败、30 秒超时、页面退出和迟到回调只能完成一次。

### 3. 统一的本地永久删除提交点

只有 `gatewayDelete` 成功后才能执行：

- `DevicePermanentDeletionContext.commit()`。
- 从 Mesh Network 删除 Node。
- 删除 `GatewayModel` 数据库记录。
- 清理本地 MQTT、Associated Spaces 及其他 Gateway 扩展数据。
- 关闭 Gateway 页面。
- 发送 Site 状态刷新通知。
- 显示最终删除成功反馈。

不能在蓝牙 Reset 成功时提前显示 Done，也不能在服务器结果前发送会触发 `syncGateway` 的普通 Gateway 数据变更通知。

## 两条最终状态链

### 正常 Delete

权限预检 → 蓝牙 Reset → 收到 Reset Status但保留本地 Node → `gatewayDelete` → 服务器成功 → 提交全部本地永久删除 → 关闭页面并刷新 Site。

- 蓝牙失败/超时：进入 FORCE DELETE 弹窗。
- 服务器失败/超时：保留本地数据，显示 `Failed to delete gateway from server`。

### FORCE DELETE

蓝牙失败/超时 → FORCE DELETE 弹窗。

- CANCEL：关闭弹窗，不请求服务器，不修改本地。
- FORCE DELETE：调用 `gatewayDelete` → 服务器成功 → 提交全部本地永久删除。
- 服务器失败/超时：保留本地，显示失败 Toast。

FORCE DELETE 不再尝试第二次蓝牙 Reset，也不需要额外调用 `/gateway/unbind`，因为 `gatewayDelete` 已负责清除全部 Associated Spaces。

## 权限前置边界

虽然删除动作顺序改为蓝牙优先，但非 Owner 的 Associated Spaces 权限预检仍应放在蓝牙 Reset 之前。否则 App 可能先把设备物理 Reset，随后才因服务器权限不足无法删除服务器记录。

服务器仍是最终权限裁决者；预检到 `gatewayDelete` 之间若权限发生变化，服务器可以拒绝，此时按服务器删除失败处理并保留本地数据。设备若已经 Reset，将成为本地保留但实际离线的待清理记录，用户可重试 Delete，后续通过幂等 `gatewayDelete` 完成清理。

## 服务器失败后的已知状态

在正常 Delete 中，蓝牙 Reset 成功但 `gatewayDelete` 失败时：

- 设备已经恢复出网，无法继续作为原 Mesh Node 工作。
- 服务器 Gateway 和 Associated Spaces 仍保留。
- App 按产品要求保留本地 Node 与 GatewayModel，便于重试服务器删除。

这是“设备优先、服务器其次”无法避免的跨系统中间状态，不是本地回滚能够恢复的。后续 UI 和重试逻辑应避免把该本地记录展示为仍可正常连接，并确保不会通过普通 `syncGateway` 自动重新上传或覆盖删除状态。

## 超时边界

- 蓝牙 Reset 当前 SDK 默认单 Node 超时约 10 秒，超时进入 FORCE DELETE 选择。
- `gatewayDelete` 按已确认规则最多等待 30 秒；明确网络/API 失败可以提前结束。
- 超时后忽略迟到回调。由于服务器接口幂等，用户重试时可安全再次调用；如果前一次请求实际上已在服务器成功，重试仍应返回成功并允许 App 完成本地清理。

## 已确认文案与 UI

- 服务器删除失败：`Failed to delete gateway from server`
- 使用 `ToastStatusView` 的 `.siteUpdate` 失败样式。
- 新增英文和简体中文本地化，建议中文为：`从服务器删除网关失败`。

## 后续开发计划必须覆盖的验证

- Reset Status 到达但服务器失败时，本地 Node、GatewayModel 和业务扩展数据均仍存在。
- 服务器成功前不显示 Done、不关闭页面、不触发 Site 删除完成通知。
- 正常 Reset 成功 + 服务器成功。
- 正常 Reset 成功 + 服务器失败/30 秒超时。
- Reset 失败 + CANCEL。
- Reset 失败 + FORCE DELETE + 服务器成功。
- Reset 失败 + FORCE DELETE + 服务器失败/超时。
- 服务器 Gateway 不存在时，幂等成功并完成本地清理。
- 删除会话期间不触发普通 `syncGateway` 重新注册。
- SDK 默认 Reset 行为对所有非 Gateway 调用点保持不变。

## 当前确认状态

除实现所需的 SDK 延迟删除机制外，产品规则已完整，无需再确认 Delete 顺序、幂等性、失败 Toast 或本地清理时机。下一阶段可以基于本文件与服务器实际响应合同制定最终开发计划。
