# Sequence / Trigger Zone 风险 2、3、4、6 修复设计

## 1. 背景

本设计覆盖 Path Sequence 页面相关的以下问题：

- Risk 2：Group 保存存在“先本地保存、后标记云同步”的中断窗口。
- Risk 3：Space Trigger Zone 清空时没有显式导出空数组。
- Risk 4：Space Trigger Zone 成功后会产生两次云同步通知。
- Risk 6：Space Trigger Zone 可能保留已经不再符合 Profile 的邻居。

方案已经确认采用“方案 B：共享写前云脏标记 + 单一成员资格判定”。

Risk 6 的产品语义已经确认：

- 永久删除不再符合条件的 Trigger Zone 成员。
- 成员全部失效后保留空 Zone。
- 清理结果保存到本地、同步设备并上传服务器。
- Profile 恢复后不自动恢复成员，需要用户重新添加。

## 2. 目标

### 2.1 功能目标

1. Group Sequence / Trigger Zone 的本地修改一旦持久化，就必须已有可恢复的云端待上传标记。
2. Space Trigger Zone 清空后，上传 JSON 必须包含 `"triggerZones": []`。
3. 导入时，无论 `triggerZones` 是空数组还是字段缺失，本地都必须得到空数组。
4. 一次 Space Trigger Zone 保存最多产生一个业务云同步通知。
5. Space Trigger Zone 的本地模型、设备目标邻居和服务器数据都不得继续包含失效成员。

### 2.2 非目标

- 不修改 Sequence / Trigger Zone 的 Mesh Opcode、Access Payload 或 SDK 消息编码。
- 不改变 Group Sequence、Group Trigger Zone 与 Space Trigger Zone 共用设备邻居表的现有架构。
- 不处理邻居数量上限、消息分片或自动重试等其他风险。
- 不新增服务器 API。
- 不新增本地化文案、资源、依赖或 target 配置。
- 不在本次修复中改变“目标邻居为空时关闭 Proximity Lighting”的既有设备行为。

## 3. 当前实现与问题根因

### 3.1 Risk 2

`GroupPathSequencePageController.saveAction()` 当前先执行：

1. 更新 `group.info.proximityLightingPath`。
2. 保存 `GroupInfo`。
3. 更新设备同步状态。
4. 无设备任务时才发送 `.common` 通知；有设备任务时等待通用同步页结束后发送 `.device` 通知。

Group 数据保存与 Space 云端待上传标记不在同一持久化步骤中。App 如果在两者之间退出，Group 修改可能存在于本地，但 `SpaceData.needUploadCloud` 仍为 `false`。

### 3.2 Risk 3

`SpaceData.export()` 只有在 `triggerZones` 非空时才写入服务器 JSON。清空全部 Zone 后，字段被省略，服务器无法区分“客户端没有提供该字段”和“客户端明确清空该字段”。

`SpaceData` 的当前导入逻辑已经兼容两种服务端输入：

- `triggerZones: []`：成功解码为空数组。
- 缺少 `triggerZones`：进入兜底分支并赋值为空数组。

因此 Risk 3 的生产修改只需要移除导出非空门禁；导入代码保留并增加防回归契约。

### 3.3 Risk 4

存在设备任务时：

1. `SyncDevicesViewController` 在任务结束后统一发送 `.device`。
2. `SpacePathTriggerZoneController.syncSuccessCallback` 又发送 `.common`。

同一次保存因此产生两个云同步入口，可能导致正在排队或执行的同步被取消并以不同优先级重新排队。

### 3.4 Risk 6

Space Trigger Zone 页面初始化时只删除 Node 或 Group 已不存在的 Item，没有校验：

- Group 是否仍属于当前 Space/Mesh Network。
- Group Profile 是否仍为 Proximity Lighting。
- Item 保存的 `groupAddress + deviceAddress` 是否仍是当前 Group 的有效成员组合。

`desiredNeighborAddresses(for:)` 也直接读取 Zone Item，导致失效地址可能继续写入其他符合条件节点的私有邻居表。

## 4. 总体设计

修复保持三条链相互独立：

1. 逻辑数据链：保存 Group Path 或 Space Trigger Zone。
2. 设备链：把清理、编译后的邻居地址同步到 Mesh 节点。
3. 云端链：持久化 Space 待上传状态，并将逻辑 JSON 上传服务器。

关键约束：

- 云端待上传标记采用写前标记。
- 设备同步是否成功不决定逻辑配置是否上传。
- 每次保存只有一个通知所有者。
- 成员资格只使用一个判定集合。

## 5. 详细设计

### 5.1 共享写前云脏标记

在现有 `SpaceData` 云同步扩展中增加：

```swift
func markLocalChangePendingCloudSync()
```

职责：

