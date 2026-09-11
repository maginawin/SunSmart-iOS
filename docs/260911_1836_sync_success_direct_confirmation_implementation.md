# Site / Space 上传成功直接确认：实施结果

日期：2026-09-11。基于用户已确认的 `260911_1828_sync_success_direct_confirmation_plan.md` 实施。工作树基线为 `dffbaabc`，未提交 Git。

## 行为变化

- `/sitespace/sync/spaceprops` 与 `/sitespace/sync/siteprops` 经现有网络层判定成功后，直接确认本次 payload 的时间戳，不再执行成功后的配置 GET 比对。
- 确认时间不倒退；请求期间发生的新修改保持待同步。
- Site 时间与各 Space 的本地持久化分别确认，一个 Space 保存失败不撤销其他项已完成的确认。
- Site-only、Site 携带 Spaces、addSpaces、首次 Site 创建使用相同成功口径。首次创建继续处理响应内地址资源，并保留时区 pending 的按版本合并规则。
- 单个解绑复用直接确认；分享权限页批量解绑接入 CloudSynchronizationManager，避免使用回调时最新的 lastUpdate 提前确认修改。成功后再检查剩余待同步状态并继续解绑。

## 回执与保护

- accepted 与 verified 回执直接完成本地收尾，不调用 GET；旧 accepted 回执附带的 `uploadReadbackConflict` / `uploadReadbackUnconfirmed` 标记随收尾解除。
- prepared 等结果未知的回执仍走原有恢复路径；首次 Site 创建中断后的资源查询、上传前检查、权限恢复、正常页面刷新继续保留。
- 删除日志和本机恢复回执按本次提交时间确认，更晚操作保留。其他拓扑、导入或权限保护标记不会被批量清除。
- Space 数据库保存失败时恢复内存中的原确认时间和错误；状态文件保存失败时保留磁盘上的 accepted 回执，下次只重试本地收尾。
- 回读标记在清空 submission 之前清理，避免收尾中断后遗留没有回执可恢复的纯回读阻塞。
- 保留账号、区域、生命周期和 submission ID 的校验，不把旧回调应用到新提交。

## 修改位置

| 文件 | 内容 |
| --- | --- |
| `SunSmart/Common/Cloud/CloudSynchronizationManager.swift` | 新增 Site 本地确认方法，成功后直接确认各 Space，保留部分确认结果 |
| `SunSmart/Common/Data/SpaceConfigurationSafety.swift` | accepted 本地收尾、历史回执兼容、解绑前直接确认、保存失败处理 |
| `SunSmart/Main/Share/Controller/ShareAuthorityViewController.swift` | 批量解绑上传接入共享同步管理器 |
| `Tests/Group/SpaceRecoveryReceiptTests.swift` | 更新 accepted 语义，新增无 GET、并发版本、不同保护原因和部分持久化失败测试 |
| `Tests/Group/CloudUploadConfirmationTests.swift` | 执行生产 Site 确认方法，验证 Site-only、addSpaces、资源、时区和保存失败 |
| `scripts/check_space_recovery_receipts.py` | 接入 Site 生产方法与策略，增加状态写入失败注入及成功路径接线检查 |

未修改 SDK、依赖、target 配置、本地化或界面布局。

## 验证结果

| 验证 | 结果 |
| --- | --- |
| `python3 scripts/check_space_recovery_receipts.py` | 通过：生产 Site/Space 确认方法、无成功后 GET、旧 accepted 回执、请求期间修改、数据库/回执/状态文件失败、未知结果恢复、权限及生命周期 |
| `python3 scripts/check_proximity_scoped_import.py` | 通过：导入、删除、设备归属、恢复日志及 Site/Space 隔离 |
| `bash scripts/check_configuration_database_safety.sh <本次构建解析的 SDK 路径>` | 通过：真实 SQLite WAL 快照、事务回滚、不可用连接和旧表兼容 |
| 拓扑策略、生命周期策略、Space Trigger Zone follow-up、review regression、配置完整性策略 | 独立编译执行通过 |
| `SitePropsEditPolicyTests` | 通过，含首次创建时区 pending 与更新版本保护 |
| `git diff --check` | 通过 |
| SunSmart / Archipelago / SLG Sync Plus / SylSmart / Lumineux | 五个 scheme 均 `BUILD SUCCEEDED` |

五个构建均直接执行 xcodebuild，使用 SunSmart.xcworkspace、Debug、iphoneos、generic/platform=iOS、CODE_SIGNING_ALLOWED=NO；解析的 NordicSigMeshSDK 为远端 release `a6246b1`。没有使用 Simulator 或运行真机测试。

### 已确认的既有测试问题

完整 `check_path_topology_persistence.sh` 在第一项旧源码契约退出；独立执行其余项目时，另一个旧契约也失败：

1. `PathTopologyPersistenceContractTests`：`Space import must preflight proximity data before destructive apply`。
2. `ProximityLightingLifecycleContractTests`：`Import must parse and validate proximity topology before destructive node replacement`。

已分别从 HEAD 导出原始测试和其读取的原始源码到临时目录执行，复现相同断言失败，确认不是本次变更引入。未为使测试转绿而修改无关导入源码或旧契约；其余回归项目独立执行结果见上表。因此不宣称完整拓扑脚本全部通过。

## 验收边界

上述行为验证使用生产确认方法和受控网络/数据库边界，接线检查与 generic iOS 构建不能替代真实服务端、真机同步及解绑交互验收。按用户要求未开展真机测试，也未访问服务端修改数据。

回退后同步成功表示服务器接受请求，客户端不再通过该次成功路径验证服务器实际保存的配置内容。现有工作树中的其他分析文档保持原样。
