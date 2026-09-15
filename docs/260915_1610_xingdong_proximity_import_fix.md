# 兴东 Space 邻近照明导入误报修复

## 结论与根因

`Test1 / C00D` 的云端 Profile 类型为 8，邻近照明数量保存为 `21`；App 本地及 15 台相关设备缓存均为 `255`。现有 UI 最大滑条位置 `21` 表示 `ALL`，业务及设备使用 `255`。修复前 Profile 校验拒绝 `21`，App 导出明确记录了 `invalidRemoteProfile:C00D:invalidProfileRelay`。

配置保护使设备显示需要同步；随后通用同步入口又错误地使用了邻近照明导入失败文案。此次修复同时处理数据兼容和提示归因。详细数据证据见 [数据分析](260915_1600_xingdong_payload_analysis.md)。

## 实现

- `SpaceConfigurationIntegrityPolicy` 按最新要求将所有大于 `20` 的非负整数统一为 `255（ALL）`，`0...20` 保持原值。负数、非整数和错误类型仍校验失败。配置比较统一使用规范值，避免恢复基线、云端回读误判冲突。
- `SpaceSyncCleanupPolicy` 在生成拓扑前规范化云端 Profile 数量，沿既有导入修复记录保留原始数据与候选数据；成功应用后按现有机制等待修复上传确认。
- 导入预检使用规范值。`Profile` 的初始化和赋值同样规范化，涵盖云端导入、本地数据库读取及后续编辑；本地旧值不会进入拓扑校验造成持续阻断。正常保存后数据库使用 `255`。
- 完整导入成功后，既有 `finishImport` 流程解除历史保护状态。未放宽其他配置异常的自动解除条件。
- 通用配置不可用改为短提示 `configuration_sync_unavailable`，同步补充英文及简体中文；云端导入失败、文件导入失败、Profile 加载失败使用对应通用文案。实际拓扑编辑错误仍使用原有邻近照明校验提示。
- SDK、依赖、品牌配置与页面布局未修改。5 个品牌 target 共用本轮中英文本地化资源。

## 已完成的行为验证

| 验证 | 结果 |
| --- | --- |
| 真实云端样本的完整快照清理 | 500 台设备、1 处 ALL 兼容修复、0 个邻近照明同步任务；除数量 21→255 外，所有 JSON 字段保持一致 |
| 真实云端样本导入预检 | 通过 |
| 回归对照 | 使用修复前 HEAD 运行新增用例，在 ALL 导入兼容断言失败；修复后通过 |
| Profile 7/8 SQLite 往返 | 实际生产模型、导入/导出映射和 SQL 保存/重开/加载均保留 255；直接写入本地旧值 21 后也能正常读取、规范化并保存 |
| 保护与修复记录 | 历史 invalidProfileRelay 阻断在成功导入后解除；原始云基线与规范值相同，修复上传意图保留；重复规范化不再产生修改 |
| 通用同步保护失败 | 不发送 Mesh 命令、不执行准备或写回、不报告成功、不再误报邻近照明；保护解除后的新一轮同步可正常完成 |
| 既有拓扑、删除、跨 Space、恢复和上传回归 | 通过 |
| 数量范围与真实修改 | 最新规则将所有整数 >20 统一为 255，包含超出 UInt8 范围的整数；负数、小数、字符串、布尔及 null 仍校验失败；合法时间参数差异仍参与配置比较。规则扩展的验证见 [后续说明](260915_1614_proximity_relay_all_normalization_update.md) |

可复用验证入口：

- `scripts/check_space_sync_cleanup.py --snapshot <云端 JSON>`
- `scripts/check_proximity_scoped_import.py --snapshot <云端 JSON>`
- `scripts/check_profile_persistence.py <SDK 本地路径>`
- `scripts/check_space_recovery_receipts.py`
- `scripts/check_sync_execution_session.py`
- `scripts/check_path_topology_persistence.sh`

测试直接运行生产逻辑；SDK 对象、账户数据库路径、网络等边界按测试用途隔离。Profile 持久化使用临时真实 SQLite。私有完整 JSON 未复制到仓库。

## 构建与真机验证

最终代码已通过以下 5 个品牌构建：SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux。均直接运行 `xcodebuild`，使用 Debug、iphoneos、generic/platform=iOS、CODE_SIGNING_ALLOWED=NO；未使用 Simulator。构建仍有工程既有的 API 弃用、重复资源/编译项、未使用变量等警告。

中英文本地化语法检查及 `git diff --check` 通过。Profile Auto min 与 Night Calibration 持久化契约回归通过。为运行真实 Profile SQL 回归，修正了测试脚本过宽的源码提取范围，排除不参与该测试的跨 Space 查询和 Mesh 快照缓存；没有修改这些生产模块。

按用户最新指示，真机和界面体验由用户手动验证，已停止自动真机验证；未安装或启动测试 App，未操作现有业务 App。

## 仍需兴东现场验收

当前数据中还存在有效的时间参数差异：云端 `timeT2=5`、`timeT4=0`、`manualOverrideTimeout=5`，本地分别为 `1200`、`600`、`600`，General Scene 的相应时间也有差异。正常导入后仍可能需要 Profile 同步。

人工检查：

1. 联网使用修复版本重新进入兴东，等待云端完整导入成功，确认历史保护状态解除，不再出现邻近照明导入误报。
2. 检查 Test1 数量为 ALL，保留 15 个路径节点和 2 个区域成员。
3. 再次退出、进入，确认无重复兼容修复或邻近照明同步任务。
4. 检查真实时间参数同步符合云端有效配置；完成正常云同步后再导出，确认规范值和恢复状态持久化。

本轮未直接修改云端数据，也未执行兴东现场 500 台设备的 BLE/Mesh 同步。自动化逻辑回归与编译结果不替代完整业务闭环和人工体验验收。
