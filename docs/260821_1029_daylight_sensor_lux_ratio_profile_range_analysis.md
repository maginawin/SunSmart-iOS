# Daylight 传感器 Lux 直用、Ratio 与 Profile 范围分析

> 分析日期：2026-08-21  
> 工程范围：`new-calibration` worktree App 源码、本地 `NordicSigMeshSDK`、工程内 Sunricher Vendor 协议说明  
> SDK 快照：`timezone` 分支，提交 `cf1d0a7`  
> 外部协议依据：Bluetooth SIG Mesh Model 1.1 Light LC 规范  
> 验证方式：静态源码与协议分析；未进行固件源码核对、真机抓包、照度计对照或闭环稳定性测试

## 1. 结论摘要

### 1.1 ON/OFF 直接填写传感器 Lux 是否可行

**技术上可行，但它会把校准坐标系改成“传感器所在位置的 Lux”，不再代表外部 calibration point 的真实 Lux。**

如果 ON/OFF 输入值与 SDK 随后采到的同一传感器 ON/OFF 值完全一致，则理论结果是：

- `Sensor ratio = 1.0`，wire 值为 `100`；
- `Ambient light ratio = 1.0`，wire 值为 `100`。

因此，如果产品明确决定直接使用传感器 Lux，`Manual Correction` 中两个 ratio 都应设为 **`1.0`**。但采样存在时间差和波动，自动校准算出的值可能只接近 `1.0`；若要强制使用原始传感器坐标，应在校准完成后把两个 ratio 都保存为 `1.0`。

这不是无条件推荐方案。它只适用于以下产品定义：

- Profile 目标 Lux 就是传感器视场内的 Lux；
- 传感器安装位置、角度、遮挡和灯具布局固定；
- 不要求 Profile 的 500 lx 等数值代表桌面、地面或其他工作面照度。

如果产品仍希望 Profile 数值代表工作面实际照度，则 ON/OFF 应继续使用同一 calibration point 的外部照度计值，由 ratio 建立“传感器读数 → 工作面照度”的映射，不能直接复制传感器原始值。

### 1.2 大于 10000 lx 是否属于协议值过大

**不是。10000 lx 对当前协议编码并不大。**

- Bluetooth Mesh Light LC illuminance 使用 24-bit、0.01 lx 分辨率；当前 SDK 可编码的已知值范围为 `0...167772.14 lx`。
- 当前 App/SDK 的 daylight sensor、校准输入、Vendor 拐点和 Light LC Lux 缓存仍大量使用 `UInt16`，实际安全边界只有 `0...65535 lx`。
- 当前 Profile 的直接 Lux UI 固定限制为 `0...1500 lx`，这是 App 产品/UI 限制，不是 Light LC 协议限制。

所以 `10000+ lx` 暴露的是 **App 范围与协议/现场不一致**，不是 wire 格式容量不足。

### 1.3 Daylight Profile 的 occupancy level 最终发送什么

对已启用 daylight sensor 的 daylight Profile，最终发送的是 **Lux，不是亮度百分比**：

- `occupancyLevel` → `Light Control Ambient LuxLevel On`，Property `0x002B`；
- `vacantLevel` → `Light Control Ambient LuxLevel Prolong`，Property `0x002C`；
- `standbyLevel` → `Light Control Ambient LuxLevel Standby`，Property `0x002D`；
- 纯 `daylight` Profile 的 `taskLevel` 也作为 `Ambient LuxLevel On` 发送。

UI 中的 `Level (%)` 只是一个取样工具：App 先把 Group 调到所选百分比，等待约 3 秒，再读取 sensor Lux；保存和最终发送的仍是读取到的 Lux。百分比不会作为 daylight occupancy target 下发。

例外是 daylight 未启用/未校准时的 fallback：App 会暂时按百分比写 `Light Control Lightness On/Prolong/Standby`，避免未建立 Lux 闭环时直接依赖 Lux 目标。

### 1.4 当前范围是否对齐

**没有完全对齐。**

