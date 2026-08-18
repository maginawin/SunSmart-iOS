# Force Clear Spaces 后网关重新上线同步失败分析

## 结论

`associatedSpaces` 仍然是有效且必要的数据。它表示 App 与服务器侧对该 Gateway 的“期望关联空间”，同时参与页面展示、本地持久化、Gateway 配置差异计算、恢复同步步骤生成以及关联 Network Key 的扫描范围计算，不能因为增加 Force Clear 而移除。

当前 Force Clear 的边界是：

1. App 请求服务器按 Gateway ID 原子删除全部 Gateway-Space 关联关系。
2. 服务器返回成功后，App 清空持久模型与页面编辑副本中的 `associatedSpaces`。
3. Force Clear 不连接 Gateway，也不向 Gateway 发送 Mesh Key、Model App Bind 或 Vendor Subnet 配置清理消息。

因此，离线 Gateway 在 Force Clear 后重新上电时，如果它仍保留原先关联 Space 的 secondary NetKey、AppKey、Model App Bind 或 Vendor Subnet Index，App 显示 `Devices not synced` 是符合当前差异检测逻辑的。真正的问题是随后进入的专用 Gateway Recovery 流程没有加入“解除旧关联空间”的任务，最终校验却要求所有差异已经清零，所以稳定失败在 `Verify Configuration`。

从产品流程看，不应要求用户删除并重新添加 Gateway。删除重加可以作为当前版本的临时恢复手段，但它是通过 Reset/重新配网绕过恢复同步缺口，不是合理的正常路径。

## Force Clear 实际清理内容

### 服务器请求

- 路径：`/sitespace/sapce/gateway/unbind`
- 请求参数：`gatewayId`、`userId`
- 特殊语义：完全省略 `spaceId`，由服务器按既定接口契约清除该 Gateway 的全部 Space 关联关系。

这里不是把某个名为 `associatedSpaces` 的请求参数传为空数组。App 根本没有发送该数组；“清空全部”的含义来自同一个 unbind 接口中省略 `spaceId`。

服务器实现不可从 App 仓库直接证明；按已确认接口契约，预期被删除的是 Gateway-Space 关联记录，使后续 reference 接口返回的 `refSpaces` 为空。

### App 本地数据

服务器成功后，App 对以下两个数组执行清空并持久化：

- `gatewayModel.associatedSpaces`：持久模型及后续配置期望状态。
- `setGatewayModel.associatedSpaces`：当前详情页的编辑副本。

### 未清理内容

Force Clear 不会直接清理：

- Gateway 内保存的 secondary NetKey。
- Gateway 内保存的 secondary AppKey。
- Gateway Model 的 AppKey Bind。
- Gateway Vendor 配置中的 Subnet AppKey Index。
- Gateway 的 Project ID、MQTT 信息或整个 Gateway 注册记录。

## `Devices not synced` 的触发原因

Gateway 详情页用 `node.getNodeSyncGatewayData(gateway:)` 是否为空决定是否显示 `Devices not synced`。

Force Clear 后，本地期望的 `gateway.associatedSpaces` 已为空；网关重新上线并读取到旧配置后，差异计算会把所有仍存在、但不再包含于期望关联列表的 secondary Network Key 归入 `gatewayUnbindAssociatedSpaces`。因此提示本身说明“网关实际配置尚未收敛到清空后的期望状态”，不是服务器清空失败的直接证据。

若现场网关重新上电后确实仍报告这些 Key，可进一步推断旧关联配置持久化在网关中；这一点需要 Mesh 消息日志或固件存储设计确认，App 源码本身不能证明固件持久化方式。

## `Verify Configuration` 一直失败的根因

从 Gateway 详情页点击 `Devices not synced` 后，进入的是专用 `.gatewayRecovery`，不是普通 `.devices` 差异同步。

当前 Gateway Recovery 生成的步骤包括：

1. 强制初始化基础 Key 与 Model Bind。
2. 对本地 `associatedSpaces` 中仍期望保留的 Space 重新下发关联配置。
3. 下发 Project ID。
4. 下发期望的 Subnet AppKey Index 列表；Force Clear 后该列表为空。
5. Wi-Fi Gateway 的服务器授权与 MQTT 信息步骤。
6. `Verify Configuration`。

缺失的步骤是：枚举 Gateway 上仍存在、但已不在 `associatedSpaces` 中的 secondary Key，并执行已有的 `gatewayUnbindAssociatedSpace` 删除任务。

普通设备差异同步其实已经具备完整解除能力，会依次执行 Model App Unbind、AppKey Delete、NetKey Delete，并在激活状态下发送 Vendor Subnet AppKey Delete。但专用 Gateway Recovery 没有复用或构造这组删除任务。

最终 `Verify Configuration` 又明确要求：

- 服务器信息有效。
- Key Bind 完成。
- `node.getNodeSyncGatewayData(gateway:)` 完全为空。

旧 secondary Key 没有被删除，最后一个条件始终不成立，因此校验失败。这是 App 恢复步骤与最终验收条件不对称导致的确定性缺口。

## 是否需要删除后重新添加

### 正常产品行为

不需要。Force Clear 的确认文案已经把“Gateway 再次上线后提示重新配置”定义为预期后续流程；这意味着 App 应能在不删除 Gateway 的情况下，把网关实际配置收敛到空关联状态。

### 当前版本临时处置

在恢复流程修复前，删除并重新添加可作为现场 workaround，因为 Reset 与重新配网通常会移除旧配置并重建 Gateway。但该操作会扩大影响范围，且是否彻底清理仍取决于 Reset/固件实现，不应作为设计要求或唯一恢复方案。

## 建议修复范围

保持 Force Clear 的服务器与本地提交逻辑不变，仅修复专用 Gateway Recovery：

1. 生成恢复步骤时，以网关当前持有的 secondary Network Key 与本地 `gateway.associatedSpaces` 期望列表计算待移除集合。
2. 为每个待移除 Space 加入已有的 `gatewayUnbindAssociatedSpace` 删除任务。
3. 删除步骤覆盖 Model App Unbind、AppKey Delete、NetKey Delete 和必要的 Vendor Subnet AppKey Delete。
4. 让 `Sync Spaces` 和 `Verify Configuration` 依赖删除步骤完成，避免先验收后清理。
5. 保留现有最终校验条件；修复后它应能验证所有 Gateway 差异真正归零。
6. 增加 Force Clear 后空期望列表、一个旧 Space、多个旧 Space、部分删除失败及重试的回归测试。

## 验证边界

源码已能证明 App 请求参数、本地数组清空、差异计算、恢复步骤缺少解绑任务及最终校验条件。仍需真机验证：

- 重新上电后网关实际报告的旧 NetKey/AppKey/Model Bind/Vendor Index。
- 删除任务的逐条 ACK 与 Node 缓存更新。
- `Verify Configuration` 最终通过且 `Devices not synced` 消失。
- Gateway 无需删除重加即可正常继续使用和重新关联 Space。

## 关键源码位置

- `SunSmart/Common/Network/NetowrkReqeustApi.swift`：清空全部接口、路径和请求参数。
- `SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift`：Force Clear 成功后的本地数组清空、未同步提示及 Gateway Recovery 入口。
- `SunSmart/Common/Data/Node+SyncData.swift`：Gateway 期望状态与实际 Key 的差异计算。
- `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`：普通差异同步具备解绑步骤，但专用 Gateway Recovery 未生成解绑步骤。
- `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift`：`Verify Configuration` 的成功条件。
- `SunSmart/Common/Data/Node+MessageHandles.swift`：已有完整的 Gateway Associated Space 解绑消息序列。
