# 删除与 Mesh Network Reset 命令使用分析

分析日期：2026-09-28。结论基于当前 App 和实际映射 SDK 的静态调用链；没有发送设备命令，没有修改业务代码，也未进行构建、真机或固件验证。

## 结论

- Lights 的单选、跨组多选、全选、整组选中最终都转成设备主单播地址列表，逐台执行 `ConfigNodeReset`（`0x8049`），以 `ConfigNodeResetStatus`（`0x804A`）作为协议成功依据。没有整组/整 Space 广播重置分支。
- 正常 ACK 路径会通过 SDK 删除本地 Node 及其属性，App 再执行关联配置清理。失败通常保留设备；用户确认 `Force Delete` 后直接删除本地记录，不再发送重置命令。迟到 ACK 是失败后仍可能发生本地删除的例外。
- Mesh Network Reset 对已知、未知网络使用相同的自定义 BLE 广播：重置命令类型码均为 `0x08`，整网目标为 `0xFFFF`，单设备目标为该设备单播地址。每次操作广播 5 秒，间隔 0.5 秒，约 10 个广播窗口，并非保证固定 10 个空口包。
- Force Reset 成功只移除当前页面扫描数据；已知网络也没有接入 Node 数据库删除、关联配置清理或云同步链路。整网成功由“10 秒内未扫描到该 Network ID”判断，单设备成功由“10 秒内扫描到相同 MAC 的未入网设备”判断。

## 核对范围

| 项目 | 当前状态 |
| --- | --- |
| App 工作树 | `fix-delete-devices-260928` |
| App 分支 / HEAD | `fix/delete-devices-260928` / `3fe9f11b` |
| 初始未提交改动 | 无 |
| 本地入口 | `SunSmartLocal.xcworkspace` |
| SDK 映射 | `.local-sdk/nordic-sig-mesh-sdk` → `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev` |
| SDK 分支 / HEAD | `one-dev` / `a05b869`，无未提交改动 |
| 正式 workspace 锁定 SDK | `a05b86979e605c830e3ba932a71b41c11866337f`，与本地 SDK HEAD 一致 |

当前正式 project / Package.resolved 实际登记的 SDK 地址为 GitHub，和 AGENTS.md 记载的 Gitee 地址不同。本次只记录实际情况，没有修改依赖；本分析使用已核对的本地映射及 revision。

## 一、Site → Space → Lights → 底部删除按钮

入口为 `DeviceLightsViewController.functionDidClickDelete` → `deleteNodes()` → `MeshAPI.resetNodes(addressDataList:)` → `MeshAddDeviceManager.resetNodes(addressDataList:)`。

| 选择场景 | 实际操作对象 | 命令及目标 | 请求组织 |
| --- | --- | --- | --- |
| 单个设备 | 选中的一个灯节点 | `ConfigNodeReset` → 主单播地址 | 一项请求 |
| 多个不同组设备，非全选 | 选中的各灯节点 | 每个节点分别发送 `ConfigNodeReset` | 按列表逐台等待结果 |
| 全选 Space 的设备 | 当前 Lights 页的 `visibleDevices` | 每个节点分别发送 `ConfigNodeReset` | 与普通多选相同，没有 `0xFFFF` 广播 |
| 选择整个组 | 该组与 `visibleDevices` 的交集 | 每个节点分别发送 `ConfigNodeReset` | 与普通多选相同，没有组地址命令 |

这里的“全选”需要按页面范围理解：`loadDevices()` 只取 `.light` 节点；名称筛选再生成 `visibleDevices`。因此无筛选时是当前 Lights 列表的全部灯，有筛选时仅是匹配的灯；不会因此删除 Sensors 等其他类别，也不会删除 Space 或 Group 对象。

确认删除前，为每个选中设备创建 `DevicePermanentDeletionContext`，检查当前 Space/网络身份、恢复上下文、待导入状态、检查点和删除日志。任一 context 未准备好就提示 `configuration_deletion_cleanup_pending` 并返回，不进入发命令阶段。

