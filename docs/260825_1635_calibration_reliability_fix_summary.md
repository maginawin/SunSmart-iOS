# Calibration 三模式可靠性修复总结

## 1. 完成结论

本批次已完成 Sensor Cal.、Plane Cal.、Night Cal. 的共同可靠性修复，并完成 App 与本地 `NordicSigMeshSDK` 的集成编译。

当前实现遵循已确认的产品规则：

- Sensor 目标 Lux 允许向下浮动 5%，最低可接受值按 `ceil(targetLux × 95%)` 计算。
- 当前 100% 稳定 Lux 低于该下限时硬失败。
- 暗环境灯具贡献 `stableOnLux - stableOffLux` 低于该下限时硬失败。
- 当前 Group 任一必要灯具离线、无响应或持续未达到目标 Lightness 时硬失败，不允许按剩余灯具降级校准。
- 断电持久化读回和 Auto 恢复后的长期闭环收敛不在本批次范围内。

## 2. 已实现行为

### 2.1 三模式统一稳定采样

- 所有 0%、粗搜、精搜、目标亮度和 100% 点均使用统一采样器。
- 每个亮度点先等待灯具到位，再按约 1 秒周期主动读取 Sensor Lux。
- 默认要求最近 4 个有效样本形成稳定窗口，并完成连续 3 次无有效方向改善判断。
- 默认稳定范围取固定 2 lx 与相对 2% 两者中的较大值。
- 默认单点总超时 20 秒；无有效样本返回无响应，持续波动返回明确的未稳定错误。
- 最终值使用稳定窗口中位数，避免瞬时过冲或遮挡形成的全过程极值直接进入 `0x38`。

因此，类似 83、86、89、94 的持续上升序列不会提前在 86 或 89 结束；必须进入最终稳定平台后才采纳。

### 2.2 严格 Group 灯具到位校验

- 页面从当前选中的 Group 中枚举实际订阅该 Group 的 Lightness Model 节点，并将 Group 地址及必要灯具快照显式传给 SDK。
- 不再依赖 `sensorNode.group` 的首个订阅组语义，避免多组订阅场景校验到错误 Group。
- 每个采样点仍先使用 Group Unack 快速下发 Lightness。
- SDK 随后逐灯单播读取 Lightness Status。
- 首次未到位时执行有限次数 acknowledged 单播修正及再次读取。
- 任一必要灯具最终未确认到位时，停止本轮校准并进入回滚。

### 2.3 Sensor 目标可达性

- 页面目标 Lux 已传入 SDK。
- `minimumReachableLux` 使用向上取整，目标 100 lx 的下限为 95 lx，目标 101 lx 的下限为 96 lx。
- 先校验当前 100% 稳定值，再校验去除 OFF 基线后的暗环境灯具贡献。
- 两项均通过后才允许提交新 `0x38`/`0x39`。

### 2.4 初始稳定性与 publish delta

- 初始环境稳定性不再依赖零样本可通过的被动 Publication 统计，而是复用主动稳定采样；零样本必定失败。
- 校准开始时设置 publish delta=1 使用严格成功响应校验。
- 校准结束恢复 publish delta=5 时最多尝试 3 次，只有 Response Code 为 `daylightPublishDelta` 且状态成功才允许继续。
- 恢复失败不得报告 SDK 成功，并进入旧校准、旧 Publication 和 publish delta 的统一回滚。

### 2.5 App 错误反馈

新增并同步 English、简体中文提示，区分：

- 必要灯具离线或未到位；
- Lux 长时间未稳定；
- 当前条件下目标不可达；
- 暗环境能力不足；
- publish delta 恢复失败。

## 3. 主要改动位置

App：

- `SunSmart/Main/Group/Controller/LightSensorCalibrationViewController.swift`
- `SunSmart/en.lproj/Localizable.strings`
- `SunSmart/zh-Hans.lproj/Localizable.strings`
- `Tests/Group/SensorCalibrationWorkflowContractTests.swift`

本地 SDK：

- `Sources/NordicSigMeshSDK/MeshLib/Manager/MeshSensorCalibrateManager.swift`
- `Sources/NordicSigMeshSDK/MeshLib/Manager/MeshSensorCalibrateServer.swift`
- `Tests/NordicSigMeshSDKTests/SensorCalibrateMathTests.swift`

SDK 仓库中另有既存的 Mesh 接收诊断相关未提交改动；本批次没有重置、覆盖或归入本次校准修复结论。

## 4. 自动化与构建结果

以下校验通过：

- `SensorCalibrationWorkflowContractTests`
- `NightCalibrationWorkflowContractTests`
- `NightCalibrationPersistenceContractTests`
- SDK 校准 Manager、Error 和数学测试源文件的 Swift 语法解析
- App 与 SDK 两个仓库的 `git diff --check`

以下四个共享 target 均使用本地 `NordicSigMeshSDK`，并通过 `iphoneos`、`generic/platform=iOS`、`CODE_SIGNING_ALLOWED=NO` 构建：

- SunSmart
- Archipelago
- SLG Sync Plus
- SylSmart

`SensorCalibrateMathTests` 已补充确定性样本、95% 边界和 Lightness 到位判断用例；当前未使用 Simulator，也没有连接测试设备执行 XCTest，因此其运行期结果仍需后续 iOS 测试环境补证。四 target 构建已经覆盖 SDK 与 App 的实际集成编译。

## 5. 真机验收清单

每种模式至少验证单灯 Group、当前三灯 Group 和多灯 Group：

1. 观察每个采样点出现完整 `light_verify_start`、逐灯 `light_verified` 和成功的 `light_verify_complete`。
2. 观察 Lux 每约 1 秒递增，持续上升/下降时不得出现 `lux_stable`；进入稳定平台后才输出代表值。
3. Sensor 目标 100 lx 时分别制造 95 lx、94 lx 边界，验证 95 通过、94 硬失败。
4. 制造较高环境光，使总 Lux 达标但 ON-OFF 灯具贡献低于 95%，验证暗环境能力硬失败。
5. 让任一必要灯具离线或拒绝到达目标 Lightness，验证三种模式均停止且不降级校准。
6. 模拟 publish delta 首次失败后重试成功，以及持续失败，验证只有正确成功 ACK 才能完成。
7. 失败后核对旧校准、Sensor Publication、publish delta 和 App Auto 恢复边界；回滚不完整时必须保持失效状态并提示重新校准。
8. 同一稳定环境重复校准，比较 OFF、ON、拐点和最终 payload 的重复性。

本批次真机通过后，再进入断电持久化读回和 Auto 长期闭环收敛验证。
