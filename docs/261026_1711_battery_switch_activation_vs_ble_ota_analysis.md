# Battery Power Switch 激活与 BLE 升级可用状态差异

分析日期：2026-10-26。范围：只分析 App 与当前本地 SDK，不修改业务代码。

## 结论

用户所指主要为 Battery Power Switch 操作弹窗的“已检测到设备激活”与详情顶部的“Normal”。它们与 Firmware update via BLE 的在线图标、可升级状态使用不同判据，没有共享的“已激活”状态。

- 操作弹窗：目标设备回复指定 Mesh GET，即判定本次检测成功。
- 详情顶部 Normal：已绑定真实设备，保存的电池数据未超过 7 天且电量大于 10%；不检测实时激活。
- BLE 升级在线图标：`node.rssi != nil`；可选升级还要求 RSSI ≥ -80、存在本地固件及符合版本策略。

因此，同一设备保持相同物理状态，仍可能出现用户描述的不同显示。已证实的是判据与更新时机不同；本次没有现场广播、扫描日志，尚不能确认该设备在 BLE 页具体卡在未发现、身份匹配、信号还是版本条件。

## 1. 实际入口与对象

`SpaceMoreViewController` 的 `.ble` 入口打开 `BleFirmwareUpdateViewController(site:space:)`，使用当前 `realNodes`。Power Switch 只有能通过 `proxyNodeAddress` 对应到当前开关记录才进入列表；没有真实节点的虚拟开关不进入 BLE 升级列表。

Battery Power Switch 详情由 `DeviceSwitchesViewController` 打开 `PJEightKeySwitchMonitorVC`，通过 `switchData.proxyNode` 取得实际设备。

入口是 Space More，未传入 Site 网关专用的 `allowedNetworkKeyIndexesByNodeAddress`。因此本次检查的是当前 Space 网络身份分支，不能套用 Site 网关的关联网络筛选结论。

## 2. 操作弹窗如何判断激活

保存自身配置、Re-Sync、Identify、TX Enable 共用 `MeshBatteryPowerSwitchActivationDetector`，调用本地 SDK 的 `MeshAPI.sendBatteryPowerSwitchActivationProbe`：

1. 取得目标设备的 `sunricherVendorModel`。
2. 立即发送 `SunricherVendorGet(function: .batteryPowerSwitchTxEnabled)`，当前 SDK 对应功能参数 `0x4C 0x03`。
3. 等待该 Model 所在 Element 地址返回的 `SunricherVendorStatus`，每次超时为 1.5 秒。
4. 响应 `status.isSuccessful` 且 `status.code == .batteryPowerSwitchTxEnabled` 才成功；不要求返回的 enabled 为 true。
5. 等待期间通常每 3 秒探测一次，最长等待 60 秒；成功后结束本次等待，进入对应后续动作。

这个成功条件没有检查目标设备的 RSSI、BLE peripheral 或目标设备是否与手机直接连接。命令使用现有 Mesh 发送链路，因此可经其他 Proxy/网络转发；响应成功不能推出目标设备的 BLE 广播一定能被手机发现。

detected 是操作 flow 的局部状态，没有存为两页共用的实时激活标志。取消、重试与新操作采用代次保护；BLE 页也不会读取先前弹窗成功结果。

详情电池刷新另用 `GenericBatteryGet`，收到合法 `GenericBatteryStatus` 后保存电量与时间；它不使用上述 TX Enable 探测成功条件。

## 3. 详情顶部 Normal 的含义

`PJEightKeySwitchMonitorViewModel.batteryStatusStyle` 按以下条件生成状态：

| 条件 | 显示 |
| --- | --- |
| 未绑定真实 Power Switch 节点 | Unlinked |
| 没有电量更新时间、超过 7 天、没有合法电量 | Unknown |
| 电池数据有效且电量 ≤ 10% | Low Battery |
| 电池数据有效且电量 > 10% | Normal |

该计算不检查 `node.state`、`node.rssi`、Mesh 连接或激活探测。即使设备已经休眠，保存的电量仍可能满足 Normal 条件。

列表正常图标也不是激活证据：Battery Power Switch 列表按绑定、启用、同步/绑定修复状态显示；仅 AC 类型额外按 `node.state` 切换离线资源。

## 4. BLE 升级页如何判断在线与可用

进入页面或下拉刷新时，`refreshRSSI()` 清空候选节点的 `rssi` 和 `peripheral`，重新计算升级状态并启动 `refreshNodesRSSI`。

当前本地 SDK 有两种 RSSI 来源：

- 广播：扫描 SDK 定义的 Mesh Proxy Service `0x1828`；解析厂商数据或兼容名称得到 MAC，匹配真实节点，再验证 Network Identity 或 Node Identity/Private Node Identity 与当前网络密钥的关系。通过后写入该节点 RSSI，并向页面返回 peripheral。
- 已连接 Proxy：对已打开的 Proxy 调用 `readRSSI()`，按 Proxy 节点地址或 MAC 定位节点，得到读数后同样回传。只有目标开关自身是该 Proxy，才能为目标开关补上 RSSI；连接其他灯具不等于取得开关 RSSI。

页面收到结果后按节点主地址匹配候选设备，并保存其 peripheral。它不发送 Battery Power Switch 激活探测，也不使用详情页的 Normal 或弹窗 detected。

