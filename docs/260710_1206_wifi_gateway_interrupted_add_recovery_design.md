# WiFi Gateway 添加中断后的权限与强制恢复设计

## 1. 文档状态

- 日期：2026-07-10
- 状态：设计已确认，等待实施计划
- 设备范围：CID `0x0A78`、PID `0x2721` 的 WiFi Gateway
- 关联分析：`docs/260710_1059_wifi_gateway_power_cut_sync_failure_analysis.md`

## 2. 背景

WiFi Gateway 在 Adding 期间断电后，App 可能已经保存 Node 和 `GatewayModel`，但设备侧尚未可靠完成 AppKey、Model Bind 或 Gateway Vendor 配置。设备重新上电后仍可通过 BLE Proxy 显示 Online，但本地缓存与设备真实配置可能不一致，导致 `Devices not synced` 以及多个 Gateway 同步任务失败。

当前还存在两个独立的 App 侧问题：

1. 未关联 Space 时，`Devices not synced` 的点击权限判断会错误拒绝具备配置权限的用户。
2. WiFi 信息自动读取与 Gateway 同步可能同时向同一节点发送 acknowledged Vendor 消息，造成回调覆盖、任务错误归因和 continuation misuse。

## 3. 目标

本次修复需要达到以下目标：

1. 统一 WiFi Gateway 的展示、进入和配置权限。
2. 用户手动点击 `Devices not synced` 时，不依赖可能失真的本地 Key Bind 缓存，执行一次 Gateway 范围内的强制完整配置。
3. 保证同一 Gateway 的 WiFi 自动读取、用户网络操作和同步任务不会并发发送 acknowledged Mesh 消息。
4. 让加载框、任务状态和结果提示具有唯一、可预测的生命周期。
5. 在 Adding 中断电的场景下，Gateway 重新在线后可通过一次完整同步恢复。

## 4. 非目标

本次不包含以下改动：

- 不调整 Fast Add 的整体成功判定、回滚或删除策略。
- 不对所有设备类型启用强制初始化，只处理指定 WiFi Gateway 的手动恢复同步。
- 不在恢复流程中读取设备真实 Key/Bind 状态后再做差异修复。
- 不重新下发或保存 WiFi SSID、Password 等网络凭据。
- 不新增 Auth 信息。
- 不改变普通 Save 的差异同步策略。
- 不顺带重构通用 Sync 页面或 Mesh 消息框架。

## 5. 已确认的产品规则

### 5.1 权限规则

- Site Owner 可以查看、进入和配置 WiFi Gateway。
- 非 Owner 用户只有拥有有效 Editor Space 权限时，才可能查看、进入和配置 WiFi Gateway。
- 对已有 Associated Spaces 的 Gateway，用户必须至少能有效编辑其中一个关联 Space。
- 对尚未关联 Space 的 Gateway，用户只要能有效编辑 Site 下至少一个 Space，即可进入并完成关联及配置。
- 仅有 Visitor 权限的用户不能看到入口，也不能进入 Gateway 页面。
- Editor 权限被系统限制或禁用时，按无有效 Editor 权限处理。

### 5.2 手动恢复规则

- 从 `Devices not synced` 进入时，始终执行一次 Gateway 范围的强制完整配置。
- 强制恢复不先读取设备当前配置，也不依据本地 `isKeybindComplete`、AppKey 或 Model Bind 缓存跳过关键消息。
- 普通 Save 仍使用现有差异同步。

### 5.3 并发交互规则

- 后台自动读取 WiFi 信息或 RSSI 时点击 `Devices not synced`：等待当前请求结束后自动继续同步。
- 用户主动执行 `Connect`、`Disconnect` 或 `Refresh` 时点击 `Devices not synced`：阻止进入同步，要求当前操作结束后再次点击。
- 不取消已经发送的 acknowledged 消息。

## 6. 权限设计

### 6.1 单一权限真值

建立一个聚焦于 Gateway 的权限判断入口，并在以下位置复用：

- Site 页面 Gateway 列表过滤与卡片状态；
- Gateway 页面导航入口；
- Gateway 详情页所有可变更操作；
- `Devices not synced` 点击入口；
- Associated Spaces 编辑；
- 深链或异常导航情况下的防御性校验。

权限判断使用“有效编辑能力”，不能只比较 Space 的角色枚举值。这样可以同时考虑 Editor 权限被禁用等运行时限制。

