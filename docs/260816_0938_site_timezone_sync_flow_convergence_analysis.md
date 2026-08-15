# Site Time Zone 同步流程与 UI 收敛分析

## 文档状态

- 日期：2026-08-16
- 状态：方案 A 已于 2026-08-16 确认
- 工程：SunSmart iOS UIKit
- 本轮范围：分析 `SiteEntryTimeZoneSyncOverlay` 是否应合并到 `SiteTimeZoneSyncStatusView`，以及进入 Site、从 Sites 编辑 Site、从 Site 编辑 Site 三条路径如何复用同一套 Site/Gateway 时区同步流程
- 本轮不修改业务代码，不执行 Git commit、push 或 merge

## 1. 结论

需求方向合理，且应该收敛，但不能只做 UIView 层面的包含或重命名。

推荐保留 `SiteTimeZoneSyncStatusView` 作为唯一的时区同步展示视图，将 `SiteEntryTimeZoneSyncOverlay` 已有的 checking、Site 结果、逐网关状态、动态高度、Footer 和安全区布局迁入其中，并在调用点完成迁移后删除 `SiteEntryTimeZoneSyncOverlay`。

同时必须抽取入口无关的 Gateway 同步阶段。原因是 Edit Site 当前只有 Site 属性提交结果，没有完整的权限、Spaces、Gateways 和 `timezoneOffset` 快照；如果只合并 UI，Edit Site 仍然无法正确判断网关范围和是否需要同步，也无法展示真实的 `Pushing…`、`Synced`、`Failed`。

不建议把“进入 Site 时的 App/Cloud 仲裁”和“用户在 Edit Site 明确提交新时区”强行改成同一条 Site 决策逻辑。两者触发语义不同，但在 Site 时区得到可信终态之后，可以进入同一个 Gateway Target Builder、Gateway Sync Coordinator 和统一状态视图。

## 2. 当前实现与职责差异

| 维度 | `SiteTimeZoneSyncStatusView` | `SiteEntryTimeZoneSyncOverlay` |
| --- | --- | --- |
| 当前入口 | Edit Site 保存时区后 | 首次进入 Site 并取得完整 Site 响应后 |
| Site 状态 | `saving/success/failure` | `checking` 与具体 Site 结果 |
| Gateway 数据 | 固定 “No gateways” 卡片 | 全部授权网关及逐项状态 |
| Gateway 请求 | 无 | `/gateway/datetime/update` 与 `/request/status` |
| 权限范围 | 无 | Owner 全部、Editor Spaces 绑定范围、Visitor 无操作 |
| 生命周期 | 添加到 active window，终态可关闭 | 由 Site 页面持有，锁导航，页面消失时取消 |
| 数据来源 | `/retrieve/siteprops` 与 `/update/siteprops` | `/get/siteprops` 的完整 Site/Spaces/Gateways 快照 |

因此，两个 View 可以合并为一个展示组件；两个业务入口不能仅靠 View 合并自动得到相同能力。

## 3. 需求完整性检查

### 3.1 已经明确且合理的部分

- 进入 Site 后继续检查授权 Gateways 的 timezone。
- 从 Sites 或 Site 进入 Edit Site，只要实际更新了 Time Zone，就展示同一套同步进度 UI。
- Gateway 只有在需要更新时才进入 `Pushing…`，完成后变成 `Synced` 或 `Failed`。
- 逐网关状态继续复用当前图标、动画、动态列表和失败统计规则。
- 两个 Edit Site 入口继续返回各自来源页面，不改变既有路由归属。

### 3.2 需要补足的规则

#### Site 更新失败

推荐规则：Site Cloud 更新失败时，不调用 Gateway 下发接口。Cloud Site timezone 尚未变成目标值，服务器不能安全地按新时区下发 Gateway。UI 显示 Site 失败，Gateway 阶段标记为未开始，不伪造逐网关失败结果。

#### 完整 Site 快照获取失败

Edit Site 的 `/update/siteprops` 响应不包含 Spaces、Gateways、权限范围或 Gateway `timezoneOffset`。Site 更新成功后必须再读取 `/get/siteprops` 并使用现有 parser。

