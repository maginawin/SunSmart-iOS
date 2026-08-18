# Gateway 返回 Site 后时区状态未自动收敛：原因分析与开发方案

## 结论

问题确认存在，且根因不在 `Review sync` 组件自身的显示/隐藏逻辑，也不在 Gateway 页的 Mesh 时区同步结果判定。

当前 Gateway 页点击 `SYNC NOW` 成功后，已经完成：

1. 向当前直连 Gateway 发送 `TimeSet`；
2. 再发送 `TimeGet` 做最终回读；
3. 校验 Gateway Offset 与 Site 目标 Offset 相同，并校验时间误差；
4. 将回读时间和时区保存到本地 Node；
5. 将 Gateway 标记为待上传并排队执行 Gateway Cloud Sync。

但是这条成功链路没有把“哪个 Gateway 已经通过回读确认、确认后的 Offset 是多少”回传给 `SiteViewController`；Gateway 模态页面关闭时，也没有触发 Site 页现有的 `.silentGatewayReconcile` 远端复查。因此 Site 页继续使用进入 Gateway 页面前缓存的 `latestTimeZoneRemoteSnapshot`，其中该 Gateway 仍然是旧 Offset，最终表现为：

- `Review sync` 继续显示；
- Gateway 名称继续显示黄色；
- 再次进入 Gateway 页时，直接读取真实 Gateway 后确认已经一致，所以不再弹出同步提示；
- 下拉刷新重新请求 `/siteInfo` 后，Site 页拿到新 Gateway Offset，组件才消失。

这与当前实测现象完全吻合。

## 当前数据与状态链路

### 1. Site 页的 Review 状态来源

`SiteViewController.performSiteLoad` 请求 `.siteInfo(siteId:)`，解析得到 `SiteEntryTimeZoneRemoteSnapshot`，保存到 `latestTimeZoneRemoteSnapshot`，再调用 `applyTimeZoneReviewState`。

`Review sync` 和 Gateway 黄色名称最终都依赖相同的 pending Gateway 集合，主要依据为：

1. 最近一次 Site 远端快照中的 `gateways[].timezoneOffset`；
2. 本地仍处于 Cloud Dirty 状态的 Gateway 时间覆盖；
3. 当前页面内存中的 `confirmedGatewayOffsetMinutesByID`。

`setTimeZoneReviewState` 已经会刷新两个 Collection View、重新计算 Header/Empty View，因此只要状态源发生变化，UI 可以正确隐藏和恢复普通颜色。

### 2. Gateway 页的成功边界

`GatewayDetailClockCoordinator.synchronize` 的成功不是只收到 `TimeSet` ACK，而是最终 `TimeGet` 回读通过以下验证后才成立：

- 回读 Offset 等于目标 Site Offset；
- 回读时间误差在允许范围内；
- Node 的时间与时区成功保存到本地。

随后 `markGatewayDirtyAndSync` 只负责修改 Gateway Cloud Generation 并排队 `.syncGateway`。`GatewayViewController` 收到成功结果后更新本页状态并显示 `gateway_clock_synced` Toast，但没有向来源 Site 页面发送任何完成结果。

### 3. 返回 Site 页时当前做了什么

Site 页 `viewWillAppear` 当前只执行：

1. `setupData()`；
2. `refreshCurrentGatewayTimeZoneReviewProjection()`；
3. `retryDirtyGatewayCloudUploads()`。

其中第 2 步只是用旧的 `latestTimeZoneRemoteSnapshot` 重新投影，并没有请求服务器。Gateway 页面又是通过模态 `NavigationViewController` 展示；在部分 iPad/Sheet 展示形态下，底层 Site 页面可能一直处于可见状态，不能把 `viewWillAppear` 当成可靠的“Gateway 页面已返回”事件。

### 4. 为什么本地 Node 已更新仍可能继续显示黄色

现有 `SiteGatewayCloudTimeZoneLocalContextBuilder` 只有在 `gateway.needUploadCloud == true` 时，才把本地 Node 的目标 Offset 作为 Dirty Override。

