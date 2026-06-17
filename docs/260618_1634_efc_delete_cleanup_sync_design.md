# EFC Delete Cleanup Sync Design

## 背景

真实 EFC 设备删除现在会先进入 `Sync device(s)` 页面清理 EFC 相关 Mesh 配置，再进入设备 Reset 删除流程。现有实现里 Delete cleanup 使用 `SyncDevicesViewController(type: .emergencyFire(... persistsSyncResult: false ...))`，Stop 或部分失败时不会保存 EFC 为需要同步状态。

这会产生风险：部分 EFC Group 订阅已经被删除，部分仍未删除，用户如果返回上级页面、取消删除流程，甚至直接关闭 App，EFC 设备仍保留在 Space 中，但功能配置已经不完整。后续 App 可能看不到该 EFC 需要同步，导致用户无法通过正常同步恢复功能。

## 目标

- 明确区分 EFC 的 `SAVE` 同步和 `Delete` 同步。
- `SAVE` 进入的 `Sync device(s)` 总是按正常 EFC 配置重发任务，并按组补齐订阅。
- `Delete` 进入的 `Sync device(s)` 只清除 associate groups 中灯设备对 EFC internal group 的订阅。
- Delete 同步不发送 EFC 控制器本体 disable、resend、action config、restore delay、publication 等任务。
- Delete 同步失败、中断或 Stop 时，立即持久化 EFC 的未同步状态，不依赖用户返回上级页面。
- Reset 删除失败时复用 light 删除流程的 CANCEL / FORCE DELETE 行为。

## 代码事实

- `DeviceEmerFireData.isSynced` 是 EFC 是否需要同步的本地状态来源，`displayStatus` 在有可同步配置且 `isSynced == false` 时显示同步异常。
- `EmergencyFireControllerSyncPlanner.makeItems()` 会生成正常 EFC 配置任务，包括 controller 本体配置、associate group 订阅和 pending cleanup。
- `EmergencyFireControllerSyncPlanner.makeDeleteCleanupItems()` 当前会混入 controller disable 任务，不符合本次 Delete 需求。
- `SyncDevicesViewController` 当前只用 `persistsSyncResult` 表达是否保存整体同步结果，不能表达 SAVE 与 Delete 的任务语义差异。
- `DeviceProtocol.deleteNodes(nodes:)` 已经提供 Deleting HUD、Reset、Reset 失败后的 FORCE DELETE 弹窗和强制删除行为，应继续复用。

## 推荐方案

采用“显式 EFC sync context + Delete 专用 cleanup 状态”的方案。

### Sync Context

为 EFC 同步引入明确来源语义：

- `saveConfiguration`：来自 Edit - SAVE、Repair、绑定后同步等恢复/配置场景。
- `deleteCleanup`：来自 Delete 删除流程。

`SyncDevicesViewController` 和 `EmergencyFireControllerSyncPlanner` 根据 context 生成不同任务：

- `saveConfiguration` 使用正常 `makeItems()` 语义，必要时全量重发 EFC controller 配置，并为 associate groups 补齐订阅。
- `deleteCleanup` 只生成 `ConfigModelSubscriptionDelete`，只清理当前仍关联或删除待清理的 group，不生成任何新增订阅或 controller 本体任务。

### Delete Cleanup 状态

Delete 流程进入 sync 前，先读取 EFC 当前 associate groups。

- 如果 associate groups 一开始为空，直接进入 `deleteNodes(nodes:)` Reset 删除流程。
- 如果不为空，进入 Delete context 的 `Sync device(s)`。
- 一个 group 的全部订阅删除成功后，从 EFC 的 associate groups 中移除该 group，并保存。
- 一个 group 中任一设备或模型订阅删除失败，该 group 继续保留在 associate groups 中。
- 一旦发生 Stop、失败或部分失败，立即保存 `isSynced = false`，并发送 EFC/Others 状态刷新通知。

这样即使用户在 `Sync device(s)` 页面直接关闭 App，下一次进入 App 仍会看到 EFC 需要同步。用户后续从正常 SAVE/Sync 入口同步时，仍在 associate groups 中的失败 group 会重新订阅 EFC Group，从而恢复功能。

