# Kinetic Switch Proxy 配置命令与 TTL 分析

## 结论

1. App 在 `Switches -> Kinetic Switch` 保存后，不是只发送一条“配置 Kinetic Switch”命令，而是按差异生成两部分配置：
   - 对 Switch Proxy Node 配置 EnOcean MAC、安全密钥、Client Model Publication 和按键动作；
   - 对被控灯具的对应 Server Model 配置 Subscription。
2. 新增 Kinetic Switch 时，Proxy 侧核心命令顺序为：
   - `SunricherVendorSet`，Mesh Vendor opcode `0xF0780A`，参数前缀 `36 01`：添加 EnOcean 设备；
   - `ConfigModelPublicationVirtualAddressSet`，opcode `0x801A`：把 Proxy 的 Light LC / Generic OnOff / Generic Level / Scene Client Model Publication 指向 Kinetic Switch 的虚拟组；
   - `SunricherVendorSet`，Mesh Vendor opcode `0xF0780A`，参数前缀 `36 03`：写入每个按键的动作映射。
3. 被控灯具侧使用 `ConfigModelSubscriptionVirtualAddressAdd`，opcode `0x8020`，将对应的 Light LC、Generic OnOff、Generic Level 或 CTL Temperature 对应 Level Server Model 订阅到虚拟组。
4. 当前 Kinetic Switch 配置链路**没有发送设置 Switch Proxy Node Default TTL 的命令**。SDK 虽然定义了标准 `ConfigDefaultTtlSet`，opcode 为 `0x800D`，但 App 与 SDK 业务代码中没有实例化或发送它。
5. Proxy 的 Model Publication 配置中确实包含一个 TTL 字段。当前写入的是 `MeshNetworkManager.instance.networkParameters.defaultTtl`，SDK 初始化值为 `5`。这表示 Proxy 后续由这些 Client Model 发布控制消息时使用的 Publication TTL；它不等同于 Node Default TTL。

## App 入口与同步链路

`DeviceSwitchViewController` 保存 Kinetic Switch 后，通过 `getNeedSyncDatas()` 判断是否存在 Proxy 或 Group 同步任务；需要同步时进入 `SyncDevicesViewController(.enOceanSwitch)`：

- `SunSmart/Main/Device/Switches/Controller/DeviceSwitchViewController.swift:220-246`
- `SunSmart/Common/Data/MeshNetwork+SunSmart.swift:1733-1833`
- `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift:408-465`

Proxy 配置任务最终调用：

- `node.getEnOceanSwitchBindMessageHandles(...)`
- `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift:602-605`

被控设备配置任务最终调用：

- `node.getEnOceanSubscriptionMessageHandles(...)`
- `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift:593-600`

配置是按本地已缓存状态计算差异的，因此已存在且一致的 Add、Publication、Key Set 或 Subscription 不会重复生成。

## Proxy Node 实际命令

### 1. 添加 EnOcean 设备

消息类型：`SunricherVendorSet`

- Vendor opcode：`0xF0780A`
- 参数前缀：`36 01`
  - `0x36`：EnOcean 功能类；
  - `0x01`：Add。
- 后续参数：`keyCount + 16-byte securityKey + reversed 6-byte MAC`。

来源：

- `NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorSet.swift:10-14,109-110`
- `NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift:637-651,914-928`
- `NordicSigMeshSDK/MeshLib/Manager/MeshEnOceanProxyServer.swift:266-287`

二维码中的 Security Key 属于设备认证信息，日志或文档对外提供时必须脱敏。

### 2. 配置 Proxy Client Model Publication

Kinetic Switch 创建的是虚拟组，因此正常新增链路使用：

- `ConfigModelPublicationVirtualAddressSet`
- opcode：`0x801A`
- 目标 Model 根据按键动作选择：
  - Auto：Light LC Client；
  - Off：Generic OnOff Client；
  - Scene：Scene Client；
  - Dim / CCT：Generic Level Client。

来源：

- `SunSmart/Main/Group/Switch/Controller/GroupSwitchsViewController.swift:225-243`
- `NordicSigMeshSDK/MeshLib/Manager/MeshEnOceanProxyServer.swift:353-410`
- `NordicSigMeshSDK/nRFMeshProvision/Mesh Messages/Foundation/Configuration/ConfigModelPublicationVirtualAddressSet.swift:34-44`

