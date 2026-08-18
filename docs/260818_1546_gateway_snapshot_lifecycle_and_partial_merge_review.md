# Gateway 快照生命周期与不完整响应合并评审

## 结论

评审提出的两个 P1 问题都成立，建议在当前 Gateway 多角色一致性改动合入前一并修复。

两者分别破坏了同一保护链的两个阶段：

1. 服务器 Node 快照只存在于本次导入创建的临时 `GatewayModel`，Site 随后从数据库重载 Gateway 后快照丢失；注册时无法保留 Editor 本地不可重建的 Key/Bind 数据。
2. clean Gateway 的字段合并使用由不完整响应构造的完整 `GatewayModel`，缺失字段被转换成默认值后无条件覆盖本地完整配置。

只修快照持久化，仍可能在导入阶段清空本地 Gateway 配置；只修字段合并，注册阶段仍可能上传缺少不可见 Key/Bind 的局部 Node。因此两项必须同时处理。

## 问题一：服务器 Gateway Node 快照生命周期

### 已确认的状态链

1. `SiteData.update` 为 `remoteGateway` 和本次从数据库读取的 `cacheGateway` 赋值 `latestServerNodeSnapshot`。
2. `GatewayModel.save()` 没有保存该属性；`gateways` 表也没有对应字段。
3. Site 导入完成后，`SiteViewController.setupData()` 调用 `loadGatewaysData()`。
4. `loadGatewaysData()` 再次调用 `GatewayModel.load(siteId:)`，构造新的 `GatewayModel`；新对象的 `latestServerNodeSnapshot` 为 nil。
5. 后续 Gateway Register、服务器授权以及普通 Gateway 云同步都从这个重载对象读取快照，最终 `remoteNode` 为 nil。

因此，当前 `GatewayRegistrationPayloadPolicy` 的合并算法虽然能在单元测试提供 `remoteNode` 时保留不透明索引，但真实 Site 刷新后的注册路径通常拿不到该输入。

### 推荐修复

新增一个按 Site + Gateway MAC 持久化的“注册保护快照”，并在 `GatewayModel.load/save` 中恢复和保存。推荐只保存注册合并实际需要的最小字段，而不是整个 `siteprops.gateways[]`：

- `netKeys`
- `appKeys`
- `elements` 中的 Model/Bind 信息
- `gatewayInfo` 中注册合并需要保留的字段
- 用于识别 Gateway 生命周期的 UUID、unicast address、device key 指纹或等价身份信息

不要把 `gatewayPreconfigured`、MQTT 用户名/密码或其他无关服务器字段复制到新增快照，避免扩大敏感数据存储范围。

持久化与更新规则：

- 数据库新增 nullable Data 字段并兼容旧数据库迁移；旧记录为 nil，不阻断加载。
- 同一 Gateway 生命周期内，新的部分响应只更新明确存在且有效的快照分区，不能用缺失分区清空旧快照。
- Owner 的已确认完整响应可以替换对应快照分区。
- UUID、address 或 device key 表明 Reset/Re-add 新生命周期时，先丢弃旧生命周期快照，再建立新快照，禁止把旧 Key/Bind 带到新 Gateway。
- 删除 Gateway、本地强制删除或 Site 删除时，快照随 Gateway 行一并删除。

可选增强是在发起 Register 前读取一次最新服务器快照，以缩短并发窗口；但它不能替代持久化，因为多个注册入口和 App 生命周期仍需要统一的数据来源。

## 问题二：不完整响应被默认值覆盖

### 已确认的状态链

`GatewayModel.import` 会为缺失字段生成业务默认值：

- `gatewayPreconfigured` 整体缺失时，`activate` 初始为 true、关联 Space 为空、APN/MQTT 为 nil。
- `gatewayPreconfigured` 存在但缺少 `activate` 时，`boolValue` 得到 false。
- 缺少 `associatedSpaces` 时，结果仍为空数组。
- MQTT 字段缺失或裁剪时，结果为 nil。

无 Gateway 级 `updateTimestamp` 的 clean Gateway 会进入 `.mergeFields`；随后 `cacheGateway.update(gatewayModel:)` 无条件复制名称、激活状态、关联 Space、APN 和 MQTT。Node 名称及 `gatewayInfo` 也按解析后的完整对象整体替换。

