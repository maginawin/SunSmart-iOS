# Daylight Calibration 三种模式诊断日志

## 结论

Calibration 页面原本没有可统一过滤的完整日志。旧日志仅覆盖部分转折点搜索过程，并在 Plane `0x39` 成功响应后打印一次倍率，无法把页面输入、SDK 接收、传感器实测、倍率计算和最终协议 payload 串联起来，也没有覆盖 Night/Sensor 的完整链路。

ON Lux、OFF Lux 也不会以两个原始 Lux 字段直接写入设备。Plane Calibration 的实际流程是：

1. App 将外部照度计的 ON Lux、OFF Lux 传给 SDK。
2. SDK 控制灯具并读取传感器的 ON Lux、OFF Lux。
3. SDK 计算传感器曲线差值，使用 Vendor `0x38` 下发拐点数据。
4. SDK 用外部照度计差值与传感器差值计算倍率，使用 Vendor `0x39` 下发 `sensorRate` 和 `ambientLightRate`。

因此，判断“ON/OFF Lux 下发是否正确”时，需要同时检查原始输入和最终 `0x38`、`0x39` 数据，不能只检查页面输入值。

## 本次改动

新增统一过滤标签：

`[DaylightCalibrationDebug]`

日志事件如下：

| event | 含义 | 关键字段 |
| --- | --- | --- |
| `app_start` | App 页面通过校验并开始校准 | mode、节点、地址及模式特有输入 |
| `sdk_input` | SDK 已收到 App 参数 | mode、节点、地址及倍率策略 |
| `send_0x38` | 即将下发传感器拐点 | 实际目标地址、传感器 ON/OFF Lux、拐点、差值、完整 payload |
| `ack_0x38` | `0x38` 响应结果 | 成功或失败 |
| `night_result` | Night 稳定采样与目标照度计算完成 | OFF/目标亮度采样、每组差值、最终目标 Lux |
| `send_0x39` | 即将下发校准倍率 | 实际目标地址、传感器 ON/OFF Lux、倍率策略、两个倍率、完整 payload |
| `ack_0x39` | `0x39` 响应结果 | 成功或失败、两个倍率 |
| `invalid_rate_input` | Plane 外部或传感器 ON/OFF 差值无效 | 四个 Lux 原始值 |
| `failed` | 校准失败 | mode、错误、模式特有输入及传感器 ON/OFF Lux |

日志使用固定英文 Key，便于 Xcode Console、Console.app 或导出日志后过滤。未修改用户可见文案，不涉及国际化资源。

## 三种模式覆盖

- Plane：`app_start` 和 `sdk_input` 记录外部照度计 ON/OFF Lux；`0x39` 记录计算出的倍率。
- Sensor：`app_start` 记录目标 Lux 和 Dim level；SDK 使用传感器自身曲线，`0x39` 固定下发 100%/100% identity 倍率。
- Night：`app_start` 和 `sdk_input` 记录目标亮度；`night_result` 记录稳定采样结果；`0x39` 固定下发 100%/100% identity 倍率。

三种模式都输出 `app_start → sdk_input → send_0x38 → ack_0x38 → send_0x39 → ack_0x39`。任何模式失败均输出 `failed`；只有 Night 额外输出 `night_result`，只有 Plane 可能输出 `invalid_rate_input`。

## Plane 计算关系

- 外部照度差值：`ambientOnLux - ambientOffLux`
- 传感器照度差值：`sensorOnLux - sensorOffLux`
- `sensorRate`：外部照度差值 / 传感器照度差值 × 100，SDK 当前上限为 5000
- `ambientLightRate`：外部 OFF Lux / 传感器 OFF Lux × 100，SDK 当前上限为 5000

协议 payload 使用项目现有 `Data` 编码直接打印十六进制，能够辅助核对 UInt16 字段顺序和大小端。

## 改动边界

- App：在 Plane、Night、Sensor 正式调用 SDK 前打印各自输入。
- SDK：只在现有校准状态机关键边界增加日志。
- 未调整 ON/OFF 校验、采样逻辑、计算公式、取整、倍率上限、Vendor 命令或失败恢复行为。

## 验证边界

静态契约和 iOS 构建可验证日志字段存在及代码可编译，但不能证明真机传感器采样、BLE Mesh 实际空口包、固件 ACK 内容或固件应用倍率后的闭环效果。真机排查时应保留从 `app_start` 到 `ack_0x39` 的完整同一轮日志；如果功能失败，也应保留 `failed` 及其之前最后一个事件。

## 自动验证结果

- `scripts/check_sensor_calibration_workflow.sh`：通过。
- App 工作区与本地 SDK 仓库 `git diff --check`：通过。
- `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart`：Debug、iphoneos、无签名构建全部通过。
- 构建仍有工程既有的资源符号重名、旧 API、重复 Compile Sources 和 Info.plist Copy Bundle Resources 警告；本次未扩大范围处理。
- 未执行真机 Calibration、BLE Mesh 抓包、固件 ACK 语义或校准后闭环 Lux 验收。
