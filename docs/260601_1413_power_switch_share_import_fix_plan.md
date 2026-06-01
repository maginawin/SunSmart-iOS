# Battery/AC Power Switch 分享与导入修复开发计划

## 背景

依据 `docs/260601_1357_power_switch_share_import_analysis.md`，当前分享/导入只处理 `DeviceSwitchData` 通用字段，没有导出和导入 `PJEightKeySwitchRepository` 中的八键 Power Switch 专属 metadata。导入前还会通过 `DeviceSwitchData.deleteSwitchs(...)` 删除当前子网下所有 switch 数据，并联动清空 `PJEightKeySwitchRepository` 专属表，导致 Battery Power Switch 与 AC Power Switch 导入后退化为普通动能开关路径。

本计划目标是让 Battery Power Switch 与 AC Power Switch 在分享、导入、云同步恢复中具备完整功能恢复能力，同时补齐已发现的权限绕过入口。

## 目标

- 新分享数据导入后，Battery Power Switch 与 AC Power Switch 能恢复为 `PJEightKeySwitchData`，并继续走八键 Power Switch UI、同步、监控、订阅、刷新与状态判断链路。
- 导出数据包含 Power Switch 专属 metadata：kind、八键面板类型、more settings、sync metadata、电池信息、Tx/LED applied state。
- 导入新数据时精确恢复上述 metadata，并同时保存通用 `DeviceSwitchData` 与 `PJEightKeySwitchRepository` 数据。
- 修复 Switch 列表长按八键 Power Switch 进入编辑器时的权限绕过，使 visitor、disabled editor、Mesh OTA distribution 等限制闭环。

## 非目标

- 不调整 `PJEightKeySwitchRepository` 的数据库表结构，当前表已经覆盖本次需要的字段。
- 不重构整体分享/导入框架，不改变现有 `switches` 通用字段含义。
- 不改变设备 PID 识别规则，只复用现有 `Node.isPowerSwitch`、`Node.powerSwitchKind`、`Node.batteryPowerSwitchPanelType`。
- 不新增 Auth 信息，不修改品牌资源、依赖或 target 配置。

## 方案决策

采用方案 A：在 `switches[]` 中增加嵌套 `powerSwitch` payload。

在现有每个 switch 字典中增加可选 `powerSwitch` 对象。通用字段保持不变，Power Switch metadata 跟随对应 switch 记录导出/导入。

优点：
- 数据归属清晰，metadata 与 switch id 天然绑定。
- 对现有通用 `switches` 字段兼容；普通 switch 不需要新增额外集合或关联逻辑。
- 改动集中在 `ExportData.swift`、`ImportData.swift` 和少量 helper。
- 不需要新增顶层集合的关联逻辑，导入删除再保存的顺序也简单。

缺点：
- `switches` 字典会变大，需要新增明确的序列化/解析 helper，避免 export/import 继续堆散落字段。

当前 App 仍处于测试阶段，不做历史分享数据兼容。只有包含 `powerSwitch` payload 的分享数据才恢复 Power Switch 专属 metadata。PID 仅用于校验 payload 与真实节点类型是否一致，不作为补偿创建 metadata 的依据。

## 数据契约设计

在 `switches[]` 的单项字典中新增可选字段 `powerSwitch`。建议 payload 版本为 `schemaVersion = 1`，包含：

- `powerSwitchKind`：`PJEightKeyPowerSwitchKind.rawValue`，battery 为 0，ac 为 1。
- `eightKeyPanelType`：稳定分享标识，建议使用 `scene8Key` / `brightness8Key` 字符串，或新增明确的 internal converter；不要依赖当前 repository 内部的私有 `PanelTypeStorage` 细节。
- `moreSettings.periodicReporting`：periodic reporting raw value。
- `moreSettings.ledIndicatorEnabled`：LED indicator 状态。
- `sync.syncState`、`sync.desiredConfigVersion`、`sync.desiredConfigHash`、`sync.appliedConfigHash`、`sync.lastSyncFailedReason`、`sync.lastSyncedAt`。
- `battery.level`、`battery.lastUpdateTime`。AC Power Switch 允许为空。
- `applied.txEnabled`、`applied.ledIndicatorEnabled`。

解析规则：

