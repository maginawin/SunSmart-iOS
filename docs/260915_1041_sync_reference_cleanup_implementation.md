# 同步失效引用清理实施与验证

## 范围

按用户确认的“三类残留自动清理，并保留现存设备必要收尾任务”方案实施。前序分析见 [问题分析](260915_1004_space_test_sync_failure_analysis_plan.md) 与 [确认方案](260915_1012_sync_validation_stale_reference_cleanup_plan.md)。

## 已实现

- 完整 Space 快照纯校验：缺失设备、缺失 Group、不适用 Profile 的路径/Zone 引用清理；保留路径槽位、其他成员和设备观察状态。
- 同步准备协调器：来源/权限/版本检查、checkpoint、清理意图、双存储读回、真实删除 journal 收尾、分类解除阻塞及云端待上传标记。
- 云端导入保存原始响应及对应候选快照；中断重试继续保留本地清理意图与原始授权基线。
- 场景、日程、Group 扩展、传感器模板和开关目标的相关失效引用收敛；现存设备的删除/解绑任务继续保留。
- 无 Group 对象的订阅删除使用 SDK 标准消息解析接口；FEFD/FEFE/FEFF、虚拟组保持有效。Group 扩展清理也计入现存虚拟组，并保护仍被其他组引用的 Profile 行。
- SDK 的普通订阅回执处理会先查 Group，Group 丢失时不会更新订阅缓存。因此在 App 的受保护回调内，核对成功状态、旧组地址、元素地址、模型标识和当前设备实例后，更新对应订阅；保存失败恢复原缓存继续重试。
- 无 Group 且仍待退出的设备，保留普通场景删除、传感器停止发布、旧灯控场景/条件删除、必要默认状态恢复及 PIR 收尾。退订依赖先前删除步骤完成，不通过清空观察数据伪造完成。
- 设备同步计划构建前准备，Profile/对象变更时停止旧计划并重建，旧响应不确认新配置；临时禁用的 PIR 按当前目标完成收尾。
- Site Zone 仅移除完整可读 Space 中确认失效的成员，保留未知成员、其他成员和扩展字段，使用原有 pending/POST/GET 确认流程；历史无效成员的设备差异改由当前完整目标和观察状态恢复。Site 存储读取失败时暂缓生成覆盖性邻近照明任务。
- 新文件加入 SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux 五个 target。

此次复用现有本地化 Key，没有新增用户可见文案、资源、依赖或 Auth 信息；未修改 NordicSigMeshSDK。清理接入 Space 入口、云同步准备、设备任务构建/失效重建和 Site Zone 同步准备；同步状态读取及调试导出保持只读。

## 原始数据验证

使用生产 `SpaceSyncCleanupPolicy` 对原始两份 JSON 运行离线探针，结果如下：

| 输入 | 自动清理 | 节点结果 | 第二次校验 |
| --- | --- | --- | --- |
| App 导出 | C00D 的 `ineligibleGroup`，清除 Profile 1 下残留邻近照明路径 | 保留本地 1 个节点 L2 | 无新修改 |
| Cloud 响应 | 同一 C00D 残留 | 保留原响应的 2 个节点 | 无新修改 |

跨快照基线验证：

- 没有 L1 删除依据时，两边基线仍不一致，不忽略设备数量差异。
- 在明确排除 L1 UUID、模拟“删除 journal 已证明该实例被删除”的条件下，两边基线一致；两个旧版遗漏的 Profile 默认字段不再形成假冲突。
- DEBUG JSON 没有完整删除 journal，因此上述条件验证不能证明现场 journal 的实际阶段。运行时仍核对 journal、当前节点身份/地址和版本后再收尾。

该策略不会直接从 Cloud 响应删除 L1。避免旧云端恢复本地已删除设备，仍由真实删除记录、原始授权基线和本地待上传保护共同完成。

## 自动化验证结果

下列检查均已通过，包含新增场景及原有相关回归：

