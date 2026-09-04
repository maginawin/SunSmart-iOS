# Group 移除流程 unknown Scheduler 清理修复总结

## 修复结果

已修复 Cloud 导入等场景下 Scheduler 分 Model 缓存未知时，Group Members 退组和整组删除可能跳过设备端定时清理的问题。

本次保留 `TimedSchedulerDeletePolicy` 的安全边界：unknown 状态仍不能直接判定删除。修复落在 Group 移除编排入口，通过权威读取把 unknown 收敛为 known 后，再生成同步与删除差量。

## 业务改动

### Group Members

- 保存时只对退出节点检查 Scheduler Model 缓存。
- 存在 unknown Model 时，先通过现有 `ScheduleServer.readUnknownSchedulerState` 完整读取 Scheduler Register 和 Action。
- 读取成功后才进入原有 `performSave`，因此读取发生在动能开关 pending-removal 保存、Proximity Lighting lifecycle commit、`.exitFailure` 标记和同步页创建之前。
- 读取期间禁用 SAVE，避免重复提交。
- 读取失败或 Mesh 不可用时留在成员编辑页，不修改成员、拓扑、预配置或开关代理状态，并允许再次保存重试。

### 整组删除

- `GroupServer.deleteGroup` 对组内 unknown 节点执行同一权威读取。
- 读取成功后的原删除流程拆入私有 continuation。
- lifecycle transaction、节点退出消息和本地 Group 删除均位于读取成功之后。
- 读取失败只进入现有失败回调，不产生部分删除。

### 保持不变的语义

- Group Target 日程在权威数据确认有效后生成删除任务。
- Device Target 日程继续按退出后的 ordinary Scheduler Owner 规则迁移。
- 已知为空的 Scheduler Model 不产生多余删除写入。
- 后续日程迁移发送失败是否阻断退组，继续使用原有 `TimedSchedulerGroupMemberExitStepPolicy`，本次未改变。

## 回归覆盖

- 新增所有 Scheduler Model 均 unknown 的 Cloud 导入策略用例。
- Timed Scheduler 集成契约新增 Group Members 源码输入，锁定权威读取成功后才能调用 `performSave`。
- 锁定整组删除的权威读取必须早于 lifecycle transaction 和 `groupDeleteNodes`。
- 保留 unknown 加旧兼容 Entry 有效时不能直接删除的原有契约。

## 验证结果

- `zsh scripts/check_timed_scheduler_single_owner.sh`：通过。
- `bash scripts/check_path_topology_persistence.sh`：通过。
- `git diff --check`：通过。
- generic iPhoneOS Debug、关闭签名构建：
  - SunSmart：通过。
  - Archipelago：通过。
  - SLG Sync Plus：通过。
  - SylSmart：通过。
  - Lumineux：通过。

Lumineux 初次构建因本地缺少 `Pods-Common-Lumineux` 生成文件失败；按现有 Podfile 执行 `pod install` 后构建通过。没有依赖版本变化，CocoaPods 对工程文件产生的机械重排已还原，未留下额外已跟踪配置改动。

## 尚待真机验收

自动化与构建不能证明设备定时已停止。仍需使用 Cloud 导入数据和真实 Mesh 灯具完成以下验证：

- Group Target 日程下退出 Group 后，读取全部 Scheduler Model 的 0～15 Entry，确认旧 Entry 已清除且不再触发。
- Device Target Turn On 日程退出自动 Group 后，确认从 Light LC Scheduler 正确迁移到 ordinary Scheduler。
- 覆盖全 unknown、部分 unknown、ACK 超时、断连、Mesh busy 和多节点部分读取失败。
- 确认权威读取失败时 App 成员关系与 Proximity Lighting 拓扑均未提前提交。

## 改动边界

本次未修改 NordicSigMeshSDK、依赖版本、项目 target 配置、资源或本地化文件，也未触碰工作区中既有的 Cloud/Proximity Lighting 未提交改动。
