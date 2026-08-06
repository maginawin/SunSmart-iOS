# Gateway Firmware Scan DEBUG 日志设计

## 目标

在 `Site -> Firmware Update` 的 Gateway BLE OTA 页面中，为候选构建、广播匹配和升级资格判断增加可定位的 DEBUG 日志。当 Gateway 被过滤、广播无法反查 Node，或设备不能升级时，日志必须给出明确原因。

本次只增加诊断能力，不改变 Gateway 候选规则、CoreBluetooth Service 过滤、Mesh 身份验证、MAC 匹配、RSSI 门槛或固件升级资格。

## 已确认范围

- 采用方案 A：保持现有扫描行为，在真实过滤点增加分层日志。
- 日志只在 `DEBUG` 构建输出。
- 不扫描全部 BLE 广播；仍只扫描 Mesh Proxy Service。
- 不新增或修改用户可见文案，不涉及国际化资源。
- 不输出 Network Key、Device Key、AppKey、完整 MAC、完整 Peripheral UUID 或其他 Auth 信息。
- 保留 App 与本地 `NordicSigMeshSDK` 工作区中的既有未提交改动。

## 日志约定

所有日志使用统一前缀 `[GatewayFirmwareScan]`，并携带同一次页面扫描的短 Session ID。首次 Session 在用户点击 Firmware Update 时生成，并从 Site 候选诊断传入页面和 SDK；后续下拉刷新由页面生成新的 Session。

字段采用稳定的英文名称和原因码：

- `session`：页面发起本轮扫描时生成的短 ID；
- `stage`：`site_candidate`、`page_candidate`、`sdk_advertisement`、`page_match`、`eligibility` 或 `summary`；
- `result`：`accepted`、`rejected`、`disabled` 或 `finished`；
- `reason`：稳定的英文原因码；
- `cid`、`pid`、`address`、`rssi`：能安全取得时输出；
- `mac_suffix`：仅输出规范化 MAC 的末四位；
- `peripheral_suffix`：仅输出 Peripheral UUID 的末四位。

同一扫描 Session 内，同一设备、同一 Stage、同一 Reason 只打印一次，避免 `CBCentralManagerScanOptionAllowDuplicatesKey` 导致日志刷屏。扫描结束时输出各原因数量汇总。

## 诊断链路

### 1. Site Gateway 候选阶段

在 `SiteViewController` 构建 Firmware Update Gateway 列表时记录：

- `gateway_model_node_unresolved`：GatewayModel 的 Address 无法在 Site 主 Mesh 网络解析到 Node；
- `permission_denied`：非 Owner 且没有 Gateway 配置权限；
- `no_associated_space`：非 Owner 的 Gateway 没有关联 Space；
- `candidate_accepted`：Gateway 已进入 Firmware Update 页面候选列表。

Owner 仍可进入全部已成功解析 Node 的 Gateway；日志不能改变现有权限语义。

菜单展示阶段仍使用现有候选属性且不打印诊断。用户实际点击 Firmware Update 后，代码使用同一套规则对当前 GatewayModel 做一次只读诊断并生成日志，再将原有候选结果和 Session ID 传入页面。诊断不能成为第二套业务过滤来源。

### 2. 页面候选构建阶段

在 `BleFirmwareUpdateViewController` 初始化和构建 `firmwareTypeDatas` 时记录：

- `missing_product_id`：传入 Node 没有 Product ID，无法生成页面类别；
- `page_candidate_accepted`：Node 已按 PID 加入页面类别。

首次 Session ID 由 Site 入口传入；下拉刷新生成新的 Session ID 并清空本轮去重状态。

### 3. SDK 广播过滤阶段

`refreshNodesRSSI` 增加一个默认关闭的 DEBUG 诊断上下文参数。只有 Gateway Firmware 页面传入上下文，其他调用方保持现状且不输出这些日志。

SDK 在现有过滤点记录：

- `mesh_network_mismatch`：Network Identity 不属于当前 Mesh Network；
- `current_network_key_mismatch`：Network Identity 不匹配当前 `currentNetworkKey`；
- `missing_supported_identity`：广播既没有可解析的 Network Identity，也没有 Node Identity；
- `node_identity_mismatch`：Node Identity 或 Private Node Identity 无法用当前 Network Key 验证；
- `provisioning_device_parse_failed`：广播无法构造 ProvisioningDevice；
- `missing_mac`：Manufacturer Data 或 Local Name 无法解析出 MAC；
- `node_mac_not_found`：解析出的 MAC 无法匹配当前 `realNodes`；
- `advertisement_matched`：广播成功反查到已入网 Node；
- `connected_proxy_matched`：已连接 Proxy 的 RSSI 成功映射到 Node。

