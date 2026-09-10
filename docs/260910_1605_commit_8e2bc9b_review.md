# 提交 8e2bc9b 审核

## 范围与结论

- 对比 `8e2bc9b^` 与 `8e2bc9b`，共 55 个文件；重点审核密钥导入/导出、恢复回执、设备与 Space 删除、Switch 作用域及其调用方。
- 结论：存在 3 项需要修复的运行时回归，不能仅凭现有测试和构建通过判定提交正确。
- 本轮未修改业务代码、测试、SDK 或依赖，也未调用生产接口、操作设备或提交 Git；只新增本审核文档。补充复现在临时目录执行，未写回仓库测试。

## 1. P1：残留订阅阻断 Switch 强制删除

位置：`SunSmart/Common/Data/DevicePermanentDeletionCleanup.swift`，492–493 行。

离线设备或解绑失败的设备仍订阅开关虚拟组时，真实 SDK 的 `Group.isUsed` 返回 true。强制删除最终仍进入同一个 `complete`，仅解除手机本地节点订阅后要求组完全无人使用，因而在删除 Switch 行之前返回 false。

此时删除回执已写入且未完成，`isBlocked` 为真；Switch 页的 `canUseMesh` 又拒绝阻断状态，联网后也不能直接通过正常解绑流程解除这一循环。应将确认后的记录移除与残留虚拟组/设备订阅的后续清理解耦，保留必要的重试信息，而非继续以远端解绑结果阻断 Force Delete。

证据：

- 已核对工程锁定的 SDK 提交 `a6246b1`：`Group+MeshNetwork.swift` 的 `isUsed` 检查节点模型的发布及订阅；普通开关和八键开关均有真实模型订阅路径。
- 在现有临时 SQLite 执行测试中，仅把目标私有组替身的 `isUsed` 改为 true，执行生产删除代码，得到：删除返回 false、Switch 行仍为 1、pendingCleanup 为 true。
- 原测试的组替身默认 `isUsed = false`，因此没有覆盖该常见失败条件。

## 2. P1：活动密钥快照过期被升级为持续同步阻断

位置：`SunSmart/Common/Data/ImportData.swift`，1755–1758 行；共享检查位于 `ExportData.swift`，78–81 行。

活动 Space A 的网络加载后，独立导入 Space B 可以合法补齐同 Site 的密钥。A 的活动对象不会因此同步刷新。再次导入 A 时仍优先复用活动对象，完整清单比较返回 `staleSnapshot`，随后被 `meshKeyFailure` 保存为持久阻断；后续上传也会被导出入口拒绝。普通重试继续选中相同旧对象，不能恢复。

应保留防止旧快照覆盖数据库的检查，在调用协调层做有界的新鲜快照校验/刷新或重试，不把可恢复的缓存过期直接当成真实密钥故障永久阻断。

证据：生产 `SpaceMeshKeyStore` 与策略的临时执行复现中，A 加载后经独立对象导入完整 B 密钥，随后对同一活动 A 连续三次协调均返回 `staleSnapshot`；仅重新加载 A 的网络对象、保持同一输入，即可成功，无实际密钥冲突。提交内的待实施快照修复计划没有改变当前调用链这一行为。

## 3. P2：节点删除清理丢失所有活动 Group 的日程绑定

位置：`SunSmart/Common/Data/DevicePermanentDeletionCleanup.swift`，255–261 行。

新的清理路径使用独立持久化网络，并把其中的 `saved.info` 整体赋给活动网络的所有 Group。`GroupInfo.load` 不加载运行时 `bindSchedules`，默认值为空；后续重新加载 `manager.schedules` 不会回填 Group 的绑定数组。

因此在有 Group/Scene 关联日程的 Space 删除任意节点后，`getNeedSyncScheduleDataNodes` 会对仍存在的日程返回空任务；Group 添加设备及 Restore 使用的 `getNodeSyncDataMessageHandles` 也会漏发相应日程。应在发布新的 GroupInfo 时重建绑定关系，不能只刷新 manager 的日程列表。

证据：核对了实际 SQL 加载实现、GroupInfo 默认值、日程同步消费者及通知处理链。在临时替身边界上执行生产缓存刷新片段和生产日程任务筛选方法，任务数从 1 变成 0，而 manager 的日程数仍为 1。该复现是方法级执行，不是完整 SDK/真机验收。

## 验证记录

已通过：

- `python3 scripts/check_space_mesh_keys.py`
- `python3 scripts/check_switch_record_scope.py`
- `python3 scripts/check_space_record_removal.py`
- `bash scripts/check_path_topology_persistence.sh`，包含 scoped import、删除执行和恢复回执测试。
- 三组本轮临时补充复现，分别验证上述遗漏条件。
- 英文与简体中文 Localizable.strings 的 `plutil -lint`。
- 提交差异的 `git diff --check`。
- project.pbxproj 的前后行多重集合完全一致，本次该文件仅调整条目位置，未改变 target 配置或文件成员关系。

构建采用直接 `xcodebuild`、Debug、generic iPhoneOS、禁用签名。SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux 五个 scheme 均构建成功，退出码均为 0。构建使用锁定的 SDK `a6246b1`，未运行 Simulator。

自动化替身及编译结果不等于真实服务端删除、Mesh Reset、重连收敛或 UIKit 实际布局验收。本轮没有进行上述现场验证。
