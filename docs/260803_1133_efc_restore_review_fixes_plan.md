# EFC Restore 审查问题修复计划

**日期：** 2026-08-03
**状态：** 已按方案 B 完成实现与静态/构建验证；真机验收待执行
**范围：** 只修复 EFC 入网后身份真值、自动 OTA 同步退出真值、迁移失败 Retry；不扩展 EFC 配置功能，不修改协议和 SDK

## 1. 审查结论

三条审查意见均与当前源码一致，需要修复。

### P1：入网后 EFC 身份异常会降级到普通恢复

扫描阶段已经通过历史 Node 和广播 CID/PID 将 `ProvisioningDevice` 分类为 EFC，但 `appendMessagesBack` 又用历史 Node 与入网后 Node 是否精确匹配决定是否进入 EFC 分支。匹配失败时会继续执行普通恢复消息链。

这会造成三个问题：

- EFC 的扫描分类在入网后失效；
- Composition CID/PID 缺失或变化时可能发送普通设备恢复配置；
- 最终可能把身份异常设备写成 Restore success。

正确原则是：扫描阶段已经分类为 EFC 后，入网后只能得到“EFC 身份验证成功”或“EFC 恢复失败”，不能降级为普通设备。

### P1：自动 OTA 同步返回与完成使用同一条 completion

EFC 专用同步和普通同步的 `syncSuccessCallback`、`backActionCallback` 最后都会调用无结果类型的 completion，`finishRestoreSyncRetryFlow` 又在自动 `.specified` 模式下无条件调用 `deviceRestoreCallback` 并跳回 BLE OTA 页面。

此外，普通 `SyncDevicesViewController` 在 `automationRestore == true` 且自动重试耗尽时，会自行跳回 BLE OTA 页面。此时 `DeviceRestoreViewController.deinit` 仍会回调全部 `restoreNodes`，外层只用 `Node.needSync` 判断，而 EFC 的权威失败真值位于 `DeviceEmerFireData.isSynced`，因此可能误报全部恢复成功并移除待恢复节点。

正确原则是：自动 OTA 只有在所有本轮已入网设备均满足各自权威成功条件后才能回调并离开；同步失败、用户返回或中止必须留在 Restore/Sync 流程，并且不能通过 deinit 回调完成。

### P2：迁移失败只有地址，没有可重试输入

当前迁移失败只写入 `failedEmergencyFireRestoreMigrationAddresses`。Retry 构建 EFC entry 时又明确过滤这些地址，普通同步同时排除 EFC，因此点击 Retry 没有执行路径。

`DeviceEmerFireStore.restoreDevice` 可以按旧地址或新地址重复解析目标记录，迁移操作具备重新执行基础；缺失的是页面对历史 Node、入网后 Node、扫描身份和设备对象的保留。

正确原则是：迁移失败属于可重试失败，页面必须保留完整输入；Retry 先重新迁移，成功后再进入 `.emergencyFire` 同步。

## 2. 方案比较

### 方案 A：继续增加失败 Set 和布尔标记

分别增加身份失败地址、迁移输入字典和自动退出标志，在现有回调中修补条件。

优点：代码改动行数较少。

缺点：同一地址的分类、身份、迁移和同步状态分散在多个集合；容易再次出现集合不同步、错误降级或 Retry 无输入。

结论：不推荐。

### 方案 B：每地址 EFC 恢复上下文 + 显式同步结果（推荐）

为每个已扫描并分类为 EFC 的设备保留一条恢复上下文，统一保存历史 Node、广播身份、ProvisioningDevice、入网后 Node、controller 和失败阶段。EFC 分支由扫描分类锁定，入网后身份验证、迁移、专用同步和 Retry 都只更新同一上下文。

同时让 EFC 队列、普通同步和最终收口返回显式结果，自动 OTA 只在权威成功时报告完成。对共享 `SyncDevicesViewController` 只增加一个可选的“自动重试耗尽处理”回调；未设置时保持其他调用方当前行为。

优点：三条问题在同一状态模型内闭环；可测试；不修改现有 callback 公共签名；共享页面改动可控。

缺点：需要新增一个纯 Swift 决策策略和页面内恢复上下文，改动比方案 A 多。

结论：推荐。

### 方案 C：重构 Device Restore 对外 callback 为完整 Result

把 `deviceRestoreCallback` 改成带成功、部分成功、失败、中止和失败原因的结果对象，并同步修改 BLE OTA、Space、Site 等所有调用方。

优点：长期接口语义最清楚。

缺点：影响所有 Restore 入口，明显超出本次三个 EFC 审查问题的聚焦范围。

结论：本次不采用。

## 3. 推荐方案 B 的状态设计

### 3.1 EFC 恢复上下文

页面新增按新 Node 地址索引的 `EmergencyFireRestoreContext`，至少保留：

- `ProvisioningDevice`；
- 历史 Node；
- 扫描广播确认的 EFC CID/PID；
- 入网后的 Node；
- 成功迁移后的 `DeviceEmerFireData`；
- 当前阶段和失败原因。

阶段固定为：

