# SIG Mesh Vendor Command 0x32 GET/SET 用途分析

## 结论

- `0x32` 是 Sunricher Vendor 协议里的业务操作码，SDK 命名为 `manualOverrideTimeout`。
- 它属于 `LIGHT_CTRL`，用途是配置或读取 “Manual override timeout”，即手动控制后保持手动状态多久，以及超时后回到哪个 Light LC 阶段。
- `0xF00A78` 是协议文档中的 SET 类型 Vendor Opcode；GET 类型不是 `0xF00A78`，而是 `0xF10A78`。
- 当前 App/SDK 代码中，SET 有实际业务调用；GET 只在 SDK 消息枚举和解析层支持，没有发现 App 侧实际发送 `manualOverrideTimeout` GET。

## Opcode 说明

协议文档使用 Company ID `0x0A78`，并把 SET/GET/RET 写作：

- SET: `0xF00A78`
- GET: `0xF10A78`
- RET: `0xF30A78`

SDK 中对应常量显示为：

- `SunricherVendorSet.opCode = 0xF0780A`
- `SunricherVendorGet.opCode = 0xF1780A`
- `SunricherVendorStatus.opCode = 0xF3780A`

这是访问层编码/字节序展示差异：实际三字节 PDU 是 `F0 78 0A`、`F1 78 0A`、`F3 78 0A`。

## SET: 0xF00A78 + 0x32

协议含义：

- 服务模块：`LIGHT_CTRL`
- 用途：手动重载设置
- 参数：使能开关、超时后状态、间隔时间
- SDK 枚举：`VendorFunctionSet.manualOverrideTimeout(enabled:state:interval:)`
- 参数单位：SDK 传给固件的是毫秒；App 的 Profile 配置通常以秒保存，同步时会转换为毫秒。`UInt32.max` 表示无限长。

实际使用功能：

1. Profile/Group 的灯控参数同步
   - 用户在 Profile Settings 中编辑 Manual override timeout。
   - 保存到 `Profile.manualOverrideTimeout`。
   - 组同步时根据 profile 类型生成 `.manualOverrideTimeout(...)`。
   - `daylight` 类型超时后状态为 `.on`，其它常见灯控类型为 `.standby`。

2. 设备同步状态判断
   - 同步列表会用节点本地缓存的 `manualOverrideEnabled`、`manualOverrideTimeout`、`manualControlState` 判断该项是否已经同步。

3. 新增设备未加入组时的默认初始化
   - Classic Add Device、Professional Add Device 都会对具备 Vendor Model 和 Light LC Model 的未入组灯控设备下发 `manualOverrideTimeout(enabled: true, state: .standby, interval: .max)`。
   - 代码注释说明目的是避免设备默认 30 秒后状态被 LC 修改。

4. 设备恢复流程的默认初始化
   - Restore 流程在未加入组时也会下发同样的无限长 manual override 配置。

5. 应答后更新节点缓存
   - 收到 Vendor Status 后，SDK 会把 `enabled/state/interval` 写回节点的 `lightLCProperty`，供后续同步判断使用。

## GET: 0xF10A78 + 0x32

SDK 支持：

- `VendorFunctionGet.manualOverrideTimeout` 会编码为业务操作码 `0x32`。
- `SunricherVendorStatus` 对 `0x32` 的返回支持解析 `enabled/state/interval`。

当前实际使用情况：

- 没有发现 App 或 SDK 当前业务流程实际发送 `SunricherVendorGet(function: .manualOverrideTimeout)`。
- 协议文档的 GET 总览也没有列出 `0x32`，但 SDK 层已经预留了 GET 枚举和返回解析。
- 因此当前可以认为 GET 是“可被 SDK 表达和解析的查询能力”，但不是现有 App 功能链路里的已用命令。

## 关键代码位置

- 协议文档：`SunSmart/sunricher_protocol_vendor.md`
  - SET/GET/RET 类型表：第 70-72 行
  - SET 0x32 定义：第 144-150 行
  - RET 0x32 定义：第 419-425 行
  - GET 总览：第 565-587 行
- SDK Vendor 消息：
  - `SunricherVendorSet.swift`：SET opcode 和 `manualOverrideTimeout` 编码
  - `SunricherVendorGet.swift`：GET opcode 和 `manualOverrideTimeout` 枚举
  - `SunricherVendorStatus.swift`：`0x32` 映射和返回参数解析
- App 业务链路：
  - `ProfileSettingsViewController.swift`：Profile 页面编辑 timeout
  - `Node+SyncData.swift`：根据 Profile 生成同步项
  - `Node+MessageHandles.swift`：同步项转为 `SunricherVendorSet`
  - `DeviceAddClassicModeController.swift` / `DeviceAddProfessionalModeController.swift`：未入组设备默认初始化
  - `DeviceRestoreViewController.swift`：恢复流程默认初始化
  - `SyncDevicesCellModel.swift`：同步完成状态判断

