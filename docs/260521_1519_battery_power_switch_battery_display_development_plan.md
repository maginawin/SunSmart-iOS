# Battery Power Switch Battery Display Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为真实 Battery Power Switch 增加本地电池电量展示、用户主动刷新、Battery Status 入库和删除清理能力。

**Architecture:** 复用现有 8-key Battery Power Switch 监控页和底部等待弹窗，把当前模拟电量替换为本地数据库数据。电池信息保存在现有 `PJEightKeySwitchRepository` 本地 SQLite 扩展表中，不进入 Site / Space 导出 JSON；刷新流程通过标准 `GenericBatteryGet` / `GenericBatteryStatus` 完成，并用 60 秒弹窗 flow 管理取消、重试和首个有效回复。

**Tech Stack:** Swift、UIKit、SnapKit、SQLite.swift、NordicSigMeshSDK、SIG Mesh Generic Battery Model、Xcode workspace `SunSmart.xcworkspace`。

---

## 当前实现分析

- `SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchMonitorHeaderView.swift`
  - 已有电池 icon、电量文本、Status、更新时间和刷新按钮布局。
  - 当前 icon 固定使用 `battery_ek`，符合需求。
  - 当前刷新按钮始终加入布局，缺少 visitor / 非真实设备隐藏逻辑。

- `SunSmart/Main/Device/Device1.5/NEightKeySwitches/ViewModel/PJEightKeySwitchMonitorViewModel.swift`
  - `headerState` 目前基于 `switchData.displayStatus` 返回模拟值，例如 `95%`、`10%`、`2min ago`、`7day ago`。
  - 当前还保留 `fault` 状态，不符合本期需求。
  - 当前没有读取本地数据库中的电池电量和 `battery_last_update_time`。

- `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift`
  - `refreshMonitor()` 目前通过 `nextRefreshSimulationWillSucceed` 和 `scheduleRefreshSimulation` 模拟成功 / timeout。
  - 已经有 `isRefreshing` 防重入，后续可以保留为刷新 flow 的入口保护。
  - 当 `viewModel.needsBatteryPowerSwitchSync` 为 true 时会先走配置同步，这个逻辑应保留，避免未完成 BPS 配置时直接读电池。

- `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchRefreshAlertController.swift`
  - 已有“等待信号 / timeout / retry”弹窗状态和 60 秒倒计时 UI。
  - 当前只负责 UI 倒计时，不发送真实 Mesh Battery Get。
  - 可在同文件内新增电池刷新 flow，复用该弹窗，避免新增 Xcode target 文件配置。

- `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchActivationAlertController.swift`
  - 已有 `PJEightKeySwitchActivationFlow`、3 秒轮询、60 秒 timeout、cancel、try again、generation 防旧回调的模式。
  - 电池刷新 flow 可以按同样状态机实现，但发送标准 `GenericBatteryGet`，不发送 vendor capability get。

- `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Repositories/PJEightKeySwitchRepository.swift`
  - 已有本地 SQLite 表 `pjEightKeySwitchs`，通过 `meshUUID + subNetworkKey + switchId` 唯一定位 Battery Power Switch 扩展数据。
  - 这是保存 `batteryLevel` 和 `batteryLastUpdateTime` 的最小改动位置。
  - `MeshNetworkManager.deleteSwitch(switchData:)` 已调用 `PJEightKeySwitchRepository.shared.delete(for:)`，若电池信息放在同一表，删除设备时会自然清理关联电池数据。

- `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift`
  - 当前承载 Battery Power Switch 的 panel、sync、配置 hash 等本地扩展状态。
  - 需要新增可选电池字段，并在 `copy()`、`convenience init(baseSwitchData:metadata:)` 中保留这些字段。

- `../../../nordic-sig-mesh-sdk`
  - 已存在 `GenericBatteryGet`、`GenericBatteryStatus` 和 `GenericBatteryClientDelegate`。
  - `Node.batteryModel` 可定位 Battery Power Switch 的 Generic Battery Server Model。
  - `MeshAPI.sendMessage(message:model:timeout:result:)` 可发送 acknowledged mesh message 并接收 `StaticMeshResponse`。

