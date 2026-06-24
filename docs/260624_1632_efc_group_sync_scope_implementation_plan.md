# EFC Group Sync Scope Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 采用方案 A，把 EFC 自身配置同步状态与 EFC 关联 Group 的订阅/清理同步状态拆开：Group 未同步完成时，EFC 仍展示 `Devices not synced`；但重新进入 Sync device(s) 页面时，只执行剩余 Group Subscription / Group Cleanup，不再误触发完整 EFC Others 任务。  
**Architecture:** `DeviceEmerFireData` 增加持久化的 EFC 自身配置 pending 标记；`EmergencyFireControllerSyncPlanner` 按 pending 类型生成任务；`SyncDevicesViewController` 按已执行任务回写聚合状态；`DeviceLightsViewController` 在 EFC group 配置变化后刷新 Light 节点 sync cache 和底部同步按钮。  
**Tech Stack:** Swift / SQLite.swift / UIKit / NordicSigMeshSDK / shell contract script。

---

## 任务 1：补 contract，先固定预期失败

- [ ] 读取并保留 `scripts/check_efc_controller_flows.sh` 当前未提交内容，尤其是已有的 brightness range 断言。
- [ ] 追加 EFC group sync scope contract：
  - `DeviceEmerFireData` 必须有 `controllerSelfSyncPending` 或同等字段。
  - `EmergencyFireControllerSyncPlanner.makeItems()` 必须按 `changedFromConfiguration`、`controllerSelfSyncPending`、publication repair 共同决定是否生成 EFC controller item。
  - `SyncDevicesViewController.finishEmergencyFireControllerSyncIfNeeded` 不允许再用 `data.isSynced = success` 粗暴覆盖聚合状态。
  - `.devices` 入口完成 EFC association tasks 后必须刷新 EFC 聚合 sync 状态。
  - `DeviceLightsViewController` 收到 `.linkedEmerFireConfigDidChange` 后必须清理 Light sync cache 并重新计算 footer sync 按钮。
- [ ] 运行 `bash scripts/check_efc_controller_flows.sh`，确认新增 contract 在当前实现下失败。

## 任务 2：数据模型与持久化

- [ ] 在 `DeviceEmerFireData` 增加 `controllerSelfSyncPending: Bool`，含 init、copy/restore、默认值。
- [ ] 在 `LinkedEmerFireConfig` 增加同字段，确保 Edit VM 能在 config 层携带状态。
- [ ] 在 `DeviceEmerFireRepository` 增加 SQLite 列与迁移：
  - 新列默认 `false`。
  - 迁移时对旧数据执行兼容回填：`isSynced == false && bindNodeAddress != nil` 的 EFC 置为 `controllerSelfSyncPending = true`，避免旧版本未同步设备丢失完整 repair 能力。
- [ ] 更新 `ExportData` / `ImportData`：
  - 导出新字段。
  - 导入缺失字段时按 `!isSynced && bindNodeAddress != nil` 兼容推断。

## 任务 3：同步状态 helper 与 Planner 任务裁剪

- [ ] 在 `EmergencyFireControllerConfiguration` 增加“只比较 controller self 配置”的 helper，忽略 `associateGroupAddresses` 与 `pendingUnassociateGroupAddresses`。
- [ ] 在 `DeviceEmerFireData+Sync.swift` 增加 helper：
  - 判断是否存在 controller self pending。
  - Group association / cleanup 成功或停止后，重新计算聚合 `isSynced`。
  - Controller self 任务成功时只清 `controllerSelfSyncPending`，不直接把 `isSynced` 置 true。
- [ ] 调整 `EmergencyFireControllerSyncPlanner.makeItems()`：
  - 只有 `changedFromConfiguration != nil`、`controllerSelfSyncPending == true`、或 publication repair 需要时，才生成 EFC controller item。
  - 无 controller self task 时不追加空的 `EmergencyFireControllerSyncItem`。
  - Group association 与 cleanup item 保持原有生成逻辑。

## 任务 4：Edit SAVE 分类

- [ ] 调整 `LinkedEmerFireEditViewModel.save/apply`：
  - EFC controller self 配置变更或 publish group 变更：`controllerSelfSyncPending = true`，并通过 `changedFromConfiguration` 生成增量 EFC Others。
  - 仅 Group associate / unassociate 变更：`controllerSelfSyncPending` 保持 false，`isSynced = false` 作为聚合未完成状态。
  - `lastSavedRequiresSync` 继续表示任一类型需要同步。
- [ ] 保存 EFC group 变更后，清理受影响 Light 节点的 sync cache，范围为 old/new active group 与 pending cleanup group 的并集。

## 任务 5：Sync 页面回写规则

- [ ] 在 `SyncDevicesViewController` 中按 task kind 区分：
  - EFC controller self tasks：publication、enabled、resend、restore delay、action config。
  - EFC association tasks：Light subscription / cleanup。
- [ ] `.emergencyFire` 入口结束时：
  - 如果本次有 controller self tasks，则按这些 task 是否成功更新 `controllerSelfSyncPending`。
  - 无 controller self tasks 时保留原 self pending 状态。
  - 无论成功/STOP，都重新计算 `isSynced` 聚合状态并保存。
- [ ] `.devices` 入口中 EFC association task 成功或完成时，也刷新对应 EFC 聚合状态并发送 `.linkedEmerFireConfigDidChange`。

## 任务 6：Lights footer 同步按钮刷新

- [ ] 修改 `DeviceLightsViewController` 的 `.linkedEmerFireConfigDidChange` observer：
  - 清理当前 Light 列表的 sync cache。
  - 调用既有 `updateUI` 或同等路径重新计算 `devices.contains { $0.needSync }`。
  - 保留 collection reload 与 all on/off UI 刷新。

## 任务 7：验证

- [ ] 运行 `bash scripts/check_efc_controller_flows.sh`，确认 contract 通过。
- [ ] 运行 `git diff --check`。
- [ ] 运行 iPhoneOS 构建：

```sh
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

## 验收结论

- Group A 的 Light A subscription 未完成并 STOP：
  - EFC Edit 显示 `Devices not synced`。
  - 从 EFC Edit 重新进入 Sync，只显示剩余 Group Subscription / Cleanup，不显示无关 EFC Others。
  - 从 Lights 底部同步进入 Sync，能执行剩余 Light 订阅任务；完成后 EFC 聚合状态可被清理。
- 从 EFC 移除 Group A 后 STOP：
  - EFC Edit 显示 `Devices not synced`。
  - 如果剩余 cleanup 任务落在 Light 侧，Lights 底部同步按钮应出现并可完成 cleanup；如果没有 Light 侧任务，则 EFC Edit 的 Devices not synced 入口仍能完成本地/远端 cleanup。