推荐规则：完整快照读取或解析失败时，Site 仍显示 `Updated to server`，Gateway 区域显示“无法检查网关”终态并允许 `DONE`；不得显示 `No gateways`，也不得绕过权限向本地全部 Gateway 下发。该状态需要新增 English 与简体中文文案。

#### 离线编辑

推荐保留当前边界：本地持久化并保留 pending，不展示 Gateway 推送进度，因为离线时无法确认 Cloud Site timezone、远端权限和 Gateway offset。恢复联网后的进入 Site/刷新流程负责继续收敛。

#### 权限变化

每次 Edit Site 成功提交时区后重新获取完整远端快照，以提交后的最新 Owner/Editor/Visitor 权限构建目标，不复用可能过期的页面缓存。

#### 并发与重复会话

同一时刻只允许一个可见的 Site timezone 同步会话。新的会话启动前取消旧会话；所有异步回调必须使用 session token 隔离，避免迟到响应更新另一个 Site 的 UI。

#### 页面刷新和 Review sync

- 从 Site 页面编辑：终态后静默刷新当前 Site 的远端快照，更新 Gateway 名称颜色和 Review sync。
- 从 Sites 页面编辑：刷新 Sites 列表中的本地 Site；失败 Gateway 不需要在 Sites 页新增入口，之后进入 Site 时由远端 offset 重新投影 Review sync。
- 进入 Site：保留当前导航锁、后续导航恢复和页面消失取消行为。

## 4. 方案比较

### 方案 A：统一 View，加共享 Gateway 同步阶段，保留两种 Site 触发策略（推荐）

做法：

- `SiteTimeZoneSyncStatusView` 吸收 Overlay 的完整 UI 和展示状态。
- 删除 `SiteEntryTimeZoneSyncOverlay`。
- 抽取共享的远端快照读取器、本地 Gateway 快照构建器和 Gateway 同步会话。
- 进入 Site 继续使用现有 App/Cloud 仲裁。
- Edit Site 继续使用明确的用户更新语义；Site 上传成功后获取完整快照，再进入共享 Gateway 阶段。

优点：真正收敛 UI 和 Gateway 流程，保留两种入口正确的业务语义，测试边界清晰。

代价：需要调整 `SiteViewController` 当前持有的部分 Gateway 会话编排，并为 Edit Site 增加完整快照读取与终态回调。

### 方案 B：让 `SiteTimeZoneSyncStatusView` 内嵌 Overlay，Edit Site 复制 Site 页编排

做法：保留两个 View，由状态视图把 Overlay 当作子视图；Edit Site 另写一套目标构建和轮询调用。

优点：短期代码改动较少。

缺点：只有视觉表面复用，业务流、取消、超时、权限、失败回收会形成两套实现，后续极易漂移，不满足“流程和 UI 展示收敛”。

### 方案 C：把 Site 仲裁、Edit 提交、Gateway 推送全部重写为一个大 Coordinator

做法：所有入口只传 trigger，由一个 Coordinator 处理所有网络、本地持久化、权限、Gateway 同步和 UI 生命周期。

优点：调用入口最少。

缺点：把“被动仲裁”和“主动编辑”混在一起，状态机过大，回归范围覆盖 Site 导入、pending、Visitor、导航和 Gateway 三分钟轮询；本次需求不需要承担这类重写风险。

## 5. 推荐架构

### 5.1 唯一展示组件

`SiteTimeZoneSyncStatusView` 只消费展示状态，不访问网络、不推导权限、不读取数据库：

- 工作态：进入 Site 时显示 checking；Edit Site 时显示 saving/checking。
- 结果态：Site 结果加 Gateway 展示状态。
- Gateway 状态继续由 `SiteEntryGatewayTimeZoneStatusView` 渲染；后续可在不改变行为的前提下重命名为无 Entry 前缀的类型。
- `DONE` 只在没有 `Pushing…` 时显示。
- 保留当前全宽、底部安全区白色背景、左侧状态图标、Dynamic Type、VoiceOver 和列表滚动实现。
- 默认展示在 active window；进入 Site 时也允许显式传入 navigation controller view，以保留当前生命周期控制。

### 5.2 共享远端快照读取器

新增入口无关的 remote snapshot provider：

