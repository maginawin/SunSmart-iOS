# Gateway Force Clear Spaces 与 Delete 最终开发计划

## 1. 计划目标

本计划覆盖两个相互关联的网关维护流程：

1. 网关蓝牙状态为 Offline 且存在 Associated Spaces 时，提供独立的 `Force clear spaces` 操作，原子清空服务器与本地的关联列表。
2. 优化 Gateway Delete，固定采用“服务器删除成功后，才尝试蓝牙 Reset”的顺序，并避免服务器已删除的网关被 App 同步流程重新注册。

本轮仅规划，不修改业务代码。后续实施以本文为最终基线；`260817_1817_gateway_delete_order_correction_analysis.md` 中的蓝牙 Reset 前置方案已经废弃。

## 2. 已确认的产品与接口契约

### 2.1 Force clear spaces

- 菜单展示条件必须同时满足：
  - Gateway 详情页的蓝牙代理状态为真正的 `.disconnected`，即 UI 的 Offline；`.connecting` 不视为 Offline。
  - 当前 Gateway 的 Associated Spaces 列表不为空。
- 菜单项位于 `Identify` 下方，图标使用已有资源 `menu_clear_spaces`。
- 点击后展示全屏确认弹窗：
  - 标题：`Force clear associated spaces?`
  - 正文：`This will remove all associated spaces from the server. Spaces will be immediately available to bind to another gateway. If this gateway comes back online, it will detect no associations and prompt for reconfiguration.`
  - 操作：`CANCEL`、`FORCE CLEAR`。
- `CANCEL` 只关闭弹窗，不改变服务器或本地数据。
- `FORCE CLEAR` 调用现有接口：
  - 方法：`POST`
  - 路径：`/sitespace/sapce/gateway/unbind`
  - 请求体只包含 `gatewayId`、`userId`。
  - 必须完全省略 `spaceId` 字段，不能发送空字符串或 `null`。
- 请求最长等待 30 秒；明确的网络/API 失败可以提前结束。超时或失败均不修改本地数据。
- 成功后清空本地 Gateway 的 Associated Spaces，并提示：
  - `All associated spaces cleared from server`
  - 使用 `ToastStatusView` 的 `.siteUpdate` 成功样式。
- 失败后提示：
  - `Failed to clear all associated spaces`
  - 使用 `ToastStatusView` 的 `.siteUpdate` 失败样式。
- 权限规则：Site Owner 可执行；非 Owner 必须对当前全部关联 Space 具备 Editor 编辑权限。服务器仍为最终权限裁决方。

### 2.2 Gateway Delete

- 所有 Gateway 统一先调用服务器 `gatewayDelete`，不再依据本地 MQTT 信息或上传时间决定是否绕过服务器。
- 服务端契约：
  - `gatewayDelete` 同一事务删除 Gateway 及全部 Associated Spaces。
  - Gateway 在服务器已不存在时按幂等成功返回。
- 服务器失败或 30 秒超时：
  - 不发送蓝牙 Reset。
  - 不清除任何本地 Gateway、MQTT、Associated Spaces、Node 或 Mesh 数据。
  - 提示 `Failed to delete gateway from server`，使用 `.siteUpdate` 失败样式。
- 服务器成功后才发送蓝牙 Reset：
  - Reset 成功：执行现有永久本地删除、退出 Gateway 页面并刷新 Site。
  - Reset 失败或超时：展示现有 FORCE DELETE 确认。
    - `CANCEL`：保留本地 Gateway 数据，停留当前页面；不得重新注册服务器 Gateway。
    - `FORCE DELETE`：只执行本地永久删除，不再调用 `gatewayDelete`，也不再单独调用清空 Associated Spaces 接口。
- 进入本地永久删除阶段必须有明确的“服务器删除已确认成功”状态，避免异步回调或重复点击越过服务器确认。

## 3. 当前实现事实与差距