1. 刷新当前 Mesh 的 Space 汇总数量。
2. Visitor 只保存汇总数量，不设置云端待上传状态。
3. Owner / Editor 按现有单调时间规则更新 `lastUpdate`：
   `max(now, lastUpdate + 1, lastUploadCloudTimestamp + 1)`。
4. 立即保存 `SpaceData`。
5. 不查找 Site，不创建云同步 Handle。

现有 `commitLocalChangeForCloudSync(...)` 改为复用该方法，再继续执行 Site 查找和同步 Handle 入队。其他现有调用方行为保持不变。

写前标记允许出现“标记成功但业务保存尚未完成”的无害假阳性；不允许出现“业务已经保存但仍未标记”的假阴性。

### 5.2 Group 保存时序

`GroupPathSequencePageController` 增加 `SpaceData` 依赖，由 `GroupViewController` 创建页面时传入。

检测到 Group Path 确实变化后，保存顺序为：

1. `space.markLocalChangePendingCloudSync()`。
2. 将编辑结果写入 `group.info.proximityLightingPath`。
3. `group.info.save()`。
4. `group.updateGroupSyncState()`。
5. 计算是否存在设备同步任务。

后续分支：

- 无设备任务：页面发送一次 `.common`，触发正常云同步入队。
- 有设备任务：页面不发送 `.common`；由 `SyncDevicesViewController` 结束时发送一次 `.device`。

如果 App 在写前标记后、Group 保存前退出，只会导致上传一次旧数据；未保存的编辑不会被误认为已经保存。

如果 App 在 Group 保存后、设备同步结束前退出，持久化的 `needUploadCloud` 会由现有离开 Space、重新进入或手动恢复同步流程识别。

### 5.3 Space Trigger Zone 保存时序

保存前先执行永久清理，再比较新旧值。

检测到逻辑数据变化后：

1. `space.markLocalChangePendingCloudSync()`。
2. 将清理后的 Zone 写入 `space.triggerZones`。
3. `space.save()`。
4. 使用同一份清理后的 `setZones` 编译设备目标邻居。

通知规则：

- 没有设备任务：发送一次 `.common`。
- 存在设备任务：只保留通用同步页的 `.device`。
- 成功回调只显示成功提示并返回。
- 设备同步失败时，通用同步页仍发送 `.device`，让逻辑配置和失败后的设备状态进入云同步。

### 5.4 Trigger Zone 成员资格

使用一个 Hashable 成员键：

```text
groupAddress + normalized deviceAddress
```

有效成员集合由当前 `eligibleGroups` 生成。Group 必须：

- 属于当前 Space 的 `meshNetworkId`。
- Profile 为 `proximityLighting` 或 `proximityLightingWithPhotocell`。

每个有效 Group 再从其当前 `group.nodes` 生成成员键；设备地址沿用现有 normalized address 规则：

- 优先使用 Sunricher Vendor Model 所在 Element 地址。
- 否则使用 Primary Unicast Address。

清理规则：

- Item 的成员键不在有效集合中时，永久删除 Item。
- 不删除成员清空后的 Zone。
- 页面初始化后清理一次工作副本。
- 点击 Save 时再次清理，覆盖页面停留期间发生的 Profile 或成员变化。
- `desiredNeighborAddresses(for:)` 再按相同有效集合防御性过滤。

### 5.5 设备侧空邻居边界

私有协议 `0xF0780A / 0x41 / subcode 0x02` 的格式允许邻居个数字段为 `0`，SDK 也能编码空地址数组；但当前 App 的 `.proximityLightingNeighbor` 固定携带 `enabled = true`。

本次不扩展设备同步任务模型：

- 清理后仍有邻居：发送现有 Neighbor Set，失效地址不会出现在 Payload。
- 清理后没有邻居：沿用当前逻辑发送 Proximity Lighting Disable。

因此，本次保证失效邻居不再参与有效拓扑，也不再被写入新的邻居集合；不额外增加“空 Neighbor Set + Disable”的双命令事务。

### 5.6 服务器导出

`SpaceData.export()` 每次都尝试编码 `triggerZones` 并写入键：

- 非空时输出正常 Zone 数组。
- 空时输出 `[]`。
- 编码失败时保持现有失败语义，不用空数组伪装编码错误。

`SpaceData` 导入继续归一化：

- 空数组导入为 `[]`。
- 字段缺失导入为 `[]`。
- 字段存在但无法解码时沿用当前兜底，导入为 `[]`。

服务器数据仍保存逻辑 Zone 结构，不保存设备最终邻居表。

## 6. 通知所有权

| 保存结果 | 通知发送方 | 类型 | 次数 |
| --- | --- | --- | --- |
| Group，无设备任务 | Group 页面 | `.common` | 1 |
| Group，有设备任务 | `SyncDevicesViewController` | `.device` | 1 |
| Space Trigger Zone，无设备任务 | Space Trigger Zone 页面 | `.common` | 1 |
| Space Trigger Zone，有设备任务且成功 | `SyncDevicesViewController` | `.device` | 1 |
| Space Trigger Zone，有设备任务但失败 | `SyncDevicesViewController` | `.device` | 1 |