- 调用现有 `.siteInfo(siteId:)`，即 `/sitespace/get/siteprops`。
- 使用 `SiteEntryTimeZoneSyncResponseParser` 解析 Site、Spaces、Gateways 和权限。
- 只返回不可变快照，不在 provider 内执行整站 import。
- 网络失败或响应不完整返回显式失败，不降级为 No gateways。

### 5.3 共享本地 Gateway 快照构建器

从 `GatewayModel.load(siteId:)` 和对应 Mesh network 构造：

- Gateway 展示名称。
- 可验证的本地 dirty timezone override。
- 无法解析 Node 时仍保留名称，但不伪造本地 offset。

权限仍只由远端快照决定，本地数据库不能扩大操作范围。

### 5.4 共享 Gateway 同步会话

从 `SiteViewController.startGatewayEntrySyncIfNeeded` 抽取入口无关的 Gateway 阶段：

输入：

- Site ID。
- 已确认的目标 `SiteTimeZoneValue`。
- Site 同步结果。
- 完整远端快照。
- 本地 Gateway 快照。
- 当前会话内已确认成功的 offset。

处理：

1. 使用现有 `SiteGatewayCloudTimeZoneTargetBuilder` 构建授权目标。
2. 已一致项初始为 `Synced`，待更新项初始为 `Pushing…`。
3. 只有待更新 MAC 进入现有 `SiteGatewayCloudTimeZoneSyncCoordinator`。
4. 下发、轮询或 180 秒超时后输出终态。
5. 产出成功 override 和失败 Gateway ID，供来源页刷新 Review sync。

### 5.5 触发策略

#### 进入 Site

1. 保留当前 `/get/siteprops`、导入前快照、权限解析和 dirty override 捕获。
2. 保留 `SiteEntryTimeZoneSyncPolicy` 与 `SiteEntryTimeZoneSyncCoordinator` 的 App/Cloud 仲裁。
3. Site 阶段得到可信结果后进入共享 Gateway 同步会话。
4. 使用统一 `SiteTimeZoneSyncStatusView` 展示。
5. 终态静默刷新并更新 Review sync；关闭后恢复导航。

#### Edit Site

1. 保留草稿、确认弹窗、本地 persist 和来源页 dismiss 逻辑。
2. 创建统一状态视图并进入 saving。
3. 提交 `/update/siteprops`。
4. 提交失败：显示 Site 失败，Gateway 不启动。
5. 提交成功：显示 `Updated to server`，读取完整 `/get/siteprops` 快照。
6. 校验快照 Site timezone 与本次目标一致；不一致时按 Gateway 快照不可用处理，禁止下发。
7. 构建本地 Gateway 快照并进入共享 Gateway 同步会话。
8. 终态通知来源 controller 刷新；Sites 和 Site 的路由保持不变。

## 6. 状态矩阵

| Site 阶段 | Gateway 快照 | 授权目标 | 待更新目标 | UI 与动作 |
| --- | --- | --- | --- | --- |
| 处理中 | 未请求 | 未知 | 未知 | 工作态，不可关闭 |
| 失败 | 不要求 | 未知 | 未知 | Site Failed；Gateway 未开始；允许 DONE |
| 成功 | 获取失败/不一致 | 未知 | 未知 | Site 成功；Gateway 无法检查；允许 DONE；不下发 |
| 成功 | 有效 | 0 | 0 | No gateways；允许 DONE |
| 成功 | 有效 | 大于 0 | 0 | 全部 Synced；允许 DONE；不调用下发 |
| 成功 | 有效 | 大于 0 | 大于 0 | 待更新项 Pushing；全部终态前不可关闭 |
| 成功 | 有效 | 大于 0 | 部分/全部失败 | 对应行 Failed，显示失败统计与现场 Bluetooth 引导；允许 DONE |

## 7. 分阶段实施计划

### 阶段 1：锁定现状与失败语义

- 扩展现有 contract/unit tests，覆盖两个 View 当前入口、Edit Site 的 site-only 行为和 Site 页的逐网关行为。
- 新增“完整快照失败不能显示 No gateways”和“Site 上传失败不能调用 Gateway API”的失败测试。
- 确认离线、Visitor、并发会话与来源页刷新规则。

### 阶段 2：统一展示组件