### 6.2 权限矩阵

| 用户状态 | 未关联 Space 的 Gateway | 已关联且至少一个 Space 可编辑 | 仅关联不可编辑 Space |
| --- | --- | --- | --- |
| Site Owner | 可查看、进入、配置 | 可查看、进入、配置 | 可查看、进入、配置 |
| 有效 Editor | 可查看、进入、配置 | 可查看、进入、配置 | 不展示、不可进入 |
| Visitor | 不展示、不可进入 | 不展示、不可进入 | 不展示、不可进入 |
| 被禁用的 Editor | 不展示、不可进入 | 不展示、不可进入 | 不展示、不可进入 |

页面隐藏不能替代操作校验。即使通过异常路径进入详情页，配置操作也必须再次检查相同权限真值。

## 7. 组件边界

### 7.1 Gateway 权限策略

职责：根据 Site、Gateway Associated Spaces 和当前用户的有效 Space 能力，返回是否允许查看和配置。

依赖：现有 Site/Space 权限模型，不自行推导新的角色体系。

不负责：UI 展示、弹窗和导航。

### 7.2 Gateway 强制恢复计划构建器

职责：为手动 `Devices not synced` 生成固定、串行、可重复执行的恢复任务，不读取本地完成标记来裁剪关键配置。

依赖：当前 Mesh Network 中的主网络 Key、关联 Space Key、Gateway 支持 Models、GatewayModel 中的项目、Space 和服务器信息。

不负责：WiFi SSID/Password、普通差异同步、页面提示。

实现优先放在 App 现有 Node/Sync 扩展层，复用 SDK 已公开的配置消息类型，避免为了单一 Gateway 恢复扩大 SDK 改动；只有公开能力不足时才最小化修改本地 `NordicSigMeshSDK`。

### 7.3 WiFi Gateway 同步前置协调器

职责：在打开 Sync 页面前判断当前 WiFi 请求类型，并决定立即继续、等待自动请求或阻止用户主动操作。

依赖：WiFi Gateway 页面已有网络操作状态、Timer、request ID 和 Gateway 在线状态。

不负责：执行具体同步任务。

### 7.4 Sync 执行器

职责：按依赖顺序逐条发送 Mesh 消息、等待业务 Status、维护任务状态并生成一次最终结果。

依赖：现有 Sync 页面和 Mesh 消息执行能力。

不负责：权限计算和 WiFi 页面自动读取。

## 8. 强制恢复数据流

用户点击 `Devices not synced` 后按以下顺序处理：

1. 使用统一权限策略进行防御性校验。
2. 检查 Gateway 是否在线以及 Proxy 是否可用。
3. 调用 WiFi Gateway 同步前置协调器：
   - 空闲时立即继续；
   - 自动读取中进入等待；
   - 用户主动网络操作中阻止进入。
4. 构建强制恢复任务，不能复用会根据缓存裁剪任务的普通 `getSyncData(.all)` 结果。
5. 打开 Sync 页面，固定包含 `Device Initialization` 以及所有适用的 Gateway 配置任务。
6. 串行执行每个任务及其内部消息。
7. 所有必要任务成功后，重新计算 Gateway 同步差异并清除 `Devices not synced`。
8. 任一必要任务失败或被跳过时，保留 `Devices not synced`。

## 9. 强制恢复任务

### 9.1 Task 1：Device Initialization

无条件生成 Gateway 恢复所需的配置消息：

- 下发当前/主网络所需 NetKey 与 AppKey；
- 对 WiFi Gateway 所需 Models 重新执行对应 AppKey Bind；
- 不因为本地 Node 已记录 Key 或 Model Bind 而省略；
- 每条消息必须收到对应 Config Status 才能成功。

该任务是所有 Gateway Vendor 配置的关键前置条件。失败后不再发送后续任务。

### 9.2 Task 2：Associated Spaces

对当前 Gateway 的全部 Associated Spaces 强制执行：

- 对应 NetKey/AppKey 下发；
- Gateway 所需子网 Models 的 AppKey Bind；
- Gateway 激活时所需的既有 Space 关联 Vendor 配置。

任务必须基于 GatewayModel 的完整目标列表，而不是只处理本地缓存认为缺少的 Space。

该任务失败时保留失败状态，但仍允许执行不依赖关联 Space Key 的 Gateway 任务，以尽可能恢复其他配置。

### 9.3 Task 3：Association Project

