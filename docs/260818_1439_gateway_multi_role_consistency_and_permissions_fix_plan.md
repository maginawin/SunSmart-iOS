# Gateway 多角色一致性与 Space 权限修复方案

> 2026-08-18 补充决策：用户确认不调整后端接口，因此本文阶段 C/D 和
> `serverUpdateTimestamp` 建议不再实施。现有接口下的最终方案见
> `docs/260818_1449_gateway_existing_cloud_sync_and_no_backend_fix_plan.md`。

## 1. 目标

在尽量不改变现有 Owner、Editor 使用习惯的前提下，解决以下问题：

1. Owner 修改 Gateway 名称后，Editor 仍显示旧名称。
2. Editor 只拥有部分 Space 权限时，Gateway 关联 Space 的展示、添加、解绑和设备同步必须保持权限边界。
3. 明确 Editor 删除 Gateway、Force Clear Spaces 等破坏性操作的真实权限。
4. 明确 Gateway 是否需要独立的服务器版本字段，以及能否复用 Site `updateTimestamp`。
5. 覆盖 Gateway 在 Owner 设备上重置并重新添加后的生命周期变化。

本方案只规划修复，不在本轮修改业务代码。

## 2. 已确认的现网事实

### 2.1 本次数据

- Site ID：`BBEE852F-DFC0-41C1-AFB3-C28BF17633EE`
- iPad User ID：`6003A832-B1EC-4D13-8E37-F927C7A7BA75`
- Site 角色：`editor`
- iPad 可见并可编辑的 Space：`wifi`
- iPad 不拥有 `Space 1` 的 Space 数据和 Key。
- Gateway ID：`D499FFB45841`
- 服务器 Gateway 名称：`Gateway1`
- Gateway 服务器关联范围：`Space 1/index 2`、`wifi/index 1`
- Gateway 设备当前 `subnetAppkeyIndexs`：`[1, 2]`
- `get/siteprops` 顶层 Site 有 `updateTimestamp`。
- `get/siteprops.data.gateways[]` 没有 Gateway 级 `updateTimestamp`。

因此，Owner 与 Editor 的名称差异不是服务器按角色返回了不同名称，而是 Editor 本地旧 Gateway 缓存没有接受服务器值。

### 2.2 当前 Gateway 导入逻辑

当前导入按 MAC 查找本地 Gateway，然后读取：

- 服务器：`gateways[].updateTimestamp`，缺失时得到 `0`；
- 本地：`GatewayModel.lastUpdate`；
- 只有服务器值大于本地值，或本地不存在时，才替换 Gateway/Node。

现网没有返回该字段，所以已有缓存通常不会更新。这可以直接解释 `Gateway111` 长期保留。

当前整 Gateway 替换还会移除旧 Node、重新导入服务器 Node，影响面明显大于“更新名称”本身，不适合用 Site 时间戳粗粒度触发。

### 2.3 当前 App 已有的 Gateway 时间字段

`GatewayModel` 已有：

- `lastUpdate`
- `lastUploadCloudTimestamp`
- `needUploadCloud = lastUpdate > lastUploadCloudTimestamp`

数据库也已持久化对应字段；`gateway/regist` 会把 `lastUpdate` 放入请求体的 `updateTimestamp`。

但当前已确认的接口语义是：服务器不使用这个请求字段做覆盖、冲突检测或版本判断。App 在上传成功后只是推进 `lastUploadCloudTimestamp`，用于确认某一代本地修改已上传。

结论：当前 App 有 Gateway 的“本地修改代次”，没有真正端到端的“服务器 Gateway 版本”。

### 2.4 当前配置入口权限

`SiteData.canConfigureGateway` 的规则是：

- Owner：允许；
- 非 Owner：只要拥有任意一个可编辑且包含 `.edit` 操作的关联 Space，就允许进入和配置整个 Gateway；
- Gateway 没有关联 Space 时，只要用户在 Site 中拥有任意可编辑 Space，也允许配置。

这意味着子集 Editor 当前可以修改 Gateway 全局名称、APN、服务器信息等。为了降低回归风险，本方案暂不收紧这个既有入口权限，只解决数据一致性和越权修改关联范围的问题。

### 2.5 当前关联 Space 行为

已有的正确保护包括：

- 候选 Space 只来自 Editor 本地可编辑且具有 `.edit` 操作的 Space；
- 已关联但无权限的 Space 会显示为不可选状态；
- 单行解绑入口要求该 Space 权限为 `.editor`；
- 选择器回调会把无权限的既有关联继续带回，通常不会主动删除。

