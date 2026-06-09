# Space Editor 心跳停止修复方案和计划

## 目标

当用户从 Site - Space 离开并回到 Sites 页面时，主动停止本机对该 Space 的在线/编辑占用心跳，避免手机 A 已不在 Space 内仍被服务端判定为 active Owner/Editor，从而干扰手机 B 以 Editor 权限进入同一个 Space。

## 当前事实

已确认与“正在编辑 Space”相关的客户端机制集中在 `SpaceViewController`：

- `SpaceViewController` 持有 `heartbeatTimer`，每 30 秒请求 `/sitespace/user/hb`，并在启动时立即 fire。
- Owner/Editor 进入 Space 时会请求 `/sitespace/get/activeuser`，如果发现其他 Owner/Editor active，会弹出“是否以 Visitor 身份进入”的提示。
- `viewWillDisappear` 目前只隐藏引导视图，不停止心跳。
- `stopHeartbeatTimer()` 当前主要在 `deinit` 和权限失效处理里触发。
- Mesh 内还有 `userAskTimer` 和 `externalVendorMessageDelegate` 做本地 Mesh 权限探测，虽然它不直接调用服务端 active user，但也属于 Space 编辑占用判断链路，应在离开 Space 时一起收敛。

全局搜索确认，服务端 `/sitespace/user/hb` 只有 `SpaceViewController` 通过 `.heartbeat(...)` 调用。其他 `LCWeakTimer` 用途是 RSSI 排序、扫描、Gateway 信号刷新、固件状态查询等，不属于本次“干扰 Editor 进入 Space”的心跳范围，不应纳入停止逻辑。

## 修复原则

1. 不在任意 `viewWillDisappear` 直接停心跳，避免进入 Space 内部子页面、弹窗、同步流程时错误丢失在线状态。
2. 只在“离开 Space 流程”时停止占用，例如 Space VC 被 pop 出导航栈、强制返回 Site、继续返回 Sites，或导航栈里已不存在该 Space VC。
3. 停止范围聚焦在 Space 编辑占用链路：服务端 heartbeat、Mesh 权限探测 timer、Mesh 权限探测 delegate。
4. 不改变 B 的成员权限模型，不把 Editor 降为 Visitor；只释放 A 的 active presence。
5. 如果后端没有 release/leave API，客户端只能停止后续心跳；B 是否立即可进入仍受服务端 active user 过期时间影响。若后端能提供释放接口，应作为增强项接入。

## 方案比较

### 方案 A：在 `SpaceViewController` 被移出导航栈时停止占用

做法：

- 在 `SpaceViewController` 增加统一的“停止 Space presence tracking”私有方法。
- 方法内部停止 `heartbeatTimer`、停止 `userAskTimer`，并在当前 delegate 仍指向该 VC 时清空 `MeshLibManager.manager.externalVendorMessageDelegate`。
- 在 `viewDidDisappear` 中判断当前 VC 已不在导航栈，或正在从父控制器移除，再调用该方法。
- 保留 `viewWillDisappear` 原行为，不影响 push 子页面或展示弹窗。

优点：

- 生命周期边界清晰。
- 不依赖 Sites 页面主动扫描。
- 能覆盖从 Space 返回 Site、再返回 Sites 的正常 pop 路径。
- 即使 VC 因异步引用未立即 `deinit`，只要已被移出导航栈，也会停止心跳。

风险：

- 需要谨慎判断“被移出导航栈”，避免把普通子页面切换误判为离开 Space。

### 方案 B：在 `SitesViewController.viewDidAppear` 做全局兜底清理

做法：

- 当 Sites 页面显示时，扫描导航栈中残留的 `SpaceViewController`，调用公开的停止方法。
- 或通过通知广播，让所有 Space 相关控制器停止 presence tracking。

优点：

- 与用户提出的“回到 Sites 页面”语义直接对应。
- 可作为兜底，处理异常导航路径。

风险：

- 正常导航栈通常是 `Sites -> Site -> Space`，回到 Sites 后 Space 理应已经被 pop；如果还要扫描残留 VC，本质上是在补救生命周期问题。
- 广播式停止容易扩大影响，未来如果有多窗口或模态导航，会更难判断目标 Space。

### 方案 C：所有 `viewWillDisappear` 都停止心跳

做法：

- 只要 `SpaceViewController.viewWillDisappear` 触发就停止心跳。

优点：

- 实现最简单。

风险：

- 进入 Space 内部子页面、弹窗、同步页面、设备详情页时也会停止 active presence。
- 可能导致用户仍在编辑 Space，但其他手机误以为没有 active Editor。
- 不推荐。

## 推荐方案

采用方案 A，并补一个轻量方案 B 兜底。

主逻辑放在 `SpaceViewController`：当 Space VC 被移出导航栈时立即停止服务端 heartbeat 和本地 Mesh 权限探测。这样能解决“VC 未立即 deinit 但已离开 Space”的核心问题。

兜底放在 `SitesViewController.viewDidAppear`：只做非常窄的清理，发现导航栈里异常残留的 `SpaceViewController` 才调用停止方法。这个兜底不应成为主路径，也不应清理无关定时器。

