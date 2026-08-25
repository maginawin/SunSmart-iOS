# Sensor Cal. 目标可达性修复总结

## 完成结论

已按确认边界完成修复：Sensor Cal. 的目标可达性只比较 100% 稳定 `OnLux` 与 `ceil(TargetLux × 95%)`，不再接收、减去或判断 0% `OffLux`。

对本次现场数据：

- Target：295 lx；
- 95% 下限：281 lx；
- 100% 稳定 OnLux：295 lx；
- 判断：`295 >= 281`，应继续校准，不再触发 `dark_capacity`。

## 实际改动

### SDK

- `sensorReachability` 签名改为只接收 `onLux` 与 `targetLux`；
- 删除内部 `darkCapacityInsufficient` 结果及灯具贡献 95% 判断；
- 删除公开 `sensorDarkCapacityInsufficient` 错误；
- Sensor `target_reachability` 日志只记录 Target、95% 下限和稳定 OnLux；
- 数学测试改为验证绝对 OnLux 的 95% 边界，并加入 295/295 现场回归样本。

### App

- 删除 Plane、Night、Sensor 失败 switch 中已不存在的暗环境错误分支；
- 删除 English、简体中文的暗环境失败文案；
- Sensor workflow 契约明确要求 `sensorReachability(onLux:targetLux:)`，并禁止暗环境错误和本地化 Key 回归。

## 保持不变的边界

以下逻辑已通过源码保护检查确认仍在，本轮没有修改：

- Night Cal. 使用成对的 `targetBrightnessLux - offLux` 生成 Night Target；
- Plane Cal. 使用工作面和 Sensor 的 ON/OFF 差值计算 `0x39 sensorRate`；
- 三种模式共用的 `0x38` 曲线继续使用相对 OffLux 的 min/max delta；
- 稳定采样、必要灯具到位、publish delta、回滚、Group Auto 生命周期；
- 其他 Mesh 接收元数据和 Replay Protection 诊断改动。

## RED 到 GREEN

先更新 Sensor workflow 契约，旧实现按预期失败，错误为 Sensor 不得减 OffLux。完成源码修改后，同一契约通过。

通过的聚焦检查：

- `SensorCalibrationWorkflowContractTests`；
- `NightCalibrationWorkflowContractTests`；
- `NightCalibrationPersistenceContractTests`；
- SDK Manager、Error、数学测试源码 Swift 语法解析；
- App 与 SDK 两个仓库的 `git diff --check`；
- 暗环境错误枚举、处理分支、文案和运行时日志残留检查。

SDK XCTest 文件已更新，但当前没有使用 Simulator 或连接 iOS 测试设备执行 XCTest；四个 App target 的实际 iphoneos 编译已覆盖 SDK 与 App API 集成。

## 四品牌构建

以下 target 均使用当前本地 `NordicSigMeshSDK`，通过 Debug、iphoneos、generic iOS device、关闭签名的构建：

- SunSmart；
- Archipelago；
- SLG Sync Plus；
- SylSmart。

四次结果均为 `BUILD SUCCEEDED`。

## 真机验收边界

自动化和构建尚不能替代真实 Sensor/Mesh 时序。建议至少复验：

1. Target 295、0% 稳定 46、100% 稳定 295 时，出现 `target_reachability ... sensorOnLux=295 success=true`，随后继续发送并确认 `0x38`、`0x39`；
2. 100% 稳定 OnLux 为 281 时通过，为 280 时仍报告 `sensorTargetUnreachable`；
3. 高环境底光不再产生 `dark_capacity`；
4. Night 的多组成对差值和最终 Target 不变；
5. Plane 的倍率 payload 与修复前相同。

App 和 SDK 原有未提交改动均保留；本轮未 commit、push 或 merge。
