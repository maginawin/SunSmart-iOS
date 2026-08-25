# Sensor Cal. 目标可达性聚焦修复计划

## 结论

按已确认的产品规则，本轮只修复 Sensor Cal. 的目标可达性：100% 稳定 `OnLux` 达到 `ceil(TargetLux × 95%)` 即通过，0% `OffLux` 不参与该目标判断。

## 修改范围

### SDK

- `sensorReachability` 移除 `offLux` 输入，只比较 `onLux` 和 Target 95% 下限；
- 删除内部 `darkCapacityInsufficient` 结果；
- 删除公开 `sensorDarkCapacityInsufficient` 错误；
- Sensor 目标日志保留 Target、95% 下限和 100% 稳定 OnLux，不再输出 `dark_capacity` 失败；
- 更新数学测试，覆盖 95% 边界以及高环境底光不再影响 Sensor 目标判断。

### App

- 删除三种失败处理 switch 中已经不存在的 `sensorDarkCapacityInsufficient` 分支；
- 删除 English、简体中文中对应的不可达文案；
- 更新 Sensor workflow 源码契约，明确禁止暗环境硬门槛回归。

## 明确不修改

- Night Cal. 成对采样和 `OnLux - OffLux` Target 生成；
- Plane Cal. 的 `0x39` 两分量倍率公式；
- Plane、Sensor、Night 共用的 `0x38` 曲线及其 Lux delta；
- 稳定窗口、Group 灯具到位、publish delta、回滚、Auto 生命周期；
- SDK Package 引用、target 配置、资源和其他 Mesh 接收诊断改动。

## 验收

1. 先让更新后的源码契约和数学边界对旧实现呈 RED；
2. 实施最小源码改动后契约转 GREEN；
3. 对 App 与 SDK 相关文件执行 `git diff --check` 和残留符号检查；
4. 验证 Night 差值实现、Plane 倍率实现和共同 `0x38` 仍存在且未改变；
5. 串行构建 SunSmart、Archipelago、SLG Sync Plus、SylSmart 四个 iphoneos Debug target，关闭签名且不使用 Simulator；
6. 真机复验 Target 295、Off 46、On 295 应继续写入校准曲线，不再触发 `dark_capacity`；94% 以下稳定 OnLux 仍应失败。