- 有 `powerSwitch` payload 且字段合法时，按 payload 精确恢复 metadata。
- `powerSwitchKind` 与 proxy node PID 推断结果不一致时，不导入该 Power Switch metadata，避免分享数据中的 kind 与真实节点类型冲突；通用 switch 记录仍按普通 switch 保存。
- `eightKeyPanelType` 缺失或非法时，不导入该 Power Switch metadata，避免静默降级为错误面板类型。
- `battery.level` 只接受 0...100，非法值按 nil 处理。
- enum raw value 非法时不导入该 Power Switch metadata；不让单个 switch 的 metadata 解析失败阻断整个 space 导入。
- 没有 `powerSwitch` payload 的 switch 不创建 `PJEightKeySwitchRepository` metadata。

## 开发阶段

### 1. 增加序列化边界 helper

目标文件：

- `SunSmart/Common/Data/ExportData.swift`
- `SunSmart/Common/Data/ImportData.swift`
- 如 helper 较多，可新增靠近 Power Switch model 的轻量结构，例如 `PJEightKeySwitchSharePayload`。

任务：

- 定义 Power Switch 分享 payload 的字段常量和解析/生成方法，避免在 export/import 中散落字符串。
- 复用 `PJEightKeySwitchRepository.metadata(for:meshUUID:networkId:)` 读取 metadata。
- 导出和导入解析 proxy node 时，优先使用当前正在处理的 `MeshNetwork` 按 `proxyNodeAddress` 查找节点，不依赖 `MeshNetworkManager.instance.meshNetwork` 的当前全局状态。
- 保持 payload 只处理 JSON 安全类型，不直接暴露数据库 row。

验收：

- 普通动能开关导出的 JSON 不新增 `powerSwitch`。
- Battery/AC Power Switch 导出的 JSON 包含完整 `powerSwitch` payload。
- 字段命名稳定，后续能基于 `schemaVersion` 演进。

### 2. 修复导出

目标文件：

- `SunSmart/Common/Data/ExportData.swift`

任务：

- 在 `SpaceData.export()` 构建 `switcheDicts` 时，对每个 `DeviceSwitchData` 尝试读取 Power Switch metadata。
- 如果 metadata 存在，导出 `powerSwitch` payload。
- 如果 metadata 不存在，不导出 `powerSwitch` payload；这类数据会在导入后按普通 switch 处理。
- 保持现有 `switches` 通用字段不变。

验收：

- Battery PID `0x2A01` / `0x2A02`、AC PID `0x2A11` / `0x2A12` 均能导出 kind 和 panel type。
- Battery 可导出 battery level 与 last update；AC 对应字段允许为空。
- `moreSettings`、`sync`、`applied` 字段能完整落入分享 JSON。

### 3. 修复导入

目标文件：

- `SunSmart/Common/Data/ImportData.swift`

任务：

- 解析 `switches[]` 时先构建通用 `DeviceSwitchData`。
- 根据 `powerSwitch` payload 构建 `PJEightKeySwitchRepository.Metadata`，并使用当前导入 `network` 中的 proxy node PID 做一致性校验。
- 对有 metadata 的 switch 创建 `PJEightKeySwitchData(baseSwitchData:metadata:)`，并保存通用 switch 表与专属 repository。
- 对没有有效 metadata 的 switch，仅保存通用 `DeviceSwitchData`，不写入 `PJEightKeySwitchRepository`。
- 注意导入前 `DeviceSwitchData.deleteSwitchs(...)` 会清空两个表；保存顺序应为先保存通用 switch，再保存 Power Switch repository。

验收：

- 新数据导入后，`DeviceSwitchData.batteryPowerSwitchData` 返回非 nil。
- 列表页 `PJEightKeySwitchRepository.makeEightKeySwitch(from:)` 能恢复八键 Power Switch 数据。
- Battery 与 AC 均不会退化到普通 EnOcean switch 订阅分支。
- 重复导入同一份 JSON 不产生重复记录，repository 仍按 switch id replace。

### 4. 修复权限绕过

目标文件：

- `SunSmart/Main/Device/Switches/Controller/DeviceSwitchesViewController.swift`
- `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift`

任务：

- Switch 列表长按八键 Power Switch 时，与普通 `DeviceSwitchViewController` 一样先判断 `space.deviceOperates.contains(.edit)`。
- 对无 edit 权限的用户，不进入可编辑的 `PJPreAddEightKeySwitchesVC`。可选择直接忽略长按，或进入只读监控页；推荐保持与普通 switch 编辑入口一致，禁止编辑入口。
- 在 `PJPreAddEightKeySwitchesVC` 内部补二次 guard：save、LINK、more settings、panel/group/scene 选择、delete callback 等修改入口应尊重 editable 状态，避免未来其它入口绕过列表判断。