| 范围 | 当前实现 | 与目标的差距 |
| --- | --- | --- |
| Gateway 菜单 | `GatewayMenuPolicy` 最后添加 `Identify`；菜单宽度固定为 120 | 缺少新 action；英文长文案会被截断 |
| Offline 状态 | 已有 `GatewayDetailProxyConnectionState`，可区分 `.disconnected`、`.connecting`、`.ready` | 新菜单必须直接使用 `.disconnected`，不能使用笼统的 `!isReady` |
| 单 Space 解绑 | `.gatewayUnbindSpace` 固定发送 `spaceId`、`gatewayId`、`userId` | 需要新增语义明确、请求体完全不含 `spaceId` 的“清空全部”API case |
| 网络超时 | `NetworkRequest.requestClosure` 对全部请求固定为 10 秒 | 清空全部和删除 Gateway 需要各自 30 秒上限，不能全局修改其他接口 |
| Associated Spaces 保存 | 比较持久模型与编辑副本，逐条调用 bind/unbind，全部完成后保存本地 | 保留现有普通编辑语义；不能把普通逐条解绑替换成强制清空 |
| Gateway Delete | 已注册分支先调用服务器，但服务器成功后立即清本地字段；未注册分支会绕过服务器 | 必须统一服务器前置，并把所有本地清理延后至 Reset 成功或 FORCE DELETE |
| 删除失败回调 | 服务器已授权但 Reset 未完成时会发送 `siteGatewayDataChanged` | Site 页收到后会排队 `syncGateway`，可能重新注册已从服务器删除的 Gateway |
| Cloud 同步 | `CloudSynchronizationManager` 支持按 `.syncGateway` operation 取消同步 | 删除请求前应取消同一 Gateway 的既有同步任务，并禁止删除流程再触发同步通知 |
| 蓝牙永久删除 | 通用 `deleteNodes` 已覆盖 Reset 成功、Reset 失败后 FORCE DELETE、Node extension 清理 | 最终顺序下可以复用，无需修改 NordicSigMeshSDK |

## 4. 总体设计

### 4.1 Force clear spaces 状态流

```text
Offline + Associated Spaces 非空
              |
              v
显示 Force clear spaces -> 确认弹窗
              |                 |
           CANCEL           FORCE CLEAR
              |                 |
           关闭弹窗        权限预检 + Loading
                                |
                                v
                  unbind(gatewayId, userId), 30s
                         |               |
                      成功          失败/超时
                         |               |
             清服务器已确认后       本地不变
             清本地两个模型副本          |
             保存并刷新关联拓扑           v
                         |            失败 Toast
                         v
                     成功 Toast
```

### 4.2 Gateway Delete 状态流

```text
用户确认 Delete
       |
权限预检 + 取消既有 syncGateway
       |
gatewayDelete, 30s
       |------------------- 失败/超时 -> 本地不变 + 失败 Toast
       v
服务器成功（删除状态锁定）
       |
蓝牙 Reset
       |------------------- 失败/超时 -> FORCE DELETE 弹窗
       |                                      |          |
       |                                   CANCEL      FORCE DELETE
       |                                      |          |
       |                               保留本地，不同步   仅本地永久删除
       v                                                 |
本地永久删除 <-------------------------------------------+
       |
关闭页面 + 刷新 Site
```

## 5. 详细开发方案

### 5.1 网络 API：区分“解绑一个”与“原子清空全部”

在 `NetowrkReqeustApi` 新增独立 case，例如语义为 `gatewayUnbindAllSpaces(gatewayId:)`：

- 与 `.gatewayUnbindSpace` 使用相同 path 和 HTTP method。
- 参数只构造 `gatewayId`、`userId`。
- 增加独立 `diagnosticName`，方便日志与测试识别。
- 保持 `.gatewayUnbindSpace(spaceId:gatewayId:)` 不变，避免普通编辑流程误用清空语义。

