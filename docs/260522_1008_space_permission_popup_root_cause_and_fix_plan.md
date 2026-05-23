# Space Permission Popup Root Cause and Fix Plan

## 问题结论

异常不是单纯的“权限被清除提示”，而是 `SpaceViewController` 的心跳生命周期没有和页面可见性、Space 权限失效状态绑定。

删除一个 Site/Space 后，旧 Space 的服务端授权已经不存在，但旧 `SpaceViewController` 仍可能继续发送心跳。心跳返回 `4009 noSpacePermission` 或 `4010 userUnauthorized` 后，代码每次都会展示 `the_space_cleared_visitor_message`。由于 `SRAlertView.show()` 会先关闭当前已有弹窗，再展示新的弹窗，所以旧 Space 的心跳可以打断当前切换到另一个 Site 后的界面弹窗，造成“明明在另一个 Site，却一直提示 Visitor permission cleared”的现象。

## 触发链路

1. 用户进入某个已上传云端的 Space。
2. `SpaceViewController.viewDidLoad()` 启动心跳：
   - Visitor 权限直接启动。
   - Owner/Editor 在 `checkTheSpaceMembersRequest()` 成功或失败后启动。
3. 心跳通过 `heartbeat(siteId:spaceId:permission:)` 每 30 秒请求一次，并且启动后立即 `fire()`。
4. 用户删除 Site/Space，或服务端清除了当前用户在该 Space 的权限。
5. 旧 Space 的下一次心跳返回：
   - `4009 noSpacePermission`
   - `4010 userUnauthorized`
6. `heartbeatRequest()` 将 `space.state` 设置为 `.waitDeleted` 并弹出 `the_space_cleared_visitor_message`。
7. 该分支没有停止心跳，也没有判断当前是否已有权限失效弹窗，因此后续心跳会继续重复弹窗。

## 根因

### 根因 1：无权限分支没有停止心跳

`heartbeatRequest()` 在收到 `noSpacePermission/userUnauthorized` 后只更新了本地 Space 状态并弹窗，没有调用 `stopHeartbeatTimer()`。这导致已经失效的 Space 继续向服务端发心跳，形成重复触发。

### 根因 2：心跳只在 `deinit` 停止

`SpaceViewController` 只在 `deinit` 停止心跳。只要控制器还未释放，哪怕用户已经切到 Site 列表或另一个 Site，旧心跳仍可能运行。`viewWillDisappear` 当前只隐藏引导视图，没有处理心跳生命周期。

### 根因 3：权限失效弹窗没有去重

密码变更分支已经有 `SRAlertView.getCurrentAlertView()` 防重逻辑，但无权限分支没有类似保护。`SRAlertView.show()` 会关闭当前弹窗，旧 Space 的心跳提示会覆盖当前界面的其他弹窗或重复出现。

### 根因 4：Site 数据刷新存在旧 Space 状态残留路径

`SiteData.update(siteJsonData:)` 能把“服务器已不存在但本地仍存在”的共享 Space 标记为 `.waitDeleted`，但这只处理 Site 数据刷新后的列表状态；它不能阻止旧 `SpaceViewController` 继续心跳。当前问题的主因仍在 Space 页面心跳处理。

## 修复原则

- 权限失效是终态事件：收到 `4009/4010` 后，当前 Space 的心跳必须立即停止。
- 弹窗只提示一次：同一个 Space 的权限失效不应重复覆盖 UI。
- 导航行为保持原有语义：确认后仍回到对应 `SiteViewController`，不要扩大到强制回 Sites 列表，除非 Site 本身也失效。
- 不改变正常 Visitor/Editor 心跳逻辑，只收敛失效后的生命周期。

## 修复计划

### Task 1：收敛 Space 心跳失效处理

修改文件：

- `SunSmart/Main/Space/Controller/SpaceViewController.swift`

计划：

1. 在 `SpaceViewController` 增加一个私有状态位，例如 `hasHandledPermissionLoss`，表示当前 Space 已处理权限失效。
2. 在 `heartbeatRequest()` 收到 `noSpacePermission` 或 `userUnauthorized` 时：
   - 先判断 `hasHandledPermissionLoss`，如果已经处理过则直接返回。
   - 立即设置 `hasHandledPermissionLoss = true`。
   - 立即调用 `stopHeartbeatTimer()`。
   - 再设置 `space.state = .waitDeleted` 并保存。
   - 再展示权限清除弹窗。
3. 弹窗展示前检查当前是否已有 `SRAlertView`：
   - 如果已有弹窗，可以选择不重复展示，或只在当前 `SpaceViewController` 仍可见时展示。
   - 推荐策略：权限失效是强制退出事件，可以展示一次，但不能重复覆盖。

