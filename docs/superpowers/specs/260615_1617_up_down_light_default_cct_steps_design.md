# Up Down Light CCT Default Steps 设计

## 背景

目标设备为 `CID 0x0A78 / PID 0x2491` 的 up down light。新增协议要求 App 在设备添加成功后读取一次设备端 `CCT default steps`，并用返回结果决定 `Site - Space - More - Device Parameter Settings` 中 `Absolute CCT Range` 的默认值。

协议新增在 Sunricher Vendor GET/RET 类型下：

| 类型 | Opcode | 主命令 | 子码 | 含义 |
|---|---|---|---|---|
| GET | `0xF10A78` | `0x53` | `0x01` | get cct default steps |
| RET | `0xF30A78` | `0x53` | `0x01` | response get default steps |

RET payload 语义：

| 字段 | 含义 |
|---|---|
| `ret` | `0` 表示成功，非 `0` 表示失败 |
| `choose` | `5` 或 `6` |

默认关系：

| CCT default steps | Absolute CCT Range 默认值 |
|---|---|
| `5` | `2700K...5000K` |
| `6` | `2700K...6500K` |
| 未返回、失败、非法值 | `2700K...5000K` |

## 已确认需求

- 只针对 `CID 0x0A78 / PID 0x2491`。
- 设备添加成功后读取一次 `CCT default steps`。
- 正常 Add Device 的 Classic、Professional 两个入口都要覆盖。
- Restore / Replace 流程也要覆盖，因为替换后的真实设备可能与旧设备配置不同。
- `CCT default steps` 需要本地持久化。原因是 `Absolute CCT Range` 有 Reset 功能，Reset 必须有稳定的设备默认根值。
- 设备不返回、读取失败或返回非法值时，本地保存默认 steps `5`。
- 不新增云同步字段；该值服务本地设备默认和 Reset 语义。

## 现状

当前分支已经有 up down light 相关能力和协议基础：

- `Node.supportsUpDownRatioControl` 已用 `companyIdentifier == 0x0A78 && productIdentifier == 0x2491` 标记目标设备。
- SDK 已在 `SunricherVendorGet`、`SunricherVendorStatus` 中支持 `Opcode 0x53 / subcode 0x02` 的 up ratio。
- `Node.defaultAbsoluteCctRange` 当前会把 `0x2491` 视为窄默认范围产品，默认 `2700K...5000K`。
- `DeviceParameterSettingsController` 的 `Absolute CCT Range` 默认值来自 `devices.first?.defaultAbsoluteCctRange`。
- `Reset` 实际也依赖 `defaultAbsoluteCctRange`，因此需要一个可持久化的设备默认依据。
- `DeviceRestoreViewController` 当前会在 restore 时把旧节点的 `changeControlPage`、`absoluteCctRange` 复制到新节点；新设计需要确保新设备读取到的 default steps 会成为后续 Reset 的根值。

## 方案对比

### 推荐方案：SDK 协议建模 + App 共享读取 helper

在 SDK 中补完整 `CCT default steps` 协议模型，在 App 中新增共享的添加后读取 helper。Classic Add、Professional Add、Restore / Replace 都调用同一个 helper。

优点：

- 符合现有 `SunricherVendorGet` / `SunricherVendorStatus` 架构。
- 协议解析集中在 SDK，不把 raw bytes 解析散落到 App 添加流程。
- 多个添加入口复用同一个读取和保存逻辑，降低遗漏风险。
- `Reset` 使用持久化 steps 计算默认 range，有稳定根值。

缺点：

- 需要同时修改 App 和本地 `NordicSigMeshSDK`。

### 备选方案：App 侧直接发送 raw vendor get

App 在添加成功后直接构造 `[0x53, 0x01]` 并自行解析返回。

优点是短期改动少。缺点是绕开 SDK 类型系统，协议知识分散，后续 `0x53` 继续扩展时维护成本高。不推荐。

### 备选方案：继续固定 `0x2491` 默认 `2700K...5000K`

实现最小，但无法支持返回 `6` 的设备，也不能反映不同设备真实默认配置。不满足需求。

## 最终设计

采用推荐方案。

### SDK 协议层

在 `NordicSigMeshSDK` 中扩展现有 up down light vendor 协议模型：

| 类型 | 新增项 |
|---|---|
| `VendorUpDownLightCode` | `defaultCctSteps = 0x01` |
| `ResponseCode` | `upDownLightDefaultCctSteps` |
| `VendorFunctionGet` | `upDownLightDefaultCctSteps` |
| `FunctionParameters` | `upDownLightDefaultCctSteps(UInt8)` |

编码规则：

- `SunricherVendorGet(function: .upDownLightDefaultCctSteps)` 生成 payload `[0x53, 0x01]`。

解码规则：

- `SunricherVendorStatus(parameters:)` 识别 `[0x53, 0x01, ret, choose]`。
- `ret != 0` 时视为失败，不输出有效参数。
- `ret == 0` 且 `choose == 5 || choose == 6` 时输出 `.upDownLightDefaultCctSteps(choose)`。
- 短包、未知 subcode、非法 `choose` 都视为无有效参数。

### 本地数据层

在 `Node` 的本地持久化属性中增加 `upDownLightDefaultCctSteps`，默认语义为 `5`。

计算关系：

| 条件 | `defaultAbsoluteCctRange` |
|---|---|
| 非 `0x0A78 / 0x2491` 且已有旧规则 | 保持现有行为 |
| `0x0A78 / 0x2491` 且 saved steps 为 `6` | `2700...6500` |
| `0x0A78 / 0x2491` 且 saved steps 为 `5`、缺失、失败 fallback | `2700...5000` |