| 层次 | 当前范围/精度 | 结论 |
| --- | --- | --- |
| Bluetooth Mesh Light LC illuminance | uint24，0.01 lx；当前 SDK 已知值 `0...167772.14 lx` | 协议范围最大 |
| SDK Light LC 消息发送 | `Decimal` 编码为 3 bytes | 可发送协议范围内的值 |
| App Profile 数据模型 | `Int` | 模型本身未声明 Lux 上限 |
| Profile 直接 Lux UI | 整数 `0...1500 lx` | 远小于协议和现场需求 |
| `Level (%)` 取样路径 | 亮度 `0...100%`，结果保存为 sensor Lux | 可间接保存大于 1500 的 Lux |
| SDK daylight sensor 缓存 | `UInt16` | 只能可靠表示 `0...65535 lx` |
| SDK Light LC Lux readback 缓存 | `UInt16` | 只能可靠表示 `0...65535 lx` |
| 校准 ON/OFF 输入 | `UInt16` | `0...65535 lx`，且要求 ON > OFF |
| Vendor `0x38` Lux 字段 | `UInt16` | 拐点 Lux delta 最大 `65535` |
| 设备固件实际闭环范围 | 未知 | 必须真机与 firmware 确认 |

`0...1500` 是协议有效范围的子集，因此对小值“能发送”；但它不能覆盖实际项目中的高 Lux。另一方面，App 又能通过 `Level (%)` 路径保存超过 1500 的值，造成同一属性在两个入口的限制不一致。

## 2. 为什么传感器 Lux 直用时 ratio 是 1.0

当前 SDK 的计算为：

- `Ambient light ratio = OFF_input / OFF_sensor × 100`
- `Sensor ratio = (ON_input - OFF_input) / (ON_sensor - OFF_sensor) × 100`

如果输入框直接填写同一传感器的值：

- `OFF_input = OFF_sensor`
- `ON_input = ON_sensor`

则两个公式都得到 `100`。Vendor wire 的 `100` 表示 UI 中的 `1.0`。

校准初始化阶段也会先发送 ratio `100 / 100`，避免旧 ratio 影响新的 sensor 采样。因此从算法设计上看，“传感器原始坐标 + identity ratio”是成立的。

但需要注意三点：

1. 输入值与 SDK 内部采样不是同一个原子样本；自然光变化、灯具稳定时间和传感器滤波都会使结果偏离 100。
2. 自动校准还会计算并发送 `0x38` 拐点；把 ratio 设为 1.0 不等于绕过整个校准流程。
3. App/SDK 源码不能证明 firmware 最终发布的是原始 Lux、ratio 修正后的 Lux，或某个融合值；identity ratio 的结论来自当前算法字段语义，最终行为仍需固件/抓包验证。

### 2.1 Wire 格式

两个 ratio 通过 selected daylight sensor 的 Sunricher Vendor Model 单播写入：

- Vendor Set Opcode：`0xF0780A`；
- Vendor 主码：`0x31`，Daylight Sensor；
- 子码：`0x39`，Daylight Calibrate Rate；
- 参数顺序：`sensorRate: UInt16`、`ambientLightRate: UInt16`；
- 当前 Apple 运行环境按 little-endian 拼接 UInt16；
- 预期 ACK Opcode：`0xF3780A`，`ret = 0` 表示成功。

Vendor parameters 的字节布局为：

`31 39 [sensorRate low] [sensorRate high] [ambientLightRate low] [ambientLightRate high]`

UI 显示倍率与 wire 数值的关系为：

`wire ratio = UI ratio × 100`

| UI 显示倍率 | Wire 数值 | UInt16 bytes | 当前 Manual Correction 是否可设置 |
| ---: | ---: | --- | --- |
| 0.00 | 0 | `00 00` | 可，但不建议在 firmware 语义未确认时使用 |
| 0.05 | 5 | `05 00` | 自动校准可产生；Manual Correction 无法精确设置 |
| 0.10 | 10 | `0A 00` | 可 |
| 0.50 | 50 | `32 00` | 可 |
| 1.00 | 100 | `64 00` | 可，identity/default mapping |
| 2.00 | 200 | `C8 00` | 可 |
| 50.00 | 5000 | `88 13` | App 当前最大值 |

两个 ratio 都为 1.0 时，完整 Vendor parameters 是：

`31 39 64 00 64 00`

自动校准计算结果会限制到 wire `0...5000`。Manual Correction 显示范围对应 `0.0...50.0`，但步进只有 0.1，即 wire 步进 10；两者精度并不完全一致。

### 2.2 两个字段分别影响什么

