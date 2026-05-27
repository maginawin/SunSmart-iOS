# Power Switch AppKey Bind 设计

## 背景

当前 AC Power Switch 与 Battery Power Switch 添加成功后的 AppKey 绑定集合不一致。已有分析见 `docs/260527_2059_ac_vs_battery_power_switch_appkey_bind_analysis.md`。

根因是本地 `NordicSigMeshSDK` 把“按键 Profile Client Models 遍历所有 element 收集并绑定”的逻辑挂在 Battery Power Switch 判断下，而 Battery 判断依赖 `Generic Battery Server (0x100C)`。AC Power Switch 没有 Battery Server，因此不会进入完整 all-elements bind 路径。

本设计采用方案 1：在 SDK 内新增 Power Switch profile 判断，通过 PID 识别 Battery / AC Power Switch，共用基础 5 个按键 Client Models 的 all-elements bind 逻辑；Battery Server 仅作为 Battery 设备额外处理。

## 目标

- AC Power Switch PID `0x2A11` / `0x2A12` 添加成功后，基础 5 个共同按键 Client Models 必须与 Battery Power Switch 使用同一把当前 AppKey，并覆盖所有实际存在的按键 element。
- Battery Power Switch PID `0x2A01` / `0x2A02` 保持现有基础 5 个共同按键 Client Models 的 all-elements bind 行为。
- Battery Power Switch 继续把 `Generic Battery Server (0x100C)` 作为额外 required model。
- AC Power Switch 的基础 5 个共同按键 Client Models 任一 bind 失败时，添加流程应按失败处理，并 reset/delete node。

## 非目标

- 本轮不扩展到协议建议的扩展 5 个 Client Models。
- 本轮不调整 vendor key config、publication、subscription 或虚拟设备配置逻辑。
- 本轮不改 App 层 AC / Battery Power Switch UI 和数据模型。

## 共同按键 Client Models

本轮只纳入基础 5 个共同按键 Client Models：

| Model ID | Model 名称 | 用途 |
|---|---|---|
| `0x1001` | Generic OnOff Client | 开关 / Toggle / OnOff Set |
| `0x1003` | Generic Level Client | 调光 / Level Delta / Level Move |
| `0x1205` | Scene Client | Scene Recall |
| `0x1302` | Light Lightness Client | Lightness Set |
| `0x1311` | Light LC Client | Light LC OnOff / Light Ctrl |

扩展 5 个 `0x1305` / `0x1309` / `0x100B` / `0x1008` / `0x1005` 本轮不进入 required bind 范围。

## 架构

SDK `Node+SupportModels.swift` 中拆出两层能力：

- `powerSwitch...`：负责 `0x2A01` / `0x2A02` / `0x2A11` / `0x2A12` 共用能力，包括 PID 识别、基础 5 个 Client Models 列表、all-elements model 收集、required model 判断。
- `batteryPowerSwitch...`：只保留 Battery 额外能力，包括 Battery PID `0x2A01` / `0x2A02` 识别，以及 `Generic Battery Server (0x100C)` 作为额外 required model。

`supportModels` 改为追加 `powerSwitchProfileClientModels`。这样 `Node+Messages.swift` 现有 `getConfigMessageHandles()` 不需要改动，仍通过遍历 `supportModels` 生成 `ConfigModelAppBind(currentApplicationKey, to: model)`。

## 数据流

1. 添加流程读取 Composition Data 后，Node 获得 `companyIdentifier`、`productIdentifier` 和 `elements`。
2. SDK 判断 `companyIdentifier == 0x0A78` 且 PID 属于 Power Switch PID 集合时，启用 Power Switch profile。
3. SDK 遍历所有 element，收集实际存在的基础 5 个共同按键 Client Models。
4. `supportModels` 包含这些 all-elements Client Models。
5. `getConfigMessageHandles()` 使用当前 AppKey 为未绑定 model 生成 bind 消息。
6. 添加流程继续使用现有配置消息发送和补齐机制。

## Required Models 与失败处理

Battery Power Switch required models：

- Health Server
- Sunricher Vendor Model
- Generic Battery Server
- 基础 5 个共同按键 Client Models 的 all-elements 实例

AC Power Switch required models：

- Health Server
- Sunricher Vendor Model
- 基础 5 个共同按键 Client Models 的 all-elements 实例

`MeshFastAddDeviceManager` 的强失败判断从 Battery-only 扩展为 Power Switch required configuration。对于 required models：

- `ConfigAppKeyAdd` 失败时，Power Switch 添加失败。
- required model 的 `ConfigModelAppBind` 下发失败或返回失败状态时，Power Switch 添加失败。
- 添加失败后沿用现有 reset/delete node 流程。

非 Power Switch 设备不进入这套强失败逻辑，避免扩大影响面。

## 测试设计

在本地 `NordicSigMeshSDK` 增加 focused unit tests，覆盖能力层，不依赖真实设备：

- Battery PID `0x2A01` / `0x2A02`：基础 5 个按键 Client Models 会从 8 个 element 全量进入 `supportModels` / required models；Battery Server 仍是额外 required model。
- AC PID `0x2A11` / `0x2A12`：基础 5 个按键 Client Models 会从 8 个 element 全量进入 `supportModels` / required models；不要求 Battery Server。
- 非 Power Switch PID：不会触发 all-elements profile 收集。
- AC 场景覆盖 `0x1302 Light Lightness Client`，防止回归到当前缺失状态。

验证命令：

- SDK focused tests：`swift test --filter PowerSwitchAppKeyBindSupportModelsTests`
- App build：`xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

## 风险与约束

- 当前 App 工程默认通过 Swift Package 引用 `NordicSigMeshSDK`。实施时如需验证本地 SDK 改动，需要确认工程已切换到 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk` 本地路径。
- `0x100B` 是 SDK 中的 Generic Power Level Client，协议文档曾出现 `0x100D` 描述；本轮不处理扩展 5 个，因此不引入该差异。
- 本轮只保证“基础 5 个共同按键 Client Models”在 AC/Battery Power Switch 添加成功后的 AppKey bind 行为一致。