仍存在以下风险：

1. 权限判定不一致：一个位置只检查 `canEditing`，其他位置同时检查 `canEditing` 和 `.edit`。
2. 保存前没有基于最新服务器关联列表重新校验 add/unbind diff。
3. 权限在页面打开后变化时，旧草稿仍可能发出请求。
4. 添加和解绑逐条执行，部分成功后如果后续失败，本地草稿与服务器真实拓扑可能不一致。
5. Editor 本地没有无权限 Space 的 Key，不能把本地 `applicationKeys` 当作 Gateway 完整目标集合。

### 2.6 当前删除行为

当前 Editor 只要拥有任意一个关联 Space 的编辑权限，就会在菜单中看到并可点击 Delete。

但在真正请求 `gateway/delete` 之前，App 会重新请求服务器 Gateway 关联列表：

- Owner：直接允许；
- 非 Owner：要求服务器返回的所有关联 Space 都映射为 `.editor`；
- 有任何一个无权限关联：拒绝，不发送删除请求；
- 关联列表为空：Swift `allSatisfy` 对空集合返回 true，因此保留现有“任一 Site Editor 可删除未关联 Gateway”的行为。

所以对本次只拥有 `wifi` 的 iPad Editor：

- 可以看到、点击 Delete，并看到确认框；
- 正常情况下不能真正请求删除同时关联 `Space 1` 的 Gateway；
- 如果服务器关联列表返回不完整，客户端保护可能失效，因此服务器仍必须做最终权限校验。

Force Clear Spaces 已经采用更严格的菜单权限，并在执行前再次请求服务器校验。这个二次校验不是无意义冗余，而是防止权限在页面打开后发生变化。

## 3. 总体设计原则

### 3.1 Gateway 是 Site 级全局实体

同一 MAC 的 Gateway 名称只有一个服务器真值。Owner 和所有可访问该 Gateway 的 Editor 必须展示同一个名称，不为不同角色维护独立名称副本。

### 3.2 Space 权限是逐 Space 的

Editor 对某个 Space 有编辑权限，不代表其有权修改同一 Gateway 的其他关联 Space。

无权限关联在 Editor 端应作为只读、不透明数据处理：

- 可以知道 Gateway 还关联了该 Space；
- 可以显示服务器提供的名称、数量和 AppKey index；
- 不要求持有该 Space 的 NetKey/AppKey；
- 不能解绑、替换或在全量同步中被遗漏。

### 3.3 展示权限与执行权限分层

- 页面和菜单使用本地缓存权限，保证 UI 稳定和快速。
- 写操作执行前使用最新服务器关联列表再次校验，防止权限变化和并发拓扑变化。
- 服务器对 bind、unbind、unbind-all、register、delete 继续做最终权限校验。

### 3.4 本地修改代次与服务器版本分离

- `lastUpdate/lastUploadCloudTimestamp` 继续只负责客户端 dirty generation 和上传确认。
- 新增的服务器版本必须使用不同属性，避免一个字段同时代表两个时钟和两类冲突语义。

## 4. 统一权限矩阵

建议新增一个无 UI 依赖的统一策略，例如 `GatewayAccessPolicy`，让菜单、关联列表、保存和破坏性操作使用同一规则。

| 操作 | Owner | Editor：仅部分关联 Space | Editor：全部关联 Space | Visitor |
| --- | --- | --- | --- | --- |
| 查看 Gateway | 允许 | 至少一个关联 Space 可编辑时允许 | 允许 | 保持现有规则 |
| 修改 Gateway 名称/全局字段 | 允许 | 暂时保持现有允许 | 允许 | 禁止 |
| 添加 Space 绑定 | 所有符合条件的 Space | 仅自己可编辑且具有 `.edit` 的 Space | 仅自己可编辑且具有 `.edit` 的 Space | 禁止 |
| 解绑单个 Space | 允许 | 仅可解绑自己可编辑的目标 Space | 允许解绑自己可编辑的目标 Space | 禁止 |
| 修改无权限关联 | 允许 | 禁止并原样保留 | 不适用 | 禁止 |
| 全量 Force Clear | 允许 | 禁止 | 允许 | 禁止 |
| 删除 Gateway | 允许 | 禁止 | 允许 | 禁止 |
| 全量 Gateway Recovery | 允许 | 禁止；只允许安全的局部修复 | 允许 | 禁止 |

