# 云端版本更新时完整替换本地 Space：实施报告

## 已实现行为

用户已确认采用云端较新版本覆盖本地的策略，实施依据为 `260910_1614_remote_newer_space_overwrite_proposal.md`。开始实施时工作区无未提交改动，基线 HEAD 为 `4df15971`。

当前行为：云端 `updateTimestamp` 严格大于最新本地 `lastUpdate` 和待确认提交时间戳时，校验并采用目标 Space 的完整云端配置，结束旧提交。相等或较旧时维持原来的校验及冲突行为。

对本次日志，若现场本地没有后续编辑、完整详情和密钥/拓扑校验通过，云端 1789011179 将替换本地 1788859046，App 中目标 Space 变为 0 个设备，Group Path/Zone 采用云端空配置，旧两设备提交不再反复回读。

本轮没有调用生产接口或使用真机；上述现场结果为实现后的预期行为，不是该 iPad 已恢复的声明。

## 共享同步与入口

- `SpaceConfigurationIntegrityPolicy` 提供严格版本判断与完整详情结构检查。显式空数组允许清空，缺少关键数组、无效时间戳或非法配置不能冒充空数据。
- `SpaceConfigurationSafety.resumeUpload` 在回读发现云端更新时调用受控导入，区分原提交确认、云端配置采用和旧任务失效三个结果。
- `CloudSynchronizationManager` 接收覆盖后的恢复代际，避免把本次合法覆盖误当旧回调。整个任务继续检查生命周期；较新编辑导致预检失效时取消旧完成逻辑，不回写旧模型。
- Site 列表、自动重试沿用共享同步任务；Space 内的冲突按钮先尝试共享恢复，符合条件时自动完成，不增加逐次确认弹窗。
- Site 同步仍有其他 Space 或 Site 属性需要上传时，排除已经采用云端且未再次编辑的 Space，避免顺带重传。覆盖后发生新编辑的 Space 仍可正常上传。
- 普通云端导入遇到更新版本时获取 spaceInfo 完整详情，不能用 Site 摘要的空节点数组直接清空本地。文件导入显式沿用原有路径，不静默替换成服务端内容。

## 全量落地与保护范围

复用 Space 导入实现并加强校验，覆盖目标 Space 的设备、Group/Profile、Path、Space Trigger Zone、场景、日程、Switch、Emergency/Fire Controller 以及既有导入合同中的 Space 属性。

- Node、Group、Scene 清理限定目标子网，保留其他 Space 和本地 Provisioner。
- 场景扩展、日程、Switch 及其八键侧表、Emergency/Fire Controller 的删除和保存失败会使导入失败，不能忽略后继续报告完成。
- Node 添加失败不再被吞掉；保存后核对节点集合（包括空集合）、Group、Scene、Schedule、Switch 和 Controller 身份集合，以及持久化拓扑。
- 对 Schedule/Scene/Switch/Controller 的不可解码或重复身份载荷拒绝破坏性替换，Controller 显式配置解析失败也拒绝。
- Mesh 密钥仍通过既有身份/冲突校验；不修改 SDK 或依赖，不整体还原 Mesh 数据库，不倒退本机 Sequence Number/IV Index。
- 此路径不发送 Reset，也不自动发起 Proximity Lighting 设备配置同步。被本地清除记录的实体设备可能仍然保持配网状态。

## 旧提交、备份和中断恢复

1. 完成预检后，通过现有 SQLite checkpoint 备份 App/Mesh 数据，在旧恢复目录保存恢复状态；旧提交与删除日志留在原目录。
2. 为本次云端覆盖建立新的恢复目录及 generation，在切换状态指针之前写好 `selected-cloud.json` 和 `pending-import.json`。
3. 新目录不继承旧待上传提交或待重放删除日志；旧回调因 generation 变化失效。正在执行的设备删除先完成，覆盖暂不进入落地阶段。
4. `cloudReplacementTimestamp` 持久化标记导入待完成。重启或重试时继续已选定载荷，不重新上传旧设备，也不临时换成另一份云端版本。
5. 覆盖完成后才更新基线并解除相应配置冲突。恢复状态最终保存失败、临时 pending 文件已删除但状态尚未提交等中断窗口，可以从保留的 selected-cloud 文件继续。
6. App 数据库事务失败时恢复内存中的本地版本标记，使后续重试能通过版本一致性检查；不通过回滚整份 Mesh 数据库恢复。
7. 用户之后明确删除设备时，暂停并留存所选云端快照，清除它的活动恢复标记，允许既有删除流程继续。该删除意图不会因后续自动恢复而被旧云端快照复活。

独立的非配置错误仍保留，不以覆盖成功为由无差别删除所有错误。备份用于追溯和后续恢复，本轮没有新增备份恢复界面。

## 验证

新增 `SpaceNewerCloudReplacementTests.swift`，通过现有 runner 执行生产恢复方法、生产导入预检前段、生产 Node/Group/Scene 清理循环、保存后节点集合判断和 Site 上传筛选表达式；网络、Mesh 落地和部分数据库边界使用替身。

覆盖：两设备到空配置、非空配置替换、旧 generation 失效、旧删除日志隔离、其他 Space/Provisioner 保留、残留节点检测、相等/较旧版本、旧提交之后的新本地编辑、等待期间版本变化、摘要转详情、缺少关键字段、访客权限变更、活动删除、明确删除中止恢复、保存失败、重启恢复及独立错误保留。它们不是完整 App 导入或真实服务器/UI 验收。

| 验证 | 结果 |
| --- | --- |
| `bash scripts/check_path_topology_persistence.sh` | 通过，含拓扑、生命周期、导入和恢复回归 |
| `python3 scripts/check_space_recovery_receipts.py` | 通过，含本轮新增覆盖与中断恢复测试 |
| `python3 scripts/check_space_mesh_keys.py` | 通过，密钥冲突、修复持久化和 Site 聚合边界 |
| `python3 scripts/check_switch_record_scope.py` | 通过，Switch/侧表作用域、失败回滚和删除恢复 |
| `bash scripts/check_configuration_database_safety.sh <resolved-sdk-checkout>` | 通过，真实 SQLite WAL checkpoint、隔离、失败与事务回滚 |
| SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux generic iPhoneOS 构建 | 最终代码五个品牌全部通过，退出码均为 0 |
| `git diff --check` | 通过 |

构建直接使用 xcodebuild，Debug、iphoneos、generic/platform=iOS、CODE_SIGNING_ALLOWED=NO；未使用 shell 包装、日志重定向或 Simulator。解析到 NordicSigMeshSDK release `a6246b1`。

构建仍有既有资源同名、重复 Compile Sources、Info.plist 资源阶段和弃用 API 等警告，本轮未改动这些无关项。未执行 Git 提交或推送。

## 验收边界

未执行生产服务器操作、真机 Mesh/蓝牙或 UI 验收。后续现场应检查：点击 SYNC 后出现 adopting newer cloud 诊断，本地设备和拓扑与详情一致，失败提示消失，重新进入或重启后仍保持云端版本，且没有为被覆盖的旧提交发起上传。

该策略明确允许丢弃本地未同步配置；时间戳不证明云端数据更完整，也不提供服务端并发写入的原子版本保护。最初产生云端空配置的上游原因不在本次修复范围内。
