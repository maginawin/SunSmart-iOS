# Space Mesh Node 上限由 300 提升到 500：源码分析与开发方案确认稿

## 1. 分析范围与结论

本报告基于以下源码快照进行静态分析：

- App：`fix` 分支，HEAD `591eab23`
- 本地 NordicSigMeshSDK：`dev` 分支，HEAD `5eb082d`
- App 与 SDK 工作区在分析开始时均无未提交改动
- 当前工程的 4 个品牌 target 均引用本地 `NordicSigMeshSDK`：`SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart`

核心结论：

1. 当前单个 Space 的 `300` 上限来自 App 的 `SpaceData.maxDevicesCount`，不是 NordicSigMeshSDK 的 Node 数量限制。
2. 把 `SpaceData.maxDevicesCount` 从 `300` 改为 `500`，现有多数底部计数和添加拦截会自动跟随变成 `500`，因为它们都读取该属性。
3. 现有限制属于客户端软限制，并未在最终批量 Provisioning 边界统一校验；手动多选批量添加和 Restore Device Data 流程存在绕过或超量风险。
4. NordicSigMeshSDK 没有发现 `300` 个 Node 的硬编码限制。SDK 按已分配的 Unicast Address Range 和设备 Element 数量分配地址，因此本需求原则上不需要修改 SDK 业务代码。
5. 服务端是否允许为同一 Site/Provisioner 继续申请足够多的 Unicast Address，无法仅由客户端源码确认，必须由后端接口或联调验证。
6. Switches 的 `16` 上限目前独立于 Node 上限，并且实际统计的是全部 `DeviceSwitchData`，包括 Kinetic Switch、Battery Power Switch、AC Power Switch，不只是本地化文案所说的 Kinetic Switch。
7. Kinetic Switch 本身不是被 Provision 到 Mesh 的 Node，所以不新增占用 Unicast Address；Battery/AC Power Switch 是真实 Mesh Node，需要占用 Unicast Address。这个模型没有问题，但 Power Switch 会同时占用一个 Node 名额和一个 Switch 名额。

## 2. 当前 300 个设备限制如何实现

### 2.1 唯一的 300 根值

`SunSmart/Common/Data/SpaceData.swift:208`：

- `maxDevicesCount` 默认值为 `300`。
- 该属性不在数据库、导入或导出逻辑中持久化，当前是每个 `SpaceData` 实例的本地默认值。
- Git 历史显示该值属于 App 产品策略：2025-03-06 引入，2025-07-18 从 `200` 调整到 `300`，未发现它来自 SDK 能力值。

### 2.2 实际统计口径

限制使用 `MeshNetworkManager.instance.realNodes.count` 作为已存在 Node 数量。

SDK 的 `realNodes` 位于：

- `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Manager/MeshLibManager.swift:809-821`

它排除本地 Provisioner 和其他 Provisioner，返回当前已加载 Mesh/Subnetwork 中的真实设备 Node。App 的 Space 摘要 `deviceCount`、云端导入摘要和 Main 添加拦截均沿用同一类统计口径。

需要特别区分：

- Node 数量：一个被 Provision 的物理设备算一个 Node。
- Unicast Address 数量：一个 Node 的每个 Element 都占一个连续地址。
- 因此“500 个 Node”不等于“500 个 Unicast Address”。

### 2.3 当前主动拦截位置

当前 App 在以下位置读取 `space.maxDevicesCount`：

