# 4G Gateway Associated Spaces 显示 No Data 分析与待确认修复方案

## 1. 结论

当前两个空态来自不同数据源：

- 4G Gateway 详情页的 `No associated spaces`：只表示当前编辑草稿 `setGatewayModel.associatedSpaces` 为空。
- Associated Spaces 选择页的 `No Data !`：表示“本地生成的可选 Space”与“服务器返回的当前网关已绑定 Space”合并后仍为空。

本次现象不是前一页面空态的自然延续。用户拥有 2 个未绑定 Space，但选择页仍显示 `No Data !`，说明这 2 个 Space 在进入选择页前已被本地候选生成逻辑全部过滤，或者其 AppKey 无法从当时使用的 MeshNetwork 中解析。

从现有源码看，最高优先级的结构性问题是 MeshNetwork 数据源不一致：

- Site 页面加载 Gateway 时，已经显式从 Site Primary MeshNetwork 解析 Gateway。
- Associated Spaces 入口仍读取全局 `MeshNetworkManager.instance.meshNetwork`。
- 因此 Gateway 可以从正确 Site 主网成功进入，但候选 Space 的 AppKey 可能在另一个 Site、旧的内存快照或尚未完成切换的全局 MeshNetwork 中查找，最终被 `compactMap` 静默丢弃。

该问题同时影响 4G Gateway 与 WiFi Gateway，因为 `WiFiGatewayViewController` 继承 `GatewayViewController`，没有覆盖 Associated Spaces 入口。

以上结构性缺陷已由源码确认；要确认测试反馈中的真机数据最终落在哪个过滤分支，仍需要一次包含 Space 权限、gatewayId、meshNetworkId 和 AppKey 命中结果的运行时证据。

## 2. 页面在什么情况下显示空态

### 2.1 Gateway 详情页：No associated spaces

`GatewayViewController` 的 Associated Spaces section 至少渲染一行。当 `setGatewayModel.associatedSpaces` 为空时，显示 `no_associated_spaces`。

可能来源：

1. 当前 Gateway 从未绑定过 Space。
2. 服务器关联查询成功并返回空的 `refSpaces`。
3. 用户在当前编辑草稿中移除了全部 Space，但尚未点击 Gateway 页面的 `SAVE`。
4. 关联数据尚未加载完成或本地 GatewayModel 缓存为空。

这个空态本身不代表 Site 没有可绑定 Space。

### 2.2 Associated Spaces 选择页：No Data !

选择页只在关联查询成功后判断是否显示 `no_data`。判断条件是合并后的 `spaces.count == 0`。

合并数据由两部分组成：

1. Gateway 页面传入的本地候选 Space。
2. `/sitespace/sapce/gateway/reference` 返回并成功解析的当前 Gateway 已绑定 Space。

因此出现 `No Data !` 必须同时满足：

- 本地候选 Space 为空；并且
- 服务器没有返回任何可成功解析的已绑定 Space。

网络失败不会显示 `No Data !`：

- 手机无网络显示 `gateway_associated_no_network_message`。
- 其他请求失败显示 `Failed to retrieve data.`、网络说明和 `RETRY`。

## 3. 本地候选 Space 被清空的全部条件

`GatewayViewController.associatedSpaces()` 先对 `site.spaces` 做过滤，再按 AppKey 做映射。以下任一类条件覆盖全部 Space 时，传入选择页的本地候选数组就会为空。

### 3.1 Site 本地数据没有 Space

- `site.spaces` 本身为空。
- SiteInfo 尚未完成导入，Gateway 页面拿到的是过期的 SiteData。
- Space 列表刷新与打开 Gateway 的时序发生竞争。

本次用户已经在 Site 中看到 2 个 Space，因此不是首选假设，但仍需确认传入 Gateway 的 `site.spaces` 与页面展示数组是同一时刻的数据。

### 3.2 Space 没有有效编辑能力

候选必须同时满足：

- `space.canEditing == true`。
- `space.deviceOperates` 包含 `.edit`。

会被排除的状态包括：

- Space 权限是 Visitor。
- Space 状态是 `waitDeleted`。
- Space 需要重新验证密码。
- `disableEditorPermission == true`。
- `meshOTADistribution == true`。

Site Owner 可以进入 Gateway 页面，但候选仍逐个检查 Space 编辑能力，因此“可以进入 Gateway”不等于“所有 Space 都可被列为候选”。

### 3.3 Space 被判定为属于其他 Gateway

候选只接受：

- `relevanceGatewayId == nil`；或
- `relevanceGatewayId == 当前 gateway.mac`。

下列情况会被排除：

- Space 确实绑定到其他 Gateway。
- SiteInfo 中保存了过期的 gatewayId。
- gatewayId 与 Gateway MAC 只有大小写或格式差异，但使用了区分大小写的字符串比较。

