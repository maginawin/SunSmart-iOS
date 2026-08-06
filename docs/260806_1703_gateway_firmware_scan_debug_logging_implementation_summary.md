# Gateway 固件升级扫描 Debug 日志实现总结

## 实现结论

已按确认的方案 A 完成：不改变 Site → Firmware Update → Gateway 的候选规则、BLE 扫描服务或升级资格判断，仅为现有链路增加 Debug 诊断日志。

所有日志统一使用 `[GatewayFirmwareScan]` 前缀和同一次页面扫描的 `session`，并按设备、阶段、原因去重。扫描结束会输出原因计数摘要。

## 诊断阶段与原因

### Site 候选阶段

- `gateway_model_node_unresolved`：数据库中的 GatewayModel 无法在 Site 主 Mesh 中解析为 Node。
- `permission_denied`：非 Site Owner 且无网关配置权限。
- `no_associated_space`：非 Site Owner 的网关没有关联 Space。
- `candidate_accepted`：通过 Site 候选过滤。

### OTA 页面候选与匹配阶段

- `missing_product_id`：Node 缺少 Product ID，无法形成固件类型数据。
- `page_candidate_accepted`：Node 可进入页面固件类型数据。
- `unexpected_node_address`：SDK 返回的广播设备地址不在当前页面候选节点中。
- `page_match_accepted`：广播设备地址属于当前页面候选节点。

### SDK 广播解析阶段

- `mesh_network_mismatch`：Network Identity 不属于当前 Mesh。
- `current_network_key_mismatch`：Network Identity 与当前 Network Key 不匹配。
- `missing_supported_identity`：广播中既无可用 Network Identity，也无可用 Node Identity。
- `node_identity_mismatch`：Node Identity 与当前 Network Key 不匹配。
- `provisioning_device_parse_failed`：无法从广播构造 ProvisioningDevice。
- `missing_mac`：广播解析成功但缺少可匹配的 MAC。
- `node_mac_not_found`：MAC 无法匹配当前 Mesh 的真实节点。
- `advertisement_matched`：广播已匹配当前 Mesh 节点。
- `connected_proxy_matched`：已连接 Proxy 的 RSSI 已匹配当前 Mesh 节点。

### 升级资格阶段

- `missing_local_firmware`：没有对应 PID 的本地固件。
- `missing_current_version`：节点缺少当前固件版本。
- `invalid_version`：当前版本或目标版本格式无效。
- `target_not_upgradeable`：版本策略判定目标固件不可升级。
- `rssi_unavailable`：扫描结束仍没有 RSSI。
- `rssi_below_threshold`：RSSI 小于 -80 dBm。
- `upgrade_eligible`：版本与 RSSI 均满足升级条件。

## Debug 与脱敏边界

- App 与 SDK Logger 的实际输出均由 `#if DEBUG` 包围。
- 非 Debug 编译下，行为测试确认 Logger 输出数组为空。
- 不输出完整 MAC、完整 Peripheral UUID、设备名称、Site 名称或认证信息。
- MAC 与 Peripheral UUID 仅保留十六进制后四位；Node 使用 Mesh 单播地址作为诊断键。
- 保持原扫描入口只扫描 `MeshProxyService.uuid`，没有扩大为全量 BLE 扫描。

## 方案 A 的可观测边界

只有被 CoreBluetooth 的 `MeshProxyService.uuid` 服务过滤命中并进入回调的广播，才能继续输出 SDK 拒绝原因。若 4G Gateway 没有广播 Mesh Proxy Service，当前方案不会收到该设备的广播回调，因此也不会出现该设备级拒绝日志；这是方案 A 保持扫描范围不变后的明确边界。

## 验证结果

- GatewayFirmwareScanDebugLogger：Debug 与非 Debug 双配置测试通过。
- GatewayFirmwareScanDiagnosticPolicy：通过。
- NodeRSSIScanDebugLogger：Debug 与非 Debug 双配置测试通过。
- NodeRSSIScanDiagnosticPolicy：通过。
- NodeRSSIRefreshSessionPolicy 回归测试：通过。
- App 与 SDK 仓库 `git diff --check`：通过。
- `SunSmart.xcodeproj/project.pbxproj`：结构校验通过；两个 App 新文件均加入四个品牌 target。
- generic iPhoneOS Debug 构建：SunSmart、Archipelago、SLG Sync Plus、SylSmart 全部成功。

## 未覆盖验收

当前验证为静态行为测试与 generic iPhoneOS 编译，不等于真机 BLE 广播验证。仍需使用目标 4G Gateway 在 Debug 包中进入该页面，按同一 `session` 收集日志，确认设备广播是否进入 Mesh Proxy Service 扫描回调，并根据最早出现的拒绝原因定位。
