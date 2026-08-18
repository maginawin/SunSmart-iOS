# Gateway 现有云同步链路与无后端改动修复方案

## 1. 决策前提

本轮确认：

- 不调整现有后端接口；
- 不要求后端新增 Gateway `updateTimestamp`；
- 继续推进 Owner/Editor 名称一致、Space 权限隔离、`Devices not synced` 修复和 Reset/Re-add 生命周期识别；
- 尽量不改变现有 Gateway 保存和同步交互。

## 2. 结论

### 2.1 App 当前如何上传 Gateway

Gateway 名称和大多数属性不通过 Site upload 上传，而是通过：

`SyncOperation.syncGateway -> /sitespace/sapce/gateway/regist`

请求体包含：

- `siteId`
- `gatewayId`
- `nodeId`
- `node`
- `updateTimestamp = gateway.lastUpdate`
- `userId`

其中：

- Gateway 名称位于 `node.name`；
- `activate`、`associatedSpaces`、APN、MQTT 信息位于 `node.gatewayPreconfigured`；
- Node 中还可能包含 Mesh、GatewayInfo、Key、Element 等完整设备数据；
- 请求中的 `updateTimestamp` 当前服务器不用于版本判断，只是 App 的本地 generation 值。

### 2.2 Associated Spaces 有两条服务器写链路

关联 Space 保存不是只依赖 Gateway register：

1. App 先按 diff 调用 `gatewayBindSpace` / `gatewayUnbindSpace`；
2. 成功后更新本地 `GatewayModel.associatedSpaces`；
3. 如需设备侧配置，进入 Mesh subnet/AppKey 同步；
4. 最后发送 Gateway changed 通知；
5. Site 页面收到通知后推进 Gateway generation，并调用 `gateway/regist` 上传最终 Node 和 `gatewayPreconfigured.associatedSpaces`；
6. topology changed 通知还会触发一次 `get/siteprops` 刷新。

因此 Associated Spaces 当前同时使用：

- 专用 bind/unbind API 作为服务器关联关系写入；
- Gateway register 作为 Gateway/Node 完整快照同步。

### 2.3 App 不会主动修改 `site.lastUpdate`

已确认以下 Gateway 路径都不会在 App 本地修改：

- `SiteData.lastUpdate`
- `SiteData.lastUploadCloudTimestamp`

Gateway register 成功只推进：

- `GatewayModel.lastUploadCloudTimestamp`

bind/unbind 成功也不会用本地 Gateway 时间戳推导 Site 时间戳。

这是正确的：服务器 Site 版本和 App Gateway generation 不是同一个时钟，App 不能自行把 `site.lastUpdate` 设置成 `gateway.lastUpdate`。

### 2.4 服务器很可能会推进 Site `updateTimestamp`

当前只读 `get/siteprops` 返回：

- Site `updateTimestamp = 1787032499`，即 2026-08-18 13:54:59（UTC+08:00）；
- 可见 Space `wifi.updateTimestamp = 1786772286`，即 2026-08-15 13:38:06；
- Gateway 名称已经是 `Gateway1`；
- Gateway 本身仍没有 `updateTimestamp`。

Site 时间明显晚于 Space 时间，并且与 Owner 当天修改 Gateway 的时间窗口吻合。由此可以合理推断：Gateway register、关联操作或其他 Gateway 写入很可能会推进父 Site 的 `updateTimestamp`。

但目前没有后端代码、写接口响应中的 Site timestamp，也没有同一操作前后的受控抓包，因此不能确认：

- 一定是 rename/register 推进；
- bind 和 unbind 是否都推进；
- 所有服务器版本是否始终保持该行为。

App 修复可以利用 Site timestamp 作为 Site 快照变化提示，但不能把该副作用视作逐 Gateway 的强版本契约。

## 3. 名称修改的完整同步时序

当前时序如下：

1. 用户在 Gateway 页面修改名称并点击 Save。
2. `GatewayViewController` 同时更新：
   - `GatewayModel.name`
   - `Gateway.name`
   - `Node.name`
3. 保存 Node 和 GatewayModel。
4. 如果没有待执行的设备侧 Gateway 配置，立即发送 `siteGatewayDataChangedNotificaitonName`。
5. 如果有设备侧配置，完成或退出 SyncDevices 流程后再发送该通知。
6. `SiteViewController` 收到通知后：
   - 更新 `gateway.model.lastUpdate`；
   - 保存 GatewayModel；
   - enqueue `.syncGateway`。
7. `CloudSynchronizationManager` 导出 Node，并附加 `gatewayPreconfigured`。
8. 请求 `gateway/regist`。
9. 成功后只确认对应 Gateway generation，更新 `lastUploadCloudTimestamp`。

名称本身不需要写入 Mesh 设备配置，它主要通过 Node 云快照上传到服务器。

