# WiFi Gateway Proxy Ready 后 Time Set 设计

## 文档状态

- 状态：已确认
- 日期：2026-07-21
- 适用范围：SunSmart App 中 CID `0x0A78`、PID `0x2721` 的 WiFi Gateway
- 方案结论：目标网关的 Mesh Proxy Filter 完成后，先向网关发送一次 `Time Set`，结束后再开始页面自动读取 WiFi 状态；App 不配置网关的 `Time Role`

## 背景

当前 `Site → Space → Timed` 配置设备定时时，App 会在写入定时任务前按需向目标设备同步 Date-Time 和手机当前时区。WiFi Gateway 页面连接目标网关后也需要建立明确、稳定的时间同步时机，避免网关时间未初始化或时区不正确而影响后续依赖本地时间的业务。

现有连接链路中存在三个容易混淆的事件：

1. `connectProxy` 完成：仅表示 GATT Bearer 已打开，Proxy Filter 尚未完成，不能保证目标节点已经可以可靠接收 Mesh 消息。
2. Proxy Filter 完成：表示当前 Proxy 会话已经完成过滤器配置，是向当前 Proxy 节点发送 `Time Set` 的合适边界。
3. WiFi Gateway `43 0E` 返回 connected：仅表示 WiFi/AP 连接状态，不代表 Mesh Proxy 可达，也不应作为 Mesh `Time Set` 的触发条件。

因此，本设计以“目标网关的 Proxy Filter 已完成”为唯一主要触发条件。

## 目标

- 每个目标 WiFi Gateway 的 Proxy/GATT 会话最多同步一次时间。
- 使用发送时刻的手机当前时间和 `TimeZone.current` 生成 `Time Set`。
- 保证 `Time Set` 与页面自动发起的 WiFi acknowledged 请求不并发。
- 时间同步失败不能阻塞用户进入或使用 WiFi Gateway 页面。
- SDK 只暴露通用 Proxy Ready 能力，不感知具体 WiFi Gateway 的 CID/PID 或页面业务。
- 仅影响 CID `0x0A78`、PID `0x2721` 的 WiFi Gateway，不改变其他 Gateway 的现有行为。

## 非目标

- 不读取、不设置网关的 `Time Role`。
- 不改变 `Site → Space → Timed` 现有时间同步行为。
- 不在每次 WiFi 状态刷新或每条网关指令前重复发送 `Time Set`。
- 不以 `43 0E`、`43 12` 或互联网/MQTT 状态作为时间同步触发条件。
- 不在 SDK 内加入 SunSmart 业务型号判断。
- 不引入用户可见的时间同步进度、成功提示或失败提示。

## 设计原则

### Time Set 与 Time Role 分离

`Time Set` 用于更新节点时钟和时区相关信息；`Time Role` 用于定义节点在 Mesh Time 模型中的传播角色。两者职责不同。

本方案只负责时间同步，不对 `Time Role` 做 Get/Set。网关固件自行决定并维持其 Time Role。只有未来产品或协议明确要求网关充当 Time Authority 或 Time Relay 时，才应另行定义 App 与固件之间的 Time Role 配置契约。

### Proxy Ready 是可发送边界

SDK 在 Proxy Filter 更新成功后发布通用的 Proxy Ready 事件。该事件必须携带足以识别当前 Proxy 节点及当前连接会话的信息，使 App 能够：

- 判断 Ready 的节点是否为当前页面目标网关；
- 区分断线重连后的新会话；
- 忽略旧会话、其他 Proxy 节点或重复回调。

SDK 同时保留只读的“当前 Proxy Ready 上下文”，供事件发布后才创建的页面读取。事件与只读快照使用同一个会话标识，且断线、Proxy 切换或新 GATT 会话建立时必须使旧上下文失效。这样页面首次订阅和晚订阅都走同一套处理逻辑，不依赖事件恰好发生在页面存活期间。

不能直接使用原始 `connectProxy` completion，因为该 completion 发生在 GATT Bearer 打开阶段，早于 Proxy Filter 完成。

## 总体数据流

