# Group Profile `Auto min.value` 属性分析

> 分析日期：2026-08-26  
> 工程范围：`ttl-test` worktree 当前 App 源码及其本地引用的 `NordicSigMeshSDK`  
> 验证方式：静态源码、数据模型、同步消息和持久化链路分析；未进行真机抓包、固件源码核对或闭环照度测试

## 1. 结论摘要

`Occupancy sensing with daylight harvesting` 中的 `Auto min.value` 是“日光采集自动调光时允许灯具维持的最低输出亮度百分比”。它不是目标照度，单位不是 lux，也不是占用传感器灵敏度。

当前 App 的实际实现是：当 daylight 已启用时，把同一个 Auto min 百分比分别写入灯具的 Light LC：

- `Light Control Lightness On`（Property `0x002E`）；
- `Light Control Lightness Prolong`（Property `0x002F`）；
- `Light Control Lightness Standby`（Property `0x0030`）。

因此它为占用、延长和待机三个 Light LC 阶段提供同一个自动调光亮度下限。当前实现没有发送独立的 Sunricher Vendor `lightAutoMinLevel` 属性；该旧分支已经注释。

新建 Group Profile 的默认状态是：

- UI：`N/A`，开关关闭；
- 模型值：`255`，作为 disabled 哨兵值；
- 同步语义：daylight 已启用时，把三个 Lightness 属性的目标写为 `0%`，也就是不额外设置 Auto min 下限；
- 新建 Group Profile 的 `Low-end trim` 仍单独默认为 `1%`，它约束灯具的非零输出范围，不能与 Auto min 混为同一个属性。

完全相同的 Auto min 属性还存在于：

- `Vacancy sensing with daylight harvesting`；
- `Daylight harvesting`。

其余五类当前 Group Profile 不包含这一属性。尤其 `Proximity/Predictive lighting with photocell` 虽然使用环境光传感器切换 Day/Night 条件，但它不是 daylight harvesting 闭环，模型和同步层均不包含 Auto min。

## 2. 属性定义与取值

### 2.1 模型定义

`Profile.LightControlData.autoMinLevel` 的源码注释定义为“环境光补偿最低亮度”：

- 有效配置范围：`0...30%`；
- `255`：未启用；
- `autoMinLevelEnabled`：当前直接通过 `autoMinLevel != 255` 判断。

对应 UI 文案进一步说明：即使环境光充足，也需要维持该最低亮度，且 Auto min 不得低于 `Low-end trim`。

源码依据：

- `SunSmart/Main/Profile/Model/Profile.swift:183-184`
- `SunSmart/Main/Profile/Model/Profile.swift:475-499`
- `SunSmart/en.lproj/Localizable.strings:395-417`
- `SunSmart/zh-Hans.lproj/Localizable.strings:397-419`

### 2.2 当前新建默认值

新建 Profile 的 General Scene 由 `LightControlData` 默认构造，`autoMinLevel` 默认为 `255`。Profile 图表只在值有效时显示百分比，否则显示 `N/A`。

需要区分三个概念：

| 概念 | 当前默认 | 含义 |
| --- | ---: | --- |
| Auto min UI | `N/A` / Off | 未启用最低亮度保护 |
| 模型持久化值 | `255` | disabled 哨兵值 |
| 关闭后的设备同步目标 | `0%` | 三个阶段的 Lightness 属性写为 0 |
| Low-end trim | `1%` | 灯具 Lightness Range 的最低非零输出限制 |

还有一个需要单独说明的 UI 行为：新建 Profile 的持久化默认仍是关闭/`255`，但首次打开编辑器后直接开启开关且不拖动滑杆，`255` 会被当前滑杆的 `0...30%` 范围夹到 `30%`。因此“默认状态”是 Off，而“首次直接开启后的初始值”按当前静态代码推导是 30%。这不是模型中另一个默认常量。

源码依据：

- `SunSmart/Main/Profile/Model/Profile.swift:388-429`
- `SunSmart/Main/Profile/Model/Profile.swift:475-499`
- `SunSmart/Main/Profile/View/ProfileSettingsSphasesView.swift:95-110`
- `SunSmart/Main/Profile/View/ProfileLevelSettingsView.swift:341-356`
- `SunSmart/Common/View/CustomDeviceSlider.swift:129-154`
- `SunSmart/Common/Data/Node+SyncData.swift:1342-1359`

### 2.3 编辑范围与约束

Auto min 编辑器的基本范围是 `0...30%`，Profile 页面再将可用范围限制在当前 `Low-end trim...High-end trim`。在正常默认配置下，有效最小值因此是 `1%`，最大值是 `30%`。

保存时：

- 开启：保存用户选择的百分比；
- 关闭：保存 `255`。

源码依据：

- `SunSmart/Main/Profile/View/ProfileLevelSettingsView.swift:598-616`
- `SunSmart/Main/Profile/View/ProfileLevelSettingsView.swift:630-649`
- `SunSmart/Main/Profile/Controller/ProfileSettingsViewController.swift:431-432`
- `SunSmart/Main/Profile/Controller/ProfileSettingsViewController.swift:1043-1049`