未关联 Gateway 的 Editor 配置/删除能力先保持现有行为，避免扩大本次产品权限调整范围。如果后续要收紧为 Owner-only，应另立产品需求。

## 5. 修复 Owner/Editor 名称不一致

### 5.1 App-only 兼容修复

在服务器尚未提供 Gateway 版本前，增加 Gateway 云快照的字段级合并策略：

1. 以标准化 MAC 定位同一个 Gateway。
2. 当本地 Gateway 不 dirty、没有进行中上传、没有删除待 Reset 状态时，服务器 `name` 覆盖本地 `GatewayModel.name`。
3. 同步更新本地 Node 的 `name`，保证 Gateway 页面、Site 页面和后续导出使用同一名称。
4. 只更新服务器权威且安全的展示字段，不因为缺少 Gateway 时间戳而移除并重建整个 Node。
5. 字段相同则不写数据库，避免每次进入 Site 都产生无效写入。

这个修复可直接解决当前 iPad 上 `Gateway111` 不收敛的问题，并且不依赖后端先上线。

### 5.2 本地 dirty 冲突保护

如果 Editor 本地刚修改名称但尚未成功上传，不能用旧服务器名称静默覆盖：

- 保留本地名称和 dirty 状态；
- 继续现有重试流程；
- 上传成功并重新获取服务器快照后再收敛；
- 失败继续显示现有云同步错误，不在本次新增复杂冲突 UI。

### 5.3 重置并重新添加的生命周期处理

同一个 MAC 在 Owner 端 Reset 后重新添加，服务器 Node UUID、unicast address、deviceKey 或 Mesh 组成信息可能改变。名称字段合并不足以修复这种情况。

建议引入 Gateway 远端身份判断：

- MAC 相同且 Node UUID/address 等身份一致：按同一生命周期做字段级合并；
- MAC 相同但服务器 Node UUID 或关键身份已变化：视为新生命周期；
- 本地 clean 时，安全替换旧 Node 与 Gateway 绑定关系；
- 本地 dirty 或处于删除流程时，不直接覆盖，记录冲突并等待刷新/重试策略处理。

不能只依赖 MAC，也不能只依赖缺失的 `updateTimestamp`。

## 6. Space 绑定、添加、解绑方案

### 6.1 统一 Space 可编辑判定

统一使用：

`space.canEditing && space.deviceOperates.contains(.edit)`

替换以下分散语义：

- Gateway 详情关联列表；
- Gateway Associated Spaces 选择器；
- 候选 Space 生成；
- 单行解绑；
- 保存前 diff 校验；
- Delete/Force Clear 的全关联权限判断。

`permissionLoss`、`permissionException` 和 `.none` 均视为不可修改。

### 6.2 草稿模型分区

关联选择器内部明确分成：

- `lockedAssociations`：服务器已关联、当前用户无编辑权限；
- `editableAssociations`：当前用户可编辑的既有关联；
- `editableCandidates`：当前用户可添加的候选。

最终提交草稿必须满足：

`finalAssociations = lockedAssociations ∪ selectedEditableAssociations`

Select All、Deselect All、单项点击都只能改变 editable 集合。locked 集合不参与取消选择，也不能因为本地没有对应 Space/Key 而消失。

### 6.3 保存前重新校验

点击 Save 后，在调用 bind/unbind API 前：

1. 重新获取 Gateway 的服务器 `refSpaces`。
2. 根据当前用户最新 Space 权限重新计算 locked/editable 集合。
3. 将草稿与最新服务器拓扑做 diff。
4. 只允许 add/unbind diff 中的每个 Space 都由当前用户编辑。
5. 如果权限或拓扑在编辑期间变化，停止本次保存、刷新页面，不使用旧草稿继续部分执行。

这层校验和服务器校验同时保留。

### 6.4 部分成功处理

为了避免改造现有接口，第一阶段仍可逐条调用 bind/unbind，但必须：

- 每成功一条就记录服务器已确认的变更；
- 任一后续请求失败时，立即重新请求 `refSpaces`；
- 用服务器真实结果替换本地 persisted/draft associations；
- 不把原始完整草稿保存为已成功状态；
- 继续保留现有失败提示。

后端将来可提供事务型 Gateway association patch 接口，但不作为本次 App 修复前置条件。

### 6.5 服务端权限契约

服务端至少应保证：

