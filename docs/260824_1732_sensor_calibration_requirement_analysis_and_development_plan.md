# Sensor Calibration 需求分析与开发规划

## 1. 结论

本需求的核心目标合理，Figma 与现有 Night Calibration 也提供了足够的 UI 和流程复用基础。产品语义已确认，可以按本文方案进入开发。

已确认的关键规则：

1. Sensor `Target value` 独立使用 `0...2500 lx`，允许 `0 lx`；
2. 不修改既有 Profile 页面中 Occupancy level 的输入范围；该值通过设备 Lux 回写时可以超过原编辑上限；
3. `Use sensor reading` 优先使用 fresh 值，否则主动读取一次，无回包时静默；
4. Sensor `Dim level` 使用 `0...100%`、步进 1%、首次进入默认 50%；
5. Sensor 手动调光期间临时关闭 Group Auto，并覆盖退出、失败和切 mode 的恢复；
6. Apply 前记录 Dim level，校准成功和失败时都尽力恢复；
7. 纯 `Daylight harvesting` Profile 将 Target value 写入 `Task level`；
8. Sensor 保留 0%/100% 与拐点曲线采集，只删除 Night 的目标亮度取样和差值计算；
9. Night 的内部 ON Lux 必须严格大于 OFF Lux；Sensor 若 `OFF Lux > ON Lux`，则先将 ON Lux 修正为 OFF Lux，确保发送设备前 `ON Lux >= OFF Lux`；
10. Plane 按钮使用 `APPLY PLANE CAL.`，Sensor About 使用 `About Sensor Cal.`；
11. 本次不扩大到 Night 校准失败后的 Group 亮度恢复修复。

本次实现限定为 Calibration 页面、共享校准 UI、英文/简体中文本地化、Sensor 校准状态机、现有 Profile 写入和对应自动化验证。不改数据库结构，不改云端格式，不改既有 Profile/Occupancy level 编辑范围，也不扩大到其他 Group/Profile 页面。

## 2. 当前实现事实

### 2.1 App 当前状态

当前 `LightSensorCalibrationViewController` 已有三种模式入口，但业务上只有 Plane 与 Night 两条真实路径：

| 模式 | 当前 UI | 当前 Apply 行为 | 当前保存模式 |
| --- | --- | --- | --- |
| Night | `Target Night Brightness` 与 Night 完成态 | 调用 SDK `calibrateNight` | `.nightCal` |
| Sensor | 仍展示 Plane 的 ON/OFF 照度输入 | 调用 Plane `calibrate` | `.planeCal` |
| Plane | ON/OFF 照度输入 | 调用 Plane `calibrate` | `.planeCal` |

因此，Sensor 需求不能通过更换标题或输入框完成。若不增加独立分支，页面显示为 Sensor，但设备曲线倍率、Profile 模式和完成态仍会被记录成 Plane，语义错误。

当前已有可复用能力：

- 三模式 segmented control 与 `Active` 展示；
- About 内容按模式切换，并已具备英文、简体中文；
- daylight sensor 选择与 1 秒 Lux 轮询；
- Night 的校准前快照、失败回滚、传感器 publication 原子切换；
- Night 的 Profile 目标值写入、Group Configuring、失败设备 RETRY、成功后恢复 Auto；
- Night 完成态中的 Profile 更新提示、待同步设备数和 `Re-calibrate`；
- `effectiveCalibrationMode` 对无效/已删除/未校准 sensor 的 Active 状态保护。

### 2.2 SDK 当前状态

