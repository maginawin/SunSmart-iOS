# WiFi Gateway Server Information 恢复设计

## 1. 文档状态

- 日期：2026-07-10
- 状态：方案 A 已确认，等待书面审阅
- 设备范围：CID `0x0A78`、PID `0x2721` 的 WiFi Gateway
- 关联设计：`docs/260710_1555_wifi_gateway_repair_recovery_design.md`
- 关联实施总结：`docs/260710_1604_wifi_gateway_repair_recovery_implementation_summary.md`
- 已确认语义：离线时继续可执行的 Mesh 修复，但 Server Authorization 和 Server Information 未完成前，整体 Repair 不得成功

## 2. 背景与问题

WiFi Gateway 在添加过程刚显示 `Adding` 时断电，重新上电后可能进入 `The device needs to be repaired.`。现有 Repair 已能补齐 Composition、Key Bind 和 Gateway 业务配置，但 Server Information 仍存在一个独立缺口：

1. Recovery 只有在 `GatewayModel.mqttServerInfo` 已存在时才构造 `Server Information` 任务；本地为空时该任务被直接省略。
2. 最终验证使用 `node.getNodeSyncGatewayData(gateway:)`；该差异计算同样只在本地存在 MQTT 目标时比较设备状态。因此，本地目标为空会被误判为“没有 Server Information 差异”。
3. Repair 成功后触发的后台 `syncGateway` 虽然调用 Gateway Register，但当前成功分支没有解析和保存响应中的 MQTT 凭据。
4. 详情页手动 `Authorize` 对 Node export 失败、成功响应字段缺失等情况没有错误反馈；取得凭据后又直接发送一个未纳入 Sync 串行和结果验证的 Mesh 消息。
5. 页面展示使用的 `setGatewayModel` 是工作副本，Authorize 判断使用 `gatewayModel`；两份对象没有统一刷新时，可能出现页面仍显示未授权，但点击后因源模型已有值而静默跳过。

因此，当前问题不是单个按钮失效，而是“服务端授权、凭据持久化、设备下发、最终验证”分别处于不同入口，缺少统一的成功语义。

## 3. 目标

本次设计需要达到以下目标：

1. 将 `Server Authorization` 作为 WiFi Gateway Recovery 的一等任务。
2. Repair 只有在服务端授权、MQTT 信息持久化和设备下发全部完成后才能成功。
3. 手机离线不阻止 Composition、Key Bind 和其他独立 Mesh 恢复任务。
4. 网络恢复后的 Retry 只重试失败或被依赖跳过的服务器任务及最终验证。
5. Add、Repair、Authorize 和后台 `syncGateway` 共用同一套 Gateway Register 响应解析及持久化规则。
6. Authorize 不再静默失败，也不再绕过现有 acknowledged Mesh 消息串行机制。
7. 页面始终根据最新持久化 Server Information 渲染。
8. 错误日志不得输出 MQTT username、password、client ID 等认证信息。

## 4. 非目标

本次不包含以下改动：

- 不改变 CID/PID 范围外 Gateway 的 Repair 行为；
- 不改变 Visitor、Owner、有效 Editor 的既有 Gateway 权限设计；
- 不修改 Fast Add 的整体成功、回滚或删除策略；
- 不重新下发或修改 WiFi SSID、Password；
- 不新增、生成或硬编码任何 Auth 信息；
- 不从设备当前 MQTT 信息反推服务端应使用的目标凭据；
- 不重构通用 Cloud Sync、Sync 页面或 NetworkRequest 框架；
- App 公开能力足够时不修改 NordicSigMeshSDK。

## 5. 已确认产品语义

### 5.1 在线 Repair

网络和 Mesh 都可用时，Recovery 必须完成：

1. Initialize；
2. Associated Spaces；
3. Association Project；
4. Sync Spaces；
5. Server Authorization；
6. Server Information；
7. Final Verification。

只有所有必要任务成功并通过最终验证，才展示 Repair success。