不建议把现有 `spaceId` 直接改为 Optional，因为调用方可能误传 `nil`，会把原本“解绑一个”的编程错误变成“清空全部”的破坏性请求。独立 case 能在类型层面隔离风险。

### 5.2 请求超时：只对两个破坏性操作设置 30 秒

为 `NetowrkReqeustApi` 增加只读的目标级请求超时配置，并增加一个很小的 Moya timeout plugin：

- 默认值保持当前 10 秒，避免影响全部现有 API。
- `gatewayUnbindAllSpaces` 和 `gatewayDelete` 返回 30 秒。
- plugin 通过 `PluginType.prepare(_:target:)` 获得实际 `NetowrkReqeustApi` target，再写入 `URLRequest.timeoutInterval`。
- 将 plugin 加入现有 `MoyaProvider`，并保留当前 request closure 的其他行为。

不能只在现有 `requestClosure` 中按 URL path 判断：该 closure 只有 `Endpoint`，且“解绑一个”与“清空全部”使用完全相同的 path，按 path 会错误地改变普通解绑超时。Moya plugin 能直接按 API case 区分两种语义。

异步业务层还需保证一次操作只完成一次：

- API 明确返回失败时立即结束。
- 到达 30 秒时取消/忽略尚未结束的请求并返回超时失败。
- 超时后到达的迟到成功回调不得再清本地数据或覆盖失败 Toast。
- 页面退出、对象释放或重复点击时，不允许旧任务更新新的页面状态。

目标级超时本身是第一道限制；业务操作的一次性完成保护用于消除取消与回调竞争。

### 5.3 菜单策略与展示

扩展 `GatewayMenuAction`，增加 `.forceClearSpaces`，并扩展 `GatewayMenuPolicy.menuActions` 输入：

- 固件类型。
- Delete 权限。
- 当前代理连接状态是否为 `.disconnected`。
- 当前 Associated Spaces 是否非空。
- 当前缓存权限是否为 Site Owner，或全部关联 Space 均为 Editor。

菜单顺序固定为：

1. 4G/Wi-Fi DFU
2. Delete（有权限时）
3. Information
4. Identify
5. Force clear spaces（满足状态与权限展示条件时）

Offline + 非空是不可放宽的业务状态条件；在此基础上，破坏性菜单沿用权限可见性规则，仅对本地缓存判断为 Owner/全部 Editor 的用户展示。点击后仍重新查询并执行完整权限预检，不能把本地缓存权限状态当成服务器最终结论。

`GatewayViewController.moreClick()` 每次打开菜单时根据最新状态重新计算，避免连接状态或关联列表变化后沿用旧菜单。新菜单存在时将宽度从固定 120 调整为能够完整显示英文文案的尺寸，优先按项目现有缩放方法使用约 164 的设计宽度；其他菜单保持现有宽度，减少视觉影响。

### 5.4 Force clear 确认弹窗与 Loading

复用项目现有 `SRAlertView`，按 Figma node `494:13837` 落地：

- 卡片设计宽度约 302，圆角 20。
- 标题与正文使用 `#404F66` 对应的项目主题色；字体 15 pt，正文行高约 22。
- `CANCEL` 保持普通动作样式。
- `FORCE CLEAR` 使用项目 `Error_Red_Color`，不使用当前 destructive 默认色与 Figma 不一致的红色。
- 使用全屏遮罩，弹窗展示期间阻止背景交互。

点击 `FORCE CLEAR` 后关闭确认态并展示全屏 Loading。操作进行中锁定重复点击；无论成功、失败、超时或页面退出，都必须成对关闭 Loading。

### 5.5 Force clear 权限与服务器操作

操作开始时冻结 Gateway ID 和 Associated Spaces ID 快照，避免请求期间编辑副本变化影响权限判断或结果提交。

权限预检：

- Site Owner：直接调用清空接口。
- 非 Owner：调用现有 `gatewayAssociationSpaceList` 获取服务器最新关联列表；只有全部关联 Space 都具备 Editor 权限才继续。
- 权限不足：不调用清空接口，显示现有 `no_permission` 提示。
- 权限查询失败：按操作失败结束，本地不变。
- 服务器清空接口仍负责最终鉴权；403/业务拒绝统一进入失败分支。