设备列表按当前页面设备顺序生成。如果选中当前代理节点，将其移到最后；在线设备结果等待时间为 10 秒，离线设备为 2 秒，代理节点强制使用 10 秒。批量循环另有“该设备 timeout + 1 秒”的信号量兜底。

### 1.1 发送次数的口径

业务层每台设备只提交一次 `ConfigNodeReset`，但不是保证空口只发送一次。SDK 的可靠消息层会在没有 ACK 时重发：初始重发延迟为 `acknowledgmentMessageInterval + TTL × 0.05 + segmentCount × 0.05` 秒，后续间隔翻倍；收到响应或可靠消息超时后结束。基础间隔默认 2 秒。发送队列还存在 `AccessError.busy` 的条件重试。因此现场包数要结合 TTL、ACK 到达时间、发送队列及底层传输判断，不能从“选了 N 台”直接断言只出现 N 个无线包。

### 1.2 成功、失败与本地数据

| 条件 | App 结果 | 本地行为 |
| --- | --- | --- |
| 结果监听收到目标地址的 `ConfigNodeResetStatus` | 地址加入成功列表 | SDK 的配置响应处理器执行 `meshNetwork.remove(node:)`，进一步调用 `node.delete()` 删除 Node 与属性；App 执行删除清理并移除页面条目 |
| 监听超时/错误，或批处理信号量超时 | 地址加入失败列表 | 通常保留节点，取消仍有效的 prepared 删除意图，弹出取消 / `Force Delete` |
| 部分成功、部分失败，选择取消 | 已成功部分保持删除，失败部分保留 | 不会回滚已成功的设备删除 |
| 失败后选择 `Force Delete`，且重新准备成功 | 强制删除失败列表对应的节点 | `forceRemove()` 直接调用 `network.remove(node:)` 并 commit；不再次发送 `ConfigNodeReset`，不要求设备已经退网 |
| 节点删除后关联数据清理未完成 | 最终可能提示 cleanup pending | 保留删除日志用于恢复；不能把 ACK 成功等同于所有配置均已清理完毕 |

`ConfigNodeResetStatus` 没有额外成功码参数，当前判断就是响应类型/来源匹配。界面整批成功条件为失败列表为空；最终 `done!` 还要经过 `DevicePermanentDeletionContext.showCompletion` 的待清理检查。没有等待所有设备重新广播未入网状态，也不以云端 HTTP 成功作为这一步删除成功依据。

App 清理涉及 Scene 地址、Schedule 设备地址及待删除地址、组的光感引用、动能开关代理引用、Proximity Lighting 拓扑等。成功删除或强制删除后调用 `commitLocalChangeForCloudSync(... .network(type: .address))` 标记变更并排入 Site/Space 同步；仍有受影响邻居配置时可进入同步页面。这表示安排后续同步，不代表云端和其他设备已经全部确认。

### 1.3 失败后仍可能本地删除的窗口

离线节点的 `waitFor` 监听是 2 秒，但 SDK `acknowledgmentMessageTimeout` setter 最小取 5 秒。结果监听超时并不取消对应的可靠消息上下文；在上下文仍存在时，迟到的 `ConfigNodeResetStatus` 仍可能匹配原请求并由配置处理器删除本地 Node，而批处理地址已记入失败列表。`DevicePermanentDeletionContext.cancel()` 也专门保留“Node 已消失”的删除证据。

这是由当前代码可以推导出的时序风险，未做现场复现。因此准确表述是“失败通常不主动删除；迟到 ACK 或用户强制删除仍可能造成删除”，不应承诺失败后数据库一定完全不变。

## 二、Force Reset the Device → Mesh Network → Start

路径为 `DeviceLightsViewController.functionEnterIntoTestDelete` → `DeviceForceResetDevicePageController` → `DeviceResetDeviceStepController.resetStepViewStartAction(.meshNetwork)` → `DeviceMeshNetworkResetController`。进入 Force Reset 页面时会关闭原 Mesh 连接。

Mesh Network Reset 的两个标签为 `Configured` 和 `Not Configured`。用户描述的“已知网络/未知网络”都位于 `Configured` 的扫描分组中，不等同于这两个标签。

