# Gateway 固件升级 Associated Network Key 实现总结

## 结论

已按确认的方案 A 完成 Site → Firmware Update 的 Gateway BLE OTA 扫描范围调整。

现在每个候选 Gateway 使用独立的允许 Key Scope：

- Primary Network Key。
- 该 Gateway 自身全部 Associated Spaces 对应的 Network Keys。
- 不允许当前 Mesh 的其他无关 Network Keys。
- 多个 Gateway 同页时不会无条件合并彼此的 Associated Keys。

其他 RSSI 扫描入口不传 Scope，继续保持只接受 `currentNetworkKey` 的原行为。

## App 改动

### Key Scope 解析

新增 `GatewayFirmwareScanNetworkKeyScopePolicy`：

- 按 Gateway 主单播地址生成独立允许集合。
- 始终尝试加入 Primary Network Key。
- Associated Space 优先使用同 index Application Key 的 `boundNetworkKeyIndex`。
- Application Key 不存在时才回退同 index Network Key。
- 本地不存在的 Key 记录为 unresolved，不扩大允许范围。
- 对重复 Key 自动去重。

### Site → OTA 页面数据流

`SiteViewController` 使用实际 `firmwareUpdateGatewayModels` 候选构造 Scope，并传给 `BleFirmwareUpdateViewController`。OTA 页面再将 Scope 传给 SDK 的 `refreshNodesRSSI`。

Space 页面和其他构造入口不传 Scope，默认值保持 `nil`。

### Debug 诊断

新增或扩展以下 reason：

- `gateway_key_scope_ready`
- `associated_space_key_unresolved`
- `primary_network_key_unavailable`
- `mesh_network_unavailable`

日志可包含允许 Key 数量、Key index 和 `primary` / `associated_space` 来源；仍只输出 MAC、Peripheral 标识后四位，不输出完整密钥、完整 Network ID 或 Space 信息。

## SDK 改动

### 可选 Gateway Scope

`refreshNodesRSSI` 新增可选的“Node 地址 → 允许 Network Key indexes”参数：

- 参数为 `nil`：保留原有 current-key-only 过滤和 reason。
- 参数存在：先用广播 MAC 找到真实 Node，再按该 Node 自己的 Scope 校验 Identity。
- Node 不在候选 Scope 时拒绝。
- Connected Proxy 也必须属于 Scope 才能回传 RSSI。

### Identity 校验

- Network Identity：查找当前 Mesh 中能匹配广播的 Network Key，再与目标 Gateway 的允许集合求交集。
- Public/Private Node Identity：使用目标 MAC 对应 Node 地址和每一把指定 Network Key 精确计算 Identity Hash。
- Key Refresh 期间同时支持 Network Key 的 current/old identity key。
- 同 Mesh 但不在目标 Gateway Scope 的 Key 输出 `gateway_network_key_not_allowed`。
- 允许 Key 命中输出 `allowed_network_key_matched`。

## 测试与验证

### 聚焦测试

最终运行通过：

- Firmware Version 策略。
- Gateway 候选、页面匹配和升级资格诊断。
- Gateway Key Scope：Primary、绑定优先、回退、缺失、重复、5 Space、多 Gateway 隔离。
- App Debug Logger 与非 Debug 零输出。
- SDK RSSI Session 策略。
- SDK 既有 Identity 诊断策略。
- SDK Gateway Key Scope：Scope 缺失兼容、允许命中、非允许拒绝、Gateway 隔离。
- SDK Debug Logger 与非 Debug 零输出。

Node Identity 加密匹配 XCTest 已补充 Public、Private 和 Key Refresh old key 用例。SDK 的 SwiftPM host 测试受工程既有 `UIKit` 依赖限制，在 macOS host 上无法执行；新加密辅助已通过下面的 iPhoneOS SDK 编译。

### 静态检查

- App `git diff --check` 通过。
- NordicSigMeshSDK `git diff --check` 通过。

### generic iPhoneOS Debug 构建

- SunSmart：通过。
- Archipelago：通过。
- SLG Sync Plus：通过。
- SylSmart：通过。

构建使用本地 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk` Swift Package。

## 真机验收边界

静态测试和 generic iPhoneOS 构建不能证明真实 Gateway 广播行为。仍需使用目标 4G Gateway 验收：

1. Primary NetKey 广播可展示并获得 RSSI。
2. 5 个 Associated Space NetKey 分别广播时均可展示并获得 RSSI。
3. 同 Site 但未关联到该 Gateway 的 NetKey 必须输出 `gateway_network_key_not_allowed` 并拒绝。
4. 解除一个 Space 关联并同步后，旧 NetKey 必须被拒绝。
5. 多 Gateway 同页时不能使用另一个 Gateway 的 Associated Key 放行。
6. RSSI、版本、本地固件等原有升级资格过滤保持不变。

目标 Gateway 正常命中 Associated Key 后，预期关键日志为 `gateway_key_scope_ready`、`allowed_network_key_matched`、`page_match_accepted`，并且不再以 `current_network_key_mismatch` 结束。
