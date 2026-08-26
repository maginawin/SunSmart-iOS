# Daylight Group Profile Auto Min 兼容性修复实施总结

> 实施日期：2026-08-26  
> 工程范围：`ttl-test` worktree  
> 目标 Profile：`Occupancy sensing with daylight harvesting`、`Vacancy sensing with daylight harvesting`、`Daylight harvesting`

## 1. 实施结果

本次已按确认计划完成 App 侧修复：

- 三种 daylight Profile 从旧云数据导入时，若顶层或 scene 缺少 `autoMinLevel`，现在统一恢复为 `255`，与新建 Profile 的关闭默认一致。
- 显式合法值 `0...30` 保持原值，其中 `0` 仍表示已启用的 `0%`，不会与缺字段混淆。
- `255` 统一表示关闭；其它越界值在 daylight Profile 的云导入及数据库读取阶段规范为 `255`。
- 调整 High-end/Low-end trim 时，关闭值 `255` 不再参与亮度范围夹取，因此不会被改成 High-end。
- UI、模型和同步输入统一使用 `0...30` 有效范围判断是否启用，消除了“UI 启用、同步关闭”的分叉判断。
- 非-daylight Profile 的导入 fallback 和阶段亮度处理保持原行为。

## 2. 修改范围

### 模型语义

`SunSmart/Main/Profile/Model/Profile.swift`

- 在 `Profile.LightControlData` 集中定义 Auto min 的有效范围、关闭哨兵、规范化、启用判断和 trim 夹取规则。
- 新建 daylight Profile 默认值继续为 `255`。
- `LightData` 的 Auto min enabled 状态改为复用统一判断。

### 云导入兼容

`SunSmart/Common/Data/ImportData.swift`

- 先识别 Profile 类型，再解析 Auto min。
- daylight Profile 的顶层数据和 `scenes[]` 都使用相同规范化规则。
- 非-daylight Profile 保留原有顶层 `0` fallback，避免扩大改动。

### 本地数据库读取兼容

`SunSmart/Common/Data/Database.swift`

- daylight Profile 的顶层数据库列和 scene JSON 在读取时规范化。
- 不修改数据库 schema，不执行批量 migration；规范值会在用户后续正常保存时通过现有链路落库。

### High/Low-end trim 与 UI 状态

`SunSmart/Main/Profile/Controller/ProfileSettingsViewController.swift`

- 三种 daylight Profile 统一通过 `daylightType` 分支处理。
- 仅对有效且已启用的 Auto min 做范围夹取。
- `255` 和历史非法值保持或恢复为关闭状态。
- Auto min 编辑器的 enabled 状态改为使用模型统一判断。

### 自动化契约

- `Tests/Group/ProfileAutoMinCompatibilityContractTests.swift`
- `scripts/check_profile_auto_min_compatibility.sh`

新增契约覆盖模型语义、云导入、数据库读取、trim 更新、UI enabled 判断，并锁定现有 Auto min 到同步数据的映射不被改变。

## 3. 关键行为矩阵

| 场景 | 输入 | 修复后结果 |
| --- | ---: | ---: |
| daylight 云顶层或 scene 缺字段 | 无 | `255`，关闭 |
| daylight 云顶层或 scene 显式值 | `0...30` | 保留原值，启用 |
| daylight 云顶层或 scene 关闭值 | `255` | `255`，关闭 |
| daylight 云/数据库历史非法值 | `<0`、`31...254`、`>255` | `255`，关闭 |
| disabled 后调整 trim | `255` | 仍为 `255` |
| enabled 后提高 Low-end | `10`，新 Low 为 `20` | `20` |
| 历史污染值后调整 trim | `100` | `255`，不夹成 High-end |

## 4. 验证结果

### 自动化检查

- `zsh scripts/check_profile_auto_min_compatibility.sh`：通过。
- `zsh scripts/check_night_calibration_persistence.sh`：通过。
- `zsh scripts/check_night_calibration_workflow.sh`：通过。
- `git diff --check`：通过。

新增契约采用仓库现有的源码契约测试方式，验证代码结构和关键调用关系；它不等同于真实云 payload、数据库或设备端到端测试。

### 四品牌 generic iPhoneOS 构建

以下 scheme 均使用 `CODE_SIGNING_ALLOWED=NO` 构建成功：

- `SunSmart`
- `Archipelago`
- `SLG Sync Plus`
- `SylSmart`

构建日志仍包含工程既有的资源重名、废弃 API、未使用返回值及 AppIntents metadata 等 warning，本次没有修改这些无关问题。

## 5. 未完成的真实验收边界

以下项目尚未通过本次自动化与构建证明，需要手动或集成环境继续验收：

- 使用真实旧云 payload，分别验证三个 daylight Profile 的顶层缺字段和 scene 缺字段导入。
- 在实际 UI 中确认缺字段显示 `N/A`、显式 `0%` 显示为启用，以及调整 High/Low 后关闭状态不变化。
- 保存并重新进入 Space/Profile，确认云、本地数据库与 UI 状态一致。
- 触发真实 Mesh 同步，确认 disabled 仍按现有规则发送 0，并验证设备最终行为。

此外，旧版本已经把“缺字段”保存为本地 `0` 的记录，与用户显式配置的 `0%` 在数据层无法区分。本次不会猜测性地把既有合法 `0` 改成 `255`；重新从仍缺字段的旧云 payload 导入时会按新规则得到 `255`。

## 6. 明确未改动

- 未修改 `Node+SyncData` 的 Auto min 同步映射。
- 未修改 daylight calibration、ratio、inflection point、目标 Lux、SDK 或固件协议。
- 未修改本地化、资源、target 配置、依赖和数据库 schema。
- 未调整首次从 Off 打开 Auto min 时滑杆落到 `30%` 的现有行为。
- 未提交、推送或合并 Git 历史。
