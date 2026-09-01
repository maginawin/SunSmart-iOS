# Night Calibration 约 50% 失败问题分析

## 结论

本次失败不是 Mesh 指令无响应、灯具离线或 `0x38` / `0x39` 写入失败，而是 Night Calibration 在真正控制灯具和采集 OFF/Target Lux 之前，被共用的“环境光稳定性检查”提前终止。

失败日志中，环境 Lux 在 20 秒采样窗口内从 `457` 持续下降到 `306`，最后 4 个样本为 `[340, 328, 317, 306]`，没有进入稳定窗口，因此 SDK 报出 `ambientInstability(minLux: 306, maxLux: 457)`。该阶段仍未发送第一条 Group Lightness 指令，也没有进入任何 `light_verify_start`，所以失败与 Night 的 OFF/Target 配对计算无关。

成功日志进入同一阶段时的起点较低：从 `345` 下降到约 `332`，第 7 个样本时最后 4 个样本 `[337, 332, 332, 331]` 已满足当前相对稳定阈值，因而继续执行并最终成功。

约 50% 的现象符合“开始采样时设备正处于不同的灯光/传感器过渡阶段”造成的时序型失败，但只有两份日志，不能据此统计确认实际概率。建议后续至少记录 20～30 次重复结果验证优化前后的失败率。

## 成功与失败证据对比

| 对比项 | 失败日志 | 成功日志 | 判断 |
| --- | --- | --- | --- |
| 校准启动 | `app_start`、`sdk_input` 正常 | 正常 | App 已正确进入 Night 模式 |
| 清空旧校准和倍率 | Vendor ACK 成功 | 成功 | 不是 Vendor 指令失败 |
| Publish Delta 临时设为 1 | 第 1 次 ACK 成功 | 第 1 次 ACK 成功 | 不是 Publish Delta 失败 |
| Sensor Publication 切到手机 | `ConfigModelPublicationStatus ... Success` | 成功 | 直读通道可用 |
| 环境阶段样本 | `457 → 306`，持续单向下降 | `345 → 331`，后段收敛 | 起始状态和收敛时机不同 |
| 环境稳定结果 | 20 秒后 `lux_stable_timeout` | 第 7 个样本 `lux_stable` | 直接分叉点 |
| 灯具到位检查 | 未开始 | 多次 `light_verify_complete success=true` | 失败早于受控采样 |
| Night OFF/Target 配对 | 未开始 | 差值 `[278, 277, 278]`，结果 `278` | Night 计算本身没有失败证据 |
| 失败回滚 | 校准、Publication、Publish Delta 均恢复成功 | 不适用 | 失败后的 SDK 回滚正常 |

## 源码原因

当前工程锁定的 NordicSigMeshSDK revision 为 `9504e5ba7286205f8d4749d8127bf2178b19d9a2`。DerivedData 实际 checkout 与本地 `one-dev` 的 `MeshSensorCalibrateManager.swift` 文件哈希一致，因此以下源码判断与本次日志对应。

1. Night 默认稳定策略的内部采样超时为 20 秒，采样间隔约 1 秒，稳定窗口为 4 个样本。
2. `stabilityVerify()` 将最小等待时间强制改为 0；Sensor Publication 设置成功后立即开始读取，没有先固定灯具输出。
3. 环境阶段使用 `trend=neutral`。稳定阈值为固定 2 Lux 与当前 Lux 的 2% 两者取大值；失败日志末 4 个样本的极差为 34 Lux，明显不满足阈值。
4. 环境检查得到的代表 Lux 没有参与后续 Night 参数计算，只作为一道成功/失败门槛。
5. 通过该门槛后，下一步本来就会把 Group 设为明确的 Lightness，等待至少 3 秒，逐个读取必要灯具的 Lightness Status，并以稳定窗口重新采集 Lux。
6. App 当前只在未完成的 Sensor Cal. 模式主动暂停 Group Auto；`startNightCalibration()` 没有做同等处理。因此 Night 的前置环境检查可能受到原有 LC Auto、当前灯具亮度、Manual Override 状态及传感器滤波残留的共同影响。