## 4. 其他 Gateway 属性的同步

### 4.1 Activate、APN、MQTT/Server Information

这些属性先写入 `GatewayModel`，需要设备侧配置时进入 SyncDevices；之后通过相同 Gateway changed 通知触发 `gateway/regist`。

GatewayModel 导出位置：

- `activate -> gatewayPreconfigured.activate`
- `associatedSpaces -> gatewayPreconfigured.associatedSpaces`
- `apn -> gatewayPreconfigured.apn`
- MQTT -> `gatewayPreconfigured.mqttConnectInfo`

### 4.2 Gateway Time/Timezone

Gateway 时间相关协调器在设备确认成功后直接：

1. 推进 `GatewayModel.lastUpdate`；
2. 保存 Node/Gateway；
3. enqueue `.syncGateway`。

它不会更新 Site 本地时间戳。

### 4.3 Force Clear 与 Delete

- Force Clear 通过 `gatewayUnbindAllSpaces` 写服务器，并刷新 Site；不依赖 Gateway register 才完成服务器解绑。
- Delete 通过 `gatewayDelete` 删除服务器 Gateway，成功后进入设备 Reset/本地删除阶段。

## 5. 为什么 Site timestamp 已更新，Editor 名称仍旧

当前 Site 和 Gateway 使用两层互不相同的导入门槛：

1. 顶层 Site：远端 `site.updateTimestamp > local site.lastUpdate` 时更新 Site name/image/timezone。
2. Gateway：远端 `gateways[].updateTimestamp > local gateway.lastUpdate` 时替换 Gateway/Node。

服务器虽然可能已经推进顶层 Site timestamp，但 `gateways[].updateTimestamp` 缺失，被解析为 `0`。

结果是：

- iPad 接受了新的 Site timestamp；
- Gateway 比较仍然是 `0 > localGatewayTimestamp`，结果为 false；
- Gateway 名称继续使用本地 `Gateway111`。

所以问题不是“Site timestamp 没更新”，而是“Gateway 导入没有使用 Site 快照中的真实字段进行安全合并”。

## 6. 无后端改动下的推荐修复

### 6.1 不新增 Gateway 服务器时间属性

既然后端不返回 Gateway 版本，本次不新增 `serverUpdateTimestamp` 数据库字段，也不修改 register API。

继续保留：

- `GatewayModel.lastUpdate`：本地修改 generation；
- `GatewayModel.lastUploadCloudTimestamp`：已确认上传 generation。

### 6.2 Site timestamp 的使用边界

可以把 `site.updateTimestamp` 用作：

- 整个 `siteprops` 快照可能变化的提示；
- 判断是否需要重新检查 Site/Gateway 字段的优化信号；
- 记录诊断日志。

不能用作：

- Gateway 整体 Node 替换版本；
- Gateway 本地 dirty 的上传确认；
- 多 Gateway 之间的独立冲突版本；
- 本地 Gateway generation 的替代值。

尤其不能只在 `remoteSiteTimestamp > localSiteTimestamp` 时合并 Gateway。当前 iPad 已经把 Site timestamp 保存为最新值，如果修复后只依赖“严格更新”，历史旧名称仍无法自愈。

### 6.3 每次 Siteprops 做幂等字段级合并

每次成功取得 `siteprops` 后，对同 MAC Gateway 执行字段比较：

#### 服务器权威、可直接更新的字段

- `gatewayOnline`
- connect/disconnect 时间
- status 等服务器运行态字段

#### 本地 clean 时更新的配置字段

- Gateway `name`
- `activate`
- APN
- MQTT/server information
- 服务器关联 Space 摘要

clean 条件至少包括：

- `gateway.needUploadCloud == false`
- 没有进行中的 `.syncGateway`
- 不处于 server deletion/reset 流程

名称更新必须同时写入：

- `GatewayModel.name`
- 对应 `Node.name`

字段相同不写数据库，使该逻辑可在每次 Site 进入时安全、幂等执行。

### 6.4 本地 dirty 保护

Gateway dirty 时不使用服务器旧配置覆盖本地待上传值：

- 本地 dirty 名称继续保留并重试 register；
- 服务器运行态字段仍可更新；
- 关联 Space 使用专用 reference/bind/unbind 结果收敛，不能仅依赖 GatewayModel dirty；
- 云上传成功后，下次 siteprops 再做 clean merge。

### 6.5 Reset/Re-add 身份变化

如果同 MAC 的服务器 Gateway 出现以下变化：

- Node UUID 变化；
- unicast address 变化；
- deviceKey 或其他稳定身份变化；

则视为可能的 Reset/Re-add 新生命周期：

- 本地 clean：替换旧 Node/Gateway 绑定关系；
- 本地 dirty、删除中或 Reset 中：暂不替换，记录冲突并刷新；
- 不以 Site timestamp 单独触发 Node 删除/重建。