30 秒上限覆盖用户点击 `FORCE CLEAR` 后的完整服务器阶段，包括必要的权限查询和清空请求，避免权限查询与清空各等待 30 秒导致总等待翻倍。

### 5.6 Force clear 成功后的本地提交

仅收到服务器成功结果后，在主线程一次性提交本地变化：

- 清空持久模型 `gatewayModel.associatedSpaces`。
- 清空页面编辑副本 `setGatewayModel.associatedSpaces`，避免页面仍显示未保存差异。
- 保存 GatewayModel。
- 重新加载 Gateway 页面 Associated Spaces 区域和底部保存状态。
- 发送现有“Gateway association topology changed”通知，刷新 Site 的关联拓扑。
- 不发送 `siteGatewayDataChanged`，因为该通知会触发 `syncGateway`，而本操作已经直接提交服务器。
- 展示 `.siteUpdate(.success)` Toast：`All associated spaces cleared from server`。

失败、超时、取消或迟到回调均不得修改上述任一对象。

### 5.7 保留普通 Associated Spaces 编辑流程

现有保存流程继续使用差异计算和逐条接口：

- 示例：原有 3 个 Space，用户移除 2 个后 Save。
- 页面编辑阶段只修改 `setGatewayModel`。
- Save 时计算出两个 unbind 差异。
- 依次发送两次 `.gatewayUnbindSpace`，每次都包含对应的 `spaceId`、`gatewayId`、`userId`。
- 服务器调用全部成功后，才保存本地模型，并继续现有 Mesh Key 清理。

该普通流程仍存在“第一个解绑成功、第二个失败”时服务器部分完成的既有风险；本需求不改变该契约。独立 Force clear 始终只发送一次原子清空请求。

### 5.8 Gateway Delete：统一服务器前置

重构 `deleteBtnAction()`，移除当前“是否已注册”的本地分支判断。确认 Delete 后统一执行：

1. 检查 `canConfigureCurrentGateway`。
2. 非 Owner 时沿用当前 Associated Spaces 权限查询，确认对全部关联 Space 有 Editor 权限。
3. 记录该 Gateway 是否存在待同步状态，并取消当前已排队或执行中的 `.syncGateway` handle。
4. 进入删除中状态，禁止重复触发 Delete、Save、Force clear 或新的 Gateway 同步通知。
5. 展示 Loading 并调用 `.gatewayDelete`，最多等待 30 秒。
6. 服务器失败/超时：关闭 Loading，解除页面操作锁；本地保持原样；若删除前存在待同步状态，则恢复原 `.syncGateway`；显示 `Failed to delete gateway from server`。
7. 服务器成功：持久化 `serverDeletionPendingLocalReset` 标记，同时记录本次页面操作的 `serverDeletionConfirmed` 状态，然后调用蓝牙 Reset。

服务器成功时不得提前执行以下操作：

- 不清 `mqttServerInfo`。
- 不清 `associatedSpaces`。
- 不清 `lastUploadCloudTimestamp`。
- 不保存清空 MQTT、Associated Spaces 等业务字段的中间删除态；只允许写入防重注册 tombstone。
- 不删除 GatewayModel、Node extension 或 Mesh Node。

`serverDeletionPendingLocalReset` 只是防止重新注册的 tombstone，不清空任何 Gateway 业务字段。这样 Reset 失败且用户选择 `CANCEL` 时，本地对象仍完整，可供用户再次进入 Delete 流程；下一次 Delete 依靠服务端幂等契约再次成功确认。

### 5.9 蓝牙 Reset 与 FORCE DELETE

服务器成功后复用现有 `deleteNodes` 永久删除能力：