强制下发当前 Gateway 所属 Site/Project 信息，不以 `gatewayInfo.projectId` 的本地缓存比较结果作为跳过条件。

### 9.4 Task 4：Sync Spaces

根据 Gateway 当前激活状态和完整 Associated Spaces 目标重新生成 AppKey index 列表并下发，不以 `gatewayInfo.subnetAppkeyIndexs` 作为跳过条件。

### 9.5 Task 5：Server Information

GatewayModel 存在有效服务器配置时强制下发 MQTT/Server Information。没有可用服务器配置时不构造虚假数据，也不覆盖设备内容。

### 9.6 明确排除的配置

恢复流程不读取、不保存、不重新下发 WiFi SSID 或 Password。App 当前不具备可用于强制覆盖设备网络凭据的可靠真值。

## 10. 消息串行与成功语义

- 同一 Gateway 同一时间只允许一个 acknowledged Mesh 请求。
- 一个任务内部的下一条消息必须等待上一条得到业务 Status、失败或超时后才能开始。
- 分段 Lower Transport ACK 只证明传输层收包完整，不能作为 Vendor 业务配置成功。
- Config 消息必须收到对应 Config Status；Gateway Vendor 消息必须收到对应 Vendor Status。
- timeout、cancelled、设备断开、失败 Status 或只有 Transport ACK 都视为业务失败。
- 每次同步使用独立操作标识；过期回调不能更新新任务、弹窗或导航。

## 11. WiFi 请求协调与页面反馈

### 11.1 空闲状态

没有 WiFi 请求时，点击 `Devices not synced` 立即进入 Sync 页面。

### 11.2 后台自动读取中

后台自动读取包括进入页面后的 WiFi 信息加载和 RSSI 读取：

1. 停止安排新的 RSSI Timer 请求。
2. 记录一次 pending sync，重复点击不重复排队。
3. 在当前页面显示 `Preparing device sync…`。
4. 不取消已经发出的 acknowledged 请求。
5. 屏蔽该自动请求原本的成功或失败弹窗。
6. 请求成功、失败或超时后关闭加载框。
7. Gateway 仍在线时继续进入强制恢复；已离线时不进入，并只提示一次离线。

等待期间的自动读取失败不能直接阻止同步，因为强制恢复可能修复当前 Vendor 通信通路。

### 11.3 用户主动网络操作中

当 `Connect`、`Disconnect` 或 `Refresh` 正在执行时：

- 不建立 pending sync；
- 不自动跳转；
- 展示 `Please wait for the current operation to finish.`；
- 当前网络操作沿用自身成功或失败反馈；
- 操作结束后由用户再次点击 `Devices not synced`。

### 11.4 生命周期清理

页面退出、Gateway 切换或对象释放时清理：

- pending sync 标记；
- 自动读取和 RSSI Timer；
- 页面级加载框；
- 仅属于旧操作的延迟弹窗与导航动作。

加载框绑定当前页面，不使用全局 Window HUD，避免影响其他页面。

## 12. 任务依赖与错误处理

执行顺序固定为：

1. `Device Initialization`
2. `Associated Spaces`
3. `Association Project`
4. `Sync Spaces`
5. `Server Information`

错误规则：

- `Device Initialization` 失败：停止流程，后续任务标记为 `Skipped`。
- `Associated Spaces` 失败：记录失败，继续执行其余独立 Gateway 任务。
- `Association Project`、`Sync Spaces` 或 `Server Information` 失败：记录失败并继续后续独立任务。
- Gateway 中途离线：终止当前消息链，未开始任务标记为 `Skipped`。
- `Skipped` 是终态但不是成功，不能清除 `Devices not synced`。
- 任务行展示详细状态，流程结束后最多展示一次汇总提示，不逐条堆叠成功/失败弹窗。

## 13. 本地状态更新

- 强制恢复通过独立模式生成消息，不通过清空、伪造或提前修改 Node 缓存来触发普通同步。
- 每个 Config 或 Gateway 配置只在收到明确成功 Status 后更新对应本地状态。
- 部分任务成功时可以保留其已确认状态，但 Gateway 总体仍保持未同步。
- 全部必要任务成功后重新计算差异；只有差异为空时才移除 `Devices not synced`。
- 失败、超时和被跳过的任务不能写入成功状态。

## 14. 用户可见文案与国际化

优先复用现有本地化 Key；确需新增时同步 English 和简体中文：

