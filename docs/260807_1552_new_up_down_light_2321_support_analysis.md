# PID 0x2321 CCT Up&Down Lighting 支持分析与待确认方案

## 文档状态

- 状态：方案 A 已于 2026-08-07 确认，尚未进入代码实施。
- 目标：让 `CID 0x0A78 / PID 0x2321` 与旧设备 `CID 0x0A78 / PID 0x2491` 在 App 内拥有完全相同的功能行为。
- 边界：新旧设备仍保留各自真实 PID、名称和型号，不做 PID 替换或身份伪装。

## 结论

不能只向 `devices_config.json` 增加一条设备配置。

旧设备 `0x2491` 当前还被 App 和 NordicSigMeshSDK 的多组显式能力判断使用。完整支持 `0x2321` 至少需要同时覆盖：

1. 设备配置、添加、恢复、重置和 3-Element 地址预算。
2. Lights 页面设备分类、在线/离线/待同步图标和单灯页路由。
3. 单灯页 Up/Down 外观、Up/Down Ratio 读取、设置、失败回滚和本地持久化。
4. 入网后 CCT default steps 读取、持久化、默认色温范围和有效色温范围。
5. Device Parameter Settings 中 Change Control Page、Absolute CCT Range，以及这些参数对单灯页和 Group 页的影响。
6. Content Display 对单灯页和 Group 页控制面板的影响。
7. Group 成员资格、Up/Down Ratio 模式、Vendor Model Group subscription 和组播控制。
8. 外部光感灯具能力，以及 Motion Sensitivity 不支持规则。
9. SunSmart、Archipelago、SLG Sync Plus、SylSmart 四个相关 target 的资源与编译回归。

推荐采用“扩展既有能力门控 + 增加真实设备配置 + 服务端配置同步”的方案。现有 UI 和业务消费者已经通过能力属性工作，不需要为新 PID 复制页面或分叉业务逻辑。

## 已核实的当前代码事实

### 设备配置与加载优先级

- `SunSmart/devices_config.json` 已包含旧设备 `0x2491`，其 `elementCount`、`iconCategory`、`deviceCategory` 分别为 `3`、`BidirectionalController`、`Lighting`。
- 新设备提供的这三个关键字段与旧设备一致，因此可复用现有双向灯图标资源和 Lighting 页面路由。
- `categoryName` 和 `modelName` 用于识别和展示，应保留新设备给出的真实值：`CCT Up&Down Lighting`、`SRPL-BL9105N-XXCCXXE`。
- App 冷启动时优先读取本地数据库中缓存的设备配置；只有缓存为空时才回退到包内 `devices_config.json`。
- 登录或刷新站点后，服务端 `/devicesConfig` 返回列表会整体替换内存列表和本地数据库。

因此，包内 JSON 增加 `0x2321` 只能保证全新且尚无配置缓存时的本地回退。要保证升级用户和联网后的稳定支持，服务端设备配置也必须同步包含 `0x0A78 / 0x2321`。

### 旧 PID 的显式能力门控

当前可执行代码中，旧 PID `0x2491` 的直接判断集中在以下位置：

| 层级 | 文件 | 当前职责 | 新设备要求 |
| --- | --- | --- | --- |
| App | `SunSmart/devices_config.json` | 支持设备清单、名称、Element 数量、图标、设备类型、型号 | 新增提供的完整配置 |
| App | `SunSmart/Common/Data/Node+Capability.swift` | 单灯和 Group 的 Up/Down Ratio 能力 | `0x2321` 与 `0x2491` 同时命中 |
| App | `SunSmart/Common/Data/Node+Capability.swift` | 入网后读取 CCT default steps | `0x2321` 与 `0x2491`、`0x2492` 同时命中 |
| App | `SunSmart/Common/Data/MeshNetwork+SunSmart.swift` | 外部光感灯具能力 | `0x2321` 与 `0x2491` 同时命中 |
| App | `SunSmart/Common/Data/MeshNetwork+SunSmart.swift` | 排除 Motion Sensitivity | `0x2321` 与 `0x2491` 同时命中 |
| SDK | `Sources/NordicSigMeshSDK/MeshLib/Node/Node+SupportModels.swift` | Up/Down Ratio Vendor Model 的 Group subscription | `0x2321` 与 `0x2491` 同时命中，并继续要求 Vendor Model 存在 |
| SDK | `Sources/NordicSigMeshSDK/MeshLib/Node/Node+Propertys.swift` | CCT steps 产品判断、默认/有效色温范围和持久化资格 | `0x2321` 与 `0x2491`、`0x2492` 同时命中 |

除上述位置外，单灯页和 Group 页均通过这些能力属性消费行为，没有发现需要再复制一套 `0x2321` 专用 UI 的证据。

