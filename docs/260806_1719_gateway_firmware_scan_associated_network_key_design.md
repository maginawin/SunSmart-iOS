# Gateway 固件升级 Associated Network Key 扫描设计

## 背景与结论

目标 4G Gateway 已通过 Site 和 OTA 页面候选过滤，并以 `-50 dBm` 被 BLE 扫描发现，但其 Network Identity 能匹配当前 Mesh 的某一把 Network Key、不能匹配扫描时的 `currentNetworkKey`，因此被 SDK 拒绝并最终表现为 `rssi_unavailable`。

Gateway 可同时持有 Primary NetKey 和多个 Associated Space NetKey。`GatewaySpaceData.appKeyIndex` 在现有 Gateway 同步链路中用于解析对应的 Network Key 和 Application Key，因此绑定 5 个 Space 的 Gateway 可能轮播广播其中任意一个合法子网身份。

本设计采用已确认的方案 A：Site Gateway OTA 允许 Primary NetKey 与该 Gateway 的全部 Associated Space NetKey，但不放开当前 Mesh 的全部 NetKey。

## 范围

### 包含

- 仅调整从 Site → Firmware Update 进入的 Gateway BLE OTA 发现范围。
- 为每个 OTA 候选 Gateway 构造独立的允许 Network Key index 集合。
- 支持 Public/Private Network Identity 和 Node/Private Node Identity 的允许 Key 判断。
- 保持现有 Site 权限、关联 Space、MAC、Node 地址、PID、版本和 RSSI 规则。
- 保持全部新增诊断输出仅在 Debug 生效并继续脱敏。

### 不包含

- 不改变普通设备、Space 页面或其他 RSSI 扫描入口的默认 `currentNetworkKey` 行为。
- 不切换全局 `currentNetworkKey` 轮询各 Space。
- 不接受当前 Mesh 的任意 Network Key。
- 不修改 Gateway 的 NetKey/AppKey 配置，不自动修复关联关系。
- 不改变固件包、版本比较、RSSI 阈值或 OTA 传输协议。

## Key Scope 构造

Site 在生成实际 OTA Gateway 候选之后，为每个 Gateway 地址建立允许 Key 集合：

1. 始终加入 Primary Network Key index。
2. 遍历该 Gateway 的 `associatedSpaces`。
3. 优先通过 Associated Space 的 `appKeyIndex` 找到同 index 的 Application Key，再取得其绑定的 Network Key index。
4. 为兼容现有 Gateway 同步约定，如 Application Key 无法解析，则回退查找同 index 的 Network Key。
5. 只加入当前 Site Mesh 中真实存在的 Network Key。
6. 对无法解析的 Associated Space Key 输出 Debug 诊断，但不扩大允许范围。

最终数据按 Node 主单播地址隔离，例如一个 Gateway 只允许 Primary、Space A、Space B，另一个 Gateway 可以拥有不同集合。

## App 到 SDK 的数据流

### SiteViewController

- 保持 `firmwareUpdateGatewayModels` 作为候选真值。
- 从候选 Gateway 构造“Node 地址 → 允许 Network Key indexes”映射。
- 将映射传给 `BleFirmwareUpdateViewController`。

### BleFirmwareUpdateViewController

- 保存 Gateway OTA 专用 Key Scope。
- 调用 `refreshNodesRSSI` 时把映射传入 SDK。
- 其他初始化入口默认不传映射，行为保持不变。
- SDK 回调后继续执行当前页面 Node 地址匹配和升级资格判断。

### NordicSigMeshSDK

- `refreshNodesRSSI` 增加可选的按 Node 地址划分的允许 Key Scope；默认值为 `nil`。
- Scope 为 `nil` 时，完全保留当前只接受 `currentNetworkKey` 的行为。
- Scope 存在时，先解析广播 MAC 并匹配真实 Node，再取得该 Node 的允许 Key 集合。
- Network Identity 必须同时满足：属于当前 Mesh、匹配该 Node 的允许 Key。
- Node Identity 必须能解析到当前 Mesh Node，并匹配该 Node 的允许 Key。
- Node 不在 Scope、Key 不在该 Node 白名单或 Scope 无法解析时均拒绝。

## 过滤顺序