| 字段 | 当前 App/SDK 计算含义 | 主要影响 |
| --- | --- | --- |
| `sensorRate` | `(ON_point - OFF_point) / (ON_sensor - OFF_sensor)` | 修正灯具开关造成的 sensor Lux 增量，使灯具贡献映射到 calibration point 坐标 |
| `ambientLightRate` | `OFF_point / OFF_sensor` | 修正关灯时自然光/背景光在 sensor 与 calibration point 之间的空间差异 |

它们直接写入的是 selected sensor，不是 Group，也不是每一台灯。其业务影响链路是：

1. selected sensor 保存/应用 `0x39` ratio；
2. sensor 通过 `Sensor Status` 向 Group 发布 Lux；
3. Light LC Server 用收到的 Ambient LuxLevel 与 Profile 的 occupancy/vacant/task Lux 目标做闭环调节；
4. 因此 ratio 会间接影响三个 daylight Profile 的自动调光结果：`occupancy_daylight`、`vacancy_daylight`、`daylight`。

它们不会直接修改：

- Profile occupancy/vacant/task Lux 目标；
- PIR occupancy detection、灵敏度或延时；
- 非-daylight Profile 的百分比亮度；
- Group 成员 Subscription；
- 灯具的 Light LC Property 配置。

`Manual Correction` 只重新发送 `0x39`，不会重新搜索或写入 `0x38` inflection point，也不会重新 Configuring Group。传感器位置、灯具数量或光学关系发生变化时，应重新执行完整 Calibration，不应只调整 ratio。

App/SDK 没有 firmware 内部实现，尚不能确认 `Sensor Status` 对 App 展示和 Group 发布的是原始 Lux 还是 ratio 修正后的 Lux。因此“ratio 改大后显示值一定按相同比例增大”等方向性行为不能仅凭当前源码保证，必须抓包验证。

### 2.3 应配置成什么值

没有一组 ratio 适合所有安装环境，配置规则应按目标坐标系选择：

| 使用方式 | Sensor ratio | Ambient light ratio | 建议 |
| --- | ---: | ---: | --- |
| 直接使用 sensor 原始 Lux | `1.0` / wire `100` | `1.0` / wire `100` | 两者使用同一 sensor 坐标，不做空间映射 |
| sensor 与 calibration point 实际读数一致 | 约 `1.0` | 约 `1.0` | 优先使用自动 Calibration 的实测结果 |
| Profile 表示工作面真实 Lux | 按 ON/OFF 增量公式计算 | 按 OFF 基准公式计算 | 推荐运行完整自动 Calibration，不手填通用常数 |
| 安装位置、灯具或光学已改变 | 不沿用旧值 | 不沿用旧值 | 重新完整 Calibration，包括 `0x38` 和 `0x39` |

工作面模式的 wire 计算公式是：

- `sensorRate = floor((ON_point - OFF_point) / (ON_sensor - OFF_sensor) × 100)`；
- `ambientLightRate = floor(OFF_point / OFF_sensor × 100)`；
- App 自动流程最终把结果限制到 `0...5000`。

不建议：

- 仅因为 sensor 全开超过 10000 lx，就把两个 ratio 一起按 `1500 / 10000` 设置；两个 ratio 的基准不同，不能合并计算；
- 把 ratio 当作 Profile occupancy Lux 上限或亮度百分比；
- 在没有 firmware 定义和真机结果时使用 `0`；
- 用 Manual Correction 保存 wire 不是 10 整数倍的自动结果，因为当前 UI 会量化精度。

### 2.4 `0x38` 与 `0x39` 如何组合为原始 Lux

**当前 App、SDK 和 Vendor 协议表不足以证明任何一组固定参数能得到“完全未经修正的原始 Lux”。**

已确认的边界是：

- `0x38` 写入两组“Lightness—Lux delta”点：minimum inflection point 和 maximum point；
- `0x39` 写入 lamp contribution ratio 与 ambient contribution ratio；
- 协议没有定义 `0x38` 的 bypass flag、raw mode 或 neutral sentinel；
- App/SDK 没有 firmware 内部组合公式；
- Vendor GET 当前只能查询 `0x36`、`0x37`、`0x3F`，不能读回 `0x38`、`0x39` 的真实设备值。

因此不能安全采用以下猜测：