写前脏标记是直接持久化操作，不属于通知，不创建云同步 Handle。

## 7. 文件边界

计划修改：

- `SunSmart/Main/Space/Controller/SpaceViewController.swift`
  - 抽取共享写前云脏标记。
- `SunSmart/Main/Group/Path/Controller/GroupPathSequencePageController.swift`
  - 注入 Space，调整保存顺序。
- `SunSmart/Main/Group/Controller/GroupViewController.swift`
  - 创建 Group Path 页面时传入 Space。
- `SunSmart/Common/Data/ExportData.swift`
  - 移除非空门禁，显式导出空 `triggerZones`。
- `SunSmart/Main/Space/TriggerZone/Controller/SpacePathTriggerZoneController.swift`
  - 永久清理成员、统一资格判定、修正保存与通知时序。

计划新增：

- `Tests/Group/PathTopologyPersistenceContractTests.swift`
  - 覆盖保存顺序、空数组导出与兼容导入、通知所有权和成员清理契约。
- `scripts/check_path_topology_persistence.sh`
  - 编译并执行聚焦契约测试。

计划验证但不修改：

- `SunSmart/Common/Data/ImportData.swift`
  - 确认空数组和字段缺失都归一化为本地空数组。

不修改 NordicSigMeshSDK 和私有协议文档。

## 8. 测试设计

### 8.1 Risk 2

- 共享写前标记包含单调时间规则并立即保存。
- `commitLocalChangeForCloudSync` 复用写前标记。
- Group 页面只有在逻辑变化时标记。
- 标记调用在 `group.info.save()` 之前。
- Group 页面由父页面传入正确的 Space。

### 8.2 Risk 3

- `triggerZones` 非空时导出对应数组。
- `triggerZones` 为空时仍写入 `triggerZones` 键且值为空数组。
- 不保留 `if !self.triggerZones.isEmpty` 门禁。
- 导入空 `triggerZones` 时得到空数组。
- 导入 JSON 缺少 `triggerZones` 时也得到空数组。

### 8.3 Risk 4

- Space Trigger Zone 无设备任务分支保留一次 `.common`。
- 成功回调不再发送 `.common`。
- 通用设备同步页保留一次 `.device`。

### 8.4 Risk 6

- 不存在的 Group 或 Node 被清理。
- Group 不属于当前 Space 时被清理。
- Group Profile 不再符合时被清理。
- Item 的 Group/Node 组合不再匹配时被清理。
- 有效成员保留原顺序。
- Zone 清空后仍保留 Zone。
- 初始化和保存前都执行清理。
- 设备目标邻居使用相同资格集合防御性过滤。
- 最后一个有效邻居消失时，设备任务沿用 Disable 行为。

## 9. 验收标准

### 9.1 自动化

- 聚焦契约测试通过。
- 现有 Group Path Sequence 契约测试通过。
- 现有 Space 删除云同步恢复检查通过。
- `git diff --check` 通过。
- `SunSmart` generic iPhoneOS Debug 构建通过。
- 审计共享源码的 target membership；如其他品牌 scheme 使用同一源码，执行对应 generic iPhoneOS 构建。

### 9.2 真机与服务器

自动化和编译不能替代以下验收：

1. Group 保存后立即退出 App，再启动后仍显示待上传并最终上传。
2. 删除全部 Space Trigger Zones，服务器请求中包含 `"triggerZones": []`。
3. 分别导入空数组和缺少字段的服务器数据，本地 `space.triggerZones` 都为空。
4. Space Trigger Zone 有设备任务时只看到一次云同步入队。
5. 将成员 Group Profile 改为非 Proximity Lighting，再打开并保存 Space Trigger Zone：
   - UI 不再显示该成员。
   - 其他有效节点收到的 Neighbor Set 不包含该地址。
   - 服务器逻辑数据不包含该成员。
   - 空 Zone 仍存在。

设备命令成功、服务器 HTTP 成功和整条业务链成功必须分别记录。

## 10. 风险控制

- 写前标记可能产生无害的额外待上传状态，但优先保证不丢修改。
- 不改变全局 NotificationCenter 协议，避免影响其他设备同步业务。
- 成员清理只发生在 Space Trigger Zone 编辑工作副本和保存流程，不全局迁移历史数据。
- 不重构 `SyncDevicesViewController`，只移除业务页面的重复通知。
- Risk 3 只修改导出门禁；现有导入兜底保持不变并由契约测试保护。
- 不修改协议层，真机仅需验证既有 Neighbor Set / Disable 行为是否符合预期。