本工程已经引用本地 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk`，四个品牌 target 均引用同一 `NordicSigMeshSDK` product。

SDK 当前有两种内部校准模式：

- Plane：扫描灯光曲线，再根据外部照度计 ON/OFF 值计算 `sensorRatio` 与 `ambientLightRatio`；
- Night：扫描灯光曲线，以 0% 与目标亮度成对取样，计算灯具贡献的 Lux 差值，倍率固定为 100%。

Sensor 所需能力应成为第三个明确分支：

- 保留连接、备份、清空旧参数、临时 publication、稳定性检查、0%/100% 和拐点曲线、写入 `0x38`、恢复 publication/publish delta、失败回滚；
- 不执行 Night 的目标亮度取样；
- 不计算 `targetLux - offLux`；
- 与 Night 一样，将 sensor/ambient light ratio 写成 100%；
- 用户输入的 `Target value` 只由 App 直接写入 Profile，不作为 SDK 采样或计算参数。

这能满足“保存 sensor 坐标系中的目标值”，同时避免把 Sensor 伪装成 Plane 或 Night。

## 3. UI：Sensor Cal. 与 Night Cal. 的区别

### 3.1 共同区域

以下区域保持一致并复用现有实现：

- daylight sensor 选择卡；
- `Calibration mode` 与三段模式选择；
- 对应模式的 About 卡；
- 页面底部固定 Apply 区域；
- 校准完成后的 Profile 更新提示与 `Re-calibrate` 行。

Figma 根节点 `519:14750` 的 Sensor 页面中，About 卡标题仍写为 `About Night Cal.`，但正文和项目现有本地化都属于 Sensor。建议将该标题视为 Figma 遗漏，继续使用 `About Sensor Cal.`。

### 3.2 未校准状态

| 项目 | Night Cal. | Sensor Cal. |
| --- | --- | --- |
| 主卡标题 | `Target Night Brightness` | `Target Sensor Value` |
| 目标输入 | 亮度百分比滑条 | 可编辑 `Target value` Lux 输入框 |
| 快速取值 | 无 | `Use sensor reading` |
| Dim level | 只记录 Night 取样亮度，不控制 Group | 每次变化都直接控制 Group 亮度 |
| Apply 文案 | `APPLY NIGHT CAL.` | `APPLY SENSOR CAL.` |
| Apply 可用条件 | 已选 sensor，且不是完成态 | 已选 sensor，且 Target value 合法，且不是完成态 |

Sensor 卡按 Figma 节点 `519:14804` 实现：

- 标题 `Target Sensor Value`；
- 单行整数输入框，placeholder 为 `Target value`，单位为 `LX`；
- 右侧描边按钮 `Use sensor reading`；
- 下方说明文案；
- `Dim level` 左右标题和值；
- 减号、滑条、加号为同一行。

用户没有选中 sensor 时，点击 `Use sensor reading` 必须静默，不显示 Toast、Alert 或错误状态，也不修改输入值。

### 3.3 Dim level 共用样式与 Night Bug

Figma 节点 `519:14820` 使用圆形减号/加号按钮、细轨道和白色带阴影 thumb。当前 Night 使用系统 `UISlider` 和文本 `−`/`+`，视觉不一致。

建议抽出 Calibration 页面私有的共享 Dim Level 控件：

- Night 与 Sensor 使用完全相同的视觉布局和现有项目资源；
- 复用 `CustomDeviceSlider`、`scene_data_value_minus`、`scene_data_value_add` 和 `slider_point`；
- 不直接复用整个 `Manual Correction` ratio 控件，避免带入 ratio 范围、标题、恢复按钮和数据精度语义；
- Night 的 value callback 只更新本地取样值；
- Sensor 的 value callback 使用限流回调发送 Group Lightness，拖动结束必须发送最终值；
- 使用未确认的 Mesh 回包前，不把“命令已发送”当作所有灯具已经达到目标亮度。

这是聚焦的组件复用，不修改全局 slider 或其他页面。

### 3.4 已完成状态

Sensor 完成态复用现有 Night 完成组件的整体结构，但按 Figma 节点 `519:15493` 参数化展示：

| 项目 | Night Cal. | Sensor Cal. |
| --- | --- | --- |
| `Active` | `Night Cal.` | `Sensor Cal.` |
| Target value card | `Target level: N lx` + `(Set at N% brightness)` | 只显示 `Target level: N lx` |
| N 的来源 | Night 计算后的灯具贡献 Lux | 用户输入的 Target value |
| Profile 提示 | Occupancy/Vacant 或 Task 提示 | 同一类提示 |
| 待同步设备提示 | 保留 | 建议保留 |
| Re-calibrate | 保留 | 保留 |

Figma 对 `519:15498` 有明确注释：Sensor 不展示 `(Set at 50% brightness)`。当前 `LightSensorNightCalibrationCompleteView` 可改名为通用完成组件，并通过参数控制是否显示 brightness 行，避免复制整套完成 UI。

### 3.5 Plane 按钮文案

当前 Plane 底部仍使用通用 `CALIBRATION`。建议新增本地化 Key 并改为：

- English：`APPLY PLANE CAL.`
- 简体中文：`应用平面校准`

需求原文的 `APPLE PLANE CAL.` 需由产品确认是否为笔误。本文不建议把 `APPLE` 作为正式 UI 文案。

## 4. 功能：Sensor Cal. 与 Night Cal. 的流程区别

### 4.1 校准前交互

Night：

1. 用户选择 sensor；
2. 用户选择目标亮度百分比；
3. 改变滑条只更新取样参数，不控制 Group；
4. Apply 后才由 SDK 控灯并取样。

Sensor：

1. 用户选择 sensor；
2. 用户通过手动输入或 `Use sensor reading` 设置目标 Lux；
3. 用户拖动 `Dim level`，App 直接控制 Group，使 sensor 的实测 Lux 变化；
4. 用户在满意的环境和灯光状态下确定 Target value；
5. Apply 时将该值作为最终 Profile 目标，不再根据校准过程中的读数重新计算。

### 4.2 SDK 校准阶段

建议将“后续与 Night 相同”解释为保留 Night 的安全和曲线能力，但排除目标取样：

| 阶段 | Night Cal. | Sensor Cal. |
| --- | --- | --- |
| 连接选中 sensor | 保留 | 保留 |
| 备份旧曲线、倍率、publication | 保留 | 保留 |
| 清空旧校准参数、倍率归一 | 保留 | 保留 |
| 临时降低 publish delta、发布到 App | 保留 | 保留 |
| 环境稳定性检查 | 保留 | 保留 |
| 0% / 100% 与拐点曲线采集 | 保留 | 保留 |
| ON/OFF Lux 处理 | ON Lux 必须严格大于 OFF Lux，否则失败 | 若 OFF Lux 大于 ON Lux，则令 ON Lux 等于 OFF Lux；最终以 ON Lux 大于或等于 OFF Lux 的数据继续 |
| 目标亮度与 0% 成对取样 | 有 | 无 |
| 计算 `targetLux - offLux` | 有 | 无 |
| 写入 `0x38` 曲线 | 保留 | 保留 |
| 写入 `0x39` ratio | 100% / 100% | 100% / 100% |
| Profile 目标来源 | SDK 计算结果 | 用户 Target value 原值 |
| 失败恢复旧曲线和 publication | 保留 | 保留 |

Sensor 模式允许灯具对 sensor 的读数变化很小，因此不能沿用 Plane 或 Night 的 ON/OFF 严格正差值失败门槛。Night 必须明确验证原始采样值满足 `ON Lux > OFF Lux`；Sensor 的原始值若满足 `ON Lux >= OFF Lux` 则保持不变，若 `OFF Lux > ON Lux` 则将 ON Lux 修正为 OFF Lux。该情况不判定为校准失败。

Sensor 必须先完成上述 ON Lux 归一化，再形成并发送设备所需的 `0x38` 曲线数据。归一化后始终满足 `ON Lux >= OFF Lux`，因此对应 Lux 增量为非负数：原始 ON Lux 较大时保留实际差值，原始 OFF Lux 较大时修正后的差值为 0，不会产生 UInt16 下溢。

### 4.3 App 提交阶段

SDK 参数阶段成功后，Sensor 应复用 Night 的提交顺序：

1. 将选中 sensor 的 publication 指向 Group；
2. 必要时关闭旧 sensor 的 Group publication；
3. publication 失败时恢复新旧 sensor 原状态；
4. publication 成功后再更新 Group 的 sensor address；
5. 写入 Profile 目标 Lux；
6. 保存 `calibrationMode = .sensorCal`；
7. 更新 Group sync state；
8. 进入现有逐灯 `Configuring`；
9. 全部成功后恢复 Group Auto；
10. 部分失败或 STOP 时保留 pending 状态，通过现有 RETRY 继续；
11. 完成页显示 `Active: Sensor Cal.` 与用户目标值。

Sensor 不需要新增数据库字段。目标值已经由 Profile 的 Light Control Data 持久化，模式由现有 `calibrationMode` 表达。

### 4.4 Profile 字段映射

建议保持 Night 已有规则：

| Profile 类型 | Sensor Target value 写入字段 |
| --- | --- |
| `occupancy_daylight` | `occupancyLevel` |
| `vacancy_daylight` | `occupancyLevel` |
| `daylight` | `taskLevel` |

原因是纯 `daylight` 没有 Occupancy 阶段，运行时维持照度读取的是 `taskLevel`。若强制只写 `occupancyLevel`，纯 Daylight Group 完成后 UI 可显示 Sensor Active，但灯具运行时不会使用该目标值。

Vacant level 不自动改写，完成态继续提示用户检查 Vacant level；这与现有 Night 和 Figma 完成态一致。

## 5. 发现的流程风险

### 5.1 Sensor 手动调光可能被 Daylight Auto 覆盖

当前进入非 Plane 模式时，sensor 选择只是页面草稿；旧的 active sensor publication 和 Group Auto 仍可能继续工作。用户拖动 Sensor 的 Dim level 后，Light LC 可能根据旧 Lux publication 再次调整灯具，导致“滑条直接控制 Group”不稳定。

建议产品确认以下策略：

- 进入 Sensor 调光阶段时临时关闭 Group Auto；
- 切换到其他 mode、退出页面、取消或失败时恢复 Auto；
- 校准成功后继续遵循“Configuring 全成功才恢复 Auto”的现有规则；
- 恢复操作必须覆盖页面退出、sensor 切换、Apply 失败和 SDK 回滚路径。

若不允许本次调整 Auto，则需要真机证明 Group Lightness Set 在现有 Auto 状态下能稳定保持，否则需求无法完整实现。

### 5.2 SDK 扫描会改变用户选定的 Dim level

Sensor Apply 后仍需执行 0%/100% 和拐点扫描。流程结束时 Group 不一定停留在用户 Apply 前的 Dim level。Figma `519:14820` 的注释要求“校准完成后维持当前 Dim level”。

需要确认是否采用以下建议：

- Apply 前记录 Sensor Dim level；
- SDK 成功、publication 提交成功后恢复该 Dim level；
- SDK 失败、回滚失败、用户取消重试时也尽力恢复该 Dim level；
- Configuring 最终成功恢复 Auto 后，允许 Light LC 根据目标 Lux 再接管亮度。

这也暴露出现有 Night 的边界：Night 失败路径没有统一恢复进入校准前的 Group 亮度。本次是否顺带修复 Night 的失败亮度恢复，需要明确批准，不能默认为 Sensor 需求的一部分。

### 5.3 `Use sensor reading` 的“当前”定义

页面已有 1 秒 Sensor Get 轮询，但 `steadyDaylightLux` 可能只是过期缓存。建议行为为：

- 有选中 sensor 且读数仍为 fresh 时立即填入；
- 无 fresh 值时主动发起一次 Sensor Get；
- 只有同一 sensor 的新回包到达后才填入；
- sensor 已切换、无回包、离线或返回值非法时静默不更新；
- 无选中 sensor 时按需求静默不更新。

若产品希望“即使灰色过期值也可填入”，应明确接受 stale 数据风险。

### 5.4 Target value 独立范围

Sensor Target value 的确认范围是 `0...2500 lx`，与既有 Profile 页面 Occupancy level 的手动编辑范围相互独立。本次不修改原 Profile/Occupancy level 输入范围，因为 Occupancy level 通过设备 Lux 回写时已经可以超过原来的 1500 lx 编辑上限。

Sensor 页面按以下规则处理：

- 手动输入只接受 `0...2500` 的整数；
- `Use sensor reading` 只在读数位于 `0...2500 lx` 时写入；
- 超过 2500 lx 的读数不截断、不写入；
- 输入为空、格式非法或超出范围时，`APPLY SENSOR CAL.` 保持禁用；
- Profile 保存、完成态和 Group Configuring 使用最终合法的 Target value 原值。

## 6. 建议开发方案

### 6.1 UI 与组件

1. 在现有 Calibration mode 文件附近新增 Sensor Target 卡或拆分为独立文件；
2. 抽取共享 Dim Level 子控件，Night 与 Sensor 统一样式；
3. Sensor Target 卡负责整数输入、单位、说明、Use 按钮和 Dim level；
4. 将 Night 完成组件通用化，支持显示或隐藏 brightness 描述；
5. Controller 根据 mode 与 complete/draft 状态切换 Plane、Night、Sensor 内容；
6. 为 Sensor、Plane Apply 文案和 Sensor 表单新增英文、简体中文本地化；
7. 不新增 Figma 临时资源，优先复用四个 target 已包含的共享资产。

### 6.2 Controller 状态

新增或明确以下页面状态：

- Sensor target Lux 草稿；
- Sensor dim level 草稿；
- Sensor 是否处于 re-calibration draft；
- 当前 Lux freshness 与对应 sensor address；
- 如获批准，Sensor 调光期间 Auto 的临时挂起/恢复状态；
- Apply 前需要恢复的 Group dim level。

按钮可用性建议：

- Night：已选 sensor 且未处于完成态；
- Sensor：已选 sensor、Target value 合法且未处于完成态；
- Plane：已选 sensor、ON/OFF 均合法且 ON > OFF；
- firmware、Mesh 在线、Group 灯具在线继续在点击 Apply 时校验，不依赖可能过期的 UI enable 状态。

### 6.3 共享提交与回滚

当前 `NightCalibrationSnapshot` 和 `commitNightSensorSelection` 实际已适合 Night/Sensor 共用。建议做局部语义重命名，并由两种模式复用：

- 共享 calibration snapshot；
- 共享 sensor publication commit/rollback；
- 共享已校准 sensor 的 reset 标记清理；
- 共享 Group sync、Configuring、pending、RETRY 和 Auto 成功门槛；
- Night 只提交 SDK 计算 Lux；
- Sensor 只提交用户 Target value；
- 两者分别保存 `.nightCal` / `.sensorCal`。

该重命名仅限 Calibration 内部，不扩散到无关模块。

### 6.4 SDK

在本地 NordicSigMeshSDK 增加显式 `.sensor` 模式和公开 `calibrateSensor` 入口：

1. 沿用现有 `prepareCalibration` 和连接流程；
2. 沿用曲线扫描与 `0x38`；
3. Sensor 跳过 `collectNightCalibrationResult`；
4. Sensor 与 Night 共用 100%/100% ratio 写入逻辑；
5. Night 对内部采集值执行严格 `ON Lux > OFF Lux` 校验；
6. Sensor 若 `OFF Lux > ON Lux`，则将 ON Lux 修正为 OFF Lux，确保以 `ON Lux >= OFF Lux` 的数据形成并发送 `0x38`；
7. 沿用旧参数和 publication 回滚；
8. 保持 Plane 的行为不变；
9. 不新增 Auth、依赖或协议字段。

## 7. 自动化与构建验证

### 7.1 SDK 测试

- 扩展 `SensorCalibrateMathTests` 或增加聚焦测试，覆盖零 Lux 增量在 Sensor 曲线中的合法性；
- 证明 Sensor 分支不调用 Night 差值计算；
- 证明 Night 的 ON Lux 必须严格大于 OFF Lux；
- 证明 Sensor 在 ON Lux 等于 OFF Lux 时保持原值并继续；
- 证明 Sensor 在 OFF Lux 大于 ON Lux 时将 ON Lux 修正为 OFF Lux，并以修正后的非负差值形成 `0x38`；
- 证明 Night 原有目标差值、稳定性和其他失败条件不变；
- 运行本地 SDK `swift test`。

### 7.2 App 契约/回归

建议增加独立 Sensor workflow contract，覆盖：

- Sensor 不再展示 Plane ON/OFF 输入；
- `APPLY SENSOR CAL.` 与 Plane 文案；
- 英文、简体中文 Key 完整；
- Sensor Apply 走 `calibrateSensor`；
- Target value 原值写入 occupancy/task；
- Target value 只接受 `0...2500 lx`，不修改 Profile/Occupancy level 既有编辑范围；
- 保存 `.sensorCal`；
- 完成态不显示 `Set at brightness`；
- publication 失败执行回滚；
- Configuring 失败/STOP 不恢复 Auto，全成功或 RETRY 全成功才恢复；
- `Use sensor reading` 无 sensor 时静默；
- Night workflow contract 继续通过。

### 7.3 四品牌真机构建

按项目规则直接、串行运行 iphoneos unsigned build，不使用 shell 包装、不重定向日志、不使用 Simulator：

- `SunSmart`
- `Archipelago`
- `SLG Sync Plus`
- `SylSmart`

同时检查共享 Swift 文件、本地 SDK product、本地化和资源在四个 target 的 membership。

## 8. 真机验收矩阵

自动化和编译不能代替以下验收：

| 场景 | 验收点 |
| --- | --- |
| 无 selected sensor | Use 无提示、无改值；Apply 禁用 |
| selected sensor 无 Lux 回包 | Use 不写入 stale/非法值，行为符合最终确认规则 |
| fresh Lux | Use 正确填入同一 sensor 的 Lux |
| Sensor dim 拖动 | Group 实际亮度随动；Mesh 不被高频命令淹没；结束值必达 |
| Group Auto 开启 | 手动 dim 不被旧 publication 意外覆盖，或按批准策略临时挂起 |
| ON Lux > OFF Lux | Night 与 Sensor 均继续后续流程 |
| ON Lux == OFF Lux | Night 失败；Sensor 保持原值并继续，曲线差值为 0 |
| ON Lux < OFF Lux | Night 失败；Sensor 将 ON Lux 修正为 OFF Lux 后继续，曲线差值为 0 |
| Apply 成功 | 写入正确 sensor 的 0x38/0x39；Active 为 Sensor；Profile 值等于输入值 |
| occupancy/vacancy/daylight | 分别验证 occupancyLevel/occupancyLevel/taskLevel |
| publication 切换失败 | 新旧 sensor、模式、Profile 目标与 Auto 状态按快照恢复 |
| Configuring 部分失败 | Active 与 pending 语义正确；RETRY 后恢复 Auto |
| STOP/CANCEL | 不把部分配置误判为完整成功，不错误恢复 Auto |
| Re-calibrate 失败 | 原 Sensor Active 与旧校准参数可恢复 |
| 高 Lux/0 Lux/边界值 | 按最终范围规则接受或拒绝，无溢出和静默截断 |
| 页面退出/切换 mode | Group dim、Auto、sensor 草稿无泄漏 |
| 四品牌 | 英文/简体中文、资源、布局、按钮 disabled 视觉一致 |

还需通过 Mesh 抓包或 SDK 日志确认：Sensor 没有执行 Night 目标取样，`0x38`/`0x39` ACK 正确，selected sensor publication 指向 Group，组内灯具收到新的 Profile 属性。外部 Lux 表只用于行为对照，不参与 Sensor Target 的计算。

## 9. 已确认开发基线

本方案中的 UI、fresh Lux、Dim level、Group Auto、亮度恢复、纯 Daylight 字段映射、Sensor 曲线流程、Plane 文案和 Sensor About 均已确认。

本次补充确认：

- Sensor Target value 为 `0...2500 lx`；
- 不修改既有 Profile/Occupancy level 编辑范围；
- Night 要求内部 ON Lux 严格大于 OFF Lux；
- Sensor 原始 ON Lux 大于或等于 OFF Lux 时保持不变；
- Sensor 原始 OFF Lux 大于 ON Lux 时，将 ON Lux 修正为 OFF Lux；
- Sensor 最终只以满足 `ON Lux >= OFF Lux` 的数据形成并发送设备曲线，不因原始反向关系判定失败；
- 不顺带扩大到 Night 校准失败后的 Group 亮度恢复修复。
