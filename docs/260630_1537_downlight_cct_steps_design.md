# Downlight CCT Steps 读取功能设计

## 背景

当前 Up/Down Light `CID 0x0A78 / PID 0x2491` 已实现 `upDownLightDefaultCctSteps` 读取能力。Downlight `CID 0x0A78 / PID 0x2492` 与 Up/Down Light 使用同一条 vendor 协议读取色温档位，但不支持 up/down ratio 控制。

Downlight 的设备配置由云端同步，不在本次改动中修改本地 `devices_config.json`：

- `companyId`: `0A78`
- `productId`: `2492`
- `categoryName`: `CCT Controller Lighting`
- `elementCount`: `3`
- `iconCategory`: `Lighting`
- `deviceCategory`: `Lighting`
- `modelName`: `SR-nRF54L15-M3`

## 目标

为 Downlight 加入入网后的 CCT steps 读取与默认 Absolute CCT Range 推导能力：

- 添加入网后读取 `upDownLightDefaultCctSteps`
- 解析 vendor response 中的 steps `5` 或 `6`
- 保存到 `Node.upDownLightDefaultCctSteps`
- Device Parameter Settings 的 `Absolute CCT Range` 默认值根据 steps 展示
- 不开启 up/down ratio UI、group ratio 控制或 ratio vendor 订阅

## 非目标

本次不做以下内容：

- 不修改本地 `devices_config.json`
- 不把 `0x2492` 加进 `supportsUpDownRatioControl`
- 不新增 Downlight 独立 UI 页面
- 不暴露 steps 为独立用户设置项
- 不改变 `0x2491` 的 up/down ratio 功能

## 协议

Downlight 使用现有 Up/Down Light CCT steps 协议：

- Vendor model：Sunricher vendor model，model id 为 `(0x0A78 << 16) | 0x01`
- Get opcode：`0xF10A78`
- Response opcode：`0xF30A78`
- Vendor payload：
  - opcode：`0x53`
  - sub opcode：`0x01`

Response 参数：

- `param 0`
  - `0`：Success
  - 其他：Failed
- `param 1`
  - `5` 或 `6`

当前 SDK 代码中的 `SunricherVendorGet` / `SunricherVendorStatus` 已具备该协议的消息构造和解析能力，本次设计复用现有协议实现。

说明：协议资料使用 `0xF10A78` / `0xF30A78` 表达，当前 SDK 常量中分别写作 `0xF1780A` / `0xF3780A`，实现时以既有 `SunricherVendorGet` / `SunricherVendorStatus` 抽象为准，不新增第二套 opcode。

## 设计方案

### 能力拆分

保留现有 up/down ratio 能力边界：

- `supportsUpDownRatioControl` 继续只命中 `CID 0x0A78 / PID 0x2491`
- `0x2492` 不进入 up/down ratio 控制能力

新增或调整 CCT steps 专用能力判断：

- `CID 0x0A78 / PID 0x2491`
- `CID 0x0A78 / PID 0x2492`

该能力只表达“需要读取 `upDownLightDefaultCctSteps` 并参与默认 CCT range 推导”，不表达 ratio 控制能力。

### 入网读取

沿用现有 `UpDownLightDefaultCctStepsReader`：

- Classic add 成功后读取
- Professional add 成功后读取
- Restore add 成功后读取

Reader 的筛选条件从 `supportsUpDownRatioControl` 改为 CCT steps 专用能力判断。这样：

- `0x2491` 继续读取 steps
- `0x2492` 新增读取 steps
- 其他设备不受影响

Reader 仍按节点顺序逐个发送：

- `SunricherVendorGet(function: .upDownLightDefaultCctSteps)`
- timeout 保持现有策略
- 无 vendor model 时保存 fallback steps `5`

### 返回值处理

沿用当前 Up/Down Light 处理规则：

- 成功且 steps 为 `6`：保存 `6`
- 成功且 steps 为 `5`：保存 `5`
- 失败、超时、返回类型不匹配、steps 不是 `5/6`：保存 `5`