### 5.2 离线 Repair

手机没有互联网但 Gateway Mesh Online 时：

- Initialize、Associated Spaces、Association Project、Sync Spaces 继续执行；
- Server Authorization 明确失败；
- Server Information 因缺少授权结果标记为 `Skipped`；
- Final Verification 因前置服务器任务未完成标记为 `Skipped`；
- 本轮 Recovery 以现有失败状态结束，不展示 Repair success；
- 已经成功的 Mesh 任务保留成功状态。

### 5.3 网络恢复后的 Retry

网络恢复后点击 Retry：

- 不重跑已成功的 Initialize 和 Gateway Mesh 任务；
- 重跑失败的 Server Authorization；
- 授权成功后重跑先前被跳过的 Server Information；
- 最后重新执行 Final Verification；
- 全部收敛后才显示成功。

## 6. 总体架构

采用方案 A：把 Server Authorization 和 Server Information 纳入同一个 Gateway Recovery 任务图。

```text
Initialize
├── Associated Spaces ─────────┐
├── Association Project ───────┤
├── Sync Spaces ───────────────┤
└── Server Authorization       │
        └── Server Information │
                               ▼
                     Final Verification
```

依赖规则：

- 所有业务任务依赖 Initialize；
- Server Information 同时依赖 Initialize 和 Server Authorization；
- 其他 Gateway Mesh 任务不依赖 Server Authorization；
- Final Verification 依赖全部适用任务；
- Server Authorization 失败不得阻止其他独立 Mesh 任务继续执行。

## 7. 组件设计

### 7.1 Gateway Server Authorization 服务

新增 App 内聚焦服务，职责包括：

- 检查手机网络状态；
- 导出 Node 数据；
- 调用 Gateway Register；
- 校验响应中的 `mqttUsername`、`mqttPassword`、`mqttClientId`、`host` 和 `port`；
- 构造 `GatewayInformation.MQTTConnectInformation`；
- 写入 `GatewayModel.mqttServerInfo` 并持久化；
- 返回明确、可区分的成功或失败结果；
- 对同一 Site 和 Gateway 的并发授权请求进行合并或串行，避免 Add、Cloud Sync、Repair、Authorize 重复注册。

服务同时提供“消费已有 Gateway Register 响应”的入口。后台 `syncGateway` 已经发出了相同请求，不应再重复请求，只需复用统一的响应解析与持久化能力。

明确错误至少包括：

- 手机无网络；
- Node export 失败；
- Gateway Register 请求失败；
- 成功响应缺少 `data`；
- MQTT 字段缺失或类型错误；
- MQTT 信息持久化失败。

任何错误都不能被转换为成功，也不能把不完整数据写入 GatewayModel。

### 7.2 Server Recovery 子任务构建器

将服务器恢复拆成可复用子任务：

1. `Server Authorization`
2. `Server Information`
3. 服务器信息验证

完整 Repair 把前两个任务嵌入 Gateway Recovery，并由现有 Final Verification 做总体收敛验证。手动 Authorize 复用同一子任务构建器，但只执行服务器子链和服务器信息验证，不重复完整 Initialize、Associated Spaces、Association Project 或 Sync Spaces。

`Server Authorization` 每次都在任务图中存在：

- 本地已有结构完整的 `mqttServerInfo` 时直接完成，不重复请求；
- 本地缺失时调用共享 Authorization 服务；
- 本地对象不能仅凭非空就视为有效，至少要满足构造 Server Information 消息所需字段完整。

`Server Information` 必须在实际开始执行时读取 GatewayModel 的最新 MQTT 信息，不能在任务图创建时捕获初始的 `nil`。这样授权任务成功后，下一任务可以直接使用刚持久化的目标。

### 7.3 Sync 执行器扩展

在现有 Sync 任务模型中增加聚焦的异步 Server Authorization 操作类型。该任务由 Sync 页面管理运行标识、状态和 Retry，但内部执行 HTTP 请求，而不是 Mesh 消息。

