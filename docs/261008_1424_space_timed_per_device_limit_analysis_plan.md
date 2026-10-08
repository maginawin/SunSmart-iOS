# Space Timed 按设备限制 16 条：现状分析与改造方案

日期：2026-10-08。状态：用户已确认按推荐方案分阶段实施；实施范围限定为 App。固件、服务器代码永远不修改，外部配套仅记录在本文并由对应团队负责。

## 1. 结论与目标

当前 App 的 Site → Space → Timed **正常创建流程限制每个 Space 共 16 条定时**。设备、组、场景目标共享这 16 条，停用的定时和没有实际设备的定时也计入。限制不是 SQLite 或已核对后端的列表容量，而是 App 将业务 `Schedule.id` 和设备 Scheduler 物理 index 合为同一个 `0…15`。

用户要求的“Space 可以超过 16 条、每台设备最多 16 条”能够基于现有 App/SDK 实现，但当前版本不能直接支持。仅移除页面计数和新增拦截会造成槽位覆盖；应拆分 **Space 内稳定业务 ID** 与 **每台设备自己的物理 slot**，同时覆盖同步、回执、关系变化、持久化和云端保护。

推荐保留 `Schedule.id: Int` 作为业务身份，新增每设备 slot 映射。SDK 的协议和设备缓存继续使用 `0…15`，保留当前普通 Scheduler / Light LC Scheduler 的 owner 选择与残留清理。没有证据表明本需求必须增加 SDK API 或修改固件；现有 SDK 能力具备，具体设备运行仍须验收。

用户已确认：**可以要求旧版 App 升级后才能编辑采用新格式的 Space**。兼容目标包括旧本地数据、旧云数据被新版读取/迁移，以及新版完整上传、云导入、重启恢复；不要求旧版继续编辑新格式。

## 2. 本次核对范围和基线

