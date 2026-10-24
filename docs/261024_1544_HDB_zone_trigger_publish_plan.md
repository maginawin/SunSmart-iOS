# HDB Zone：Publish Occupancy / Publish Vacancy 方案与实施记录

日期：2026-10-24。状态：用户确认后已完成 App 实施、相关隔离回归及 SunSmart generic iOS Debug 构建；未操作真机。

已在 Zone 详情页的 Members 上方增加 Trigger Zone 区域，两个按钮分别向当前 Zone 的组地址发送 Presence Detected=true/false。当前 Zone 订阅已覆盖 Light LC Server，本次未增加 JSON 字段或扩展 sensorGroupModels 的订阅。两个按钮表示发布感应事件，不能承诺全部成员已经切换状态；尤其 Presence=false 不保证立即进入 Vacancy。

## 1. 两个按钮发送什么

每次点击重新核对当前 Site、Space、Zone 和权限，通过现有 Mesh 发送队列提交一条组播消息。

| 项目 | Publish Occupancy | Publish Vacancy |
| --- | --- | --- |
| Message | Sensor Status | Sensor Status |
| Opcode | `0x52` | `0x52` |
| Property | Presence Detected，`0x004D` | Presence Detected，`0x004D` |
| Raw Value | `0x01` / true | `0x00` / false |
| SDK 编码后的 parameters | `A0 09 01` | `A0 09 00` |
| 目的地址 | 按当前 zoneId 查 `hdb.lightingZones[].groupId`，解析为 UInt16 | 同左 |
| AppKey / TTL | 当前 Space AppKey；沿用现有控制发送路径的默认 TTL | 同左 |
| 设备 ACK | 无 | 无 |

源地址为 App 当前 Provisioner 的本地 Element，现有 API 默认使用 Primary Element。这里由 App 模拟 Sensor 上报，不借用某台真实传感器的源地址，也不配置真实传感器改向 Zone 发布。

SDK 已有 `SensorStatus`、Presence Detected、Bool 编码和按地址发送接口，按当前接口不需要修改 SDK。按钮不发送 `LightLCOccupancyModeSet(false)`；该命令修改的是自动感应模式，并非发布无人事件。

## 2. 能否让整个 Zone 进入对应状态

Bluetooth Mesh Model 1.1 §6.5.1.7.1 规定：LC 接收有效 Presence>0 后，按 Occupancy Delay 触发 Occupancy。§6.2.5 的状态机没有对应的“收到 Presence=0 立即 Vacancy”转换；正常回落依赖计时。由此不能推定 false 会提前结束 HoldTime。[Bluetooth SIG Mesh Model 1.1](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/MMDL_v1.1/out/en/index-en.html)

对本项目的含义：

- Occupancy：已完成 Zone 订阅和 AppKey 绑定、在线可达、LC 自动控制条件满足的灯具可以响应。当前 HDB preparation 的目标值包含 LC Mode=true 和 Occupancy Mode=true，但保存的配置与初始化回执不代表设备当前运行状态。
- Vacancy：发送一次 false 可以作为无人消息测试；灯具是否立即下降，必须以目标固件行为为准。标准路径通常是在没有后续有人触发后，按已有 HoldTime、RampDownTime 回到较低亮度。项目把 DimIntensity 配到 LC Prolong Lightness，因此不能把 Vacancy 简化成 Off。
- 自带传感器仍向本机 LC 单播。真实有人、其他消息来源或其他 Zone 的触发可继续影响同一个 LC；按下 Vacancy 不清除其他来源，也不暂停传感器。
- Members 是期望成员清单。订阅 pending、历史残留订阅、离线和无线丢包都可能使实际响应集合与清单不同；无 ACK 的发送不能作为全部成员执行成功的证据。

若验收要求变成“点击 Vacancy 后立即跳过 HoldTime、进入 DimIntensity”，需固件团队明确支持的命令、状态转换、优先级及与本机传感器并发的规则，再规划 App 映射。增加 Model 订阅不能补足这个状态机契约；本轮不修改固件或服务器。

## 3. 接收 Model、JSON 与多 Zone 订阅

负责消费感应数据并驱动灯控的是 **Light LC Server `0x130F`**，不是发送感应数据的 Sensor Server `0x1100`。当前 `spaceData.hdb.devices[]` 已保存所需模型清单与成员关系。