已知/未知由扫描到的 Network ID 是否能通过 `SpaceData.load(subNetworkId:)` 找到本地 Space 决定显示名称：找到则显示 Space 名称，找不到则显示 `Unknown Mesh Network`。这项查询用于展示，不形成两套发送策略；两者都调用同一个 `DeviceMeshNetworkResetHandle`。

| 场景 | App 发送命令 | 广播计划 | 成功后的本地数据库删除 |
| --- | --- | --- | --- |
| 已知网络：整个网络 | `.meshNetworkReset(proxyAddress:macAddress:)`；类型码 `0x08`，目标 `Address.allNodes = 0xFFFF` | 5 秒，0.5 秒间隔，约 10 个广播窗口 | 无；只移除该 Network ID 的扫描条目和分组 |
| 已知网络：单个设备 | `.resetNode(address:macAddress:)`；类型码 `0x08`，目标为该设备地址 | 同上 | 无；只移除该 MAC 的扫描条目 |
| 未知网络：整个网络 | 与已知整网完全相同 | 同上 | 无 |
| 未知网络：单个设备 | 与已知单设备完全相同 | 同上 | 无 |

这是自定义 BLE 广播类型码 `0x08`，不是 SIG Mesh `ConfigNodeReset` 的 opcode。整网命令会先扫描指定 Network ID 的代理候选：RSSI ≥ -70 时直接选取，否则收集约 3 秒取较强者，总扫描超时为 10 秒。找不到代理就报告失败，本轮没有发出整网重置广播。

SDK 将类型码、校验字段、MAC 和目标地址等编码为 Service UUID 列表，调用 `CBPeripheralManager.startAdvertising`。整网广播使用选中代理的地址/MAC 构造数据，目标字段为 `0xFFFF`；单设备使用目标设备本身的地址/MAC。App 不为整网逐台循环发送，也不使用某个 Group 地址。完整载荷、字节序和 Service 说明见第三节。

App/SDK 能确认到“向代理发出的广播内容”为止；代理固件收到广播后，在 Mesh 网络内转发何种 opcode、重复几次、如何覆盖子网设备，不在本次 App/SDK 源码的证据范围内，需固件源码、协议或抓包确认。

### 2.1 为什么只能说约 10 次

`DeviceMeshNetworkResetHandle.startBroadcasting` 设置 0.5 秒间隔和独立的 5 秒结束定时器。SDK 的间隔定时器第一次在 0.5 秒后触发，每次 `startAdvertising` 后保持约 0.1 秒，再 `stopAdvertising`。正常计划中 0.5～4.5 秒有 9 个窗口，第 10 个窗口与 5 秒结束定时器存在调度竞争；系统蓝牙状态与调度也会影响实际执行。

所以当前实现是“按时间广播，名义约 10 个窗口”，不是计数器严格发送 10 次，更不能等同于设备收到 10 包。页面没有发送失败后的自动重置重试循环。

### 2.2 重置结果如何判断

| 操作 | 检查方式 | 判成功 | 判失败 |
| --- | --- | --- | --- |
| 整网重置，已知/未知相同 | 广播 5 秒后再等 5 秒，扫描 Mesh Proxy Service 10 秒 | 10 秒内未发现同 Network ID 的 Proxy 广播 | 扫描到任何同 Network ID 设备；或之前找不到代理/数据异常 |
| 单设备重置，已知/未知相同 | 广播 5 秒后立即扫描 Mesh Provisioning Service，最多 10 秒 | 发现 MAC 与目标相同的未入网设备 | 10 秒内未发现；或数据异常 |

整网判定是“未观察到原网络”，并没有逐台收到重置确认；离线、超出范围、没有广播或扫描未命中等情况无法通过这个条件排除。单设备判定有同 MAC 未入网广播作为正向证据；超时仍只能表示没有观察到成功条件。

