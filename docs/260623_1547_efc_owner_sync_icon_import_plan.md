# EFC Owner Sync Icon Import Analysis And Fix Plan

## 结论

Owner App 上 `EFC update` 显示需要同步图标，根因不是 Editor 端 Sync 成功后没有更新 Space 时间，也不是云端 payload 缺少 `isSynced`。给出的云端数据里 `isSynced` 已经是 `true`。

当前问题发生在 Owner App 导入云端 Space 时：`ImportData.swift` 对 `emergencyFireControllers` 的 `isSynced` 没有读取云端字段，而是用 `configuration.hasSyncIntent`、`bindNodeAddress`、`publishGroupAddress` 重新推导。你的数据包含关联 group `49161`，也有 `bindNodeAddress` 和 `publishGroupAddress`，因此导入后会被强制保存为 `isSynced = false`。随后 Others 页面读取 `DeviceEmerFireData.displayStatus` 时，命中 `hasSyncableConfiguration && !isSynced`，所以显示 `.syncIssueDevice` 图标。

## 代码证据

- `SunSmart/Common/Data/ImportData.swift:1028` 到 `1031` 使用 Space 级 `updateTimestamp` 决定是否应用云端 Space。这里判断的是整个 Space 是否需要导入，不是 EFC 设备自己的 `lastUpdate`。
- `SunSmart/Main/Space/Controller/SpaceViewController.swift:481` 到 `488` 收到 `SpaceChangeDataType.device` 会更新 `space.lastUpdate`，并走 `.promptly` cloud sync。EFC Save/Sync 都会发 `.device`。
- `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmControllerSyncVC.swift:300` 到 `310` Sync 成功时会把 `data.isSynced = true` 并保存。
- `SunSmart/Common/Data/ExportData.swift:607` 会导出 EFC 的 `isSynced`，所以 Editor 上传到云端的数据可以携带 `true`。
- `SunSmart/Common/Data/ImportData.swift:1697` 到 `1708` 没有读取 `controllerJson["isSynced"]`，而是计算 `importedIsSynced`。只要配置有 sync intent、绑定节点或 publish group，就会导入为 `false`。
- `SunSmart/Main/Device/Device1.5/FireAlarm/Model/DeviceEmerFireData.swift:317` 到 `319` 会把 `hasSyncableConfiguration && !isSynced` 显示为 `.syncIssueDevice`。

## 对当前云端数据的判断

这份配置会让当前 import 逻辑算出 `false`：

- `powerLossSettings.associateGroupAddresses = [49161]`
- `fireAlarmSettings.associateGroupAddresses = [49161]`
- `bindNodeAddress = "1E24"`
- `publishGroupAddress = "C00B"`

其中任一项都不是“完全空配置”。尤其 `configuration.hasSyncIntent` 会因为 active associated group 非空而返回 `true`。因此 Owner App 即使从云端拿到 `isSynced: true`，本地保存后仍会变成 `false`。

## 是否涉及 Battery Power Switch / AC Power Switch

目前看不是同型问题。

Battery/AC Power Switch 使用 `PJEightKeySwitchData` 的同步元数据，而不是单个 `isSynced` 布尔值。它会导出并导入 `syncState`、`desiredConfigHash`、`appliedConfigHash`、`lastSyncedAt`、`appliedTxEnabled`、`appliedLEDIndicatorEnabled` 等字段：

- 导出：`SunSmart/Main/Device/Device1.5/NEightKeySwitches/Repositories/PJEightKeySwitchRepository.swift:434` 到 `470`
- 导入：`SunSmart/Main/Device/Device1.5/NEightKeySwitches/Repositories/PJEightKeySwitchRepository.swift:474` 到 `527`
- import 组装：`SunSmart/Common/Data/ImportData.swift:1653` 到 `1675`
- 成功回写：`SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift:228` 到 `235`

Battery/AC 也可能因为真实配置 hash、applied 状态或 syncState 不一致而显示同步失败，但那属于其自身的 hash/applied 判断，不是这次 EFC “云端 true 被 import 强制改成 false”的问题。

## 修复方案

### 方案 A：导入时保留云端 `isSynced`，缺省时才走旧推导

推荐采用。

改动范围：

- 修改 `SunSmart/Common/Data/ImportData.swift`
  - 当 `emergencyFireControllers[]` 明确包含 `isSynced` 字段时，使用云端值。
  - 当旧 payload 没有 `isSynced` 字段时，保留当前 fallback：空配置、无绑定、无 publish group 才导入为 synced。
  - 保留 `configuration`、`bindNodeAddress`、`publishGroupAddress` 的解析，不改变 EFC sync planner 行为。

预期效果：

- Editor 同步成功并上传 `isSynced: true` 后，Owner 导入后仍为 true，Others 不再误显同步图标。
- Editor 同步失败或未同步并上传 `isSynced: false` 后，Owner 仍显示同步图标。
- 老版本云端数据没有 `isSynced` 时，仍沿用当前保护逻辑，不把未知设备误判为已同步。

风险：

- 这个修复把 EFC 的 `isSynced` 定义明确为 cloud-shareable device state，而不是“当前手机本地是否执行过 sync”。这与用户场景一致，因为 Editor 已经对真实设备完成了 Sync，Owner 不应要求重复同步。

### 方案 B：引入时间戳比较后再决定是否信任 `isSynced`

不推荐作为第一版。

需要比较 EFC 自己的 `lastUpdate`、Space `updateTimestamp`、本地 controller timestamp，以及本地是否有未上传改动。当前问题不需要这么复杂；而且本次 Owner 能拿到新云端数据，说明 Space 级 timestamp 已经足以触发导入。

## 实施计划

1. 在 `ImportData.swift` 提取一个局部 helper 或小段明确逻辑：优先读取 `controllerJson["isSynced"]`，字段缺失才使用旧 `importedIsSynced` 推导。
2. 在 `scripts/check_efc_controller_flows.sh` 增加 contract：EFC import 必须引用 `controllerJson["isSynced"]`，并且仍保留缺省 fallback，防止未来回归成完全重算。
3. 可选增加一个轻量 Swift 单元测试或脚本级 fixture：输入包含 associated group、bind/publish、`isSynced: true` 的 EFC JSON，验证导入后状态为 true。若项目现有测试接入成本高，先用 contract 覆盖。
4. 运行 `bash scripts/check_efc_controller_flows.sh`。
5. 运行 `git diff --check`。
6. 按项目规则运行 iPhoneOS 构建：
   `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

## 需要你确认

建议按方案 A 修复：EFC 云端 payload 明确有 `isSynced` 时，Owner/Editor 导入都保留云端状态；只有旧 payload 缺字段才继续使用当前 fallback 推导。
