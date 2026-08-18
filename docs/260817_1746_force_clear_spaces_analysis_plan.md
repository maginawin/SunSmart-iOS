# 网关 Force Clear Spaces 需求分析与开发计划

## 结论

需求目标合理：当网关蓝牙链路已明确处于 Offline 且仍有关联空间时，允许只清理服务器与 App 本地的关联关系，不依赖离线网关响应；同时在网关蓝牙删除失败后的强制删除路径中，避免遗留服务器关联空间。

但当前需求尚不能直接按“失败时不更新任何东西”完整落地，开发前需要确认服务器接口的原子性与删除顺序。当前 App 只有单个 Space 解绑接口，没有原子地把一个网关的整份 `Associated Spaces` 列表置空的接口。逐条解绑时若中途失败，App 可以不修改本地数据，但服务器可能已经部分解绑。

本阶段只分析和规划，不修改业务代码。

## 当前源码事实

### 网关页面与菜单

- `GatewayViewController` 是 4G Gateway 与 WiFi Gateway 的共享页面；`WiFiGatewayViewController` 只覆盖 WiFi 特有行为。因此新菜单和清理流程应在共享层实现，自动覆盖两个页面。
- 当前菜单由 `GatewayMenuPolicy` 统一生成，顺序为 DFU、Delete（有权限时）、Information、Identify。
- Figma 要求的新选项位于 Identify 下方，因此应作为最后一项追加，不改变既有菜单顺序。
- 当前菜单宽度为 120pt，无法稳定容纳英文 `Force clear spaces`。显示该项时需要把菜单宽度扩大到约 164pt，并做四个品牌的英文/中文视觉检查。
- 页面显示的蓝牙 Online/Offline 状态来自目标网关的 Mesh Proxy Ready 状态，不是 `GatewayModel.connectStatus` 或 MQTT/Internet 状态。菜单条件应使用连接状态机的明确 `.disconnected`，不能简单使用 `!isGatewayProxyReady`，否则 Connecting 期间也会错误显示。
- 页面中的关联空间展示使用编辑副本 `setGatewayModel.associatedSpaces`；服务器加载成功后，代码同时刷新持久模型与编辑副本。

### 当前服务器接口

当前网关关联关系使用以下接口：

- 查询关联空间：`POST /sitespace/sapce/gateway/reference`
  - 参数：`siteId`、`gatewayId`
- 解绑单个空间：`POST /sitespace/sapce/gateway/unbind`
  - 参数：`spaceId`、`gatewayId`、`userId`

路径中的 `sapce` 是服务器现有拼写，客户端必须保持一致。

当前没有“传入 gatewayId 和空列表，一次性覆盖 Associated Spaces”的专用接口。`gatewayRegister` 会提交完整 Node 与 `gatewayPreconfigured`，同时涉及授权、MQTT、APN 等数据，不适合作为单纯清空关联空间的替代接口。

### 当前 Delete / Force Delete 状态链

已注册网关的现有流程是：

1. 用户确认 Delete。
2. 非 Owner 先从服务器读取关联空间，并检查是否存在无权限空间。
3. 调用 `gatewayDelete` 删除服务器网关。
4. 服务器删除成功后，立即清空本地 MQTT、Associated Spaces 和上传时间戳并保存。
5. 通过蓝牙执行 Node Reset。
6. 蓝牙 Reset 失败时，通用 `DeviceProtocol.deleteNodes` 展示 FORCE DELETE。
7. FORCE DELETE 当前会直接提交本地永久删除并从 Mesh Network 移除 Node，没有任何异步前置检查。

因此进入 FORCE DELETE 弹窗时，当前模型中的 Associated Spaces 已经为空，不能再据此判断删除前是否有关联空间。实现时必须在步骤 3 前保存不可变的关联空间快照，并给通用强制删除流程增加一个仅 Gateway 使用的异步前置钩子。

还需要服务器确认：`gatewayDelete` 成功后，`gatewayUnbindSpace` 是否仍允许按原 gatewayId 解绑。如果不允许，需求指定的“点击 FORCE DELETE 后再清理”与当前服务器优先删除顺序不兼容。

## Figma UI 结论

Figma 节点 `494:13837` 的弹窗规格如下：

- 全屏遮罩，中间 302pt 宽卡片，20pt 圆角。
- 标题：`Force clear associated spaces?`，15pt Regular，颜色 `#404F66`。
- 正文：`This will remove all associated spaces from the server. Spaces will be immediately available to bind to another gateway. If this gateway comes back online, it will detect no associations and prompt for reconfiguration.`，15pt Light，22pt 行高，居中，颜色 `#404F66`。
- 操作区高 60pt，左侧 `CANCEL`，右侧 `FORCE CLEAR`。
- `FORCE CLEAR` 使用提示色 `#FF4831`；项目通用 `Red_Color` 并非该颜色，应显式复用 `Error_Red_Color`。

