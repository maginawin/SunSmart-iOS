# Daylight 未校准 Auto High-End Trim 修复设计

## 背景

当 group 的 profile 是纯 `.daylight`，也就是 Daylight harvesting closed loop 时，未校准状态下在组控制页点击 Auto 后，组内灯可能开、也可能关，亮度行为不稳定。已校准状态下功能正常。

期望行为是：未校准状态下，重新 SAVE / Sync profile 后，任何来源下发 Auto 命令，包括组控制页、传感器、遥控器，都应让灯进入 profile 的 high-end trim 亮度。

本次不修改 Auto 命令本身。`GroupViewController.autoBtnAction` 仍发送 `LightLCLightOnOffSetUnacknowledged(true, transitionTime: .default, delay: 0)`，因为传感器和遥控器也会通过同类 Auto 命令触发设备进入 Auto 效果。根因应在设备 profile 配置里修复。

## 当前代码分析

组页 Auto 路径位于 `SunSmart/Main/Group/Controller/GroupViewController.swift`：

- `autoBtnAction` 只发送 `LightLCLightOnOffSetUnacknowledged(true)` 到 group address。
- 本地 UI 更新依赖节点的 `lightLCOnLightness`，该属性来自 `node.lightLCProperty.lightnessOn`。
- 对 daylight profile 的本地判断只看 `ambientLightSensorNode != nil`，不直接决定真实设备行为。

profile 同步路径位于 `SunSmart/Common/Data/Node+SyncData.swift`：

- `getNodeLightDataSyncProfiles(...)` 会根据 `daylightEnabled` 判断是否启用 closed-loop。
- `daylightEnabled == true` 的条件是 group 的 ambient light sensor 已校准，或存在 restore calibration 数据。
- `.daylight` 未校准时，代码会下发 `lightAutoAdujustEnabled(false)`。
- `.daylight` 的 `.taskLevel` 当前仍按 daylightType 下发 `occupancyLux(lux: taskLevel)`，不会写入 `LightControlLightnessOn`。
- 因此未校准 `.daylight` 下，设备收到 Auto 后缺少明确的百分比亮度目标，实际表现取决于设备已有或默认的 Light LC On 属性。

已校准 `.daylight` 下，现有逻辑会：

- 下发 `lightAutoAdujustEnabled(true)`；
- 下发 target lux；
- 在 `autoMinValue` 分支中，把 `LightControlLightnessOn / Prolong / Standby` 写成 auto-min 亮度，未启用时为 0。

这说明校准后并不应长期保留未校准 fallback 的 high-end trim level。

## 修复目标

1. 仅保证重新 SAVE / Sync profile 后，未校准纯 `.daylight` group 的 Auto 正常进入 high-end trim。
2. 不修改组页 Auto、传感器 Auto、遥控器 Auto 的命令内容。
3. 已校准 `.daylight` 保持现有 closed-loop 行为。
4. 从未校准切换到已校准并重新同步后，`LightControlLightnessOn` 应从 high-end trim 回到 auto-min 或 0，由现有 calibrated 分支维护。
5. 不扩大到 `.occupancy_daylight` / `.vacancy_daylight`，除非后续有单独需求。

## 方案比较

### 方案 A：修改 profile 同步生成规则

在 `getNodeLightDataSyncProfiles(...)` 中处理 `.taskLevel` 时，增加未校准纯 `.daylight` 分支：

- 条件：`groupProfile.type == .daylight && !daylightEnabled`。
- 目标：确保 `LightControlLightnessOn == highEndTrim`。
- 消息：复用现有 `.occupancyLevel(value: groupLightData.highEndTrim)`，最终发送 `LightLCPropertySet(.lightControlLightnessOn, .perceivedLightness(...))`。

优点：

- 根因修复在设备配置层，所有 Auto 来源都受益。
- 不改 Auto 命令，不影响传感器和遥控器路径。
- 改动集中在同步 profile 生成逻辑。
- 校准后现有 auto-min 分支会把 level 改回目标值。

缺点：

- `.daylight` 未校准时 `.taskLevel` 的 lux 写入需要让位给 fallback level，避免同一阶段同时表达 lux 目标和百分比 fallback。

### 方案 B：新增专用 ProfileType

新增类似 `daylightUncalibratedAutoLevel(highEndTrim)` 的 enum case，消息仍写 `LightControlLightnessOn`。

优点是语义最清晰。缺点是需要同步检查 UI 文案、同步步骤展示、成功判断和其它 switch 分支，改动面比实际需求大。

### 方案 C：SAVE / Sync 后补发 Auto

同步结束后再发一次 Auto。

该方案只能影响当次同步后的现场状态，不能改变设备之后响应传感器或遥控器 Auto 的基础配置，因此不解决根因。

## 选定方案

采用方案 A。

在 `getNodeLightDataSyncProfiles(...)` 中，针对纯 `.daylight` 且未校准的情况，把 Auto 的 fallback 亮度配置到 `LightControlLightnessOn`：

- 如果 `forceFullProfileSync == true`，始终生成 `.occupancyLevel(value: highEndTrim)`。
- 否则只有当当前 `lightLCProperty.lightnessOn` 不等于 `Node.getLightness(lightness100: highEndTrim)` 时生成。
- 已校准 `.daylight` 继续走 target lux 和 auto-min 配置，不保留 high-end trim fallback。

行为结果：

- 未校准 `.daylight` 同步后，Auto 命令进入 LC On，灯亮度为 high-end trim。
- 校准后再次同步，`lightAutoAdjustEnabled(true)` 生效，target lux 继续由现有逻辑维护，`LightControlLightnessOn` 由 auto-min 分支改回 auto-min 或 0。
- Auto 命令来源不再重要，组页、传感器、遥控器都使用设备内同一套 Light LC 配置。

## 测试设计

优先添加或扩展围绕 `getNodeLightDataSyncProfiles(...)` 的单元级验证。如果当前工程没有合适测试承载，则至少用源码检查和 iOS build 验证。

需要覆盖：

1. 未校准纯 `.daylight`，`highEndTrim = 80`，生成 `.occupancyLevel(value: 80)`。
2. 未校准纯 `.daylight`，当前 `lightnessOn` 已等于 high-end trim 且非 force full sync，不重复生成。
3. 已校准纯 `.daylight` 不走 high-end trim fallback，仍按现有逻辑生成 target lux 和 auto-min/0 level。
4. `.occupancy_daylight` / `.vacancy_daylight` 行为不因本次修复改变。

构建验证使用：

`xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

## 风险与边界

- 如果固件在未校准 `.daylight` 下仍优先使用 lux 属性而忽略 `LightControlLightnessOn`，需要设备侧确认 Light LC On 在 `lightAutoAdjustEnabled(false)` 时的优先级。但从现有 Auto 行为和 `lightLCOnLightness` 本地估算来看，`LightControlLightnessOn` 是正确落点。
- 不修改 `GroupViewController` 的 Auto 命令，避免只修一个入口。
- 不处理未重新同步配置的历史设备。用户需要重新 SAVE / Sync profile 后才具备确定行为。
- 不扩展到带 occupancy 的 daylight profile，避免改变占用感应 fallback 行为。