因此存在明确时序窗口：

1. Gateway 最终回读成功，本地 Node 已是 Site Offset；
2. Gateway Cloud Sync 很快成功，`lastUploadCloudTimestamp` 追上 `lastUpdate`，`needUploadCloud` 变为 `false`；
3. Site 页仍持有同步前的远端快照；
4. 返回时重新投影不再采用 Dirty Override，只能回退到旧远端 Offset；
5. `Review sync` 和黄色名称继续保留。

这也说明只在 Site 返回时调用一次现有 `refreshCurrentGatewayTimeZoneReviewProjection()` 不足以稳定修复问题。

### 5. 为什么下拉刷新有效

两个下拉刷新控件都调用 `loadSiteRequest()`，它会重新请求 `/siteInfo`。成功后会：

- 更新 `latestTimeZoneRemoteSnapshot`；
- 重新计算 Gateway pending 状态；
- 调用 `setTimeZoneReviewState` 刷新 Header 和 Gateway 名称。

所以“下拉刷新后正常”直接证明缺失的是返回后的数据协调/刷新触发，而不是 UI 刷新能力。

## 根因分层

### 主根因：Gateway 成功结果没有跨页面传递

Gateway 页已经拿到最强的设备侧证据——最终 `TimeGet` 回读确认；但这个结果只更新 Gateway 页自己的 `gatewayClockState`，Site 页的 `confirmedGatewayOffsetMinutesByID` 没有收到该 Gateway 的 ID 和目标 Offset。

### 主根因：Gateway 页面关闭没有触发静默 Site 复查

工程已经有 `.silentGatewayReconcile`，它不会展示 HUD，失败时也不会打扰用户，但当前只用于 Edit Site/Sync Gateways 等既有流程，没有接到单个 Gateway 页面返回链路。

### 次要根因：本地覆盖与远端快照之间存在竞态窗口

本地 Dirty Override 依赖 `needUploadCloud`。Cloud Sync 成功会让这个覆盖失效，但 Site 的旧远端快照不一定同时更新，导致“本地正确、云上传已结束、Site UI 仍按旧快照显示”的短暂或持续不一致。

### 生命周期风险：不能只依赖 `viewWillAppear`

Gateway 页面是模态展示，尤其 iPad Sheet 场景下，Site 的 appearance 回调不一定形成完整的 disappear/appear 周期。需要明确的 Gateway 页面会话关闭事件，同时覆盖左上角关闭和系统交互式下拉关闭。

## 推荐开发方案

### 1. 为单个 Gateway 页增加聚焦的时区同步结果回调

在共享的 `GatewayViewController` 增加一个仅用于“最终回读验证成功”的结果回调，结果至少包含：

- 规范化前的 Gateway ID/MAC；
- 最终确认的 Offset Minutes。

触发点必须放在 `GatewayDetailClockCoordinator.synchronize` 成功完成、Node 本地保存成功之后。以下情况不得回调成功：

- `TimeSet` 失败；
- 最终 `TimeGet` 失败；
- Offset 或时间误差校验失败；
- 本地持久化失败。

Wi-Fi Gateway 继承同一个 `GatewayViewController`，因此 Wi-Fi 与 4G Gateway 共用该行为，不增加类型特判。

### 2. Site 页接收设备侧确认并复用现有 confirmed precedence

`SiteViewController` 创建 Gateway 页面时注入成功回调。收到成功结果后：

1. 校验回调 Gateway 属于当前 Site 和当前权限范围；
2. 规范化 Gateway ID；
3. 写入 `confirmedGatewayOffsetMinutesByID[id] = offsetMinutes`；
4. 不伪造或直接修改 `latestTimeZoneRemoteSnapshot`。