| 字段 | 当前实际用途 | 本次处理 |
| --- | --- | --- |
| `lightingZones` | 设备所属 zoneId 数组，最多 8 个 | 继续由它确定全部 Zone 目的组 |
| `zoneModels` | 所有 Elements 的 `130F`、`1310`、`1300`；仅 Primary 的 `1000`、Vendor `0A780001` | 已包含必要的 LC 接收方，继续使用 |
| `sensorGroupModels` | 所有包含 LC 的 Elements 上实际存在的 `130F`、`1310`、`1000` | 保留现有元数据语义，本次不增加订阅用途 |
| `sensorGroupId` | 为其他功能保留的设备 Sensor Group 地址 | 不作为这两个按钮的目的地址 |
| `sensorPublication` | 当前设备 Presence Sensor 向本机 LC 单播的配置 | 不改动 |

`HDBLightingZonePolicy.operations` 当前已经按以下顺序生成设备配置：

1. 对全部 zoneModels 执行 Subscription Delete All。
2. 恢复受影响模型的 Broadcast 订阅。
3. 遍历设备全部 lightingZones，解析每个 zoneId 对应的 groupId，对全部 zoneModels 分别执行 Subscription Add。

因此，设备加入两个 Zone 时，其 LC 已经订阅两个 Zone 的组地址。例如设备属于 Zone 7 / Zone 9，目录映射为 `C107` / `C109`，其 `000A/130F` 接收方应同时订阅这两个地址。这里的地址仅为示例，不使用 zoneId 加固定偏移来推算真实 groupId。

`1310` 是 LC 配置模型，`1000` 是 OnOff 控制模型；保留现有订阅规则即可，无需为了 Sensor Status 再对整个 sensorGroupModels 增加一轮 Zone 订阅。部分模型有共享订阅关系，但不依赖这种关系来替代显式配置 LC。

Zone 页面 Set/Retry 与普通 Sync 均使用上述生成器，清空、移除成员、失败重试仍沿用现有机制。当前导入导出会核对 Composition 与模型清单；本次无 schema、持久化或存量迁移变更。如果设备实际订阅与保存结果不符，使用现有 Set/Retry 重新应用该设备全部 Lighting Zones。

## 4. 已实施的 App 改动

1. **页面**：在 `HDBLightingZoneDetailViewController` 的 Test Controls 与 Members 之间增加 Trigger Zone section，一行两个按钮。沿用当前按钮样式和点击反馈；长文案可换行，使用动态行高。新增 section 后把成员点击限定到明确的 Members section，避免现有 `section >= 2` 把新按钮区当成成员列表。
2. **服务**：在 `HDBLightingZoneService` 增加发布 Presence 的入口，共用 `validateControl` 和现有发送队列。映射地址由服务重新校验，不把 zoneId 当作组地址。无持久化、云端上传或订阅任务副作用。
3. **反馈与生命周期**：记录本页最近一次触发请求，使用 Requested 语义，不作为设备当前状态或全体成功回执；与 Auto/On/Off 的选择反馈分开。页面失活时不接受新点击，不持久化请求，不在重进、重连、重启后自动补发。
4. **文案**：复用 `trigger_zone`；新增两个按钮及简短行为说明的英文、简体中文 Key。英文按钮使用需求给定的 Publish Occupancy / Publish Vacancy，说明明确 Vacancy 可能遵循保持和渐变时间，未确认设备实际状态。

继续拒绝：无编辑权限、恢复保护、Site/Space 或组映射变化、空 Zone、当前任务忙、断连、消防/紧急模式。沿用当前测试控制策略，允许存在 pending 成员的非空 Zone 提交测试请求，并提示成员清单与实际响应可能不同；不新增“任一成员 pending 就禁用全 Zone”的条件。

页面与服务由多个品牌共享，按各品牌现有 HDB 开关可见。此次不改变品牌开关、工程资源归属、SDK API、依赖声明或传统 Site/Space Trigger Zone 业务。

## 5. 验证与人工验收

