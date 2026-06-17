# Support Models AppKey Bind 设计

## 背景

Space 添加设备后的 AppKey 绑定由 SDK 的 `Node.supportModels` 驱动。App 在配置阶段调用 SDK 生成配置消息，`getConfigMessageHandles()` 遍历 `supportModels`，对未绑定当前 Space AppKey 的 model 生成 `ConfigModelAppBind`。

当前 SDK 已能通过普通 getter 或 Power Switch profile 让部分 client model 进入 `supportModels`。但对包含 Light Lightness Client 和 Light HSL Client 的普通设备，`supportModels` 不保证收集这些 client model，因此设备即使 composition 中存在这些 model，也可能不会在 Space 添加流程中绑定当前 AppKey。

## 已确认范围

本轮只处理以下两个 model：

| Model ID | Model 名称 | 处理方式 |
|---|---|---|
| `0x1302` | Light Lightness Client | 如果设备 composition 中存在，则加入 `supportModels` |
| `0x1309` | Light HSL Client | 如果设备 composition 中存在，则加入 `supportModels` |

以下两个 model 已明确不纳入本轮绑定范围：

| Model ID | Model 名称 | 处理方式 |
|---|---|---|
| `0x100A` | Generic Power Level Setup Server | 不加入 |
| `0x100B` | Generic Power Level Client | 不加入 |

## 目标

- 任何设备只要 composition 中实际存在 `0x1302` 或 `0x1309`，Space 添加设备配置阶段都应使用当前 Space AppKey 绑定这些 model。
- 不要求 App 新增业务判断或 EFC 专用配置入口。
- 不改变 Power Switch profile 的现有 required model 逻辑。
- 不影响没有这些 model 的设备。

## 非目标

- 不新增 Power Level 相关 AppKey bind。
- 不新增 publication、subscription 或目标地址配置。
- 不重做 EFC `0x4D/0x07` action config。
- 不新增 Auth 信息、不调整 target 配置、不改本地化资源。

## 方案

采用方案 A：在 SDK 的 `Node+SupportModels.swift` 中增加一组通用 additional client AppKey bind models。

该 helper 只做三件事：

1. 定义本轮需要额外绑定的 SIG Client Model ID 集合：`0x1302`、`0x1309`。
2. 遍历 node 的所有 elements，只收集 composition 中实际存在的 model。
3. 在 `supportModels` 末尾追加这些 model，并沿用现有去重规则，避免和 Power Switch profile 或已有 getter 重复。

App 层继续复用现有数据流，不新增 EFC 特例。

## 数据流

1. 添加设备流程读取 Composition Data，SDK node 获得 elements 和 models。
2. `supportModels` 先按现有逻辑收集 server model、vendor model、已有 client model 和 Power Switch profile model。
3. SDK 额外遍历所有 elements，发现 `0x1302` / `0x1309` 时加入 `supportModels`。
4. `getConfigMessageHandles()` 遍历 `supportModels`。
5. 如果目标 model 未绑定当前 Space AppKey，则生成 `ConfigModelAppBind`。
6. 现有添加流程负责发送消息、处理 ACK、保存 node 状态。

## 错误处理

本轮不新增独立错误处理分支。

- `ConfigModelAppBind` 下发失败时，沿用当前添加/配置流程的失败处理。
- `supportModels` 只收集实际存在的 model，不因为缺少 `0x1302` 或 `0x1309` 判定设备不完整。
- Power Switch required configuration 的强失败逻辑保持不变。

## 测试设计

在本地 `NordicSigMeshSDK` 增加 focused unit tests：

- 构造包含 `0x1302` / `0x1309` 的 node，断言两个 model 都进入 `supportModels`。
- 构造多个 element 都包含 `0x1302` / `0x1309` 的 node，断言实际存在的每个 model 都被收集。
- 构造不包含这两个 model 的 node，断言不会凭空产生额外 model。
- 覆盖 Power Level：构造包含 `0x100A` / `0x100B` 但不包含 `0x1302` / `0x1309` 的 node，断言它们不会因为本轮 helper 进入 `supportModels`。

推荐验证：

- SDK focused tests：`swift test --filter SupportModelsAppKeyBindTests`
- App iPhoneOS build：`xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

## 风险与约束

- 方案 A 是通用 SDK 行为，会让所有包含 `0x1302` / `0x1309` 的设备都绑定 Space AppKey，而不是只影响 EFC PID。该行为符合“如果设备有这些 Model 则同样需要绑定 Space Appkey”的需求。
- 如果某些历史设备 composition 暴露了这些 client model 但固件不希望绑定，方案 A 会扩大绑定集合。当前没有看到这类例外，且 AppKey bind 本身是配置阶段的标准能力。
- App 工程需要使用本地 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk` 的 SDK 改动进行验证。

## 验收标准

- `0x1302` / `0x1309` 存在于 composition 时，进入 `supportModels`。
- `0x100A` / `0x100B` 不因本轮变更进入 `supportModels`。
- Space 添加设备配置消息中能由现有链路为 `0x1302` / `0x1309` 生成当前 AppKey 的 bind 消息。
- SunSmart iPhoneOS build 通过。