## 7. Associated Spaces 无后端改动修复

继续使用现有接口：

- `gateway/reference`
- `gatewayBindSpace`
- `gatewayUnbindSpace`
- `gatewayUnbindAllSpaces`

App 修复内容：

1. 统一使用 `space.canEditing && space.deviceOperates.contains(.edit)`。
2. 无权限关联作为 locked/opaque association 原样保留。
3. Save 前重新获取 reference 并校验 add/unbind diff。
4. 只允许 Editor 修改自己有权限的 Space。
5. 部分请求成功后发生失败，重新加载服务器 reference，不保存推测状态。
6. topology changed 后继续立即刷新 siteprops。
7. Gateway register 上传时，不能把 Editor 本地缺失的 Key/index 当成服务器删除意图。

最后一项需要重点验证当前服务器 register 的 merge 行为。由于不修改后端，如果服务器把 Editor 的局部 Node 快照当成全量覆盖，App 端必须在子集 Editor 场景避免上传会造成破坏的完整 Gateway register，或确保导出时保留服务器提供的 opaque index 元数据。

## 8. `Devices not synced` 无后端改动修复

期望 index 使用现有响应即可获得：

- `gatewayInfo.subnetAppkeyIndexs`
- `gatewayPreconfigured.associatedSpaces[].appKeyIndex`
- `gateway/reference` 返回的 AppKey index

规则：

- 状态比较使用服务器完整关联 index；
- Editor 本地 `applicationKeys` 只代表其可操作 Key，不代表完整 Gateway 目标；
- 添加/解绑只修改授权 Space 的 index；
- 未授权 index 原样保留；
- 子集 Editor 不执行需要完整 Key 材料的全量 Recovery。

本次数据应判断为：

- 服务器期望 `[1,2]`
- 设备实际 `[1,2]`
- 已同步

## 9. 本地 generation 需要顺带修正

普通 Gateway changed 通知当前直接写当前秒数：

`gateway.lastUpdate = Int64(Date().timeIntervalSince1970)`

同一秒内连续保存可能得到相同 generation，使失败重试、in-flight 合并和 dirty 判断不可靠。

项目已经有 `GatewayCloudSyncGenerationPolicy.next`，建议所有 Gateway mutation 统一使用：

`max(now, current + 1, uploaded + 1)`

这是纯 App 修复，不改变请求结构和服务器语义。

## 10. 调整后的实施顺序

### 第一阶段：现有接口下立即修复

1. Gateway siteprops 字段级 clean merge。
2. 同步更新 GatewayModel/Node 名称。
3. 增加 Reset/Re-add identity 判断。
4. Editor 非完整 Gateway 快照不得因“服务器列表缺失”删除本地 Node。
5. 修复完整关联 index 来源和 `Devices not synced`。
6. 普通 Gateway mutation 使用单调 generation policy。

### 第二阶段：权限收敛

1. 统一 Gateway/Space 权限策略。
2. locked association 原样保留。
3. Save 前 reference 二次校验。
4. 子集 Editor 只允许局部 bind/unbind。
5. Delete/Force Clear 执行前实时校验继续保留。
6. 验证子集 Editor 的 register 不覆盖无权限 Space 数据。

### 不再实施

- 不新增后端 Gateway timestamp。
- 不新增 App `serverUpdateTimestamp`。
- 不修改现有 Gateway register、bind、unbind、delete API 结构。
- 不把 Site timestamp 直接复制到 GatewayModel。

## 11. 验证服务器 Site timestamp 副作用的方法

实现和验收时增加诊断，不要求修改后端：

1. 操作前读取一次 siteprops，记录 Site timestamp、Gateway name/refSpaces。
2. 分别执行 rename、bind、unbind。
3. 每个操作成功后重新读取 siteprops。
4. 记录：
   - 操作类型；
   - Site timestamp before/after；
   - Space timestamp before/after；
   - Gateway name/refSpaces before/after；
   - App `gateway.lastUpdate/lastUploadCloudTimestamp`。
5. 结果只作为现网行为验证，App 字段级 merge 不依赖该副作用必须存在。

## 12. 最终建议

不更新后端接口是可行的。

最小风险方案不是让 Gateway 复用 Site timestamp 做整包版本，而是：

- 保留现有 Gateway register 与 bind/unbind 链路；
- App 不主动更新本地 Site timestamp；
- 通过下一次 siteprops 获取服务器权威 Site timestamp；
- 无论 Site timestamp 是否再次变大，都对 clean Gateway 做幂等字段级合并；
- dirty Gateway 继续使用现有本地 generation 保护；
- Reset/Re-add 用身份变化处理；
- 权限和 opaque association 在 App 内收敛。

这样可以修复当前 Owner/Editor 名称不一致，又不会把一次 Site 变化扩大成 Gateway Node 的无条件重建。