- `0x38 = 0/0/0/0`；可能形成退化曲线、除零、饱和或被 firmware 拒绝；
- `0x38 = 0/0/FFFF/FFFF`；这只是人为构造一条 Lightness—Lux 曲线，不等于 raw bypass；
- 只发送 `0x39 = 100/100` 就宣称完全 raw；旧的 `0x38` 仍可能留在设备中。

当前唯一有 App 流程支持的 **identity-calibration 候选组合** 是：

1. 发送 `0x36 FFFF`，SDK 注释将其视为清空旧 calibration cache，但 Vendor 协议只称它为“底部值”，最终 reset 语义仍需 firmware 确认；
2. 发送 `0x39 100/100`，即 `31 39 64 00 64 00`，先取消旧倍率；
3. 使用 sensor 自身的实际采样建立 `0x38`：
   - `minLightness =` 第一个相对 OFF 基准至少增加约 2 lx 的扫描点；
   - `minLux = sensor(minLightness) - sensor(OFF)`；
   - `maxLightness = 0xFFFF`；
   - `maxLux = sensor(ON) - sensor(OFF)`；
4. 最终再次发送 `0x39 100/100`。

该组合的含义是：

- `0x38` 仍保存现场真实的灯具—sensor 响应曲线，而不是伪造 neutral curve；
- `0x39` 对 lamp 与 ambient 两部分都做 1:1 映射；
- 如果 firmware 的模型是“先用 `0x38` 分解 lamp/ambient，再分别乘 `0x39`，最后相加”，则理论输出会回到 sensor 原始 Lux；
- 但上述 firmware 公式并不在 App/SDK 中，所以这仍是待验证候选，不能标记为已确认 raw mode。

`0x36 FFFF + 0x39 100/100` 之后、`0x38` 写入之前，是 SDK 校准时最接近 raw sampling 的状态；SDK 正是在该阶段读取 OFF、扫描点和 ON Sensor Status。但这个中间状态不是完整的产品配置：App 不会保存完整 `sensorCalibrationData`，也不能据此证明重启后仍保持 raw。

要确认是否真正 raw，至少需要做以下 A/B 验证：

| 阶段 | 配置 | 记录 |
| --- | --- | --- |
| A | `0x36 FFFF` + `0x39 100/100`，尚未写 `0x38` | 固定环境与多个 Lightness 下的 Sensor Status，作为 raw candidate baseline |
| B | 写入现场实测 `0x38`，保持 `0x39 100/100` | 同样条件下的 Sensor Status |
| C | 完整断电重启 | Sensor Status、ratio/curve 是否持久化、daylight auto 是否恢复 |

若 A 与 B 在各采样点一致，且外部 firmware 说明确认 `0x39 = 1:1` 时 `0x38` 只用于分量拆解，则可以把上述组合认定为 raw-coordinate configuration。若 A/B 不一致，则必须由 firmware 团队提供 `0x38 + 0x39` 的精确公式，App 侧不能继续猜测。

## 3. 直接使用传感器 Lux 的业务含义

### 3.1 外部照度计模式

外部照度计模式希望建立：

`传感器安装位置读数 → calibration point / 工作面真实照度`

此时：

- Profile 中的 500 lx 可解释为工作面约 500 lx；
- sensor 因靠近灯具而读到 10000 lx 并不要求 Profile 也配置为 10000 lx；
- 自动计算出的 `Sensor ratio` 可能远小于 1.0，用来压缩灯具贡献部分；
- `Ambient light ratio` 独立处理关灯时环境底光的空间差异。

示例：

| 状态 | Sensor | 外部 calibration point |
| --- | ---: | ---: |
| OFF | 200 lx | 100 lx |
| ON | 10000 lx | 600 lx |

按当前公式：

- `Ambient light ratio = 100 / 200 = 0.5`，wire 值约 `50`；
- `Sensor ratio = (600 - 100) / (10000 - 200) ≈ 0.051`，wire 值约 `5`。

这说明 sensor 的高读数应优先通过真实空间校准映射处理，而不是把 Profile 上限直接等同于传感器全开读数。

当前 `Manual Correction` UI 的步进是 `0.1`，wire 步进是 `10`；自动校准可以产生 wire `5` 这样的更细结果，但 Manual Correction 无法精确重设 `0.05`。高倍率差现场会暴露这个精度问题。

