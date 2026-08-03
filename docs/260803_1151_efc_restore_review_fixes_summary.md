# EFC Restore 审查问题修复总结

**日期：** 2026-08-03
**方案：** B（每地址 EFC 恢复上下文 + 显式同步结果）
**状态：** 三项审查问题已完成实现、聚焦测试、静态合约和四个 App target 构建；真机 EFC/Mesh/OTA 验收待执行

## 1. 修复结果

### 1.1 入网后身份异常不再降级为普通恢复

扫描阶段已分类为 EFC 的设备现在始终进入 EFC 身份决策。只有广播身份、历史设备身份和入网后 Composition 身份均为已登记的 `EmergencyController`，且 CID/PID 精确一致时，才允许迁移并进入专用恢复链。

Composition CID/PID 缺失、变化、命中其他 EFC、普通产品或未知产品时均进入终止身份失败：不发送普通恢复消息、不迁移 EFC 数据、不进入普通同步，也不计入成功恢复结果。

### 1.2 自动 OTA 只在权威成功时完成

EFC 队列、普通设备同步与最终收口现在传递显式结果：`succeeded`、`needsAttention`、`cancelled`。用户返回、自动重试耗尽、EFC `isSynced != true`、普通 Node 仍 `needSync` 或存在身份/迁移/同步失败时，Restore 不再向 BLE OTA 报告完成，也不会自动移除待恢复节点。

对外成功数组改为按设备类别读取权威真值：普通设备要求恢复成功且 `needSync == false`；EFC 要求上下文成功且 controller `isSynced == true`。同时增加一次性回调保护，避免显式完成和页面释放重复报告。

共享的 `SyncDevicesViewController` 仅新增可选自动恢复失败回调。Restore 设置后，重试耗尽会保留失败同步页；其他调用方未设置时继续保持原行为。

### 1.3 EFC 数据迁移失败可执行 Retry

每个已 Provision 的 EFC 地址现在保留完整恢复上下文，包括 `ProvisioningDevice`、历史 Node、扫描身份、入网后 Node、controller 与阶段状态。迁移失败后 Retry 会使用同一上下文重新执行迁移；成功后进入 `.emergencyFire` 专用同步，失败则继续保持可重试状态。

原先仅保存失败地址、导致 Retry 无输入的状态集合已删除。身份失败仍是不可同步的终止失败，不会生成无动作的同步任务。

## 2. 主要变更

- 新增 `DeviceRestoreEFCRecoveryPolicy`，集中处理入网后身份、自动完成门禁与成功结果归约。
- `DeviceRestoreViewController` 新增按地址维护的 EFC 恢复上下文，锁定 EFC 分支并统一迁移、同步和 Retry 状态。
- `SyncDevicesViewController` 新增可选的自动恢复失败回调，阻止 Restore 场景在失败时自动返回 BLE OTA。
- 新增恢复策略聚焦测试，并把新策略源码加入 SunSmart、Archipelago、SLG Sync Plus、SylSmart 四个 target。
- 更新 EFC Restore 静态合约，覆盖上下文、迁移 Retry、显式同步结果和自动完成门禁。
- 未修改 `NordicSigMeshSDK`，未新增用户可见文案，未修改本地化资源。

## 3. TDD 与验证证据

### 3.1 RED / GREEN

- 入网后身份及自动收口测试首次运行因 `DeviceRestoreEFCRecoveryPolicy` 不存在而编译失败；实现后全部通过。
- 成功结果权威归约测试首次运行因缺少 `shouldReportSuccessfulNode` 而编译失败；实现后通过。
- 四 target 源文件归属合约首次运行因新策略未加入 target 而失败；补齐工程引用后通过。
- EFC flow 合约首次运行因恢复上下文尚不存在而失败；完成页面状态链后通过。

### 3.2 聚焦测试与静态合约

- `scripts/check_device_restore_efc_support.sh`：PASS，候选策略和恢复策略测试均通过。
- `scripts/check_efc_controller_flows.sh`：PASS。
- `scripts/check_efc_comprehensive_status_mapping.sh`：PASS。
- `scripts/check_efc_status_content_list.sh`：PASS。
- `scripts/check_efc_i18n.sh`：PASS。
- `git diff --check`：PASS；未跟踪文件另行执行 whitespace 检查。

### 3.3 generic iPhoneOS 构建

以下四个 scheme 均使用 Debug、generic iPhoneOS、`CODE_SIGNING_ALLOWED=NO` 直接执行 `xcodebuild` 并成功：

- SunSmart
- Archipelago
- SLG Sync Plus
- SylSmart

构建仍包含工程既有的资源名重复、过时扫码 API、actor isolation、重复 source 和 Info.plist 等告警；本次未扩大范围处理。

## 4. 真机验收矩阵

当前验证证明策略、静态业务合约和四 target 编译成立，不等同于真实 EFC、Mesh ACK、OTA 页面联动或落库重启已通过。发布前至少验证：

1. `CID 0x0A78 / PID 0x2131` 完成扫描、Provision、迁移、专用同步并以 `isSynced == true` 收口。
2. 另一种已登记 `EmergencyController` 完成相同链路，确认没有 PID 白名单。
3. 注入 Composition CID/PID 缺失或不一致，确认不发送普通恢复配置、不报告成功。
4. 注入首次本地迁移失败，确认 Retry 重新迁移；随后成功进入 EFC 同步，连续失败仍可再次 Retry。
5. EFC 与普通同步页分别执行 Back/Cancel，确认留在 Restore/Sync，BLE OTA 不移除失败节点。
6. 自动重试耗尽后保留失败同步页，不触发完成回调。
7. 混合普通/EFC 批次任一失败时不报告整批完成，已完成设备保留权威成功状态。
8. 全部设备权威成功时只回调一次，页面释放不会重复回调。
9. App 重启后核对 EFC controller 地址、configuration、pending 状态和 `isSynced` 持久化真值。

## 5. Git 状态

本次未创建 commit、未 push、未 merge；改动保留在当前 `fix` linked worktree，等待人工检查与真机验收。
