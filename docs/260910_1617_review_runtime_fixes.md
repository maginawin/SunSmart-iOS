# 三项运行时审核问题修复

本次修复针对 `8e2bc9b` 审核中的开关强制删除、活动密钥快照过期和删除后的日程绑定遗漏。修改集中在共享数据层及回归测试；保留工作区原有的两份分析文档。

## 修复行为

1. **Switch 强制删除与残留组清理解耦**：先持久化待清理地址，再事务性删除 Switch、八键开关扩展记录并更新计数与上传时间戳。残留设备订阅或 SDK 组删除失败不会阻止记录删除。`SpaceDeletionJournal.pendingVirtualGroupAddresses` 单独保存后续工作，不参与 `needsCleanup`、`hasReceipts`，也不随上传确认丢失；维护完成回执写入失败可再次重放，不新增同步阻断。
2. **密钥过期快照执行一次刷新重试**：共享 `SpaceMeshKeyStore.reconcile` 保留完整清单比较，发现过期后读取最新持久化清单，验证已有密钥、绑定、刷新阶段一致，再补齐新增密钥。活动网络对象及其节点/组对象继续保留，刷新过程不保存其旧 Site 元数据。重试仍发现过期时退出本次操作，`meshKeyFailure` 不为 `staleSnapshot` 新增持久阻断。已有密钥被删除、修改或出现冲突时仍需检查，成功协调会沿现有入口清除旧密钥阻断。
3. **删除后重建 Group 日程绑定**：替换活动 `GroupInfo` 时，以同一次加载的日程列表及保存的 Group 地址、待删除 Group 地址、Scene 关联重建 `bindSchedules`，再发布 `manager.schedules` 并清理节点同步缓存。

SDK `MeshAPI.createGroup(..., isVirtual: true)` 在锁定版本中使用普通组地址并设置业务标记，故维护队列按 Space 及组地址保存。重放会重新检查是否被新开关引用、是否属于其他 Space、是否仍被模型使用；条件不满足时保留组及待清理信息。仅在引用消失后清理，不向离线设备发送未经确认的解绑命令。

## 回归证据

- `python3 scripts/check_space_mesh_keys.py`：通过。覆盖活动 A 加载后独立导入 B、同一活动对象连续三次协调、后续保存保留 B 密钥、一次刷新重试上限、真实冲突及保存失败。
- `python3 scripts/check_switch_record_scope.py`：通过。执行生产 Switch SQL/事务/删除入口，覆盖 `isUsed == true`、组删除失败、扩展表及计数、重启和上传确认后的重放、新开关/跨 Space 引用保护，以及持久化组已删除但活动缓存尚存的恢复。
- `bash scripts/check_path_topology_persistence.sh`：通过，包含 scoped import、删除执行、拓扑及恢复回执测试。新增日程用例执行生产 `getNeedSyncScheduleDataNodes`，验证 Group/Scene 的同步任务、待删除日程任务保留，且无关日程不绑定。
- `python3 scripts/check_space_recovery_receipts.py`：通过，覆盖缓存过期不新增阻断、真实密钥冲突仍阻断、独立组维护不影响同步，以及原有回执和权限隔离。
- `python3 scripts/check_space_record_removal.py`：通过。
- `zsh scripts/check_device_permanent_deletion_cleanup.sh`：通过。
- `git diff --check`：通过。

将三组新增回归分别应用于修复前的 `HEAD` 生产实现，均在目标条件上按预期失败：强制删除返回失败；无冲突过期密钥协调失败；Group/Scene/待删除日程绑定丢失。基线执行只在临时测试抽取时读取 `git show HEAD:...`，没有回滚或覆盖工作区文件。

测试边界为生产方法与持久化/SDK 替身，Switch SQL 使用临时 SQLite；不代表完整 SDK、Mesh 或服务端现场验收。

## 构建与范围

构建均直接运行 `xcodebuild -workspace SunSmart.xcworkspace`，采用 Debug、`-sdk iphoneos`、`-destination generic/platform=iOS`、`CODE_SIGNING_ALLOWED=NO`，使用锁定的 NordicSigMeshSDK `a6246b1`。

SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux 五个 scheme 的最终源码均构建成功，退出码均为 0。SunSmart 和 Archipelago 在最后一次共享代码调整后补做了构建复核。

没有修改 SDK、依赖、品牌配置、本地化或 UI。未执行 Simulator、真机或生产服务端验证，未提交 Git。
