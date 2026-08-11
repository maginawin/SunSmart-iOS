# Site Sync Gateways 功能设计规格

## 1. 文档状态

- 日期：2026-08-13
- 状态：产品与技术设计已确认，等待规格审阅
- 范围：Site 的 Review sync 入口、Sync gateways 页面、BLE 时间同步、本地持久化、Gateway 云端回写与生命周期管理
- UI 基准：Figma `One-SunSmart`，主节点 `399:10732`，以及需求中给出的 Nearby、No signal、Syncing、Retry、Synced、Toast 和进度状态节点

## 2. 目标与成功标准

用户从 Site 的 Review sync 入口进入 Sync gateways 页面后，App 持续发现本次需要更新时区的 Gateway。用户可以逐台连接 Gateway，并通过一个完整的 SIG Mesh Time Set 同时写入当前日期时间和 Site 目标 timezone offset。

功能成功需要满足：

- 两个 Review sync 入口使用相同的数据与路由口径。
- 只统计进入任务时确实需要更新 timezone offset 的 Gateway。
- 同一时刻最多同步一台 Gateway。
- 有效 Time Status 与本地持久化成功后，立即将设备认定为 Synced，不等待云端。
- Synced Gateway 的本地变更复用 `.syncGateway` 上传到 `/sitespace/sapce/gateway/regist`。
- 页面退出能停止本页面拥有的扫描与未发送事务，同时允许已经发送的 Time Set 在无 UI 副作用的情况下收敛。
- Nearby、Other、进度、attention、按钮与 Toast 始终由同一状态模型驱动。

## 3. 已确认的业务口径

### 3.1 目标时区

- 正常进入 Site 后，使用已完成 App/Cloud 协调的 `app.site.timezone`。
- 进入 Sync gateways 时将其转换为不可变的 target timezone 快照；页面存续期间不反复读取可变 Site 对象。
- 若 App 与最新可信 Cloud Site timezone 不一致，则先刷新并重新协调，不能静默选择其中一方开始同步。
- Offset 按固定 GMT 分钟数处理，不使用手机当前的 `TimeZone.current`。

### 3.2 任务 Gateway

- 按可信 Cloud `site.gateways` 数组顺序生成候选清单，再以标准化 MAC 关联本地 GatewayModel 和 Mesh Node。
- 权限范围沿用现有 Site Review policy：Owner 使用全部可见 Gateway；Editor 只使用其可见 Space 绑定的 Gateway；Visitor 不进入本页面。
- 只有进入任务时本地/云端协调结果显示 `timezoneOffset != targetOffset` 的 Gateway 才成为目标。
- 已经与目标一致的 Gateway 不计入总数，也不展示在 Nearby 或 Other。
- 若本地 Gateway 仍为 cloud dirty，但其经有效 Time Status 确认的 offset 已等于目标，则不重复要求现场 BLE，同步任务只重试云上传。

### 3.3 设备与云端成功真值

- Device Synced：收到 typed Time Status，时间有效、返回 offset 与目标一致，并完成本地 Node 持久化。
- Cloud Synced：对应 Gateway payload/generation 已由 `.syncGateway` 成功提交。
- 顶部 updated、attention 和 Cell 状态只使用 Device Synced。
- 云端失败不得将已 Synced Cell 改回 Retry，也不显示本页 BLE 失败 Toast。

## 4. 架构

采用独立状态机与协调器方案，避免 ViewController 同时承担扫描、Mesh 事务、云同步和展示真值。

### 4.1 SyncGatewaysContext

进入页面时创建的不可变任务输入，包含：

- Site ID、Site display name 与权限范围。
- Target timezone、target offset minutes 与 `UTC±HH:mm` 展示值。
- 目标 Gateway 的远端顺序、远端身份信息、本地 GatewayModel/Node 关联结果。
- 页面 session 标识。

如果 target gateway 总数为 0，则不进入页面，并让 Site Review 状态按最新数据消失。

### 4.2 Gateway 页面状态

每个目标 Gateway 只维护一条状态记录：

- 稳定身份：Gateway ID、标准化 MAC、display name、远端顺序、GatewayModel、Node。
- Device sync：pending、syncing、failed、synced。
- Cloud sync：clean、pending、uploading、failed。
- Proximity：最新 RSSI、最新 Peripheral、累计有效未发现时长、No signal。
- Attempt：当前 attempt ID、Time Set 是否已发送、是否已终止。

Nearby、Other、进度、attention、按钮状态和 Cell 展示均由这些记录派生。数据库对象、BLE 回调与 ViewController 不单独维护 UI 真值。