- 将 Overlay 的 checking/result UI 和状态接口迁入 `SiteTimeZoneSyncStatusView`。
- 让 Site 页面改用统一 View，保持现有展示和生命周期行为。
- 删除 Overlay 及其工程 Sources 引用。
- 保持 `SiteEntryGatewayTimeZoneStatusView` 行状态 UI 不变；可仅做聚焦重命名，不同时重构布局。

### 阶段 3：抽取共享 Gateway 阶段

- 把 Target Builder、Gateway Coordinator 的串联和终态结果从 `SiteViewController` 抽为独立会话对象。
- Site 入口接入新会话，确保行为与现状一致。
- 覆盖取消、session token、无目标、提交失败、轮询、超时和结果不可逆测试。

### 阶段 4：Edit Site 接入

- 增加完整 Site 快照读取器和本地 Gateway 快照构建器。
- Edit Site 上传成功后获取权威快照，再启动共享 Gateway 阶段。
- Sites/Site 两个入口通过 finish completion 注入来源刷新回调，但状态视图继续全屏展示。
- Site 上传失败、快照失败、快照 timezone 不一致全部 fail closed。

### 阶段 5：回归与验收

- 运行 Site props、Entry policy/coordinator、Gateway target/coordinator、Edit routing、统一 UI 的聚焦测试。
- 运行 `scripts/check_site_sync_gateways.sh` 与 `git diff --check`。
- 检查删除/重命名文件在 SunSmart、Archipelago、SLG Sync Plus、SylSmart 四个 target 的 Sources membership。
- 串行执行四个 scheme 的 generic iPhoneOS Debug、关闭签名构建。
- 真机验证 Sites Edit、Site Edit、进入 Site、Owner、Editor、无 Gateway、全部一致、部分失败、超时、后台/前台、英文/简体中文、小屏与 iPad。

## 8. 预计文件范围

主要修改：

- `SunSmart/Main/Site/View/SiteTimeZoneSyncStatusView.swift`
- `SunSmart/Main/Site/View/SiteEntryGatewayTimeZoneStatusView.swift`
- `SunSmart/Main/Site/Controller/SiteEditViewController.swift`
- `SunSmart/Main/Site/Controller/SiteViewController.swift`
- `SunSmart/Main/Site/Controller/SitesViewController.swift`
- `SunSmart/Main/Site/Model/SiteGatewayCloudTimeZoneSyncCoordinator.swift`
- `SunSmart/Main/Site/Model/SiteGatewayCloudTimeZoneTarget.swift`
- `SunSmart/Main/Site/Model/SiteEntryTimeZoneSyncResponseParser.swift`
- 相关 Site contract/unit tests
- English 与简体中文本地化文件，仅在确认 Gateway 快照失败态文案后修改

预计删除：

- `SunSmart/Main/Site/View/SiteEntryTimeZoneSyncOverlay.swift`

预计新增：

- 入口无关的完整 Site 快照读取器。
- 入口无关的本地 Gateway 快照构建器。
- 共享 Gateway 同步会话及对应单元测试。

最终文件命名应在实施计划前结合现有 target membership 再确认，避免为类型重命名扩大不必要的工程文件变更。

## 9. 风险与验证边界

- `/update/siteprops` 成功只证明 Cloud Site 属性响应匹配，不证明 Gateway 已更新。
- `/gateway/datetime/update` 返回 requestId 不等于逐网关成功，必须以 `/request/status` 终态为准。
- 服务器 Gateway success 不等于本地 Mesh Node timezone/timestamp 已持久化。
- 自动化测试和 generic iPhoneOS 构建不能替代真实服务器权限、真实 Gateway、Bluetooth Review sync、导航动画与真机视觉验收。
- 当前 worktree 已有未提交的 Time zone sync UI 修改；实施时必须在其基础上迁移，不能覆盖或重置。

## 10. 已确认决策

采用方案 A，并确认以下规则：

1. Site 上传失败时不启动 Gateway 阶段，UI 显示 Site Failed，允许 DONE。
2. Site 上传成功但完整 Site/Gateway 快照失败或 timezone 不一致时，显示“Gateway 无法检查”终态，允许 DONE，不显示 No gateways，不调用 Gateway API。
3. 离线编辑继续只保留本地 pending，不展示 Gateway 推送进度。
4. Gateway 失败继续由 Site 页现有 Review sync/Bluetooth 流程承接，不在 Sites 页新增 Review sync 入口。
