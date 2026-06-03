# Occupancy Daylight 未校准 Auto High-End Trim 修复设计

## 背景

已完成的纯 `.daylight` 修复让 Daylight harvesting closed loop profile 在未校准时，重新 SAVE / Sync profile 后响应 Auto 命令进入 profile high-end trim 亮度。

现在需要把同一规则扩展到另外两个支持 daylight calibration 的 profile：

- `.occupancy_daylight`
- `.vacancy_daylight`

本次仍不修改 Auto 命令本身。组控制页、传感器、遥控器仍通过 `LightLCLightOnOffSetUnacknowledged(true)` 触发设备进入 Auto；修复点继续放在 profile SAVE / Sync 下发的设备 Light LC 配置。

## 当前代码分析

支持 daylight calibration 入口的 group profile 范围是：

- `.occupancy_daylight`
- `.vacancy_daylight`
- `.daylight`

在 `SunSmart/Common/Data/Node+SyncData.swift` 的 `getNodeLightDataSyncProfiles(...)` 中：

- `daylightType` 当前覆盖 `.occupancy_daylight`、`.vacancy_daylight`、`.daylight`。
- `daylightEnabled` 表示 daylight sensor 已校准，或存在 restore calibration 数据。
- 未校准 daylight profile 会下发 `lightAutoAdujustEnabled(false)`。
- 纯 `.daylight` 已在上一次修复中改为未校准时写入 `LightControlLightnessOn = highEndTrim`。
- `.occupancy_daylight` / `.vacancy_daylight` 未校准时仍在 `autoMinValue` 分支使用固定 fallback：On 为 100，Prolong 为 50，Standby 为 0。

因此当 `.occupancy_daylight` / `.vacancy_daylight` 的 high-end trim 不是 100 时，Auto 第一阶段不会按 high-end trim，而是按固定 100，和新需求不一致。

## 修复目标

1. 重新 SAVE / Sync profile 后，未校准 `.occupancy_daylight` / `.vacancy_daylight` 响应 Auto 时进入 profile high-end trim 亮度。
2. 不修改组页、传感器、遥控器的 Auto 命令。
3. 纯 `.daylight` 已有行为保持不变。
4. 已校准 `.occupancy_daylight` / `.vacancy_daylight` 保持现有 closed-loop 行为，并由现有 auto-min 分支把 level 改回 auto-min 或 0。
5. 不扩展到 `.proximityLightingWithPhotocell`，因为它不是当前 daylight calibration 入口范围。

## 方案比较

### 方案 A：统一 daylight 未校准 fallback

把未校准 fallback 规则从纯 `.daylight` 扩展为所有 `daylightType && !daylightEnabled`。这会覆盖 `.daylight`、`.occupancy_daylight`、`.vacancy_daylight`。

未校准时同步目标：

- `LightControlLightnessOn = groupLightData.highEndTrim`

优点：

- 规则统一，所有支持 calibration 的 daylight profile 未校准 Auto 行为一致。
- 继续在设备配置层治本，所有 Auto 来源都受益。
- 改动仍集中在 `getNodeLightDataSyncProfiles(...)`。

缺点：

- 需要确保未校准 `.occupancy_daylight` / `.vacancy_daylight` 不再被后面的固定 `100 / 50 / 0` 分支覆盖。

### 方案 B：只改 auto-min fallback 固定值

仅把 `.occupancy_daylight` / `.vacancy_daylight` 未校准分支中的 On 固定 100 改成 high-end trim。

优点是改动小。缺点是纯 `.daylight` 和 occupancy daylight 的 fallback 逻辑会继续分散在不同分支中，后续维护容易再次不一致。

### 方案 C：新增 helper 抽象 fallback level

新增一个内部 helper 统一判断是否需要 daylight uncalibrated fallback，并返回 high-end trim。

优点是语义清晰。缺点是当前逻辑规模较小，新增 helper 会让改动比需求更重。

## 选定方案

采用方案 A。

实现时把纯 `.daylight && !daylightEnabled` 的条件扩展为 `daylightType && !daylightEnabled`，并让未校准 daylight profile 优先写入 `LightControlLightnessOn = highEndTrim`。

同时需要调整 `autoMinValue` 的未校准 occupancy 分支，避免它继续追加固定 `100 / 50 / 0` 并覆盖 high-end trim。推荐做法是让该固定 fallback 只作用于非 daylight calibration 的场景；对 `daylightType && !daylightEnabled`，不再写固定 On/Prolong/Standby。

行为结果：

- `.daylight` 未校准：Auto 到 high-end trim，保持已有修复行为。
- `.occupancy_daylight` 未校准：Auto 第一阶段到 high-end trim，不再固定 100。
- `.vacancy_daylight` 未校准：Auto 第一阶段到 high-end trim，不再固定 100。
- 三种 daylight profile 已校准：继续启用 `lightAutoAdujustEnabled(true)`，target lux 和 auto-min/0 回写保持现有逻辑。
- Auto 命令入口不变。

## 测试设计

需要覆盖：

1. 未校准 `.occupancy_daylight`，`highEndTrim = 80`，生成 `.occupancyLevel(value: 80)`，不生成 `.occupancyLevel(value: 100)`。
2. 未校准 `.vacancy_daylight`，`highEndTrim = 70`，生成 `.occupancyLevel(value: 70)`，不生成 `.occupancyLevel(value: 100)`。
3. 未校准纯 `.daylight` 仍生成 high-end trim fallback。
4. 已校准 `.occupancy_daylight` / `.vacancy_daylight` 仍由 auto-min 分支回写 level，不保留 high-end trim fallback。
5. Auto 命令入口文件没有改动。

构建验证使用：

`xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

## 风险与边界

- 本次只保证重新 SAVE / Sync profile 后的行为。未重新同步的历史设备不会自动改变。
- 不修改 `GroupViewController`、传感器或遥控器 Auto 下发命令。
- 不处理 `.proximityLightingWithPhotocell`，避免改变 day/night lux trigger 场景逻辑。
- 如果固件对未校准 daylight occupancy profile 仍优先读取 lux 属性，需要设备侧确认。但当前关闭 `lightAutoAdujustEnabled(false)` 后，`LightControlLightnessOn` 是最一致的 Auto fallback 配置点。