### 4.3 SyncGatewaysScanSession

负责本页面拥有的 BLE RSSI 扫描生命周期：

- start、pause、resume、finish。
- 过滤非目标 Gateway，并将扫描结果映射到对应状态记录。
- 使用单调时钟累计“扫描实际运行期间”的未发现时长。
- 使用 session ID 丢弃旧扫描会话或页面退出后的回调。
- 在单 Gateway 同步事务期间暂停实际扫描并冻结计时；事务收敛后恢复。

### 4.4 GatewayTimeSyncCoordinator

串行执行单 Gateway 的现场同步：

- 校验页面、attempt、Peripheral 和当前互斥状态。
- 暂停扫描并连接目标 Gateway。
- 在发送前获取 App 当前 Date，结合 Context 的固定 target offset 构造完整 SIG Mesh Time Set。
- 等待并校验 typed Time Status。
- 处理成功、失败、超时、取消以及页面退出后的迟到结果。
- 在事务终态释放本次连接资源并按页面状态决定是否恢复扫描。

### 4.5 GatewayCloudSyncBridge

在 Device Synced 后负责本地 dirty 与云端收敛：

- 推进 GatewayModel 的客户端 dirty generation。
- 复用 `.syncGateway(gateway:node:)` 与 `/sitespace/sapce/gateway/regist`。
- 入队时捕获实际 payload/generation；成功只确认该 generation。
- 如果请求完成时存在更新 generation，继续入队，防止旧请求错误清除新 dirty。
- 本页面批次触发的云请求全部收敛后，最多静默刷新一次 `/sitespace/get/siteprops`。

### 4.6 SyncGatewaysViewController

只负责：

- UIKit 页面结构与状态渲染。
- 用户事件转发。
- `ToastStatusView` 展示。
- 导航返回、交互式返回和 Done 的页面 finish。

它不直接实现 Mesh Time Set、15 秒计时规则或云端 generation 判断。

## 5. 页面状态与排序

### 5.1 Nearby gateways

- 展示未 Synced 且当前有有效信号的 Gateway。
- 正在 Syncing 的 Gateway 在事务结束前固定保留在 Nearby，避免扫描暂停导致跨 Section 跳动。
- failed Gateway 有信号时展示 Retry。
- 按 Cloud `site.gateways` 原始顺序排列。
- 任一 Gateway 正在 Syncing 时，其他 Sync/Retry 按钮不可用。
- 无 Nearby 时显示：`No more gateways are currently nearby. Move closer and rescan.`

### 5.2 Other gateways

按以下分组顺序展示：

1. 未 Synced 且 No signal 的 Gateway。
2. 已 Synced 的 Gateway。

两个分组内部均保持 Cloud `site.gateways` 原始顺序。Synced Gateway 仍接收 RSSI 更新，但始终留在 Other。

Attention 使用尚未 Device Synced 的数量。数量为 0 时隐藏；Other 无 Cell 且 attention 也隐藏时，隐藏整个 Section。

### 5.3 顶部进度

- 总数：本次目标 Gateway 数量。
- 已更新数：`deviceSync == synced` 的数量。
- 示例：`1 of 4 updated`。
- 进度条与文字在本地 Device Synced 后立即更新。

## 6. BLE 扫描与 15 秒规则

- 页面出现并准备完成后启动唯一页面级扫描会话。
- 每次发现目标 Gateway 时更新 RSSI 与 Peripheral，并把该 Gateway 的有效未发现时长归零。
- 15 秒只累计扫描实际运行的时长；Bluetooth 不可用、页面扫描暂停或单 Gateway 同步期间不累计。
- 未 Synced Gateway 累计 15 秒未发现后转为 No signal，并从 Nearby 移到 Other。
- failed Gateway 转为 No signal 后保留 failed；再次发现时回到 Nearby 并显示 Retry。
- Synced Gateway 达到 15 秒后仍在 Other，仅把信号显示改为 No signal。
- Header 搜索图标在页面任务存续期间持续旋转，表达整体搜索任务；它不保证底层扫描在 Syncing 期间仍实际运行。

## 7. 单 Gateway 同步流程