| 对象 | 当前基线 | 边界 |
|---|---|---|
| App | `feat/timed-limited-261008`，HEAD `6d0b1bbd`；开始时工作树干净 | 本文新增前再次确认干净 |
| 本地 workspace | `SunSmartLocal.xcworkspace` | 引用 App、Pods 和 `.local-sdk/nordic-sig-mesh-sdk` |
| SDK | `.local-sdk/nordic-sig-mesh-sdk` 实际指向 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`；HEAD `2598bd1`，干净 | 只读，没有修改或新 API 依赖 |
| 本地后端 | `/Users/maginawin/Developer/SunSmartDev/sunsmart-services`；HEAD `df617d8`，干净 | 源码和离线映射证据，不代表线上部署 |
| 品牌 | SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux | 定时共享代码；资源/配置风险需在实施时逐 target 核对 |

分析覆盖：页面/新建引导 → 目标解析 → 业务身份和设备槽位 → 组/场景/设备恢复 → 同步任务与回执 → SQLite → Space/Site 云上传导入与回读保护。分析阶段未构建；实施后的构建和回归见第9节。全程未操作真机或请求线上云服务。

## 3. 当前具体限制与定时类型

### 3.1 限制位置

| 位置 | 当前行为 |
|---|---|
| `SunSmart/Main/Timed/Controller/TimedViewController.swift`，66、199、425 附近 | 底部显示 `count/16`，已有 16 条时禁止进入新增 |
| `SunSmart/Main/Timed/Controller/ScheduleAddViewController.swift`，198 附近 | 保存新增前调用全 Space 的 `getNextAvailableScheduleId()` |
| `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`，733–753 | 默认名称只寻找 1…16；业务 ID 只寻找 0…15 空位 |
| `SunSmart/Main/Space/Controller/SpaceNewCreationProcessController.swift`，93 附近 | 新建引导的“继续创建定时”同样检查 Space 数量小于 16 |
| `SunSmart/Main/Timed/Model/Scheduler.swift`，119、225–243 | id 声明为 0…15；`data` 直接将 id 转 UInt8 作为设备 index；停用修改 year，仍保留定时 |
| `SunSmart/Common/Data/Database.swift`，1286–1342 | SQLite 无 16 条限制，但业务 ID 在 Mesh/子网范围内唯一 |

上述是正常 UI 创建限制，不是“任何导入数据都必然最多 16”。云 Schedule 解码没有以 16 条为上限的完整业务验证，因此异常/外部数据可能绕过 UI；它们仍会遇到同一 index 耦合问题。

### 3.2 当前可用类型

| 用户选择 | 动作 | 实际执行设备 | 当前数量关系 |
|---|---|---|---|
| Devices | Auto/On、Off | 直接选中的设备 | 与其他类型合计占 Space 的 16 条 |
| Groups | Auto/On、Off | 所选组的成员设备 | 一条组定时会在每台适用成员设备占一个槽 |
| Scenes | Recall | Scene 关联组的成员设备 | 一条场景定时会在每台适用成员设备占一个槽 |

时间设置是按星期选择、时/分执行的 Schedule。同一条定时选择多个星期仍是一条记录，不按重复天数累计容量。

代码还保留 `TimedSelectTypeView` 的 Schedule / Rhythm / Time 类型，但该选择栏在 `TimedViewController.setupUI()` 中被注释；非 Schedule 分支只显示开发中。`Schedule.TargetType.profile` 是保留类型，编辑页和同步规划对应分支未实现，不能将它当作当前可用的第四类定时。迁移应保留已存的合法保留字段，不擅自转成其他类型。

Dongle 的 Collection Schedule 与后端的 GatewaySchedule 是其他功能，不能用来替代本页面的 Mesh Schedule，也不在本次解除 Space 上限的范围。

### 3.3 为什么设备存在 16 的限制

Bluetooth Mesh Model 规范规定，**每个 Scheduler Server 实例对应的 Schedule Register 是 16-entry 数组**；Action Set 的 Index 只有 4 bit，范围 `0x0…0xF`。规范限制的是对应 Element/Model 的 Register，不是 App 的 Space。依据：[Bluetooth SIG Mesh Model 1.1，5.1.4.2、5.2.3.4、5.3.6](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/MMDL_v1.1/out/en/index-en.html)。

有些设备同时有普通 Scheduler 和 Light LC Scheduler，它们具有不同 Register。“每台设备总共 16 条”是本需求明确采用的产品规则，不能表述成所有多 Model 设备物理上只存在 16 个条目。本方案跨这些 Model 共同预留 16 个 slot，确保每条业务定时在设备上只有一个有效 owner，不扩展成每个 Model 各 16 条业务定时。

当前 owner 规则：Auto/On 且有效组为自动控制组时优先 Light LC；其余用普通 Scheduler；单 Model 设备由 SDK 回退到唯一模型。Devices Target 的设备若属于自动组，同样可能选 Light LC。这是执行语义，与业务目标类型并非一一对应。

从源码可确认，App 使用全 Space 唯一 id 让每台设备使用相同 index，简化了分配、查找、清理和同步。因此把协议槽位上限扩大成了 Space 业务列表上限。此处是实现机制解释，不推定当初产品决策的历史动机。

## 4. 为什么不能只解除页面限制

SDK 的 `SchedulerRegistryEntry.marshal` 只写 index 的低 4 bit；下发 `id=16` 会编码成 slot 0。超过 UInt8 范围的业务 ID 在直接转换时还会触发转换失败。SDK initializer 的范围注释不能代替 App 的校验。

同时让不同定时复用同一个业务 id 也不成立：SQLite 的唯一键、数组查找、删除、通知和绑定关系都依赖 Space 内唯一 id。

| 方案 | 判断 |
|---|---|
| 仅移除 `count < 16`、扩大 id 范围 | 不可采用；协议 index 被截断，其他身份使用点未改 |
| 每条定时仍共用一个 slot，只让不重叠设备复用 | 不推荐；还需拆业务身份，并且不同设备可能各有空位却没有共同空位，无法完整满足“只按设备容量限制” |
| 稳定业务 id + 每设备 slot 映射 | 推荐；设备各自分配，复用既有下发与 owner 清理机制 |

示例一：A 设备有 16 条只作用于 A 的定时，B 设备有 16 条只作用于 B 的定时，Space 应能保存 32 条。示例二：两台设备尚未满时，一条同时作用 A/B 的定时可以在 A 使用空闲 slot 2、在 B 使用空闲 slot 7；不要求两台设备拥有同一个空闲编号。

## 5. 推荐设计

### 5.1 业务身份与映射

保留现有 `Schedule.id: Int`、名称、目标类型、目标地址、动作、时间与周期。不强制引入 Schedule UUID，也不对旧记录全量重新编号。

新增每条定时的节点绑定记录，建议字段表达：节点 UUID、设备配网身份指纹、节点地址、物理 slot、配置/待移除状态，以及用于校验异步任务归属的操作代次。配网身份校验复用已有 `SchedulerModelSnapshot` 的 UUID/地址/DeviceKey fingerprint 思路，不新增或输出完整密钥。

规则：

- 业务 id 只用于 App 对象/SQLite/组场景绑定；不再转换为 UInt8 或用于设备缓存查找。分配与 slot 独立，保持有效记录和待清理记录中的唯一性；新增编号不重排已有定时。
- 同一节点身份 + slot 只能属于一条业务定时；同一业务定时在该节点只有一个 slot。该 slot 在该节点全部 Scheduler Models 上归同一业务定时，不能给另一个 owner 的不同定时复用。
- SDK 的 `allSchedulerModelEntrys[model][slot]`、`schedulerActions[slot]` 和 `scheduleIds` 保持物理含义。
- 发包、差异比较和清理通过“定时 + 节点 → slot”解析；收到回执通过“网络/节点身份 + slot + 当前任务 → 业务定时”反查。映射缺失/冲突必须形成明确错误，不能返回空任务后被判成成功。
- `Schedule.data` 这种不带节点上下文却直接包含 index 的接口要清除耦合或改为显式接收已验证 slot。

建议将映射保存到 Schedule 的本地扩展列及 `schedules[].nodeSlots`（字段名待实施时统一），并在 `spaceData.timedSchemaVersion` 声明新格式。`spaceData` 当前由显式字段重建，需要同时增加本地保存、导入和导出。

### 5.2 容量规则

以去重后的“设备上的不同业务定时”计数，Devices / Groups / Scenes 合并计算。目标展开复用 `Schedule.targets(node:contextGroup:)`、既有组成员解析和 Scene 关系，预检查使用**拟提交的新关系**，不能仅查询修改前的 `group.nodes`。

- 停用定时继续占槽，保留当前停用语义；不开辟新的“停用无限量、启用再抢槽”需求。
- 尚未下发、下发失败或已保存待重试的定时仍预留槽位；否则失败后其他定时可能占用其原 slot。
- 删除未确认、移出目标未确认的绑定继续占槽；清理完该节点所有相关 Models 后才释放。
- 已确认空的 Model 和未知 Model 严格区分；无可信状态时按需权威读取。读取失败不能视作空槽。
- 无归属的设备有效条目不能当作空位、不能凭相同时间/动作任意认领或删除；先识别合法 legacy 归属或进入待修复状态。
- 一条定时通过多条关系落到同一设备时只占一次；不同业务定时即使时间相同仍分别占槽，不在本次做合并压缩。
- 合法空组/空 Scene 目标可继续保存定时，不占设备槽；以后加入设备时检查该设备能否承载所有关联定时，不人为再设 Space 16 上限。
- 无 Scheduler 能力的设备不分配槽位；沿用现有能力与适用性处理，不能把“不适用”误报成容量不足或同步成功。

新建、目标编辑、组成员新增/恢复、场景增减组及执行前统一复核。容量不足时指出具体设备及占用原因，保留用户编辑输入；已满 16 条不应阻止改名、修改已有定时的时间/动作、移除目标、删除或清理重试。owner 切换沿用原 slot，不多占一条。

“移除旧定时并加入新定时”的组合操作可以先清理再占用；旧清理失败则后续写入保持待办，不越过未释放槽位。新增保护必须允许这条恢复路径。

### 5.3 操作顺序与恢复

1. 对完整候选目标和当前绑定计算差异及容量；跨多台设备先完成校验，不能一边修改业务对象一边发现后续设备超限。
2. 将配置变化、slot 预留、待清理绑定作为一次本地事务保存；已存在的绑定优先保持。只有准备完成才生成发送任务。
3. 复用现有“非 owner 清理 → owner 写入”、设备批次一次 TimeSet、Scene 下发依赖和失败/取消机制。
4. 成功、部分失败、取消、重启均使用同一持久映射重试。云上传表达配置意图及待清理状态，不能把缓存 ACK 当作业务配置身份。
5. owner 清理成功但新写入失败时仍预留原 slot 并显示 Unsync；所有 Models 清理完成、旧任务结束后才能释放。
6. 任务携带原 Space/网络、节点配网身份、业务 id、slot 和操作代次。切换 Space、重配设备、取消后迟到 ACK 不能释放或更新新绑定。由于协议本身不含业务代次，还需复用队列串行/取消边界和必要读回，不能仅添加本地 generation 字段就声称消除了迟到报文风险。
7. 永久删除/重新配网沿既有删除生命周期处理；设备地址被复用不代表同一配网身份。恢复旧设备时迁移业务目标，但新设备槽位以其身份和实际空状态重新规划。

## 6. 兼容性与云端方案

### 6.1 旧数据迁移

纯读取旧格式可保持原样；新版第一次修改该 Space 时，将其整体事务迁移为新格式，比“只有创建第 17 条才切换”减少双模式写入分支。云管理的 Space 在启用新格式写入前，应先确认服务端支持并建立旧端保护，不能先发送新设备配置后才发现服务器无法保留映射。

- 未声明新 schema 的有效旧记录，id 唯一且在 0…15：按历史含义为相关节点建立 `slot = id`，保留现有物理槽位，不因升级重排或重新下发全部定时。
- 迁移目标包括 active、待移除的节点/组/场景，以及权威设备状态可证明的历史残留；旧缓存缺失保持 unknown，不伪造“已同步”。
- 继续支持当前已知合法格式：可选旧字段、空目标、现有 Scene 地址数字/十六进制形式的解码兼容。校验可规范化合法旧值，不能整体放宽网络/设备身份校验。
- 重复 legacy id、legacy id 超范围、已声明新 schema 却缺必要映射、未知未来 schema，均在修改数据库前拒绝并保留当前配置；不静默回退成 legacy，不截断成前 16 条。
- 新格式中“无设备目标”允许空绑定；有实际待配置设备却缺映射属于损坏/未完成规划，必须明确区分。
- 同一 Space 已迁移后，普通云同步不能把过期旧格式写回当作新配置。已迁移 Space 导入旧备份同样拒绝，保留当前配置。原方案设想的“显式恢复旧备份后向前迁移”尚未实现：现有文件导入直接复用云导入，没有独立的恢复生命周期，不能假设设备仍处于旧备份时的 slot 状态。要支持此场景，需要单独核对当前设备占用、保留 v2 待清理绑定并形成可重试的恢复事务；此项保持待办，不能视作旧数据首次导入已经覆盖。

### 6.2 云端同时保留两类数据

| 字段层级 | 新格式语义 |
|---|---|
| `space.schedules[]` | 完整业务定时，id 可大于 15；携带节点 slot 绑定与必要待清理状态 |
| `space.spaceData.timedSchemaVersion` | 业务定时格式版本；与现有 Proximity Lighting 字段并存 |
| `nodes[].schedules[]` | 设备物理槽位缓存，id 继续是 0…15 |
| `nodes[].custProps.schedulerModelStates` | 每个 Model 的原始物理快照；保留 schema 1、known empty/unknown、身份校验，不为业务扩容更改其 index 含义 |

当前 `Schedule` 的 Codable 没有编码 `needDeleteNodeAddresses/Groups/Scenes`，而 SQLite 会保存这些字段。新方案必须将恢复清理所需的节点/slot 状态纳入云数据。删除未结束的业务对象/绑定不能先丢弃；后续组或场景被删除，也应靠持久节点身份和 slot 继续清理，不能只依赖已不存在的关系对象。

业务定义是期望状态，设备快照是观察状态，允许因部分同步而不同；导入校验检查身份、slot 唯一性、范围和容量，不要求每个已预留 binding 都已有匹配的设备 ACK，否则会拦住正常待同步和失败重试数据。

### 6.3 导入、上传和回读的一致性

当前 `ImportData.swift` 1965–1968 若 Schedule 数组任意项解码失败，会保留初始化的空数组；2529–2535 仍删除旧数据并保存新数组。新增字段时若沿用该行为，旧数据兼容失败可能表现成整个 Timed 被清空。这是本需求必须一起修正的关联问题。

采用“完整解析 → 版本规范化 → 引用/身份/容量验证 → 事务应用 → 本地读回”流程。任何阶段失败保留旧业务数据与映射。合法空数组正常导入；损坏数组不能当作合法清空。编码失败也必须终止上传，不能用默认空数组覆盖云端。

复用现有 SpaceConfigurationSafety 提交、dirty、baseline、重试与回读机制，但补充完整 Timed canonical 数据：业务定义、Devices/Groups/Scene 目标、绑定与待清理状态。现有 `scheduleTargetsData` 只比较 id/selectTarget/sceneAddress，不能证明时间、动作和新增映射保真。

该 canonical 数据需进入本地持久 baseline、待提交 receipt、云回读比较及是否需要导入的判断；旧 receipt 缺此字段按明确兼容规则处理。禁止对节点/数组排序变化重新分配 slot，不能在导入时随机生成新映射。

Space 单独同步、Site 批量同步、新增 Space、分享/备份及恢复共用相同序列化和校验。并发编辑需要服务器配置 revision 的条件更新或等价事务保护，作为后端团队配套要求记录，不在本次修改服务器。客户端“先 GET 再全量 POST”不能独自防止两个写入者同时分配/覆盖配置。

### 6.4 后端支持与旧客户端门禁

本节是提交给后端团队的配套要求，不是本任务的代码修改范围。责任方：后端团队；验收：旧端请求被拒绝、旧格式不得覆盖 v2、并发旧 revision 写入被拒绝、合法新格式完整读回；发布依赖：混合版本配置客户端环境启用新格式前完成配套并联调。固件不需要已知修改；若发现新的固件契约缺口，也只记录并交对应团队处理。

本地后端 `sitespace/models.py` 将 schedules/space_data 保存为 TextField；`services_4_space.py` 299–332 对整个数组/字典执行 JSON 序列化；`snippet.py` 324–345 读回。未见 Space 定时 16 条截断，也未按业务 id 拆分数据库行。因此可复用现有列，原则上不需为每条定时新建服务端表。

但是：

- Node 数据是白名单映射，新字段不能随意放在 Node 顶层；旧客户端缺 `custProps` 的全量上传会以 `{}` 覆盖原快照。
- 旧 App 的 Schedule Codable 同样是白名单，会丢弃新增映射；对 id 大于 15 仍可能直接当设备 index 使用。
- 本地已核对的 Site/Space 读写入口没有 Timed schema/client capability 门禁；新增 schema 字段不会使已经发布的旧 App 自动只读。

后端应在业务修改前校验客户端能力、Space 已存 schema 和提交 revision，覆盖 Site/Space 全量写入及能改节点配置的入口，拒绝旧格式覆盖已升级 Space。读取/分享入口不能把新版配置直接作为旧版可编辑快照下发；对旧端返回升级要求。新版 App 的文件导出已使用 `{format: "sunSmartSpace", formatVersion: 2, space: ...}` 封装；顶层不提供旧入口要求的 uuid/spaceName，旧入口将拒绝。新版文件导入接受此封装及合法 legacy 原始文件，拒绝无封装的 v2 文件、未知文件版本和损坏内容。云 API 仍使用未封装 Space payload；服务端门禁不能由文件封装替代。

后端门禁不能阻止已发布旧 App 使用离线缓存直接通过 BLE 改设备。上线约束应明确：**采用新格式的 Space 由已升级的配置客户端管理，停止用旧版离线配置它**。不在本次顺带设计固件鉴权或宣称服务器已解决此离线问题。

## 7. 必须改造的使用方

| 职责 | 文件/主要位置 | 必须保持的一致性 |
|---|---|---|
| 模型及持久化 | `Main/Timed/Model/Scheduler.swift`；`Common/Data/Database.swift`；`Common/Data/SpaceData.swift` | stable id、bindings、schema、待清理状态和 copy/编码完整 |
| 共享槽位规划 | 建议新增小型 `Main/Timed/Model/TimedSchedulerSlotPolicy.swift`，具体命名待实施 | 统一目标去重、容量预检、保留/释放规则；不另建同步框架 |
| UI与新增引导 | TimedViewController、ScheduleAddViewController、ScheduleDevices/Groups/ScenesView、SpaceNewCreationProcessController；MeshNetwork+SunSmart 的名称/ID 分配 | 移除 Space 16 的计数含义；保存/选择提示按具体设备；默认名称可超过 16 |
| 下发与差异 | `Common/Data/Node+MessageHandles.swift` 456–495；`MeshNetwork+SunSmart.swift` 1574–1755 | 全部从 node binding 获得 slot，包括 orphan 清理；不再凭业务 id 删除其他设备的同 slot |
| 回执与显示 | `MeshNetwork+SunSmart.swift` 3028–3051、3204–3268；`Main/Space/Model/SyncDevicesCellModel.swift` | 缓存投影、完成判定和 pending 清理统一逆映射；不只改发包 |
| 关系与恢复 | `Node+SyncData.swift`；GroupServer；SyncSceneScheduleTaskBuilder；SyncDeviceTaskBuilder；DeviceGroupDeferredSyncPlanner；设备恢复/永久删除；SpaceSyncCleanupCoordinator | 新增/退出组、Scene变化、恢复和延后重试均复核容量并保存旧清理映射 |
| 云与安全保护 | ExportData、ImportData、SpaceConfigurationIntegrityPolicy、SpaceConfigurationSafety、CloudSynchronizationManager | 全格式往返、完整 Timed canonical、导入失败保留、版本和并发保护 |
| 服务端配套（仅文档） | 后端团队的实际共享入口 | 旧端门禁、schema防降级、条件更新、读回保真；由后端团队实施和部署，App侧仅联调 |
| 国际化 | `SunSmart/en.lproj/Localizable.strings`、`zh-Hans.lproj/Localizable.strings`及品牌资源归属 | 新的设备容量/待清理提示国际化，取消“整个Space 16条”的错误表述 |

路径未写 `SunSmart/` 前缀的 App 文件均相对此目录。保留组/Scene 自身现有容量限制，不借本任务扩大其他对象上限；保留 owner、TimeSet、时区与 Scene Recall 语义。

## 8. 分阶段实施与验证计划

以下 App 实施安排已获用户确认，由主代理统一实施，数据结构、共享文件和云保护之间依赖紧密，不安排并行写同一工作树。每阶段先建立能复现相关失败的行为夹具，再做最小实现，不以源码文本匹配代替行为验证；不自动提交。后端/固件配套仅写文档，不创建其分支或工作树。

- [x] **阶段一：固定数据与兼容契约。** 定义 stable id、node binding、schema、待清理生命周期及服务端能力/revision契约；验证旧 0/1/16 条迁移不重排、v2 缺映射拒绝、身份冲突和合法空目标。后端版本保护是发布前置条件。
- [x] **阶段二：共享分配与持久化。** 在 SQLite 保存 bindings/schema并事务迁移，建立正反查；验证 Space 32 条分配到两台设备各16、同设备第17条拒绝、业务 id>255、重启映射不变、disabled和pending占用。
- [x] **阶段三：接通设备链路与拓扑入口。** 改造所有差异/下发/成功判定/回执归属，再覆盖组成员、Scene、恢复/延后同步；验证 owner切换部分失败、删除失败、取消后重试、迟到回执和节点地址复用。未知容量与分配错误必须有失败结果，不能空任务成功。
- [ ] **阶段四：App 云同步与导入闭环。** 完整 Codable和canonical、前置验证与失败回滚、Site/Space/分享往返；验证旧库升级→上传→另一客户端导入→重启后与设备相同slot对应。服务端门禁和条件更新仅形成配套文档；线上旧端请求保护由后端团队实施后联合验收。
- [x] **阶段五：UI接入与验收。** 调整计数/名称/新建引导/目标选择及中英文提示；设备满16时允许编辑既有定时和清理；稳定后运行相关回归并构建代表scheme，按跨品牌资源/配置风险决定其余品牌构建。最终真机和线上验收由用户完成，除非另行授权自动执行。

以上勾选表示 App 实现及当前可执行离线验证完成，不表示真实设备/服务器验收完成。阶段四的常规云同步、导入和文件往返已实现，显式旧备份覆盖已升级 Space 的恢复流程仍未实现，因此该阶段不整体勾选。

关键验收矩阵：

| 场景 | 预期 |
|---|---|
| 同 Space，A16条 + B16条，目标不重叠 | 保存32条，A/B各自slot0…15，互不覆盖 |
| 一条定时同时作用A/B，各自空槽不同 | 使用各自空槽，业务身份保持同一条 |
| 同设备16条，Devices/Groups/Scenes混合 | 第17条涉及该设备时拒绝；其他设备仍能新增 |
| 同一设备有直接、组、Scene等重复到达关系 | 同一业务定时去重；不同业务定时各计一次 |
| 停用、同步失败、删除失败、取消/重启 | binding持续有效；删除确认前不复用，重试不变slot |
| 空组已有超过16条定时，再加入设备 | 空组配置合法；加入时明确拒绝无法容纳的设备，不能默默只下发16条 |
| 已满设备编辑名称/时间/动作、移除目标/删除 | 不误触容量拦截，owner迁移不新增占用 |
| 自动组与Manual组切换；设备恢复/重配 | 保留owner语义，旧身份不误用；超容量可解释、可重试 |
| 旧数据0/1/16条，缺可选字段、合法空目标 | 正常导入并迁移；旧slot不重排 |
| 一条损坏记录、重复slot、错误身份、未知schema | 拒绝整个有问题的配置提交/导入，原数据不清空 |
| 新版>16条，含pending，通过Site/Space云往返 | logical id/每节点slot/目标/时间/动作/清理状态一致 |
| 云返回顺序改变、同时间戳映射改变、并发旧revision写入 | 排序不改变绑定；映射改变可识别；陈旧写入不覆盖 |
| 新版首次升级、旧端请求、旧备份显式恢复 | 发布前完成旧端门禁；旧备份覆盖已升级 Space 当前拒绝，向前恢复流程待实现 |

## 9. 实施验证与尚未验证项

### 已通过的离线验证

| 验证 | 覆盖范围与边界 |
|---|---|
| `check_timed_device_slots.py` | 生产分配策略与完整 payload：A16+B16、同设备第17条拒绝、逻辑 id>255、legacy 原槽、unknown/pending/disabled、冲突、32条 JSON 往返、排序、身份/版本校验及 v2 文件封装 |
| `check_timed_slot_persistence.py` | 抽取生产 SQLite 方法和实际运行时预留：旧表加列、17条以上、重启、损坏/DB不可用、事务失败、关系变更失败回滚、反查及旧身份/旧generation回执拒绝；SDK对象为边界替身 |
| `check_timed_delete_result.py` | 抽取生产删除批次：预留失败/空消息不能成功、ACK但状态未清除不能成功、确认清空后成功 |
| `check_schedule_scene_target_export.py` | 生产 Schedule Codable：非活动Space的存储Scene目标、数值legacy Scene、id300、slot与pending完整往返；损坏项拒绝整个数组 |
| `check_space_recovery_receipts.py` | 导入前置拒绝不改变原配置、schema降级拒绝、旧回执兼容、完整 Timed 回读、失败重试及既有权限/删除/成员恢复保护；传输与对象为边界替身 |
| `check_timed_scheduler_single_owner.sh` | owner策略与接线契约；源码匹配只作补充 |
| `check_timed_schedule_time_sync.sh`、`check_timed_scheduler_persistence.sh` | 既有TimeSet/设备Model缓存及读完成边界 |
| `check_scheduler_cloud_roundtrip.py` | 70节点/140个Model、物理slot与known empty/unknown的快照往返；不代表线上服务器保真 |
| `check_fresh_provisioning_scheduler_state.sh`、`check_fast_add_task_checkpoint_tracker.sh`、`check_fast_add_dual_scene_verification.sh` | 新入网known-empty、Fast Add任务检查点、拓扑空值策略、上下文与失败计划 |
| `check_timed_schedule_selection.py` | 生产选择入口：0/1/多选、离线保护、过滤后反选、确认/取消及过期界面回调 |
| `check_device_restore_transition_time.sh`、`check_device_restore_efc_support.sh` | 既有恢复目标/清理与能力边界，不替代新slot恢复真机验收 |
| `check_configuration_database_safety.sh` | 真实SQLite的WAL/checkpoint及事务失败回滚 |

两处原有测试入口已失效：picker观察方法已改名，Fast Add脚本仍匹配已迁走的Path/Zone循环。已更新夹具定位和共享拓扑策略检查，同时改为匹配新回执包装入口，重新运行均通过；未修改无关业务逻辑。

### 构建

本地 `SunSmartLocal.xcworkspace`，Debug、generic iOS、关闭签名、固定本工作树DerivedData：SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux均构建成功。新增Swift源文件和en/zh资源已核对五品牌归属。最后的共享事务、删除、文件封装修改由SunSmart最终增量构建验证；其他品牌此前构建用于资源/配置覆盖，不能表述为各品牌最后差异全部重建。构建存在项目原有弃用、重复资源/文件与捕获警告；未以clean或SDK改动绕过。

SDK实际来源仍为 `one-dev` 的 `2598bd1`，没有新增SDK API、未提交SDK差异或远端发布要求。固件、后端代码与运行配置均未修改。

### 未完成项与人工验收

1. **发布前置**：第6.4节服务端schema/旧端能力门禁、条件更新以及线上字段完整读回。由后端团队实施；本次只交付契约，不宣称已部署。没有虚构能力查询接口，当前App实现应在这些发布条件满足后投放。
2. **App后续功能**：向已经迁移的Space恢复旧备份，当前明确拒绝；正常旧数据首次导入/升级与新格式往返不受此限制。需要独立恢复事务才能启用，原计划此子项未完成。
3. **真机与体验**：保留旧安装数据升级；A先16条，Space第17条选择B成功、选择A拒绝，最终A/B各16条；混合Devices/Groups/Scenes和停用；断连造成删除失败后重启重试；组/Scene变化失败不误释放；Classic/Professional/Fast Add与设备恢复；各Scheduler Model owner切换和真实迟到包/取消；上传后另一新版客户端导入并按相同slot实际执行。新设备能力需读取Composition后确认，无法承载组定时会保留已入网节点并让组配置失败，不回滚配网；无Scheduler设备不因此被拦截。
4. **范围边界**：没有自动真机安装/运行、Simulator或线上请求。离线夹具、ACK和构建分别说明，不作为真实Mesh/服务器验收。

## 10. 已确认的实施边界与执行记录

已确认：旧版App可以要求升级后再编辑新格式Space。

已确认的设计整体：保持停用占槽、待清理不释放、空目标允许保存；保留Int业务ID并增加每节点slot映射；新格式发布前的云端保护由后端团队配套。Space不再设置固定16上限，但不承诺无限规模性能；后续以真实业务规模验收，不为本需求另加任意列表上限。

实施范围仅包含 App 持久化、同步、云兼容及 UI。永远不修改固件或服务器代码、运行配置，不执行其部署，不为其修改创建工作树；外部需求只记录到本文。当前SDK无需新API；若实施中出现必须修改App侧SDK的证据，再明确revision和正式release依赖待办。线上部署版本、其他配置客户端配套及真实固件行为仍需发布联调确认，不能用本地源码或隔离测试代替。

- 2026-10-08：用户确认推荐方案和五阶段实施，随后明确永久仅 App 开发规则；已写入本工作树 `AGENTS.md`。中断的后端工作树创建命令未生效，后端仍只有原 main/dev 工作树且源码干净。
- 执行裁定：复用本文件记录阶段进展，不额外创建重复计划；现有 App 工作树已隔离。后端修改任务全部替换为接口/验收文档，App 实现与离线验证继续。

### App 实施结果（2026-10-08）

- 业务`Schedule.id`与每节点物理slot拆分，Space不再固定16条；单设备0…15跨全部Scheduler Models共同占用，停用/待清理继续预留。新建/编辑/拓扑变化、永久删除/设备恢复、下发/回执/差异及云端数据均接入。
- SQLite采用可空列兼容legacy；首次预留保持旧id→slot，业务id可超过255；槽位与组/Scene变更在同一savepoint中持久化，失败同时恢复内存和数据库。完整Timed canonical进入receipt与baseline，编码/解码失败不再用空数组覆盖。
- 审查的四项问题均修复并补失败证据：删除预留失败空任务误报成功、关系提交失败残留预留、待删除Scene再次成为目标、未知Composition时误拦无Scheduler设备。删除还要求实际Model确认清空；保存删除意图失败恢复原业务对象。
- 文件导出v2增加版本封装，新版可读旧文件与新文件；云API仍为原Space结构。已迁移Space拒绝legacy覆盖，显式向前恢复为尚未实现项，见第9节。
- 两个旧脚本的失效源码定位已修正并重新通过。审查只进行一轮独立审查，修复后执行对应行为回归；没有以多轮审查替代实现。
- 用户永久App-only规则已写入`AGENTS.md`。所有改动留在当前App工作树，未commit、push、merge或清理工作树；SDK/固件/服务器未修改。

### 本轮三项 review 修复（2026-10-08）

基于 `feat/timed-limited-261008` / `adb6a862`，本轮开始时工作树干净；以下修改尚未提交。

- 整组删除和公共定时清理入口按节点持久化 `pendingRemoval`，保留其他节点、slot 和 generation。整组删除同时覆盖设备已知空槽、无需物理清理任务的情况；持久化失败停止该节点退出并报告失败。全部 Model 清空且队列空闲后，既有释放/预规划机制可回收槽位。
- 启用状态全失败时，将 `previousEnabled` 保存回操作开始时的 Mesh/子网，保留首次迁移产生的绑定。部分成功仍保留新值，重试沿用原槽位。
- 本地 v2 收到 v1 时，只有匹配已确认时间戳、完整 Timed 基线、配置与网络身份，以及已有 Model 基线的响应，才保留本地配置并允许继续进入；保留未确认上传回执。不匹配、初始化覆盖、待导入或权限变化要求重新导入时，继续拒绝降级。

验证：`check_timed_slot_persistence.py` 新增生产 Group 退出/开关方法与真实 SQLite 夹具，覆盖15条直接定时加1条组定时、另一节点绑定不变、只清空部分 Model、busy 后回收、空槽退出、SQL 写失败、开关双向全失败/部分成功及重试。`check_space_recovery_receipts.py` 新增未提交/已准备/已接受上传期间重复进入、同时间戳迁移、真正降级及权限变化拒绝。两个脚本与设备槽位/payload、删除结果、owner、TimeSet、Model持久化/读完成回归均通过；夹具中的 Mesh 对象和传输为替身，不等于真实设备或服务端验收。

最终共享 Swift 差异已通过 `SunSmartLocal.xcworkspace` / SunSmart / Debug / generic iOS 无签名增量构建，固定 DerivedData 为 `SunSmart-feat-timed-limited-261008`。SDK 仍为 `one-dev` / `2598bd1`，未修改；本轮没有资源、target 或依赖变化，未重复其他品牌构建。保留项目既有编译警告。

待人工验收：①设备15条直接定时加1条组定时，删除整组后新增直接定时成功；②旧格式首次切换开关时让设备全部失败，关闭失败页并重启，开关及导出仍为旧值；③首次迁移后让上传失败，退出重进 Space，保留本地新配置，恢复网络后可继续同步。本轮未操作真机或线上服务器。

### 旧安装及失败恢复 review 修复（2026-10-08）

基于 `feat/timed-limited-261008` / `650b4caa`，开始时工作树干净，本轮改动尚未提交。

- **旧安装基线**：独立检查旧恢复文件缺少 Timed 基线的情况，不再依赖已有的通用迁移标记。收到与已确认时间戳、原配置回执及网络身份一致的云数据时，先持久化缺失基线，再恢复本地清理或返回保留本地改动；没有可用旧回执时，仍经导出与云配置核对建立基线。公共预留事务在已上传的 v1 Space 缺少基线时拒绝迁移，写入失败可重试。保留原 v2 降级、权限和身份检查；未上传的新 Space 不要求云基线。
- **待退出成员**：拓扑预检排除残留订阅中的 `.exitFailure` 节点。Group Members 初始选择、重连和修复回调不再自动选回这些节点；用户明确重新选择时，经 `addingMembers` 恢复绑定并继续检查单设备容量。已清空且空闲的槽位可回收，未清空、未知或正在执行的槽位保留 `pendingRemoval`。
- **场景恢复**：场景的公共差异读取、状态显示、SAVE 与任务生成均纳入关联定时的缺失状态。重新选择原场景组，或未改参数再次 SAVE，都会进入同步并生成需要恢复的定时任务；沿用先 Scene、后 Schedule 的任务依赖。Scene-only 设备继续生成场景操作，不生成不适用的定时任务。

验证结果：以下 6 个入口均通过；`git diff --check` 通过。

| 回归入口 | 本轮覆盖 |
| --- | --- |
| `check_space_recovery_receipts.py` | 旧回执已有迁移标记但缺字段、同时间戳 GET、身份/配置不匹配、状态写失败重试、待上传清理的补基线顺序、迁移后重进及既有权限/上传回执保护 |
| `check_timed_slot_persistence.py` | 真实 SQLite 事务；15 条直接定时加 1 条组定时；无关组/场景编辑、已清空/未清空/未知/busy、显式重新加入和满槽拒绝；恢复相同 Scene 时的实际任务生成、重试及状态收敛 |
| `check_node_sync_status_refresh.py` | 共享 Group/Scene/Timed 读取、刷新、取消、页面重入与状态失效；补齐了旧夹具中缺失的接口字段/参数 |
| `check_timed_device_slots.py` | 业务 ID、设备物理槽位与完整 Timed payload 校验 |
| `check_timed_scheduler_single_owner.sh` | Scheduler owner 策略及入口契约 |
| `check_timed_schedule_time_sync.sh` | 每批设备 TimeSet 策略 |

最终生产代码已通过 `SunSmartLocal.xcworkspace` / SunSmart / Debug / generic iOS 无签名构建，固定 DerivedData 为 `SunSmart-feat-timed-limited-261008`。本地 SDK realpath 仍为 `nordic-sig-mesh-sdk-worktrees/one-dev`，revision `2598bd1`，SDK 工作树干净。改动为五品牌共享逻辑，无新增资源、编译条件、SDK API 或依赖变更，使用 SunSmart 代表构建。保留项目现有警告。

待人工验收（本轮未操作真机或云端）：

1. 保留旧安装的恢复文件升级，首次编辑后让上传失败，退出并重进 Space；应保留本地 v2 且正常进入，网络恢复后继续上传。
2. 设备有 15 条直接定时和 1 条组定时，退出组时让取消订阅失败但 Scheduler 清空成功；保存其他组/场景后新增直接定时应成功，明确重新加入原组时仍受 16 槽限制。
3. 移出场景组时让定时清理成功、SceneDelete 失败；重新选择原组并保持参数保存，应进入同步并恢复定时。中断后再次 SAVE 应继续同步，成功后不再显示待同步。
