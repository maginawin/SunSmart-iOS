# App 控制设备后卡死调查与修复计划

## 结论

本次日志指向 SDK 的固件分发状态探测流程，而不是设备开关控制本身。

高概率根因是 `MeshFirmwareDistributionManager.currentActiveFirmwareDistributionNodeGet()` 在 async 方法中使用 `DispatchSemaphore.wait(timeout:)` 同步等待 Mesh 广播回包。该方法由 `DevicesViewController.getMeshDistribution()` 在 Mesh 首次连接后触发，调用链来自主线程 UI 观察回调，因此等待期间有机会阻塞主线程。日志中的 `SunricherVendorGet(function: .currentActiveDistribution)` 没有收到有效 `SunricherVendorStatus.currentActiveDistributionGet`，所以经常会走 3 秒超时路径；Xcode 报错位置落在 `MeshFirmwareDistributionManager.swift:965`，正好是 `withCheckedContinuation` 结束处。

用户点击设备开关时的 `GenericOnOffSet` 和 `GenericOnOffStatus` 是正常控制链路。日志最后的 `[EFC Scene] proxy filter already contains desired addresses: []` 只是收到控制回包后进入设备页消息分发，未看到它直接导致卡死。

## 证据

- `SunSmart/Main/Device/Controller/DevicesViewController.swift:207` 监听 `MeshLibManager.manager.isMeshNetworkConnected`。
- `SunSmart/Main/Device/Controller/DevicesViewController.swift:228` 首次连接后调用 `getMeshDistribution()`。
- `SunSmart/Main/Device/Controller/DevicesViewController.swift:522` 创建 `Task`，随后 `await MeshFirmwareDistributionManager.shared.currentActiveFirmwareDistributionNodeGet()`。
- `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Manager/MeshFirmwareDistributionManager.swift:944` 定义 `currentActiveFirmwareDistributionNodeGet()`。
- 同文件 `:951` 创建 `DispatchSemaphore(value: 0)`。
- 同文件 `:952` 覆盖全局 `MeshLibManager.manager.messageReceiveCallback`。
- 同文件 `:960` 广播 `SunricherVendorGet(function: .currentActiveDistribution)` 到 `FFFF`。
- 同文件 `:961` 使用 `semphore.wait(timeout: .now() + self.sendMessageTimeout)` 同步等待。
- 同文件 `:963` 清空 `messageReceiveCallback`。
- 同文件 `:965` 是 continuation 作用域结束位置，和用户提供的错误位置一致。

日志中对应片段：

- `send message: SunricherVendorGet(function: NordicSigMeshSDK.VendorFunctionGet.currentActiveDistribution) address: 65535`
- 本机收到自己的广播后显示 `UnknownMessage(opCode: 0xF1780A, parameters: 3904) source:1 destination:0xFFFF`
- 后续从空中收到同 seq 的本机广播回环并被丢弃：`Discarding packet (seqAuth: 24779, expected > 24779)`
- 没有出现 `SunricherVendorStatus` 且 `status.code == .currentActiveDistributionGet` 的有效回包。

## 风险点

1. `DispatchSemaphore.wait` 出现在 async API 内，如果调用发生在 MainActor，会阻塞 UI。
2. `messageReceiveCallback` 是单例全局闭包，`currentActiveFirmwareDistributionNodeGet()` 和 `lastFirmwareDistributionNodeGet()` 会互相覆盖，也可能短暂影响其他依赖该 callback 的流程。
3. 查询当前固件分发者属于非交互辅助功能，但现在会在进入设备页后立即执行，和设备状态刷新、心跳刷新、控制消息共用 Mesh 消息队列。
4. `getDistributionState(distributionNode:firmwareSize:)` 标注了 `@MainActor`，其中在 `.transferSuccess` 分支又调用 `currentActiveFirmwareDistributionNodeGet()`，如果进入该分支，主线程阻塞风险更直接。

## 修复目标

- 彻底移除固件分发探测路径中的同步 semaphore 等待。
- 保留现有功能：进入设备页后仍能发现当前正在分发的节点，OTA 页面仍能读取最后一个排队分发者。
- 避免控制设备、心跳刷新、设备状态刷新被固件分发探测拖住。
- 尽量不改业务 UI，不调整 EFC proxy filter 逻辑，不改动 Auth 信息。