1. 用户点击 Sync 或 Retry。
2. 校验页面 session 有效、当前无其他 Syncing、Gateway 仍有可用 Peripheral。
3. 创建新 attempt ID，将目标状态改为 syncing，禁用其他按钮。
4. 暂停实际 RSSI 扫描并冻结全部 Gateway 的失效计时。
5. 连接目标 Gateway。
6. 在即将发送时读取当前 Date，使用 Context 的 target offset 构造完整 Time Set；不单独发送 Time Zone Set。
7. 标记 Time Set 已发送，等待 typed Time Status。
8. 校验 Time Status 时间为有效非零值，且返回 timezone offset 等于 target offset。
9. 成功时使用响应值更新并持久化 Node 的 Mesh timestamp 与 timezone offset。
10. 将 Device sync 改为 synced，更新顶部进度，将 Cell 移到 Other，显示成功 Toast。
11. 推进 GatewayModel dirty generation 并异步 enqueue `.syncGateway`。扫描恢复不等待云响应。
12. 连接、发送、超时、无效时间或 offset 不匹配时，将 Device sync 改为 failed，并显示失败 Toast。
13. BLE attempt 收敛并释放本次连接资源后恢复扫描；页面已 finish 时不恢复。

同一时刻最多存在一个 BLE 同步 attempt；后台云请求不占用 Syncing 状态。

## 8. 页面退出与迟到响应

页面 finish 必须幂等：

- Done 和导航栏 Back 在关闭页面前 finish。
- 侧滑返回仅在交互式转场确认完成后 finish；手势取消时继续页面任务。
- 不以 `deinit` 或普通 `viewWillDisappear` 作为唯一清理边界。
- finish 停止扫描、RSSI 计时、尚未开始的步骤与所有 UI 回调。

进行中的 attempt 分两种情况：

- Time Set 尚未发送：取消连接/发送流程，不产生设备同步结果。
- Time Set 已发送：页面与 attempt 解绑，但底层 attempt 可在原定超时内收敛。
  - 收到有效匹配的 Time Status 时，仍持久化 Node、推进 GatewayModel dirty 并 enqueue `.syncGateway`。
  - 不更新已关闭页面，也不显示 Toast。
  - attempt 已超时或进入终态后的回调一律忽略，不能影响后续 Retry。

退出时不得恢复本页面扫描。只清理本页面主动拥有的扫描与连接状态，避免破坏其他页面的长期 Mesh 生命周期。

## 9. 云端回写与权威快照

### 9.1 本地 dirty

- Node 保存成功后，GatewayModel 的客户端 dirty generation 必须单调推进。
- 现有 `lastUpdate/lastUploadCloudTimestamp` 如果继续作为 generation marker，必须避免同一秒内无法区分更新；实现可采用单调递增策略。
- `gateway/regist` body 的 `updateTimestamp` 在服务器端没有业务作用，不用于服务器覆盖或冲突判断。

### 9.2 请求并发

- `.syncGateway` 请求必须捕获本次提交的 payload/generation。
- 成功只能将 `lastUploadCloudTimestamp` 推进到实际提交的 generation，不能读取完成时已经变化的 `gateway.lastUpdate` 并将其全部标记 clean。
- 同一 Gateway 的进行中请求可合并，但旧请求完成后发现更新 dirty 时必须再次 enqueue 最新 payload。
- 云失败保留 dirty，供网络恢复、再次进入 Site 或后续相关操作重试。

### 9.3 Site 快照

- 本页面批次发起的 Gateway 云请求全部进入成功或失败终态后，最多静默调用一次 `/sitespace/get/siteprops`。
- 已 clean Gateway 接受服务器权威 snapshot。
- 仍 dirty Gateway 保留本地有效 Time Status 已确认的 timestamp/timezoneOffset，不能由旧 cloud snapshot 覆盖并再次要求用户现场同步。
- 不直接修改 `SiteData.lastUpdate`；服务器 Site timestamp 只通过权威 Site snapshot 合并。
- 页面已退出时，云同步与快照收敛仍可静默完成，但不得产生页面 UI 或 Toast。

## 10. UI 与国际化

### 10.1 入口

- `Sync status` 弹窗的 `REVIEW SYNC`：先关闭弹窗，再从当前 Site 页面 push。
- Site 页 `Review sync` 组件的 `Review sync`：直接 push。
- 两个入口调用同一 Context builder 和 router。

### 10.2 页面结构

从上到下：

1. Site time-zone card。
2. 固定 On-site sync Alert。
3. Nearby gateways Section。
4. Other gateways Section 与动态 attention。
5. 固定于安全区底部的 Bottom action bar；中间内容独立滚动。

Done 始终可点击。点击后 finish 并关闭页面，不要求所有 Gateway 已完成。

### 10.3 动态内容

- Time-zone card 标题由 Site display name 与本地化 time-zone 格式组成，不固定为 `Hospital time zone`。
- Offset 格式为 `UTC±HH:mm`。
- On-site sync 内容按 Figma 固定展示。
- Other attention 使用剩余未完成数量插值；完成后隐藏。

