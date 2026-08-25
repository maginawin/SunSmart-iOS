# Night Calibration Log 成功性分析

## 结论

这份 Log **符合当前 Night Cal. 的 SDK 算法与协议成功条件**，可以判定 selected daylight sensor `L2 / 0x008F` 的 Night 参数阶段真实走到了 SDK 成功出口：三台必要灯具均已确认到位、Lux 稳定采样有效、三组 OFF→Target 结果有效、`0x38` 与 `0x39` 均收到成功 ACK、publish delta 也已从临时值 `1` 成功恢复为 `5`。

但它还不能单独证明 Calibration 页整条业务链和最终照明效果都成功。当前 Log 截止于 SDK 成功回调之前的最后一项设备参数确认，没有覆盖随后由 App 执行的 Sensor Publication 提交、Profile 保存、Group member Configuring、Group Auto 恢复和运行时 Light LC 闭环。

因此应分层判定：

| 层级 | 本次结论 |
| --- | --- |
| SDK Night 采样与 selected sensor 参数写入 | 成功 |
| selected sensor 参数命令获得设备成功 ACK | 成功 |
| App Publication、Profile 与全部灯具 Configuring | 当前 Log 无法确认 |
| Group Auto 命令实际生效 | 当前 Log 无法确认 |
| firmware NVM、断电保持与真实闭环效果 | 当前 Log 无法确认 |

## 1. 输入与前置准备符合要求

- App 与 SDK 均记录 `mode=night`、sensor `L2 / 0x008F` 和 `targetBrightnessPercent=100`，输入一致。
- `100%` 位于 SDK 的 `1...100` 有效范围，也位于本次灯具记录的 `655...65535` Lightness Range 上限内。
- SDK 使用 `pairCount=3`，符合三组 OFF→Target 配对采样要求。
- Night 使用 identity rate，`sensorRate=100`、`ambientLightRate=100`，符合 Night 不使用外部照度计倍率的当前设计。
- 校准开始时 publish delta 临时设为 `1`，第一次 ACK 即成功，且 `codeMatches=true`，说明响应类型和成功状态均匹配。

## 2. 环境和每个灯光点均达到稳定条件

### 2.1 初始环境

初始环境样本为 `[44, 44, 44, 44]`，稳定代表值为 `44 lx`。窗口无波动，符合稳定要求。

### 2.2 必要灯具到位

本轮明确要求 `0x008C`、`0x008F`、`0x0092` 三台灯具参与。所有采样点均逐台出现：

- `present` 等于按各节点 Lightness Range 计算后的 `expected`；
- `target=<nil>`，表示已无待完成 transition，当前实现允许以已到位的 present 值通过；
- `attempt=0 success=true`，说明首次 GET 即确认到位，没有依赖修复重发；
- 每一轮最后均有 `light_verify_complete ... success=true`。

`requested=0` 时虽然日志仍显示节点非零 Range `655...65535`，但当前实现对 OFF 特殊处理，期望值固定为 `0`，所以 `expected=0 present=0` 是正确结果，不是 Low End Trim 校验漏洞。

### 2.3 曲线采样

本轮曲线关键点为：

| 采样点 | 稳定代表值 | 说明 |
| --- | ---: | --- |
| 0% | 44 lx | 初始 OFF 基线 |
| 25% | 116 lx | 粗搜索首次发现明显灯光影响 |
| 5%，Lightness 3276 | 64 lx | 精细搜索得到最小拐点 |
| 100%，Lightness 65535 | 297 lx | 最大曲线点 |

先采 25% 再回到 5% 是当前“分段粗搜索后按 5% 步进精搜”的正常顺序，不是亮度控制乱序。

各阶段的样本均先经历对应上升或下降趋势，再形成最近四个样本的稳定窗口。没有 `lux_stable_timeout`、`light_verify_complete ... success=false` 或 `failed`。

## 3. Night 三组配对计算正确

三组结果为：

| 组次 | OFF | Target 100% | 配对差值 |
| --- | ---: | ---: | ---: |
| 1 | 45 | 295 | 250 lx |
| 2 | 45 | 296 | 251 lx |
| 3 | 45 | 297 | 252 lx |

计算结果：

- 每组 Target 都大于 OFF；
- 每组差值都远高于当前最小有效差值 `2 lx`；
- 三组差值极差为 `252 - 250 = 2 lx`，小于当前允许的 `10 lx`；
- 平均值为 `(250 + 251 + 252) / 3 = 251 lx`；
- Log 中 `targetLux=251` 与计算完全一致。