| 入口 | 当前行为 | 源码证据 |
| --- | --- | --- |
| Main → Add Device | 在进入添加页前判断 `realNodes.count < maxDevicesCount` | `SunSmart/Main/Device/Controller/DevicesViewController.swift:486-492` |
| Classic Add 初始化 | 将 Space 上限复制到本地 `maxDeviceCount` | `SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift:258` |
| Classic Add 全选 | 按剩余名额截取可选设备 | `DeviceAddClassicModeController.swift:1055-1075` |
| Classic Add 单设备/队列添加 | 用现有 Node + wait/adding/addConnecting 数量拦截 | `DeviceAddClassicModeController.swift:2161-2164`、`:2233-2236` |
| Professional Add 候选列表 | 候选 View 从 Space 读取上限 | `SunSmart/Main/Device/View/DeviceAddCandidateDeviceListView.swift:60`、`:192` |
| Professional Add 全选 | 按剩余名额截取 | `DeviceAddCandidateDeviceListView.swift:285-297` |
| Professional Add 单设备/队列添加 | 用现有 Node + wait/adding/addConnecting 数量拦截 | `DeviceAddCandidateDeviceListView.swift:871-874`、`:986-989` |
| Group → Add Devices | 进入添加页前判断 Space Node 上限 | `SunSmart/Main/Group/Controller/GroupViewController.swift:1365-1371` |
| 空 Group → Add Devices | 空态入口执行相同判断 | `SunSmart/Main/Group/Controller/GroupMembersViewController.swift:352-359` |

### 2.4 当前方案的缺口

当前方案不能视为严格的 300 Node 硬限制，原因如下：

1. Classic/Professional 的手动逐项选择判断只统计已经处于 wait/adding/addConnecting 的设备，没有把尚未开始添加但已勾选的整批设备都纳入最终校验。
2. 批量开始添加前主要执行地址充足性和 Power Switch 16 个限制校验，没有统一重算“现有 Node + 在途 Node + 本次请求 Node”是否超过 Space 上限。
3. `DeviceRestoreViewController` 有 Unicast Address 充足性检查，但没有读取 `maxDevicesCount`，因此 Restore 流程可以突破逻辑 Node 上限。
4. 数据库加载、服务端导入和 Space 恢复不会按 `maxDevicesCount` 截断；如果已有数据超过上限，App 仍会加载。
5. 多处旧注释仍写“Space 只能添加 200 个设备”，与当前 `300` 已不一致。

所以当前方案更准确的描述是：“多数常用添加入口上的 UI/流程拦截”，而不是唯一、不可绕过的容量策略。

## 3. Main 页面当前有哪些数量限制

Space 的底部一级菜单 `Main` 对应 `DevicesViewController`，其二级分类只有 4 个：Lights、Switches、Sensors、Others。

| Main 分类 | 左下角当前显示 | 真正限制口径 | 结论 |
| --- | --- | --- | --- |
| Lights | `当前 Light Node 数量 / 300` | 添加时按全部 `realNodes / 300` | 分子与真正限制口径不一致；混有 Sensor、Power Switch 等 Node 时可能看起来未满但实际已满 |
| Switches | `全部 DeviceSwitchData 数量 / 16` | 全部 Switch 类型合计最多 16 | 保持不变；Kinetic、Battery、AC 共用 16 个名额 |
| Sensors | `全部 realNodes / 300` | 全部 `realNodes / 300` | 显示的是 Space 总 Node 数量，不是 Sensor 数量 |
| Others | `全部 realNodes / 300` | 全部 `realNodes / 300` | 显示的是 Space 总 Node 数量，不是 Others 列表数量 |

对应源码：

- Main 的 4 个实际子页面：`SunSmart/Main/Device/Controller/DevicesViewController.swift:796-828`
- Lights：`SunSmart/Main/Device/Lights/Controller/DeviceLightsViewController.swift:178-205`、`:324`
- Switches：`SunSmart/Main/Device/Switches/Controller/DeviceSwitchesViewController.swift:263`
- Sensors：`SunSmart/Main/Device/Sensors/Controller/DeviceSensorsViewController.swift:78`
- Others：`SunSmart/Main/Device/Others/Controller/DeviceOthersViewController.swift:160`

工程里仍存在旧的 `GatewaysViewController` 和 `EmerFireAlarmDevicesController`，也引用了 `space.maxDevicesCount`，但当前 Main 的 Page Controller 不会创建这两个页面，应按遗留/不可达代码处理，不应把它们误认为当前 Main 分类。

## 4. Main 之外还有哪些相关限制

### 4.1 同一 Node 上限的其他入口

- Group 详情的 Add Devices 入口。
- 空 Group Members 页的 Add Devices 空态入口。
- Classic Add 和 Professional Add 内部候选、单设备和队列逻辑。
- Power Switch 物理设备关联最终复用 Device Add，因此仍会经过 Device Add 内部限制。

