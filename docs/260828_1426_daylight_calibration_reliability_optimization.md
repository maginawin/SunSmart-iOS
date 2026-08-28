# Daylight Calibration P0/P1/P2 可靠性优化总结

## 实施结论

已完成 Night Calibration 失败分析对应的 P0、P1、P2 优化，并将 Group Auto 暂停范围统一扩展到 Plane、Night、Sensor 三种校准模式。

本次改动分别落在 SunSmart App 与本地 NordicSigMeshSDK 开发工作树：

- App：`/Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/new-calibration`
- SDK：`/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`

## P0：Night 从受控灯光状态开始采样

Night 模式完成初始化、Publish Delta 调整和 Sensor Publication 切换后，不再执行未受控的环境稳定门槛，而是直接进入现有受控灯光采样流程。

这不会取消 Night 的稳定性保护。Night 后续每组 OFF/Target 采样仍会：

1. 向 Group 发送明确的 Lightness；
2. 等待最小稳定时间；
3. 对全部必要灯具执行 Lightness Status 到位确认；
4. 灯具确认到位后按稳定窗口采集 Lux；
5. 完成三组 OFF/Target 配对一致性校验。

SDK 新增 `environment_stability_skipped` 调试事件，用于区分 Night 主动跳过未受控门槛和实际漏采样。

Plane、Sensor 仍保留环境稳定性检查。

## P1：三种模式统一管理 Group Auto 生命周期

Plane、Night、Sensor 在启动 SDK 校准前统一暂停 Group Auto，避免 LC Auto 与校准 Lightness 指令竞争。

恢复规则统一为：

- SDK 普通失败且 SDK 回滚成功：恢复 Group Auto；
- SDK 回滚失败：保持 Group Auto 关闭，避免在设备临时状态未完整恢复时重新启动自动控制；
- SDK 成功后进入 App Publication、Profile 保存及灯具配置阶段：继续保持 Group Auto 关闭；
- App 配置全部成功：恢复 Group Auto；
- App 配置失败并等待 RETRY、CANCEL 或 STOP：保持 Group Auto 关闭；
- App Publication 或校准数据回滚均成功：恢复 Group Auto；
- 任一 App 回滚失败：保持 Group Auto 关闭并使校准状态失效。

SDK 校准仍在执行时，页面自定义返回按钮会阻止退出，交互式侧滑返回也会临时禁用；SDK 阶段结束后恢复原始侧滑状态。帮助页面等非退出跳转不会触发 Group Auto 恢复。

Sensor 模式原有的草稿手动调光和退出恢复语义继续保留，并复用统一的 Daylight Group Auto 状态。

## P2：60 秒窗口与 ambientInstability 二次采样

两套默认稳定采样策略的单次超时均由 20 秒延长到 60 秒：

- `LightnessLuxStabilityPolicy.settleTimeout`
- `NightSensorCalibrationPolicy.settleTimeout`

所有可能产生 `ambientInstability` 的环境稳定检查统一允许两次采样窗口：第一次 60 秒失败后，仅当错误为 `ambientInstability` 时继续采样一次；无响应等其他错误不重试。

环境阶段外层超时同步调整为 `60 × 2 + 15 = 135` 秒，避免原有外层 timer 提前报 `noResponse`。

受控灯光点的单次采样窗口延长后，整体校准超时同步放大：

- Plane、Sensor：300 秒调整为 900 秒；
- Night：600 秒调整为 1800 秒。

受控灯光点采样超时产生的是 `lightOutputUnstable`，不是 `ambientInstability`；本次按要求仅对全部 `ambientInstability` 增加一次继续采样，没有把真实的灯光输出不稳定自动重试隐藏掉。

## 自动验证结果

以下检查通过：

- Sensor Calibration 工作流契约；
- Night Calibration 工作流契约；
- Night Calibration 持久化契约；
- App 与本地 SDK `git diff --check`；
- 本地 NordicSigMeshSDK 的 iPhoneOS 无签名构建；
- `SunSmart` iPhoneOS 无签名构建；
- `Archipelago` iPhoneOS 无签名构建；
- `SLG Sync Plus` iPhoneOS 无签名构建；
- `SylSmart` iPhoneOS 无签名构建；
- `Lumineux` iPhoneOS 无签名构建。

构建日志中仍有工程既有资源重名、废弃 API 和并发隔离等警告，本次没有扩大范围处理。

## 依赖与验收边界

SunSmart workspace 当前构建解析的是远程 NordicSigMeshSDK `release` revision，因此 App 五个 target 的构建验证证明 App 改动可与当前依赖编译；本地 SDK 改动则通过 NordicSigMeshDemo 对 `one-dev` 的本地 Package 引用单独完成 iPhoneOS 构建验证。

本次未修改 UI 布局、资源、本地化或 target 配置。

尚未完成真实设备上的 BLE Mesh 与照度闭环验收。建议至少覆盖低、中、高起始亮度以及 Group Auto 正在调节的状态，每个场景重复 Night Calibration 10 次，并分别确认：

- 每次都进入首个受控 `light_verify_start`；
- OFF/Target 灯具到位与稳定 Lux 窗口正常；
- SDK 校准 ACK、App Profile 保存、Configuring 完成；
- 成功和普通失败后 Group Auto 恢复；
- 回滚失败后 Group Auto 保持关闭；
- Publication、Publish Delta 与校准数据没有残留临时状态。
