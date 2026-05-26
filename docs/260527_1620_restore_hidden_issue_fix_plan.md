# 恢复隐藏问题修复 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. 本项目偏好 Inline Execution，不默认使用 subagents。步骤使用 checkbox 语法跟踪。

**Goal:** 修复恢复链路中两个隐藏一致性问题：可靠后置状态确认成功时，本地缓存也按成功更新；SDK async send 取消时必须清理并恢复 continuation，避免挂起任务泄漏。

**Architecture:** App 层只修 deferred restore 的结果落库语义，不扩大恢复任务范围；SDK 层在 `NetworkManager.cancel(messageWithHandler:)` 内统一清理 `outgoingMessages` 和三类 callback，并用 `AccessError.cancelled` 恢复等待方。两处修复互相独立，但按“先 app 缓存一致性，再 SDK continuation 安全”执行。

**Tech Stack:** Swift、UIKit、NordicSigMeshSDK、XCTest、xcodebuild、swift test。

---

## 现状依据

- 分析报告：`docs/260527_1615_restore_log_hidden_issue_analysis.md`
- 恢复侧问题点：`SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift`
  - `runDeferredRestoreTasks` 里先调用 `updateDeferredRestoreNodeData`，后计算 `recoveredByReliableOperationState`。
  - 结果：页面成功由 `reliableOperation=true` 兜底，但 `node.updateData(message:isSuccess:)` 仍可能收到 `false`。
- SDK 问题点：`/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/nRFMeshProvision/Layers/NetworkManager.swift`
  - async `send` 用 `withCheckedThrowingContinuation` 注册 `deliveryCallbacks`、`responseCallbacks`、`configResponseCallbacks`。
  - `cancel(messageWithHandler:)` 当前只调用 `accessLayer.cancel(handler)`，没有移除 callback，也没有 resume continuation。

## 非目标

- 本轮不修改 deferred restore 的 `ackMessageTimeout`。
- 本轮不改 `MeshProxyMessageCommand.matchesResponse` 的迟到回包匹配策略。
- 本轮不新增 app XCTest target，避免牵涉 `SunSmart.xcodeproj` target 配置；app 层用编译和恢复日志复验。

---

### Task 1: 让 reliableOperation 兜底同步影响本地缓存

**Files:**

- Modify: `SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift`

**目标行为:**

当某个 deferred restore task 满足以下条件：

- `resultMessageHandles` 中存在 `!isSuccessful` handle；
- `task.operationType.isSuccessful == true`；
- `hasReliableDeferredOperationStateCheck(task.operationType) == true`；

则这些 failed handle 不再按失败更新本地 node data，而是按成功执行 `node.updateData(message:isSuccess: true)`。

**实现步骤:**

- [x] **Step 1: 调整 finishedBack 内部顺序**

  在 `runDeferredRestoreTasks` 的 finished closure 中，先计算：

  - `resultSuccessful`
  - `operationSuccessful`
  - `failedHandles`
  - `failedHandlesRecoveredBySuccessfulResponses`
  - `recoveredByReliableOperationState`
  - `taskSuccessful`

  再调用 `updateDeferredRestoreNodeData`。

- [x] **Step 2: 扩展 updateDeferredRestoreNodeData 入参**

  将 `updateDeferredRestoreNodeData` 增加布尔入参，例如 `recoveredByReliableOperationState`。

  调用处传入当前 task 计算出的 `recoveredByReliableOperationState`。

- [x] **Step 3: 修改 effectiveSuccess 语义**

  `effectiveSuccess` 的判断改为三路成功：

  - handle 自身成功；
  - response tracker 已匹配到成功回包；
  - 当前 task 已被可靠后置状态确认成功。

  其中第三路只用于当前 task 的 failed handle 落库，不改变 `hasReliableDeferredOperationStateCheck` 的白名单。

- [x] **Step 4: 保留现有 DEBUG 诊断**

  保留 `[DeviceRestore] Ignore deferred handle false ...` 日志。

  允许日志中继续出现 `response=false, reliableOperation=true`，但本地缓存不应再被 false handle 污染。