现有 `effectiveGatewayOffsetOverrides` 已经定义了“confirmed 优先于 dirty、dirty 优先于 remote”的顺序，可以直接复用。这样 Gateway 页返回时，即使服务器读模型暂时仍是旧值，Site 也能依据刚刚完成的真实设备回读立即移除该 Gateway 的 pending 状态，避免黄色状态闪回。

### 3. 增加明确且幂等的 Gateway 页面返回协调

为每次 Site -> Gateway 模态展示建立一个轻量 Session/Token，并用统一的返回处理方法收口以下路径：

- Gateway 页左上角关闭；
- Gateway 页内部完成后关闭；
- iOS Sheet 交互式下拉关闭。

建议由 Gateway 关闭回调覆盖显式关闭，并由 `UIAdaptivePresentationControllerDelegate` 补齐交互式关闭；统一处理方法使用 Session/Token 保证每次展示只执行一次，避免同一次关闭触发两次请求。

返回处理顺序建议为：

1. 重新读取本地 Gateway 列表；
2. 使用 confirmed/dirty/remote 优先级立即重新投影 `Review sync` 和黄色名称；
3. 若 Site 已上传且当前有网络，调用 `performSiteLoad(presentation: .silentGatewayReconcile)`；
4. 保留现有 Dirty Gateway Cloud 重试逻辑。

该流程不展示 HUD、不弹成功/失败提示；静默请求失败时维持当前可信状态，等待后续进入 Site、网络恢复或手动刷新再次收敛。

### 4. 继续使用现有远端确认清理机制

静默 `/siteInfo` 返回后，继续调用现有 `reconcileConfirmedGatewayOffsets(with:)`：

- 服务器 Gateway Offset 已等于确认值：移除对应 confirmed override，后续完全依赖远端快照；
- 服务器仍返回旧值：保留 confirmed override，避免 UI 回退；
- Cloud Sync 失败且 Gateway 仍 Dirty：本地 Dirty Override 继续参与判断和重试。

不应在发起静默请求时提前清除 confirmed 值，也不应因为一次旧快照响应就重新显示黄色。

### 5. 保持 Review 状态的统一数据源

不在 Gateway 页面直接操作 Site Header、Gateway Cell 颜色或 `timeZoneReviewState`。所有显示变化仍通过：

`confirmed/dirty/remote -> SiteEntryTimeZoneSyncPolicy.reviewState -> setTimeZoneReviewState`

这样可以确保：

- 同步一个 Gateway 后，计数正确减一；
- 仍有其他 Gateway 不一致时，`Review sync` 保留；
- 所有有权限的 Gateway 都一致时，`Review sync` 隐藏；
- Gateway 名称颜色与 Review pending 集合一致。

## 不推荐的修复方式

### 仅在 `viewWillAppear` 调用 `loadSiteRequest`

这不能可靠覆盖 iPad Sheet 返回，并且会走交互式 HUD/Entry Sync 展示语义；同时仍存在 Gateway Cloud 更新与 `/siteInfo` 返回之间的竞态。

### Gateway 同步成功后直接把 Site Review 强制设为 hidden

一个 Site 可能有多个待同步 Gateway。强制隐藏会误伤其他 Gateway，也会绕过 Owner/Editor Space 权限范围和统一 pending 计算。

### 直接修改缓存的远端 Snapshot

远端 Snapshot 应继续表达服务器返回值。设备回读确认应进入已有 confirmed override 层，等服务器确认后再自然清理，不能混淆设备事实与服务器事实。

### 只监听 Gateway Cloud Sync 成功

Cloud API 成功不等于 Site 当前持有的 `/siteInfo` 快照已经更新，也不能替代设备最终 `TimeGet` 回读。设备确认与服务器复查需要保留为两个独立边界。

## 测试方案

### 纯逻辑/契约测试