- Reset 成功：现有 `DevicePermanentDeletionContext` 提交 Node extension/Mesh 等清理，随后关闭 Gateway 页面并刷新 Site。
- Reset 失败/超时：使用现有强制删除弹窗。
- 用户 `CANCEL`：回调归类为删除未完成，保留本地数据并刷新当前页面；不发送任何 Gateway cloud sync 通知。
- 用户 `FORCE DELETE`：仅调用现有本地永久删除提交；不得再次请求服务器。

调用 Reset 前以及处理 FORCE DELETE 成功回调前，都要断言本次状态已获得服务器成功确认。这样即使发生重复回调，也不会出现服务器未确认却删除本地的路径。

最终顺序可以完全复用当前 SDK 对 Config Node Reset Status 的处理，因此本计划不修改 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk`，也不切换或提交 SDK 代码。

### 5.10 防止服务器删除后被重新注册

当前 `SiteViewController` 收到 `siteGatewayDataChanged` 后会修改时间戳并新增 `.syncGateway`；`viewWillAppear` 还会通过 `retryDirtyGatewayCloudUploads()` 自动重试脏 Gateway。只移除一次通知不足以覆盖 App 退出重启和已有脏数据，因此需要一个持久化 tombstone：

- 调用 `gatewayDelete` 前，通过 `CloudSynchronizationManager.cancelSynchronizationHandle(operation:)` 取消同一 MAC 的既有 `.syncGateway`。
- 只有 `gatewayDelete` 成功后，才把 GatewayModel 的 `serverDeletionPendingLocalReset` 设为 `true` 并保存；服务器失败时不写该标记。
- `CloudSynchronizationManager` 在 `.syncGateway` 真正执行服务器授权前统一检查该标记，为 `true` 时直接终止且不发请求；Site 页的 dirty retry 同样跳过，避免无意义入队。
- 删除操作从服务器请求开始到 Reset/强制删除结果结束期间，不发布 `siteGatewayDataChanged`。
- 删除服务器成功、Reset 失败且用户 `CANCEL` 时，也不发布该通知。
- 删除完成只发布用于 Site 本地刷新/拓扑刷新的通知，不触发 Gateway 注册上传。
- 检查 Gateway 页面退出、table reload、Reset completion 等所有现有通知点，确保删除专用路径不会间接调用 `persistGatewayConfiguration()`。
- Reset 成功或 FORCE DELETE 后 GatewayModel 整行删除，tombstone 随之消失。
- 用户稍后再次 Delete 时仍先调用幂等 `gatewayDelete`；不能仅凭 tombstone 跳过服务器确认。

数据库在现有 `gateways` 表增加默认值为 `false` 的 Bool 列，并沿用项目当前 `initDatabase()` 的增列方式兼容旧数据库。该标记不导出到服务器，也不改变服务器 Gateway 数据结构。

### 5.11 国际化与文案

新增独立 localization keys，并同步更新 English 与 `zh-CN`：

| Key 语义 | English | 简体中文建议 |
| --- | --- | --- |
| 菜单 | `Force clear spaces` | `强制清除空间关联` |
| 弹窗标题 | `Force clear associated spaces?` | `强制清除关联空间？` |
| 弹窗正文 | Figma 完整英文正文 | `这将从服务器移除所有关联空间。空间将立即可绑定到其他网关。如果此网关重新上线，它会检测到没有关联并提示重新配置。` |
| 确认按钮 | `FORCE CLEAR` | `强制清除` |
| 清空成功 | `All associated spaces cleared from server` | `已从服务器清除所有关联空间` |
| 清空失败 | `Failed to clear all associated spaces` | `无法清除所有关联空间` |
| 删除服务器失败 | `Failed to delete gateway from server` | `无法从服务器删除网关` |

`CANCEL` 优先复用现有 key。所有新增文案禁止在 Controller 中硬编码。

## 6. 预计修改文件

| 文件/目录 | 计划改动 |
| --- | --- |
| `SunSmart/Common/Network/NetowrkReqeustApi.swift` | 新增原子清空 Associated Spaces case、参数、路径映射、诊断名和目标级超时配置 |
| `SunSmart/Common/Network/NetworkRequest.swift` | 注册 target 级 timeout plugin，支持 30 秒破坏性请求且不影响其他 API |
| `SunSmart/Common/Network/NetworkRequestTimeoutPlugin.swift`（建议新增） | 通过 Moya target 安全应用每个 API case 的 timeout |
| `SunSmart/Main/Device/Gateway/Model/GatewayModel.swift` | 增加并复制 `serverDeletionPendingLocalReset` tombstone |
| `SunSmart/Common/Data/Database.swift` | 为 gateways 表增列、读写 tombstone，旧数据库默认 false |
| `SunSmart/Main/Device/Gateway/Model/GatewayMenuPolicy.swift` | 新增菜单 action、展示条件和顺序策略 |
| `SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift` | 新菜单、确认弹窗、权限预检、Force clear 流程、本地提交、Delete 状态顺序与通知隔离 |
| `SunSmart/Common/Cloud/CloudSynchronizationManager.swift` | 复用按 operation 取消能力，并集中阻止 tombstone Gateway 再次入队同步 |
| `SunSmart/Main/Site/Controller/SiteViewController.swift` | dirty Gateway 自动重试时跳过 tombstone Gateway |
| English / zh-CN Localizable strings | 新增全部用户可见文案 |
| Gateway 相关单元测试 target | API contract、菜单策略、清空与删除状态测试 |
| `SunSmart.xcodeproj/project.pbxproj` | 仅当新增测试/业务文件时，补入 SunSmart、Archipelago、SLG Sync Plus、SylSmart 对应 target membership |

现有用户新增资源 `menu_clear_spaces.imageset` 直接复用，不覆盖、不重新生成。修改资源或 target 配置时检查四个品牌 target 的可访问性。

## 7. 测试计划

### 7.1 API contract 测试

- `.gatewayUnbindSpace` 请求体包含准确的 `spaceId`。
- `.gatewayUnbindAllSpaces` 请求体不含 `spaceId` key，且包含 `gatewayId`、`userId`。
- 两者 path 相同，diagnosticName 不同。
- `gatewayUnbindAllSpaces` 与 `gatewayDelete` timeout 为 30 秒；其他 API 仍为 10 秒。
- 同 path 的普通 `.gatewayUnbindSpace` 仍为默认 10 秒。
- `gatewayDelete` 对服务端“已不存在”的幂等成功响应进入 success。

### 7.2 菜单策略测试

- `.disconnected` + 非空：在 `Identify` 后出现 Force clear。
- `.connecting` + 非空：不出现。
- `.ready` + 非空：不出现。
- `.disconnected` + 空列表：不出现。
- 4G/Wi-Fi 两类菜单顺序一致，DFU action 保持对应类型。
- Force clear 的缓存权限不满足时隐藏；缓存权限满足后点击仍必须进行服务器最新权限预检。

### 7.3 Force clear 状态测试

- `CANCEL` 无请求、无本地修改。
- Owner 成功：一次原子请求，两个本地模型清空、保存、刷新拓扑、成功 Toast。
- 全部 Space 为 Editor：允许请求。
- 任一 Space 无 Editor：不发清空请求，本地不变。
- 网络失败、API 失败、30 秒超时：本地不变、失败 Toast。
- 超时后的迟到成功：仍保持本地不变，不出现第二个 Toast。
- 重复点击：只产生一次服务器请求。
- 页面退出：Loading 正确关闭，回调不访问失效 UI。

### 7.4 普通编辑回归测试

- 3 个 Space 移除 2 个后 Save，产生两次带不同 `spaceId` 的解绑请求。
- 第二次失败时不误调用清空全部接口。
- 全部成功后才提交本地编辑模型，并继续现有 Mesh Key 清理。

### 7.5 Gateway Delete 状态测试

- 所有 Gateway 都先请求 `gatewayDelete`，不再存在未注册绕过分支。
- 服务器失败/超时：未发送 Reset，本地所有字段保持不变，固定失败 Toast。
- 删除前存在待同步 Gateway、服务器删除失败：原同步意图恢复，不会因防竞态而永久丢失。
- 服务器成功 + Reset 成功：本地永久删除、关闭页面、刷新 Site。
- 服务器成功 + Reset 失败 + `CANCEL`：本地业务数据保留、tombstone 保留，不发第二次服务器请求，不排队 `syncGateway`。
- 服务器成功 + Reset 失败 + `FORCE DELETE`：仅本地永久删除，不发第二次 `gatewayDelete` 或 unbind-all。
- 服务器返回 Gateway 不存在的幂等成功：继续 Reset。
- 服务器迟到回调、Reset 重复回调、重复点击：本地永久删除最多提交一次。
- 删除前已有 `.syncGateway`：任务被取消，服务器成功后不会重新注册。
- `CANCEL` 后离开再进入 Site、网络恢复、App 重启：tombstone Gateway 均不会被 dirty retry 自动重新注册。
- tombstone Gateway 再次 Delete：仍要求服务器幂等成功后才进入 Reset。
- 权限查询失败/不足：不调用 `gatewayDelete`。

### 7.6 UI、静态与构建验证

- 对照 Figma 验收弹窗尺寸、遮罩、字体、行高、按钮颜色及长正文换行。
- 验收英文菜单不截断；中文菜单布局无回归。
- 检查 icon 在四个 target 中均能加载。
- 运行相关单元测试。
- 运行 `git diff --check`。
- 按 AGENTS 规则直接运行 generic iPhoneOS unsigned build，不使用 Simulator，并依次验证：
  - SunSmart
  - Archipelago
  - SLG Sync Plus
  - SylSmart
- 真机/联调验收仍需覆盖：真实 BLE Reset 成功、BLE 超时、服务器 30 秒超时、服务器幂等删除、Force clear 后空间可重新绑定，以及 Gateway 恢复在线后的重新配置提示。

构建通过只能证明编译和链接，不等于服务器、BLE、Mesh 或视觉端到端验收完成。

## 8. 实施顺序

1. 先补 API contract、菜单策略和删除状态测试，锁定请求体、顺序及无本地副作用要求。
2. 新增原子清空 API case、target timeout 配置和 Moya timeout plugin。
3. 扩展菜单策略、国际化和 Figma 弹窗。
4. 实现 Force clear 权限预检、Loading、一次性完成保护和成功后的本地原子提交。
5. 增加本地 tombstone 数据库兼容，并在 Gateway cloud sync/dirty retry 的公共入口阻止重新注册。
6. 重构 Gateway Delete 为统一服务器前置，移除本地注册状态分支和服务器成功后的提前本地清理。
7. 接入 Reset/FORCE DELETE 结果，取消既有 `syncGateway`、处理失败恢复并清理删除路径中的同步通知。
8. 完成单元测试、静态检查、四 target 构建和真机/服务器验收清单。

## 9. 开发边界

- 不修改服务器接口协议。
- 不把普通逐条 Associated Spaces 编辑替换为原子清空。
- 不修改 NordicSigMeshSDK。
- 只新增一个本地 tombstone 列用于阻止服务器删除后的自动重新注册；不扩展为通用删除状态机或服务器字段。
- 不顺手重构通用 Alert、Toast、Cloud Sync 或 Device Delete 架构。
- 不修改与本需求无关的资源、格式或 target 配置。
- 不覆盖当前 worktree 中已有的 `menu_clear_spaces` 用户改动。

## 10. 开始实施前的确认结论

方案已经具备实现所需的接口语义、权限、超时、状态顺序、失败文案和本地提交边界，不再存在必须等待服务器补充的接口阻塞项。获得实施确认后，可按第 8 节顺序开始编码。
