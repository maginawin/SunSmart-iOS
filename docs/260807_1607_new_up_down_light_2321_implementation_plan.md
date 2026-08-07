# PID 0x2321 CCT Up&Down Lighting 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` and execute this plan inline in the current session. Do not use subagents. Steps use checkbox syntax for tracking.

**Goal:** 为 `CID 0x0A78 / PID 0x2321` 增加与 `CID 0x0A78 / PID 0x2491` 完全相同的 App、SDK、单灯、参数、Content Display 和 Group 行为，同时保持两个产品的真实身份独立。

**Architecture:** 保留现有分层：App 负责支持设备配置、页面能力门控和入网后读取；NordicSigMeshSDK 负责 CCT steps 的默认值/持久化以及 Vendor Model Group subscription。现有 UI、Vendor 消息和数据库字段全部复用，只扩展既有产品资格判断，不复制页面或协议实现。

**Tech Stack:** Swift、UIKit、NordicSigMeshSDK Swift Package、XCTest、Foundation standalone contract tests、JSON、Xcode workspace。

## Global Constraints

- 新设备身份固定为 `CID 0x0A78 / PID 0x2321`，不得映射或改写为 `0x2491`。
- 新设备配置固定为：`categoryName = CCT Up&Down Lighting`、`elementCount = 3`、`iconCategory = BidirectionalController`、`deviceCategory = Lighting`、`modelName = SRPL-BL9105N-XXCCXXE`。
- 新设备功能必须与 `0x2491` 相同；`0x2492` 继续只有 CCT default steps 能力，不获得 Up/Down Ratio 能力。
- 不修改 Vendor opcode、payload、status 解析和现有数据库 schema。
- 不新增 UI 页面、图片资源、本地化文案、Auth 信息或依赖。
- 保持改动聚焦，不重构无关模块，不格式化无关文件。
- App 已使用本地 NordicSigMeshSDK：`/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk`。
- App 与 SDK 都不得覆盖各自已有的无关工作区改动；执行每个任务前先复核两个仓库的 `git status --short`。
- 未经用户明确授权，不执行 Git commit、push、merge 或 SDK 版本发布。
- 自动化和构建验证不能宣称真实 BLE/Mesh、服务端或硬件链路已经成功。
- iOS 构建必须直接运行 `xcodebuild`，使用 generic iPhoneOS destination，不使用 shell 包装、日志重定向或 Simulator。
- 四个受影响 scheme 均需验证：SunSmart、Archipelago、SLG Sync Plus、SylSmart。

---

## Scope and File Map

### App 仓库

- Create: `Tests/Device/UpDownLightProductSupportContractTests.swift`
  - 解析真实配置并执行真实 `Node+Capability.swift` 的产品能力行为，不加入 Xcode target。
- Create: `Tests/Device/UpDownLightNordicSigMeshSDKStub.swift`
  - 为 standalone contract test 提供编译真实 `Node` extension 所需的最小 SDK 类型边界。
- Create: `scripts/check_up_down_light_product_support.sh`
  - 编译并执行聚焦契约测试，使用 `/tmp` 放置测试二进制。
- Modify: `SunSmart/devices_config.json`
  - 增加新设备的真实配置。
- Modify: `SunSmart/Common/Data/Node+Capability.swift`
  - 集中定义四类产品能力策略，并让现有 `Node` Ratio/CCT steps 属性消费该策略。
- Modify: `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`
  - 让外部光感灯具与 Motion Sensitivity 判断消费同一产品能力策略。

### NordicSigMeshSDK 仓库

- Create: `Sources/NordicSigMeshSDK/MeshLib/Node/UpDownLightProductPolicy.swift`
  - 集中定义 CCT default steps 与 Up/Down Ratio 两类 SDK 产品资格。
- Create: `Tests/Standalone/UpDownLightProductPolicyTests.swift`
  - 不依赖 UIKit test host 的纯产品策略契约测试。
- Create: `scripts/check_up_down_light_product_policy.sh`
  - 编译生产策略文件并执行 standalone contract test。
- Modify: `Tests/NordicSigMeshSDKTests/NodeCctDefaultValueTests.swift`
  - 补充 `0x2321` 的 CCT 默认值、范围、归一、覆盖与状态缓存 XCTest。
- Modify: `Sources/NordicSigMeshSDK/MeshLib/Node/Node+Propertys.swift`
  - 将 `0x2321` 纳入 CCT default steps 产品资格。
