# EFC Working Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 `CID 0x0A78 / PID 0x2131` EFC 设备实现新的 Working Mode 协议与 App 展示逻辑，用 `0x4D / 0x05` Working Mode 替换旧 Emergency Enabled，并保证本地配置、云同步、云分享、SAVE 同步任务、Edit 页面、真实设备页状态控件和 Mock 按钮一致。

**Architecture:** Working Mode 作为 EFC desired configuration 的一部分，保存在 `EmergencyFireControllerConfiguration.workingMode`。SDK 暴露 Working Mode GET/SET/STATUS；App 同步任务从旧 `.emergencyEnabled` 切换为 `.emergencyWorkingMode`。UI 根据当前配置过滤展示控件，但不删除隐藏配置，也不影响其他配置任务下发。

**Tech Stack:** Swift, UIKit, NordicSigMeshSDK Swift Package, SQLite.swift, CocoaPods, Xcode workspace `SunSmart.xcworkspace`。

---

## 执行说明

- 本项目按 AGENTS 偏好使用 Inline Execution；执行本计划时使用 `superpowers:executing-plans`，不默认启用 subagents。
- SDK 修改位于本地仓库 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk`。
- App 修改位于当前仓库 `/Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/emergency-fire`。
- 每个阶段完成后检查 diff，避免顺手格式化无关文件。
- App 用户可见文案必须同步 English 和简体中文。
- 不新增 Auth 信息。

## 参考设计

- `docs/260629_1734_efc_working_mode_design.md`

## Task 1: SDK 协议替换与单元测试

**目标：** 在 NordicSigMeshSDK 中把 `0x4D / 0x05` 从旧 `emergencyEnabled(Bool)` 替换为 Working Mode，并覆盖编码与解析。

**涉及文件：**

- `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorGet.swift`
- `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorSet.swift`
- `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift`
- `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/VendorServerDelegate.swift`
- `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/EmergencyFireVendorMessageTests.swift`

**Steps:**

- [ ] 先改测试，替换旧 `emergencyEnabled` 断言：
  - GET `.emergencyWorkingMode` 编码为 `Data([0x4D, 0x05])`。
  - SET `.disabled` 编码为 `4D 05 00`。
  - SET `.powerLossOnly` 编码为 `4D 05 01`。
  - SET `.fireAlarmOnly` 编码为 `4D 05 02`。
  - SET `.powerLossAndFireAlarm` 编码为 `4D 05 03`。
  - SET ACK `Data([0x4D, 0x05, 0x00])` 能解析成功。
  - GET response `Data([0x4D, 0x05, 0x00, 0x01])` 能解析出 `.powerLossOnly`。
  - Wrong params `Data([0x4D, 0x05, 0x04])` 能保留 ret/error 信息。
  - Invalid mode `Data([0x4D, 0x05, 0x00, 0x04])` 不应被当作合法 Working Mode。
- [ ] 在 SDK 新增公开枚举，例如 `EmergencyFireWorkingMode: UInt8, Codable, Equatable`：
  - `disabled = 0`
  - `powerLossOnly = 1`
  - `fireAlarmOnly = 2`
  - `powerLossAndFireAlarm = 3`
- [ ] 在 `SunricherVendorGet.Function` 中将旧 `case emergencyEnabled` 替换为 `case emergencyWorkingMode`，保持 opcode/subopcode 为 `4D 05`。
- [ ] 在 `SunricherVendorSet.Function` 中将旧 `case emergencyEnabled(Bool)` 替换为 `case emergencyWorkingMode(EmergencyFireWorkingMode)`，payload 追加 mode raw value。
- [ ] 在 `SunricherVendorStatus.ResponseCode` 中将旧 `.emergencyEnabled` 替换为 `.emergencyWorkingMode`，subopcode 仍为 `0x05`。
- [ ] 在 `FunctionParameters` 中新增 Working Mode 解析结果：
  - 成功 GET response 使用 `.emergencyWorkingMode(EmergencyFireWorkingMode)`。
  - 仅有 ret 的 SET response 使用明确 ACK 类型或现有 error/status 表达，不强行读取不存在的 mode。
- [ ] 更新 `VendorServerDelegate` 中对应 delegate 方法命名，移除旧 enabled 语义。
- [ ] 全仓搜索 SDK 内 `emergencyEnabled`，确认不再有 App/协议路径可调用旧语义。
- [ ] 在 SDK 仓库运行 focused test：

```sh
swift test --filter EmergencyFireVendorMessageTests
```

- [ ] 若 focused test 被既有 UIKit/test target 环境问题阻塞，记录具体错误，并在 App 侧最终用 iPhoneOS build 兜底验证编译。
- [ ] 在 SDK 仓库提交本阶段改动，建议 commit message：

```text
feat: add EFC working mode vendor protocol
```

## Task 2: App 配置模型与同步任务

**目标：** App 侧保存 Working Mode，默认 `.powerLossOnly`，SAVE 时只在 Working Mode 变化或首次/修复同步时下发 Working Mode task，并替换旧 Enable task。

**涉及文件：**

- `SunSmart/Main/Device/Device1.5/FireAlarm/Model/LinkedEmerFireConfig.swift`
- `SunSmart/Main/Device/Device1.5/FireAlarm/Model/DeviceEmerFireData+Sync.swift`
- `SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmergencyFireControllerSyncPlan.swift`
- `SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmergencyFireControllerSyncPlanner.swift`
- `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`
- `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmControllerSyncVC.swift`
- `SunSmart/Main/Device/Device1.5/FireAlarm/Repositories/DeviceEmerFireRepository.swift`
- `SunSmart/Main/Device/Device1.5/FireAlarm/Model/DeviceEmerFireData.swift`

**Steps:**

- [ ] 在 `EmergencyFireControllerConfiguration` 增加 `workingMode: EmergencyFireWorkingMode`。
- [ ] 将 `EmergencyFireControllerConfiguration.defaultValue` 设置为 `.powerLossOnly`。
- [ ] 删除或停用 `EmergencyFireControllerConfiguration.enabled`，避免 App 继续用旧 enabled 语义生成任务。
- [ ] 如果需要兼容本地未发布测试数据，给 `EmergencyFireControllerConfiguration` 增加自定义 `init(from:)`，缺少 `workingMode` 时落到 `.powerLossOnly`；不做线上旧数据迁移。
- [ ] 确认 `controllerSelfConfigurationEqual(to:)` 会比较 `workingMode`，让 Edit Save 能识别 mode 改动。
- [ ] 在 `DeviceEmerFireData.makeControllerSyncTasks(...)` 中替换旧 task：
  - task title 使用 `"efc_sync_working_mode".localizedString` 或复用 `"efc_emergency_mode".localizedString`。
  - task kind 从 `.enabled` 改为 `.workingMode`。
  - message 使用 `SunricherVendorSet(function: .emergencyWorkingMode(configuration.workingMode))`。
  - 条件为 `oldConfiguration == nil || oldConfiguration?.workingMode != configuration.workingMode`。
  - 保持 `changedOnly: onlyChangedKeyParameters`。
- [ ] 在 `EmergencyFireControllerSyncTask.Kind` 中将 `.enabled` 替换为 `.workingMode`，raw value 使用 `efc_sync_working_mode`。
- [ ] 更新 `SyncDevicesViewController.isEmergencyFireControllerSelfTaskKind(...)` 和 `EmerFireAlarmControllerSyncVC` 的 self sync kind 集合，使用 `.workingMode`。
- [ ] 审计 `EmergencyFireControllerSyncPlanner.makeDisableControllerItems()`：
  - 不允许继续调用旧 `.emergencyEnabled(false)`。
  - 若当前删除清理流程仍需要“删除时禁用真实控制器”的语义，则仅在删除流程显式调用 `.emergencyWorkingMode(.disabled)`。
  - 不在 Create/Edit UI 暴露 Disabled，也不在普通 SAVE 中因为 UI 切换到 Power Loss 或 Fire Alarm 而下发 Disabled。
- [ ] 确认 `DeviceEmerFireRepository` 的 `configurationData` JSON 能自动保存/读取 `workingMode`，不新增数据库列。
- [ ] 检查 `DeviceEmerFireData.clearMonitoringConfiguration()` 重置后仍得到默认 `.powerLossOnly`。
- [ ] 全仓搜索 App 内 `emergencyEnabled`、`efc_sync_enable`、`.enabled` EFC sync kind，确认旧 Enable 语义不再出现在业务路径。
- [ ] 在 App 仓库提交本阶段改动，建议 commit message：

```text
feat: sync EFC working mode configuration
```

## Task 3: Edit 与创建虚拟设备页 UI

**目标：** 在 `Associate With Group(s)` 下增加 `Emergency Mode` 独立行，允许选择三种 App 支持模式，并按模式过滤 `When The Emergency Event Occurs` 下的 UI。

**涉及文件：**

- `SunSmart/Main/Device/Device1.5/FireAlarm/Model/LinkedEmerFireEditRow.swift`
- `SunSmart/Main/Device/Device1.5/FireAlarm/Model/LinkedEmerFireEditState.swift`
- `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/LinkedEmerFireEditVC+Table.swift`
- `SunSmart/Main/Device/Device1.5/FireAlarm/ViewModels/LinkedEmerFireEditViewModel.swift`
- `SunSmart/en.lproj/Localizable.strings`
- `SunSmart/zh-Hans.lproj/Localizable.strings`

**Steps:**

- [ ] 在 `LinkedEmerFireEditRow` 增加 `.emergencyMode`。
- [ ] 调整 row/card grouping，让 `.emergencyMode` 位于 `.associatedGroups` 后面，视觉上是独立 section/row。
- [ ] 在 `LinkedEmerFireEditState` 增加 Working Mode 读写：
  - `apply(config:)` 读取 `config.workingMode`。
  - `makeConfig()` 写回 `workingMode`。
  - 增加 `workingModeText()` 用于 cell detail。
  - 增加 `selectableWorkingModes`，只返回 `.powerLossOnly`、`.fireAlarmOnly`、`.powerLossAndFireAlarm`。
- [ ] 在 `visibleRows` 中加入 `.emergencyMode`，并按 `state.workingMode` 过滤事件配置行：
  - `.powerLossOnly`：显示 Power Loss 相关行和公共行，隐藏 Fire Alarm 相关行。
  - `.fireAlarmOnly`：显示 Fire Alarm 相关行和公共行，隐藏 Power Loss 相关行。
  - `.powerLossAndFireAlarm` 和 `.disabled`：显示全部。
- [ ] 过滤只影响 `visibleRows`，不能清空 `powerLossSettings` 或 `fireAlarmSettings`。
- [ ] 为 `.emergencyMode` 复用 `EmerFireSelectionCell`，title 使用 `"efc_emergency_mode".localizedString`。
- [ ] 点击 `.emergencyMode` 时展示选项弹窗或现有项目选择控件：
  - `Power Loss Only`
  - `Fire Alarm Only`
  - `Power Loss & Fire Alarm`
  - 不展示 `Disabled`
- [ ] 用户选择后更新 `state.workingMode` 并 `tableView.reloadData()`，确保隐藏/展示行立即变化。
- [ ] 确认 `save` 仍使用 `state.makeConfig()`，被隐藏的配置仍保留并可参与同步任务。
- [ ] 新增本地化 key：
  - `efc_emergency_mode`
  - `efc_working_mode_power_loss_only`
  - `efc_working_mode_fire_alarm_only`
  - `efc_working_mode_power_loss_and_fire_alarm`
  - `efc_sync_working_mode`
- [ ] English 文案使用用户确认的英文：
  - `Emergency Mode`
  - `Power Loss Only`
  - `Fire Alarm Only`
  - `Power Loss & Fire Alarm`
- [ ] 简体中文翻译保持清晰：
  - `应急模式`
  - `仅断电`
  - `仅火警`
  - `断电和火警`
- [ ] 在 App 仓库提交本阶段改动，建议 commit message：

```text
feat: add EFC emergency mode editor
```

## Task 4: 真实设备页 Status & Settings 与 Mock 按钮

**目标：** 真实设备页底部弹窗从当前配置读取 Working Mode，过滤同一行状态控件和 Mock 按钮；展开配置摘要不受 Working Mode 影响。

**涉及文件：**

- `SunSmart/Main/Device/Device1.5/FireAlarm/ViewModels/EmerFireAlarmMonitorState.swift`
- `SunSmart/Main/Device/Device1.5/FireAlarm/ViewModels/EmerFireAlarmMonitorViewModel.swift`
- `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorVC.swift`
- `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorRendering.swift`
- `SunSmart/Main/Device/Device1.5/FireAlarm/views/EmerFireAlarmStatusSetView.swift`
- `SunSmart/Main/Device/Device1.5/FireAlarm/views/EmerFireAlarmMoniView.swift`

**Steps:**

- [ ] 在 monitor state/view model 增加 Working Mode 展示辅助：
  - `showsPowerLossControls`
  - `showsFireAlarmControls`
  - `.disabled` 按全部展示处理。
- [ ] 调整实时状态映射：
  - 不再因为旧 comprehensive status 的 `enabled == false` 显示 Disabled。
  - `fireActive` 或 `emergencyActive` 仍按真实状态显示。
  - 无活动状态时显示 normal。
- [ ] 保持 `statusItems(for:)` 展开配置摘要返回完整列表，不按 Working Mode 过滤。
- [ ] 在 `EmerFireAlarmStatusSetView` 增加 header controls 可见性配置，隐藏不相关的同一行状态控件：
  - `.powerLossOnly`：保留 Power Loss trigger/status。
  - `.fireAlarmOnly`：保留 Fire Alarm trigger/status。
  - `.powerLossAndFireAlarm` / `.disabled`：全部保留。
- [ ] 确认隐藏的 arranged subviews 能让剩余控件重新居中；如当前 stack view 不满足，补充明确的 stack distribution/alignment。
- [ ] 在 `EmerFireAlarmMonitorRendering.updateStatusSetView()` 或 `renderRealState(...)` 中，在更新 row status 后同步 header controls 可见性。
- [ ] 调整 `EmerFireAlarmMonitorVC.configureActions()` 按 mode 生成 action 数组：
  - Identify 始终保留。
  - `.powerLossOnly`：Identify + Power Loss mock + Restore mock。
  - `.fireAlarmOnly`：Identify + Fire Alarm mock + Restore mock。
  - `.powerLossAndFireAlarm` / `.disabled`：Identify + Fire Alarm mock + Power Loss mock + Restore mock。
- [ ] 确认 `EmerFireAlarmMoniView.configure(actions:)` 对 3 个 action 时隐藏多余按钮，并让剩余同一行按钮水平居中。
- [ ] 保持 `mockFireAlarmAction()`、`mockPowerLossAction()`、`mockRestoreAction()` 的权限、发送逻辑不因 mode 改变。
- [ ] 在 App 仓库提交本阶段改动，建议 commit message：

```text
feat: filter EFC monitor controls by mode
```

## Task 5: 云同步、云分享与导入检查

**目标：** 确认 Working Mode 进入云同步/云分享 payload，并且导入缺失字段时使用默认值，不破坏当前未发布测试数据。

**涉及文件：**

- `SunSmart/Main/Site/ExportData.swift`
- `SunSmart/Main/Site/ImportData.swift`
- `SunSmart/Main/Device/Device1.5/FireAlarm/Repositories/DeviceEmerFireRepository.swift`
- `SunSmart/Main/Device/Device1.5/FireAlarm/Model/LinkedEmerFireConfig.swift`

**Steps:**

- [ ] 确认 `ExportData.swift` 导出的 `emergencyFireControllers[].configuration` 自动包含 `workingMode`。
- [ ] 确认 `ImportData.swift` 解码 `EmergencyFireControllerConfiguration` 后能拿到 `workingMode`。
- [ ] 如果实现了自定义 `init(from:)`，添加缺省字段 fallback 测试或脚本检查，缺失 `workingMode` 时得到 `.powerLossOnly`。
- [ ] 确认 `isSynced`、`controllerSelfSyncPending`、association cleanup 字段语义不因 Working Mode 改动发生变化。
- [ ] 不新增独立云字段，不新增 sync hash。

## Task 6: Contract 脚本与静态检查

**目标：** 用现有轻量 contract 风格检查关键路径，防止旧 Enable 语义残留或 UI/localization 漏项。

**涉及文件：**

- `scripts/check_efc_controller_flows.sh`

**Steps:**

- [ ] 更新或新增 contract 检查：
  - `EmergencyFireControllerConfiguration` 包含 `workingMode`。
  - 默认值包含 `.powerLossOnly`。
  - `DeviceEmerFireData+Sync.swift` 使用 `.emergencyWorkingMode`。
  - App 业务同步路径不再调用 `.emergencyEnabled`。
  - `.workingMode` 属于 EFC controller self sync kind。
  - Edit rows 包含 `.emergencyMode`。
  - Monitor controls 根据 Working Mode 过滤。
  - English 和 zh-Hans localization 包含新增 key。
- [ ] 若删除流程保留 `.emergencyWorkingMode(.disabled)`，脚本允许该调用仅出现在 delete cleanup planner，不把它当作普通 SAVE/UI 路径。
- [ ] 运行 contract 脚本：

```sh
scripts/check_efc_controller_flows.sh
```

- [ ] 运行 diff 空白检查：

```sh
git diff --check
```

- [ ] 在 App 仓库提交本阶段改动，建议 commit message：

```text
test: cover EFC working mode contracts
```

## Task 7: 最终构建验证

**目标：** 用 iPhoneOS build 验证 App 与本地 SDK 改动能共同编译。

**Steps:**

- [ ] 确认 App 工程当前引用的是需要修改的本地 NordicSigMeshSDK，或按项目规则切换到本地路径引用。
- [ ] 运行 iPhoneOS build：

```sh
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

