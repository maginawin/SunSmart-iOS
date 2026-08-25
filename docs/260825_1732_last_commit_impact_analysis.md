# 最新提交对 Calibration 审查修复计划的影响分析

## 结论

用户最新提交为 App 仓库的 `093e0743`（`fix: sensor cal don't - OffLux`）。SDK 仓库最新提交仍为 `71061e16`，当前待修复的 SDK 可靠性与接收元数据代码仍属于未提交工作树改动。

该提交不改变三条审查意见的成立条件，也不阻塞既定修复，但新增了一条必须保留的产品边界：Sensor Cal. 的目标可达性只比较稳定的绝对 OnLux 与目标值 95% 下限，不得减去 OffLux，也不得重新引入暗环境能力门槛。

## 提交影响

### App 代码

最新提交已经：

- 将当前 Group 的必要 Lightness 灯具和 Group 地址显式传入 Plane、Sensor、Night 三种 SDK 校准入口；
- 将 Sensor Target Lux 显式传给 SDK；
- 增加必要灯具不到位、输出不稳定、目标不可达和 publish-delta 恢复失败的 UI 错误映射；
- 删除 `sensorDarkCapacityInsufficient` 分支及本地化文案；
- 强化 Sensor workflow 契约，禁止 Sensor 目标判断重新减去 OffLux。

这些改动与 Lightness Range、publish-delta 竞态及 metadata continuation 修复没有接口冲突。

### SDK 当前未提交代码

对应 SDK 工作树已经采用只接收 `onLux` 与 `targetLux` 的 `sensorReachability`，并删除暗环境能力错误。后续修改 `MeshSensorCalibrateManager` 时必须保留这些现有增量。

三项待修复点仍然存在：

- 逐灯到位仍将 Status 与 Group 原始请求值直接比较，没有按节点 `lightnessRange` 计算期望值；
- publish-delta 三次 ACK 的约 31 秒预算仍与 30 秒 timer 竞争；
- `cancelNotifyCallback` 仍会静默删除 metadata callback，不恢复旧 continuation。

## 对实施计划的调整

原三项修复设计保持不变，仅调整回归保护：

1. 扩展现有 Sensor workflow 契约时，继续保留“不包含 dark capacity”与“Sensor 不减 OffLux”的断言；
2. Lightness Range 修复只改变逐灯 Status 的期望值，不改变 Sensor Target 可达性公式、OnLux/OffLux 采样或 `0x38` 曲线 delta；
3. publish-delta 和 metadata 修复不增加新的 App 错误类型或本地化；
4. 四品牌构建继续使用当前本地 SDK 引用，不修改 dependency、target 或 Package 配置。

## 工作树保护

App 在最新提交后工作树为 clean；SDK 保留校准可靠性和 Mesh 接收诊断的多文件未提交改动。实施时只编辑规划列出的聚焦文件，不重置、覆盖或格式化其他 SDK 文件。