通用接收路径 `Node.updateNodeStatus(message:source:)` 已能在收到 `.upDownLightDefaultCctSteps(let steps)` 时保存到节点属性。本次只需要确保 `0x2492` 在 SDK 的“支持 CCT steps 产品”判断中被接受，保证落库和默认值推导一致。

### SDK 默认范围

在 SDK 的 `Node.isUpDownLightDefaultCctStepsProduct` 中加入 `PID 0x2492`。

`Node.defaultAbsoluteCctRange` 对 `0x2491` 和 `0x2492` 使用同一规则：

- `upDownLightDefaultCctSteps == 6`：`2700K...6500K`
- 其他情况：`2700K...5000K`

`Node.defaultChangeControlPage` 不变：

- `0x2492` 默认仍为 `.tunableWhite`

### 显式范围优先级

保持当前 `effectiveCctRange` 策略：

- 如果 steps 为 `6`，但配网阶段旧的 `LightCTLTemperatureRangeGet` 写入了 legacy `2700K...5000K`，则 `effectiveCctRange` 返回 `2700K...6500K`
- 如果用户或同步流程设置了其他显式范围，例如 `3000K...4500K`，继续优先使用显式范围

该逻辑需要同时适用于 `0x2491` 和 `0x2492`。

### 本地数据库

`MeshDatabase.savePropertys()` 当前只在 `isUpDownLightDefaultCctStepsProduct` 为 true 时保存 `upDownLightDefaultCctSteps`。

加入 `0x2492` 后，Downlight 的 steps 会与 Up/Down Light 一样落库，并在下次加载节点属性时恢复。

## 用户可见行为

添加 Downlight 后：

- 如果设备返回 steps `6`，Device Parameter Settings 中 `Absolute CCT Range` 默认显示 `2700K~6500K`
- 如果设备返回 steps `5`、失败或未返回，默认显示 `2700K~5000K`
- 页面仍显示 Tunable White 相关能力
- 不显示 up/down ratio 控制

## 影响范围

App：

- `SunSmart/Main/Device/Model/DeviceGroupDeferredSyncPlanner.swift`
  - 调整 Reader 筛选条件
- `SunSmart/Common/Data/Node+Capability.swift`
  - 新增 CCT steps 专用能力判断，命中 `0x2491` 和 `0x2492`

SDK：

- `Node+Propertys.swift`
  - `isUpDownLightDefaultCctStepsProduct`
  - `defaultAbsoluteCctRange`
  - `effectiveCctRange`
- `MeshDatabase.swift`
  - 通过 `isUpDownLightDefaultCctStepsProduct` 自动扩展落库范围

不应改动：

- up/down ratio UI
- group up/down ratio 控制
- vendor group subscription for ratio
- 本地 `devices_config.json`

## 测试与验证

SDK 层测试：

- `0x2492` 默认 steps 为 `5` 时，默认 range 为 `2700...5000`
- `0x2492` steps 为 `6` 时，默认 range 为 `2700...6500`
- `0x2492` steps 为异常值时，归一为 `5`
- `0x2492` steps 为 `6` 且 `absoluteCctRange == 2700...5000` 时，`effectiveCctRange == 2700...6500`
- `0x2492` steps 为 `6` 且 `absoluteCctRange == 3000...4500` 时，`effectiveCctRange == 3000...4500`

App 层验证：

- `0x2491` 仍会读取 steps，并保留 up/down ratio 控制
- `0x2492` 会读取 steps，但不出现 up/down ratio 控制
- Classic add / Professional add / Restore add 路径都覆盖
- iPhoneOS `xcodebuild` 通过

推荐构建命令：

`xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

## 风险与控制

- 风险：把 `0x2492` 加入 `supportsUpDownRatioControl` 会错误开启 ratio UI。
  - 控制：新增 CCT steps 专用能力，不复用 ratio capability。
- 风险：只改 App reader，不改 SDK 产品判断，会导致 steps 收到但默认范围或落库不生效。
  - 控制：SDK `isUpDownLightDefaultCctStepsProduct` 同步加入 `0x2492`。
- 风险：显式 Absolute CCT Range 被 steps 默认值覆盖。
  - 控制：保持现有显式范围优先策略，只让 legacy `2700...5000` 在 steps `6` 时让位。