- bind：Owner 或目标 Space Editor；
- unbind：Owner 或目标 Space Editor；
- unbind-all：Owner，或对所有当前关联 Space 都是 Editor；
- delete：Owner，或对所有当前关联 Space 都是 Editor；
- register/name update：与 App 当前“任一关联 Space Editor 可修改全局字段”的既有策略一致；
- 关联列表接口给已授权访问 Gateway 的 Editor 返回完整 `refSpaces` 元数据，但不返回无权限 Space 的密钥。

如果后端不能保证完整 `refSpaces`，客户端不能据此授权 delete/unbind-all，必须按失败处理。

## 7. Editor 删除 Gateway 的处理建议

### 7.1 结论

“只拥有部分 Space 权限的 Editor 可以直接删除 Gateway”在当前实现中只对 UI 入口成立，对实际服务器请求通常不成立。

### 7.2 最小影响调整

1. Delete 菜单展示改为与 Force Clear 相同的缓存权限：Owner，或本地已知全部关联 Space 都为 `.editor`。
2. 点击删除后的服务器 `refSpaces` 二次校验继续保留。
3. 二次校验失败时不发送 `gateway/delete`。
4. 服务器继续做最终权限校验。
5. `serverDeletionPendingLocalReset` 只恢复已经完成服务器删除后的本地 Reset，不重复执行新的删除授权。

如果产品接受“菜单可见、点击后才提示无权限”的冗余交互，也可以暂时保留菜单现状；但执行前二次校验不能删除。推荐同步收敛菜单，以减少误导和无效确认步骤。

## 8. `Devices not synced` 与权限范围

### 8.1 当前误报原因

本次 iPad 本地只有 AppKey index 1，设备实际和服务器期望都是 `[1, 2]`。如果 App 用本地可解析的 `node.applicationKeys` 生成完整目标，就只得到 `[1]`，从而把正确的 `[1, 2]` 判为未同步。

### 8.2 状态判定

Gateway 关联索引的完整期望值应来自服务器完整 `refSpaces` 或 Gateway 服务器快照，而不是 Editor 本地 Key 集合。

- 期望：`[1, 2]`
- 设备：`[1, 2]`
- 结果：已同步，不显示 `Devices not synced`。

### 8.3 局部修改安全规则

子集 Editor 修改自己有权限的 Space 时：

- 添加：只添加目标 Space 的 NetKey/AppKey/index；
- 解绑：只移除目标 Space 的 NetKey/AppKey/index；
- 无权限 index 作为 opaque index 原样保留；
- 禁止把本地可见 `[1]` 当成全量目标写入设备，覆盖掉 `[2]`；
- 只有 Owner 或全部关联 Space Editor 才可执行需要完整 Key 集合的全量 Recovery。

如果某个异常只发生在无权限 Space，子集 Editor 不应得到一个可执行但注定不完整的全量修复入口；Owner 端负责全量修复。

## 9. Gateway 服务器版本设计

### 9.1 不建议使用 Site `updateTimestamp`

Site 时间戳只能说明 Site 聚合快照发生变化，不能说明哪个 Gateway、哪个字段发生变化。直接用它作为 Gateway 替换条件会产生以下问题：

1. Site 名称、时区、任意 Space 修改都可能触发 Gateway 整体重建。
2. 多 Gateway 无法独立比较版本。
3. Gateway 本地 dirty 可能被不相关 Site 更新覆盖。
4. 当前 Gateway 导入会移除并重新添加 Node，影响 Mesh 运行期状态和本地保存信息。
5. 客户端不能用本地 Gateway 时间猜测服务器 Site 时间，也不能因此推进 `SiteData.lastUpdate`。

Site `updateTimestamp` 最多可作为“Site 快照已变化”的刷新提示，不能作为 Gateway 数据冲突和覆盖版本。

### 9.2 推荐新增独立服务器字段

推荐后端为每个 Gateway 持久化并返回服务器生成的单调版本，例如：

- API 字段：`gateways[].updateTimestamp`
- App 属性：`GatewayModel.serverUpdateTimestamp: Int64?`

不要复用当前 `lastUpdate` 或 `lastUploadCloudTimestamp`：

- `lastUpdate`：本地 dirty generation；
- `lastUploadCloudTimestamp`：本地 generation 的上传确认；
- `serverUpdateTimestamp`：最后一次已应用的服务器 Gateway 快照版本。

后端版本应由服务器生成，不直接信任客户端墙钟。

### 9.3 需要推进 Gateway 版本的操作

