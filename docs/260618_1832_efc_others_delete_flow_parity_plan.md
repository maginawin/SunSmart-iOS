# EFC Others Delete Flow Parity 分析与修复方案

## 背景

需求：在 `Site - Space - Main - Others` 中进入底部删除状态后，点击 EFC 设备上的删除入口，其行为应与 EFC 设备页右上角菜单中的 `Delete` 一样。

## 当前代码链路

### Others 页删除入口

文件：`SunSmart/Main/Device/Others/Controller/DeviceOthersViewController.swift`

- EFC item 使用 `EmerFireAlarmDeviceCell`。
- 编辑状态下 cell 显示删除按钮。
- 点击 EFC cell 删除按钮后调用：
  - `confirmDeleteEmergencyFireController(_:)`
  - 再调用共享 helper `confirmDeleteEmergencyFireControllerDevice(...)`
  - `presentsSyncModally: true`
  - 删除成功后执行 `finishDeleteOthersItem()`

### EFC 设备页右上角 Delete

文件：`SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorRouting.swift`

- 若是已绑定真实 EFC：
  - 菜单中的 `Delete` 调用 `deleteDevice()`
  - 再调用共享 helper `confirmDeleteEmergencyFireControllerDevice(...)`
  - `presentsSyncModally: false`
  - 删除成功后执行 `finishDeleteDevice()`
- 若是未绑定虚拟 EFC：
  - `moreClick()` 先进入 `showUnlinkedVirtualEmergencyFireControllerMenu()`
  - `Delete` 调用 `confirmDeleteUnlinkedVirtualEmergencyFireController()`
  - 确认后走本地删除 `deleteUnlinkedVirtualEmergencyFireController()`
  - 不进入 delete cleanup sync，也不发送 reset

## 是否一致

不完全一致。

### 一致的部分

对“已绑定真实 EFC”，两条入口最终都使用 `confirmDeleteEmergencyFireControllerDevice(...)`，因此主删除语义一致：

- 先检查 associate groups / pending cleanup；
- 必要时进入 EFC Delete cleanup 的 `SyncDevicesViewController`；
- cleanup 成功后清空 associations；
- 再发送 reset 并删除本地 EFC cache。

主要差异只是展示方式：

- Others 页以 modal 形式展示 sync；
- EFC 设备页以 push 形式展示 sync。

### 不一致的部分

1. 未绑定虚拟 EFC 的删除不一致。

   - EFC 设备页右上角 Delete：本地删除，不进入 sync，不发送 reset。
   - Others 页 cell 删除：直接走真实 EFC 共享删除 helper；如果配置里仍有 associate groups 或 pending cleanup，可能进入 delete cleanup sync。

2. Delete 权限 gating 不一致。

   - EFC 设备页右上角菜单只有在 `space.deviceOperates.contains(.delete)` 时才展示 Delete。
   - Others 页底部进入删除状态目前主要由 `.edit` 控制；EFC cell 删除 callback 没有单独 guard `.delete`。
   - 这意味着有 edit 但没有 delete 权限时，Others 页可能仍能触发 EFC 删除确认。

3. 未绑定虚拟 EFC 的确认文案不一致。

   - EFC 设备页右上角 Delete 使用 `Are you sure to delete the EFC device?`。
   - Others 页当前共享真实设备删除确认使用 `device_delete_message`。

## 根因

EFC 设备页已经把“真实已绑定 EFC”和“未绑定虚拟 EFC”拆成两条删除流；Others 页只接入了真实 EFC 的共享删除 helper，没有先判断 `device.bindNode == nil`。

同时，Others 页的编辑态是列表通用行为，进入编辑态和展示 cell 删除按钮没有对 EFC 的 `.delete` 权限做二次保护。

## 推荐修复方案

推荐做法：抽一个共享的 EFC 删除入口，让 Others 页和 EFC 设备页都复用同一套分流。

### 方案 A：最小改动，在 Others 页补齐分流和权限

改动点：

- 在 `DeviceOthersViewController.confirmDeleteEmergencyFireController(_:)` 开头增加 delete 权限 guard。
- 若 `device.bindNode == nil`：
  - 走与 EFC 设备页相同的未绑定虚拟 EFC 本地删除语义；
  - 使用同一确认文案；
  - 删除 `DeviceEmerFireStore` cache；
  - 更新 space count；
  - 发送 `devicesUpdateNotificationName`、`deviceOthersRefreshNotificationName`、`spaceDataChangedNotificaitonName`；
  - 调用 `finishDeleteOthersItem()` 收口 UI。
- 若 `device.bindNode != nil`：
  - 继续走 `confirmDeleteEmergencyFireControllerDevice(...)`。

优点：改动小，风险低。

缺点：未绑定虚拟 EFC 本地删除逻辑会和设备页保留少量重复。

