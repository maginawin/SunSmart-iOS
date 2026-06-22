# EFC LINK Associated Group Sync 修正设计

## 现场偏差

上一轮方案 A 实现后，虚拟 EFC 关联一个包含真实设备的 Group，再 LINK 真实 EFC 时，用户现场观察到：

- Add Device 完成后提示成功。
- 没有进入 EFC Sync 页面。
- Group 内真实设备的 Model subscription 未真正下发。
- 功能仍不正常。

## 根因修正

当前 `DeviceAddViewController` 的绑定流程已经在 `finishBindingFlowIfNeeded()` 中先关闭 Add Device 页面，然后才调用外层 `deviceAddCallback`。

上一轮在 `LinkedEmerFireEditVC.deviceAddCallback` 中又调用了一次 `dismiss(animated:completion:)`，实际变成“Add Device 已经关闭后再次 dismiss”。这个二次 dismiss 没有可靠的 presented controller 可关闭，completion 不可靠，因此 `openSyncAfterLinkedDeviceIfNeeded()` 可能没有被执行，导致不会进入 EFC Sync。

另一个设计偏差是：上一轮 `openSyncAfterLinkedDeviceIfNeeded()` 使用 `items: nil` 创建 `SyncDevicesViewController`。`items: nil` 会让 `EmergencyFireControllerSyncPlanner.makeItems()` 生成完整 EFC 同步任务，包括：

- EFC controller 自身配置。
- associated Group 订阅任务。
- cleanup 任务。

这不符合当前预期。当前预期是：

- EFC controller 自身配置仍在 Add Device append 阶段静默下发。
- LINK 成功后的 Sync 只负责真实 associated Group 内设备订阅 EFC publish group 的跨节点配置。

## 修正目标

1. LINK 成功后必须可靠进入 EFC Sync 页面。
2. LINK 后 EFC Sync 只包含 associated Group subscription tasks，不重新下发 EFC controller 自身配置。
3. 空组或无真实可下发订阅任务时，不进入 Sync 页面。
4. Sync 成功后刷新 Edit / Others 状态，并把 EFC 标记为 synced。
5. Sync 失败时保留 need-sync，允许后续 Retry / SAVE 继续下发。

## 推荐方案

采用“callback 直接打开 limited sync”的修正方案：

1. `LinkedEmerFireEditVC.deviceAddCallback` 中移除二次 `dismiss`。
2. 因为 `DeviceAddViewController` 已经关闭 Add Device 后才调用外层 callback，所以外层 callback 刷新状态后直接调用 `openSyncAfterLinkedDeviceIfNeeded()`。
3. `openSyncAfterLinkedDeviceIfNeeded()` 重新读取绑定后的 EFC 数据。
4. 使用 `EmergencyFireControllerSyncPlanner(data:meshUUID:subnetworkId:)` 构建 sync planner。
5. 只调用 `makeAssociatedGroupItems()` 生成 LINK 后需要下发的 Group subscription items。
6. 如果 items 为空，返回 false，不打开 Sync 页面。
7. 如果 items 非空，创建：

   `SyncDevicesViewController(type: .emergencyFire(data: device, items: items, context: .saveConfiguration(persistsSyncResult: true, changedFromConfiguration: nil)))`

8. Sync 成功后刷新 `viewModel.refreshLinkedDeviceFromStore()` / table / Others 通知。

## 方案边界

- 不修改 SDK fast-add append 发送语义。
- 不恢复 associated Group subscription 到 Add Device append。
- 不让 LINK 后 Sync 使用 `items: nil`。
- 不改变 EFC SAVE 的完整同步行为；SAVE 仍可使用完整 planner。

## 验证计划

1. 更新 `scripts/check_efc_controller_flows.sh`：
   - 要求 LINK callback 直接调用 `openSyncAfterLinkedDeviceIfNeeded()`。
   - 禁止 LINK callback 中出现 `dismiss(animated: true) { ... openSyncAfterLinkedDeviceIfNeeded() ... }` 的二次 dismiss 模式。
   - 要求 `openSyncAfterLinkedDeviceIfNeeded()` 使用 `makeAssociatedGroupItems()`。
   - 禁止该方法用 `items: nil` 打开 EFC Sync。
2. 运行 `bash scripts/check_efc_controller_flows.sh`。
3. 运行 iPhoneOS build：
   `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
4. 手工验证：
   - 虚拟 EFC + 空组 + LINK：Add Device 成功后不进入 Sync。
   - 虚拟 EFC + 有真实设备 Group + LINK：Add Device 成功后进入 EFC Sync，且只显示 Group 内真实设备的 EFC subscription 同步项。
   - Sync 成功后功能生效，不再显示 need-sync。