## 修复方案

### Task 1：把当前分发者查询改为真正异步超时

**修改文件**

- `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Manager/MeshFirmwareDistributionManager.swift`

**步骤**

1. 新增一个私有异步等待工具，用 `withCheckedContinuation` 加 `Task.sleep` 或 `withTaskGroup` 实现超时，不使用 `DispatchSemaphore.wait`。
2. 工具内部维护 `didResume` 状态，确保 Mesh 回包和超时只会 resume 一次。
3. callback 命中条件保持现有逻辑：消息必须是 `SunricherVendorStatus`，`status.isSuccessful == true`，`status.code == .currentActiveDistributionGet`，来源节点存在且不是本地 provisioner。
4. 发送 `SunricherVendorGet(function: .currentActiveDistribution)` 后立即返回挂起态，不阻塞当前线程。
5. 回包命中或超时后清理 `MeshLibManager.manager.messageReceiveCallback`。

**验收**

- 方法在无设备响应时约 3 秒后返回 `nil`，但主线程可继续滚动和点击。
- 控制设备时 `GenericOnOffSet` 仍能发送，`GenericOnOffStatus` 仍能更新设备状态。

### Task 2：同步修复最后排队分发者查询

**修改文件**

- `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Manager/MeshFirmwareDistributionManager.swift`

**步骤**

1. 对 `lastFirmwareDistributionNodeGet()` 做同样改造，移除 `DispatchSemaphore.wait`。
2. 命中条件保持现有逻辑：`status.code == .lastDistributionQueueGet`，来源节点不是本地 provisioner，且真实节点中存在 `distributionQueueNextAddress == node.primaryUnicastAddress`。
3. 移除末尾额外 `DispatchQueue.main.async` resume，避免 continuation 的恢复线程被人为切回主线程。

**验收**

- OTA 页面读取排队分发者时不会阻塞 UI。
- 与 Task 1 共用的等待工具能区分不同 `VendorDFUCode`。

### Task 3：降低进入设备页时的非必要探测影响

**修改文件**

- `SunSmart/Main/Device/Controller/DevicesViewController.swift`

**步骤**

1. 保留首次连接后检查分发状态，但确保 UI 更新只在需要时切回主线程。
2. `getMeshDistribution()` 内部对 `self` 使用弱引用，避免页面已退出时仍继续操作 HUD 或弹窗。
3. 对访客或没有分发记录的场景快速返回，不显示 HUD。

**验收**

- 进入设备页后没有分发记录时，不出现无意义 loading。
- 设备列表页和灯具页可以在分发探测超时期间正常操作。

### Task 4：补充最小诊断日志

**修改文件**

- `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Manager/MeshFirmwareDistributionManager.swift`

**步骤**

1. 在 DEBUG 下记录当前分发者查询开始、命中、超时、清理 callback。
2. 日志包含 function 类型和超时时长，不打印敏感认证信息。
3. 不在 release 增加大量日志。

**验收**

- 复现时能区分“无分发者正常超时”和“有分发者但没有收到状态回包”。
- 日志不会刷屏影响控制消息。

### Task 5：验证

**命令验证**

1. `swift test`，工作目录：`/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk`
2. `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
3. 如改动影响多个品牌 target，再分别构建 `Archipelago`、`SylSmart`、`SLG Sync Plus`。

**手动验证**

1. 冷启动 App，进入同一 Space。
2. 等待 Mesh 连接完成，观察 `currentActiveDistribution` 查询超时期间 UI 是否可滑动。
3. 进入 `DeviceLightsViewController`，点击地址 `0x0143` 或同类灯具开关。
4. 确认收到 `GenericOnOffStatus` 后 App 不冻结，设备 cell 状态延迟更新正常。
5. 在无 OTA 分发者和存在 OTA 分发者两种网络里分别验证。

## 当前注意事项

- 本地 SDK 仓库已有未提交改动：`Sources/NordicSigMeshSDK/MeshLib/Manager/MeshFirmwareDistributionManager.swift`。当前 diff 看起来主要是格式变化，实施修复前需要先确认这些改动是否要保留。
- 当前 App 工程已经通过 `XCLocalSwiftPackageReference` 指向 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk`，后续修复 SDK 后可直接构建 App 验证。