- `SunSmart/Common/Data/ExportData.swift` 和 `SunSmart/Common/Data/ImportData.swift`
  - 当前 Site / Space JSON 只导出 `DeviceSwitchData` 基础字段，不导出 `PJEightKeySwitchRepository` 扩展表。
  - 本需求明确电池数据不需要同步服务器，因此不应把电池字段加入这些 JSON。

当前工程没有现成 XCTest target；本计划不新增测试 target，避免扩大 target 配置影响面。验证以静态检查、直接 `xcodebuild` 编译和真实设备手工验收为主。

---

## File Structure

- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Repositories/PJEightKeySwitchRepository.swift`
  - 在 `pjEightKeySwitchs` 表中新增可选字段 `batteryLevel` 和 `batteryLastUpdateTime`。
  - 扩展 `Metadata`、`save(_:)`、`metadata(for:)`。
  - 新增保存有效电量、清理电量的 repository 方法。

- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift`
  - 新增 `batteryLevel: UInt8?` 和 `batteryLastUpdateTime: Int64?`。
  - 在 metadata 初始化和 copy 中保留电池字段。

- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/ViewModel/PJEightKeySwitchMonitorViewModel.swift`
  - 用本地电池字段生成 header 状态。
  - 实现电量分档、Low / Normal / Unknown 状态、更新时间文案。
  - 删除本期不需要的 Fault 状态展示路径。
  - 暴露刷新按钮可见性和保存有效 Battery Status 的入口。

- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchMonitorHeaderView.swift`
  - 按 view model 状态隐藏或显示刷新按钮。
  - 继续使用固定 `battery_ek` icon。

- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchRefreshAlertController.swift`
  - 保留现有 UI。
  - 增加 Battery Get 发送 flow 和可注入 reader。
  - 支持 cancel、timeout、retry、首个有效 Battery Status 完成本次刷新。

- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift`
  - 移除模拟刷新。
  - 接入真实 Battery refresh flow。
  - 刷新成功后更新本地数据库、刷新 UI；取消 / timeout / 无效回复不更新旧值。

- Modify: `SunSmart/en.lproj/Localizable.strings`
  - 增加真实更新时间所需文案：`Just now`、`%d min ago`、`%d hr ago`、`%d day ago`。

- Modify: `SunSmart/zh-Hans.lproj/Localizable.strings`
  - 增加真实更新时间所需文案：`刚刚`、`%d分钟前`、`%d小时前`、`%d天前`。

- Verify only: `SunSmart/Common/Data/ExportData.swift`
  - 确认不加入电池字段。

- Verify only: `SunSmart/Common/Data/ImportData.swift`
  - 确认不从服务器 JSON 读取电池字段。

---

### Task 1: 本地电池数据模型与 SQLite 存储

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Repositories/PJEightKeySwitchRepository.swift`
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift`

- [ ] **Step 1: 记录现有 repository 调用点**

Run:

```bash
rg -n "PJEightKeySwitchRepository|batteryLevel|batteryLast" SunSmart/Main/Device SunSmart/Common/Data -g '!user-temp/**'
```

Expected:

- `PJEightKeySwitchRepository` 调用集中在 BPS 创建、保存、删除和 view model 持久化路径。
- 现阶段没有 `batteryLevel` / `batteryLast`，说明新增字段不会与旧实现冲突。

- [ ] **Step 2: 扩展 `PJEightKeySwitchRepository.Metadata`**

在 `Metadata` 中增加：

- `batteryLevel: UInt8?`
- `batteryLastUpdateTime: Int64?`

初始化默认值均为 `nil`。含义如下：

- `batteryLevel == nil`：该 Battery Power Switch 尚未成功刷新过电池电量。
- `batteryLastUpdateTime == nil`：没有成功刷新时间。
- 只有收到合法 `GenericBatteryStatus` 并成功保存时，这两个字段才同时更新。

- [ ] **Step 3: 扩展 SQLite 表结构**

在 `PJEightKeySwitchRepository.ExpressionKey` 增加：

- `batteryLevel`，SQLite 类型使用可空 `Int`。
- `batteryLastUpdateTime`，SQLite 类型使用可空 `Int64`。