OFF 三次均为 `45 lx`，Target 三次为 `295/296/297 lx`，重复性良好。它们与前面的曲线 OFF `44 lx`、100% `297 lx` 只有 `1~2 lx` 差异，属于当前稳定窗口允许范围内的一致结果。

## 4. 0x38 曲线写入正确

Log 给出的曲线参数为：

- `sensorOffLux=44`；
- 最小拐点：Lightness `3276`、稳定 Lux `64`，所以 `minLuxDelta=64-44=20`；
- 最大点：Lightness `65535`、稳定 Lux `297`，所以 `maxLuxDelta=297-44=253`。

Payload `3138CC0C1400FFFFFD00` 可对应为：

| 字段 | 小端字节 | 数值 |
| --- | --- | ---: |
| function | `31 38` | Daylight `0x38` |
| minLightness | `CC 0C` | 3276 |
| minLuxDelta | `14 00` | 20 |
| maxLightness | `FF FF` | 65535 |
| maxLuxDelta | `FD 00` | 253 |

随后出现 `ack_0x38 ... success=true`，说明设备对本次 selected sensor 单播参数写入返回成功状态。

`0x38` 的 `20/253` 与 Night `targetLux=251` 不应相等：前者描述灯具—传感器曲线的最小/最大增量，后者是三组 OFF→Target 差值的平均，后续写入 Profile 作为运行时目标 Lux。

## 5. 0x39 与最终成功门槛正确

- `0x39` 使用 identity ratio：`100/100`；
- Payload `313964006400` 中两个 UInt16 小端数值均为 `100`；
- `ack_0x39 ... success=true`；
- 最后 publish delta 从临时值 `1` 恢复为默认值 `5`，第一次尝试成功，且 `codeMatches=true`。

当前 SDK 只有在 publish delta 恢复成功后才调用 Night 成功回调。最后一条 `delta=5 attempt=1/3 success=true codeMatches=true` 因此证明本轮已通过 SDK 的最后成功门槛；不存在“0x38/0x39 成功但 cleanup 失败却仍误报成功”的情况。

## 6. 为什么还不能把它称为 Calibration 页完整成功

SDK 成功回调后，App 还会依次执行：

1. 把 selected sensor 的 Sensor Publication 提交到当前 Group，并在必要时关闭旧 sensor 的 Publication；
2. 将 `targetLux=251` 保存到 Profile：纯 daylight 写 `taskLevel`，带 occupancy 的 daylight Profile 写 `occupancyLevel`；
3. 保存 `targetNightBrightness=100` 和 `calibrationMode=nightCal`；
4. 对 Group member 执行 Configuring；
5. 只有全部待配置节点成功，或失败后 RETRY 最终全部成功，才发送 Group Auto On。

提供的 `[DaylightCalibrationDebug]` 没有记录以上 App 层结果。即使页面已经显示 Active Night，也只表示本地校准算法状态，不等于所有 Group member 已同步完成。Group Auto On 本身还是 unacknowledged 消息，因此“App 已发送”也不能单独证明设备运行态已经切回 Auto。

## 7. 最终现场判定标准

若当时页面随后满足以下条件，可以把本轮进一步判定为 App 层成功：

- Configuring 的 Completed 覆盖全部待配置节点；
- Failed 为 0，没有 STOP/CANCEL，或失败后的 RETRY 最终全部成功；
- 页面完成态显示 `Target level = 251 lx`、`Set at 100% brightness`，且无 pending devices；
- Group Auto 已恢复，Group 页面无需再次手动点 AUTO。

若要称为最终真机成功，还需补充：

- 抓包或设备侧 readback 证明 Profile Lux 与相关 Light LC Property 已写入各灯具；
- 环境光变化时实际亮度能稳定闭环到约 `251 lx`，没有振荡、闪烁或长期异常饱和；
- 传感器和灯具断电重启后 `0x38/0x39`、Profile 和 Auto 行为仍保持；
- firmware 团队确认 ACK 表示参数已正确应用并按预期持久化，而不是仅接收命令。

## 8. 当前源码核对与自动检查

- App 当前通过本地路径引用 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk`；本次核对的 SDK HEAD 为 `6327881`。
- `NightCalibrationWorkflowContractTests`：通过。
- `NightCalibrationPersistenceContractTests`：通过。
- 本次仅新增分析文档，未修改 App 或 SDK 业务代码，未执行构建。