### 4.2 没有执行 Node 上限的相关入口

- Restore Device Data：只检查地址是否够，不检查 `maxDevicesCount`。
- 服务端数据导入/本地数据库加载：不按上限截断。
- Site 级 Gateway 添加：该流程只扫描 Gateway，属于 Site 主网络，不使用当前 Space 的 Node 上限。

### 4.3 其他独立资源限制

这些限制不是“单 Space Mesh Node 500”本身，不应随本需求一起修改：

- Switches：16 个，保持不变。
- Scenes：16 个，当前有主动拦截。
- Timed/Schedules：16 个，当前有主动拦截。
- Groups：旧的 16 个判断已注释，当前主要受可用 Group Address 约束。
- Gateway 关联 Space：每个 Gateway 默认最多关联 10 个 Space。
- Gateway 关联 Node：曾有汇总 300 Node 的代码，但常量、展示和拦截均已注释，目前不是活动限制。
- Mesh OTA 一次可选择的升级目标数：由分发能力 `maxSize` 动态决定，与 Space Node 上限无关。

## 5. Switch 类型与 Mesh 地址的关系

### 5.1 Kinetic Switch

Kinetic/EnOcean Switch 在 App 中是 `DeviceSwitchData` 记录，而不是通过 Provisioning 加入网络的 Mesh Node：

- 本身不新增占用 Unicast Address。
- 它可以绑定一个已经存在的 Mesh Node 作为 Proxy；这个 Proxy Node 本来就已经计入 `realNodes`，绑定不会再次增加 Node 数量。
- 当开关需要控制目标时，会创建虚拟 Group 地址用于 Publication/Subscription。当前普通 Switch 面板按 2 个虚拟 Group 地址做可用性检查；这属于 Group Address，不属于 Node/Unicast Address。
- 它占用 16 个 Switch 名额中的 1 个。

### 5.2 Battery Power Switch / AC Power Switch

Battery/AC Power Switch 是实际被 Provision 的 Mesh Node：

- 在 `devices_config.json` 中，PID `0x2A01`、`0x2A02`、`0x2A11`、`0x2A12` 的 `elementCount` 均为 8。
- 因此每台设备算 1 个 Node，但需要连续保留 8 个 Unicast Address。
- 同时会创建/关联一个 `PJEightKeySwitchData`，因此也占用 16 个 Switch 名额中的 1 个。

这个“双重计数”是合理的：

- Node 上限约束真实 Mesh 设备规模。
- Switch 上限约束 App 的 Switch 配置记录和相关虚拟组/配置规模。

期望边界应明确为：

- Space 已有 500 个 Node，但 Switch 少于 16 个：仍可新增 Kinetic Switch。
- Space 已有 500 个 Node：不能再 Provision Battery/AC Power Switch。
- Space 有 499 个 Node 且 Switch 少于 16 个：可添加 1 个 Battery/AC Power Switch，完成后达到 500 Node；同时必须还有至少 8 个连续可分配 Unicast Address。
- Switch 已有 16 个：无论 Node 是否未满，都不能再新增 Kinetic/Battery/AC Switch。

### 5.3 现有文案的语义问题

`switchs_overrun_message` 的英文和中文都写成“Kinetic switches/动能开关最多 16 个”，但代码实际对全部 Switch 类型合计执行 16 个限制。若产品希望用户理解 Battery/AC 也占用该名额，后续可单独修正文案为通用 Switch 限制；这不是把 Node 上限改为 500 的必要改动，建议不要在未确认时顺带修改。

## 6. SDK 是否需要更新

### 6.1 当前结论：不需要为 500 修改 SDK 容量常量

本地 NordicSigMeshSDK 中未发现 Node/Device `300` 上限：

- Unicast Address 的协议范围为 `0x0001...0x7FFF`：`Address.swift:49`。
- 新 Node 的地址按 Provisioner 的 `allocatedUnicastRange` 和 `elementsCount` 查找连续空闲区间：`MeshNetwork+Custom.swift:69-127`。
- 可用地址数量同样根据实际已分配范围和已占用 Element 地址计算：`MeshAPI.swift:1064-1110`。

