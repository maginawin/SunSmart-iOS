# Night Calibration 审查问题修复计划

## 1. 目标与结论

本次只修复审查指出的两个状态语义问题，不扩展 Night Calibration 功能，也不调整既有交互：

1. Night 校准完成后的 Group member 配置只有在全部成功时才恢复 Group Light LC Auto；任一节点失败或用户点击 STOP 时保持 Auto 关闭，失败节点继续处于待同步状态。
2. Profile 的持久化校准模式只有在当前 Group 仍能解析到有效、且校准数据完整的 daylight sensor 时才生效；否则 UI 和云端导出统一按 `none` 处理。

两个修复都可以在 App 当前工作树内完成，不需要修改 NordicSigMeshSDK。

## 2. 当前问题与源码依据

### 2.1 Night 配置失败后错误恢复 Auto

涉及文件：

- `SunSmart/Main/Group/Controller/LightSensorCalibrationViewController.swift`

Night 校准成功保存 sensor、Profile 和模式后，会调用现有 `configuring(lightNodes:completion:)`。该方法的 completion 语义已经明确：

- 没有待配置节点：返回 `true`；
- 所有待配置节点成功：返回 `true`；
- 任一节点失败：返回 `false`，并展示 RETRY/CANCEL；
- 用户点击 STOP：未完成节点被归入失败节点，最终返回 `false`；
- RETRY 继续复用原 completion，重试节点最终全部成功时返回 `true`。

当前 Night 调用方忽略 completion 参数，无论结果如何都会发送 Group `Light LC Auto = On`。同一控制器中的 Plane 路径已经使用 `guard success else { return }`，所以 Night 行为与既有正确路径不一致。

### 2.2 无效传感器仍采用持久化 Active 模式

涉及文件：

- `SunSmart/Main/Profile/Model/Profile.swift`
- 调用方：`LightSensorCalibrationViewController.swift`、`ExportData.swift`

`effectiveCalibrationMode(sensorCalibrated:)` 当前先返回非 nil 的持久化 `calibrationMode`，仅在旧数据缺失该字段时才检查 `sensorCalibrated`。因此，即使当前 sensor 已删除、已从 Group 解绑、地址无法解析，或校准数据已被 reset，持久化的 `nightCal` / `planeCal` 仍会被解释为 Active。

现有两个调用方已经传入同一有效性事实：当前 Group 能解析出的 `ambientLightSensorNode` 是否满足 `sensorCalibrated == true`。问题不在调用方，而在 `effectiveCalibrationMode` 的判断顺序。

## 3. 修复设计

### 3.1 P1：仅成功后恢复 Group Auto

在 Night 校准完成后的 `configuring` completion 中接收 `success`，并在调用 `restoreGroupAutoAfterDaylightCalibration()` 前增加成功门槛。

预期状态如下：

| Configuring 结果 | 恢复 Group Auto | 失败节点状态 | 后续操作 |
| --- | --- | --- | --- |
| 无待同步节点 | 是 | 无 | 流程完成 |
| 所有节点成功 | 是 | 无 | 流程完成 |
| 任一节点失败 | 否 | 保持 pending | RETRY 或 CANCEL |
| 用户点击 STOP | 否 | 未完成节点记为失败并保持 pending | RETRY 或 CANCEL |
| 失败后 RETRY 全部成功 | 是 | 清空本轮 pending | 流程完成 |
| 失败后 CANCEL | 否 | 保持 pending | 等待后续同步/重试 |

本次不修改 `configuring` 自身的回调、重试和 STOP 逻辑，也不增加回滚。原因是现有流程允许已成功节点保留结果，失败节点通过 `getNodeSyncProfiles()` 继续表达待同步；修复只需阻止配置未全部成功时重新开启自动控制。

### 3.2 P2：先验证传感器，再解释持久化模式

调整 `effectiveCalibrationMode(sensorCalibrated:)` 的判定顺序：

1. 非 daylight Profile 始终返回 `none`；
2. 当前 sensor 不存在或未完成有效校准时返回 `none`；
3. sensor 有效且已校准时，采用非 nil 的持久化模式；
4. sensor 有效且已校准、但旧数据缺少模式字段时，继续兼容为 `planeCal`。

完整预期矩阵：