## 完整影响链路

### 1. 设备识别、添加、恢复与重置

新增真实设备配置后：

- Classic、Professional、Site 添加、Configured/Not Configured Reset、Safe Mode Reset 和 Force Reset 等入口可通过 CID/PID 查到设备配置。
- 设备名称使用 `CCT Up&Down Lighting`。
- 设备类型为 Lighting，进入 Lights 列表并路由到 `DeviceLightViewController`。
- `elementCount = 3` 参与预估 Unicast Element 地址消耗，与旧设备一致。
- Restore 候选和设备信息展示使用新设备自己的型号与 PID，不伪装成旧设备。

### 2. Lights 页面图标和行为

`iconCategory = BidirectionalController` 会复用现有三套资源：正常、离线、待同步。`deviceCategory = Lighting` 会使新设备：

- 出现在 Lights 页面和 Luminaire 计数中。
- 参与 All On/Off、All Brightness 和支持 CCT 时的 All CCT 行为。
- 长按或从 Group 成员进入时打开普通 Lighting 控制页。

本项不需要新增图片资源；需要验证四个品牌 target 都继续包含共享 `Assets.xcassets` 和 `devices_config.json`。

### 3. 单设备控制页

扩展 `supportsUpDownRatioControl` 后，新设备自动复用旧设备的：

- Up/Down 发光顶部视图。
- Up/Down Ratio 控件和页面布局。
- 进入页面时的 Vendor GET。
- Ratio 修改时的 Vendor SET、成功确认、失败回滚和本地 `Node.PreConfiguration.upRatio` 持久化。
- Up Ratio 与 Down Ratio、亮度、色温共同驱动顶部视觉反馈。

亮度和 CCT 的基础支持仍以设备 Composition 中实际 Model 为真值；PID 只补齐旧设备已有的特殊 Up/Down 能力。

### 4. CCT default steps 与 Device Parameter Settings

App 的入网后 reader 和 SDK 的产品判断都加入 `0x2321` 后，流程为：

1. 新设备 Provisioning 完成后发送 CCT default steps Vendor GET。
2. 返回 `6` 时保存为 6 steps；返回 `5`、无 Vendor Model、超时、错误或非法值时按现有规则回退并保存为 5 steps。
3. SDK 使用持久化结果计算默认 Absolute CCT Range。
4. Device Parameter Settings 继续直接读取 SDK 的默认值和有效值，不增加 App 页面专用覆盖。

应保持与旧设备完全一致的矩阵：

| 状态 | Change Control Page 默认值 | Absolute CCT Range 默认值 |
| --- | --- | --- |
| 5 steps、读取失败或尚无有效结果 | Tunable White | 2700K...5000K |
| 6 steps | Tunable White | 2700K...6500K |
| 用户已配置自定义范围 | 按用户配置 | 自定义范围优先 |

参数对页面的现有影响也应原样继承：

- Change Control Page 为 Tunable White 时，单灯页和单灯 Cell 显示 CCT。
- Change Control Page 为 Single White 时，单灯页和单灯 Cell 隐藏 CCT。
- Group、Scene、全灯控制等跨设备功能继续以原始 CCT Model 能力为准，不因 Single White 隐藏单灯 CCT 而丢失跨设备 CCT 能力。
- Absolute CCT Range 继续影响 slider 范围、输入值 clamp、快捷色温按钮数量和 CCT 限制提示。

### 5. Content Display

Content Display 是 Space 级配置，没有针对 `0x2491` 的 PID 绑定。新设备只要正确进入 Lighting 控制页，就会自动继承：

- Device Name Display 对列表名称前缀的显示设置。
- CCT Quick Buttons 对单灯页和 Group 页快捷按钮的显示设置。
- Control Style 的 Simple / Detailed 控制面板样式。

因此本项不建议新增 PID 判断或新字段，只需要把新设备纳入回归验收。

### 6. Group 行为

App 能力和 SDK Group subscription 同时扩展后，新设备应具备：

- 可作为 Lighting 加入 Group。
- 组内存在新设备时显示 Up/Down Ratio mode button。
- Ratio 模式下复用现有控件，更新并持久化所有 Up/Down 成员的 ratio。
- Ratio 确认时继续向 Group Address 发送现有 Vendor SET。
- 加入 Group 时给新设备的 Sunricher Vendor Model 增加 Group subscription，确保设备能收到该组播。
- Group CCT 显示、范围合并、成员级 clamp 和限制提示继续根据实际 CCT Model、Change Control Page 和有效范围计算。
- Group 页继续消费 Space 的 Content Display 设置。