- [ ] 如果构建失败，先区分是本次 Working Mode 改动、SDK package 引用、还是既有工程问题。
- [ ] 构建通过后检查两个仓库状态：
  - 当前 App 仓库 `git status --short`
  - 本地 SDK 仓库 `git status --short`
- [ ] 汇总提交列表、验证命令和结果。

## 验收矩阵

| 场景 | 期望 |
| --- | --- |
| 新建 EFC 虚拟设备 | Emergency Mode 默认 `Power Loss Only` |
| Edit 选择 `Power Loss Only` | 隐藏 Fire Alarm Emergency 相关控件，Power Loss 和公共控件保留 |
| Edit 选择 `Fire Alarm Only` | 隐藏 Power Loss Emergency 相关控件，Fire Alarm 和公共控件保留 |
| Edit 选择 `Power Loss & Fire Alarm` | 展示全部事件控件 |
| SAVE mode 变化 | 生成 Working Mode self sync task |
| SAVE mode 未变化但其他隐藏配置变化 | 仍按配置差异生成对应任务，不被 mode 过滤 |
| 首次/修复同步 | 包含 Working Mode task，默认下发 `.powerLossOnly` |
| 同步失败 | `isSynced = false`，controller self pending 保留 |
| Status & Settings Power Loss Only | 同一行只展示 Power Loss 状态控件，展开摘要仍完整 |
| Status & Settings Fire Alarm Only | 同一行只展示 Fire Alarm 状态控件，展开摘要仍完整 |
| Status & Settings Power Loss & Fire Alarm | 同一行展示全部状态控件 |
| Mock Power Loss Only | 隐藏 Fire Alarm mock，Power Loss 和 Restore mock 居中 |
| Mock Fire Alarm Only | 隐藏 Power Loss mock，Fire Alarm 和 Restore mock 居中 |
| SDK SET wrong params ret=4 | 能解析/暴露错误，不误判成功 |

## 非目标

- 不在 App UI 展示 Disabled 选项。
- 不在入网后主动 GET Working Mode 作为默认值。
- 不因为 Working Mode 隐藏 UI 而跳过隐藏配置的同步任务。
- 不重构 EFC 无关模块。
- 不修改 Auth 相关信息。
