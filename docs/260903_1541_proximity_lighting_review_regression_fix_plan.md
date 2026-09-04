# 邻近照明 Review 回归修复计划

## 1. 结论

Review 提出的 6 个 P1 问题均成立，当前聚焦测试通过的原因是它们主要锁定拓扑计算、持久化顺序和同步页创建，没有覆盖以下运行时边界：

- Site 刷新把“服务器包含但 Space 导入失败”误当成“服务器不包含”。
- Group 删除的部分成功状态被整体回滚，破坏下一次退组任务生成。
- 邻近照明任务集合被错误地当成整个 Group 配置的同步集合。
- 设置了 `backActionCallback` 后，同步页的关闭责任转移给调用方，但新增删除入口没有履行该责任。

本轮只修复上述回归，不修改 NordicSigMeshSDK、不新增 Auth、不调整本地化或资源，也不重构其他同步流程。

## 2. 已确认的根因与修复语义

### 2.1 Space 导入失败不等于服务器删除

当前 `SpaceData.import` 在 Space 身份已解析、但邻近照明预检拒绝快照时返回空值。`SiteData.update` 的任务组只收集非空 Space，再用该集合判断服务器已删除的 Space，因此已有 editor/visitor Space 会被错误标记为 `waitDeleted`。

修复语义：

- Space 的“服务器存在性”和“本次快照能否应用”必须是两个独立结果。
- 导入结果显式携带服务器 Space ID、可应用的 Space 以及 applied/skipped/rejected 状态。
- Site 刷新用全部可识别的服务器 Space ID 判断删除；rejected 的 Space 不覆盖本地数据，但仍算服务器存在。
- 只有服务器列表明确不含某个本地 Space ID 时，才允许将 editor/visitor Space 标记为 `waitDeleted`。
- 若服务器条目损坏到连 ID 都无法可靠解析，本次快照不执行缺失 Space 删除判定，采用保守保留，避免坏数据触发批量误删。
- 文件导入入口继续把 rejected 视为失败，不能因结果模型扩展而误报成功。

预计修改：

- `SunSmart/Common/Data/ImportData.swift`
- `SunSmart/Main/Site/Controller/SiteViewController.swift`（仅适配文件导入结果）

### 2.2 Group 删除保留逐设备真实退组结果

`getNodeExitMessageHandles` 会先把目标 Node 置为 `exitFailure`；订阅删除成功后 Node 变为 `none`，失败则保持 `exitFailure`。当前 `deleteGroup` 在任一成员失败时把所有 Node 恢复为删除前状态，导致失败 Node 不再产生 `unsubscribeGroup`，成功 Node 反而可能产生 `subscribeGroup`。

修复语义：

- 成员退组阶段发生部分失败时，不恢复整组的原始 `groupState`。
- 成功 Node 保持 `none`，失败 Node 保持 `exitFailure`，以 Mesh 操作结果作为重试依据。
- `deleteFailedCheck` 明确只把 `exitFailure` Node 作为 `outNodes`，避免任何已成功退出的设备进入重试页。
- Group 和原逻辑拓扑在所有必要任务成功前仍不做最终本地删除；本次不改变既有两阶段删除提交边界。
- 邻近对端同步或最终本地提交失败属于后续阶段，不与“成员退组部分失败”混用状态回滚；实现时逐个检查现有恢复点，禁止把已确认的设备 ACK 状态伪造回旧值。

预计修改：

- `SunSmart/Main/Group/Model/GroupServer.swift`
- `SunSmart/Main/Group/Controller/GroupViewController.swift`

### 2.3 普通 Profile 保存必须独立失效通用同步缓存

`ProximityLightingLifecycleCoordinator` 只根据旧、新邻近拓扑计算候选地址。现有非邻近 Profile 的亮度、超时等字段变化不会产生邻近候选地址，因此协调器不会清除 Group 成员的通用同步缓存。若 `needSync` 之前缓存为 false，Profile 页面会直接退出。

修复语义：

- `GroupViewController` 在 Profile 数据保存完成后显式调用 Group 的通用同步状态失效逻辑。
- 缓存失效发生在保存回调返回前，确保 `ProfileSettingsViewController` 随后的 `needSync` 判断读取新配置重新计算。
- 邻近照明协调器继续只负责拓扑候选和补充任务，不扩大为所有 Group 配置缓存的隐式所有者。
- Profile 类型切换、传感器保护上下文和跨 Group 邻近任务继续沿用现有流程。

预计修改：

- `SunSmart/Main/Group/Controller/GroupViewController.swift`

### 2.4 通用 Group 编辑不能只看邻近任务集合

`GroupAddViewController.finishGroupEdit` 目前仅根据 `lifecycleResult.syncDatas` 决定是否进入同步页。该集合只表示邻近照明差异，普通 Profile 变化时通常为空；旧流程中的通用缓存失效又已丢失，因此保存后直接结束。

修复语义：