执行器需要遵守：

- HTTP 任务结束后再驱动依赖任务；
- 旧运行标识的回调不能更新新一轮 Retry；
- Server Authorization 失败只跳过 Server Information 和最终验证；
- 其他已具备依赖条件的 Mesh 任务继续执行；
- Retry 只重置 Failed 任务及其 Skipped 依赖后继，不重置 Success 任务；
- Server Information 继续使用现有串行 Mesh 消息执行能力并等待业务 Status。

### 7.4 Gateway 页面模型一致性

`gatewayModel` 继续作为持久化真值，`setGatewayModel` 继续作为页面编辑副本。由于 Server Information 不是页面可编辑字段，每次页面重新出现、收到 Gateway 数据变化通知或服务器恢复完成时，都将最新 `gatewayModel.mqttServerInfo` 同步到工作副本。

页面 Header、Cell、Authorize 按钮状态和点击逻辑统一读取同一个有效 Server Information，禁止展示模型和动作模型分别判断。

## 8. 各入口的数据流

### 8.1 Repair

1. 用户从 `The device needs to be repaired.` 点击 `REPAIR`；
2. 进入既有 Gateway Recovery Sync 页面；
3. Initialize 成功后，服务器授权和其他 Gateway 任务按依赖执行；
4. Authorization 取得并保存 MQTT 目标；
5. Server Information 从 GatewayModel 读取最新目标并通过 Mesh 下发；
6. 业务 Status 更新 Node 的设备侧 Gateway Information；
7. Final Verification 重新计算所有状态；
8. 满足完整成功条件后才显示成功。

### 8.2 手动 Authorize

1. 用户点击 `Authorize`；
2. 进行既有权限、Gateway Online 和 Proxy 可用检查；
3. 使用 WiFi 请求前置协调器等待已发出的自动 acknowledged 请求结束；
4. 进入服务器恢复 Sync 子链；
5. 执行 Server Authorization；
6. 执行 Server Information；
7. 验证设备侧 Server Information 与目标一致；
8. 成功后刷新页面并移除 `The server authentication is not completed.`。

Authorize 不再直接调用一个忽略返回结果的 Mesh send，也不再使用可能无限停留的 Window HUD。

### 8.3 Fast Add

Fast Add 保持现有总体流程，但 Gateway Register 响应改用共享解析和持久化规则：

- 返回有效 MQTT 信息时保存后再构造 Gateway Server Information 下发消息；
- 无网络、请求失败或响应无效时不伪造 MQTT 信息；
- 本设计不改变现有 Fast Add 对该失败的总体成功或回滚策略；
- 后续进入 Recovery 时会把本地 MQTT 信息缺失识别为未完成并允许恢复。

### 8.4 后台 syncGateway

后台 `syncGateway` 成功回调必须检查 Gateway Register 响应：

- 响应含完整 MQTT 信息时，复用共享解析器并保存；
- 本地 MQTT 信息为空且响应无法提供完整凭据时，不得把服务器授权标记为已完成；
- 本地已有有效 MQTT 信息而服务端更新响应不重复返回凭据时，可保留已有目标，但不能清空；
- Cloud Sync 只负责注册响应和本地持久化，不在后台直接向设备发送 Server Information；
- 页面或 Recovery 根据最新本地目标显示并执行后续 Mesh 同步。

## 9. 成功与状态真值

### 9.1 Server Authorization 成功

必须同时满足：

- 本地已有有效 MQTT 目标，或者本次 Gateway Register 返回完整字段；
- MQTT 信息已成功写入当前 GatewayModel；
- 持久化完成后重新读取仍能取得有效信息。

仅 HTTP 状态成功、仅业务 code 成功、字段不全或只更新内存，都不算成功。

### 9.2 Server Information 成功

必须同时满足：

- 使用最新持久化 MQTT 目标构造消息；
- 消息进入现有 acknowledged 串行队列；
- 收到匹配的 Gateway Vendor 业务 Status；
- Node 的设备侧 Gateway Information 更新为目标值。

