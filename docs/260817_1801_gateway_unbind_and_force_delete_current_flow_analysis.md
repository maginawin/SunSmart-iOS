# Gateway Unbind 与 Force Delete 当前流程分析

## 结论

服务器已具备原子清空 Associated Spaces 的能力：调用现有 `POST /sitespace/sapce/gateway/unbind` 时只传 `gatewayId`、不传 `spaceId`，即可清空该网关的全部 Associated Spaces。因此独立 `Force clear spaces` 不需要新增服务器 path，也不需要由 App 逐条解绑。

普通 Gateway 编辑中从 3 个 Associated Spaces 删除 2 个时，当前 App 不使用“省略 spaceId”的清空全部能力，而是计算旧列表和编辑列表的差集，对两个被删除的 Space 分别调用两次带 `spaceId` 的 unbind 接口。两次服务器调用都成功后，App 才保存本地 GatewayModel，并进一步通过 Mesh 同步网关设备中的 Key 与关联索引。

当前已注册 Gateway 的 Delete 流程已经要求 `gatewayDelete` 成功后才开始蓝牙 Reset，因此该分支进入 FORCE DELETE 弹窗时，服务器删除实际上已经成功。但本地被判断为“未注册”的 Gateway 会直接进入蓝牙删除，不调用 `gatewayDelete`，所以“所有 Gateway 的 FORCE DELETE 都必须先确认服务器删除成功”目前并不是全局不变量。

本轮只分析，不修改业务代码。

## 从 3 个 Spaces 删除 2 个时的完整状态链

### 1. UI 编辑阶段

用户在 Associated Spaces 列表删除 Space 时，`unbindAssociatedSpace` 只从编辑副本 `setGatewayModel.associatedSpaces` 移除该 Space，并刷新页面和 Save 状态。此时：

- 持久模型 `gatewayModel.associatedSpaces` 仍为 3 个。
- 编辑副本变为 1 个。
- 尚未请求服务器。
- 尚未向 Gateway 发送 Mesh 命令。

### 2. 点击 Save 后计算差集

`saveAssociatedSpacesIfNeeded` 使用：

- `oldSpaces = gatewayModel.associatedSpaces`
- `newSpaces = setGatewayModel.associatedSpaces`
- `unbindSpaces = oldSpaces - newSpaces`

示例中 `unbindSpaces` 包含被删除的两个 Space。

### 3. 通知服务器

App 顺序遍历 `unbindSpaces`，每个 Space 调用一次：

- `POST /sitespace/sapce/gateway/unbind`
- 参数：`spaceId`、`gatewayId`、`userId`

因此删除两个 Space 会发送两次请求，每次带一个具体 `spaceId`。当前 `NetowrkReqeustApi.gatewayUnbindSpace` 把 `spaceId` 定义为非 Optional，所以现有 App 还不能通过同一 case 生成“省略 spaceId”的清空全部请求。

### 4. 服务器全部成功后保存本地

两次 unbind 都成功后：

- `gatewayModel.update(gatewayModel: setGatewayModel)` 把持久模型更新为只剩 1 个 Space。
- `gateway.model.save()` 保存数据库。
- 发送 Gateway 关联拓扑变化通知，Site 页面重新加载服务器数据。

若第一条成功、第二条失败，当前流程会停止且不把编辑副本写入持久模型，但服务器已经发生部分解绑。代码会发送拓扑变化通知以重新加载服务器状态。这是普通多 Space 编辑仍然存在的非原子边界，与新的 Force Clear 单请求方案无关。

### 5. 同步已连接的 Gateway 设备

本地保存后，`node.getNodeSyncGatewayData` 比较目标 Associated Spaces 与 Gateway Node 当前持有的 Secondary Network Keys / Application Keys。对两个已删除 Space 生成 `gatewayUnbindAssociatedSpaces` 同步任务，并进入 `SyncDevicesViewController`。

每个被删除 Space 对应的 Mesh 操作包括：

- 对相关 Models 发送 `ConfigModelAppUnbind`。
- 发送 `ConfigAppKeyDelete`。
- 发送 `ConfigNetKeyDelete`。
- Gateway 已激活时，发送 Vendor `gatewaySubnetAppkeyDelete`，更新 Gateway 的子网 AppKey 索引关联。

因此当前顺序是服务器先解绑、本地再保存、最后同步在线 Gateway 设备。服务器请求成功不等于 Gateway Mesh 同步也成功；两者是不同的完成边界。

## 现有 Unbind 接口如何支持 Force Clear

后续独立 Force Clear 应扩展 App 的 API 建模，使 `spaceId` 可选，并确保清空全部时请求体真正不包含 `spaceId`：

- 普通移除一个或多个 Space：每次传具体 `spaceId`，保持现有行为。
- Force Clear：只传 `gatewayId` 与 `userId`，不传 `spaceId`，调用一次完成服务器原子清空。

