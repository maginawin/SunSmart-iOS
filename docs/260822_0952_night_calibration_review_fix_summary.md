# Night Calibration 审查问题修复总结

## 修复结果

已完成两条审查意见对应的最小修复：

1. Night 校准进入 Group member Configuring 后，仅在 completion 返回成功时恢复 Group Light LC Auto。节点失败、用户 STOP 或 CANCEL 时不会恢复 Auto；RETRY 最终全部成功时仍会通过同一 completion 恢复 Auto。
2. Profile 的有效校准模式现在要求当前 Profile 属于 daylight 类型，且当前 sensor 仍存在并满足 `sensorCalibrated == true`。无效 sensor 统一降级为 `none`；有效旧数据缺少模式字段时仍兼容为 `planeCal`。

## 修改范围

- `SunSmart/Main/Group/Controller/LightSensorCalibrationViewController.swift`
- `SunSmart/Main/Profile/Model/Profile.swift`
- `Tests/Group/NightCalibrationWorkflowContractTests.swift`
- `Tests/Group/NightCalibrationPersistenceContractTests.swift`

同时新增了独立修复计划和本总结。未修改 NordicSigMeshSDK、数据库结构、导入导出格式、UI、本地化、资源或 target 配置，也未处理工作树中其他既有 Night Calibration 改动。

## 契约验证

两组契约均按先失败、后修复通过的顺序验证：

- 修复前，Workflow 契约因 Night 路径没有成功门槛而失败；
- 修复前，Persistence 契约因持久化模式未验证 sensor 而失败；
- 修复后，`scripts/check_night_calibration_workflow.sh` 通过；
- 修复后，`scripts/check_night_calibration_persistence.sh` 通过；
- Workflow 契约限定在 Night 结果提交片段，并验证 Configuring、成功门槛、恢复 Auto 的先后顺序，避免被 Plane 路径误满足。

## 构建验证

以下构建均使用 Debug、iphoneos、generic iOS destination，并关闭代码签名，按顺序执行且成功：

- `SunSmart`
- `Archipelago`
- `SLG Sync Plus`
- `SylSmart`

构建中仅出现 AppIntents metadata extraction skipped 提示，没有构建失败。`git diff --check` 通过。

## 尚未验证

本次没有真实 BLE Mesh、固件 ACK、设备上下线、STOP/RETRY 操作和云端实际上传环境，因此以下仍需真机验收：

- 失败或 STOP 分支确实没有发送 Group Auto On；
- RETRY 最终成功后发送 Group Auto On；
- 失败节点的 pending 状态在退出重进后仍正确；
- sensor 删除、解绑或 reset 后，页面 Active、Night Apply 和云端导出均表现为 `none`。