### 10.4 Toast

只复用现有 `ToastStatusView` 样式、位置和动画，不复用旧提示语 Key：

- English failure：`%@ sync failed. Try again.`
- English success：`%@ time zone updated.`
- 简体中文 failure：`%@ 同步失败，请重试。`
- 简体中文 success：`%@ 时区已更新。`

`%@` 使用 Gateway display name。文案使用完整参数化国际化 Key，不拼接多个翻译片段。云上传失败不显示上述 Toast。

新增或修改的共享 UI、资源、本地化和工程文件引用需同步检查 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 四个 target。

## 11. 异常处理

- Bluetooth 未授权、关闭或扫描无法启动：复用项目现有 BLE 提示机制；扫描未运行时不累计 15 秒。
- Cloud Gateway 无法映射到本地 GatewayModel/Node：按 Cloud 顺序保留在 Other，展示 No signal，计入 attention，但不提供 Sync。
- Site timezone 在页面打开后发生变化：Context 不动态切换；下一次 Sync/Retry 前检测到不一致时 finish 当前任务并返回 Site，由最新数据重新计算 Review sync。
- 每次 Sync/Retry 前重新校验当前本地 Site 可见范围。若 Gateway 已被移出或用户权限已失效，则不发起连接，结束页面任务并重新获取 Site 权威数据。服务器在页面快照之后发生但 App 尚未获知的权限变化，由服务器与下一次权威刷新收敛。
- App 进入后台：暂停实际扫描与有效时间累计；尚未发送 Time Set 的 attempt 取消并进入 failed，前台恢复且页面 session 仍有效时恢复扫描并允许 Retry；已发送 attempt 按原定超时规则收敛，UI 仍受 session/attempt 校验保护。
- Time Status 缺失、时间无效、offset 不匹配或 Gateway 不支持所需模型：本次 Device sync 失败，进入 Retry。

## 12. 验证方案

### 12.1 自动化测试

- Context/Parser：权限范围、MAC 标准化和去重、远端顺序、本地关联缺失、Site timezone 一致性、dirty local override。
- 状态模型：Nearby/Other 投影、两级排序、进度、attention、按钮互斥、pending/syncing/failed/synced 转换。
- 扫描会话：发现重置、15 秒有效时间、暂停不计时、恢复续算、后台暂停、旧 session 回调隔离。
- Time Set：显式 Date、固定 target offset、完整时间参数、typed Time Status 成功条件。
- 生命周期：Done、Back、完成/取消侧滑、发送前退出、发送后迟到成功、超时后迟到结果。
- 云同步：generation snapshot、旧请求不能清理新 dirty、失败保留、重新 enqueue、批次最多一次 Site refresh。
- UI/Source contract：两个入口、Figma 关键状态、动态 Toast、国际化 Key、四 target 文件归属与退出清理接线。

### 12.2 静态与构建验证

- `git diff --check`。
- `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 四个 scheme 的 generic iPhoneOS Debug 无签名构建。
- 构建成功只证明静态集成，不代表 BLE、Gateway 或服务器端到端验收通过。

### 12.3 真机与服务器验收

- 持续 BLE 广播与目标 Gateway 发现。
- RSSI 15 秒 No signal、同步暂停期间不计时以及恢复后的续算。
- 单 Gateway 连接互斥、完整 Time Set、真实 Time Status 与日期时间/offset 回读。
- Done、Back、侧滑、后台/前台和迟到响应。
- `gateway/regist` 持久化、失败重试、generation 竞态与 Site snapshot 回读。
- 四品牌 target 的页面、资源和国际化展示。

## 13. 本期不包含

- 自动批量同步多台 Gateway。
- 云上传进度、Cloud failed Cell 状态或手动云重试按钮。
- Gateway OTA 流程重构。
- 全局 BLE/Proxy 架构重构。
- 新增 Auth 信息或记录敏感 Node export。
- 与 Sync gateways 无关的 Site、Space 或 Gateway 模块重构。

## 14. 实施约束

- 在现有 Site timezone、Review sync 和空 `SyncGatewaysViewController` 改动基础上增量实现，不覆盖或重做无关功能。
- 优先复用现有 UIKit 组件、主题、颜色、字体、尺寸、图标和 `ToastStatusView`。
- 状态机、扫描会话、时间同步协调器和云同步桥接层保持单一职责，并通过可替换依赖支持测试。
- 所有异步副作用必须同时受 page session 和 gateway attempt 所有权保护。
- 静态/构建结果与真机/服务器验收结论必须分开报告。