为得到准确原因，现有复合 `guard` 会拆成语义等价的分支，但接受和拒绝条件保持不变。

CoreBluetooth 仍使用 Mesh Proxy Service 进行系统级扫描过滤，因此没有 Proxy Service 的设备不会进入 SDK 回调，也不会产生 `missing_proxy_service` 日志。本次设计明确不覆盖该情况。

### 4. 页面地址白名单阶段

SDK 回调后，页面记录：

- `unexpected_node_address`：SDK 找到的 Node 不在进入页面时传入的 Gateway Node 地址白名单；
- `page_match_accepted`：Node 地址属于当前页面候选。

附近其他 Mesh 节点不会被动态加入 Gateway Firmware 页面。

### 5. 升级资格阶段

对于页面中的 Gateway Node，记录不能勾选的最终原因：

- `missing_local_firmware`：本地没有对应 PID 的固件包；
- `missing_current_version`：Node 没有当前固件版本；
- `invalid_version`：当前版本或目标版本不符合 BLE Batch 版本格式；
- `target_not_upgradeable`：版本策略判定不需要或不允许升级；
- `rssi_unavailable`：本轮没有匹配到广播或已连接 Proxy RSSI；
- `rssi_below_threshold`：RSSI 小于 -80 dBm；
- `upgrade_eligible`：固件、版本、Peripheral 和 RSSI 均满足升级条件。

资格日志应复用 `FirmwareVersionUpdatePolicy.bleBatchAware` 的实际结果，不能另写一套可能漂移的版本比较规则。

## 组件边界

### App

- `SiteViewController`：负责 Site 候选与权限阶段日志；
- `BleFirmwareUpdateViewController`：持有页面扫描 Session、页面级去重、地址白名单与升级资格日志；
- App 日志辅助逻辑保持轻量，不承载业务过滤决定。

### NordicSigMeshSDK

- `MeshLibManager.refreshNodesRSSI`：在现有广播判断点发出原因；
- 新增独立、可测试的 DEBUG 诊断策略对象，负责字段脱敏、按设备和原因去重、原因计数与结束汇总；
- 默认诊断上下文为空，保证所有现有调用方行为不变。

## 测试策略

严格按 RED-GREEN 执行：

1. 先增加 SDK 独立测试，覆盖同一设备同一原因只记录一次、不同原因分别记录、MAC 与 Peripheral UUID 只保留末四位、结束汇总计数正确；
2. 先增加 App 聚焦 Contract Test，约束 Gateway Firmware 页面必须传入诊断上下文，并覆盖 Site、页面白名单、Product ID 和升级资格的原因码；
3. 观察测试因诊断能力尚不存在而按预期失败；
4. 最小实现后重新运行测试并确认通过；
5. 运行现有 Node RSSI Session 测试，确保不破坏用户尚未提交的 Proxy RSSI 刷新工作；
6. 运行 `git diff --check`；
7. 按项目规则直接运行 SunSmart generic iPhoneOS `xcodebuild`，不使用 Simulator 或 shell 重定向。

SDK 被多个品牌 Target 引用。若 SDK 公共方法签名发生变化，依靠默认参数保持源码兼容，并至少检查 SunSmart、Archipelago、SLG Sync Plus 与 SylSmart 的 Target 引用；实际构建范围在实施计划中结合改动风险明确。

## 验收标准

- 打开 Site Firmware Update 页面后，每轮扫描都有唯一 Session 日志；
- 符合现有扫描条件的广播打印成功匹配；
- 进入 SDK 回调但被过滤的广播打印唯一且明确的失败原因；
- 页面候选、地址白名单和升级资格被过滤时打印明确原因；
- 重复广播不会对同一原因刷屏；
- 日志不包含完整 MAC、完整 Peripheral UUID 或任何 Mesh/Auth Key；
- Release 构建不输出 `[GatewayFirmwareScan]` 日志；
- 业务过滤规则和用户界面保持不变；
- 静态测试和 iPhoneOS 构建不等同于真实 4G Gateway 验收，最终仍需用设备广播验证实际原因码。

## 非目标

- 不增加页面内日志 UI；
- 不保存日志到文件或上传服务器；
- 不改变 RSSI 门槛；
- 不改变 4G Gateway PID 配置；
- 不在 DEBUG 下扫描全部 BLE 广播；
- 不修复本轮日志揭示出的设备广播或数据问题。
