# Light Information Date time / Time zone 需求分析与开发规划

## 1. 结论

需求方向合理，现有架构也可以支持。2026-08-20 已确认全部 P0 业务边界与 P1 交互细节，需求范围现已闭合；进入代码实现前继续按显式审批执行。

可以确认的目标是：仅从 `Site -> Main -> Lights` 进入普通灯详情，再打开 Information 时，对支持 SIG Mesh `TimeGet` 的灯追加与 Gateway Information 相同位置、相同格式的 `Date time` 和 `Time zone` 两行；进入页面后自动读取，点击任一行可以重试。

已确认的核心业务定义如下：

1. 同时自动补齐灯节点的 Time Server AppKey Binding，以及手机本地 Provisioner 的 Time Client Binding。
2. 只有具备设备编辑权限的用户才允许自动补齐远端 Time Server Binding；无编辑权限用户只读取已经正确配置的设备。
3. 读取成功后只可靠保存本地 Node 时间快照，不新增普通灯 Cloud sync。
4. 2026-08-20 更新：不支持 TimeGet 的灯仍展示两行，右侧显示本地化的 `Not supported`；Mesh 未连接时两行显示 `--` 并提示 Toast。
5. 页面进入后若 Mesh 稍后才连接，不监听、不自动重试；用户点击任一时间行后才重试。
6. 远端 Binding 成功但 TimeGet 失败时保留 Binding，不执行回滚。

以上确认不改变其他既有边界：不伪造 Composition Model、不发送 TimeSet、不修改 Site timezone、不影响 Gateway 与其他共享 Information 入口。

## 2. 当前源码事实

### 2.1 Information 页面和入口范围

- Gateway 与普通设备当前共用 `DeviceInformationViewController`。
- Gateway 通过 `GatewayInformationContext` 显式开启时间行；普通设备默认不展示。
- 当前时间行位于 `Signal strength` 之后，顺序为 `Date time`、`Time zone`，标题分别复用现有本地化 Key `gateway_date_time` 和 `site_time_zone_row_title`。
- `Site -> Main -> Lights` 列表只加载 `node.deviceType == .light` 的节点，普通灯详情使用 `DeviceLightViewController`。
- 普通灯详情的 Information 入口目前调用 `DeviceInformationViewController(node:showsSceneSection:)`。
- 同一个 Information 控制器还被 `DeviceBaseViewController`、Gateway、Battery Power Switch、Emergency/Fire 等入口复用。因此不能只在共享控制器内部通过 `node.deviceType == .light` 自动开启时间行。
- `node.deviceType` 在缺少产品配置时默认回退为 `.light`，进一步说明它不适合作为本需求唯一范围开关。

结论：应由 `DeviceLightViewController.information()` 显式传入 Light Time Information Context；其他入口保持默认值，不展示时间行。这样才能严格满足“仅 Site - Main - Lights 类型入口”。

### 2.2 Gateway 实现不能直接复用运行时逻辑

Gateway 当前链路包含以下 Gateway 专属行为：

- 要求当前手机 direct Proxy Ready 的地址就是该 Gateway；
- 读取成功后推进 `GatewayModel` generation；
- enqueue `.syncGateway` 更新 Cloud `site.gateways[]` 快照；
- 使用 `GatewayInformationContext` 管理 Gateway 身份。

普通灯通过任意可用 Mesh Proxy 路由到目标灯，不要求当前 Proxy 就是该灯，也没有 `GatewayModel`。因此只能复用时间格式、请求去重、有效响应校验和回滚思想，不能直接把 `GatewayTimeInformationCoordinator` 套到灯上。

### 2.3 TimeGet 能力真值

- `TimeGet` 的目标是灯 Composition Data 中的 Time Server Model，SIG Model ID 为 `0x1200`。
- 当前 SDK 的 `node.timeModel` 会遍历实际 Elements 查找 `0x1200`，因此能够保留多 Element 设备的真实目标地址。
- `TimeGet` 响应是 `TimeStatus`，Opcode 为 `0x5D`。
- `TimeStatus.time.seconds == 0` 表示设备时间未知，不能作为可展示成功值。
- `Time Setup Server 0x1201` 是 `TimeSet` 所需模型；本需求只读，不应为了 TimeGet 强制要求或配置它。