这使结果高度依赖用户点击 APPLY 的时刻：如果过渡曲线在 20 秒窗口内进入阈值则成功；如果仍在明显下降则失败。它把正常的“等待设备收敛”错误分类成了“环境不稳定”。

## 推荐优化

### P0：Night 从第一个受控灯光状态开始校准

推荐仅对 Night 模式跳过当前未受控的前置环境稳定门槛，完成初始化、Publish Delta 和 Sensor Publication 后，直接进入现有灯具拐点流程。

现有下一阶段的第一次 OFF 采样已经包含完整保护：

- 向 Group 发送明确的 Lightness；
- 等待最小 settle duration；
- 对全部必要灯具逐个执行 Lightness Status 到位确认，必要时使用 acknowledged unicast 补偿；
- 灯具确认到位后再进行稳定 Lux 轮询；
- 失败时仍走现有校准、Publication 和 Publish Delta 回滚。

因此这不是取消 Night 的稳定性保护，而是移除一个结果未被使用、且采样状态未受控的重复门槛。Plane/Sensor 仍可保留当前环境检查，避免扩大改动范围。

如果产品仍要求 Night 必须检查环境稳定性，应把检查移动到“明确固定灯具输出并确认到位”之后，而不是在当前未知灯光状态下进行。

### P1：补充 Night 的 Group Auto 生命周期管理

可以在 Night 开始前暂停 Group Auto，防止 LC 控制与校准 Lightness 指令竞争。但这项改动比 P0 风险更高，必须完整覆盖成功、普通失败、回滚失败、STOP/CANCEL、RETRY 和页面退出，并确认原始 Auto 状态只在配置完成后恢复。

单独发送 Group Unack 的 LC Off 不能证明所有灯具已经退出 Auto，所以即使实施 P1，也不应替代现有逐灯到位验证。

### P2：延长或自适应重试仅作为临时缓解

把 20 秒延长到 40～60 秒，或者对 Night 的 `ambientInstability` 增加一次继续采样，可以降低当前失败率，但会延迟真正的环境异常，并仍然保留无业务用途的前置门槛。若临时采用，还必须同步调整外层 30 秒 timer，否则外层可能先报 `noResponse`。

## 建议增加的诊断信息

- 为每个校准事件增加单调时间或相对耗时，便于准确区分 Mesh 往返与传感器收敛时间。
- Night 启动时记录 Group Auto 暂停状态、当前 Group/必要灯具 Lightness、最后一次 Lux 及其时间。
- 对跳过或移动后的环境门槛记录明确事件，区分“未受控前置检查”与“受控 Lightness 稳定检查”。

## 实施后的验收边界

1. 从低、中、高三种起始亮度，以及 Group Auto 正在调节的状态，各重复 Night Calibration 至少 10 次。
2. 每次必须进入首个 `light_verify_start`，不能再因未受控的 `stage=environment` 过渡直接失败。
3. 仍需验证每个 OFF/Target 采样的灯具到位、Lux 稳定窗口和三组差值一致性；不能仅看最终 ACK。
4. 验证普通失败、灯具离线、Publication 失败和 STOP/CANCEL 的回滚，不得残留临时 Publish Delta、Publication 或校准数据。
5. 分别确认 SDK `0x38` / `0x39` ACK、App Profile 保存与 Configuring 完成、Group Auto 恢复，以及真实灯具闭环行为。
6. SDK 改动后编译所有引用 NordicSigMeshSDK 的品牌 target；编译成功仍不代替真机 BLE Mesh 和照度闭环验收。

## 分析范围

本次仅分析日志和源码，没有修改 App/SDK 业务代码，也没有执行构建或真机测试。