`effectiveCctRange` 继续保持现有合同：已保存 `absoluteCctRange` 优先；没有显式配置时才使用 `defaultAbsoluteCctRange`。

### Reset 语义

`Absolute CCT Range` 的 Reset 不再只依赖静态 PID 默认规则，而是依赖本地保存的 `upDownLightDefaultCctSteps`。

- steps `5`：Reset 到 `2700K...5000K`。
- steps `6`：Reset 到 `2700K...6500K`。
- 未读取到或读取失败：保存 steps `5`，Reset 到 `2700K...5000K`。

### 添加后读取流程

新增共享 helper，例如 `UpDownLightDefaultCctStepsReader`。

职责：

- 输入成功添加的 `Node` 列表。
- 只筛选 `supportsUpDownRatioControl == true` 且存在 `sunricherVendorModel` 的节点。
- 对每个目标节点发送 `SunricherVendorGet(function: .upDownLightDefaultCctSteps)`。
- 成功且返回 `5` 或 `6` 时保存该 steps。
- 失败、超时、无 vendor model、非法返回时保存默认 steps `5`。
- 保存后确保 `defaultAbsoluteCctRange` 和 Reset 能使用新 steps。
- 不展示额外 UI，不因为读取失败把添加流程标记失败。

### 接入入口

需要覆盖三个添加成功路径：

| 入口 | 接入点 |
|---|---|
| `DeviceAddClassicModeController` | 添加成功节点进入 `addSuccessNodes` 后，最终通知前触发 helper |
| `DeviceAddProfessionalModeController` | 同 Classic，复用同一 helper |
| `DeviceRestoreViewController` | restore / replace 新节点成功后触发 helper |

对于 Classic / Professional，读取 helper 必须在 `deviceAddCallback` 和空间刷新通知前完成并保存结果；失败也要先保存 fallback steps `5`，再继续原有添加完成通知，避免 Device Parameter Settings 立即打开时看到旧默认值。

对于 Restore / Replace：

- 仍允许 restore 继承旧节点的显式 `absoluteCctRange`，避免用户配置无故丢失。
- 新设备读取到的 `upDownLightDefaultCctSteps` 必须保存到新节点，作为后续 Reset 的根值。
- 如果新节点没有显式 `absoluteCctRange`，则 `effectiveCctRange` 会立即使用新 steps 对应默认值。
- 如果新节点继承了旧 `absoluteCctRange`，当前展示保持显式配置；用户点击 Reset 后回到新设备 steps 对应默认值。

## 非目标

- 不新增云同步字段、share/import 字段或接口 payload。
- 不改变 `Change Control Page` 的默认规则。
- 不改变 up ratio 的现有 GET/SET 行为。
- 不调整 Device Parameter Settings UI 布局、文案和交互。
- 不把读取失败计入添加失败或同步失败。
- 不为非 `0x0A78 / 0x2491` 设备发送该 GET。

## 错误处理

| 场景 | 行为 |
|---|---|
| 设备返回 `ret != 0` | 保存 steps `5` |
| 超时或无 response | 保存 steps `5` |
| 返回 choose 非 `5` / `6` | 保存 steps `5` |
| 节点无 vendor model | 保存 steps `5` |
| 添加流程中 helper 局部失败 | 不阻断添加成功 |

## 测试计划

SDK 测试：

1. GET 编码生成 `[0x53, 0x01]`。
2. RET 成功解析 `[0x53, 0x01, 0x00, 0x05]` 为 steps `5`。
3. RET 成功解析 `[0x53, 0x01, 0x00, 0x06]` 为 steps `6`。
4. `ret != 0` 不输出有效参数。
5. 短包、未知 subcode、非法 choose 不输出有效参数。
6. 确认 `[0x53, 0x01]` 不与 up ratio `[0x53, 0x02]` response matching 混淆。

App 验证：

1. 静态检查 Classic Add、Professional Add、Restore / Replace 都调用同一个 helper。
2. 静态检查 helper 只筛选 `0x0A78 / 0x2491`。
3. 静态检查失败 fallback 会保存 steps `5`。
4. 静态检查 `defaultAbsoluteCctRange` 对 `0x2491` 使用持久化 steps。
5. 静态检查 Reset 使用 `defaultAbsoluteCctRange`，因此能回到 steps 对应默认值。
6. 运行 `git diff --check`。
7. 运行 iPhoneOS 构建：

`xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

## 验收标准

| 场景 | 期望 |
|---|---|
| 新增 `0x0A78 / 0x2491`，设备返回 steps `5` | 本地保存 `5`，Absolute CCT Range 默认和 Reset 为 `2700K...5000K` |
| 新增 `0x0A78 / 0x2491`，设备返回 steps `6` | 本地保存 `6`，Absolute CCT Range 默认和 Reset 为 `2700K...6500K` |
| 新增 `0x0A78 / 0x2491`，设备不返回或失败 | 本地保存 `5`，默认和 Reset 为 `2700K...5000K` |
| Restore / Replace 为不同设备且返回 steps `6` | 新节点保存 `6`，Reset 回 `2700K...6500K` |
| Restore / Replace 继承旧显式 range | 当前显式 range 不被强制覆盖；Reset 使用新设备 steps |
| 其他 CCT 产品 | 默认规则保持现状 |

## 实施边界

正式实现前单独写 implementation plan，按阶段执行：

1. SDK 协议枚举、编码、解码和测试。
2. SDK / App 本地持久化字段和 `defaultAbsoluteCctRange` 计算接入。
3. App 添加成功后读取 helper。
4. Classic、Professional、Restore / Replace 三个入口接入。
5. 回归验证和 iPhoneOS 构建。