在 `initDatabase()` 的 create table 中增加这两列，并在 schema migration 中检查列是否存在，不存在则 `addColumn`。

Expected:

- 新安装用户直接创建包含两列的表。
- 老用户升级后自动补列。
- 补列默认值为 `nil`，不会把老数据误判为 `0%` 或“刚刚更新”。

- [ ] **Step 4: 扩展保存和加载**

修改 `save(_:)`：

- 将 `switchData.batteryLevel` 以 `Int?` 保存。
- 将 `switchData.batteryLastUpdateTime` 保存。

修改 `metadata(for:)`：

- 将可空 `batteryLevel` 转成 `UInt8?`。
- 将 `batteryLastUpdateTime` 原样返回。

Expected:

- 编辑 BPS profile、保存配置 hash 或刷新电池后，旧电池字段不会被无意清空。

- [ ] **Step 5: 增加电池保存 helper**

在 repository 中新增一个聚焦方法，用于刷新成功后只更新电池字段：

- 输入：`switchData`、合法电量 `UInt8`、更新时间 `Int64`，可选 `meshUUID` / `networkId`。
- 行为：更新 `batteryLevel` 和 `batteryLastUpdateTime`，同时同步写回传入的 `switchData` 实例。
- 返回：数据库写入是否成功。

该 helper 不修改 panel type、sync state、desired hash、applied hash 等配置字段。

- [ ] **Step 6: 扩展 `PJEightKeySwitchData`**

新增属性：

- `batteryLevel: UInt8?`
- `batteryLastUpdateTime: Int64?`

在以下路径同步赋值：

- `convenience init(baseSwitchData:metadata:)`
- `copy()`

Expected:

- 从数据库加载 BPS 后，view model 能直接读取电池字段。
- 编辑页面 copy / save 不会丢失已经刷新过的电池信息。

- [ ] **Step 7: 静态检查**

Run:

```bash
rg -n "batteryLevel|batteryLastUpdateTime" SunSmart/Main/Device/Device1.5/NEightKeySwitches -g '!user-temp/**'
```

Expected:

- 结果包含 repository 的 ExpressionKey、Metadata、save/load/helper。
- 结果包含 `PJEightKeySwitchData` 属性、init、copy。

---

### Task 2: Header 展示规则替换模拟数据

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/ViewModel/PJEightKeySwitchMonitorViewModel.swift`
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchMonitorHeaderView.swift`
- Modify: `SunSmart/en.lproj/Localizable.strings`
- Modify: `SunSmart/zh-Hans.lproj/Localizable.strings`

- [ ] **Step 1: 增加 HeaderState 字段**

在 `HeaderState` 中加入 `showsRefreshButton: Bool`。

状态枚举只保留本期需要的展示语义：

- `normal`
- `lowBattery`
- `unknown`

`fault` 不再用于本期 Battery Power Switch 电池展示。

- [ ] **Step 2: 实现刷新按钮可见性**

在 view model 中新增计算属性：

- `canRefreshBattery`

规则：

- `switchData.proxyNode?.isBatteryPowerSwitch == true`
- 当前 `space.permission != .visitor`
- 若未来虚拟设备没有 `proxyNode`，刷新按钮不展示。

在 header view `configure(state:)` 中用 `showsRefreshButton` 控制刷新按钮隐藏。

- [ ] **Step 3: 实现电池文本**

展示规则：

- `batteryLevel == nil`：显示 `--`。
- `0...14`：向下分档后为 `0 / 5 / 10`，显示 `Low`。
- `15...100`：按 5% 向下取整后显示百分比，例如 `19` 显示 `15%`，`100` 显示 `100%`。
- 超过 7 天未刷新时，仍按最近一次有效电量展示，不改成 `--`。

非法数据规则：

- `GenericBatteryStatus.isBatteryLevelKnown == false` 不写入数据库。
- `batteryLevel > 100` 不写入数据库。
- 无效回复不覆盖旧电量。

- [ ] **Step 4: 实现状态优先级**

按以下顺序生成状态：