1. `awaitingComposition`：扫描已确认 EFC，等待入网后身份；
2. `readyForMigration`：Composition 身份与扫描身份完全一致；
3. `migrationFailed`：身份有效，但本地数据迁移失败，可 Retry；
4. `readyForSync`：迁移成功，等待 `.emergencyFire`；
5. `syncFailed`：专用同步失败或中止，可 Retry；
6. `succeeded`：controller 权威状态 `isSynced == true`；
7. `identityFailed`：Composition 身份缺失、未注册或不一致，终止恢复且不可进入普通同步。

上下文只服务当前 Restore 页面，不写入 SDK，不引入新的持久化表。

### 3.2 入网后身份决策

新增纯 Swift `DeviceRestoreEFCRecoveryPolicy`，将“扫描确认的 EFC 身份”和“Composition 身份”归约为明确结果：

- 精确匹配且仍为注册表中的 EmergencyController：允许迁移；
- Composition CID/PID 缺失：`identityFailed`；
- Composition 命中不同 EFC 产品：`identityFailed`；
- Composition 命中普通设备或未知产品：`identityFailed`；
- 非 EFC 扫描候选：保持普通恢复链。

`appendMessagesBack` 必须先按扫描分类分支：

- 扫描分类为 EFC：只执行身份验证、迁移和 Attention，不得落入普通恢复消息构建；
- 扫描分类为普通设备：保持当前普通恢复链。

身份失败时：

- 不迁移 EFC 数据；
- 不生成普通恢复消息；
- 不进入 `.devices` 或 `.emergencyFire` 同步；
- 将设备标记为终止失败并保持不可重新 Add 的选择状态；
- 不计入对 BLE OTA 回调的成功恢复 Node。

### 3.3 迁移失败 Retry

`syncBtnAction` 对 EFC 的处理顺序改为：

1. 从上下文找出 `migrationFailed`；
2. 使用保留的历史 Node、入网后 Node 和 Space 重新调用 `DeviceEmerFireStore.restoreDevice`；
3. 成功则更新为 `readyForSync` 并创建专用 sync entry；
4. 仍失败则保持 `migrationFailed`，不转入普通设备同步；
5. 将原有 `syncFailed` 且已持有 controller 的上下文直接加入专用队列。

迁移函数按地址幂等：成功后清除迁移失败，不重复创建默认 controller；新地址上若已有同一记录则继续复用。

`identityFailed` 是不可同步失败，不出现在 Sync Retry 的可执行集合中。若同一批次只有身份失败，不展示一个点击后无动作的 Sync Retry；设备行仍保持失败真值。

### 3.4 显式同步结果和自动 OTA 收口

内部同步流程统一返回显式结果：

- `succeeded`：所有目标设备满足权威成功条件；
- `needsAttention`：存在迁移失败、普通同步失败、EFC `isSynced != true`；
- `cancelled`：用户从同步页返回或中止。

EFC 队列规则：

- 单台同步成功且 `controller.isSynced == true` 后才处理下一台；
- callback 到达但 controller 仍未同步，按 `needsAttention` 处理；
- 用户返回时将当前项保留为 `syncFailed`，停止本轮队列，剩余项保持待同步并回到 Restore 页面；
- 不把返回事件当成队列完成成功。

普通同步规则：

- `syncSuccessCallback` 后按每个 `Node.needSync` 更新成功项；
- `backActionCallback` 返回 `cancelled`，即使部分 Node 已完成也不触发自动 OTA 完成；
- 已实际完成的普通 Node 可以保留 success，未完成项继续显示 Retry。

自动 OTA 最终规则：

- 只有显式结果为 `succeeded`，且不存在 `identityFailed`、`migrationFailed`、`syncFailed`、EFC `isSynced != true` 或普通 `Node.needSync`，才调用 `deviceRestoreCallback` 并返回 BLE OTA；
- 其他结果只隐藏 Automatic HUD、刷新 Restore 状态并留在当前流程；
- Restore 对外只报告权威成功的 Node，不能把已 Provision 但恢复失败的 Node 放入成功数组；
- 增加一次性回调保护，避免显式完成与 deinit 重复回调；
- 自动模式存在未解决失败时，deinit 不回调完成结果。

为保留当前普通同步页的自动重试次数，`SyncDevicesViewController` 新增一个可选的自动重试耗尽回调。Device Restore 设置该回调后，重试耗尽只隐藏 HUD 并保留失败页；其他调用方未设置时继续使用当前跳回 BLE OTA 的行为。

## 4. 文件与任务规划

### Task 1：纯 Swift 入网后身份和收口策略

**新建：**

- `SunSmart/Main/Device/Model/DeviceRestoreEFCRecoveryPolicy.swift`
- `Tests/Device/DeviceRestoreEFCRecoveryPolicyTests.swift`

**修改：**

- `SunSmart.xcodeproj/project.pbxproj`
- `scripts/check_device_restore_efc_support.sh`

测试先覆盖：

- 扫描 EFC 与同 CID/PID Composition 匹配；
- Composition 身份缺失；
- 不同 EFC PID；
- EFC 与普通产品交叉；
- 非 EFC 保持普通分支；
- 自动指定恢复仅在无未解决失败时允许报告完成；
- cancel、迁移失败、controller 未同步、普通 Node needSync 均必须留在 Restore 流程。

