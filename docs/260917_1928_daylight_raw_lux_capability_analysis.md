# Daylight 校准前后 Lux 与原始硬件读数能力分析

日期：2026-09-17。范围：当前 App `fix` / `24037dd3`；本地 SDK `one-dev` / `a971027`。分析开始时两者均无未提交改动。

本地入口为 `SunSmartLocal.xcworkspace`，`.local-sdk/nordic-sig-mesh-sdk` 实际指向 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`。本次仅静态分析和标准查证，不修改业务代码，不构建，不操作设备。没有目标设备型号、固件版本、固件源码或本次抓包，不能认证所有现有固件的具体行为。

## 结论

- 当前设备行始终显示设备上报的 `Present Ambient Light Level (0x004E)` 经 SDK 整数化、平滑后的值。校准前后没有切换属性，也没有 App 侧的工作面校准换算。
- Plane 校准意图是将传感器读数映射到工作面；Sensor/Night 校准保持两个倍率均为 1.0，意图保留传感器照度坐标。三者都会写灯光曲线。因此不能笼统地说所有“校准后 Lux”都是工作面 Lux，也不能把 1:1 倍率等同于已确认的硬件 bypass。
- 已检查的 SDK API 和仓库 Vendor 协议表没有独立的实时 raw Lux 读取接口。保持现有校准运行、同时增加一份原始 Lux，当前没有已确认可直接接入的通道。固件是否有未公开接口，需要设备团队按型号/版本确认；不能仅凭 SDK 缺少 API 宣称固件绝对不支持。
- SIG Mesh 可以承载这样的功能，但标准 `Sensor Get` 没有“忽略校准”参数。推荐固件提供独立、只读的 Vendor 查询，保留现有 `0x004E` 对 Light LC 的反馈语义。

## 当前显示链路

实际入口是 Group 的 daylight sensor 设置 → `LightSensorCalibrationViewController` → `LightSensorCalibrationSelectView` 的 `Sensor reading`。不是同名的 Day/Night 条件阈值列表。

1. Controller 每秒通过 `MeshAPI.getAmbientSensorValue(node:result:nil)` 请求选中传感器。
2. SDK 发送 `SensorGet(.presentAmbientLightLevel)`，仅指定 `0x004E`。
3. `DeviceProperty` 按 24-bit、0.01 lx 的格式解析为 Illuminance。
4. `Node+Messages` 将该值存入 `daylightLux: UInt16`，旧样本存入 `lastDaylightLux`；这里不应用 `sensorRatio` 或 `ambientlightRatio`。
5. 设备行和 Manual Correction 使用 `steadyDaylightLux`。算术意图为 `(当前样本 × 10 + 上一样本 × 990) / 1000`，结果取整数；这是两个相邻样本的加权，不是以历史平滑值递归计算。

因此要区分三个值：硬件/固件校准前的测量值、Mesh 回包中解码出的照度、App 平滑显示值。改用 `daylightLux` 最多去掉 App 平滑，不能去掉固件已经应用的校准；而且该缓存已丢失协议的小数精度。

有效回包后读数变绿，3 秒没有新回包转灰；颜色表示新鲜度，不表示校准状态。校准和配置期间页面轮询暂停。校准结束初期，缓存及相邻样本平滑可能短暂混合旧状态读数，不宜用第一帧判断换算结果。

Profile 的 Task/Occupancy Lux 是控制目标，不是实时读数；其中通过亮度百分比取样设置目标时，同样调用 `getAmbientSensorValue`，并不会额外取得 raw Lux。

## 校准前后的区别

| 状态 | 当前 App/SDK 已证实的动作 | 读数应如何理解 |
| --- | --- | --- |
| 首次校准前 | 直接读取当前 `0x004E`，显示路径不主动重置设备 | 设备当前上报照度；只有设备确实没有现场修正时，才可视为未做现场校准的传感器照度。App 显示“未校准”不独立证明设备内部无历史参数 |
| 校准采样阶段 | 先发 Vendor `0x31/0x36 = FFFF`，再发 `0x31/0x39 = 100/100` | SDK 意图清除旧校准影响后采样；`FFFF` 的完整固件 reset 语义仍需确认 |
| Plane 完成 | 写 `0x38` 曲线和计算出的 `0x39` 两个倍率 | 设计意图是工作面/校准点坐标。若固件按此模型修正并上报 `0x004E`，页面随之显示修正后的值；App 源码不能单独证明固件发布公式 |
| Sensor 完成 | 写 `0x38` 曲线；`0x39` 固定 `100/100` | 意图保持传感器坐标，用户输入的是该坐标下目标 Lux；不是按外部照度计做空间映射 |
| Night 完成 | 同样写曲线及 `100/100`；由目标亮度与关灯读数的差值生成目标 Lux | 实时设备行仍读 `0x004E`。Night 目标采用 delta，不代表页面也会减去关灯值 |

Plane 的两个倍率在 SDK 中为：

- 灯光贡献倍率：`(工作面 ON − 工作面 OFF) / (传感器 ON − 传感器 OFF)`。
- 环境光倍率：`工作面 OFF / 传感器 OFF`。
- wire 值为倍率乘 100，经 SDK 的边界处理；wire `100` 表示 1.0。

当前三种模式的 `0x38` 都写入相对关灯基准的照度增量。仓库协议表仅称其为“步骤照度”，没有定义固件内部组合公式或 raw bypass。Sensor/Night 的 identity 设置可说明产品意图，不能证明输出与光感芯片内部读数逐点完全一致。

此外，校准过程中会主动改变灯光，结束后恢复 Auto 也可能改变灯光。前后数值变化不一定全由校准倍率造成；比较必须固定自然光及实际灯光输出。

## 当前固件接口证据与局限

SDK `SunricherVendorGet` 和 `SunSmart/sunricher_protocol_vendor.md` 中，AMB 主码 `0x31` 的 GET 为：

| 子码 | 内容 | 是否为实时 raw Lux |
| --- | --- | --- |
| `0x36` | 校准/底部值 | 否，配置参数 |
| `0x37` | 上报门限 | 否 |
| `0x3F` | 当前条件/场景 | 否 |

`0x38`、`0x39` 是曲线和倍率的 SET；已检查表/API 没有它们的读取入口，更没有独立实时原始照度 GET。条件配置中的 `useCalibrationValues` 用于条件判定选择，也不是 `Sensor Get` 的原始读数开关。

不能用以下方式冒充“保留校准，同时读取原始 Lux”：

- 每次读数前暂时写 `100/100` 再恢复：这是修改设备运行校准，会影响期间发布给 Light LC 的反馈，也引入恢复失败风险。
- 只把 UI 从 `steadyDaylightLux` 换成 `daylightLux`：只能取消 App 平滑。
- 用单个倍率除回去：Plane 有两种贡献倍率和灯光曲线，缺少经确认的固件公式、实时分量与精度信息，不能无损反推。
- 将 ON/OFF 历史校准样本当作实时原始 Lux：历史样本不能代表当前环境。

这里的“原始硬件 Lux”建议定义为：芯片读数经必要的单位转换/出厂补偿之后、应用现场 daylight 曲线与空间校准之前的 lx。若需求是 ADC/register count，应单独定义单位，不能标为 lx。

## SIG Mesh 层面的支持

[Mesh Model 1.1](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/MMDL_v1.1/out/en/index-en.html) §4.1.4、§4.2.13–14 定义了传感器属性、数据编码及 Get/Status。`Sensor Get` 只有可选 Property ID；`Sensor Raw Value` 是属性编码字段名称，不保证它来自校准前硬件。省略 Property ID 可读取该 Element 暴露的所有属性，但不会使设备暴露原本没有实现的读数。

[Ambient Light Sensor NLC Profile 1.0](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/ALSNLCP_v1.0/out/en/index-en.html) §3.5 明确把上报照度与内部测量、Sensor Gain 联系起来，并规定校准设置。这说明标准照度可以是校准结果。该标准不能证明当前采用 Sunricher 双倍率 Vendor 流程的固件实现了 Sensor Gain 设置。

结论分为两层：标准读数接口没有通用的 bypass 开关；Mesh 可以通过 Vendor Model 增加独立 raw Lux Get/Status。若考虑标准 Sensor Model 的额外属性/Element，需要另行设计属性语义和合规映射，不能随意占用保留 Property ID。尤其 NLC Ambient Light Sensor 对其 Sensor Server 的属性集合有限制，不能简单在同一模型上随意追加一个自定义 raw 属性并声称标准兼容。

## 建议与最短确认路径

1. 先让固件团队按目标产品及版本确认：`0x004E` 的 Get 回复与主动发布分别位于校准链的哪一阶段；`0x38 + 0x39` 的公式；`100/100` 是否保证恒等输出；是否已有只读 raw 查询及其命令、格式、支持版本。
2. 已有接口时补 SDK 解码与 App 独立字段；没有时新增只读 Vendor 查询。建议同一响应带同一次采样的 raw/校准后照度及有效状态，避免两次查询的环境变化被误判为校准差异。具体子码由固件协议分配，本次不预占。
3. raw 查询不得改写校准或影响现有 `0x004E` 的控制反馈。UI 可分开标为 `Raw sensor lux` 与 `Calibrated lux`；只有语义确认的机型才这样命名。
4. 用户/固件团队验收时，在固定自然光、固定实际输出下对比校准前后 `0x004E` 与固件内部原始值，再验证新 raw 查询不改变校准和 Auto 行为。覆盖 Plane 非 1.0 倍率以及 Sensor/Night 1.0 倍率即可针对本需求取得关键证据。

## 主要代码定位

- App：`SunSmart/Main/Group/Controller/LightSensorCalibrationViewController.swift` 的 `requestSelectedSensorLux` 调用链（实际轮询最终调用 `getAmbientSensorValue`）、`didReceiveMessage`、三种校准入口；`SunSmart/Main/Group/View/LightSensorCalibrationSelectView.swift` 的设备行刷新。
- SDK：`MeshLib/MeshAPI.swift` 的 `getAmbientSensorValue`；`MeshLib/Node/Node+Messages.swift` 的 SensorStatus 处理；`MeshLib/Node/Node+Propertys.swift` 的 `daylightLux` / `steadyDaylightLux`。
- SDK：`MeshLib/Manager/MeshSensorCalibrateManager.swift` 的初始化、`setCalibrateRate`、`setIdentityCalibrateRate`、`nightCalibrationResult` 及 `0x38` 写入。
- SDK：`MeshLib/Message/Vendor/SunricherVendorGet.swift`；`nRFMeshProvision/Mesh Messages/Sensors/SensorGet.swift`；`nRFMeshProvision/Mesh Messages/DeviceProperty.swift`。

验证范围：当前源码、协议表和 Bluetooth SIG 公开规范交叉核对。未验证具体固件运行行为；无需因分析文档执行 App 构建。