如果后端已有或能新增 active user release API，则在停止 heartbeat 的同一位置补发 release 请求。当前客户端代码未发现该 API，因此第一阶段按“停止后续心跳，等待服务端过期”落地。

## 开发计划

### Task 1：封装 Space presence 停止入口

修改文件：

- `SunSmart/Main/Space/Controller/SpaceViewController.swift`

计划：

1. 增加一个私有状态位，防止同一个 Space 多次执行停止逻辑。
2. 增加统一停止方法，职责只包含：
   - 停止 `heartbeatTimer`。
   - 停止 `userAskTimer`。
   - 如果 `MeshLibManager.manager.externalVendorMessageDelegate` 当前仍由该 VC 负责，则清空。
   - 记录调试日志，包含 siteId、spaceId、permission、停止原因。
3. `deinit` 继续调用该统一方法，避免保留两套停止逻辑。
4. 权限失效处理继续走已有 `handleSpacePermissionLoss()`，内部也复用统一停止方法。

验收：

- 停止入口可重复调用且无副作用。
- 不改变正常进入 Space 后的 heartbeat 启动逻辑。
- 不影响 `hasHandledPermissionLoss` 的一次性弹窗保护。

### Task 2：在离开 Space 流程时停止 presence

修改文件：

- `SunSmart/Main/Space/Controller/SpaceViewController.swift`

计划：

1. 在 `viewDidDisappear` 中判断当前 VC 是否已离开 Space 流程：
   - `isMovingFromParent` 为 true；或
   - `navigationController?.viewControllers` 已不包含当前 VC。
2. 满足条件时调用统一停止方法，停止原因标记为离开 Space 导航栈。
3. 不在普通 `viewWillDisappear` 中停止，避免进入 Space 子页面时误停。
4. 保留当前返回拦截逻辑：如果 `space.needUploadCloud`，仍先走 `promptlySyncSpace()`，不要因为计划修复绕过同步保护。

验收：

- 从 Space 返回 Site 时，心跳立即停止，不等待 `deinit`。
- 从 Site 再返回 Sites 后，不再有该 Space 的 heartbeat 请求。
- 从 Space push 到设备详情、组、场景、同步页面时，心跳不应被停止。

### Task 3：在 Sites 页面增加窄兜底

修改文件：

- `SunSmart/Main/Site/Controller/SitesViewController.swift`

计划：

1. 在 `viewDidAppear` 或合适的页面显示时机，检查当前导航栈是否异常保留了不可见的 `SpaceViewController`。
2. 仅对“不在当前 visibleViewController 路径中”的 Space VC 调用公开/内部可见的停止 presence 方法。
3. 不扫描或停止其他 timer，不操作设备扫描、Gateway、Firmware、Profile 等页面。
4. 如果实现需要暴露方法，优先使用 `internal` 且语义明确的方法名，不把 timer 暴露给外部直接操作。

验收：

- 用户已经回到 Sites 页面时，不存在任何旧 Space 的 `/sitespace/user/hb` 后续请求。
- 若正常导航栈没有残留 Space VC，兜底逻辑不做任何事。

### Task 4：补充日志与诊断点

修改文件：

- `SunSmart/Main/Space/Controller/SpaceViewController.swift`

计划：

1. 在启动 heartbeat、停止 presence、收到 active member 冲突、确认降级 Visitor 这几个关键点补充轻量日志。
2. 日志只用于 DEBUG 或现有调试输出路径，避免生产环境大量输出敏感数据。
3. 日志不新增 Auth 信息，不打印密码、token、完整用户隐私信息。

验收：

- 手动验证时能看到 A 离开 Space 后停止 presence 的明确日志。
- B 进入时如果仍被拦，能用日志判断是客户端仍在发心跳，还是服务端 active user 尚未过期。

### Task 5：验证

构建验证：

- 运行 iPhoneOS 构建：
  `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

手动验证：

1. 手机 A 作为 Owner 进入 Site - Space。
2. 确认 A 开始发送 `/sitespace/user/hb`。
3. 手机 A 从 Space 返回 Site，再返回 Sites。
4. 确认 A 不再继续发送该 Space 的 `/sitespace/user/hb`。
5. 手机 B 以 Editor 权限进入同一 Space。
6. 预期：如果服务端 active user 已过期，B 直接以 Editor 可编辑状态进入；如果仍提示 Visitor，则抓 `/sitespace/get/activeuser` 确认是否是服务端缓存尚未过期。

回归验证：

1. A 从 Space push 到设备详情或其他 Space 内子页面时，heartbeat 继续存在。
2. A 在 Space 内正常编辑设备、组、场景，不因页面切换丢失编辑占用。
3. 权限被清除时，已有 `handleSpacePermissionLoss()` 仍只弹一次并停止心跳。
4. 密码变更、Site 权限失效、Space 删除等现有流程不回退。

## 预期效果

修复后，手机 A 只要真正离开 Space 流程并回到 Site/Sites，就会立即停止客户端继续上报 active Owner/Editor。这样可以显著减少手机 B 被误判为“有人正在编辑”的概率。

如果停止后 B 仍短时间内被拦，原因应转移到服务端 active user 的过期窗口。届时需要后端提供明确的 release/leave active user API，客户端在统一停止入口中补发释放请求，才能做到“离开即释放、B 立即可编辑”。