```text
SDK Proxy Filter 完成
        ↓
发布通用 Proxy Ready 事件（节点 + 会话标识）
        ↓
GatewayViewController 匹配当前目标节点
        ↓
调用默认空实现的窄作用域 Hook
        ↓
WiFiGatewayViewController 交给 TimeSyncCoordinator
        ↓
校验型号、Key Bind、Time Setup Model、当前 Proxy、会话状态
        ↓
发送一次单播 Time Set
        ↓
成功 / 失败 / 超时 / 跳过均结束前置阶段
        ↓
开始原有 WiFi 状态自动加载（43 12、43 0E）
```

## 分层职责

### NordicSigMeshSDK

SDK 在 `proxyFilterUpdated` 确认过滤器配置完成后，发布通用 Proxy Ready 事件。

SDK 负责：

- 明确 Ready 节点；
- 提供可区分 Proxy/GATT 会话的稳定标识或等价 generation；
- 提供当前有效 Ready 上下文的只读快照，支持晚订阅页面；
- 避免将已失效会话报告为当前 Ready；
- 保持事件为通用 Mesh 生命周期事件。

SDK 不负责：

- 判断 CID `0x0A78`、PID `0x2721`；
- 决定是否发送 `Time Set`；
- 管理 WiFi Gateway 页面加载顺序；
- 配置 `Time Role`。

### GatewayViewController

共享 Gateway 基类负责订阅和清理 Proxy Ready 事件，并只在事件节点与当前页面目标节点匹配时调用一个窄作用域 Hook。

Hook 默认无操作，因此其他 Gateway 页面保持现状。共享层不包含 WiFi Gateway 型号判断，也不改变其他子类的加载流程。

页面销毁或切换目标节点时必须移除/更新订阅，避免旧页面收到新会话事件。

### WiFiGatewayViewController

WiFi Gateway 子类覆写 Hook，将 Ready 上下文交给专用 `TimeSyncCoordinator`。页面首次建立观察后还应读取一次 SDK 当前 Ready 上下文，以覆盖页面创建前 Proxy 已 Ready 的情况。事件和快照最终进入同一个幂等入口。页面自身只负责协调“时间同步前置阶段”和“原有 WiFi 状态加载阶段”，不在控制器中堆叠 Mesh 消息细节。

现有在线状态回调不能在时间同步前置阶段尚未结束时立即发起 `43 12` 或 `43 0E`。如果在线状态先到达，应记录“需要加载”状态；待 TimeSyncCoordinator 完成或跳过后，只触发一次原有加载链路。

### TimeSyncCoordinator

协调器的会话去重状态必须由可跨页面实例复用的 Gateway/Mesh 生命周期服务持有，不能只存在于单个 ViewController 中。页面重建后再次提交同一 Ready 上下文时，协调器应返回该会话已经完成或正在处理，而不是再次发送。

协调器负责：

- 校验目标是否为指定 WiFi Gateway；
- 校验 Ready 节点是否仍为当前 Proxy；
- 校验节点 Key Bind 已完成；
- 查找可用的 Time Setup Model；
- 按会话去重；
- 在真正发送消息时读取 `Date()` 与 `TimeZone.current`；
- 发送一次单播 acknowledged `Time Set`；
- 将成功、失败、超时或跳过统一收敛为“前置阶段结束”；
- 输出调试日志，不展示用户错误。

协调器不负责 WiFi 私有协议请求，也不设置 Time Role。

## 触发与前置条件

处理分为“事件身份校验”和“有效会话内前置条件校验”两层。

以下身份条件必须首先全部满足：

1. 当前页面目标节点 CID 为 `0x0A78`、PID 为 `0x2721`；
2. Proxy Ready 事件对应当前页面目标节点；
3. 当前 SDK Proxy 仍然是该节点；
4. Ready 上下文仍对应 SDK 当前有效会话；
5. 页面与本次请求仍处于有效生命周期内。

身份条件不满足表示该事件与当前流程无关，必须直接忽略：不标记当前会话、不放行或启动 WiFi 状态加载，也不改变新会话状态。

确认是当前有效目标会话后，再校验以下发送条件：

1. `node.isKeybindComplete == true`；
2. 节点存在可用于发送 Time 消息的 `timeSetupModel`；
3. 当前 Proxy/GATT 会话尚未执行过本次时间同步尝试。