1. 没有 `batteryLastUpdateTime`：`Unknown`
2. `now - batteryLastUpdateTime > 7 days`：`Unknown`
3. 分档后的电量小于等于 `10%`：`Low battery`
4. 其他：`Normal`

颜色规则：

- `Normal`：继续使用现有绿色 `RGB(69, 197, 122)`。
- `Unknown`：使用与 `Normal` 相同的绿色。
- `Low battery`：继续使用现有橙色 `RGB(240, 162, 55)`。

- [ ] **Step 5: 实现更新时间文本**

更新时间使用 `batteryLastUpdateTime` 和手机当前时间计算：

- `nil`：`--`
- `delta < 60s`：`Just now`
- `delta < 1hr`：`X min ago`
- `delta < 24hr`：`X hr ago`
- `delta >= 24hr`：`X day ago`

若手机时间被调到刷新时间之前，`delta` 按 `0` 处理，展示 `Just now`。

- [ ] **Step 6: 补充本地化**

英文新增：

- `neightkeyswitches_updated_just_now` = `Just now`
- `neightkeyswitches_updated_min_ago_format` = `%d min ago`
- `neightkeyswitches_updated_hr_ago_format` = `%d hr ago`
- `neightkeyswitches_updated_day_ago_format` = `%d day ago`

中文新增：

- `neightkeyswitches_updated_just_now` = `刚刚`
- `neightkeyswitches_updated_min_ago_format` = `%d分钟前`
- `neightkeyswitches_updated_hr_ago_format` = `%d小时前`
- `neightkeyswitches_updated_day_ago_format` = `%d天前`

- [ ] **Step 7: 静态检查模拟值已移除**

Run:

```bash
rg -n "95%|10%|neightkeyswitches_updated_2min|neightkeyswitches_updated_7day|neightkeyswitches_status_fault|case fault" SunSmart/Main/Device/Device1.5/NEightKeySwitches -g '!user-temp/**'
```

Expected:

- `PJEightKeySwitchMonitorViewModel.headerState` 不再使用这些模拟展示值。
- 本地化文件中旧 key 可以保留给历史 UI，但 BPS 电池 header 不再依赖它们。

---