因此 App 把逻辑 Node 上限改为 500，不需要同步修改 SDK 的容量常量或数据模型。

### 6.2 需要验证但暂不建议直接修改 SDK 的事项

1. 当前支持设备的 `elementCount` 为 2、3、4 或 8。500 个 Node 在当前配置下可能需要约 1000–4000 个 Unicast Address，取决于设备组合。
2. App 地址不足时会调用 `applyAddress(siteId:type:number:)` 向服务端申请更多地址，并额外按当前已用地址数的 20% 申请余量。
3. 客户端接口的 `number` 是普通整数，未发现客户端 300 限制；但服务端地址池、单次申请数、累计申请数和响应负载限制需要后端确认。
4. SDK 的可用地址枚举和部分节点遍历在 500 Node 下可能增加 CPU/内存耗时。是否需要优化，应由 500 Node 数据和真实硬件压力测试决定，不应先猜测性修改 SDK。

SDK 更新触发条件建议定义为：只有 500 Node 压测明确证明地址查找、数据库加载、消息队列或节点状态刷新发生不可接受的性能/稳定性问题，才另立 SDK 优化任务。

## 7. 可选开发方案

### 方案 A：只把默认值 300 改为 500

改动：

- 将 `SpaceData.maxDevicesCount` 从 300 改为 500。
- 更新仍写 200 的旧注释。

优点：改动极小；现有引用该属性的标签和入口会自动显示/使用 500。

缺点：保留现有软限制缺口；Restore 仍可超限；手动多选批量添加仍缺最终总量校验；Lights 左下角分子仍与真实 Node 限制不一致。

结论：可作为临时版本，不建议作为长期交付。

### 方案 B：统一 Space Node 容量策略，并把上限设为 500（推荐）

设计：

1. 建立单一的 Space Node 容量策略，明确上限 `500`、当前 Node 数、在途 Node 数、本次请求数量和剩余名额。
2. 保留 `SpaceData.maxDevicesCount` 作为兼容入口，改为由统一策略提供，避免一次性改动全部调用方。
3. 在最终批量添加边界再次校验，不只依赖全选或单行点击时的 UI 判断。
4. Classic、Professional、Group 指定添加、Battery/AC 物理设备关联全部复用同一判断。
5. Restore Device Data 也执行同一 Node 上限；地址是否充足继续作为独立的第二层检查。
6. Main 中 Lights、Sensors、Others 的容量展示统一采用“Space 全部真实 Node / 500”；Switches 继续显示“全部 Switch / 16”。
7. 不修改 Kinetic/Battery/AC 的 16 个 Switch 限制，不修改 Scene、Timed、Group、Gateway 和 OTA 限制。
8. 不修改 SDK，先补 SDK/App 边界压力验证。

优点：限制口径统一；修复已发现的旁路；UI 与真实限制一致；后续再调整上限只改一处。

缺点：比方案 A 多涉及 Device Add、Restore 和测试文件，需要完整回归添加流程。

结论：推荐。

### 方案 C：服务端下发每个 Space 的动态 Node 上限

设计：服务端返回 Space 级 `maxNodeCount`，App 持久化并在离线时使用缓存/默认值。

优点：可按客户、站点或版本动态控制，无需发版再次调整。

缺点：需要后端协议、数据库迁移、离线策略、旧版本兼容和多端一致性；本次固定提升到 500 不需要承担这部分复杂度。

结论：除非已有明确商业需求，不建议纳入本次范围。

## 8. 推荐方案 B 的拟开发范围

### 8.1 App 文件范围

预计修改：

- `SunSmart/Common/Data/SpaceData.swift`
  - 将单 Space Node 上限定义为 500，并接入统一容量策略。
- `SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift`
  - 批量开始添加前做最终容量校验，统一处理剩余名额。
- `SunSmart/Main/Device/View/DeviceAddCandidateDeviceListView.swift`
  - 统一全选、手动选择、单个添加和批量提交口径。
- `SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift`
  - 在委托接收批量请求时执行最终策略校验，防止绕过 View 层。
- `SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift`
  - Restore 时应用 500 Node 上限，地址检查保持独立。