这使“响应没有提供该字段”和“服务器明确要求清空该字段”无法区分，确实可能清除本地完整配置，并在后续保存/注册时上传空值或空关联。

### 推荐修复

不要用 `GatewayModel.import` 生成的完整对象执行 clean merge。新增原始响应驱动的字段级 Patch，例如 `GatewayCloudPatch`，为每个字段保留三态语义：

- absent：响应未提供，保留本地值；
- value：响应提供且类型有效，更新本地值；
- explicit null：仅在接口契约明确表示“清空”时清除本地值。

建议的字段规则：

- `name`：仅顶层 Node payload 明确存在合法名称时更新 Gateway 与 Node 名称。
- `activate`：仅 `gatewayPreconfigured.activate` 明确存在且为 Bool 时更新。
- `associatedSpaces`：仅字段明确存在、数组结构整体有效时替换；单个非法元素应使该字段 Patch 无效，不应静默变成更短数组。
- `apn`、`mqttConnectInfo`：区分 absent 与明确清空；不完整/非法对象不覆盖本地值。
- `gatewayInfo`：按子字段存在性合并，不能因某个裁剪后的 `GatewayInformation` 对象而整体替换。
- Node 的 Key、Bind、Element 等不可见字段只进入注册保护快照，不直接灌入 Editor 的本地 Mesh Network。

`.importNew`、`.replaceRemote` 与 `.mergeFields` 应保持不同语义：

- `.mergeFields` 必须严格执行 presence-aware Patch。
- `.replaceRemote` 只在身份变化已确认且远端满足新 Gateway 的最低完整性要求时替换；否则保留本地并记录/等待下一次完整刷新。
- `.importNew` 可以按现有最低可用字段创建，但必须保留字段完整性状态，不能把“未知”解释成服务器默认配置。

## 推荐实施顺序

1. 先引入独立、可单测的字段存在性 Patch 与最小注册保护快照类型。
2. 修改 clean merge，仅应用明确存在且合法的字段。
3. 为 `gateways` 表增加 nullable 快照字段，补齐 `initDatabase/load/save`。
4. 在 Site Gateway 导入时按角色、响应完整性和 Gateway 生命周期更新快照。
5. 让 Cloud Sync、服务器授权和 Gateway 页面注册入口统一读取持久化后的快照。
6. 补充迁移、重载、部分响应和 Reset/Re-add 测试，再执行四品牌 generic iPhoneOS 构建。

## 必须新增的回归覆盖

- Editor 刷新 Site 后经过 `GatewayModel.save/load`，注册保护快照仍存在。
- App 重启后从数据库加载，注册仍保留不可见的 AppKey/NetKey/Model Bind。
- `gatewayPreconfigured` 整体缺失时，不改变本地 activate、关联 Space、APN、MQTT。
- `gatewayPreconfigured` 仅包含一个字段时，只更新该字段。
- `associatedSpaces` 缺失与明确空数组具有不同结果。
- MQTT 缺失、非法对象、明确清空分别具有不同结果。
- 部分/非法 `associatedSpaces` 不得静默清除合法关联。
- Owner 完整响应可以合法清空关联或可选配置。
- Reset/Re-add 后旧生命周期快照不会合并到新 Node。
- Site 刷新后从 `SiteViewController.loadGatewaysData()` 得到的对象可供三个 Register 入口使用同一快照。

现有 `GatewayCloudSyncGenerationPolicyTests` 只验证向合并函数直接传入内存 `remoteNode` 的结果；现有源码契约测试也只检查属性和调用存在，均无法覆盖数据库重载与字段缺失语义，需补充行为测试。

## 后端建议

App 侧上述修复可以封住当前已知覆盖路径，但从一致性模型看，长期更稳妥的方案仍是让服务器提供 Gateway 级单调版本，并让 `gateway/register` 支持字段掩码、条件写入或服务器端保留未授权字段。这样才能从根本上避免多角色客户端以局部快照覆盖完整服务器对象。

## 验证边界

静态脚本、单元测试和 generic iPhoneOS 构建只能证明本地逻辑与编译通过，不能证明真实服务器按角色返回的字段完整度、Gateway Register 的服务端替换/合并语义、MQTT 或 Mesh 设备最终配置。仍需 Owner/Editor 真实账号进行写后读回和设备侧验收。