已扩展已有控制回归，验证两条消息的 opcode、property、raw value、完整 parameters、目的地址、每次点击一条逻辑消息，以及配置/上传次数不变。覆盖现有权限、连接、空 Zone、紧急状态、错误映射和 pending 成员边界；页面回归执行实际动作、提示更新和成员路由方法，覆盖失活拒绝、失败保留上次请求以及与 Auto/On/Off 提示分离。编码回归提取本地 SDK 的 Sensor Status 构造、MPID marshalling、Presence ID 和 Bool 序列化实现执行，仅适配夹具类型和可见性，没有在测试替身中重新实现报文字节规则。

已使用 SunSmartLocal workspace 对 SunSmart 做一次 Debug generic iOS 构建，`iphoneos`、`generic/platform=iOS`、`CODE_SIGNING_ALLOWED=NO`，退出码 0，输出 `BUILD SUCCEEDED`。DerivedData 使用 `/Users/maginawin/Library/Developer/Xcode/DerivedData/SunSmart-feat-HDB-261020`。工程核对确认 SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux、HSmart 共 6 个 target 均引用同一页面、服务和 Localizable.strings；本次没有新增资源归属或品牌编译分支，因此只构建代表 target SunSmart。未使用 Simulator，未安装或运行真机。

| 检查 | 本轮实施后结果 |
| --- | --- |
| `check_hdb_zone_control.py` | 通过；实际 SDK 编码、目的地址、一条逻辑消息、无持久化/上传副作用及拒绝/允许边界 |
| `check_hdb_control_observation.py` | 通过；连接/紧急通知、页面失活、独立请求提示、拒绝后的反馈、Members 精确路由 |
| `check_hdb_integration.py --subelement` | 通过；跨 Element 订阅，Sensor 有/无与 0/1/2/8 个 Zone，失败/重试/取消及缓存收敛 |
| 本地化与工程静态检查 | 英文/简体中文 strings 语法通过，6 个 target 资源/源码归属一致，差异无空白错误 |
| SunSmart Debug generic iOS 构建 | 通过；本地 SDK revision 仍为 `e7c1a7f`，SDK 无本次改动 |

最短人工验收：

1. 两台完成 preparation / Zone Sync 的灯加入同一 Zone，另有一台不属于该 Zone；接收方包含非 Primary LC。点击 Occupancy，确认目标灯响应、非成员不响应。
2. 在真实传感器无新触发的条件下点击 Vacancy，记录是否立即变化，或按 HoldTime + RampDownTime 回落；记录设备型号、固件版本和实际时间，不能仅记录 App 点击成功。
3. 同一灯加入两个 Zone，分别触发；再移除其中一个并完成 Sync，确认旧 Zone 不再影响它。
4. 在本机传感器持续触发、手动覆盖、断连及重新进入页面时，确认实际行为与提示一致；确认两个按钮和 Members 仍可正常操作。

隔离 UI 回归未渲染 UIKit 界面；真实布局、无线覆盖和固件 Vacancy 行为仍按以上步骤待人工验收。编译及回归不替代这些运行结果。

## 6. 证据与外部边界

- 当前核对：App `feat/HDB-261020`，HEAD `c258098b`；本地 SDK 映射到 `one-dev`，HEAD `e7c1a7f`。开始分析时两个工作树均无未提交改动。
- [Zone 订阅策略](../SunSmart/Common/Data/HDBLightingZonePolicy.swift)、[Composition 到 JSON 清单](../SunSmart/Common/Data/HDBConfigurationStore+Mesh.swift)、[统一同步上下文](../SunSmart/Main/Space/HDB/Model/HDBDeviceSyncContext.swift)。
- [Zone 页面与交互](../SunSmart/Main/Space/HDB/Controller/HDBLightingZoneDetailViewController.swift)、[控制校验与发送](../SunSmart/Main/Space/HDB/Model/HDBLightingZoneService.swift)、[本机 Sensor 单播的当前契约](261024_1136_HDB_sensor_local_unicast_analysis.md)。
- [SLP 协议的 Trigger Zones](../protocols/HDB/SLP%20Interface%20Control%20Document.md) 是给传感器配置触发目标的功能；本需求是 Zone 页面手动发消息，不能据此声称已经完成 SLP setTriggerZone/getTriggerZone。
- 现有 [HDB 网关配置任务](../protocols/HDB/HDB%20网关配置任务.md) 仍包含旧的 Sensor Group publication / 订阅描述，与 10 月 24 日 App 当前实现不同。本方案以现行代码及当天单播契约为准；该既有文档差异应另行对齐，不据其推断外部网关已经支持新契约。