只有 Transport ACK、超时、取消、离线或忽略 send 返回值，都不能算成功。

### 9.3 Repair 总体成功

WiFi Gateway Repair 最终必须满足：

- 所有必要任务没有 Failed 或 Skipped；
- `node.isKeybindComplete == true`；
- `gateway.mqttServerInfo` 存在且有效；
- 设备侧 MQTT Server Information 与本地目标一致；
- `node.getNodeSyncGatewayData(gateway:)` 为空。

最终验证需要显式检查 `gateway.mqttServerInfo`，不能只依赖当前差异函数，因为差异函数对 `nil` 目标不会生成 Server Information 差异。

## 10. 错误处理与用户反馈

- Sync 页面使用任务行表达 `Server Authorization`、`Server Information` 的 Success、Failed 和 Skipped；
- 一轮 Recovery 最多展示一次汇总结果，不为每个任务叠加成功或失败弹窗；
- 手机无网络时 Server Authorization 使用明确的网络错误，不显示通用成功；
- Gateway Register 响应字段无效时显示服务器授权失败，并保留可 Retry 状态；
- Authorize 的 Node export 失败、响应无效、Mesh 下发失败都必须有可见结果，不能点击无反应；
- 页面退出后旧 HTTP 或 Mesh 回调不得重新弹窗、导航或覆盖新状态；
- Debug 日志只记录 Gateway 标识、阶段、错误类型和缺失字段名，不输出字段值及认证内容。

新增用户可见任务名或错误文案时，必须同时补充 English 和简体中文。优先复用现有 `phone_no_network`、`server_failure` 等本地化 Key；任务行预计新增：

| English | 简体中文 | 用途 |
| --- | --- | --- |
| `Server Authorization` | `服务器授权` | Sync 任务标题 |

## 11. Gateway Register API 合同

App 无法自行重新生成服务端 MQTT password。因此，受影响 Gateway 能否在本地凭据已经丢失后恢复，取决于 Gateway Register 是否满足以下合同之一：

1. 对已注册 Gateway 重复调用时仍返回完整 MQTT 凭据；或者
2. 服务端提供等价的凭据恢复/重新签发能力。

如果重复注册只返回成功但不再返回 password，App 只能明确报告 Server Authorization 未完成，不能伪造配置或显示 Repair success。实施和真机验收必须确认该接口合同；若不满足，需要服务端配合，不能仅靠 iOS 修复闭环。

## 12. 预计改动边界

### App 代码

- `SunSmart/Main/Device/Gateway/Model/GatewayServerAuthorizationService.swift`
  - 新增共享注册、响应解析、校验和持久化能力。
- `SunSmart/Main/Site/Controller/SiteDeviceAddViewController.swift`
  - Fast Add 复用共享 Gateway Register 解析与保存规则。
- `SunSmart/Common/Cloud/CloudSynchronizationManager.swift`
  - `syncGateway` 成功时消费并保存 Gateway Register 响应。
- `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift`
  - 增加 Server Authorization 操作类型，收紧最终成功条件。
- `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`
  - 构建服务器子任务、动态读取 MQTT 目标并支持依赖式 Retry。
- `SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift`
  - Authorize 改走服务器恢复子链；统一页面模型刷新与结果处理。
- `SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift`
  - 复用现有 WiFi 请求前置协调及返回页面刷新。
- `SunSmart/en.lproj/Localizable.strings`
- `SunSmart/zh-Hans.lproj/Localizable.strings`
  - 补充无法复用的任务标题或错误文案。
- `SunSmart.xcodeproj/project.pbxproj`
  - 将新增共享文件加入所有使用 Common Gateway 代码的品牌 target。

### Contract checks

在 `scripts/` 增加或扩展聚焦检查，覆盖：