## 3. 实际影响的功能

### 3.1 已启用 daylight 闭环后的三个阶段

App 只有在 Group 的 ambient light sensor 已校准，或者节点存在可恢复的 daylight calibration 数据时，才将 `daylightEnabled` 视为 true。

此时 Auto min 会影响：

| Light LC 阶段 | App 同步项 | Light LC Property | 作用 |
| --- | --- | --- | --- |
| Occupancy / On | `occupancyLevel` | `0x002E Lightness On` | 日光闭环处于 On 阶段时的最低亮度目标 |
| Vacant / Prolong | `vacantLevel` | `0x002F Lightness Prolong` | 延长阶段的最低亮度目标 |
| Standby | `standbyLevel` | `0x0030 Lightness Standby` | 待机阶段的最低亮度目标 |

三者都使用同一个 Auto min 值。比如配置为 `10%`，App 会将 On、Prolong、Standby 三个 Lightness 属性都同步为 10% 对应的 16-bit Lightness；配置关闭时三者都同步为 0。

这些消息均为 acknowledged `LightLCPropertySet`，Access Opcode 为 `0x62`，发送到灯具的 Light LC Setup Model。

能力边界上，灯具至少需要 Light LC Model 和 Light LC Setup Model，当前同步函数才会生成这些属性消息；Vendor `lightAutoAdjustEnabled` 开关又只在存在 Sunricher Vendor Model 时发送。因此，对缺少对应模型的设备，App 中保存了 Auto min 并不等于设备端闭环一定生效。

源码依据：

- `SunSmart/Common/Data/Node+SyncData.swift:1238-1242`
- `SunSmart/Common/Data/Node+SyncData.swift:1290-1298`
- `SunSmart/Common/Data/Node+SyncData.swift:1342-1359`
- `SunSmart/Common/Data/Node+MessageHandles.swift:542-557`
- 本地 SDK `DeviceProperty.swift:268-273,452-457`
- 本地 SDK `LightLCPropertySet.swift:33-50`

### 3.2 与目标 Lux 的关系

Auto min 只提供百分比亮度边界；它不替代 daylight Profile 的目标照度：

- Occupancy target lux 仍写入 `0x002B Ambient LuxLevel On`；
- Vacant target lux 仍写入 `0x002C Ambient LuxLevel Prolong`；
- Standby target lux 仍写入 `0x002D Ambient LuxLevel Standby`；
- 纯 `Daylight harvesting` 的 Task level 写入 `Ambient LuxLevel On`。

可以把两组属性理解为：Lux 属性定义“希望环境达到多少照度”，Auto min 映射出的 Lightness 属性定义“即使自然光已经充足，灯具是否仍需保留最低输出”。

这项解释符合 App 文案和同步映射；固件内部 Light LC regulator 如何组合 Lux、Lightness Range、三个阶段 Lightness 与 Vendor 自动调光开关，当前 App/SDK 源码无法完全证明，仍需固件说明或真机抓包验证。

### 3.3 未校准或 daylight 未启用时

`Occupancy sensing with daylight harvesting` 和 `Vacancy sensing with daylight harvesting` 在 daylight 尚未启用时，不使用 Auto min 值，而是使用百分比 fallback：

- On：`High-end trim`；
- Prolong：`50%`；
- Standby：`0%`。

纯 `Daylight harvesting` 未启用 daylight 时，On 使用 `High-end trim` fallback。

因此，修改 Auto min 后如果 Group 尚未完成有效 daylight 校准，不能期待设备立即表现出 Auto min 的闭环效果。校准完成并重新同步后，App 才会把对应阶段 Lightness 改回 Auto min 或 0。

源码依据：

- `SunSmart/Common/Data/Node+SyncData.swift:1360-1382`

### 3.4 不会直接影响的功能

从当前源码看，Auto min 不直接修改：

- Occupancy/PIR 检测开关或灵敏度；
- Occupancy、Vacant、Standby 的目标 Lux；
- T1～T5 阶段时间；
- daylight calibration 的 `0x38` 拐点或 `0x39` ratio；
- Manual Override Timeout；
- Power-up state/CCT；
- Group membership、Subscription 或传感器 Publication。

它会参与 Profile 本地数据库保存、场景 JSON 编码、云导出/导入和设备同步比较，因此修改后可能触发该 Profile 的保存及灯具重新同步。

## 4. 其他 Group Profiles 是否有类似属性

当前 `ProfileType` 一共八类，模型分配结果如下：

| Group Profile | 是否有 Auto min | 当前作用 |
| --- | --- | --- |
| Occupancy sensing with daylight harvesting | 有 | On / Prolong / Standby 的 daylight 自动调光最低百分比 |
| Vacancy sensing with daylight harvesting | 有 | 与上面相同，差异主要在 Occupancy Mode，不在 Auto min |
| Occupancy sensing | 无 | 三阶段直接使用百分比亮度，不做 daylight harvesting |
| Vacancy sensing | 无 | 三阶段直接使用百分比亮度，不做 daylight harvesting |
| Daylight harvesting | 有 | 纯 daylight 闭环的最低百分比；同步层仍写三个 Lightness 属性，主要运行阶段是保持目标 Lux 的 On 阶段 |
| Manual control | 无 | 使用 Task level 作为手动 On 亮度 |
| Proximity/Predictive lighting | 无 | 使用占用阶段百分比和路径逻辑 |
| Proximity/Predictive lighting with photocell | 无 | 光传感器只用于 Day/Night 条件与场景切换，不属于 daylight harvesting 闭环 |