现有 `SRAlertView` 的宽度、圆角、排版、分割线和双按钮结构与设计基本一致，建议复用并做少量参数覆盖，不新增一套弹窗组件。Loading 使用现有阻塞式全 Window HUD，开始请求后禁止重复触发，所有结束路径只关闭一次。

## 需求缺口与建议决策

### 1. 服务器清空操作的原子性

严格满足“失败时服务器和本地都不更新”需要服务器提供原子接口，例如一次请求按 gatewayId 清空全部 Associated Spaces。推荐由服务器提供或确认已有此类接口。

如果只能复用现有单 Space 解绑接口，则客户端只能保证：

- 所有解绑都成功后才清空本地。
- 任一失败或总时长超过 30 秒时，本地保持不变并提示失败。
- 已成功的服务器解绑无法可靠回滚，服务器可能处于部分清理状态；下次进入页面需要从服务器重新拉取并校正本地。

不建议用“失败后逐条重新绑定”模拟事务，因为补偿请求也可能失败，并可能覆盖并发修改。

### 2. 30 秒语义

建议定义为整个清理事务的最大等待时间：明确的网络错误或服务器失败可立即结束；一直无最终结果时在 30 秒截止并失败。超时后必须忽略迟到回调，不能再写本地或继续 Force Delete。

当前通用网络请求的单请求超时是 10 秒。若产品要求“无响应必须等待满 30 秒”，应为清理接口增加作用域内的 30 秒请求配置，不能修改所有接口的全局超时。若 30 秒仅是上限，则保留更早的明确网络失败即可。

### 3. 权限

需求只定义了 Offline 与列表非空，没有定义谁能清空全部空间。当前页面允许 Owner，或至少能编辑一个关联空间的 Editor 进入；后者不等于有权清理全部空间。

建议沿用现有 Delete 的安全边界：Owner 可执行；非 Owner 必须对服务器返回的每一个关联空间都拥有 Editor 编辑权限，否则中止并提示无权限。菜单可按需求条件展示，但点击后必须重新读取服务器列表并校验权限，避免缓存过期。

### 4. 数据源与并发

- 菜单显示使用当前页面已加载的列表，操作执行前重新读取服务器关联列表作为权威快照。
- 弹窗显示后如果网关重新 Online，建议仍允许完成已确认的服务器清理；操作本身只修改服务器与本地，不向网关发送命令。若产品希望状态变化后自动取消，需要另行明确。
- 请求期间锁定重复操作；页面退出、Task 取消或 30 秒超时后，迟到结果不得更新 UI 和本地数据库。

### 5. 文案拼写

需求中的成功 Toast `All assocaited spaces cleared from server` 存在拼写错误。建议改为 `All associated spaces cleared from server`。失败文案 `Failed to clear all associated spaces` 可直接使用。

## 推荐开发方案

### A. 共享菜单策略

扩展 `GatewayMenuAction` 和 `GatewayMenuPolicy`，增加 Force Clear Spaces 动作，并把是否显示的条件显式建模：

- 网关页面连接状态机为 `.disconnected`，即 UI 真正显示 Offline。
- 当前 Associated Spaces 非空。
- 页面具备基本配置权限；最终权限仍在服务器预检后校验。

满足条件时在 Identify 后追加动作，图标使用当前 worktree 已新增的 `menu_clear_spaces`。该资源位于共享 Asset Catalog，会供 SunSmart、Archipelago、SLG Sync Plus、SylSmart 使用。

### B. 确认弹窗与本地化

复用 `SRAlertView` 实现 Figma 弹窗，按钮点击行为如下：

- CANCEL：只关闭弹窗。
- FORCE CLEAR：弹窗完全关闭后启动清理事务，显示全 Window Loading。

所有新文案添加英文和简体中文本地化，建议中文为：

- `Force clear spaces`：`强制清除空间`
- `Force clear associated spaces?`：`强制清除关联空间？`
- 正文：`这将从服务器移除所有关联空间。空间将立即可绑定到其他网关。如果此网关重新上线，它将检测到没有关联空间并提示重新配置。`
- `FORCE CLEAR`：`强制清除`
- `All associated spaces cleared from server`：`已从服务器清除所有关联空间`
- `Failed to clear all associated spaces`：`清除所有关联空间失败`

### C. 共享服务器清理协调器

新增一个不直接修改 UI 或本地模型的 Gateway Associated Spaces 清理协调器，供独立菜单和 Force Delete 共用：

1. 读取服务器当前关联列表，并严格解析所有 spaceId；响应结构异常视为失败，不能把解析失败误判为空列表。
2. 执行权限校验。
3. 优先调用服务器原子清空接口；若确认只能使用现有接口，则对权威列表执行逐条解绑，并明确接受非原子风险。
4. 用单调时钟控制整个事务最多 30 秒。
5. 返回 `success`、`failure` 或 `timeout`；协调器本身不改 `GatewayModel`。
6. 取消或超时后忽略迟到响应。