不能传空字符串、`null` 或伪造 Space ID；服务器合同明确依赖属性缺失，App 测试需要检查最终请求体中不存在 `spaceId` Key。

仍需服务器确认该模式的权限、成功响应、幂等性和事务保证。特别是返回成功必须代表全部关联已经提交清除，而不是仅受理请求。

## 当前 Gateway Delete / Force Delete 行为

### 已注册 Gateway 分支

当前代码用以下本地状态判断 Gateway 已注册：

- `mqttServerInfo != nil`，或
- `lastUploadCloudTimestamp != nil`

该分支的顺序是：

1. 非 Owner 先查询服务器关联列表并校验全部 Space 权限。
2. 调用 `gatewayDelete(gatewayId:)`。
3. 服务器成功后，立即清空本地 MQTT、Associated Spaces 和上传时间戳并保存。
4. 调用蓝牙 `resetNodes`。
5. 蓝牙失败后才展示 FORCE DELETE。

因此在该分支，`gatewayDelete` 失败会停在步骤 2，不会开始蓝牙 Reset，也不会出现这次蓝牙操作对应的 FORCE DELETE 弹窗。从调用顺序看，已注册 Gateway 当前已经满足“服务器删除成功后才允许进入后续强制删除路径”。

但服务器失败时当前展示的是 `error.localizedDescription` 的通用错误 HUD，并不是指定的固定 Toast `Failed to delete gateway from server`。

### 本地判定为未注册的 Gateway 分支

如果两个本地字段都为空，当前代码直接调用 `resetNode()`，完全绕过 `gatewayDelete`。蓝牙失败后仍可点击 FORCE DELETE，并直接提交本地永久删除。

所以如果产品要求所有 Gateway 的 FORCE DELETE 都必须以服务器 `gatewayDelete` 成功为前置条件，当前实现不完整。仅依赖 MQTT 与上传时间戳也不能严格证明服务器一定不存在该 Gateway，因为本地缓存可能过期或异常。

## 推荐的删除约束

后续方案应建立明确的删除会话状态，而不是让通用 `DeviceProtocol.deleteNodes` 推断服务器状态：

1. 发起 Gateway Delete。
2. 调用 `gatewayDelete`，服务器在同一事务内删除 Gateway 并清除全部 Associated Spaces。
3. 只有收到明确成功响应，才设置 `serverDeletionConfirmed = true` 并开始蓝牙 Reset。
4. 蓝牙成功：提交本地永久删除。
5. 蓝牙失败：展示 FORCE DELETE。
6. 点击 FORCE DELETE 时再次检查删除会话中的 `serverDeletionConfirmed`；为 true 才允许提交本地永久删除和 Mesh Node 移除。
7. `gatewayDelete` 明确失败或 30 秒无最终成功：中断流程，使用 Site Update 失败 Toast 显示 `Failed to delete gateway from server`，不开始蓝牙 Reset，也不确认删除成功。

为了把该约束覆盖到本地“未注册”场景，推荐服务器把 `gatewayDelete` 定义为幂等：Gateway 已不存在时仍返回可识别的成功。这样 App 可以统一先调用服务器，而不再依赖两个本地字段绕过服务器。如果服务器对不存在 Gateway 返回失败，则需要服务器提供权威存在性查询，不能仅用本地缓存作为跳过依据。

## 还发现的删除状态边界

当前 `gatewayDelete` 成功后，在蓝牙结果出来前就清空并保存了部分本地 Gateway 数据；真正删除 Gateway 数据库记录和 Mesh Node 则要等蓝牙成功或 FORCE DELETE。

蓝牙失败并选择 Cancel 时，当前回调还会发送 `siteGatewayDataChanged` 通知。Site 页收到后会启动 `syncGateway`，存在把刚从服务器删除的 Gateway 再次注册上传的风险。后续规划需要明确处理这一分支，避免删除会话被普通 Gateway 配置同步反向恢复。

建议后续把以下状态明确区分：

- 服务器删除未确认。
- 服务器删除已确认，等待蓝牙结果。
- 蓝牙失败，等待用户 Cancel 或 FORCE DELETE。
- 本地永久删除已提交。

删除会话期间不应触发普通 `siteGatewayDataChanged` 云同步重新注册 Gateway。

## 待确认事项

1. `gatewayDelete` 对服务器上已不存在的 Gateway 是否按幂等成功处理？这决定 App 能否对所有 Gateway 统一强制要求服务器确认。
2. `gatewayDelete` 成功后、蓝牙 Reset 失败且用户选择 Cancel 时，预期是保留本地 Gateway 供再次删除，还是仍清除本地 Gateway？无论哪种，都不应自动重新注册服务器 Gateway。
3. 服务器失败 Toast 是否确认使用 `ToastStatusView` 的 `.siteUpdate` 失败样式，文案固定为 `Failed to delete gateway from server`？
4. 是否把本地 MQTT、Associated Spaces 等字段的清除延后到蓝牙成功或 FORCE DELETE 本地提交时，避免中间状态提前破坏页面数据？