`deviceReset` / `meshNetworkReset` 成功回调只修改 `scanDevices`、`networkSections` 和 `networkData.devices`，没有调用 `MeshAPI.removeNode`、`meshNetwork.remove(node:)`、`node.delete()`、`DevicePermanentDeletionContext` 或云同步。代码中“删除设备缓存”的注释在此处只指扫描数组。父页面旧的数据库删除回调也已被注释，当前子页面未接入它。因此已知设备即使物理退网，本地 Lights 配置仍可能保留并在后续表现为离线。

## 三、Mesh Network Reset 广播协议

本节描述当前 SDK 在 iOS 小端架构上构造的完整自定义重置载荷，以及传给 CoreBluetooth 的 Service UUID 数组。系统补充的广播链路层头、手机广播地址、Flags、实际 AD Type、广播/扫描响应分配等不由这段代码完整指定，不能冒充已抓到的完整空口包；第三节末尾单独列出这层边界。

### 3.1 协议输入与两种重置的差别

| 属性 | 整个网络重置 | 单个设备重置 |
| --- | --- | --- |
| SDK 枚举 | `BroadcasterType.meshNetworkReset(proxyAddress:macAddress:)` | `BroadcasterType.resetNode(address:macAddress:)` |
| 类型码 `code` | `0x08` | `0x08` |
| 校验使用的设备地址 `A` | 新扫描选出的 `proxyDevice.address` | 被点击设备的 `device.address` |
| MAC 字符串 `M` | `proxyDevice.macAddress` | `device.macAddress` |
| 载荷末尾目标地址 `D` | `Address.allNodes = 0xFFFF` | 同一个 `device.address` |
| Network ID | 选择代理、检查整网重置结果使用；不写入重置载荷 | 不写入重置载荷 |
| 已知/未知网络 | 同一协议 | 同一协议 |

单设备的地址来自扫描模型；当前控制器若在已加载网络中按 MAC 找到 Node，会用 `node.primaryUnicastAddress` 覆盖扫描地址。整网代理由 `DeviceMeshNetworkProxyScanner` 重新扫描选择，使用该次扫描模型的地址和 MAC。

扫描模型 `ProvisioningDevice` 通常从设备 Manufacturer Data 中读取 MAC 和地址：MAC 来自偏移 `4..<10` 的 6 字节反转，已入网地址来自偏移 12 的 2 字节。这里描述的是输入属性来源；**App 发出的重置命令自身并没有放在 Manufacturer Data 中**。

载荷中的 MAC 是目标设备/代理的产品 MAC，不是手机 BLE 广播包头中的 Advertiser Address。该命令没有携带 NetKey、AppKey、DeviceKey、Group 地址、PID、随机数或时间戳；固定输入不变时，重复广播的数据也不变。

### 3.2 完整逻辑载荷及字段偏移

正常 6 字节 MAC 下，`BroadcasterType.data` 先生成 **16 字节**数据；`makeUUIDs` 再添加 1 字节加和校验及 1 字节补零，最终得到 **18 字节**，编码成 **9 个 16-bit Service UUID**。

以下偏移从这 18 字节逻辑数据的第一个字节开始，全部数值示例使用十六进制；`H0` 是 CRC32 数值的最低字节，`M0` 是 MAC 字符串最左侧的一字节，`D0` 是目标地址最低字节。

```text
0A 78 | 0D | 08 | H0 H1 H2 H3 | M5 M4 M3 M2 M1 M0 | D0 D1 | S | 00
 CID    LEN  CMD      CRC32            MAC             DST    SUM  PAD
```

| 偏移 | 长度 | 字段 | 值、字节序及来源 |
| --- | --- | --- | --- |
| 0～1 | 2 | Company ID | SDK 常量 `CompanyId = 0x0A78`；使用 `.bigEndian` 后追加，字节为 `0A 78` |
| 2 | 1 | Payload Length | `0x0D`，即 13 字节，只计算偏移 3～15；不含 CID、长度本身、SUM、PAD |
| 3 | 1 | Command | `0x08`，整网和单设备相同 |
| 4～7 | 4 | CRC32 / hash | 对本节 3.3 的输入计算 CRC32 后按小端存储；`H0 H1 H2 H3` |
| 8～13 | 6 | MAC | `Data(hex: macAddress).reversed()`；例如 `112233445566` → `66 55 44 33 22 11` |
| 14～15 | 2 | Destination | 整网：`FF FF`；单设备：设备主单播地址的小端字节，例如 `0x1234` → `34 12` |
| 16 | 1 | SUM8 | 将偏移 0～15 的全部字节累加，取最低 8 位，即 `sum & 0xFF` |
| 17 | 1 | Padding | `00`；添加 SUM 后为 17 字节，补到两字节整组 |