Key Bind 或 Time Setup Model 条件不满足时，将该有效会话记为已处理，跳过发送并允许后续 WiFi 状态加载继续。如果会话已经在处理，则当前页面等待共享结果；如果会话已经结束，则当前页面直接取得已结束结果并继续加载。

## 每会话一次的定义

“每会话一次”以 Proxy/GATT 会话标识或 SDK 提供的等价 generation 为边界，而不是以页面实例、节点地址或 App 生命周期为边界。

- 同一会话内收到重复 Proxy Ready：只允许第一次进入发送或跳过判断，后续重复事件不再次发送。
- 断线后重新建立新的 Proxy/GATT 会话：允许重新发送一次。
- Proxy 从其他节点切换到该 WiFi Gateway：该网关的新会话允许发送一次。
- 页面重新出现但复用同一个已经处理过的会话：通过 SDK Ready 快照和共享协调器取得既有结果，不重复发送。
- 旧会话的延迟回调：不得改变新会话状态，也不得触发 WiFi 状态加载。

会话应在开始处理时标记为“已尝试”，而不是成功后才标记，避免 SDK 重复回调或超时窗口内重复发送。

## 消息顺序与并发控制

目标顺序固定为：

1. Proxy Filter 完成；
2. `Time Set` 成功、失败、超时或确定跳过；
3. 原有 WiFi Gateway 状态加载开始；
4. 按现有串行策略执行 `43 12`、`43 0E` 等请求。

`Time Set` 不能与页面自动发起的 `43 12`、`43 0E` acknowledged 请求并发。这样可避免同一目标节点的 acknowledged 消息在初始化阶段相互干扰，并保持现有 WiFi 请求串行器的职责不变。

如果页面在线状态在 Proxy Ready 之前到达，页面只记录待加载意图，不立即发送 WiFi 请求。Proxy Ready 后完成/跳过时间同步，再消费该意图。若时间同步已完成而在线状态后到达，则在线状态可以直接触发原有加载链路。两条路径最终都必须通过同一个“一次性开始加载”入口去重。

## Time Set 数据来源

时间消息在实际发送前即时构造：

- Date-Time：使用发送时刻的 `Date()`；
- 时区：使用发送时刻的 `TimeZone.current`；
- 目标地址：当前 WiFi Gateway 节点单播地址；
- Model：目标节点的 Time Setup Model；
- 消息：acknowledged `Time Set`，等待对应 `Time Status` 或 SDK 错误/超时。

不缓存页面进入时的 Date-Time 或时区，避免连接过程较长或系统时区变化后发送旧值。

## 状态收敛与异常处理

时间同步前置阶段只有一个终态：允许页面继续加载。不同结果仅影响日志内容：

- 成功：记录节点、会话和成功结果，然后继续；
- 缺少 Time Setup Model：记录跳过原因，然后继续；
- Key Bind 未完成：记录跳过原因，然后继续；
- 型号、节点或会话身份不匹配：作为无关事件忽略，不改变当前有效流程；
- 发送失败：记录错误，然后继续；
- 超时：记录超时，然后继续；
- 页面失效或会话已切换：丢弃旧回调，不操作新页面/新会话；当前有效流程按自身状态继续。

失败和超时不展示 HUD、Alert 或 Toast，不阻塞页面，不在同一会话立即重试。下一次新的 Proxy/GATT 会话可再次尝试。

## 建议状态模型

协调器按会话维护以下概念状态：

- `idle`：尚未收到目标会话 Ready；
- `syncing`：已将该会话标记为尝试，并正在等待 Time Set 结果；
- `finished`：成功、失败、超时或跳过，允许后续加载；
- `invalidated`：SDK 会话断开或被替换，忽略该会话的后续回调。

页面另行维护一次性的 WiFi 状态加载门闩和请求令牌，确保在线状态回调与时间同步完成回调无论先后顺序如何，都只启动一次原有加载链路。协调器的会话状态跨页面实例复用；页面销毁只使该页面的请求令牌失效，不应抹除仍然有效的共享会话结果。

## 日志要求