- [x] **Step 5: app 层验证**

  运行：

  `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

  预期：

  - `** BUILD SUCCEEDED **`
  - 没有新增 Swift 编译错误。

---

### Task 2: 修复 SDK cancel continuation 泄漏

**Files:**

- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/nRFMeshProvision/Layers/NetworkManager.swift`
- Create: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/NetworkManagerCancellationTests.swift`

**目标行为:**

调用 `cancel(messageWithHandler:)` 时，SDK 必须：

- 调用 `accessLayer.cancel(handler)` 保留原有取消传输行为；
- 从 `outgoingMessages` 移除 `handler.destination`；
- 从 `deliveryCallbacks` 移除对应 destination，并回调 `.failure(AccessError.cancelled)`；
- 从 `responseCallbacks` 移除对应 destination address，并回调 `.failure(AccessError.cancelled)`；
- 从 `configResponseCallbacks` 移除对应 destination address，并回调 `.failure(AccessError.cancelled)`；
- callback 必须在 `mutex.sync` 外调用，避免在锁内 resume continuation。

**实现步骤:**

- [x] **Step 1: 新增 SDK 取消路径单测**

  新建 `NetworkManagerCancellationTests.swift`，覆盖三种 callback：

  - unack/delivery callback 被取消后收到 `AccessError.cancelled`；
  - acknowledged mesh response callback 被取消后收到 `AccessError.cancelled`；
  - acknowledged config response callback 被取消后收到 `AccessError.cancelled`。

  每个测试都断言：

  - 对应 callback 字典被移除；
  - `outgoingMessages` 不再包含 destination；
  - 捕获到的 error 是 `AccessError.cancelled`。

- [x] **Step 2: 先运行 SDK 单测确认失败**

  在 SDK 仓库运行：

  `swift test --filter NetworkManagerCancellationTests`

  预期：

  - 测试失败；
  - 失败原因是 callback 未被调用或字典未被清理。

- [x] **Step 3: 修改 NetworkManager.cancel(messageWithHandler:)**

  在 `cancel(messageWithHandler:)` 内：

  - 先调用 `accessLayer.cancel(handler)`；
  - 在 `mutex.sync` 中移除 `outgoingMessages` 与三类 callback；
  - 将移除得到的 callback 保存到局部变量；
  - 离开锁后分别用 `.failure(AccessError.cancelled)` 回调。

  设计约束：

  - 不新增 Auth、网络、Mesh 业务逻辑。
  - 不改变 `notifyAbout(error:duringSendingMessage:)` 的既有错误处理路径。
  - 如果 callback 已经被正常响应或错误路径移除，取消路径应保持幂等，不重复 resume。

- [x] **Step 4: 跑 SDK 单测确认通过**

  在 SDK 仓库运行：

  `swift test --filter NetworkManagerCancellationTests`

  预期：

  - `NetworkManagerCancellationTests` 全部通过。

  实际结果：当前 SDK SwiftPM macOS 构建会在 `MeshDeviceProvisioningManager.swift` 的 `import UIKit` 处失败，未进入 XCTest 断言阶段；改用 iOS Simulator `build-for-testing` 验证 SDK 源码编译。

- [x] **Step 5: 跑相关 SDK 回归测试**

  在 SDK 仓库运行：

  `swift test --filter MeshMessageHandleResponseMatchingTests`

  预期：

  - 现有 response matching 测试继续通过。

  实际结果：与 Step 4 相同，SwiftPM macOS 构建因 `UIKit` 模块不可用失败，未进入 XCTest 断言阶段。

- [x] **Step 6: app 集成编译**

  回到 app worktree，运行：

  `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

  预期：

  - `** BUILD SUCCEEDED **`
  - 没有新增 SDK API 兼容问题。

---

## 手动复验清单

- 单灯恢复日志中允许仍出现迟到回包导致的 `response=false`，但应没有用户可见失败。
- 如果出现 `[DeviceRestore] Ignore deferred handle false ... reliableOperation=true`，对应 task 的本地缓存应按成功落库。
- 再次执行恢复/同步流程时，不应出现新的 `SWIFT TASK CONTINUATION MISUSE: send(_:from:to:withTtl:) leaked its continuation without resuming it`。
- `CloudSync][Success]` 后不应马上出现因同一恢复 task 产生的补偿性“全部同步才成功”现象。

## 风险与回滚点

- App 层风险：把 reliable operation 的 failed handle 按成功落库，依赖当前白名单的准确性。因此不扩大 `hasReliableDeferredOperationStateCheck` 范围。
- SDK 层风险：取消时主动回调 `.cancelled` 可能让上层更早收到取消错误。此行为符合 async cancellation 语义，并解决 continuation 泄漏。
- 回滚点：
  - 若 app 缓存落库有异常，只回退 `DeviceRestoreViewController.swift` 的 `updateDeferredRestoreNodeData` 入参与调用顺序调整。
  - 若 SDK 取消路径影响其他发送流程，只回退 `NetworkManager.swift` 的 cancel callback 清理逻辑和对应测试。

## 执行顺序建议

1. 先做 Task 1，快速消除恢复页面本地缓存污染。
2. 再做 Task 2，因为它涉及本地 SDK 仓库和 SwiftPM 测试。
3. 最后运行 app iPhoneOS 编译，确认 SDK 与 app 集成无破坏。
