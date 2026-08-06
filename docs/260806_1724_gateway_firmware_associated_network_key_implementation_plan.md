# Gateway 固件升级 Associated Network Key 实现计划

## 目标

仅在 Site → Firmware Update 的 Gateway BLE OTA 页面，将广播身份允许范围从单一 `currentNetworkKey` 扩展为“每个候选 Gateway 自己的 Primary NetKey + Associated Spaces NetKeys”，同时保持其他 RSSI 扫描入口行为不变，并保留现有权限、候选地址、MAC、PID、版本及 RSSI 过滤。

## 实现原则

- App 按 Gateway 主单播地址生成独立 Key Scope，不合并成全局允许集合。
- Associated Space 首选 Application Key 的 `boundNetworkKeyIndex`，仅在无法解析 Application Key 时回退同 index Network Key。
- SDK 的新 Scope 参数为可选；`nil` 必须继续走当前 Key 专用逻辑。
- Network Identity 与 Public/Private Node Identity 都必须精确验证到该 Gateway 的允许 Key。
- Connected Proxy 只能回传 Scope 中的 Gateway。
- 新增诊断继续只在 Debug 输出，不输出完整密钥、完整 Network ID 或 Space 信息。
- 不修改无关模块，不提交 Git commit。

## Task 1：App Key Scope 纯策略（TDD）

**文件：**

- 新增 `Tests/Firmware/GatewayFirmwareScanNetworkKeyScopePolicyTests.swift`
- 新增 `SunSmart/Main/Firmware/Model/GatewayFirmwareScanNetworkKeyScopePolicy.swift`
- 修改 `SunSmart.xcodeproj/project.pbxproj`

**步骤：**

1. 先写失败测试，覆盖 Primary Key、5 个 Associated Spaces、AppKey bound NetKey 优先、同 index 回退、缺失 Key、重复 Key、多个 Gateway 相互隔离。
2. 运行独立 Swift 测试，确认因策略尚不存在而失败。
3. 实现 Foundation-only 的输入、解析结果和纯策略。
4. 重新运行测试直至通过。
5. 将源文件加入 SunSmart、Archipelago、SLG Sync Plus、SylSmart 四个 target。

## Task 2：SDK Gateway Key Scope 纯策略与 Identity Key 精确匹配（TDD）

**文件：**

- 新增 `Tests/Standalone/NodeRSSIGatewayKeyScopePolicyTests.swift`
- 新增 `Sources/NordicSigMeshSDK/MeshLib/Manager/NodeRSSIGatewayKeyScopePolicy.swift`
- 新增 `Sources/NordicSigMeshSDK/MeshLib/Manager/NodeIdentity+NetworkKeyMatch.swift`

**步骤：**

1. 先写失败测试，覆盖无 Scope 兼容、Node 不在 Scope、允许 Key 命中、同 Mesh 非允许 Key 拒绝、不同 Gateway Scope 隔离。
2. 运行独立 Swift 测试并确认 RED。
3. 实现纯 Scope 判定策略。
4. 为 Public/Private Node Identity 增加按指定 Network Key 计算 Identity Hash 的精确匹配辅助，包含 Key Refresh old/current identity key。
5. 运行聚焦测试直至通过。

## Task 3：扩展 Debug 日志字段（TDD）

**文件：**

- 修改 `Tests/Firmware/GatewayFirmwareScanDebugLoggerTests.swift`
- 修改 `SunSmart/Main/Firmware/Model/GatewayFirmwareScanDebugLogger.swift`
- 修改 `Tests/Standalone/NodeRSSIScanDebugLoggerTests.swift`
- 修改 `Sources/NordicSigMeshSDK/MeshLib/Manager/NodeRSSIScanDebugLogger.swift`

**步骤：**

1. 先写失败断言，覆盖 `network_key_index`、`network_key_source`、`allowed_network_key_count`。
2. 扩展事件去重键，确保不同 Key index 的 unresolved 事件不会被合并。
3. 保持 Release/非 Debug 零输出测试。
4. 运行 App 与 SDK logger 测试直至通过。

## Task 4：SDK 扫描链路接入 Scope

**文件：**

- 修改 `Sources/NordicSigMeshSDK/MeshLib/Manager/MeshLibManager.swift`
- 必要时扩展 `Tests/Standalone/NodeRSSIScanDiagnosticPolicyTests.swift`
- 必要时修改 `Sources/NordicSigMeshSDK/MeshLib/Manager/NodeRSSIScanDiagnosticPolicy.swift`

**步骤：**

1. 给 `refreshNodesRSSI` 增加默认 `nil` 的 `allowedNetworkKeyIndexesByNodeAddress` 参数。
2. Scope 为 `nil` 时保持当前 NetworkKey 过滤顺序与 reason 不变。
3. Scope 存在时先由 MAC 解析真实 Node，再校验 Node 是否在 Scope。
4. Network Identity 精确找出匹配的本地 Network Key，并与该 Node 的允许集合求交集。
5. Node Identity 精确校验广播对应 Node，并逐把验证该 Node 的允许 Network Key。
6. 命中允许 Key 后输出 `allowed_network_key_matched`；同 Mesh但不允许时输出 `gateway_network_key_not_allowed`。
7. Connected Proxy 只允许 Scope 中 Node；非 Scope 输出 `node_not_in_gateway_scope`。
8. 不改变其他调用方，因为新参数默认 `nil`。

## Task 5：Site 与 OTA 页面传递 Scope

**文件：**

- 修改 `SunSmart/Main/Site/Controller/SiteViewController.swift`
- 修改 `SunSmart/Main/Firmware/Controller/BleFirmwareUpdateViewController.swift`

**步骤：**

1. 使用 `firmwareUpdateGatewayModels` 候选构造策略输入。
2. 从 Site 主 Mesh 提取 Primary Network Key、现有 Network Key indexes 和 AppKey → bound NetKey 映射。
3. 输出 `gateway_key_scope_ready` 和 `associated_space_key_unresolved` Debug 日志。
4. 将按 Node 地址划分的 Scope 传给 OTA 页面，再传给 SDK。
5. 其他 OTA 初始化入口继续使用 `nil`，维持原行为。

## Task 6：回归与工程验证

**验证项：**

1. 运行全部本次 App/SDK 独立聚焦测试，包括 Debug 与非 Debug logger。
2. 执行 App 与 SDK `git diff --check`。
3. 检查改动文件和四个 target 的 project 引用。
4. 直接运行 generic iPhoneOS Debug 构建：SunSmart、Archipelago、SLG Sync Plus、SylSmart。
5. 保存实现总结到 `docs/`，明确静态/构建验证不等于真机广播验收。

## 真机验收重点

- 同一个绑定 5 个 Space 的 4G Gateway：Primary 与五把 Associated Space NetKey 广播均能展示并获得 RSSI。
- 同 Site 但未关联到该 Gateway 的 NetKey 广播必须拒绝。
- 多 Gateway 同页时不能串用另一个 Gateway 的允许 Key。
- 解除 Space 关联并同步后，旧 NetKey 广播必须拒绝。
- `RSSI < -80 dBm`、版本不可升级或本地固件缺失时仍保持原有不可升级结果。