源码依据：

- `SunSmart/Main/Profile/Model/Profile.swift:237-250`
- `SunSmart/Main/Profile/Model/Profile.swift:271-284`
- `SunSmart/Main/Profile/Model/Profile.swift:535-604`
- `SunSmart/Main/Profile/Model/Profile.swift:566-573`
- `SunSmart/Main/Profile/View/ProfileSettingsSphasesView.swift:130-213`

### 4.1 最接近但不相同的属性：Low-end trim

所有 Group Profiles 都有 `Low-end trim`，它是最容易与 Auto min 混淆的属性，但两者作用层不同：

| 属性 | 适用范围 | 是否可关闭 | 当前消息/属性 | 含义 |
| --- | --- | --- | --- | --- |
| Auto min | 三种 daylight harvesting Profile | 可以，`255` 表示关闭 | LC Lightness On/Prolong/Standby | daylight 闭环仍需保留的最低亮度百分比 |
| Low-end trim | 全部八种 Profile | 不使用 `255` 开关 | Light Lightness Range Set | 设备允许的最低非零 Lightness 范围 |

产品文案要求 Auto min 不得低于 Low-end trim，UI 也用 Low-end trim 限制 Auto min 的可选下限。

## 5. 当前实现中的两个数据一致性风险

### 5.1 旧云数据缺少字段时默认成 0，而不是 255

新建 Profile 的模型默认值是 `255`，但 Group 云导入时，如果顶层 Profile JSON 缺少 `autoMinLevel`，当前代码使用 `0` 作为 fallback。由于 `0 != 255`，这会被部分 UI/模型判断为“已启用”，与新建 Profile 的默认关闭语义不一致。

场景 JSON 缺字段时则保留新建 `LightControlData` 的 `255`，所以顶层旧数据和 scene 旧数据还存在不同 fallback。

源码依据：

- `SunSmart/Main/Profile/Model/Profile.swift:475-499`
- `SunSmart/Common/Data/ImportData.swift:1663-1668`
- `SunSmart/Common/Data/ImportData.swift:1673-1689`

### 5.2 disabled 哨兵值与范围调整逻辑存在冲突

修改 High-end/Low-end trim 时，daylight Profile 会检查 `autoMinLevel` 是否在新范围内。当前逻辑没有先排除 disabled 哨兵值 `255`，因此关闭状态下的 `255` 也会被夹到亮度范围内，通常变成 High-end 值。

这会造成判断不一致：

- `LightControlData.autoMinLevelEnabled` 只判断是否不等于 `255`，可能把该值显示成启用；
- `LightData` 转换又只把 `<= 30` 视为有效 Auto min，因此 High-end 常见值 50～100 会被同步层视为 disabled，并写 0。

也就是说，调整亮度范围后可能出现“UI/模型看似启用，但设备同步仍按关闭处理”的状态。该问题不改变本次对属性本意和正常同步链路的结论，但在验证默认值、云恢复和 Need Sync 时应单独关注。

源码依据：

- `SunSmart/Main/Profile/Controller/ProfileSettingsViewController.swift:365-395`
- `SunSmart/Main/Profile/Model/Profile.swift:274-280`
- `SunSmart/Main/Profile/Model/Profile.swift:487-489`

## 6. 验证边界与建议测试

本次可以由源码确认：

- App 模型、UI 范围、默认哨兵值和 Profile 类型覆盖；
- App 在已校准/未校准条件下生成哪些同步项；
- App 将 Auto min 映射到哪三个 SIG Light LC Property；
- 本地持久化及云导入/导出包含该字段。

本次不能由源码确认：

- firmware 是否严格把三个 Lightness Property 解释为闭环最低输出；
- Auto min 为 0 时是否允许稳定关灯，还是会在 off/最低非零亮度之间抖动；
- Low-end trim、Auto min、Lux target 和 PI regulator 饱和时的最终优先级；
- 断电重启后固件是否持久保存并恢复这三个属性。

建议至少做以下真机矩阵：

1. 使用已校准的 `Occupancy sensing with daylight harvesting` Group。
2. 分别配置 Auto min 为 Off、1%、10%、30%。
3. 每组分别记录 Occupancy、Prolong、Standby 三阶段在低自然光和充足自然光下的实际输出。
4. 读取或抓包确认 `0x002E / 0x002F / 0x0030` 的写入值与 Status 回显。
5. 同时记录 Low-end trim 为 1% 和高于 Auto min 的边界行为。
6. 断电重启后重复测试，确认 NVM 和闭环恢复。

在完成这些测试前，结论应表述为“App 配置目标已确认”，不能直接宣称“真实灯具闭环行为已验收”。