1. Gateway 同步只有在最终回读和本地持久化成功后才发布 confirmed 结果；
2. 同步失败不发布 confirmed 结果；
3. Site 接收单个 Gateway confirmed 后，只移除该 Gateway 的 pending；
4. 多 Gateway 场景下，剩余 Gateway 仍保持 Review 和黄色名称；
5. 最后一个 Gateway confirmed 后，Review 隐藏；
6. 服务器旧快照返回时 confirmed 不被清除，UI 不闪回；
7. 服务器新快照确认后清除 confirmed，UI 仍保持隐藏；
8. 每次 Gateway 展示 Session 的返回协调最多触发一次；
9. 显式关闭和交互式下拉关闭都触发静默复查；
10. 返回复查使用 `.silentGatewayReconcile`，不进入 Entry Sync Overlay/HUD；
11. Wi-Fi 与 4G Gateway 都通过共享基类回传结果。

建议更新：

- `GatewayDetailClockCoreTests` / `GatewayDetailClockRuntimeContractTests`；
- `SiteTimeZoneReviewSyncContractTests`；
- 如需要隔离生命周期幂等逻辑，新增一个小型 Return Session Reducer 的纯逻辑测试。

### 自动化回归

- 运行 `scripts/check_gateway_information_time.sh`；
- 运行 Site Time Zone Review/Entry Sync/Edit Sync 相关聚焦测试；
- 运行本地化 lint（预计本次无需改文案）；
- 运行 `git diff --check`；
- 对 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 执行 generic iPhoneOS Debug、关闭签名构建，不使用 Simulator。

### 真机验收

1. 单 Gateway 不一致，`SYNC NOW` 成功后返回 Site：无 HUD，名称恢复普通颜色，Review 隐藏；
2. 两个 Gateway 不一致，只同步一个：返回后计数减一，只保留未同步 Gateway 的黄色状态；
3. 最后一个 Gateway 同步成功：返回后 Review 隐藏；
4. Gateway 同步失败：返回后 Review 和黄色名称保留；
5. Gateway 设备同步成功、Cloud 更新较慢：返回后 UI 不闪回，服务器确认后内存 override 自动清理；
6. 无网络返回：按本地 confirmed 结果更新 UI，不展示网络错误；网络恢复后自动重试 Cloud 并收敛远端；
7. Wi-Fi/4G Gateway 各验证一次；
8. iPhone 全屏关闭和 iPad Sheet 下拉关闭均验证一次；
9. 再次进入已同步 Gateway：连接成功后不再弹 `Gateway time zone needs sync`。

自动化与 generic iPhoneOS 构建不能证明真实 BLE/Mesh `TimeSet`、最终 `TimeGet`、服务器 Gateway Register 回读、iPad Sheet 生命周期或真机视觉结果，仍需上述真实 Gateway 验收。

## 预计改动范围

主要修改：

- `SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift`
- `SunSmart/Main/Site/Controller/SiteViewController.swift`
- `Tests/Device/GatewayDetailClockRuntimeContractTests.swift`
- `Tests/Site/SiteTimeZoneReviewSyncContractTests.swift`

按测试可维护性决定是否新增：

- 一个只描述 Gateway 页面返回幂等状态的小型 Model/Test 文件；

预计不需要修改：

- `NordicSigMeshSDK`；
- 中英文国际化文案；
- 图片资源；
- target 配置与依赖；
- Gateway 的 TimeSet/TimeGet 协议实现；
- Site Entry、Edit Site、Sync Gateways 的既有业务语义。

## 待确认

建议按以下口径实施：

1. Wi-Fi 与 4G Gateway 都覆盖；
2. 只有最终 `TimeGet` 回读与本地保存成功，才把 Gateway 记为 confirmed；
3. 返回 Site 后先依据 confirmed 结果立即更新，再静默请求 `/siteInfo`；
4. 服务器旧快照不能覆盖刚完成的设备确认，等远端真正一致后再清除 confirmed；
5. 无论本次是否执行过 `SYNC NOW`，从 Gateway 页面返回都静默复查一次；
6. 显式关闭与 iPad Sheet 交互式关闭都覆盖；
7. 不新增用户文案，不改变现有 Gateway 同步提示与 Toast 语义。