只改 App 的 ratio 能力而不改 SDK subscription 会造成“按钮可见、命令已发送，但设备收不到组播”的假支持，必须避免。

### 7. 额外能力

旧 PID 还具有两项容易遗漏的显式规则：

- 被视为可使用外部光感的 Luminaire，影响 Light Sensor Calibration 和 Profile Settings 相关行为/提示。
- 即使存在 Presence Sensor Model，也不展示 Motion Sensitivity 参数。

既然需求定义新旧功能完全相同，新 PID 必须加入这两个名单。

## 方案比较

### 方案 A：扩展既有能力门控并同步真实配置（推荐）

- 在 App 与 SDK 的既有能力判断中增加 `0x2321`。
- 增加新设备真实配置，不改变其 PID、名称和型号。
- 服务端 `/devicesConfig` 同步增加同一条配置。
- 复用既有 UI、协议、持久化和 Group 控制实现。

优点：改动聚焦、符合当前架构、不会影响旧设备身份，能够覆盖完整链路。缺点：App、SDK 和服务端配置必须协调发布。

### 方案 B：App 合并包内配置与服务端配置

在方案 A 的能力扩展之外，修改设备配置加载策略，让包内 `0x2321` 即使不在服务端列表中也始终被合并保留。

优点：可降低服务端漏配对新设备支持的影响。缺点：会改变全局设备清单优先级，可能重新启用服务端有意移除的旧设备，影响范围明显大于本需求。

除非服务端短期无法更新且明确接受该风险，否则不推荐。

### 方案 C：把新 PID 映射或伪装为旧 PID

在配置或运行时把 `0x2321` 当作 `0x2491`。

优点：表面改动少。缺点：会污染真实设备身份，影响型号展示、设备配置、固件匹配、日志诊断和未来 PID 专属差异，也无法自然解决服务端配置覆盖问题。

不推荐。

## 推荐实施范围

### App 仓库

- 修改 `SunSmart/devices_config.json`：增加用户提供的 `0x2321` 完整配置。
- 修改 `SunSmart/Common/Data/Node+Capability.swift`：在现有能力文件内集中维护 Ratio、CCT steps、外部光感灯具与 Motion Sensitivity 排除产品策略，现有 `Node` 属性继续作为页面调用入口。
- 修改 `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`：改为消费同一产品能力策略，避免两处独立维护名单。
- 新增聚焦行为契约测试，通过最小 SDK 编译 stub 编译真实 `Node+Capability.swift`，验证新配置字段及上述 App 能力与旧设备一致，同时验证 `0x2492` 仍只有 CCT steps 能力、没有 Up/Down Ratio 能力。

### NordicSigMeshSDK 仓库

- 修改 `Sources/NordicSigMeshSDK/MeshLib/Node/Node+SupportModels.swift`：扩展 Vendor Model Group subscription 资格。
- 修改 `Sources/NordicSigMeshSDK/MeshLib/Node/Node+Propertys.swift`：扩展 CCT steps、默认范围和持久化资格。
- 更新 `Tests/NordicSigMeshSDKTests/UpDownLightVendorMessageTests.swift`：覆盖 `0x2321` 的 Group subscription、去重与负例。
- 更新 `Tests/NordicSigMeshSDKTests/NodeCctDefaultValueTests.swift`：覆盖 `0x2321` 的 5/6/非法 steps、自定义范围、状态回写和 Tunable White 默认值。