| English UI copy | 简体中文含义 |
| --- | --- |
| `Preparing device sync…` | 正在准备设备同步… |
| `Please wait for the current operation to finish.` | 请等待当前操作完成。 |
| `Skipped` | 已跳过 |

其他权限、离线和同步结果提示优先复用现有文案，禁止硬编码。

## 15. 验收与测试设计

### 15.1 权限测试

- Owner + 无 Associated Spaces：可看到 Gateway、可进入、可同步。
- 有效 Editor + 无 Associated Spaces：可看到 Gateway、可进入、可同步。
- 有效 Editor + 至少一个可编辑的 Associated Space：可进入、可同步。
- Editor 只有无关 Space 的编辑权：已关联 Gateway 不展示且不可进入。
- Visitor：Gateway 不展示且不可进入。
- Editor 权限被禁用：按 Visitor 处理。
- 异常导航进入时，详情页所有配置入口仍被统一权限策略拦截。

### 15.2 强制恢复计划测试

- 本地 `isKeybindComplete` 为 true 时仍包含 `Device Initialization`。
- 本地已经记录主 AppKey 和 Vendor Model Bind 时仍生成强制 Key/Bind 消息。
- Associated Spaces 使用完整目标集合，不因本地缓存存在而跳过。
- Project、Space index 列表和 Server Information 不因 `gatewayInfo` 看似一致而跳过。
- 恢复计划不包含 WiFi SSID/Password 写入。
- 普通 Save 仍使用差异同步，不进入强制模式。

### 15.3 并发协调测试

- 自动 WiFi 读取中点击同步：只排队一次，停止新轮询，屏蔽中间弹窗，完成后进入 Sync。
- 自动读取失败但 Gateway 在线：仍进入 Sync。
- 等待期间 Gateway 离线：关闭加载框，不进入 Sync，只提示一次离线。
- `Connect`、`Disconnect` 或 `Refresh` 中点击同步：不排队、不导航，只提示等待。
- 页面退出后旧请求完成：不弹窗、不跳转、不修改新页面状态。
- 连续点击 `Devices not synced`：只能产生一个恢复会话。

### 15.4 任务状态测试

- 初始化失败：后续任务不发送并显示 `Skipped`。
- Associated Spaces 失败：独立 Gateway 任务继续执行，最终总体失败。
- Vendor 消息只有 Transport ACK、没有 Vendor Status：任务超时失败，不更新缓存。
- Gateway 中途断开：当前任务失败，后续任务跳过。
- 所有任务成功：重新计算差异为空，`Devices not synced` 消失。

### 15.5 端到端验收

1. 添加 CID `0x0A78`、PID `0x2721` 的 WiFi Gateway。
2. Adding 数秒后断电，使 Gateway 保留为半完成状态。
3. 重新上电并等待 BLE Proxy Online。
4. Owner 或符合规则的有效 Editor 进入 Gateway 页面。
5. 点击 `Devices not synced`，确认不再错误提示 `No permission!`。
6. 完成一次强制恢复，确认五项任务均成功且 `Devices not synced` 消失。
7. 确认 Gateway 原有 WiFi 网络连接未被恢复流程覆盖。
8. 使用 Visitor 和不具有关联 Space 编辑权的用户确认无法进入。

### 15.6 构建验证

修改完成后使用直接的 iPhoneOS `xcodebuild` 验证主工程。由于 Gateway 代码和本地化可能属于共享 target，需要先核对 target membership，并验证所有实际受影响的品牌 target；不使用 Simulator，不使用 shell 包装或日志重定向。

若最终必须修改本地 `NordicSigMeshSDK`，需要同时验证 SDK 自身可用构建入口，以及所有引用该 SDK 且受改动影响的 App target。

## 16. 完成标准

满足以下全部条件才视为修复完成：

- 权限矩阵在 Site 与 Gateway 页面保持一致。
- 手动恢复不依赖本地 Key Bind 完成标记，并执行已定义的完整任务序列。
- WiFi 自动读取和 Sync 不再并发发送 acknowledged 请求。
- 用户主动网络操作不会被同步自动打断或排队。
- 失败和跳过状态不会清除 `Devices not synced`。
- Adding 中断电的实机场景可通过一次恢复同步成功修复。
- 不覆盖 WiFi 凭据，不改变普通 Save 与其他设备同步行为。
- English 与简体中文文案完整，所有受影响 target 构建通过。