- Modify: `Tests/NordicSigMeshSDKTests/UpDownLightVendorMessageTests.swift`
  - 补充 `0x2321` 的 Group Vendor Model subscription、去重与缺失 Model XCTest。
- Modify: `Sources/NordicSigMeshSDK/MeshLib/Node/Node+SupportModels.swift`
  - 将 `0x2321` 纳入 Up/Down Ratio Group subscription 资格。

### 外部发布前置条件

- 服务端 `/devicesConfig`
  - 返回列表必须包含用户提供的 `0x0A78 / 0x2321` 完整配置。
  - 该变更不在当前本地仓库内实施，但必须在发布验收中提供真实响应证据。

## Task 1: 建立 App 产品支持失败契约

**Files:**

- Create: `Tests/Device/UpDownLightProductSupportContractTests.swift`
- Create: `Tests/Device/UpDownLightNordicSigMeshSDKStub.swift`
- Create: `scripts/check_up_down_light_product_support.sh`
- Read: `SunSmart/devices_config.json`
- Read: `SunSmart/Common/Data/Node+Capability.swift`
- Read: `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`

**Interfaces:**

- Consumes: 仓库根路径、设备配置 JSON、真实 `Node+Capability.swift` 和最小 SDK 类型边界。
- Produces: 可独立执行的 App 侧产品支持契约；后续 Task 2 以该测试通过作为完成条件。

- [x] **Step 1: 创建 standalone contract test**

  测试使用 Foundation，并从命令行参数接收仓库根路径。测试不得读取或匹配 Swift 源码文本，必须编译和调用真实生产能力实现。测试逐项断言：

  - JSON 可以解析为设备配置数组。
  - `CID 0x0A78 / PID 0x2321` 恰好存在一条记录。
  - CID、PID、categoryName、elementCount、iconCategory、deviceCategory、modelName 七个字段与 Global Constraints 中的值完全一致。
  - 真实 `Node.supportsUpDownRatioControl` 对 `0x2491`、`0x2321` 返回 true，对 `0x2492`、其他 CID 返回 false。
  - 真实 `Node.supportsUpDownLightDefaultCctSteps` 对 `0x2491`、`0x2492`、`0x2321` 返回 true，对普通灯和其他 CID 返回 false。
  - 产品能力策略对 `0x2491`、`0x2321` 返回外部光感灯具 true，对其他 CID 返回 false。
  - 产品能力策略对 `0x2491`、`0x2321` 返回 Motion Sensitivity unsupported true，对普通灯和其他 CID 返回 false。
  - 测试输出唯一成功标识 `UpDownLightProductSupportContractTests passed`。

- [x] **Step 2: 创建最小 SDK 编译 stub**

  Stub 只提供真实 `Node+Capability.swift` 编译所需的公开 `Node` 类型边界：companyIdentifier、productIdentifier、versionIdentifier、isEmergencySignController。不得在 stub 中实现任何待测能力或复制 PID 判断。

- [x] **Step 3: 创建聚焦检查脚本**

  脚本必须：

  - 从脚本自身位置解析仓库根路径，不依赖调用者当前目录。
  - 在临时目录把 stub 编译为名为 `NordicSigMeshSDK` 的测试模块。
  - 使用该模块、真实 `SunSmart/Common/Data/Node+Capability.swift` 和 contract test 编译 standalone test。
  - 将二进制写入 `/tmp/UpDownLightProductSupportContractTests`。
  - 执行二进制并把仓库根路径作为唯一参数传入。
  - 任一步失败立即返回非零退出码。

- [x] **Step 4: 运行契约并确认 RED**

  运行 `scripts/check_up_down_light_product_support.sh`。

  预期：编译因待新增的集中产品能力策略不存在而失败，或运行后明确指出 `0x2321` 配置/能力缺失。失败必须来自缺少本需求行为，而不是路径、stub 或脚本错误。

- [x] **Step 5: 检查测试改动范围**

  只允许出现 contract test、SDK stub 与检查脚本。确认尚未修改生产代码，并记录 RED 输出作为 TDD 证据。

## Task 2: 增加 App 配置及全部 App 侧能力门控

**Files:**

- Modify: `SunSmart/devices_config.json`
- Modify: `SunSmart/Common/Data/Node+Capability.swift`
- Modify: `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`
- Test: `Tests/Device/UpDownLightProductSupportContractTests.swift`
- Verify: `scripts/check_up_down_light_product_support.sh`