正常 SiteInfo 导入会把缺失或空字符串 gatewayId 归一为 `nil`。如果这 2 个 Space 在服务器真值中确实未绑定，这一层应当通过。

### 3.4 找不到 Space 对应的 AppKey

通过前述过滤后，每个 Space 还必须在当前取到的 MeshNetwork 中找到一个 AppKey，其绑定 NetKey 的 networkId 与 `space.meshNetworkId` 相等。

找不到时，代码直接返回 `nil`，不会向 UI 暴露原因。全部 Space 都找不到时，就会表现为 `No Data !`。

可能场景：

- 全局当前 MeshNetwork 属于另一个 Site。
- Site 页面正在异步切换到 Primary Network，用户在切换完成前打开 Gateway。
- 全局 MeshNetwork 是旧的内存快照，尚未包含新导入 Space 的 NetKey/AppKey。
- 本地数据库确实缺少 Space 的 AppKey。
- `space.meshNetworkId` 与 NetKey networkId 不一致。
- NetKey 已存在但 AppKey 缺失；当前 Space 导入修复逻辑只在 NetKey 不存在时一并补 NetKey 和 AppKey，无法单独修复缺失的 AppKey。

### 3.5 服务器返回的已绑定 Space 无法补回

选择页请求成功后，`refSpaces` 中每项必须同时包含：

- `spaceId`
- `spaceName`
- `deviceCount`
- `appKey.index`

任一字段缺失或类型不匹配都会被静默丢弃。如果当前 Gateway 没有绑定 Space，服务端返回空数组属于正常情况，不能帮助补回本地未绑定候选。

## 4. 根因优先级

### P1：Associated Spaces 使用了错误或陈旧的全局 MeshNetwork

可信度：高。

证据：

1. Site Gateway 的解析已改为显式 `sitePrimaryMeshNetwork()`，不依赖全局当前网络。
2. Associated Spaces 仍直接使用 `MeshNetworkManager.instance.meshNetwork`。
3. Site 页面在 `viewDidAppear` 中异步切换 Site Primary Network，入口没有等待或校验该切换结果。
4. AppKey 未命中会被静默过滤，最终刚好呈现本次 `No Data !`。
5. 2026-07-24 的 Gateway online 状态修复让 Gateway 可从显式 Site 主网解析；候选生成仍保留旧的全局依赖，两条路径由此产生不一致。

最小确认方式：

- 在进入 Associated Spaces 时记录 Site meshUUID、全局 meshUUID、当前 NetKey 是否 Primary。
- 对 2 个 Space 逐项记录 permission、canEditing、device edit、relevanceGatewayId、meshNetworkId 和 AppKey 是否命中。
- 若前两层通过而 AppKey 均未命中，即可确认。

### P2：AppKey 数据本身缺失或内存快照未刷新

可信度：中。

即使全局 MeshNetwork 属于正确 Site，也可能因为新 Space 的 Key 只写入了另一个 MeshNetwork 实例或数据库，当前内存实例仍不完整。现有导入逻辑还存在“NetKey 已存在时不单独补 AppKey”的缺口。

这个原因应在 P1 修复使用显式、最新 Site 网络快照后继续验证，避免直接扩大到全局 Key 导入修复。

### P3：权限、过期 gatewayId 或 SiteData 时序

可信度：低到中。

这些条件都能独立造成相同空态，但与“2 个 Space 均未绑定”这一事实相比，解释力弱于 AppKey/网络上下文问题。运行时逐项原因记录可以一次排除。

### P4：服务器 refSpaces 返回异常

可信度：低。

该接口只补当前 Gateway 已绑定 Space。当前详情本来就显示没有关联 Space，因此服务端返回空 `refSpaces` 合理；它不是“所有可绑定 Space”的数据源。

## 5. 修复方案比较

### 方案 A：显式 Site 网络快照 + 可解释的候选解析

推荐。

核心：

1. Associated Spaces 候选生成不再读取隐式全局 MeshNetwork。
2. 使用与 Site/Gateway 一致的 siteId、meshUUID 和 Primary Network 数据源，必要时从本地 Mesh 数据库重新加载最新快照。
3. 把候选判断集中为一个可测试的解析策略，至少区分：
   - 可选择；
   - 无编辑能力；
   - 已绑定其他 Gateway；
   - 缺少 AppKey。
4. 只有“确实不存在可选择 Space”时展示 `No Data !`。
5. 若存在符合权限和绑定条件的 Space，但 AppKey 全部缺失，则按数据加载失败处理并允许重试，不再伪装成业务空态。
6. 服务器接口继续只补当前 Gateway 已绑定 Space，不改变现有保存边界。

优点：

- 修复根因，不依赖页面打开时全局 Mesh 切换是否完成。
- 同时覆盖 4G 与 WiFi Gateway 的共享入口。
- 能将真实空态与本地 Key 数据异常区分开。
- 不改变现有云端 bind/unbind、Gateway `SAVE` 和设备同步语义。