因此建议将“设备支持 TimeGet”定义为：当前有效 Composition 中存在 `node.timeModel`。不能根据 PID 猜测，也不能在远端 Composition 中凭空新增 `0x1200`。如果本地 Composition 缺失或过期，需要单独定义“重新读取 Composition Data”的修复流程，不能把伪造 Model 当成补齐。

### 2.4 “Model 配置”存在两层

| 层级 | Model | 当前状态 | 本需求需要的处理 |
| --- | --- | --- | --- |
| 灯设备远端节点 | Time Server `0x1200` | `node.timeModel` 存在不代表已绑定当前可用 AppKey | 未绑定时发送 `ConfigModelAppBind`，严格校验 `ConfigModelAppStatus` 后再 TimeGet |
| 手机本地 Provisioner | Time Client `0x1202` | SDK 会创建该 Model，但 `ensureLocalClientModelBindings()` 的白名单当前只有 Sensor Client 和 Scene Client | 应把 Time Client 纳入同一 AppKey 的幂等本地绑定修复，并保存本地 Node |

远端 Time Server Binding 使用 Device Key，属于真实设备配置变更；本地 Time Client Binding 只修改 App 本地 Mesh 配置数据库。两者的权限和失败语义不能混为一谈。

### 2.5 当前 TimeStatus 的副作用

SDK 在业务回调前会把收到的任何 `TimeStatus` 写入 `node.timestamp/node.timezone` 并调用 `savePropertys()`。因此 Light Coordinator 也必须像 Gateway 链路一样：

- 请求前保存旧的 timestamp/timezone；
- 只接受 typed `TimeStatus`、非零 seconds 和有效 Offset；
- 无效回包、页面退出后的回包或本地保存失败时恢复旧值；
- 有效结果才原子更新两行。

否则 `seconds == 0` 或过期回包可能污染本地设备状态。

## 3. 建议补全后的产品规格

### 3.1 展示范围

| 场景 | 是否展示两行 |
| --- | --- |
| `Site -> Main -> Lights -> 普通灯详情 -> Information`，且存在 Time Server | 是，展示读取值或 `--` |
| 同一路径，但 Composition 不含 Time Server | 是，两行均展示 `Not supported` |
| Gateway Information | 保持现状 |
| Switch、Sensor、Dongle、Battery Power Switch、Emergency/Fire 等共享 Information 入口 | 否 |
| 其他未来直接调用 `DeviceInformationViewController` 的入口 | 默认否，必须显式传入 Context 才开启 |

这里的“所有灯设备”包含该入口下不具备 Time Server 的灯；不支持设备只展示能力结论，不伪造 Model，也不发送配置或读取消息。

### 3.2 页面行为

1. 页面进入时先判断 Light Context 与 `node.timeModel`。
2. 不支持 TimeGet：追加两行，右侧均显示本地化的 `Not supported`；不发送配置或读取消息。
3. 支持 TimeGet：在 `Signal strength` 后追加 `Date time`、`Time zone`，初始显示 `--`。
4. 确认 App 已连接当前 Mesh 网络。普通灯不要求 direct Proxy，也不主动切换 Proxy。
5. 幂等修复本地 Time Client Binding。
6. 检查目标灯 Time Server 是否绑定本次通信使用的 AppKey；需要时先配置并验证。
7. Binding 成功或原本已正确配置后，向 Time Server 所在的实际 Element 发送一次 `TimeGet`。
8. 有效 `TimeStatus` 使用同一响应生成两行：
   - `Date time`：`yyyy-MM-dd HH:mm:ss`；
   - `Time zone`：`UTC±HH:mm`。
9. 点击任一时间行重新执行“连接检查 -> Binding 检查 -> TimeGet”；进行中的请求忽略重复点击。
10. 页面退出后隔离旧配置回调和旧 TimeStatus，不允许旧结果刷新已离开的页面或覆盖新请求。

标题和格式建议与 Gateway 当前实际 UI 完全一致，继续显示 `Date time` 与 `Time zone`，不要因需求描述中的 `Date-time` / `Timezone` 另起一套文案。

### 3.3 失败行为