### 方案 B：推荐，抽共享 helper 统一分流

改动点：

- 在 `DeviceProtocol where Self: UIViewController` 中新增共享入口，例如：
  - `confirmDeleteEmergencyFireControllerDeviceOrVirtual(...)`
- 该 helper 内部统一处理：
  - delete 权限 guard；
  - `bindNode == nil` 时本地删除；
  - `bindNode != nil` 时进入现有 `confirmDeleteEmergencyFireControllerDevice(...)`。
- `EmerFireAlarmMonitorRouting.deleteDevice()` 和 `DeviceOthersViewController.confirmDeleteEmergencyFireController(_:)` 都调用新 helper。
- EFC 设备页可保留菜单分流展示，但真正删除动作复用 helper。

优点：

- 最符合“两个入口需要一样”的预期；
- 权限、本地删除、真实 EFC delete cleanup 都只有一个真值入口；
- 后续再改 EFC 删除语义时不容易漏掉 Others 页。

缺点：

- 需要轻微整理 `confirmDeleteUnlinkedVirtualEmergencyFireController()` / `deleteUnlinkedVirtualEmergencyFireController()` 的职责边界。

### 方案 C：只把 Others 页全部改成 EFC 设备页右上角 Delete 的同名函数

不推荐。`deleteDevice()` 依赖 `currentDevice` 和设备页 navigation 关闭语义，不适合直接从 Others 页调用；会把页面生命周期耦合到设备页。

## 推荐实现细节

采用方案 B。

1. 在共享 helper 层增加 `confirmDeleteEmergencyFireController(...)` 统一入口，参数包含：
   - `device`
   - `space`
   - `presentsSyncModally`
   - `preferredContentSize`
   - `completion`
2. helper 先 guard `.delete` 权限，不满足则显示 `no_permission`。
3. 若 `device.bindNode == nil`：
   - 弹出 `Are you sure to delete the EFC device?`；
   - 确认后删除 cache；
   - 保存 space count；
   - 发刷新通知；
   - 显示 done；
   - 调用 completion。
4. 若 `device.bindNode != nil`：
   - 复用现有真实 EFC helper。
5. Others 页 EFC cell 删除 callback 改为调用新共享入口。
6. EFC 设备页右上角 Delete 改为调用同一个共享入口，保留自己的 `finishDeleteDevice()` completion。
7. 更新 `scripts/check_efc_controller_flows.sh`：
   - 断言 Others 页 EFC 删除有 delete 权限 guard 或调用共享 guarded helper；
   - 断言 Others 页未绑定虚拟 EFC 删除不会进入 delete cleanup sync；
   - 断言 EFC 设备页和 Others 页都调用同一个共享入口。

## 验证计划

- 先运行 `bash scripts/check_efc_controller_flows.sh`，确认新增 contract 在旧代码下失败。
- 实现后运行：
  - `bash scripts/check_efc_controller_flows.sh`
  - `git diff --check`
  - `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

## 手工验收建议

1. 已绑定真实 EFC：
   - 从 Others 删除入口删除；
   - 从 EFC 设备页右上角 Delete 删除；
   - 两者都应按 associate groups 情况进入 delete cleanup sync，再进入 reset 删除流程。
2. 未绑定虚拟 EFC：
   - 从 Others 删除入口删除；
   - 从 EFC 设备页右上角 Delete 删除；
   - 两者都应只本地删除，不进入 sync，不发送 reset。
3. 无 delete 权限账号：
   - EFC 设备页右上角不应展示 Delete；
   - Others 页即使进入编辑态，也不应能实际触发 EFC 删除，或应提示 `no_permission`。

## 2026-06-18 实现结果

- 已采用方案 B。
- 新增共享入口 `confirmDeleteEmergencyFireControllerDeviceOrVirtual(...)`。
- 共享入口先检查 `.delete` 权限；无权限直接提示 `no_permission`。
- `device.bindNode == nil` 时走未绑定虚拟 EFC 本地删除：
  - 使用 `Are you sure to delete the EFC device?` 确认；
  - 删除 `DeviceEmerFireStore` cache；
  - 更新 space 设备计数；
  - 发送设备列表和 Others 刷新通知；
  - 不进入 Delete cleanup sync，不发送 reset。
- `device.bindNode != nil` 时复用现有真实 EFC 删除流程：
  - associate groups / pending cleanup 存在时进入 Delete cleanup sync；
  - cleanup 成功后清空关联组；
  - 再走 reset 删除设备和本地 cache。
- `DeviceOthersViewController` 和 `EmerFireAlarmMonitorRouting` 已改为调用同一个共享入口。
- `scripts/check_efc_controller_flows.sh` 已增加共享入口、权限 guard、虚拟 EFC 分流和 Others 入口不可绕过的 contract。