Gateway OTA Scope 存在时，SDK 使用以下顺序：

1. 广播必须来自 Mesh Proxy Service 扫描回调。
2. ProvisioningDevice/MAC 必须可解析。
3. MAC 必须匹配当前 Mesh 的真实 Node。
4. Node 地址必须存在于 Gateway OTA Key Scope。
5. 广播 Identity 必须属于当前 Mesh。
6. Identity 匹配到的 Key 必须位于该 Node 的允许集合。
7. SDK 才回传 Node、Peripheral 和 RSSI。
8. OTA 页面再次按候选 Node 地址校验。
9. 最后执行 PID、固件版本及 `RSSI >= -80 dBm` 判断。

这保证允许 Associated Space NetKey 只扩大目标 Gateway 的身份匹配范围，不扩大 Gateway 候选范围。

## Debug 日志

在现有 `[GatewayFirmwareScan]` 与 `session` 基础上增加：

- `gateway_key_scope_ready`：Gateway Key Scope 已建立，记录允许 index 数量。
- `associated_space_key_unresolved`：某个关联 Space 无法解析出本地 Network Key。
- `allowed_network_key_matched`：广播匹配到允许 Key。
- `gateway_network_key_not_allowed`：广播属于当前 Mesh，但匹配到的 Key 不在该 Gateway 白名单。
- `node_not_in_gateway_scope`：广播 Node 不是当前 Gateway OTA 候选。

允许记录 Key index、`primary`/`associated_space` 来源和脱敏后的 Network ID 后四位；禁止输出完整 NetKey、AppKey、Network ID、Space 名称或认证数据。

## 异常与兼容策略

- Key Scope 构造失败时，不回退为“当前 Mesh 全部 Key”；仅保留能确认的 Primary/Associated Keys。
- Primary Key 缺失时输出诊断，不生成随机或替代 Key。
- Associated Space 数据陈旧、Gateway 广播未关联 Key 时明确拒绝，用于提示配置同步问题。
- Key Refresh 的 current/old identity 匹配继续复用 SDK 现有能力。
- Connected Proxy RSSI 只对 Scope 中的 Gateway Node 回传；不因已连接而绕过候选范围。
- 多 Gateway 同页扫描时，每个 Node 使用自己的 Key Scope，不使用所有 Gateway Key 的无条件并集。

## 测试设计

### App 聚焦测试

- Primary Key 始终加入。
- 5 个 Associated Spaces 全部正确映射。
- Application Key bound Network Key 优先于同 index 回退。
- 缺失 Application Key、缺失 Network Key、重复 index 正确处理。
- 两个 Gateway 的 Key Scope 相互隔离。
- 非 Gateway OTA 入口不生成 Scope。

### SDK 聚焦测试

- Scope 为 `nil` 时只允许 `currentNetworkKey`，保持回归行为。
- Primary Identity 允许。
- 每个 Associated Space Identity 允许。
- 同 Mesh 但不在该 Gateway Scope 的 Key 拒绝。
- 其他 Gateway 的合法 Key 不得错误放行当前 Gateway。
- 外部 Mesh、MAC 无法解析、Node 不在 Scope、Node Identity 不匹配均拒绝。
- Connected Proxy 仅对 Scope 内 Node 生效。
- Debug 日志去重、脱敏及非 Debug 零输出继续通过。

### 工程验证

- App 与 SDK `git diff --check`。
- 现有 Firmware Version、RSSI Session、扫描诊断测试回归。
- SunSmart、Archipelago、SLG Sync Plus、SylSmart 四个 generic iPhoneOS Debug 构建。

## 真机验收

对同一个绑定 5 个 Space 的 4G Gateway，至少覆盖：

- 广播 Primary NetKey 时能够展示并获得 RSSI。
- 分别广播五个 Associated Space NetKey 时均能够展示并获得 RSSI。
- 广播同 Site 但未关联 Space NetKey 时被拒绝。
- 解除一个 Space 关联并同步后，该旧 NetKey 被拒绝。
- RSSI 低于 -80 dBm 时仍按原规则不可升级。
- 没有本地固件或版本不可升级时仍按原规则不可升级。

generic iPhoneOS 构建与静态测试不等同于上述硬件验收。