- Mesh 未连接：不配置、不读取；两行保持 `--`，使用本地化提示，并允许点击重试。
- 本地 Time Client 修复失败：不发送 TimeGet，按读取失败处理。
- 远端缺少 Node Application Key：不尝试构造虚假配置，按配置失败处理。
- `ConfigModelAppBind` 超时、错误状态或响应字段不匹配：不发送 TimeGet，保留旧值并允许重试。
- TimeGet 超时、错误类型、seconds 为零或 Offset 无效：恢复请求前 Node 值；首次读取保持 `--`，已有页面成功值则保留上次成功值。
- 本地 Node 保存失败：恢复旧值，不刷新两行。
- 每次失败最多展示一次 Toast，避免 Binding 和 TimeGet 两阶段连续报错。

### 3.4 数据边界

建议本需求保持只读语义：

- 允许保存有效 `TimeStatus` 到本地 Node，因为 SDK 本身已有该行为，业务层需要校验并使其可靠；
- 不发送 `TimeSet`；
- 不修改 Site timezone；
- 不推进 `GatewayModel`；
- 不 enqueue `.syncGateway`；
- 不因进入 Information 主动触发普通灯 Cloud sync；
- 不改变 Timed、Scheduler、Sync Devices、Restore、Fast Add 等既有时间同步流程。

如果产品要求把灯时间快照立即上传服务器，需要另行确认普通 Node 的服务器字段所有权、更新 API、冲突策略和回读成功边界，不能照搬 Gateway Register。

## 4. 已确认决策

### P0：已于 2026-08-20 确认

1. **自动补齐范围**
   - 已确认同时修复手机本地 Time Client Binding 和灯设备远端 Time Server Binding。
   - Composition 不含 Time Server 时不伪造远端 Model，按不支持 TimeGet 处理。

2. **配置权限**
   - 已确认仅有 `space.deviceOperates.contains(.edit)` 权限时允许自动补齐远端 Binding。
   - 无编辑权限用户只读取已正确配置的设备；配置缺失时不修改远端设备，并按读取失败处理。

3. **云端行为**
   - 已确认只可靠保存本地 Node，不新增普通灯 Cloud sync。
   - 不触发普通 Node 或 Gateway Cloud 更新，不补充新的服务器合同。

### P1：已于 2026-08-20 确认

4. **不支持 TimeGet**
   - 原决策为隐藏两行；2026-08-20 更新为仍展示 `Date time` 和 `Time zone`，右侧均显示本地化的 `Not supported`。

5. **Mesh 未连接**
   - 已确认两行显示 `--` 并提示一次 Toast，不复用 Gateway 专属的 `Gateway not connected` 文案。

6. **连接稍后恢复**
   - 已确认页面不持续监听 Mesh 连接、不自动重试；用户点击任一时间行后才重新执行连接检查与读取。

7. **Binding 成功、TimeGet 失败**
   - 已确认保留已完成的 Binding，不回滚；下次重试跳过已完成的幂等配置，只重试后续读取。

## 5. 推荐架构

### 5.1 App 层

新增独立的 Light Time Information Context 和 Coordinator，保持 Gateway Coordinator 不变。

职责划分：

- `DeviceLightViewController`：只负责从目标入口显式开启能力，并传入是否允许配置 Model 的权限。
- `DeviceInformationViewController`：只负责行展示、点击重试、页面退出通知；不直接拼装配置消息。
- `LightTimeInformationCoordinator`：负责能力判定、连接检查、Binding 流程、TimeGet、回包校验、Node 回滚/保存和请求生命周期。
- 通用纯逻辑 Formatter/Core：复用 Gateway 已验证的 Mesh epoch、Offset 和格式规则；可以保留 Gateway 兼容别名，避免无关调用面变化。

不要把 Gateway 的 direct Proxy 与 Cloud sync 分支塞进 Light Coordinator，也不要在共享 Information 控制器里通过全局 Site/Space 反查权限。

### 5.2 SDK 层

本地 SDK 当前已作为四个 target 的 local Swift Package 引用。建议做一个最小 SDK 改动：

- 将 Time Client `0x1202` 纳入 `ensureLocalClientModelBindings()` 管理的本地 SIG Client 白名单；
- 保持方法幂等，只为当前 AppKey 补缺失 Binding；
- Binding 发生变化后继续保存 local Node；
- 不新增 Auth，不改变其他远端设备配置策略。