而且 slider 初始化会把现有 wire ratio 除以 10 后转成整数。若自动校准值不是 10 的整数倍，例如 wire `5`，打开 Manual Correction 后 slider 实际只能落在 `0`；此时再保存可能把原值量化为 `0`。`Restore` 也只恢复弹窗打开时经过同样步进约束的值，不是固定恢复 `1.0`。因此低于 0.1 或需要 0.01 精度的 ratio 不应通过当前 Manual Correction 反复保存。

### 3.2 传感器原始值模式

如果两个 ratio 都固定为 1.0：

- Profile 目标必须按传感器实际读数配置；
- 同一个“500 lx”不再保证对应桌面 500 lx；
- 更换 sensor、改变朝向、加装灯罩或改变安装位置后，Profile 的既有 Lux 目标可能全部失去意义；
- 当 sensor 直视灯具时，Profile 可能需要数千或上万 Lux，当前 `0...1500` UI 就会直接成为阻碍。

因此这是产品坐标系选择，不应只作为规避 1500 上限的临时技巧。

## 4. 10000+ lx 与 1% 已超过 1500 lx 的处理

这两个现象必须分开判断。

### 4.1 只有全开读数高，但目标仍可达到

如果 100% 时 sensor > 10000 lx，但在某个较低输出仍可稳定达到目标，那么闭环本身可工作：

- 外部照度计模式：继续用工作面 ON/OFF Lux 校准，让 ratio 把 sensor 高读数映射到真实目标；
- 传感器原始值模式：Profile 需要允许输入现场真实的 sensor Lux；
- 不要把 occupancy Lux 转换为亮度百分比发送，因为 Light LC PI regulator 的目标输入本来就是 Lux。

对当前 App，`Level (%)` 路径可以作为现有取样入口：选择某个百分比后，App 会读取 sensor Lux，并可把大于 1500 的读数保存成 occupancy/task Lux。它证明数据链路并不必然受 1500 限制，但这个入口与直接 Lux 入口范围不一致，不能视为最终产品方案。

### 4.2 1% 的最小非零输出已超过目标

如果灯在最小非零输出时，反馈 Lux 已高于目标，例如：

- 0%：300 lx；
- 1%：2000 lx；
- 目标：1500 lx；

则目标位于灯具物理可达范围的“空档”中。无论 App 上限是 1500、10000 还是 65535，灯具都无法以稳定的非零输出维持 1500 lx。

此时可能出现：

- PI regulator 长期饱和在最低输出；
- firmware 在 off 与最小输出间反复切换；
- 照度持续高于目标；
- 调光抖动、闪烁或响应很慢。

当前校准算法的拐点搜索先扫描 25/50/75/95%，再以 5% 步进精扫，不能精确刻画 1% 附近的输出跳变。对“1% 已过亮”的灯具，`0x38` minimum inflection point 也可能只记录到 5% 附近，这需要列入设备验证。

应优先从物理和驱动可控范围解决：

- 确认驱动是否真的支持低于 1% 的连续调光，以及 Mesh lightness 到驱动输出的实际曲线；
- 降低单灯功率、减少同一控制区灯具数量或拆分 Group；
- 调整灯具光学、安装距离、遮光或扩散；
- 调整 sensor 位置/角度，避免直接看到光源导致局部读数远高于工作面；
- 保持 auto minimum lightness 为 0，允许 controller 在必要时关灯，但要真机确认 firmware 是否会产生 off/on hunting；
- 用照度计分别记录 0%、最小非零、5%、10%、100% 的 sensor 与工作面 Lux，先确认目标是否物理可达。

如果业务允许把目标提高到 2000 lx 以上，则放宽 App 范围能解决“不能输入”的问题；如果业务必须维持 1500 lx 以下，则放宽范围没有解决根因。

## 5. Daylight occupancy level 的实际发送链路

### 5.1 数据模型复用了 `level` 命名

`Profile.LightControlData` 的注释已经表明：

- `occupancyLevel` 是“第一阶段 level/lux”；
- `vacantLevel` 是“第二阶段 level/lux”；
- `taskLevel` 是 daylight 的环境光维持照度。

所以字段名不能单独证明单位，单位由 Profile type 和 daylight 是否启用决定。

### 5.2 已启用 daylight 时

