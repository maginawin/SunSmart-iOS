# 北美停车场 Mesh 同步顺序与通讯路径分析

日期：2026-09-17。范围：分析，不修改业务代码或 SDK。

## 结论

不能直接归类为“SIG Mesh 通讯层问题，App 无法优化”。当前代码可以确认同步任务保留输入列表顺序并串行推进；常规组配置的数据来源保留节点入网列表顺序，因此先添加的远端设备可能先执行、先等待应答，从而推迟后面的近端设备。这个顺序不等于 Mesh 无线转发路径。

现场描述及 Jesse 的模拟尚不能证明整批变慢的根因。候选因素包括任务排队、目标链路丢包与应答超时、手机移动后代理未切换、代理到目标的中继覆盖，以及设备端处理差异。需区分首个完成时间、单设备实际发送到应答耗时、整批总耗时。

## 核对基线

- App：`fix`，HEAD `24037dd3`；开始调查时工作树干净。
- 本地入口：`SunSmartLocal.xcworkspace`，引用 `.local-sdk/nordic-sig-mesh-sdk`。
- SDK realpath：`/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`，HEAD `a971027`；调查时无未提交差异。
- 结论基于当前代码；现场 App/固件版本尚未核对。本次未构建、未运行真机、未采集现场性能数据。

## 已证实的代码行为

| 层次 | 代码入口与行为 | 含义 |
| --- | --- | --- |
| Profile 页面 | `SunSmart/Main/Profile/Controller/ProfileSettingsViewController.swift` 将组 Profile 同步交给 `SyncDevicesViewController(type: .group(...))` | 实际分析的是当前组 Profile 下发入口 |
| 任务生成 | `SyncTaskPlanBuilder.swift` 遍历 `group.nodes`；`SyncProfileTaskBuilder.swift`、`SyncParameterTaskBuilder.swift` 保留传入列表顺序；`SyncSceneScheduleTaskBuilder.swift` 保留同步数据中的设备顺序 | 未在这些任务生成入口发现按 RSSI、实际跳数或网关距离排序 |
| 节点来源 | SDK `Group+Nodes.swift` 从 `realNodes` 过滤；`MeshLibManager.swift` 从 `meshNetwork.nodes` 过滤；`MeshNetwork+Nodes.swift` 添加节点时使用 `nodes.append(node)` | 常规添加流程中的组节点顺序与添加顺序一致；导入、恢复及不同上游列表不能一概而论 |
| 调度 | `SyncDevicesCellModel.swift` 的 `allModels` 保留模型顺序；`SyncExecutionSession+Tasks.swift` 的 `getNextHandleModel()` 逐设备取待执行任务；`SyncExecutionSession.swift` 在当前操作完成后推进 | 前面设备等待应答时，后面设备等待调度 |
| 超时 | `SyncOperationResultPolicy.swift` 普通操作 ACK timeout 为 15 秒；`SyncExecutionEnvironment.swift` 传给 SDK `MeshProxyMessageCommand` | 丢包或无应答可能把一次操作拖入秒级等待；15 秒是超时配置，不是每次发送固定耗时，也不是完整操作耗时上限 |
| 代理选择 | SDK `MeshLib/MeshNetwork/NetworkConnection.swift` 默认 `maxConnections = 1`；自动扫描发现 RSSI ≥ -70 dBm 的候选即可连接，否则对收集候选按 RSSI 降序选择 | 不是按设备添加顺序固定选择入口，也不保证始终选择全网最优代理 |
| 代理切换 | 自动连接模式下定时读取已连接代理 RSSI；满足 RSSI < -85 dBm 等条件才启动重新扫描；弱信号候选排序分支另有至少 15 dB 改善判断 | 人走近另一盏灯不代表立即换代理；这些阈值属于现有实现，不能据此宣称适合现场 |
| 数据发送 | `NetworkConnection.send` 通常使用当前已打开代理，切换期间另有选择分支 | 未在此发送入口按每个目标设备选择最优代理或生成无线中继路径 |

以上 App 同步模型文件均位于 `SunSmart/Main/Space/Model/`，SDK 路径以本地 SDK 根目录为基准。

## SIG Mesh 与 App 的责任边界

SIG Mesh 1.0 使用 Managed Flooding：启用 Relay 的节点根据 TTL、消息缓存等条件转发，不使用设备添加先后作为转发链。手机通过 GATT Proxy 接入网络时，代理入口与最终配置目标可以是不同设备。参见 [Bluetooth SIG Mesh Networking Primer](https://www.bluetooth.com/bluetooth-mesh-networking-primer/) 和 [Directed Forwarding 技术说明](https://www.bluetooth.com/mesh-directed-forwarding/)。

Mesh 1.1 增加 Directed Forwarding，由支持该能力的网络节点建立、维护转发路径；不能假设现有灯具固件已经支持，也不能通过 App 调整列表顺序获得此能力。参见 [Bluetooth SIG Feature Enhancements Summary](https://www.bluetooth.com/mesh-feature-enhancements-summary/)。

App 可优化任务调度、失败设备延后重试、必要消息数量；App 与 SDK 可共同优化代理选择、连接切换与发送节奏。无线覆盖、设备端 Relay 行为及支持能力则涉及固件和部署。扫描 RSSI 仅说明手机附近可发现设备的信号，不能当作全网拓扑或代理到所有目标的距离。

调整顺序时必须保留 Profile 锁定、切换、参数写入、保存及恢复等依赖。若所有设备仍需执行完全相同的操作、每个设备耗时不变，仅交换顺序一般只改善部分设备的完成时间，不会明显降低整批耗时。不能把“近端先完成”当作整网传输性能提升。

## 最小现场对照

1. 固定设备集合、固件、待下发参数和消息量；每轮确保确实有同等配置需要下发，避免第二轮因差异同步减少消息。
2. 在 A、B 两个位置分别记录：实际连接代理、代理 RSSI、目标地址、任务开始与首次实际发送时间、应答时间、失败/超时/重传情况、整批耗时。仅看进度列表或体感不足以定位。
3. 同一位置比较保持原代理与重新连接后执行，核对移动后的入口因素；代理固定且负载一致时再比较设备执行顺序，区分排队与单设备通讯耗时。
4. 若目标从实际发送开始就慢，继续核对代理到目标及返回方向的覆盖、Relay/TTL/重传配置和设备处理；若仅等待轮到自己慢，则优先评估调度。

若现场实际是云端经固定网关下发，应另查网关到 Mesh 的链路。本次查明的普通配置路径为 App 经 `MeshProxyMessageCommand` 的蓝牙下发，不能直接外推到云端网关。

## 建议对外表述

“已确认当前配置任务按设备列表顺序执行，弱链路设备排在前面时会影响后续设备的配置等待时间；该顺序不代表 Mesh 报文按设备添加顺序转发。问题涉及 App 调度、SDK 代理连接及现场 Mesh 通讯质量，仍有软件优化空间，需通过代理连接和单设备应答/超时日志确定主要瓶颈。”