灯设备 Time Server 的远端 Binding 仍由 App Coordinator 通过标准 `ConfigModelAppBind` 完成，复用 `GatewayDetailClockCoordinator.bindIfNeeded` 已验证的响应字段校验方式，但不改变 Gateway 现有同步流程。

## 6. 预计修改范围

### App 仓库

- `SunSmart/Main/Device/Controller/DeviceLightViewController.swift`
  - 仅 Lights 详情 Information 入口传入 Light Context 与配置权限。
- `SunSmart/Main/Device/Controller/DeviceInformationViewController.swift`
  - 增加 Light 时间展示状态、两行重试路由和页面退出隔离；Gateway 行为保持不变。
- 建议新增 `SunSmart/Main/Device/Lights/Model/LightTimeInformationCoordinator.swift`
  - 实现 Binding + TimeGet 完整链路。
- 视复用方式调整 `SunSmart/Main/Device/Gateway/Model/GatewayTimeInformationCoordinator.swift`
  - 只抽取或兼容复用纯 Formatter/Core，不改 Gateway direct Proxy、Node 持久化和 Cloud sync 语义。
- `SunSmart.xcodeproj/project.pbxproj`
  - 新文件加入 SunSmart、Archipelago、SLG Sync Plus、SylSmart 四个 Sources phase。
- `Tests/Device/`、`scripts/`
  - 增加纯逻辑测试、运行时合同和聚焦检查入口。
- `SunSmart/en.lproj/Localizable.strings`、`SunSmart/zh-Hans.lproj/Localizable.strings`
  - 标题优先复用现有 Key；只有失败口径无法复用时才双语新增。

### 本地 NordicSigMeshSDK

- `Sources/NordicSigMeshSDK/MeshLib/Manager/MeshLibManager.swift`
  - 本地 Time Client AppKey Binding 补齐。
- `Tests/`
  - 增加当前 AppKey、缺失 Binding、已存在 Binding、切换子网后的幂等测试或聚焦合同。

### 明确不修改

- Gateway Information 的展示、direct Proxy 判定和 Gateway Cloud sync；
- Site timezone、Site props、Gateway timezone Review/Sync 流程；
- TimeSet、Scheduler、Timed、Fast Add、Restore 流程；
- Switch、Sensor、Dongle、Power Switch、Emergency/Fire Information 入口；
- 设备 Composition 内容；不支持 Time Server 的设备仅新增静态能力展示，不进行协议操作；
- 资源、依赖版本、Auth 信息及无关 target 配置。

## 7. 开发任务拆分

### Task 1：先固定规格和测试合同

- 建立范围矩阵测试，要求只有 `DeviceLightViewController` 的 Information 入口开启 Light Context。
- 固定 `Signal strength -> Date time -> Time zone` 顺序、点击重试和默认关闭语义。
- 建立纯逻辑测试，覆盖支持/不支持、Binding 决策、请求去重、旧回包、seconds 为零、正负/零/15 分钟 Offset。

### Task 2：补齐 SDK 本地 Time Client Binding

- 先写失败测试或源码合同，证明 Time Client 当前未在本地 Binding 白名单。
- 加入 Time Client，验证当前 AppKey 下首次补齐、重复调用无变化、切换 AppKey 后补齐新 Binding。
- 运行 SDK 聚焦测试和 `swift build` / 必要的 `swift test`。

### Task 3：实现 Light Time Information Coordinator

- 保存请求前 Node 时间快照。
- 校验 Mesh 连接、Time Server 实际 Element、Node Application Key。
- 按权限决定是否执行远端 `ConfigModelAppBind`。
- 严格验证 `ConfigModelAppStatus` 的 status、key index、element address、model identifier 和 company identifier。
- Binding 成功后发送 TimeGet，校验 typed/nonzero TimeStatus。
- 有效结果保存 Node 并生成 Snapshot；失败或过期结果恢复旧值。
- 保证 Binding/TimeGet 串行、单一 active attempt、页面退出隔离。

### Task 4：接入唯一目标入口和 UI

- 仅修改 `DeviceLightViewController.information()` 的构造参数。
- `DeviceInformationViewController` 在 Light Context 存在时追加两行；`node.timeModel == nil` 时显示 `Not supported`。
- 保留 Gateway 当前上下文和行为；其他调用点不传 Light Context。
- 复用现有双语标题；按确认后的失败口径补本地化。

