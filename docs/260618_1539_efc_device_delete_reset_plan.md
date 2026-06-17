# EFC Device Page Delete Reset Plan

## 背景

真实 EFC 设备页右上角菜单的 Delete 当前走 `EmerFireAlarmMonitorRouting.deleteDevice()`，后续只执行 EFC delete cleanup 和 `DeviceEmerFireStore.shared.clearMonitoringConfiguration(for:)`。这会清空本地 monitoring configuration，但不会发送 Mesh Reset，也不会从 Mesh node / EFC store 中删除真实设备。

`Site - Space - Main - Others` 页面中 EFC cell 的删除入口已经走完整删除设备链路：先执行 EFC cleanup，再通过 `DeviceProtocol.deleteNodes(nodes:)` 调用 `MeshAPI.resetNodes`，Reset 失败时展示强制删除提示，最后删除 EFC 本地缓存并刷新 Others 列表。

## 目标

- 设备页右上角菜单选择 Delete 时，改为删除真实 EFC 设备。
- 删除前仍保留现有 EFC cleanup sync。
- cleanup 后必须对绑定 node 发送 Reset。
- Reset 失败时沿用 `DeviceProtocol.deleteNodes` 的强制删除提示。
- 删除成功或强制删除后，回到 Others 页面并刷新设备列表。
- Others 页面原有删除入口与设备页菜单删除入口使用同一套共享流程，避免后续分叉。

## 文件结构

- 修改 `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorRouting.swift`
  - 新增 `DeviceProtocol where Self: UIViewController` 的 EFC 删除共享 helper。
  - 设备页 `deleteDevice()` 改用共享 helper。
  - 移除只清 configuration 的设备页 delete 实现。
- 修改 `SunSmart/Main/Device/Others/Controller/DeviceOthersViewController.swift`
  - EFC cell 删除入口改用共享 helper。
  - 保留 `finishDeleteOthersItem()` 作为 Others 列表刷新和通知收口。
- 修改 `scripts/check_efc_controller_flows.sh`
  - 增加 contract，确保设备页删除调用共享 Reset 删除流程。
  - 增加 contract，防止 `EmerFireAlarmMonitorRouting` 回退到 `clearMonitoringConfiguration`。

## 实施步骤

1. 在 `EmerFireAlarmMonitorRouting.swift` 中新增共享 helper：
   - `confirmDeleteEmergencyFireControllerDevice(...)` 展示 `device_delete_message` 确认框。
   - `deleteEmergencyFireControllerDevice(...)` 生成 `makeDeleteCleanupItems()`。
   - cleanup 有 Mesh message 时，未连接 mesh 则提示 `device_notconnect_message` 并停止。
   - cleanup 成功后进入 node 删除。
   - 无 cleanup message 时直接进入 node 删除。
   - node 删除使用 `deleteNodes(nodes:)`，复用 Reset 和强制删除弹窗。
   - 删除完成后调用 `DeviceEmerFireStore.shared.deleteCachedDevice(device)`，再执行调用方 completion。

2. 设备页接入共享 helper：
   - `deleteDevice()` guard 当前 device。
   - 调用共享 helper，`presentsSyncModally` 传 `false`，让 sync 页面按当前导航栈 push。
   - completion 中更新 `space.deviceCount` / `space.luminairesCount`，保存 space，发送 `devicesUpdateNotificationName` 与 `deviceOthersRefreshNotificationName`，最后 `closeOrBack()`。

3. Others 页接入共享 helper：
   - `confirmDeleteEmergencyFireController(_:)` 改为调用共享 helper。
   - `presentsSyncModally` 传 `true`，保持现有 modal sync 展示方式。
   - iPad 时继续传 `iPadPreferredContentSize`。
   - completion 继续调用 `finishDeleteOthersItem()`。
   - 删除原有重复的 `deleteEmergencyFireController` 和 `deleteEmergencyFireControllerNodeAndCache` 私有方法。

4. 更新 contract：
   - 断言 `EmerFireAlarmMonitorRouting.swift` 存在 `confirmDeleteEmergencyFireControllerDevice`。
   - 断言 `EmerFireAlarmMonitorRouting.swift` 存在 `deleteNodes(nodes: [node])`。
   - 断言 `EmerFireAlarmMonitorRouting.swift` 不再包含 `clearMonitoringConfiguration(for: device)`。

5. 验证：
   - `bash scripts/check_efc_controller_flows.sh`
   - `git diff --check`
   - `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

## 风险与边界

- 未绑定 node 的 EFC 只能删除本地缓存，不发送 Reset，因为没有真实设备地址。
- cleanup sync 失败时不会继续 Reset，保持当前 sync 成功后才清理/删除的行为。
- Reset 失败后的强制删除完全复用 `DeviceProtocol.deleteNodes`，不新增另一套强制删除弹窗。
- 不修改 EFC Edit 页底部 Delete 的语义；本轮只覆盖真实 EFC 设备页右上角菜单和 Others 页真实设备删除入口。