整网重置的 **代理地址没有独立的明文字段**，只参与 CRC32 计算；偏移 14～15 放的是 `0xFFFF`。单设备的地址既参与 CRC32，又出现在 Destination 字段。固定 `0A 78` 是本自定义载荷的 CID 字节，不能套用 Manufacturer Specific Data 的头部规则来交换它。

### 3.3 CRC32 和加和校验的计算范围

定义：

- `A_LE`：上表校验设备地址 `A` 的两字节小端形式。
- `M_REV`：6 字节 MAC 反转后的结果。
- `SR`：固定字符串的 UTF-8 字节 `53 52`。

CRC32 输入共 10 字节：

```text
CRC input = A_LE（2 字节） || M_REV（6 字节） || 53 52（2 字节）
```

实际实现为随 SDK 附带的 CryptoSwift `Data.crc32(seed: nil, reflect: true)`：反射多项式 `0xEDB88320`（IEEE CRC32），初值 `0xFFFFFFFF`，最终异或 `0xFFFFFFFF`。`Data.crc32()` 先输出高字节在前的数据，广播代码再 `.reversed()`，因此最终 hash 字段是 CRC32 数值的小端表示。

这段代码的变量名为 `encryptionData`，实际运算是 CRC32 校验，不是 AES 等加密。`53 52` 只参与计算，不作为独立字段发送。CRC32 不覆盖 CID、Payload Length、Command 或单独的 Destination 字段；尤其整网场景使用的是代理地址 `A`，不是末尾的 `FF FF`。

SUM8 则覆盖已生成的完整 16 字节数据，包括 CID、长度、命令、CRC32、MAC 和 Destination，不含 SUM8 本身与 PAD。因此当代理/设备输入相同，仅切换整网与单设备重置时，CRC32 可以相同，但 Destination 和 SUM8 会变化。

### 3.4 如何编码为 Service UUIDs

`makeUUIDs(from:groupSize:reverseBytes:)` 的实际参数是 `groupSize = 2`、`reverseBytes = true`：

1. 对 16 字节 `BroadcasterType.data` 计算并追加 SUM8。
2. 追加 `00`，补成 18 字节。
3. 顺序分成 9 个两字节片段。
4. 每片段反转后构造 `CBUUID(data:)`，按原顺序加入数组。

逻辑字节与 API 层 UUID 表示的关系如下：

| 逻辑字节 | 传给 `CBUUID(data:)` 的字节 | UUID 字符串 |
| --- | --- | --- |
| `0A 78` | `78 0A` | `780A` |
| `0D 08` | `08 0D` | `080D` |
| `H0 H1` | `H1 H0` | `H1H0` |
| `H2 H3` | `H3 H2` | `H3H2` |
| `M5 M4` | `M4 M5` | `M4M5` |
| `M3 M2` | `M2 M3` | `M2M3` |
| `M1 M0` | `M0 M1` | `M0M1` |
| `D0 D1` | `D1 D0` | `D1D0`，整网为 `FFFF` |
| `S 00` | `00 S` | `00SS`，其中 `SS` 为校验和的两位十六进制值 |

当前 `startAdvertising` 字典只有两项实际赋值：

| CoreBluetooth 键 | 传入值 |
| --- | --- |
| `CBAdvertisementDataServiceUUIDsKey` | 上述 9 个 `CBUUID` 构成的数组 |
| `CBAdvertisementDataIsConnectable` | `false`；是否能控制空口连接属性见 3.7 |