`getNodeSyncProfiles()` 对 daylight Profile 执行以下转换：

| Profile 数据 | 同步项 | Light LC Property | 单位 |
| --- | --- | --- | --- |
| `occupancyLevel` | `occupancyLux` | `0x002B Ambient LuxLevel On` | lx |
| `vacantLevel` | `vacantLux` | `0x002C Ambient LuxLevel Prolong` | lx |
| `standbyLevel` | `standbyLux` | `0x002D Ambient LuxLevel Standby` | lx |
| `taskLevel` | `occupancyLux` | `0x002B Ambient LuxLevel On` | lx |

消息是 acknowledged `LightLCPropertySet`，Opcode `0x62`。SDK 把 App 的整数 Lux 放入 `.illuminance(Decimal(lux))`，再以 0.01 lx 分辨率编码为 3 bytes。

例如 App 值 `1500` 表示 1500 lx，不是 15.00 lx，也不是 15%。SDK 会把它编码成 150000 个 0.01 lx 单位。

### 5.3 UI 的 `Level (%)` 选择

当用户选择 `Level`：

1. slider 范围使用 `lowEndTrim...highEndTrim`，单位概念是亮度百分比；
2. App 向 Group 发送该百分比对应的 Lightness；
3. 等待约 3 秒；
4. 从 selected ambient sensor 读取 Lux；
5. 将读取到的 Lux 写回 `occupancyLevel` / `vacantLevel` / `taskLevel`；
6. 保存 Profile 后，仍按上一节的 Lux Property 下发。

因此当前 UI 的 `Level`/`Lux` 是“两种目标 Lux 的录入方法”，不是“两种设备侧目标单位”。

### 5.4 daylight 未启用时

daylight sensor 尚未校准或未启用时，App 会配置百分比 fallback：

- occupancy 使用 `highEndTrim`；
- vacant 使用 50%；
- standby 使用 0%；
- 纯 daylight 的 task fallback 使用 `highEndTrim`。

这部分写的是 `Light Control Lightness` Property。校准/启用后，App 才配置 Lux 目标并打开 daylight auto adjust。测试时必须区分“Profile 数据中保存了 Lux”与“设备当前正在按 Lux 闭环运行”。

## 6. 协议、SDK 与 App 范围分析

### 6.1 Bluetooth Mesh / SDK wire 范围

Bluetooth SIG Mesh Model 规定 Light LC Ambient LuxLevel 是 uint24，分辨率为 0.01 lx。工程当前 SDK 的 `DevicePropertyCharacteristic.illuminance`：

- 以 3 bytes 编码；
- 有效范围限制为 `0...167772.14 lx`；
- 把 `0xFFFFFF` 作为 unknown；
- 解码后返回 Decimal Lux。

因此从标准 Light LC Property 的 wire 表达看，1500 lx 不是上限。

### 6.2 当前 App/SDK 的 UInt16 收窄

工程在标准 24-bit Lux 之上又做了 UInt16 收窄：

- `Node.daylightLux` / `lastDaylightLux` / `steadyDaylightLux` 是 `UInt16`；
- `LightLCProperty.luxLevelOn/Prolong/Standby` 是 `UInt16`；
- 校准 manager 的 sensor Lux、ON/OFF 输入和 Lux delta 是 `UInt16`；
- Vendor `0x38` 的两个 Lux 字段也是 `UInt16`。

风险分成两种：

1. Sensor Status 使用 `NSNumber.uint16Value`，大于 65535 的 Lux 会发生低 16-bit 收窄，读数可能回绕而不是报错。
2. Light LC Property Status 使用 `UInt16(luxValue)`，大于 65535 的 readback 可能触发整数越界问题。

所以在不改 SDK 数据类型前，即使 wire 能表达 167772.14 lx，App 也不应宣称完整支持该范围。

### 6.3 当前可主张的范围

根据现有代码，可以分层表述：

- **App 直接输入已实现范围**：`0...1500` 整数 lx；
- **当前 App/SDK 端到端建议安全上限**：不高于 `65535` 整数 lx；
- **标准/SDK wire 可编码上限**：`167772.14` lx；
- **固件实际闭环上限**：未知，必须 readback 和真机验证。

其中“建议安全上限 65535”只表示类型容量，不代表应直接把 UI 产品范围扩到 65535。最终产品上限还应结合 sensor 量程、firmware 内部类型、灯具应用场景和输入体验确定。