至少包括：

- register/rename/global configuration；
- bind Space；
- unbind Space；
- unbind all Spaces；
- Gateway 服务器配置变更；
- Reset 后重新注册到 Site；
- 会改变 `siteprops.gateways[]` 权威内容的其他操作。

删除使用资源消失或 tombstone/lifecycle 语义，不要求客户端用旧实体时间戳覆盖新实体。

### 9.4 上传和拉取流程

建议流程：

1. App 本地修改继续推进 `lastUpdate`。
2. 上传请求继续携带现有 generation，以兼容旧接口；如需乐观并发，另传 `baseServerUpdateTimestamp`，不要复用一个字段。
3. 服务器合并后生成新的 Gateway `updateTimestamp`。
4. 响应最好返回该版本；旧接口不返回时，由下一次 `siteprops` 获取。
5. App 保存到 `serverUpdateTimestamp`。
6. 拉取时按服务器版本、生命周期身份和本地 dirty 状态决定字段合并或整体替换。

### 9.5 旧服务器兼容

在 `gateways[].updateTimestamp` 缺失期间：

- clean Gateway：允许安全字段级合并名称；
- dirty Gateway：保护本地修改；
- 身份变化：按生命周期规则处理；
- 不把缺失解析为有意义的 `0` 后继续做严格大于比较；
- 不使用 Site 时间戳触发全 Gateway/Node 重建。

## 10. 防止部分 Editor 的全量注册覆盖

Editor 本地没有无权限 Space 的 Key，因此 `gateway/regist` 不能把 Editor 上传的 Node 数组当成 Gateway 完整权威快照。

推荐按优先级处理：

1. 最优：新增字段级 Gateway patch，名称修改只提交 `name` 和 base server version。
2. 次优：服务器按字段 merge，Editor 缺失的 `netKeys/appKeys/subnetAppkeyIndexs/associatedSpaces` 不代表删除。
3. 客户端继续把无权限 association/index 作为 opaque 数据保留，但绝不能伪造未知 Key 内容。

否则即使名称同步修复，子集 Editor 的一次 rename/register 仍可能把 Owner 侧完整 Gateway 数据覆盖成局部数据。

## 11. 实施阶段

### 阶段 A：App 兼容热修复

1. 抽取 Gateway 云快照解析与字段级合并策略。
2. Gateway timestamp 缺失时，clean 本地缓存仍接受服务器名称。
3. 同步更新 GatewayModel 和 Node 名称。
4. 增加 Reset/re-add 身份变化判断。
5. Editor 响应不是完整 Gateway 列表时，不因服务器列表中缺失就删除本地 Gateway/Node；只有 Owner 或接口明确声明完整快照时才执行缺失删除。
6. 修正 `Devices not synced` 的完整 index 来源。

阶段 A 不改变数据库结构，也不等待后端，可优先验证当前案例。

### 阶段 B：权限策略收敛

1. 新增统一 `GatewayAccessPolicy`。
2. 关联选择器统一使用 `canEditing && .edit`。
3. 明确 locked/editable association 分区。
4. 保存前重新请求并校验 refSpaces。
5. 部分失败后以服务器结果回滚/刷新本地草稿。
6. Delete 菜单使用全关联权限；执行前二次校验保留。
7. 全量 Recovery/Force Clear 只允许 Owner 或全部关联 Space Editor。

### 阶段 C：后端 Gateway 独立版本

1. 后端持久化 Gateway `updateTimestamp`。
2. 所有 Gateway 写接口推进该版本。
3. `siteprops.gateways[]` 和写接口响应返回该版本。
4. App 新增可空 `serverUpdateTimestamp` 数据库列和兼容迁移。
5. 导入策略从 legacy field merge 平滑切换到版本化 merge。

### 阶段 D：字段级 Gateway API

1. 名称和全局配置使用 patch，而不是部分 Editor 上传整份 Node。
2. 增加可选 `baseServerUpdateTimestamp` 做并发控制。
3. 服务器返回合并后的规范 Gateway 和新版本。

阶段 D 可与阶段 C 合并实施；如果后端周期较长，阶段 A、B 可先上线。

## 12. 预计代码影响范围

优先聚焦以下位置：