`CBAdvertisementDataLocalNameKey`、`CBAdvertisementDataManufacturerDataKey`、`CBAdvertisementDataServiceDataKey` 在发送函数中均为注释，没有实际传入。代码也没有为这 9 个 UUID 调用 `addService` 建立 GATT 服务；这些 UUID 承载的是自定义命令数据。

### 3.5 可复算的完整示例

以下地址和 MAC 均为构造示例，不来自真实设备。两例均设 `A = 0x1234`、MAC 字符串为 `112233445566`；整网例中的 `A/MAC` 指代理，单设备例中指目标设备。

两例 CRC32 输入相同：

```text
输入：34 12 66 55 44 33 22 11 53 52
CRC32 数值：0x16A9557E
载荷中的 hash 字节：7E 55 A9 16
```

#### 3.5.1 重置整个网络

Destination 为 `0xFFFF`，SUM8 为 `0x8C`。

```text
BroadcasterType.data（16 字节）：
0A 78 0D 08 7E 55 A9 16 66 55 44 33 22 11 FF FF

追加 SUM8 和 PAD 后（18 字节）：
0A 78 0D 08 7E 55 A9 16 66 55 44 33 22 11 FF FF 8C 00

传给 CBAdvertisementDataServiceUUIDsKey 的 9 个 UUID，按数组顺序：
780A, 080D, 557E, 16A9, 5566, 3344, 1122, FFFF, 008C
```

#### 3.5.2 重置单个设备

Destination 为 `0x1234`，SUM8 为 `0xD4`。

```text
BroadcasterType.data（16 字节）：
0A 78 0D 08 7E 55 A9 16 66 55 44 33 22 11 34 12

追加 SUM8 和 PAD 后（18 字节）：
0A 78 0D 08 7E 55 A9 16 66 55 44 33 22 11 34 12 D4 00

传给 CBAdvertisementDataServiceUUIDsKey 的 9 个 UUID，按数组顺序：
780A, 080D, 557E, 16A9, 5566, 3344, 1122, 1234, 00D4
```

### 3.6 广播和扫描分别涉及哪些 Service

| 阶段 | Service / UUID | 实际用途 |
| --- | --- | --- |
| App 发出整网/单设备重置广播 | 自定义 9 项 16-bit UUID 列表；前两项固定为 `780A`、`080D`，其余编码 hash、MAC、Destination、SUM8 | 使用 Service UUIDs 广播字段传命令；没有单独的 Mesh GATT 重置服务 |
| Configured 页面发现已入网设备 | Mesh Proxy Service：`0x1828` | 扫描过滤、获取设备广播 |
| 整网重置前重新选择代理 | Mesh Proxy Service：`0x1828` | 找同 Network ID 的候选设备 |
| 整网重置后检查 | Mesh Proxy Service：`0x1828` | 检查原 Network ID 是否仍被广播 |
| 单设备重置后检查 | Mesh Provisioning Service：`0x1827` | 查找同 MAC 的未入网设备 |
| Not Configured 标签扫描 | Mesh Provisioning Service：`0x1827` | 展示未入网设备 |

`0x1828` 的完整 Bluetooth Base UUID 为 `00001828-0000-1000-8000-00805F9B34FB`；`0x1827` 同理为 `00001827-0000-1000-8000-00805F9B34FB`。本 SDK 定义的 Proxy Data In/Out 特征为 `0x2ADD/0x2ADE`，Provisioning Data In/Out 为 `0x2ADB/0x2ADC`；本页面的广播重置与结果检查不连接这些服务、不向这些特征写入重置命令。

因此，设备端接收 App 的这套重置广播时，不能只寻找 App 广播的 `0x1828` 或 `0x1827`：它们是 App 扫描设备时使用的 Service。App 发出的命令应按本节的自定义 Service UUID 列表解析。

### 3.7 AD 结构与完整空口包的边界