若新增 Swift 文件，需要加入四个 App target 的 Sources，不能只加入 SunSmart。

### D. 独立 Force Clear 成功/失败落地

服务器清理全部成功后，在主线程一次性提交本地变更：

- 清空 `gatewayModel.associatedSpaces`。
- 清空 `setGatewayModel.associatedSpaces`，避免编辑副本把旧值再次保存回来。
- 保存 `GatewayModel` 数据库记录。
- 刷新 Associated Spaces section、Header 设备数、Save 状态与菜单条件。
- 发送关联拓扑变化通知，让 Site 页重新计算 Gateway 过滤、Space 关联和页面数据；避免走会再次完整注册 Gateway 的普通配置同步路径。
- 使用 `ToastStatusView` 的 `.siteUpdate` 成功样式显示 `All associated spaces cleared from server`。

任一失败或超时：关闭 Loading，不修改两个模型、不保存数据库、不发送拓扑通知，使用 `.siteUpdate` 失败样式显示 `Failed to clear all associated spaces`。

### E. Force Delete 前置清理

保持普通设备 Delete 行为不变，仅为 `DeviceProtocol.deleteNodes` 增加可选的异步 Force Delete 前置钩子：

- 默认没有钩子，其他设备继续直接强制删除。
- Gateway 在开始服务器删除前保存原 Associated Spaces 快照，并把共享清理协调器作为前置钩子传入。
- 蓝牙 Reset 失败并点击 FORCE DELETE 后：
  - 快照为空：立即继续原强制删除提交。
  - 快照非空：显示 Loading，先清理服务器关联空间。
  - 清理成功：继续现有永久删除、Mesh Node 移除和页面关闭流程。
  - 清理失败或超时：不执行永久删除，不从 Mesh Network 移除 Node，显示失败 Toast。
- 使用一次性 completion / operation token，确保成功、失败、超时、页面退出和迟到回调只能完成一次。

该方案避免复制整个通用蓝牙删除实现，也不会改变 Light、Other、Fire Alarm 等其他设备的 Force Delete。

## 测试与验证计划

### 自动化

- 扩展 `GatewayMenuPolicyTests`：覆盖 4G/WiFi、Online/Connecting/Offline、空/非空列表、权限和 Identify 后的顺序。
- 增加清理协调器测试：服务器列表为空、全部成功、单项失败、部分成功后失败、响应结构异常、30 秒超时、迟到回调、重复 completion。
- 增加 Force Delete 前置钩子测试：无空间直接继续；有空间成功后继续；失败/超时不提交删除；其他设备默认路径不受影响。
- 更新 Gateway 菜单静态契约，检查 `menu_clear_spaces`、英文/中文本地化 Key、四 target Sources membership。
- 运行 `git diff --check`。

### 构建

按项目规则串行运行四个 unsigned generic iPhoneOS Debug 构建，不使用 Simulator、不使用 shell 包装或日志重定向：

- SunSmart
- Archipelago
- SLG Sync Plus
- SylSmart

### 手工/联调验收

- Online、Connecting、Offline 三种蓝牙状态与空/非空关联列表的菜单可见性。
- 4G 与 WiFi Gateway 菜单顺序、宽度、图标和四品牌视觉。
- Figma 弹窗文案、尺寸、按钮颜色、CANCEL 行为。
- 服务器成功、明确失败、无网络、30 秒超时、部分解绑失败、迟到响应。
- 成功后 Gateway 页面、Site Gateway 筛选、Space 关联状态和重进页面的一致性。
- Delete 的蓝牙成功、蓝牙失败后取消、无关联空间 Force Delete、有空间清理成功、清理失败/超时。

自动化和 unsigned 构建只能证明静态逻辑与编译通过，不能替代真实服务器事务、BLE/Mesh Reset、网关重新上线后的行为和最终视觉验收。

## 开发前需要确认

1. 服务器是否能提供或已有“按 gatewayId 原子清空全部 Associated Spaces”的接口？若没有，是否接受逐条调用 `/sitespace/sapce/gateway/unbind` 可能造成服务器部分成功的风险？
2. 当前 `gatewayDelete` 成功后，解绑接口是否仍接受该 gatewayId？若不接受，需要服务器删除接口原子清理关联，或允许把关联清理提前到服务器删除之前。
3. 是否确认权限规则采用“Owner，或对全部关联空间均有 Editor 权限”？
4. 是否确认修正成功 Toast 的拼写为 `All associated spaces cleared from server`？
5. 30 秒是否为最大等待上限，明确网络/API 失败可提前结束？