### Delete Sync 重试

Delete context 下的 Re-sync 不根据 `isSynced` 重新生成普通 SAVE 任务，只继续执行删除订阅任务。

- 已成功清除并移出 associate groups 的 group 不再出现在 Delete retry 中。
- 未完全清除的 group 继续显示并重试 `ConfigModelSubscriptionDelete`。
- 全部清除成功后，进入 Reset 删除流程。

### Reset 结果

全部 associate groups 清除成功后，进入现有 `deleteNodes(nodes:)`：

- Reset 成功：删除 EFC 本地缓存和 Mesh node，返回 Others 并刷新列表。
- Reset 失败 + CANCEL：EFC 保留在 Space 中，此时 associate groups 已为空；刷新设备状态。
- Reset 失败 + FORCE DELETE：强制删除 EFC 本地缓存和 Mesh node，返回 Others 并刷新列表。

## 备选方案

### 方案 A：继续只用 `persistsSyncResult`

不推荐。这个布尔值只能表达“是否保存整体同步结果”，不能表达 Delete 与 SAVE 的任务语义。Delete retry 仍可能和普通 need-sync 逻辑混淆，导致删除流程中重新订阅 group。

### 方案 B：新增独立 EFC Delete Sync VC

边界清楚，但会复制 `SyncDevicesViewController` 的 Stop、Re-sync、进度、cell 状态、失败处理和通知逻辑。维护成本较高，不适合当前需求。

### 方案 C：显式 sync context，复用现有 Sync 页面

推荐。改动集中在 EFC planner、EFC sync type、Delete 入口和持久化状态处理，不复制 UI，不改变其他设备同步流程。

## 边界与风险

- Delete cleanup 不发送 EFC 本体 disable 任务。Reset 失败 CANCEL 后，EFC 设备仍存在，但 associate groups 已为空，不应继续控制原组。
- 离线灯或未 keybind 完成的灯无法立即删除订阅。相关 group 需要保留为未同步状态，后续 SAVE/Sync 用正常订阅流程恢复功能。
- Delete context 必须贯穿 Retry。不能只根据 `isSynced == false` 重新生成任务，否则会把 Delete 重试变成 SAVE 订阅补齐。
- 成功移除 associate group 时需要谨慎保存两套 function 的 group 地址，Power Loss 和 Fire Alarm 当前共享同一 associated groups UI，但底层仍是两套 settings。
- 需要保证已有真实 EFC 删除入口和 Others 删除入口使用同一套共享删除流程。

## 验收标准

- Edit - SAVE 进入 Sync 后，仍按正常 EFC 配置全量同步，并按组补齐订阅。
- Delete 进入 Sync 后，只出现 group subscription delete 任务，不出现 EFC enable/resend/action/restore/publication 任务，也不出现 subscription add 任务。
- Delete Sync 中 Stop 或部分失败后，EFC 立即保存为 `isSynced = false`，返回或重启 App 后仍显示需要同步。
- Delete Sync 中失败 group 后续从 SAVE/Sync 入口同步时，会重新补齐 EFC Group 订阅。
- Delete Sync 自身点击 Re-sync 时，只继续删除订阅，不会重新订阅。
- associate groups 为空时，Delete 不进入 Sync 页面，直接进入 Deleting / Reset。
- Reset 失败 CANCEL 后 EFC 保留且 associate groups 为空；FORCE DELETE 后 EFC 从 Others 消失。

## 验证计划

- 更新 `scripts/check_efc_controller_flows.sh`：
  - 断言 Delete context 不生成 controller 本体任务。
  - 断言 Delete context 不生成 `ConfigModelSubscriptionAdd`。
  - 断言 Delete context 使用 `ConfigModelSubscriptionDelete`。
  - 断言 Delete 入口仍走 `deleteNodes(nodes:)`。
- 运行 `bash scripts/check_efc_controller_flows.sh`。
- 运行 `git diff --check`。
- 运行 iPhoneOS 构建：
  `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