- `SunSmart/Main/Device/Lights/Controller/DeviceLightsViewController.swift`
  - 左下角分子改为 Space 全部真实 Node 数，避免显示 Light 数量却表达总容量。
- 必要的测试文件和轻量检查脚本。

预计无需修改：

- NordicSigMeshSDK 业务源码。
- Switches 的 16 上限与相关业务逻辑。
- 本地化字符串：`devices_number_exceeds_message` 已使用 `%d`，会自动展示 500。
- 数据库 schema：`maxDevicesCount` 当前不持久化，不需要迁移。
- 图片、资源和 target 配置。

如果新建公共策略源码文件，则必须同时加入 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 四个 target；为降低 target 配置风险，也可将小型策略放在现有 Common 文件中。

### 8.2 自动化验证

应覆盖以下边界：

1. 499 Node + 添加 1 个：允许。
2. 500 Node + 添加 1 个：拒绝。
3. 499 Node + 批量请求 2 个：只能接受剩余 1 个或整批拒绝，具体交互按确认后的产品规则实现；不能 Provision 到 501。
4. 已有在途设备时，剩余容量正确扣减。
5. Restore 不得突破 500。
6. 500 Node 时仍允许新增 Kinetic Switch，前提是 Switch 少于 16 且 Group Address 足够。
7. 500 Node 时禁止新增 Battery/AC Power Switch 的物理 Node。
8. 第 16 个 Switch 允许，第 17 个 Switch 拒绝；三种 Switch 类型合计统计。
9. Main 的 Lights、Sensors、Others 均显示总 Node 数/500；Switches 仍显示 Switch 数/16。
10. Unicast Address 不足时仍进入地址申请流程；Node 容量不足时不应先发起无意义的地址申请。

### 8.3 构建与真实环境验收

静态/构建验证：

- Focused capacity policy tests。
- 现有 Device Add/Restore/Switch contract tests。
- `git diff --check`。
- 对 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 执行 generic iPhoneOS Debug build，禁用代码签名。

真实环境验收：

- 使用接近 500 Node 的真实或服务器导入数据验证 Space 冷启动、进入 Main、切换四个分类、搜索、编辑和返回 Site。
- 对 499→500→拒绝第 501 个的 Classic、Professional、Group 指定添加和 Restore 路径分别验收。
- 验证 8-Element Battery/AC Power Switch 的连续地址申请和 Provisioning。
- 验证 500 Node 时 Kinetic Switch 的创建、Proxy 绑定、虚拟 Group 地址申请与控制不受 Node 上限误伤。
- 验证云端 Space/Site 上传与下载能完整保存 500 Node 数据。
- 对比 300 Node 基线，观察导入、数据库加载、地址查询、RSSI/Heartbeat 刷新、Group/Scene/Timed 列表、同步任务、内存和 CPU；如 SDK 层出现明确瓶颈，再建立独立 SDK 优化任务。

构建成功不等于 500 台真实 Mesh 设备可稳定工作。BLE Mesh 广播拥塞、Proxy 吞吐、批量状态刷新、服务器载荷和设备固件资源必须通过真实规模或等效压力测试验收。

## 9. 待确认的产品契约

推荐按以下契约实施：

- 每个 Space 最多 500 个真实 Mesh Node，按 Node 数而不是 Element/Unicast Address 数统计。
- Battery/AC Power Switch 各算 1 个 Node，并分别占用其实际 Element 地址；Kinetic Switch 不算 Node。
- Kinetic、Battery、AC 三种 Switch 合计仍最多 16 个。
- Main 中非 Switch 分类的容量指示统一显示 Space 总 Node 数/500；Switches 显示 Switch 数/16。
- Classic、Professional、Group 指定添加和 Restore 都不能突破 500。
- 批量请求超过剩余名额时，推荐沿用现有全选体验：只保留可添加的前 N 个并提示上限，而不是整批失败。
- SDK 暂不改代码；后端先确认地址池和请求/数据规模能力，SDK 只在压测证明确有瓶颈时另行优化。

确认以上契约和方案 B 后，再编写逐文件、逐测试步骤的正式实施计划，并按 Inline Execution 执行。