### Task 5：聚焦验证与四品牌构建

- 运行新增 Light Information / Model Binding 测试。
- 回归 `scripts/check_gateway_information_time.sh`，证明 Gateway 原行为未破坏。
- 校验双语 strings、Xcode target membership 与 `git diff --check`。
- 串行执行四个 generic iPhoneOS Debug 构建，禁止 Simulator：SunSmart、Archipelago、SLG Sync Plus、SylSmart。
- SDK 修改完成后检查四个 target 均继续引用同一本地 NordicSigMeshSDK。

## 8. 验收矩阵

| 场景 | 预期 |
| --- | --- |
| 支持 TimeGet，远端/本地 Model 已正确配置 | 进入自动读取，两行同时显示有效值 |
| 支持 TimeGet，本地 Time Client 未绑定 | App 本地幂等补齐后成功读取 |
| 支持 TimeGet，远端 Time Server 未绑定，有配置权限 | Binding Status 验证成功后读取 |
| 支持 TimeGet，远端未绑定，无配置权限 | 不修改设备；展示确认后的失败状态并允许重试 |
| Composition 不含 Time Server | 不展示两行，不发送任何消息 |
| Time Server 在非 Primary Element | 向真实 Element 发送，正确匹配回包 |
| Mesh 未连接 | 不配置、不读取，保持 `--`，提示一次 |
| 灯离线/TimeGet 超时 | 保留上次有效 UI 和 Node 状态，允许重试 |
| `TimeStatus.seconds == 0` | 判失败并恢复旧 Node 状态 |
| 快速重复点击两行 | 只有一个 Binding/TimeGet operation |
| 请求期间退出页面 | 旧回调不更新 UI，不污染 Node |
| Binding 成功、TimeGet 失败 | Binding 保留，Node 时间回滚，下次只重试 TimeGet |
| Gateway Information | 展示、连接和 Cloud 行为与当前完全一致 |
| Switch/EFC/BPS 等共享 Information | 不出现新增时间行 |
| English / 简体中文、四品牌 target | 文案和编译均通过 |

## 9. 自动化无法替代的真实验收

即使聚焦测试、SDK 测试和四品牌 iPhoneOS 构建通过，仍不能证明以下结果：

- 真实灯固件是否接受 Time Server `ConfigModelAppBind`；
- 实际 Mesh Proxy 路由、AppKey/子网选择和 TimeStatus source 是否正确；
- 多 Element 灯、离线灯、断连重连和超时后的设备侧状态；
- Owner/Editor/Visitor 权限口径符合产品预期；
- iPhone/iPad 页面位置、滚动、点击和 Toast 视觉表现；
- SDK 本地 Time Client Binding 在真实导入网络、切换子网和旧数据库上的迁移效果。

这些需要至少一台“已正确配置”灯、一台“Time Server 未绑定”灯，以及一个不含 Time Server 的设备做真实 BLE/Mesh 验收。

## 10. 已确认实施基线

本需求后续实现必须遵循以下基线：

1. 只在 `DeviceLightViewController` 显式入口开启，其他共享 Information 页面不受影响。
2. 所有该入口下的灯显示两行；Composition 不含 Time Server 时两行均显示 `Not supported`，且不发消息。
3. 同时保证本地 Time Client 和远端 Time Server 与目标 AppKey 配置正确；绝不伪造远端 Composition Model。
4. 远端自动 Binding 受设备编辑权限控制；Visitor 只读取已经配置正确的设备。
5. 普通灯只保存校验通过的本地 Node 时间快照，不新增云同步，不发送 TimeSet。
6. 普通灯使用当前 Mesh Proxy 路由，不要求或主动建立对目标灯的 direct Proxy。
7. 失败保留上次有效值，单 Toast，点击任一时间行重试。
8. 不支持 TimeGet 时两行显示 `Not supported`；支持但 Mesh 未连接时两行显示 `--` 并提示一次 Toast。
9. Mesh 连接稍后恢复时不自动读取，只有用户点击时间行后才重试。
10. Binding 成功但 TimeGet 失败时保留 Binding，不回滚已完成配置。

按此方案，需求的用户价值、协议边界、权限、副作用、失败恢复和入口范围才是闭合的。