当前 Xcode 工程已经通过本地 Swift Package 引用 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk`，无需再次切换依赖。

### 服务端配置

- `/devicesConfig` 返回中增加 `CID 0x0A78 / PID 0x2321`，字段与用户提供的 JSON 一致。
- 验证服务端刷新后不会把 App 内存和数据库中的新设备配置移除。

### 明确不改

- 不新增独立控制页面或复制 Up/Down UI。
- 不新增图片资源。
- 不新增本地化文案。
- 不新增数据库字段。
- 不改变 Vendor opcode 或 payload。
- 不改变旧设备 `0x2491`、Downlight `0x2492` 和其他灯具的既有能力。
- 不修改 Auth 信息。

## 验收矩阵

| 场景 | 预期结果 |
| --- | --- |
| 全新安装、无配置缓存 | 包内配置可识别并展示 `0x2321` |
| 升级安装、已有配置缓存 | 服务端配置刷新后仍可识别 `0x2321` |
| Classic / Professional / Site 添加 | 显示真实名称和双向灯图标，按 3 Elements 计入地址预算 |
| Restore 与各 Reset 入口 | 能按 `0x0A78 / 0x2321` 找到配置并保持 Lighting 类型 |
| Lights 页面在线、离线、待同步 | 使用现有 BidirectionalController 对应图标 |
| 单灯页 | 显示 Up/Down 顶部视图和 Ratio 控件，亮度/CCT 由真实 Model 决定 |
| 单灯 Ratio GET 成功 | 使用设备返回值刷新并持久化 |
| 单灯 Ratio SET 成功/失败 | 成功确认并保存；失败按旧设备逻辑回滚并提示 |
| Provisioning 后 steps = 5 / 6 | 分别得到 2700K...5000K / 2700K...6500K 默认范围 |
| steps 超时、错误、非法值或无 Vendor Model | 按现有规则回退为 5 steps |
| Parameter Settings 切换 Change Control Page | 单灯页和 Cell 的 CCT 显隐与旧设备一致 |
| Parameter Settings 修改 Absolute CCT Range | 单灯、Group、Scene 和批量 CCT 的范围/clamp 与旧设备一致 |
| Content Display 切换 quick buttons / control style | 新设备单灯页和包含它的 Group 页同步生效 |
| Group 仅含普通灯 | 不显示 Up/Down Ratio mode button |
| Group 含 `0x2321` | 显示 Ratio mode button，Vendor Model 已订阅 Group Address |
| Group Ratio 控制 | Group SET 可到达新设备，并持久化所有 Up/Down 成员的 ratio |
| 外部光感与 Profile | 新设备被视为可使用外部光感的 Luminaire |
| Motion Sensitivity | 与旧设备一样不展示该参数 |
| `0x2492` 回归 | 继续支持 CCT steps，但不获得 Up/Down Ratio UI/组播能力 |
| 其他 PID 回归 | 行为不变 |

## 验证计划

### 静态与自动化验证

- 校验 `devices_config.json` 可解析，且 `0x2321` 字段与输入完全一致。
- 运行 App 聚焦契约测试，覆盖全部显式能力名单。
- 运行 NordicSigMeshSDK 的 UpDownLight Vendor Message 与 Node CCT Default Value 测试。
- 分别在 App 和 SDK 仓库执行 diff whitespace 检查。
- 确认 App 中所有可执行代码的 `0x2491` 产品门控均已逐项判断是否应包含 `0x2321`。

### Target 构建验证

按项目规则直接使用 iPhoneOS generic destination 构建：

- SunSmart
- Archipelago
- SLG Sync Plus
- SylSmart

不使用 Simulator 作为构建验收。

### 真机与真实 Mesh 验证

自动化测试和 iPhoneOS 构建不能证明真实设备协议链成功，仍需使用 `0x2321` 真机验证：

- Provisioning、3 Elements 和 Composition Models。
- CCT steps Vendor GET 的真实响应。
- Ratio GET/SET 的 opcode、payload、ACK/status 和失败行为。
- Vendor Model Group subscription 实际配置成功。
- 单播与 Group Address 组播控制均能到达设备。
- 5/6 steps、Content Display、Parameter Settings、Lights 页面和 Group 页完整矩阵。

## 风险与确认项

1. 本方案依据“新设备与旧设备功能完全相同”复用旧协议。若新设备 Composition、Vendor Model 或 Vendor 协议有任何差异，需要另行补充协议事实，不能仅靠 PID 名单保证硬件行为。
2. 服务端设备配置是完整支持的发布前置条件。若本次范围不包含服务端更新，需要明确是否改用风险更高的“App 合并包内配置”方案。
3. App 与 SDK 是两个仓库；实现、测试、提交和发布版本需要同步管理。当前仅形成方案，不执行提交。

## SDK 修改必要性

SDK 修改不涉及 Vendor opcode、payload 或解析规则，只扩展两个产品能力门控：

1. CCT default steps 的默认值、有效色温范围和数据库持久化由 SDK `Node` 负责。App 即使读到了 `0x2321` 的 steps，SDK 不把它识别为对应产品时，也不会按旧设备规则计算和持久化 5/6 steps 结果。
2. Group Up/Down Ratio 使用 Group Address 发送 Vendor SET。设备 Vendor Model 的 Group subscription 消息由 SDK 生成；SDK 不加入 `0x2321` 时，会出现 App 显示 Ratio UI 并发出组播，但新设备 Vendor Model 没有订阅该地址的假支持。

把这两项逻辑复制到 App 会造成默认值、持久化和 Mesh 配置职责分叉，因此方案 A 保持旧设备现有分层，由 SDK 继续作为这两项能力的真值来源。

## 已确认方案

采用方案 A，并把服务端 `/devicesConfig` 增加 `0x2321` 作为发布前置条件。后续按 Superpowers 的 writing-plans 流程生成逐文件、逐测试、可执行的实施计划；默认采用当前会话 Inline Execution，不使用 subagents。