## 7. 建议方案

### 7.1 先确定产品坐标系

必须先在产品/firmware/App 三方确认二选一：

1. **工作面 Lux 模式（推荐）**：ON/OFF 用外部照度计；Profile Lux 表示工作面目标；ratio 负责映射。
2. **传感器原始 Lux 模式**：ON/OFF 直接用 sensor；两个 ratio 固定 1.0；Profile Lux 表示 sensor 位置目标。

不能在不同 Group 或不同入口中隐式混用，否则相同的 occupancy 500 lx 会有不同物理含义。

### 7.2 对当前 1500 上限的最小修正方向

如果现场明确需要 10000+ sensor Lux，且短期不改完整 SDK：

- 统一 `occupancyLux`、`vacantLux`、`taskLux` 的直接输入与 `Level (%)` 取样结果范围；
- 上限应由产品/设备能力常量管理，不要继续散落硬编码 `1500`；
- 在 SDK 仍为 UInt16 时，上限不得超过 `65535`；
- 输入越界必须给出明确错误，不能像当前 calibration ON/OFF 那样静默返回；
- 保存前、导入时、同步前和 readback 时都要使用同一验证规则；
- 修改后同步检查所有共享 target，因为这些 Profile UI 和 Common 同步代码被多品牌 target 共用。

如果产品继续采用工作面 Lux，通常不需要把正常 UI 直接放到 65535；可选择更符合照明场景的范围，同时保留经过设备能力确认的高级输入方式。

### 7.3 完整协议对齐方向

若要声明支持完整 Light LC illuminance 范围，需要先完成：

- sensor Lux 与 Light LC Lux cache 从 `UInt16` 改成可表达 uint24/Decimal 的类型；
- 明确 `0xFFFFFF` unknown 的处理；
- 校准 Vendor `0x38` 仍是 UInt16，需定义标准 Lux 超过 Vendor 校准范围时的策略；
- 检查数据库、Codable、导入导出、云同步和多版本兼容；
- 修复 readback 的收窄/越界；
- 对 firmware 的真实范围、饱和和 NVM 精度做设备验证。

### 7.4 Manual Correction 精度

当前 Manual Correction：

- 范围 `0.0...50.0`；
- UI 步进 `0.1`；
- wire 步进 `10`；
- 自动校准本身可以产生 wire 步进 `1`。

如果 sensor 与工作面差异可能达到 10000:500 这种量级，应把 Manual Correction 的最小步进需求纳入产品设计，否则自动计算出的 `0.05` 无法通过 UI 精确恢复或微调。

## 8. 推荐真机验证矩阵

| 场景 | 需要记录 | 通过条件 |
| --- | --- | --- |
| Identity ratio | 同一 sensor 的 OFF/ON 输入、SDK 内部 OFF/ON、最终 `0x39` | 两个 ratio 接近或等于 100；发布 Lux 行为可解释 |
| 外部点低倍率 | sensor 约 10000、工作面约 500 | 自动 ratio 可小于 0.1；工作面闭环接近目标 |
| Profile 直接输入 >1500 | App 保存值、`0x62/0x002B` payload、Property Status | 值按 Lux 发送并 readback 一致 |
| `Level (%)` 取样 >1500 | 亮度命令、Sensor Status、Profile 保存值、下发值 | 取样值与最终 Lux Property 一致，不被裁剪到 1500 |
| 1% 输出过亮 | 0%、最小非零、5%、10%、100% 的 sensor/工作面 Lux | 明确目标是否可达，无 off/on hunting 或闪烁 |
| 65535 边界 | Sensor Status 与 Light LC Property Status | 65535 正确；65536 不允许进入旧数据链路或已完成类型升级 |
| 断电恢复 | ratio、`0x38`、Lux target、auto 状态 | 重启后保持且闭环恢复 |
| 多品牌 target | SunSmart、Archipelago、SLG Sync Plus、SylSmart | Profile UI、同步和本地化行为一致 |

## 9. 最终回答