**Interfaces:**

- Consumes: Task 1 的失败契约与用户提供的设备配置。
- Produces: App 可识别的 `0x2321` 配置，以及由一个策略真值驱动的 Ratio/CCT steps、外部光感和 Motion Sensitivity 排除行为。

- [x] **Step 1: 向包内设备配置增加新设备**

  在 `0x2313` 与 `0x2401` 之间按当前 PID 顺序增加 `0x2321`，字段逐字使用 Global Constraints 中的配置。不得修改 `0x2491` 原记录。

- [x] **Step 2: 在现有能力文件内建立集中产品策略**

  在 `Node+Capability.swift` 中新增内部纯策略类型，并集中定义四个 CID/PID 行为：

  - Ratio 能力只允许 `CID 0x0A78` 下的 `0x2491` 与 `0x2321`。
  - CCT steps reader 能力允许 `CID 0x0A78` 下的 `0x2491`、`0x2492` 与 `0x2321`。
  - 外部光感灯具能力保留现有 PID 集合，并增加 `0x2321`。
  - Motion Sensitivity unsupported 能力保留现有 PID 集合，并增加 `0x2321`。
  - 不给其他 CID 的同 PID 设备开放能力。

  现有 `Node.supportsUpDownRatioControl` 和 `Node.supportsUpDownLightDefaultCctSteps` 保持名称和调用者不变，只委托给该策略。

- [x] **Step 3: 让 MeshNetwork 侧能力消费集中策略**

  在 `MeshNetwork+SunSmart.swift` 中：

  - `Node.isExternalLightSensorCapableLuminaire` 的静态入口委托给集中策略。
  - `Node.supportMotionSensitivity` 使用集中策略排除不支持产品。
  - 删除被策略替代的两组私有 Company ID/PID 常量，保留其他 Emergency、Gateway 等无关判断不动。

- [x] **Step 4: 运行 App 聚焦契约并确认 GREEN**

  运行 `scripts/check_up_down_light_product_support.sh`。

  预期：输出 `UpDownLightProductSupportContractTests passed`，退出码为 0。

- [x] **Step 5: 校验 JSON 与 App 源码范围**

  - 使用系统 JSON 工具确认 `SunSmart/devices_config.json` 语法有效。
  - 搜索 App 可执行 Swift 源码中的 `0x2491`，确认四类产品行为统一收敛到集中策略，消费者不再独立维护同类 PID 名单。
  - 确认没有修改图片、本地化、数据库 schema、Xcode target membership 或依赖。

- [x] **Step 6: 建立 App 检查点**

  执行 `git diff --check` 和 `git status --short`，审阅本任务的六个文件。未经授权不提交。

## Task 3: 让 SDK 按旧设备规则处理 CCT default steps

**Files:**

- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/NodeCctDefaultValueTests.swift`
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Node/Node+Propertys.swift`
- Create: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Node/UpDownLightProductPolicy.swift`
- Create: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/Standalone/UpDownLightProductPolicyTests.swift`
- Create: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/scripts/check_up_down_light_product_policy.sh`

**Interfaces:**

- Consumes: `Node.isUpDownLightDefaultCctStepsProduct`、`defaultAbsoluteCctRange`、`effectiveCctRange`、`upDownLightDefaultCctSteps` 和现有数据库保存逻辑。
- Produces: `0x2321` 与 `0x2491` 相同的 5/6 steps 默认值、有效范围、状态回写和持久化资格。

- [x] **Step 1: 扩展 SDK CCT 默认值测试并保持旧回归**

  将现有 Up/Down Light 测试的产品输入扩展为 `0x2491` 与 `0x2321`，对两个 PID 分别覆盖：

  - 默认 Change Control Page 为 Tunable White。
  - 默认 steps 为 5，默认和有效范围为 2700K...5000K。
  - steps 为 6 时默认和有效范围为 2700K...6500K。
  - 非 5/6 值归一为 5。
  - 自定义 Absolute CCT Range 优先。
  - 6 steps 能忽略旧的 2700K...5000K legacy range。
  - Vendor status 回写后缓存变为 6，并更新默认/有效范围。

  保留 `0x2492` 的全部现有测试，继续证明 Downlight 行为不变。

- [x] **Step 2: 运行 SDK 产品策略契约并确认 RED**

  创建并运行 `scripts/check_up_down_light_product_policy.sh`，直接编译真实生产策略文件。首次编译因策略尚不存在而失败，确认缺少 `0x2321` 产品资格。

  `swift test --filter NodeCctDefaultValueTests` 另行尝试，但现有 Package 源码依赖 UIKit，macOS SwiftPM host 在测试编译前报 `no such module 'UIKit'`；该结果只记录为测试宿主限制。

- [x] **Step 3: 最小扩展 SDK 产品资格**

  新增内部纯策略，将 `0x2321` 加入 `0x2491`、`0x2492` 的 CCT steps 集合语义，并让 `isUpDownLightDefaultCctStepsProduct` 委托该策略。不得修改：

  - `isSingleWhiteDefaultCctProduct`。
  - 5/6 steps 的归一规则。
  - 默认范围常量。
  - `effectiveCctRange` 的 legacy range 兼容规则。
  - 数据库字段或 Vendor status 解析。

- [x] **Step 4: 再次运行 SDK 产品策略契约并确认 GREEN**

  在 SDK 仓库运行 `scripts/check_up_down_light_product_policy.sh`。

  预期：输出 `UpDownLightProductPolicyTests passed`，并明确覆盖 CCT steps 的 `0x2491`、`0x2321`、`0x2492` 以及 CID/PID 空值和其他 CID/PID 负例。

- [x] **Step 5: 检查 SDK 持久化链路未被绕过**

  静态确认 `MeshDatabase.savePropertys()` 仍依据 `isUpDownLightDefaultCctStepsProduct` 决定是否保存 steps。不得增加 App 侧数据库特判。

- [x] **Step 6: 建立 SDK CCT 检查点**

  在 SDK 仓库执行 `git diff --check` 和 `git status --short`，审阅本任务的两个文件。未经授权不提交。

## Task 4: 让 SDK 为新设备配置 Group Vendor Model subscription

**Files:**

- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/UpDownLightVendorMessageTests.swift`
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Node/Node+SupportModels.swift`
- Reuse: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Node/UpDownLightProductPolicy.swift`
- Test: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/Standalone/UpDownLightProductPolicyTests.swift`

**Interfaces:**

- Consumes: `Node.isUpDownLightUpRatioCapable`、`Node.getSubscribeToGroupMessages(_:)` 和现有 Sunricher Vendor Model。
- Produces: `0x2321` 加入 Group 时生成与 `0x2491` 相同的 Vendor Model subscription，且已有订阅时不重复生成。

- [x] **Step 1: 扩展 Group subscription 测试**

  让现有正例和去重测试分别对 `0x2491` 与 `0x2321` 执行，并断言：

  - 未订阅时生成目标 Group Address 的 Sunricher Vendor Model subscription。
  - 已订阅时不重复生成。
  - `0x24A1` 负例仍不生成 Vendor subscription。
  - 缺少 Sunricher Vendor Model 时不生成 Vendor subscription。

- [x] **Step 2: 扩展 Ratio 产品策略契约并确认 RED**

  在 standalone 测试中调用尚不存在的 `supportsUpDownRatioControl` 并运行检查脚本。

  预期：因 Ratio 产品资格入口不存在而编译失败；失败必须来自本需求行为缺失。

- [x] **Step 3: 最小扩展 SDK Group 能力**

  只扩展 `isUpDownLightUpRatioCapable` 的产品判断，使其继续要求：

  - Company ID 为 `0x0A78`。
  - Product ID 为 `0x2491` 或 `0x2321`。
  - Sunricher Vendor Model 存在。

  不修改 Group Address、Model ID、subscription message 生成或 Vendor SET 编码。

- [x] **Step 4: 再次运行 SDK 产品策略契约并确认 GREEN**

  在 SDK 仓库运行 `scripts/check_up_down_light_product_policy.sh`；使用 generic iPhoneOS `build-for-testing` 编译生产 Package，并使用 iPhoneOS SDK 对两个相关 XCTest 文件执行静态类型检查。

  预期：纯策略契约全部通过；生产 Package test build 与 XCTest 静态类型检查成功。由于当前环境没有可运行的 iOS 真机 test destination，不把 XCTest 断言写成已执行通过。

- [x] **Step 5: 建立 SDK Group 检查点**

  在 SDK 仓库执行 `git diff --check` 和 `git status --short`，审阅本任务的两个文件。未经授权不提交。

## Task 5: 完成自动化、源码审计和双仓库集成验证

**Files:**

- Verify: 本计划 Scope and File Map 中列出的全部 App 与 SDK 文件。
- Verify: `SunSmart.xcodeproj/project.pbxproj`，只读确认本地 SDK 引用和四 target 资源归属，不修改。

**Interfaces:**

- Consumes: Tasks 1–4 的实现和测试。
- Produces: App/SDK 产品能力覆盖证据、回归测试结果和干净的 diff 检查结果。

- [x] **Step 1: 串行运行聚焦测试**

  按以下顺序运行，前一项结束后再运行下一项：

  1. `scripts/check_up_down_light_product_support.sh`
  2. SDK `scripts/check_up_down_light_product_policy.sh`
  3. SDK 两个相关 XCTest 文件的 iPhoneOS 静态类型检查

  三项都必须退出码为 0。

- [x] **Step 2: 记录 SDK 全量测试宿主限制**

  在 SDK 仓库运行 `swift test`。当前 Package 的生产源码依赖 UIKit，macOS SwiftPM host 在进入测试前报 `no such module 'UIKit'`。保留该限制，不把 standalone contract 或静态类型检查表述为 SDK 全量测试通过。

- [x] **Step 3: 审计所有旧 PID 产品门控**

  分别搜索 App 可执行 Swift 源码、包内设备配置和 SDK Sources 中的 `0x2491`。对每处结果建立检查结论：

  - 旧设备专属测试数据可以保留。
  - Ratio、CCT steps、外部光感和 Motion Sensitivity 四类产品行为必须由集中策略覆盖 `0x2321`。
  - 任何新增发现若属于同功能链，先补入聚焦测试，再补实现。
  - 文档历史记录不做机械替换。

- [x] **Step 4: 验证资源和 target 影响**

  只读确认：

  - 共享 `Assets.xcassets` 中存在 BidirectionalController 正常、离线、待同步资源。
  - `devices_config.json` 被四个 App target 的 Resources phase 引用。
  - 四个 target 都引用当前本地 NordicSigMeshSDK product。
  - 未新增或修改品牌专属资源。

- [x] **Step 5: 执行双仓库 diff 检查**

  在 App 和 SDK 仓库分别执行：

  - `git diff --check`
  - `git status --short`
  - 针对 Scope and File Map 的逐文件 diff 审阅

  确认无无关格式化、无 Auth、无本地化和依赖变更。未经授权不提交。

## Task 6: 验证四个 iPhoneOS target

**Files:**

- Verify: `SunSmart.xcworkspace`
- Verify: Tasks 1–4 修改的生产文件。

**Interfaces:**

- Consumes: 已通过自动化验证的 App 与本地 SDK。
- Produces: 四个品牌 scheme 的 generic iPhoneOS 编译证据。

- [x] **Step 1: 构建 SunSmart**

  直接使用项目规定的 Debug、iphoneos、generic iOS、关闭签名参数运行 `xcodebuild`，scheme 为 `SunSmart`。预期 `BUILD SUCCEEDED`。

- [x] **Step 2: 构建 Archipelago**

  使用相同参数直接运行 `xcodebuild`，scheme 为 `Archipelago`。预期 `BUILD SUCCEEDED`。

- [x] **Step 3: 构建 SLG Sync Plus**

  使用相同参数直接运行 `xcodebuild`，scheme 为 `SLG Sync Plus`。预期 `BUILD SUCCEEDED`。

- [x] **Step 4: 构建 SylSmart**

  使用相同参数直接运行 `xcodebuild`，scheme 为 `SylSmart`。预期 `BUILD SUCCEEDED`。

- [x] **Step 5: 汇总构建边界**

  分别记录四个 scheme 的成功或首个失败 stage。只有四个都成功时才能声明多 target 静态构建通过；不得据此声明真机、BLE、Mesh、服务端或 Group subscription 已验收。

## Task 7: 完成服务端与真实设备验收

**Files:**

- Verify only: 服务端 `/devicesConfig` 真实响应。
- Verify only: `CID 0x0A78 / PID 0x2321` 真机及真实 Mesh 网络。

**Interfaces:**

- Consumes: 已构建 App、已同步服务端配置、真实新设备。
- Produces: 发布前端到端验收记录；不把 HTTP 200、Mesh ACK 或单项状态误写成整条链路成功。

- [ ] **Step 1: 验证服务端设备配置**

  在目标发布区域获取真实 `/devicesConfig` 响应，确认存在且仅存在一条 `0x0A78 / 0x2321`，七个字段与 Global Constraints 完全一致。验证响应进入内存并写入本地数据库后，重启 App 仍可识别该设备。

- [ ] **Step 2: 验证新安装与升级缓存路径**

  - 新安装且无设备配置缓存：确认包内 JSON 可识别设备。
  - 升级安装且已有旧配置缓存：确认服务端刷新后可识别设备。
  - 服务端刷新完成后再次进入添加、恢复和重置入口，确认配置没有被覆盖丢失。

- [ ] **Step 3: 验证添加与 Composition**

  分别验证 Classic 和 Professional 添加入口；至少验证一次 Restore 或 Reset 配置入口。记录：

  - 名称、型号、双向灯图标和 Lighting 类型。
  - 地址预算为 3 Elements。
  - Provisioning 后实际 Composition 包含旧设备功能所需的 Lightness、CCT 和 Sunricher Vendor Model。

- [ ] **Step 4: 验证 CCT default steps 链路**

  分别覆盖设备返回 5 和 6 的样本或可控固件状态，并记录原始 Vendor response：

  - 5 对应默认 2700K...5000K。
  - 6 对应默认 2700K...6500K。
  - 重启 App 后保存值和有效范围不丢失。
  - 超时/错误样本只验证 fallback，不把 fallback 记录为设备成功响应。

- [ ] **Step 5: 验证单灯页与 Device Parameter Settings**

  验证：

  - Up/Down 顶部视觉、Ratio GET、Ratio SET success status、失败回滚。
  - Brightness、CCT 和 Ratio 对顶部视觉的共同影响。
  - Change Control Page 在 Tunable White / Single White 间切换后，单灯页和 Cell 的 CCT 显隐正确。
  - Absolute CCT Range 自定义、Reset、输入 clamp、slider 和快捷按钮范围正确。

- [ ] **Step 6: 验证 Content Display**

  在同一 Space 切换：

  - Device Name Display。
  - CCT Quick Buttons。
  - Simple / Detailed Control Style。

  确认 `0x2321` 单灯页与包含该设备的 Group 页都继承 Space 设置，且不需要设备专属 Content Display 配置。

- [ ] **Step 7: 验证 Group subscription 与控制**

  将 `0x2321` 加入 Group，分别记录配置阶段和控制阶段：

  - 配置阶段确认 Sunricher Vendor Model 对目标 Group Address 的 subscription status 成功。
  - Group 页因包含 `0x2321` 显示 Ratio mode button。
  - Group Ratio SET 使用 Group Address，设备实际改变 Up/Down Ratio。
  - 混合 Group 中所有 Up/Down 设备同步变化，普通灯不写入 ratio。
  - Group CCT 范围合并、成员 clamp、限制提示和 Content Display 行为正确。

- [ ] **Step 8: 验证额外能力及回归**

  - 外部光感 Calibration/Profile 路径把 `0x2321` 视为支持灯具。
  - Device Parameter Settings 不为 `0x2321` 展示 Motion Sensitivity。
  - `0x2491` 全部旧行为不变。
  - `0x2492` 继续支持 CCT steps，但没有 Ratio UI、Ratio Group button 贡献或 Vendor Ratio subscription。
  - 普通 Lighting PID 行为不变。

- [x] **Step 9: 形成最终验收报告**

  报告必须分开列出：App contract、SDK focused tests、SDK full tests、四 target builds、服务端响应、真机单播、真机 Group subscription/组播。任何未执行项明确标记为未验收。

## Final Review Checklist

- [x] 设计文档的 9 类影响面均有对应实施或验收步骤。
- [x] App 中 Ratio、CCT steps、外部光感和 Motion Sensitivity 四类能力由同一策略覆盖 `0x2321`。
- [x] SDK 只修改 CCT steps 与 Group Vendor subscription 两个产品能力门控。
- [x] `0x2321` 的配置字段逐字匹配用户输入。
- [x] `0x2492` 未获得 Ratio 能力。
- [x] 未新增页面、资源、本地化、数据库字段、Auth 或依赖。
- [x] App 与 SDK 的聚焦测试、diff 检查均有结果。
- [x] 四个 iPhoneOS scheme 均有独立构建结果。
- [x] 服务端与真机证据没有被静态测试或构建结果替代。
- [x] 未经授权没有创建 Git commit。

## Execution Handoff

本计划按项目偏好固定使用 **Inline Execution**。只有在用户明确要求开始实施后，才调用 `superpowers:executing-plans` 按 Task 1–7 顺序执行并在阶段检查点汇报；不使用 subagents。
