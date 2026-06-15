# Daylight Condition Recall Profile Switch 修复总结

## 问题现象

Group SAVE profile 后，某设备在 `配置文件切换` 任务失败。日志显示设备不是超时，而是明确返回：

- `SunricherVendorSet(.daylightLuxTriggerLock(delay: 600))` 成功
- `SunricherVendorSet(.daylightConditionRecall(index: 0))` 失败
- `SunricherVendorStatus.code = daylightConditionRecall`
- `isSuccessful = false`
- `errorCode = 2`

`配置文件切换` 对应的实际命令不是普通 `SceneRecall`，而是 `daylightConditionRecall(index:)`。

## 根因

`daylightConditionRecall` 用于按 daylight lux trigger condition index 激活对应的 profile scene。设备执行该命令前，目标 index 对应的 lux trigger condition 必须已经存在且可用。

当前 `proximityLightingWithPhotocell` 的 profile 同步顺序存在风险：

1. 生成 day/night threshold 配置到 `syncSceneProfiles`
2. 如果需要修改 Light LC 参数，先追加 `daylightSensorConditionRecall`
3. 再追加 `syncSceneProfiles`

这会导致 App 在本轮需要重写 condition 时，先发送 `daylightConditionRecall(index:)`，再发送 condition 配置。设备端如果此时没有该 condition，或 condition 尚未更新完成，就会拒绝 recall。

重试路径也有同类问题：`resyncRelevanceCheck()` 只把 Lock 和 Switch/Recall 放回重试队列，没有包含 `profileDayToggleTriggerConditionLux` / `profileNightToggleTriggerConditionLux`。因此用户点击 Retry 时，仍可能只重发 Lock + Recall，无法补齐 Recall 依赖的 condition。

第二轮实机日志进一步确认：Retry 仍然只发了 `daylightConditionRecallGet`、`daylightLuxTriggerLock`、`daylightConditionRecall(index: 0)`，中间没有 `daylightConditionLuxThresholdSet` / `daylightExecuteSceneActionSet` / `daylightConditionLuxUseCalibrationValuesSet`。这说明 App 本地缓存认为 condition 已存在且一致，但设备端实际拒绝 recall，属于本地缓存与设备端 condition 状态不一致。

## 修复内容

1. 调整 `Node.getNodeSyncProfiles(...)` 中场景型 profile 的生成顺序：
   - 先追加 day/night lux trigger condition 配置
   - 再追加 `daylightSensorConditionRecall` 或 `SceneRecall`
   - 最后追加 Light LC 参数配置和 `SceneStore`

2. 对准备使用 `daylightConditionRecall` 的场景，强制生成完整 day/night condition 配置：
   - 不只依赖本地 `lightControlLuxTriggerConditions` 是否存在
   - 使用 `forceFullSet: true`，确保分段协议下也会完整重写 threshold、execute scene、use calibration values

3. 调整 `SyncDeviceStepTaskModel.resyncRelevanceCheck()`：
   - Retry `配置文件切换` 时，重新带上 day/night threshold 前置任务
   - 保留原有 Lock、Switch/Recall 关联逻辑

## 影响范围

- 仅影响 group profile 同步中 `proximityLightingWithPhotocell` 场景配置的任务顺序与重试关联。
- 不修改 `daylightConditionRecall` 协议编码。
- 不修改 SDK vendor status 解析。
- 不改变普通 `SceneRecall`、Light LC 参数、Store、Lock/Unlock 的命令内容。

## 验证

已用一次性静态行为检查验证：

- condition profiles 会在 `daylightConditionRecall` 前生成
- Light LC profiles 仍在 `daylightConditionRecall` 后生成
- `daylightConditionRecall` 前存在强制 condition set 兜底
- Retry relevance 包含 day/night lux threshold 前置任务
- `git diff --check` 通过
- iPhoneOS `xcodebuild` 编译通过