仅输出调试日志，至少包含：

- 目标节点单播地址；
- Proxy 会话标识或 generation；
- 开始发送时间；
- 当前时区标识和 UTC offset；
- 成功、跳过、失败、超时或失效原因；
- 是否已放行 WiFi 状态加载。

日志不得输出 AppKey、NetKey、WiFi 密码或其他 Auth 信息。

## 预期改动边界

实现阶段预计只涉及以下窄范围：

- NordicSigMeshSDK：在 Proxy Filter Ready 真值点增加通用事件及会话标识；
- NordicSigMeshSDK：提供当前有效 Proxy Ready 上下文的只读快照，并在断线或会话替换时失效；
- App 的共享 Gateway 基类：订阅事件、匹配目标节点、暴露默认空 Hook；
- WiFi Gateway 页面：接入可跨页面复用会话状态的 TimeSyncCoordinator，并为自动 WiFi 状态加载增加前置门闩；
- 新增聚焦的协调器与对应测试；
- 必要的 SDK 事件测试和 App 行为测试。

不修改其他 Gateway 子类，不调整 WiFi 私有协议格式，不改变 Time Model 消息编码，不新增本地化文案或 UI 资源。

## 测试方案

### 单元与行为测试

至少覆盖：

1. 目标型号、当前 Proxy、Key Bind 和 Time Setup Model 均满足时发送一次；
2. 同一会话重复 Ready 不重复发送；
3. 新会话允许再次发送；
4. 非目标 CID/PID 不发送；
5. Ready 节点与页面目标不匹配时不发送；
6. Key Bind 未完成时跳过并放行加载；
7. 缺少 Time Setup Model 时跳过并放行加载；
8. Time Set 成功后开始 WiFi 状态加载；
9. Time Set 失败或超时后仍开始 WiFi 状态加载；
10. `43 12`、`43 0E` 不会在 Time Set 结束前自动发出；
11. 在线状态先到和 Time Set 完成先到两种顺序都只启动一次加载；
12. 页面销毁、目标切换或会话替换后，旧回调不会影响当前流程；
13. 发送时读取当前 Date-Time 和 `TimeZone.current`；
14. 页面在 Proxy Ready 之后才创建时，可通过当前 Ready 快照完成同一流程；
15. 页面重建并复用同一会话时不重复发送 Time Set；
16. 无关节点或旧会话事件被忽略，不能提前放行当前页面加载；
17. 全链路不会发出 Time Role Get/Set。

### 真机验证

至少覆盖：

- 首次进入 WiFi Gateway 页面并建立 Proxy；
- 同一会话反复进入/退出页面；
- 主动断开后重连；
- 从其他 Proxy 节点切换到目标网关；
- Time Set 正常响应；
- Time Set 不响应直至超时；
- 网关缺少 Time Setup Model 或 Key Bind 未完成；
- 手机切换到不同时区后重新建立会话；
- WiFi 已连接、未连接两种 `43 0E` 状态。

抓包或日志应证明消息顺序为 Proxy Ready → Time Set → WiFi 状态请求，且同一会话仅出现一次 Time Set。

### 构建验证

SDK 和 App 改动完成后，使用 iPhoneOS 分别验证所有引用 NordicSigMeshSDK 的相关 target：

- `SunSmart`
- `Archipelago`
- `SLG Sync Plus`
- `SylSmart`

构建使用真实设备通用目标并关闭签名，不使用 Simulator。

## 验收标准

- 目标 WiFi Gateway 每个 Proxy/GATT 会话最多收到一次 Time Set；
- Time Set 发生在 Proxy Filter 完成之后、自动 WiFi 状态请求之前；
- 消息使用发送时手机当前 Date-Time 和当前时区；
- App 不读取或设置 Time Role；
- 时间同步失败、超时或不具备条件时，页面仍能继续正常加载；
- 同一会话不立即重试，新会话允许重试；
- 其他 Gateway 行为不变；
- 不出现 Time Set 与 `43 12`、`43 0E` 自动请求并发；
- 旧页面或旧会话回调不会污染当前会话；
- 聚焦测试、四个相关 target 的 iPhoneOS 构建和真机关键路径验证通过。