| Profile 类型 | sensorCalibrated | 持久化模式 | effective 模式 |
| --- | --- | --- | --- |
| 非 daylight | 任意 | 任意 | `none` |
| daylight | false | `nightCal` / `sensorCal` / `planeCal` / `none` / nil | `none` |
| daylight | true | `nightCal` | `nightCal` |
| daylight | true | `sensorCal` | `sensorCal` |
| daylight | true | `planeCal` | `planeCal` |
| daylight | true | `none` | `none` |
| daylight | true | nil（旧数据） | `planeCal` |

该方案只修正“有效模式”的解释，不主动覆写数据库中的原始 `calibrationMode`。因此无需新增数据库迁移；UI 的 Active/完成状态、Night Apply 可用性以及云端导出都会通过现有调用方自动得到 `none`。如果未来同一 sensor 被合法恢复且校准数据重新有效，原始模式仍可按现有恢复语义使用。

## 4. 契约检查调整

### 4.1 Workflow 契约

修改 `Tests/Group/NightCalibrationWorkflowContractTests.swift`：

- 在 Night 校准结果保存到进入 `makeNightCalibrationSnapshot` 之前的限定源码片段中，断言 `configuring` completion 使用 `success`；
- 断言恢复 Auto 前存在失败返回门槛；
- 限定检查范围，避免同文件 Plane 路径已有的成功门槛让 Night 缺陷误通过。

### 4.2 Persistence 契约

修改 `Tests/Group/NightCalibrationPersistenceContractTests.swift`：

- 将“持久化模式始终权威”的旧断言改为“sensor 有效校准是持久化模式生效的前置条件”；
- 断言无效 sensor 返回 `none`；
- 继续保留旧数据 `nil + calibrated sensor -> planeCal` 的兼容断言；
- 尽量限定到 `effectiveCalibrationMode` 方法体，避免无关源码字符串造成误通过。

脚本入口保持不变：

- `scripts/check_night_calibration_workflow.sh`
- `scripts/check_night_calibration_persistence.sh`

## 5. 实施顺序

1. 先补强两组静态契约，使其能分别复现 P1 和 P2，并确认在当前代码上失败。
2. 修改 Night `configuring` completion，仅在 `success == true` 时恢复 Group Auto。
3. 修改 `effectiveCalibrationMode` 的判断顺序，保留 legacy Plane fallback。
4. 运行两组契约脚本，确认新契约通过。
5. 执行 `git diff --check`，确认无空白和补丁格式问题。
6. 串行执行 iphoneos、关闭签名的构建验证；至少验证 `SunSmart`，并因为两个修改点位于共享业务代码，再验证 `Archipelago`、`SLG Sync Plus`、`SylSmart` 相关 scheme。
7. 复核最终 diff，只包含两个业务文件及对应契约调整，不触碰当前工作树中的其他 Night Calibration 改动。

## 6. 验收清单

### 6.1 自动验证

- 当前缺陷版本下，新 P1/P2 契约能够失败；
- 修复后两组 Night Calibration 契约通过；
- `git diff --check` 通过；
- 四个品牌 scheme 按项目要求使用 iphoneos 串行构建通过，不使用 Simulator。

### 6.2 真机 / Mesh 回归

以下行为不能由静态契约和编译证明，需在设备环境验证：

- 全部灯具配置成功后只发送一次 Group Auto On；
- 单节点离线或命令失败时不发送 Group Auto On，完成页仍显示 pending 数量；
- 点击 STOP 后不恢复 Auto，未完成节点保持 pending；
- RETRY 最终全部成功后才恢复 Auto；
- CANCEL 后重新进入页面，pending 状态仍由节点实际同步差异得出；
- 删除当前 sensor、将其移出 Group、清空 calibration data 三种场景下，Active 显示 None，Night Apply 重新可用，导出值为 `none`；
- 旧数据库中 `calibrationMode == nil` 且 sensor 有效校准时仍显示 Plane Active。

建议抓取 Mesh 发送日志或包，确认失败/STOP 分支没有 `LightLCLightOnOffSetUnacknowledged(true)`，而成功/最终重试成功分支存在该消息。

## 7. 明确不在本次范围

- 不修改 NordicSigMeshSDK 的 Night 采样、曲线、ratio 或 rollback 实现；
- 不改变 Configuring 的部分成功、STOP、RETRY、CANCEL 交互；
- 不清理或迁移数据库中的历史 `calibrationMode` 原始值；
- 不修改 Group 删除、成员解绑、sensor reset 的现有数据清理流程；
- 不调整 UI、用户文案、本地化、资源或 target 配置；
- 不处理当前工作树中与这两条审查意见无关的改动。