- `SunSmart/Common/Data/ImportData.swift`
- `SunSmart/Common/Data/Database.swift`
- `SunSmart/Main/Device/Gateway/Model/GatewayModel.swift`
- `SunSmart/Main/Device/Gateway/Model/GatewayMenuPolicy.swift`
- `SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift`
- `SunSmart/Main/Device/Gateway/Controller/GatewayAssociatedSpacesController.swift`
- Gateway recovery/sync target 生成相关策略
- `SunSmart/Common/Network/NetowrkReqeustApi.swift`，仅在后端契约确定后修改

建议新增独立纯策略文件和测试，不在 ViewController 内继续叠加分支。

## 13. 测试计划

### 13.1 名称与版本

- Owner `Gateway111 -> Gateway1`，Editor 下次进入 Site 显示 `Gateway1`。
- Gateway timestamp 缺失、本地 clean：名称合并成功，不重建 Node。
- Gateway timestamp 缺失、本地 dirty：不覆盖本地草稿。
- 服务器版本更高：按策略更新。
- 服务器版本相同：幂等，不写数据库。
- 同 MAC、Node UUID/address 变化：按新生命周期处理。
- Site timestamp 变化但 Gateway 未变化：不重建 Gateway。

### 13.2 Space 权限

- Owner 可添加/解绑任意符合条件 Space。
- 子集 Editor 只能添加/解绑自己的 Space。
- 无权限既有关联在 Select All/Deselect All/保存后仍存在。
- 页面打开后权限被撤销，保存前校验阻止请求。
- bind 成功、unbind 失败后，本地重新加载服务器真实关联。
- Editor 缺少 AppKey index 2 时，任何操作都不能从 Gateway 删除 index 2。

### 13.3 删除与 Force Clear

- 子集 Editor 菜单不显示 Delete/Force Clear。
- 即使通过旧入口触发，执行前校验仍拒绝且不请求 delete/unbind-all。
- 全关联 Editor 和 Owner 可以执行。
- 服务器关联列表不完整或请求失败：按失败处理，不放行。
- 未关联 Gateway 保持现有 Editor 行为。

### 13.4 `Devices not synced`

- 服务器期望 `[1,2]`、设备 `[1,2]`、Editor 本地只有 `[1]`：不显示未同步。
- Editor 添加 index 1 时保留 opaque index 2。
- Editor 解绑 index 1 时保留 opaque index 2。
- 只有无权限 index 异常时，不提供会覆盖全量配置的修复动作。

### 13.5 回归与构建

- 扩展 `GatewayMenuPolicyTests`。
- 扩展 `GatewayAssociatedSpaceCandidatePolicyTests`。
- 扩展 `GatewayForceClearSpacesContractTests`。
- 新增 Gateway access policy、snapshot merge、remote identity、version parser 测试。
- 增加 import contract，覆盖 Editor 非完整 Gateway 列表不能删除本地缓存。
- 运行现有 Gateway associated-spaces 脚本检查。
- 使用 generic iPhoneOS、关闭签名构建 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart`，因为相关代码位于共享 Common/Gateway 模块。
- 最终仍需 Owner iPhone、Editor iPad、真实 Gateway 和服务器联合验收；单元测试与无签名构建不能证明真实 Mesh/云端结果。

## 14. 验收标准

1. 同一服务器 Gateway 对 Owner、Editor 展示相同名称。
2. 子集 Editor 不会删除、解绑或覆盖无权限 Space 的关联和 Key index。
3. 子集 Editor 不会因为本地 Key 不完整看到错误的 `Devices not synced`。
4. Delete、Force Clear、全量 Recovery 的 UI 与执行权限一致，且执行前仍做服务器校验。
5. Gateway 本地 dirty generation 与服务器版本语义分离。
6. 不使用 Site `updateTimestamp` 作为 Gateway 整体覆盖版本。
7. Reset/re-add 后，旧生命周期缓存可以安全收敛到服务器新实体。
8. Owner 现有 Gateway 配置、绑定和删除流程不发生非预期变化。

## 15. 推荐结论

建议采用“阶段 A + 阶段 B 先行，阶段 C/D 配合后端”的路线：

- 立即用字段级 clean merge 修复当前名称不一致；
- 统一 Space 权限策略，保留无权限关联和 index；
- Delete 菜单收紧，但执行前实时校验继续保留；
- 不使用 Site `updateTimestamp` 替代 Gateway 版本；
- 后端增加 Gateway 级服务器版本，App 新增独立 `serverUpdateTimestamp`，不复用现有两个本地 generation 字段；
- 长期将名称更新改为字段级 patch，避免部分 Editor 上传局部 Node 快照覆盖 Owner 的完整数据。