### Task 3: 标准 SIG Mesh Battery Get 刷新流程

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchRefreshAlertController.swift`
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift`
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/ViewModel/PJEightKeySwitchMonitorViewModel.swift`

- [ ] **Step 1: 移除模拟刷新状态**

从 `PJEightKeySwitchMonitorVC` 移除：

- `nextRefreshSimulationWillSucceed`
- `scheduleRefreshSimulation(for:willSucceed:)`

保留：

- `isRefreshing`
- `viewModel.needsBatteryPowerSwitchSync` 前置检查

- [ ] **Step 2: 新增 Battery reader 协议**

在 `PJEightKeySwitchRefreshAlertController.swift` 中新增可注入 reader：

- `PJEightKeySwitchBatteryReading`
- 默认实现 `MeshBatteryPowerSwitchBatteryReader`

默认 reader 逻辑：

1. 取 `node.batteryModel`。
2. 发送 `GenericBatteryGet()` 到该 model。
3. 单次发送 timeout 使用小于 3 秒的值，避免下一轮发送前还有未结束监听。
4. 收到 `GenericBatteryStatus` 且 `isBatteryLevelKnown == true` 且 `batteryLevel <= 100` 时，返回有效电量。
5. 未响应、未知电量或非法电量返回无有效值。

- [ ] **Step 3: 新增 Battery refresh flow**

在同文件新增 `PJEightKeySwitchBatteryRefreshFlow`，复用现有弹窗。

状态：

- `idle`
- `waiting`
- `updated`
- `timeout`
- `cancelled`

Timer：

- countdown timer：每 1 秒更新弹窗剩余时间。
- probe timer：每 3 秒发送一次 `GenericBatteryGet`。
- 第一次进入 waiting 时立即发送一次。

并发保护：

- 每次开始 waiting 生成新的 `generation`。
- reader 回调必须同时满足：generation 一致、当前仍为 waiting、回复为有效电量。
- 首个有效回复完成本次刷新；后续回复不再触发 UI 或数据库更新。

- [ ] **Step 4: 定义刷新结果行为**

有效 Battery Status：

- 停止两个 timer。
- 用手机当前时间生成 `batteryLastUpdateTime`。
- 调用 view model 保存电量到 repository。
- 成功保存后更新 UI。
- 弹窗显示 `Updated just now`。
- 可保留现有成功状态，不需要前端定时刷新更新时间。

无效 Battery Status：

- 不保存电量。
- 不更新 `batteryLastUpdateTime`。
- 不完成本次刷新，继续等待下一次有效回复，直到 60 秒 timeout。

取消：

- 停止两个 timer。
- 取消当前 generation。
- 不保存电量。
- 不更新 UI。

Timeout：

- 停止两个 timer。
- 弹窗显示 timeout。
- 展示 retry。
- 不保存电量。
- 不更新 UI。

Retry：

- 重新生成 generation。
- 重置 60 秒倒计时。
- 立即发送一次 `GenericBatteryGet`。

- [ ] **Step 5: 接入 MonitorVC**

`refreshMonitor()` 行为调整为：

1. 若 `isRefreshing == true`，直接返回。
2. 若 `viewModel.needsBatteryPowerSwitchSync == true`，沿用现有配置同步流程。
3. 若 `viewModel.informationNode == nil`，提示失败并返回。
4. 创建 `PJEightKeySwitchBatteryRefreshFlow`。
5. flow 成功保存电池后调用 `updateUI()`。
6. flow 结束、取消或 timeout 后恢复 `isRefreshing = false`。

- [ ] **Step 6: 在 ViewModel 增加保存入口**

新增方法：

- 输入合法 `batteryLevel: UInt8` 和当前手机时间。
- 调用 repository 只保存电池字段。
- 成功后同步更新 `switchData.batteryLevel` 和 `switchData.batteryLastUpdateTime`。
- 失败时不更新内存 UI，避免显示未落库的数据。

- [ ] **Step 7: 静态检查刷新路径**

Run:

```bash
rg -n "nextRefreshSimulationWillSucceed|scheduleRefreshSimulation|GenericBatteryGet|GenericBatteryStatus|PJEightKeySwitchBatteryRefreshFlow|MeshBatteryPowerSwitchBatteryReader" SunSmart/Main/Device/Device1.5/NEightKeySwitches -g '!user-temp/**'
```

Expected:

- 模拟刷新字段和方法不存在。
- `GenericBatteryGet` / `GenericBatteryStatus` 只出现在真实刷新 reader / flow 中。

---

### Task 4: 删除清理与同步边界确认

**Files:**
- Verify / optionally modify: `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`
- Verify only: `SunSmart/Common/Data/ExportData.swift`
- Verify only: `SunSmart/Common/Data/ImportData.swift`

- [ ] **Step 1: 确认单个 BPS 删除清理**

检查 `MeshNetworkManager.deleteSwitch(switchData:)`。

Expected:

- 删除设备时调用 `PJEightKeySwitchRepository.shared.delete(for:meshUUID:networkId:)`。
- 因电池字段与 BPS metadata 放在同一行，删除 metadata 行时同时删除电池电量和更新时间。

- [ ] **Step 2: 确认 UI 删除入口都走统一删除路径**

Run:

```bash
rg -n "deleteSwitch\\(switchData:|deleteCache\\(switchData:|deleteSwitchAction" SunSmart/Main/Device -g '!user-temp/**'
```

Expected:

- BPS monitor 页和 switch 列表页最终都调用 `MeshNetworkManager.instance.deleteSwitch(switchData:)`。

- [ ] **Step 3: 确认不写入服务器 JSON**

Run:

```bash
rg -n "batteryLevel|batteryLastUpdateTime|battery_last_update_time|Battery Status|GenericBattery" SunSmart/Common/Data/ExportData.swift SunSmart/Common/Data/ImportData.swift SunSmart/Common/Cloud -g '!user-temp/**'
```

Expected:

- 没有命中电池电量字段。
- 如果命中，只允许是注释或无关内容；不允许把电池数据加入 export / import / cloud sync。

- [ ] **Step 4: 记录导入边界**

保持当前导入导出策略：

- 电池电量是本机本地缓存。
- 服务器 JSON 不携带电池字段。
- 重新添加同一个设备但生成新的 switch id 时，不会继承旧电池数据。
- 删除 switch 时立即删除本地电池数据，避免同一 switch id 继续显示脏数据。

---

### Task 5: 编译验证与验收

**Files:**
- All modified files above.

- [ ] **Step 1: 运行静态检查**

Run:

```bash
rg -n "last_sceen|last_seen_time|fault_last_update_time|threshold|nextRefreshSimulationWillSucceed|scheduleRefreshSimulation" SunSmart/Main/Device/Device1.5/NEightKeySwitches docs/260521_1125_battery_power_switch_battery_display_requirements.md -g '!user-temp/**'
```

Expected:

- 不出现本需求禁止的字段或模拟刷新实现。
- 文档内不保留未处理占位内容。

- [ ] **Step 2: 运行 iOS 编译**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected:

- BUILD SUCCEEDED。
- 不使用 `/bin/zsh -lc` 包裹命令。
- 不使用输出重定向。

- [ ] **Step 3: 手工验收首次进入页面**

前置条件：

- Battery Power Switch 已添加到当前 Site - Space。
- 本地数据库没有该 switch 的电池字段。

Expected:

- 电量显示 `--`。
- 状态显示 `Unknown`。
- 更新时间显示 `--`。
- Owner / editor 可见刷新按钮。
- Visitor 不显示刷新按钮。

- [ ] **Step 4: 手工验收刷新成功**

操作：

- 点击刷新按钮。
- 按设备任意按键激活设备。
- 设备在 60 秒内回复标准 `GenericBatteryStatus`。

Expected:

- App 每 3 秒发送一次 `GenericBatteryGet`，首次进入等待时立即发送一次。
- 收到第一条有效 Battery Status 后停止发送。
- 数据库保存电量和 `batteryLastUpdateTime`。
- UI 更新电量、Status 和更新时间。
- 更新时间显示 `Just now` / `刚刚`。

- [ ] **Step 5: 手工验收分档和状态**

用可控返回值或调试设备验证：

- `0% / 5% / 10% / 11% / 12% / 13% / 14%` 显示 `Low`，状态 `Low battery`。
- `15% / 20% / 25% ... 95% / 100%` 按 5% 档位显示。
- `batteryLastUpdateTime` 超过 7 天时，状态 `Unknown`，但电量仍展示最近一次成功同步值。
- `Unknown` 状态颜色与 `Normal` 相同。

- [ ] **Step 6: 手工验收失败和边界**

操作：

- 设备不激活，等待 60 秒。
- 在等待弹窗中取消。
- timeout 后点击 retry。
- 让设备返回 unknown battery 或非法电量。

Expected:

- 60 秒未回复时显示 timeout。
- timeout 后有 retry。
- 取消后停止发送 Battery Get。
- 取消、timeout、unknown、非法电量都不覆盖旧电量，不更新 `batteryLastUpdateTime`。

- [ ] **Step 7: 手工验收删除清理**

操作：

- 刷新成功一次，确认 UI 有电池值。
- 删除该 Battery Power Switch。
- 重新添加或进入列表确认旧数据不再显示。

Expected:

- 删除设备时同步删除 `pjEightKeySwitchs` 中对应行。
- 重新添加后的新 switch 没有旧电量，首次展示 `--` / `Unknown` / `--`。

---

## 风险与注意事项

- `GenericBatteryStatus` 的 `batteryLevel == 0xFF` 表示未知，不能保存为 `255%`。
- 如果设备返回 `11...14`，展示和状态都按向下分档后的 `10%` 处理。
- `Unknown` 是“电池数据过期或未刷新”，不是故障，也不是设备离线。
- 不要新增前端定时器刷新 header 更新时间；页面只在进入、用户刷新成功、现有 `updateUI()` 调用时重算展示。
- 不要修改 `ExportData.swift` / `ImportData.swift` 把电池数据带入服务器同步。
- 如果后续希望跨手机共享电池电量，需要重新评审服务器同步语义，本期不做。