Bluetooth 广播中，`0x02` 表示不完整的 16-bit Service UUID 列表，`0x03` 表示完整列表。当前 App 只提交 UUID 数组，没有直接写入 AD Type；不能仅凭源码确定系统最终使用哪一种。[Bluetooth Assigned Numbers](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/Assigned_Numbers/out/en/index-en.html)

若系统按提交顺序将 9 个 UUID 完整放入一个 16-bit UUID 列表 AD 结构，UUID16 按小端表示后，AD Data 就还原成本节的 18 字节逻辑数据；AD Length 为 `1 + 18 = 19 = 0x13`。这是结合 SDK 编码和 Bluetooth 字节序规则推导的结构，不是抓包结果。[Bluetooth Core：Type Names 与字节序](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/Core-60/out/en/architecture,-change-history,-and-conventions/general-terminology-and-interpretation.html)

以使用 Complete List（`0x03`）为例，仅该 AD 结构的完整字节如下：

```text
整个网络：
13 03 0A 78 0D 08 7E 55 A9 16 66 55 44 33 22 11 FF FF 8C 00

单个设备：
13 03 0A 78 0D 08 7E 55 A9 16 66 55 44 33 22 11 34 12 D4 00
```

前面的 `13` 是 AD Length，`03` 是 AD Type；载荷里的 `0D` 是自定义 Payload Length，`08` 是自定义重置命令码。不要把这两层长度、类型混淆。若实际为 Incomplete List，则 AD Type 为 `02`；是否确实为此结构、顺序及分配方式需以前台运行抓包为准。