- `applyGroupInfoEdits` 保存 Profile 后显式失效 Group 成员的通用同步缓存。
- `finishGroupEdit` 的进入条件改为“Group 存在通用待同步任务，或存在补充邻近照明任务”，两者互不替代。
- 进入同步页后仍使用 `.group` 生成完整 Group 配置任务，并通过 `supplementaryProximityLightingSyncDatas` 追加跨 Group 邻近任务。
- 仅修改名称或图片且设备配置没有差异时，重新计算后仍可正常结束，不制造空同步页。

预计修改：

- `SunSmart/Main/Group/Controller/GroupAddViewController.swift`

### 2.5 永久删除先关闭同步页，再恢复原完成回调

`SyncDevicesViewController` 在存在 `backActionCallback` 时不会自行关闭；当前 `DeviceProtocol.syncPermanentDeletionPeers` 的成功和返回回调只调用外部 completion。结果是 Device Others 停在同步页，而 DeviceBase/Gateway 的原 completion 只弹出了同步页，没有继续关闭已经删除的设备详情。

修复语义：

- 在 `DeviceProtocol` 新增的删除邻居同步入口内建立一个共享、一次性的结束闭包。
- 成功与用户返回都先确认当前顶层控制器是该同步页并将其关闭，再调用原 completion。
- completion 的既有职责不变：Device Others 刷新列表，DeviceBase/Gateway 按原来的延迟和页面关闭语义继续执行。
- 不修改 `SyncDevicesViewController` 的全局 callback 契约，避免影响 Profile、成员、Restore、EFC 等大量既有入口。

预计修改：

- `SunSmart/Main/Device/Model/DeviceProtocol.swift`

### 2.6 批量删除的邻居同步页必须可退出

`DeviceLightsViewController.syncDeletionPeersIfNeeded` 与上一个问题相同：设置了两个 callback，却没有在任一路径关闭同步页；其中取消强删后的 completion 还是空闭包。

修复语义：

- 成功和返回统一走一次性结束闭包。
- 先关闭当前同步页回到批量设备列表，再执行原 completion；空 completion 也必须关闭页面。
- 保留当前删除结果、列表刷新、完成提示和失败重试语义，不改变批量删除的数据处理。

预计修改：

- `SunSmart/Main/Device/Lights/Controller/DeviceLightsViewController.swift`

## 3. 回归测试计划

扩展现有邻近照明聚焦门禁，优先新增一个针对本次 review 的源码契约测试，并接入 `scripts/check_path_topology_persistence.sh`。自动化至少锁定：

1. Site 删除判定使用服务器存在 ID，而不是只使用成功导入的 Space；known-ID rejected 结果不得进入 `waitDeleted`，真正缺失仍可进入。
2. Group 成员部分退组失败分支不得整体恢复旧 `groupState`；重试页只接收 `exitFailure` Node。
3. Group Profile 保存后、回调返回前执行通用同步缓存失效。
4. 通用 Group 编辑的同步页进入条件同时检查通用 Group 待同步状态和邻近补充任务。
5. `DeviceProtocol` 与批量灯具删除的成功、返回两条 callback 均先关闭目标同步页，再执行 completion。
6. 现有生命周期、拓扑、持久化、Space Trigger Zone follow-up 合约全部继续通过。

自动化验证顺序：

1. 运行新增回归测试，确认当前代码先出现 RED。
2. 完成最小修复后运行 `zsh scripts/check_path_topology_persistence.sh`。
3. 运行 `git diff --check`。
4. 依次执行 SunSmart、Archipelago、Lumineux、SylSmart、SLG Sync Plus 的 Debug generic iPhoneOS 无签名构建；不使用 Simulator。

## 4. 真机与人工验收

自动化和构建不能证明 BLE/Mesh ACK、页面栈和最终设备状态，发布前需覆盖：

- 服务器仍包含一个本地 editor/visitor Space，但其邻近拓扑版本不支持或数据无效：刷新后 Space 保持正常且本地最后正确数据不变。
- 服务器确实移除该 Space：刷新后仍正确进入 `waitDeleted`。
- 删除含两台设备的 Group，一台退组成功、一台失败：重试页只展示失败设备的退组任务，不出现成功设备重新订阅；重试成功后再删除 Group。
- 已缓存为 Synced 的普通 Profile 修改亮度、超时等字段：保存后立即进入 Sync Device(s)，设备收到新配置。
- 通用 Group 编辑修改普通 Profile：同步页完整包含通用 Group 任务；仅名称/图片变化且无设备差异时不出现空任务页。
- Device Others、DeviceBase、Gateway 通过共用删除流程产生邻居任务：成功和手动返回后都先离开同步页，再按各自原语义刷新或关闭。
- 灯具批量删除在全部成功、部分失败后取消、强制删除三条分支产生邻居任务：同步成功或手动返回都能回到设备列表。

## 5. 实施边界与交付标准

- 不修改 NordicSigMeshSDK；本地 SDK 仅用于核对 `Group.nodes`、`Node.groupState` 和订阅更新语义。
- 不新增或修改用户可见文案，因此预计无国际化改动。
- 不改 `SyncDevicesViewController` 的通用自动关闭行为。
- 不提交、不推送，不触碰无关文件。
- 交付时分别报告：聚焦测试、五 target generic iPhoneOS 构建、尚未完成的真实服务器/Mesh/UI 验收，不能用编译成功代替端到端完成。