验收：

- visitor 长按八键 Power Switch 不能保存、LINK 或删除。
- disabled editor 长按八键 Power Switch 不能保存、LINK 或删除。
- Mesh OTA distribution 中不能通过长按进入可写路径。
- owner/editor 正常保持原有编辑能力。

### 5. 同步链路回归检查

目标文件：

- `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`
- `SunSmart/Common/Data/Node+SyncData.swift`
- `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`

任务：

- 验证导入后 `batteryPowerSwitchData != nil` 的关键分支被命中。
- 验证 target group subscription 走 Power Switch 专属分支，而不是普通 EnOcean switch 分支。
- 验证 `needsBatteryPowerSwitchConfigurationSync`、Tx enable sync、LED indicator sync 的判断基于恢复后的 metadata。
- 验证 AC Power Switch 的 offline icon、heartbeat 刷新集合、Power Switch 监控页状态仍按 AC kind 工作。

验收：

- Battery/AC 导入后在设备列表、Power Switch 监控页、同步列表中类型与动作正确。
- syncState/hash/applied state 对同步任务的影响符合导入前状态。

## 验证矩阵

### 数据恢复

- Battery scene8Key：PID `0x2A01`，导出后导入，恢复 kind、panel type、groups、scenes、more settings、sync metadata、battery info。
- Battery brightness8Key：PID `0x2A02`，导出后导入，恢复 kind、panel type、groups、more settings、sync metadata、battery info。
- AC scene8Key：PID `0x2A11`，导出后导入，恢复 kind、panel type、groups、scenes、more settings、sync metadata。
- AC brightness8Key：PID `0x2A12`，导出后导入，恢复 kind、panel type、groups、more settings、sync metadata。
- 普通 EnOcean switch：导出/导入行为保持不变，不生成 Power Switch metadata。
- 异常 JSON：非法 enum、非法 panel type、kind 与 PID 冲突、缺失 `powerSwitch` 嵌套对象时不阻断整个 space 导入；对应 switch 只保存通用数据，不写入 Power Switch metadata。

### 权限

- owner：长按八键 Power Switch 可编辑、保存、LINK、删除。
- editor：启用状态下行为同 owner。
- visitor：不能通过长按进入可写编辑路径。
- disabled editor：不能通过长按进入可写编辑路径。
- Mesh OTA distribution：不能通过长按进入可写编辑路径。

### 构建

优先按项目规则使用直接 `xcodebuild`，不使用 shell 包装、重定向或 Simulator 校验：

- `SunSmart` scheme，Debug，iphoneos，`CODE_SIGNING_ALLOWED=NO`。
- 因改动位于共享 Common 与主业务代码，完成后再检查 `Archipelago`、`SylSmart`、`SLG Sync Plus` 等品牌 scheme 是否受编译影响。

## 风险与处理

- 风险：分享 payload 字段过多导致 export/import 中继续堆积字典逻辑。处理：用集中 helper 做字段生成和解析。
- 风险：PID 与 payload kind 冲突。处理：不写入 Power Switch metadata，避免错误恢复为错误类型；通用 switch 数据仍导入。
- 风险：权限只在入口判断，未来新增入口仍可能绕过。处理：列表入口与 `PJPreAddEightKeySwitchesVC` 内部修改动作都加 guard。
- 风险：项目缺少现成测试 target。处理：至少完成直接 `xcodebuild` 编译验证，并按验证矩阵做导出 JSON 与导入后 repository/UI 路径检查；若已有可用测试 target，再补充 focused tests。

## 实施顺序

1. 增加 Power Switch 分享 payload helper 与字段契约。
2. 修复 `SpaceData.export()` 的 Power Switch metadata 导出。
3. 修复 `SpaceData.update(spaceJsonData:)` 的 Power Switch metadata 导入与 PID 一致性校验。
4. 修复八键 Power Switch 长按编辑权限入口，并在编辑器内部补 guard。
5. 按验证矩阵做数据恢复、权限与同步链路回归。
6. 运行直接 `xcodebuild` 编译验证，优先 SunSmart，再检查共享代码影响到的品牌 scheme。

## 完成标准

- 新分享数据能完整恢复 Battery Power Switch 与 AC Power Switch 的八键 UI、more settings、sync metadata、电池/刷新状态、Tx/LED applied state。
- 普通 switch 分享/导入无回归。
- 权限绕过入口被封闭。
- SunSmart iphoneos Debug 构建通过；共享代码影响的品牌 scheme 完成必要编译检查。