系统添加的其他 AD 字段、广播 PDU 类型、手机 Advertiser Address、链路层 CRC 和射频实际重复次数不在这 20 字节 AD 示例内。Apple 说明 `startAdvertising` 只支持 Local Name 和 Service UUIDs 两类输入，且广播按系统 best-effort 方式发送，后台 Service UUIDs 会进入 overflow 区域。因此，源码中的 `CBAdvertisementDataIsConnectable: false` 不能作为“必定发出不可连接 PDU”的证据；SDK 的 `peripheralManagerDidStartAdvertising(error:)` 当前也没有处理错误，实际 API 接受情况和空口发送仍需运行证据。[Apple：startAdvertising](https://developer.apple.com/documentation/corebluetooth/cbperipheralmanager/startadvertising%28_%3A%29?language=objc)

## 四、顺带确认的页面问题

`DeviceMeshNetworkResetConfiguredController.deviceReset` 在删除某个网络最后一个扫描设备后，使用该设备在 `networkData.devices` 中的 `index` 执行 `networkSections.remove(at: index)`。最后一个设备的索引为 0，但该网络分组不一定在第 0 项。

当列表有多个网络，重置非第一个网络的最后一台设备成功时，会错误移除第一个网络分组，并留下目标空分组。这是扫描列表维护问题，不是数据库删除；本次只记录，没有修改。

## 五、证据入口

以下文件均已定向读取；本地 SDK 链接依赖当前工作树已核对的 `.local-sdk` 映射。

| 结论 | 源码入口 |
| --- | --- |
| Lights 范围、选择、普通删除、强制删除 | [DeviceLightsViewController.swift](../SunSmart/Main/Device/Lights/Controller/DeviceLightsViewController.swift)，`loadDevices`、`applyDeviceNameFilter`、`updateEditUI`、`deleteNodes`、`didSelectAllAction` |
| 删除日志及关联配置清理 | [DevicePermanentDeletionCleanup.swift](../SunSmart/Common/Data/DevicePermanentDeletionCleanup.swift)，`prepare`、`cancel`、`forceRemove`、`commit`、`complete`、`showCompletion` |
| 删除后云同步 | [SpaceViewController.swift](../SunSmart/Main/Space/Controller/SpaceViewController.swift)，`SpaceData.commitLocalChangeForCloudSync` |
| 逐台发送与结果列表 | [MeshAddDeviceManager.swift](../.local-sdk/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Manager/MeshAddDeviceManager.swift)，`resetNodes(addressDataList:)` |
| ACK 监听及发送排队 | [MeshAPI.swift](../.local-sdk/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/MeshAPI.swift)，`sendMessage(message:address:timeout:result:)`；[MeshMessageManager.swift](../.local-sdk/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Manager/MeshMessageManager.swift) |
| ACK 后删除 | [ConfigurationClientHandler.swift](<../.local-sdk/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/nRFMeshProvision/Layers/Foundation Layer/ConfigurationClientHandler.swift>)，`case is ConfigNodeResetStatus`；[MeshNetwork.swift](<../.local-sdk/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/nRFMeshProvision/Mesh Model/MeshNetwork.swift>)，`remove(nodeWithUuid:)`；[MeshDatabase.swift](../.local-sdk/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/MeshDatabase.swift)，`Node.delete()` |
| 可靠消息重试、超时 | [AccessLayer.swift](<../.local-sdk/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/nRFMeshProvision/Layers/Access Layer/AccessLayer.swift>)，`AcknowledgmentContext`、`createReliableContext`；[NetworkParameters.swift](../.local-sdk/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/nRFMeshProvision/Layers/NetworkParameters.swift) |
| 已知/未知网络分组及成功后仅清扫描数据 | [DeviceMeshNetworkResetConfiguredController.swift](../SunSmart/Main/Device/Reset/Controller/DeviceMeshNetworkResetConfiguredController.swift)，`devicesRssiSort`、`setupDataSource`、`deviceReset`、`meshNetworkReset` |
| 广播时长与重置结果判定 | [DeviceMeshNetworkResetHandle.swift](../SunSmart/Main/Device/Reset/Model/DeviceMeshNetworkResetHandle.swift) |
| 整网代理选择 | [DeviceMeshNetworkProxyScanner.swift](../SunSmart/Main/Device/Reset/Model/DeviceMeshNetworkProxyScanner.swift) |
| 广播类型、载荷与广播窗口 | [BluetoothBroadcaster.swift](../.local-sdk/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Broadcaster/BluetoothBroadcaster.swift)；[BackgroundTimer.swift](../.local-sdk/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/nRFMeshProvision/Utils/BackgroundTimer.swift) |
| CID 与 Service 常量 | [MeshUtils.swift](../.local-sdk/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Utils/MeshUtils.swift)，`CompanyId`；[MeshConstants.swift](../.local-sdk/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/nRFMeshProvision/Utils/MeshConstants.swift)，`MeshProxyService`、`MeshProvisioningService` |
| UInt16 追加的字节序 | [Data.swift](<../.local-sdk/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/nRFMeshProvision/Type Extensions/Data.swift>)，`DataConvertible` |
| CRC32 算法与返回字节序 | [Checksum.swift](../.local-sdk/nordic-sig-mesh-sdk/Sources/CryptoSwift/Sources/CryptoSwift/Checksum.swift)；[Data+Extension.swift](../.local-sdk/nordic-sig-mesh-sdk/Sources/CryptoSwift/Sources/CryptoSwift/Foundation/Data+Extension.swift)；[Int+Extension.swift](../.local-sdk/nordic-sig-mesh-sdk/Sources/CryptoSwift/Sources/CryptoSwift/Int+Extension.swift)；[Generics.swift](../.local-sdk/nordic-sig-mesh-sdk/Sources/CryptoSwift/Sources/CryptoSwift/Generics.swift) |

## 六、验证范围

已核对当前 App/SDK revision、载荷拼接、CRC32 实现、数值字节序和 UUID 分组算法。第三节示例使用 SDK 原始 CRC32 查找表按相同循环离线复算，并与 Python 标准库 CRC32 交叉核对；两种载荷长度、SUM8、UUID 列表反解结果均已检查。另用 Swift 实际构造 `CBUUID(data:)`，确认 `0A 78 → 780A`、`0D 08 → 080D`、`34 12 → 1234`、`8C 00 → 008C`，并确认 CID 大端追加和地址小端追加的字节结果；未创建广播管理器。

未构建 App、未启动广播、未发送设备命令。实际 BLE 空口内容和包数、代理固件转发、设备退网和本地数据库运行结果没有进行现场验收。该文档仍是本任务唯一新增文件。