1. **可以直接使用 sensor Lux，但这是把整个系统定义成 sensor-coordinate Lux。** 这时 `Sensor ratio` 和 `Ambient light ratio` 都设为 `1.0`，wire 值都是 `100`。
2. **如果需要工作面真实 Lux，不应直接使用 sensor Lux。** sensor 10000 lx 可以通过自动 ratio 映射到工作面 500 lx；这正是当前双 ratio 校准的用途。
3. **10000+ 不超过当前 UInt16 链路，1500 是 App UI 限制。** 当前直接 Lux 输入与 `Level (%)` 取样入口没有对齐。
4. **daylight occupancy level 最终发送 Lux。** `Level (%)` 只是先调光再取 sensor Lux，最终仍写 `Light Control Ambient LuxLevel On`。
5. **协议/SDK wire 支持远大于 1500 的 Lux，但当前 App/SDK cache 只安全到 UInt16。** 在未升级类型前，不能按完整 uint24 范围宣称支持。
6. **若 1% 已高于所需目标，根因是闭环目标物理不可达。** 放宽 Profile 上限只能允许设置更高目标，不能解决低目标过亮；需要处理驱动最小输出、灯具分区/功率、光学和 sensor 安装位置，并验证 firmware 在输出下限处的行为。

## 10. 主要证据索引

### App

- `SunSmart/Main/Group/Controller/LightSensorCalibrationViewController.swift`
  - ON/OFF `UInt16` 校验与 calibration 调用；Manual Correction 写 ratio。
- `SunSmart/Main/Group/View/LightSensorManualCorrectionView.swift`
  - ratio 显示、范围、步进和 wire 换算。
- `SunSmart/Main/Profile/Controller/ProfileSettingsViewController.swift`
  - `Level (%)` 控灯后读取 sensor Lux，并把 Lux 写回 Profile。
- `SunSmart/Main/Profile/View/ProfileLevelSettingsView.swift`
  - daylight Lux 直接输入默认范围 `0...1500`。
- `SunSmart/Main/Profile/Model/Profile.swift`
  - `occupancyLevel` / `vacantLevel` 的 level/lux 复用数据模型。
- `SunSmart/Common/Data/Node+SyncData.swift`
  - daylight Profile 的 level → lux 同步分支及未校准 fallback。
- `SunSmart/Common/Data/Node+MessageHandles.swift`
  - `occupancyLux` / `vacantLux` / `standbyLux` 到 Light LC Property 的消息映射。
- `SunSmart/sunricher_protocol_vendor.md`
  - Vendor `0x38` / `0x39` 的 UInt16 字段定义。

### NordicSigMeshSDK

- `MeshLib/Manager/MeshSensorCalibrateManager.swift`
  - ratio 公式、0...5000 clamp、UInt16 校准数据、5% 拐点精扫。
- `MeshLib/Node/Node+Messages.swift`
  - Sensor Status 与 Light LC Property Status 的 Lux 缓存收窄。
- `MeshLib/Node/Node+Propertys.swift`
  - `daylightLux` 与 `luxLevelOn/Prolong/Standby` 的 UInt16 类型。
- `nRFMeshProvision/Mesh Messages/DeviceProperty.swift`
  - illuminance 24-bit、0.01 lx、`0...167772.14` 编解码。
- `nRFMeshProvision/Mesh Messages/Lighting/LightLCPropertySet.swift`
  - Opcode `0x62` 与 Property Value 编码。

### Bluetooth SIG

- [Mesh Model Specification 1.1 - Light LC](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/MMDL_v1.1/out/en/index-en.html)
  - Light LC Ambient LuxLevel、Ambient LuxLevel On/Prolong/Standby 与 PI Feedback Regulator 定义。

## 11. 证据边界

当前可以从源码和标准确认：

- ratio 的 App/SDK 计算方式和 wire 值；
- daylight Profile 最终使用 Lux Property；
- 标准与 SDK 的 wire 表达范围；
- App 1500 UI 限制和 UInt16 收窄风险。

当前不能仅凭 App/SDK 确认：

- Sunricher firmware 如何组合两个 ratio 与 `0x38` 拐点；
- Sensor Status 发布的是原始还是校准后 Lux；
- firmware 对大于 1500、10000、65535 的实际存储和闭环行为；
- 1% 输出过亮时 firmware 会饱和、关灯还是振荡；
- ratio、拐点和 Light LC Property 的断电持久化精度。

这些项目必须通过 firmware 规范、Vendor readback、Mesh 抓包、外部照度计和实际灯具曲线补齐。