- Recovery 在 MQTT 目标为空时仍创建 Server Authorization 和 Server Information 依赖链；
- Final Verification 显式要求有效 `mqttServerInfo`；
- Server Information 在执行时读取最新 GatewayModel；
- Authorize 不再直接调用忽略结果的 Mesh send；
- Cloud `syncGateway` 不再丢弃 Gateway Register 响应；
- Add、Repair、Authorize、Cloud 复用共享解析规则；
- 日志不输出 MQTT password 等认证信息；
- English 和简体中文本地化完整。

## 13. 验证设计

### 13.1 静态与自动化验证

- 为 Gateway Register 响应解析增加单元或聚焦 Contract 测试：完整字段、缺少 data、字段缺失、port 类型错误；
- 验证 `mqttServerInfo == nil` 时 Recovery 仍包含服务器任务链；
- 验证 Server Authorization 失败后其他独立 Mesh 任务仍可执行；
- 验证 Retry 不重置已成功 Mesh 任务，只重置服务器失败链和最终验证；
- 验证最终检查不会把 `mqttServerInfo == nil` 当作成功；
- 验证 Authorize 与 Repair 使用相同服务器子任务；
- 运行现有 WiFi Gateway Repair、网络状态、凭据清理和 Associated Spaces 聚焦脚本；
- 对 English、简体中文 strings 执行 `plutil -lint`；
- 执行 `git diff --check`。

### 13.2 真机验收矩阵

| 场景 | 预期结果 |
| --- | --- |
| 添加刚进入 Adding 即断电，重新上电后 Repair，手机在线 | Repair 完成服务器授权和下发，成功后不显示 Server Authentication 或 Devices not synced |
| 同一场景，手机离线但 BLE Online | Mesh 任务继续；Server Authorization 失败；整体不成功 |
| 离线 Repair 后恢复网络并 Retry | 只执行服务器失败链和最终验证，完成后成功 |
| Gateway Register 返回成功但 MQTT 字段缺失 | Server Authorization 明确失败，不发送空 Server Information |
| Repair 成功后返回详情页 | 页面读取最新 GatewayModel，Server Information 已配置 |
| 正常详情中手动点击 Authorize | 进入服务器恢复链；成功、失败均有明确任务状态 |
| Authorize 期间已有自动 WiFi acknowledged 请求 | 等待当前自动请求结束，不并发发送 Mesh 请求 |
| Gateway 在 Server Information 下发中离线 | 当前任务失败，最终验证不成功，可重新 Retry |
| 后台 syncGateway 获得 MQTT 凭据 | 凭据保存到 GatewayModel，不被丢弃，不在后台绕过串行直接下发 |
| 已注册 Gateway 重复调用 Gateway Register | 确认服务端能返回或重新签发完整 MQTT 凭据；否则记录为服务端阻塞项 |

### 13.3 iOS 构建

共享 Gateway、Sync、Cloud 和本地化文件会影响多个品牌 target，实施完成后按项目规则使用 generic iPhoneOS 依次验证：

- SunSmart
- Archipelago
- SLG Sync Plus
- SylSmart

不得使用 Simulator 替代本轮 iOS 构建验证。

## 14. 完成标准

满足以下条件才可认为本问题修复完成：

1. Repair 不会在 Server Authorization 或 Server Information 缺失时显示成功；
2. 离线 Mesh 恢复和在线服务器恢复符合已确认的独立依赖语义；
3. Retry 只重试服务器失败链及其依赖后继；
4. Authorize 不存在静默返回和未验证 Mesh send；
5. Cloud Sync 不再丢弃可用 MQTT 凭据；
6. 页面展示、按钮判断和持久化 GatewayModel 一致；
7. Gateway Register 的重复注册凭据合同已通过真实环境确认，或明确登记为服务端阻塞；
8. 聚焦检查、本地化校验和四个品牌 target 的 generic iPhoneOS 构建通过；
9. 真机完成在线 Repair、离线 Repair、在线 Retry 和手动 Authorize 四条核心路径验收。