验收：

- 同一个失效 Space 最多弹一次 `the_space_cleared_visitor_message`。
- 弹窗出现后不会继续发该 Space 的心跳。

### Task 2：调整页面不可见时的心跳策略

修改文件：

- `SunSmart/Main/Space/Controller/SpaceViewController.swift`

计划：

1. 梳理心跳是否必须在 Space 页面不可见时保持。
2. 如果业务不要求后台页面继续占用编辑/访客在线状态，则在 `viewWillDisappear` 停止心跳，在 `viewWillAppear` 或 `viewDidAppear` 按现有条件恢复。
3. 如果业务要求进入子页面时仍保持心跳，则不要简单在 `viewWillDisappear` 停止；改为只在导航栈顶部已经不是当前 Space 流程、或当前 Space 已 `.waitDeleted` 时停止。

推荐先做保守方案：

- 权限失效时停止心跳。
- `viewWillDisappear` 不立即改动，避免影响子页面、设备页、组页中的在线占用逻辑。

验收：

- 删除/解绑 Space 后不会由旧 Space 继续弹窗。
- 进入 Space 子页面时原有在线权限逻辑不回退。

### Task 3：同步 Site 列表中的失效 Space UI

修改文件：

- `SunSmart/Main/Site/Controller/SiteViewController.swift`
- `SunSmart/Common/Data/ImportData.swift`

计划：

1. 保留 `SiteData.update(siteJsonData:)` 中对服务器缺失 Space 的 `.waitDeleted` 标记。
2. 检查 `SiteViewController.loadSpaceReqeust(space:)` 的 `noSpacePermission/userUnauthorized` 分支：
   - 当前已设置 `.waitDeleted`、保存、刷新 UI，这是正确的。
   - 可以补充网关关联状态刷新，避免 Gateway Space 权限显示滞后。
3. 不在 Site 列表层弹完整 `the_space_cleared_visitor_message`，保持列表层使用现有 `space_permission_cleared_message`，避免语义混乱。

验收：

- 切回 Site 列表后，失效 Space 显示为待清理状态。
- 点击失效 Space 时走 `showPermissionClearedMessage(space:)` 的回收/删除流程。

### Task 4：验证

手动验证场景：

1. 账号 A 分享 Space 给账号 B 为 Visitor。
2. 账号 B 进入该 Space，确认心跳已启动。
3. 账号 A 清除账号 B 的 Visitor 权限，或删除该 Space。
4. 账号 B 等待下一次心跳。
5. 预期：只弹一次 `the_space_cleared_visitor_message`，确认后返回 Site 页面。
6. 账号 B 切换到另一个 Site。
7. 预期：旧 Space 不再重复弹窗。

回归场景：

1. Visitor 正常进入 Space，心跳成功，不应弹窗。
2. Space 密码变更仍走 `the_space_password_change_message`。
3. Site 权限失效仍走 `noSitePermission` 原有流程。
4. Owner/Editor 进入 Space 后仍能维持原有 active member 行为。

构建验证：

运行：

`xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

## 实施记录

已按保守方案实施 Task 1：

- 在 `SpaceViewController` 增加 `hasHandledPermissionLoss`，用于防止同一个失效 Space 重复处理和重复弹窗。
- `startHeartbeatTimer()` 与 `heartbeatRequest()` 在 Space 非 `.normal` 或已处理权限失效时直接停止/拒绝继续心跳。
- `heartbeatRequest()` 收到 `noSpacePermission` 或 `userUnauthorized` 后改由 `handleSpacePermissionLoss()` 统一处理：
  - 立即停止心跳。
  - 标记 Space 为 `.waitDeleted` 并保存。
  - 发送 `spacesRefreshChangeNotificationName` 刷新 Space 列表状态。
  - 只有当前 `SpaceViewController` 仍在 window 中时才展示权限清除弹窗，避免隐藏旧 Space 页面把弹窗打到当前 Site。
- `noSitePermission` 分支也立即停止心跳，避免 Site 权限失效后继续重复请求。

未实施 Task 2 中的 `viewWillDisappear` 停心跳方案，因为该方案可能影响进入 Space 子页面后的 active member/在线占用语义。当前修复只收敛权限失效后的终态行为。

验证结果：

- `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build` 通过，结果为 `BUILD SUCCEEDED`。
- 当前 workspace 未发现可用 XCTest target，因此未补充自动化回归测试；后续如果新增测试 target，应覆盖 Space 心跳 `4009/4010` 后只处理一次且停止 timer 的行为。