代价：

- 需要增加候选解析测试和一条数据异常分支。
- 如最终确认数据库也缺 AppKey，需要在同一方案内增加最小 Key 恢复处理。

### 方案 B：进入 Gateway 或 Associated Spaces 前强制切换全局 MeshNetwork

不推荐。

做法是等待 `MeshLibManager` 切到 Site Primary Network 后再开放入口。

问题：

- 修改全局 BLE/Mesh 运行上下文，影响面大。
- 仍无法保证当前内存快照包含新 Space AppKey。
- 引入异步等待、页面时序和连接状态风险。
- 候选构建继续依赖隐式状态，后续容易复发。

### 方案 C：取消 AppKey 门槛，先展示全部未绑定 Space

不推荐。

这样虽然能显示 2 个 Space，但保存和设备侧同步仍需要正确的 AppKey index。把错误推迟到 `SAVE` 或 Mesh 同步阶段，会造成更难理解的失败，属于症状修复。

## 6. 待确认实施计划

本计划在用户确认后再进入代码实施。

### 阶段 1：先建立失败证据

1. 为 Associated Spaces 候选策略增加 RED 测试。
2. 覆盖“Site 有 2 个可编辑、未绑定 Space，但全局当前 Mesh 属于其他 Site”的回归场景。
3. 覆盖权限不足、已绑定其他 Gateway、缺 AppKey、当前 Gateway 已绑定 Space等边界。
4. 证明旧实现会把前述 2 个有效 Space 过滤为空。

### 阶段 2：最小修复候选数据源

1. 将候选解析从 `GatewayViewController.associatedSpaces()` 的内联过滤中提取为单一策略。
2. 输入显式 Site Primary MeshNetwork 快照，不再读取全局当前 MeshNetwork。
3. 保留现有编辑权限和“不能抢占其他 Gateway Space”的规则。
4. 保留现有 Gateway 草稿模型和外层 `SAVE` 统一提交语义。

### 阶段 3：拆分真实空态与 Key 数据异常

1. 候选为零且没有任何业务上合格的 Space时，继续显示 `No Data !`。
2. 存在业务上合格的 Space但缺 AppKey 时，显示现有“获取数据失败”状态和 `RETRY`，不新增硬编码文案。
3. Retry 重新加载显式 Site 网络快照并重新计算候选。
4. 如果证据确认数据库缺少 AppKey，再增加“只补缺失 AppKey、不重复添加 NetKey”的最小恢复逻辑；未确认前不扩大修改。

### 阶段 4：验证

自动化：

1. 新候选策略 RED→GREEN 测试。
2. 现有 `check_gateway_associated_spaces_deferred_save.sh`。
3. 现有 `check_site_gateway_online_state.sh`。
4. `git diff --check`。

构建：

1. SunSmart generic iPhoneOS Debug。
2. Archipelago generic iPhoneOS Debug。
3. SLG Sync Plus generic iPhoneOS Debug。
4. SylSmart generic iPhoneOS Debug。

真机/服务器验收：

1. Site 有 2 个可编辑且未绑定的 Space，4G Gateway 选择页展示 2 项。
2. WiFi Gateway 共享入口行为一致。
3. Space 已绑定其他 Gateway 时不展示。
4. 当前 Gateway 已绑定 Space 时保持选中。
5. 从其他 Site 或 Space 快速返回并立即进入 Gateway，不再受全局 Mesh 切换时序影响。
6. 选择后不点击 Gateway `SAVE` 退出，关联关系不持久化。
7. 点击 `SAVE` 后，云端绑定、Gateway 本地模型和设备侧 Mesh 同步仍按现有链路执行。

## 7. 预计改动范围

优先控制在：

- `SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift`
- Associated Spaces 候选策略所在的 Gateway Model 文件
- `GatewayAssociatedSpacesController.swift`，仅在需要区分 Key 数据异常和真实空态时做最小状态入口调整
- `Tests/Device/` 或 `Tests/Site/` 下的聚焦测试
- `scripts/` 下的聚焦测试入口

不计划修改：

- 云端 bind/unbind API 契约
- Gateway `SAVE` 提交边界
- WiFi Gateway 专有网络配置逻辑
- NordicSigMeshSDK，除非运行时证据证明缺陷位于 SDK 的 MeshNetwork 加载行为
- 本地化文案；优先复用已有 `failed_to_retrieve_data`、`network_problem_note` 和 `RETRY`

## 8. 确认建议

建议确认方案 A，并先按“显式 Site 网络快照 + 可解释候选解析”实施。

若 RED 测试或运行时证据证明显式最新快照仍缺 AppKey，再把“单独修复缺失 AppKey”作为同一任务的受控第二步；不先行修改全局 Space 导入或 SDK。