| 检查 | 主要覆盖 |
| --- | --- |
| `python3 scripts/check_space_sync_cleanup.py` | 缺失设备/Group、Profile 1～8、路径槽位、观察状态保留、虚拟组/特殊地址、重复地址/损坏输入拒绝、幂等 |
| `python3 scripts/check_missing_group_hardware_cleanup.py` | 无组场景/Profile 收尾、真实观察状态保留、失败及错模型回执拒绝、持久化失败恢复、成功回执仅删除旧组订阅 |
| `python3 scripts/check_sync_task_builders.py` | 退订在必要删除任务之后、关闭旧功能任务保留、原有 Profile/日程/开关/网关依赖及结果判断 |
| `python3 scripts/check_sync_execution_session.py` | Profile/节点变更后的旧回调失效、停止后重建、重试、PIR 补偿、取消及跨页面执行顺序 |
| `bash scripts/check_site_trigger_zones.sh` | Site 成员清理、schema 兼容、未知成员/字段保留、权限、冲突、持久化及拓扑 |
| `bash scripts/check_path_topology_persistence.sh` | 完整拓扑/生命周期/持久化契约；同时运行导入、删除和云回执恢复回归 |
| `python3 scripts/check_proximity_scoped_import.py` | 自动清理作用域、删除已移除但页面仍持有 Context 的恢复、有效设备观察状态及真实差异保留 |
| `python3 scripts/check_space_recovery_receipts.py` | 清理保存失败重试、原始云端基线、导入中断、保留待上传状态、权限/版本及其他阻塞隔离 |
| `python3 scripts/check_sync_devices_row_display.py`、`python3 scripts/check_sync_devices_progress.py` | 行复用、失败重试、连续进度、旧事件及页面离开后的显示保护 |
| `git diff --check` | 补丁空白检查 |

汇总拓扑检查中的旧源码断言同步更新为当前异步预检调用、Set 插入去重及导出目的透传；仍检查预检先于破坏性导入，并保留生产行为测试。

### 五品牌构建

最终源码使用 `SunSmart.xcworkspace`、Debug、iphoneos SDK、`generic/platform=iOS`、`CODE_SIGNING_ALLOWED=NO` 直接运行 xcodebuild，以下五个 scheme 均退出 0：

- SunSmart
- Archipelago
- SLG Sync Plus
- SylSmart
- Lumineux

构建仍有已有的资源符号重名、Info.plist 资源阶段和重复编译条目等警告。本次未修改相关资源与配置以消除无关警告。

### MtestiPhone15 真机检查

- 使用现有 `prepare_sync_devices_row_ui_tests.py` 生成隔离同步列表 App，复用生产 Cell 与布局代码。
- 签名构建、安装并运行成功，App 退出码为 0；渲染结果显示 `PASS: stable icons and layout`，图标、文字、箭头、进度没有发现重叠或裁切。
- 验证包含 12 个任务进度、失败重试和显示事件过滤；临时渲染结果位于 `/tmp/SpaceSyncCleanupUI/sync-row.png`。
- XCTest Runner 因本机缺少所引用的 provisioning profile 未能启动，随后使用同一隔离 App 的内置检查完成真机运行。未将其记为 XCTest 通过。
- 本检查没有替换业务 SunSmart App，没有读取用户账号/业务数据库，也没有访问真实 Space 或发 Mesh 指令。

## 真实设备和服务器验证边界

本次输入为离线导出。**尚未对用户真实 Space 执行上传或 Mesh 命令。** 策略、受控传输/存储替身测试及隔离真机布局检查不能代替真实退订、Profile 下发和服务器收敛验收。最终体验仍需人工确认。

### 人工验收步骤

1. 在含原 Test Space 数据和权限的新版本 App 中进入 Space 并同步：确认保留 L2，C00D 失效路径清除；若现场删除 journal 有效，完成对应删除收尾，旧云端 L1 不重新导入。确认有效拓扑读回后才清除相关 `-2003` 与已知阻塞。
2. Group 删除但设备仍存在：在线设备完成场景/日程/开关、传感器及旧灯控清理，再退订旧组；离线设备保留必要任务，不再被当成结构损坏。
3. Profile 7/8 → 1～6：清除不适用路径/Zone，真实关闭旧邻近照明并下发当前配置；7 ↔ 8、同类型改参数保留有效拓扑并重建差异。
4. 同步过程中删除设备、删除 Group 或再次修改 Profile：旧响应不确认新配置；临时禁用的 PIR 按当前目标收尾，再执行新计划。
5. 包含 Site Zone 时：确认其他有效成员、未知成员和扩展字段仍保留；Site 云端确认后，现存跨 Space 设备仍执行必要邻居更新。
6. 分别制造设备命令失败、上传失败、清理后退出重启：验证可重试、旧数据不恢复、云和设备完成状态独立确认；再次校验没有额外配置写入或时间戳增长。

## 交付状态

已完成代码、相关自动化回归、五品牌构建及隔离同步列表真机检查。所有改动保留在当前工作区，尚未创建 Git commit 或推送。