### 3. 写入按键动作

每个发生变化且成功生成 Publication 配置的按键，随后发送：

- `SunricherVendorSet`
- Vendor opcode：`0xF0780A`
- 参数前缀：`36 03`
  - `0x36`：EnOcean；
  - `0x03`：Switch Key Set。
- 后续参数：反转 MAC、按键索引、方向、Scene Number 和 Action Type。

来源：

- `NordicSigMeshSDK/MeshLib/Manager/MeshEnOceanProxyServer.swift:423-430`
- `NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorSet.swift:113-141`

### 4. 替换或删除时的补充命令

替换或解除绑定时还可能发送：

- `36 05`：Switch Key Unbind；
- 禁用对应 Client Model Publication；
- `36 02`：删除 EnOcean 设备。

这些不是正常首次新增时固定存在的命令，而是由 Proxy 已缓存状态与本次配置差异决定。

## 被控灯具命令

被控灯具需要订阅 Proxy 发布使用的虚拟组。正常 Kinetic Switch 虚拟组对应：

- `ConfigModelSubscriptionVirtualAddressAdd`
- opcode：`0x8020`

按动作选择的 Server Model：

- Auto：Light LC Server；
- Off：Generic OnOff Server；
- Dim：Generic Level Server；
- CCT：存在 Temperature Model 的元素对应的 Generic Level Server。

来源：

- `NordicSigMeshSDK/MeshLib/Manager/MeshEnOceanProxyServer.swift:523-565`
- `NordicSigMeshSDK/nRFMeshProvision/Mesh Messages/Foundation/Configuration/ConfigModelSubscriptionVirtualAddressAdd.swift:34-49`

## TTL 语义

需要区分三种 TTL：

### 1. Proxy Node Default TTL

Bluetooth Mesh 标准设置命令是：

- `ConfigDefaultTtlSet`
- opcode：`0x800D`
- payload：1-byte TTL。

当前代码只有消息类型定义和 Configuration Server 解析支持；全量搜索没有发现 App 或 SDK 业务链路创建 `ConfigDefaultTtlSet(...)`。因此，保存 Kinetic Switch 不会修改 Proxy Node Default TTL。

### 2. Proxy Model Publication TTL

Kinetic Switch 配置会在 `ConfigModelPublicationVirtualAddressSet` payload 中写入 Publication TTL。当前值来自：

- `MeshNetworkManager.instance.networkParameters.defaultTtl`
- SDK `MeshLibManager.initConfig()` 将其初始化为 `5`。

因此，在没有其他运行期改写的当前实现中，Kinetic Switch Proxy Client Model 的 Publication TTL 被配置为 `5`。

这只影响 Proxy 固件后续由对应 Client Model 发布的控制消息，不会修改该节点所有消息所使用的 Default TTL。

### 3. App 发送配置包时的 Network PDU TTL

Lab 中的 Outgoing Mesh TTL Override 会覆盖 App 自己发送 Access Message 时的 Network PDU 初始 TTL。它可能影响 App 发往 Proxy 的 `0x801A`、`0xF0780A` 等配置包如何穿越 Mesh，但不会把 `0x801A` payload 内的 Publication TTL 从 `5` 改为 Lab 值，也不会配置 Proxy Node Default TTL。

## 最终判断

- 如果问题是“App 有没有配置 Proxy 后续发出 Kinetic 控制消息的 TTL”：**有**，通过 Model Publication Set 的 TTL 字段，当前静态配置值为 `5`。
- 如果问题是“App 有没有配置 Switch Proxy Node 的 Default TTL”：**没有**，当前链路没有发送 `ConfigDefaultTtlSet (0x800D)`。
- 如果需求是让 Proxy 的所有默认发送消息或回复都使用指定 TTL，需要新增独立的 `ConfigDefaultTtlSet` 配置及状态确认；只修改 Publication TTL 不等价。

## 验证边界

本结论基于当前 `fix` worktree 与其实际本地 Swift Package 引用 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk` 的静态源码追踪。未修改业务代码、未执行构建，也未抓取真实 Mesh 空口/SDK 发送日志。若要确认某台设备的实发字节与固件生效结果，仍需抓取一次 Kinetic Switch Save 同步日志，并分别观察 `0x801A` payload 的 TTL 字节和是否出现 `0x800D`。