新增源码加入 SunSmart、Archipelago、SLG Sync Plus、SylSmart 四个 target。

### Task 2：锁定 EFC 分支并记录恢复上下文

**修改：**

- `SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift`
- `scripts/check_efc_controller_flows.sh`

先更新合约使当前实现失败，要求：

- EFC 分支由扫描后的 `ProvisioningDevice.deviceType` 或等价不可变分类决定；
- 入网后身份失败不能继续普通恢复消息链；
- 每个 EFC 新地址都有包含 old/new Node 的上下文；
- 身份失败不会写入成功恢复结果；
- 删除仅靠 `failedEmergencyFireRestoreMigrationAddresses` 表达全部迁移状态的方式。

实现后重新运行候选策略测试和 EFC flow contract。

### Task 3：迁移失败重新执行并进入专用同步

**修改：**

- `SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift`
- `scripts/check_efc_controller_flows.sh`

测试与合约要求：

- `migrationFailed` 上下文保留历史 Node、入网后 Node 和设备对象；
- Retry 必须先重新调用 EFC migration；
- 成功迁移后创建 `.emergencyFire` entry；
- 再次失败保持可重试状态；
- `identityFailed` 不进入普通或 EFC sync queue；
- 只有终止身份失败时，不产生无动作的 Sync Retry。

### Task 4：显式同步结果与自动 OTA 退出门禁

**修改：**

- `SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift`
- `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`
- `scripts/check_efc_controller_flows.sh`

测试与合约要求：

- EFC/普通同步的成功与 back/cancel 使用不同结果；
- `finishRestoreSyncRetryFlow` 必须消费显式结果并复核权威状态；
- 自动 `.specified` 只有全部权威成功才回调和 pop；
- back/cancel、自动重试耗尽、EFC `isSynced == false` 均不得调用完成回调；
- `deviceRestoreCallback` 最多调用一次；
- deinit 在自动未解决失败时不报告完成；
- 共享同步页的新增失败回调为可选值，其他调用方行为不变。

### Task 5：回归与交付验证

执行：

- `scripts/check_device_restore_efc_support.sh`；
- `scripts/check_efc_controller_flows.sh`；
- `scripts/check_efc_comprehensive_status_mapping.sh`；
- `scripts/check_efc_status_content_list.sh`；
- `scripts/check_efc_i18n.sh`；
- `git diff --check`，并单独检查未跟踪文件；
- generic iPhoneOS 构建 SunSmart、Archipelago、SLG Sync Plus、SylSmart。

不使用 Simulator，不修改 NordicSigMeshSDK，不创建 commit。

## 5. 验收矩阵

### 身份异常

1. 扫描为 `0x0A78/0x2131`，Composition 相同：进入 EFC migration 和专用同步。
2. 扫描为 EFC，Composition CID/PID 缺失：失败，不发送普通恢复配置。
3. 扫描为 EFC，Composition 为另一 EFC 产品：失败，不迁移配置。
4. 扫描为 EFC，Composition 为普通产品或未知产品：失败，不进入 `.devices`。

### 迁移 Retry

1. 首次迁移失败后 Retry 会再次执行迁移。
2. 第二次迁移成功后立即进入 `.emergencyFire`。
3. 第二次仍失败时保留失败状态和再次 Retry 能力。
4. 迁移成功不会创建重复 controller 或丢失旧 configuration。

### 自动 OTA

1. 普通同步全部成功：回调一次并返回 BLE OTA。
2. EFC 专用同步全部成功且 `isSynced == true`：回调一次并返回。
3. 普通同步页返回：留在 Restore，外层不移除待恢复 Node。
4. EFC 同步页返回：停止本轮队列，留在 Restore，外层不移除待恢复 Node。
5. 自动重试耗尽：保留失败同步页，不自行跳回 BLE OTA。
6. 混合普通/EFC 批次任一失败：不报告整批完成；已成功项保持成功状态。
7. 显式完成后页面释放：不会因 deinit 再次回调。

## 6. 明确不在本次范围

- 不修改 EFC vendor opcode、payload 或 Working Mode/Action 规则；
- 不重构全部 Restore 对外 callback API；
- 不修改 BLE OTA 的提示文案和现有国际化资源；
- 不改变普通设备、Gateway、Battery Power Switch、Dongle 的恢复内容；
- 不处理工程原有构建警告；
- 不进行 Git commit、push 或 merge。

## 7. 已确认决策

用户已确认方案 B，并按以下产品行为完成实现：

- 入网后 EFC 身份异常属于终止失败，不允许普通恢复或 Sync Retry；
- EFC 本地数据迁移失败属于可重试失败，Retry 先重新迁移；
- 自动 OTA 同步失败或用户返回时留在 Restore/Sync 流程，不向 BLE OTA 报告完成；
- 只有权威成功的 Node 才进入 `deviceRestoreCallback` 的成功数组。

实施结果与验证证据见 `docs/260803_1151_efc_restore_review_fixes_summary.md`。