| BLE 页表现 | 直接代码条件 |
| --- | --- |
| 正常图标、设备名正常色、显示 dB | `node.rssi != nil` |
| Battery Power Switch 离线图标、灰色名字、RSSI 为 `--` | `node.rssi == nil` |
| 信号显示红色，不能选择升级 | RSSI < -80 |
| 待升级状态下可选择/显示升级按钮 | RSSI ≥ -80，且本地固件版本符合 `bleBatchAware` 策略 |

版本策略通常要求目标三段版本更高，但同三段版本有批次号规则，不能简单归纳为字符串或普通数值“大于”。只有云端版本信息、尚未下载本地固件，也不足以满足升级条件。

在线图标不是连接成功证明：实际开始升级时，SDK 才对目标 peripheral 建立 GATT 链路并执行固件流程。

### 扫描时间窗口

- 页面首次安排 10 秒后停止扫描。
- 每发现一台此前尚未取得 peripheral 的候选设备，再把停止时间延后 10 秒。
- 候选设备都取得 RSSI/peripheral 时可提前结束。
- 停止后没有持续的激活探测。若用户此后才唤醒设备，要重新下拉刷新；扫描结束后唤醒不会自动更新旧结果。
- RSSI 没有在此页按设备的 60 秒唤醒窗口自动失效；取得过 RSSI 也不表示设备随后仍保持激活。

UI 提示的“60 秒激活窗口”是当前产品文案，不能视为本次已实测的固件行为；它也不是页面扫描的持续时间。

## 5. 如何定位本次现场差异

最短人工核对：在 BLE 页先唤醒目标开关，立即下拉刷新，观察该行的 RSSI 与升级入口。

1. RSSI 为 `--`：目标没有产生被此次扫描接受的 RSSI。可能是扫描时机、没有可被当前扫描收到的 Proxy 广播、广播 MAC/身份不匹配，或目标已连接但未取得有效 RSSI。这里只能列为候选原因。
2. RSSI 是小于 -80 的数值：已经发现设备，限制来自信号阈值。
3. RSSI ≥ -80 仍不可升级：检查本地固件包、当前版本及目标版本策略。

项目已有 DEBUG 日志，无需先添加诊断代码：

| 日志 | 用途 |
| --- | --- |
| `[GatewayFirmwareScan] stage=sdk_advertisement` | 查 `missing_mac`、`node_mac_not_found`、`missing_supported_identity`、`current_network_key_mismatch`、`node_identity_mismatch` 或成功匹配 |
| `[GatewayFirmwareScan] stage=page_match` | 确认 SDK 结果是否命中本页目标地址 |
| `[GatewayFirmwareScan] stage=upgrade_eligibility` | 查 `missing_local_firmware`、`missing_current_version`、`invalid_version`、`target_not_upgradeable`、`rssi_unavailable`、`rssi_below_threshold` |
| `[NodeRSSIRefresh]` | 查扫描包数、候选数、结束原因和实际耗时 |

尽管日志前缀含 Gateway，当前 Space BLE 升级入口也会使用它。日志没有某台目标记录并不能单独证明固件没广播，因为服务过滤会在回调之前排除不匹配的广播；升级资格日志也可能优先报告固件问题而未报告缺少 RSSI，需结合行显示和扫描记录判断。

## 6. 建议与边界

- 不宜把 BLE 升级条件直接替换成详情 Normal 或 Mesh 探测成功；实际升级仍需要目标设备的 BLE 链路。
- 若确认是停止扫描后才唤醒，可讨论调整 Battery Power Switch 的扫描等待/刷新交互，保留身份认证与升级限制。
- 若广播被拒绝，应按该设备 PID、版本与脱敏广播样本核对具体兼容分支，不整体放宽网络身份检查。
- 若需要统一文案，应分别表达电池状态、Mesh 激活检测和 BLE 升级可用性，避免正常/离线图标让用户误以为在显示同一状态。
- 本次不提出固件或服务器修改；若日志证实需外部配合，再记录接口与广播契约，由对应团队实施。

## 7. 证据与验证边界

App：`feat/HDB-261020`，HEAD `6c6dbd5d`。本地 workspace 的 `.local-sdk/nordic-sig-mesh-sdk` 指向 `one-dev`，SDK HEAD `e7c1a7f`；检查时 App 与 SDK 均无未提交业务改动。这是当前源码结论，尚未核对用户运行包的实际 revision。

主要源码：

- [BLE 页面与扫描生命周期](../SunSmart/Main/Firmware/Controller/BleFirmwareUpdateViewController.swift)：`refreshRSSI`、`setupData`、`startUpgraded`。
- [BLE 图标和升级入口](../SunSmart/Main/Firmware/View/BleFirmwareTypeUpdateViewCell.swift)：`BleFirmwareUpdateDeviceCell.device`。
- [Battery Power Switch 激活流程](../SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchActivationAlertController.swift)：`MeshBatteryPowerSwitchActivationDetector`、各 flow。
- [详情电池状态](../SunSmart/Main/Device/Device1.5/NEightKeySwitches/ViewModel/PJEightKeySwitchMonitorViewModel.swift)：`batteryStatusStyle`。
- [本地 SDK 扫描](../.local-sdk/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Manager/MeshLibManager.swift)：`refreshNodesRSSI`、`emitNodeRSSIRefreshSample`。
- [本地 SDK 激活探测](../.local-sdk/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/MeshAPI.swift)：`sendBatteryPowerSwitchActivationProbe`。

完成源码链路核对；未构建、未运行真机、未获取现场 BLE 广播/日志。未修改 App/SDK 生产代码，未将任一候选现场原因认定为已复现缺陷。
