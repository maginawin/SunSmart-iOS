# EFC Default Config 当前状态分析

## 背景

用户之前实现过：添加 EFC 设备后，即使没有配置 `Associate with group(s)`，也要在添加成功后立即通过 `0x4D/0x07` 下发默认 action config，使 EFC 的应急状态变化能被 App 监听和展示。

本次目标是确认当前代码里这个功能是否仍存在；若不存在，再规划恢复方案。

## 当前结论

当前功能没有被整块回退。

证据：

- 当前分支存在提交 `aa037259 fix: no associate groups need to update EFC status`。
- `DeviceAddClassicModeController` 和 `DeviceAddProfessionalModeController` 都保留了 EFC 默认配置消息缓存、失败记录和收尾逻辑。
- Classic / Professional 的 `appendMessagesBack` 在新增节点是 EFC 时，会调用 `appendEmergencyFireControllerDefaultConfigurationMessages(...)`。
- `DeviceEmerFireData.getControllerDefaultConfigurationMessageHandles(...)` 仍会通过 `makeControllerSyncTasks(..., changedFrom: nil)` 生成完整 controller 默认配置消息。
- `makeControllerSyncTasks(...)` 当前会生成 Scene publication、Enable、Trigger Resend、Restore Resend、三条 state action config，以及 Restore Delay。

也就是说，添加 EFC 后无 associated group 的默认 controller 配置下发链路仍在。

## 发现的问题

### 1. `0x4D/07 app_idx` 修复不在当前 checkout

历史记录里曾有一轮修复：EFC `0x4D/07` action config 的 `app_idx` 应固定为 Space App Index `0`，不能使用 App 当前的 `currentApplicationKey.index`。

但当前 `DeviceEmerFireData+Sync.swift` 仍然在生成每个 state 的 action config 时传入 `MeshNetworkManager.instance.currentApplicationKey.index`。

当前 `scripts/check_efc_controller_flows.sh` 也没有保留这条防回退 contract。

这意味着：默认配置确实会下发，但 payload 内的 `app_idx` 可能不是 EFC 设备期望的 Space App Index `0`。如果固件按 `app_idx` 决定状态事件发布使用的 AppKey，这会造成“配置发了，但 App 仍监听不到或状态不同步”的现象。

### 2. Edit 页面 Link 后不进入 Sync 页面是当前设计，不等于默认配置功能消失

`LinkedEmerFireEditVC.openSyncAfterLinkedDeviceIfNeeded()` 仍然只在 `configuration.hasSyncIntent` 为 true 时打开同步页；无 associated group 时该值为 false。

这看起来像“没有触发同步”，但当前实现选择的是在 Add Device 的 `appendMessagesBack` 静默追加默认配置，而不是跳转 Sync 页面。

因此不能仅凭 Link 后没打开 Sync 页面判断功能被回退。

### 3. Add Device 成功状态没有合并 EFC 默认配置失败

Classic / Professional 都会记录 `failedEmergencyFireDefaultConfigurationNodeAddresses`，并在 `finishEmergencyFireDefaultConfiguration(for:)` 里根据失败情况更新 EFC `isSynced`。

但 Add Device 行状态目前只看 group sync 是否失败，不会因为默认 EFC 配置失败把该设备行标为 `syncFailed`。

这符合之前“默认配置失败不打断 Add Device 主流程”的设计，但如果测试只看添加结果行，可能看不到 EFC 默认配置失败，只能在后续 EFC 同步态或日志里发现。

## 判断

“添加 EFC 成功后静默下发默认 controller 配置”这项功能仍在当前代码中。

更像被回退的是另一项相关修复：`0x4D/07 app_idx` 固定为 `0` 的修复和 contract。当前代码重新回到了使用 `MeshNetworkManager.instance.currentApplicationKey.index` 的状态。

## 建议修复方案

### 方案 A：恢复 EFC `0x4D/07 app_idx = 0` 并补回 contract

推荐。

改动范围：

1. 在 `DeviceEmerFireData+Sync.swift` 中新增 EFC action config 专用 app index 常量，固定为 `0`。
2. `makeControllerSyncTasks(...)` 中生成当前和旧配置的 `actionConfig(...)` 时都使用该常量。
3. 保持 Scene Client publication 继续使用 `MeshNetworkManager.instance.currentApplicationKey`，不混淆 Mesh publication AppKey 和 EFC vendor payload 的 `app_idx`。
4. 在 `scripts/check_efc_controller_flows.sh` 增加防回退检查：
   - 必须存在固定 `0` 的 EFC action app index 常量。
   - EFC action config 不允许再传 `MeshNetworkManager.instance.currentApplicationKey.index`。
5. 补一份简短 docs 记录该边界，避免后续再把这两个 AppKey 语义混起来。

验证：

1. 运行 `bash scripts/check_efc_controller_flows.sh`。
2. 运行 `git diff --check`。
3. 运行 iPhoneOS 构建：
   `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
4. 手工 BLE 验证：新增 EFC，不配置 associated group，确认添加流程中发出的三条 `0x4D/07` payload 的 `app_idx` 为 `0`，并触发 EFC 状态变化后 App 页面能刷新。

### 方案 B：同时把 EFC 默认配置失败显示为 Add Device `syncFailed`

不建议作为本次默认范围。

这会改变 Add Device 主流程的用户可见状态，可能影响批量添加体验。除非测试需要在添加列表立刻暴露 EFC 默认配置失败，否则建议保持当前“失败只影响 EFC 本地同步态，后续手动 repair/sync”的设计。

## 待确认

是否按方案 A 恢复 `0x4D/07 app_idx = 0` 和 contract？

确认后建议只做这一个收口修复，不改 Add Device 的成功/失败展示语义。
