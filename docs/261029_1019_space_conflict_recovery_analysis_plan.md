# Space 1 编辑锁、数量差异与异常恢复

日期：2026-10-29。用户已确认 App 实施范围，并补充“配置时间戳相同时以服务器为准”。本文保留根因、最终行为与验收边界；不修改服务器、固件或现场数据。

## 结论与已确认规则

1. 本次不是 Owner 身份丢失，而是 App 因 `cloudConfigurationConflict` 禁止普通配置写入。仅打开添加/删除按钮不能解除同步死循环。
2. 本地有 L1、SW1 两个 Mesh 节点；服务器只有 SW1，但声明设备数为 3，并留下 Switch 3 指向 001D 的悬空代理引用。两端配置时间戳都是 `1793088941`。
3. 按用户确认的规则，同时间戳服务器完整配置是权威来源。本样本恢复后采用 SW1，清除悬空代理并重算设备数为 1；不再要求用户选择保留本机 L1。
4. Owner/Editor 可独立进入恢复流程，选择云端、本机（仅非同版本）、清理引用、移除选定设备或清空内容。Space 实体永久删除仍仅 Owner 可执行。
5. 强制清除记录不表示实体设备已恢复出厂设置。地址排除信息继续保留，实体设备再次入网前需现场复位。

## 一、现场证据与修复前根因

输入文件：

- `/Users/maginawin/Desktop/Space_Space 1_20261029_100900_326+0800.json`
- `/Users/maginawin/Desktop/enter space logs.txt`
- `/Users/maginawin/Desktop/spaceprops.txt`

实施工作树：`feat-device-scene-261028`，分支 `feat/device-scene-261028`，起始 HEAD `b8e8cd9d`。没有把完整现场 JSON、凭据或 Mesh 密钥写入仓库。

| 检查项 | 本地/日志 | 服务器详情 | 结论 |
| --- | --- | --- | --- |
| 权限 | Owner；joined/initialized；active/writable | role=owner，Owner 与当前请求账号一致 | 不是 Visitor 降权 |
| 未完成事务 | 无 pending import/upload/deletion cleanup | GET 业务成功 | 不是等待旧事务完成 |
| 配置版本 | local/confirmed=1793088941 | updateTimestamp=1793088941 | 同版本不同内容 |
| Mesh 节点 | L1/0002/PID 2134；SW1/0005/PID 2A01 | 只有 SW1/0005 | 服务器成员集合更少 |
| 数量 | nodes.count=2，deviceCount=2 | nodes.count=1，deviceCount=3 | 服务器计数与成员不一致 |
| Switch 3 | 无代理节点 | proxyNodeAddress=001D | 两端均无此节点/Element |
| 失败原因 | cloudConfigurationConflict；-2005；sameVersionRemoval.notOnlyNodeRemoval | — | App 完整性保护锁住编辑 |

进入日志的 Site 导入、Space 导入和基线回读均命中同一原因。修复前链路为：GET 应用 Owner 元数据 → 尝试同版本节点删除仲裁 → 要求其余业务属性及保留节点一致 → 比较不通过 → 保存保护状态、保留本地数据 → 设备/Group 等普通编辑被禁用。普通清理又要求仲裁先成功，因此重复进入、重试同步都无法解决。

现场纯 Swift 比对还确认：仅移除临时副本中的 001D 引用，仍有 8 个表示差异导致 SW1 哈希不等：`calibrationRatedPower`、`custProps`、`groupAddress`、`lightControlSceneExecuteDatas`、`motionSensitivityRangeMin/Max`、`pirEnabled`、`enOceanKeyScenes`。因此仅清理代理不足以解决原问题。

本次不把这些字段全部放宽成“相等”。同时间戳通过独立的服务器权威导入处理；网络身份、完整解码、数据结构和权限检查保留。非同版本仍保留原有冲突及本地较新变更保护。

缺少删除发生时的请求/回执和其他客户端历史，不能从这些文件确认 L1 最初因何消失。用户已明确服务器在主动修复，且存在未更新配置时间戳的问题；这是本次服务器优先规则的业务依据，服务端时间戳问题仍由后端修复。

## 二、“2 个设备但只看到 1 个”的口径

- PID 2134 是 Lighting；PID 2A01 是 BatteryPowerSwitch。日志进入的是 Lights 页，该页只显示 L1 一盏灯。
- 真实 Mesh 设备总数包含 SW1，因此本机原始总数为 2。逻辑 Switch 记录数量（本样本 3 条）不能加到 Mesh 节点总数中。
- Space 卡片原先把 `deviceCount` 标成 `Luminaires`，本次改成 `Devices`。
- 恢复页分别展示本机实际节点数、服务器实际节点数及服务器声明计数，另列双方独有的节点名称/地址。
- 没有证据证明 SW1 在 Switches 页丢失；本次不把分类筛选误当成设备记录消失。

采用服务器修复后，本样本应为 1 个真实节点（SW1），Lights 页不再保留 L1。001D 代理被清除，但 Switch 3 逻辑配置本身保留。

## 三、最终交互与权限

统一入口：异常 Space 首次进入提示、导航栏同步失败入口、`More → Repair Space`、Space 内及 Site 列表的非空 Space 删除入口、业务配置无法完整加载时的恢复页。

异常提示说明 Owner/Editor 权限仍有效；当前页面实例只主动提示一次。用户可稍后处理，通过常驻入口继续恢复。

| 操作 | Owner | Editor | 行为 |
| --- | --- | --- | --- |
| Use Cloud Data | 允许 | 允许 | 使用最新云端集合并修复可确认的悬空引用 |
| Use This Phone | 非同版本允许 | 非同版本允许 | 再次核对本机快照，作为新的待上传配置；同时间戳不显示 |
| Repair Invalid References | 允许 | 允许 | 同时间戳采用服务器；非同版本成员不一致时需先选源，不能暗中决定成员归属 |
| Remove Selected Devices | 允许 | 允许 | 从明确标注的 Server Devices 清单选择，预览名称/地址及引用影响 |
| Clear Space Contents | 允许 | 允许 | 清空设备、组、场景、日程、开关、区域与控制器配置；保留 Space 身份和权限 |
| Fix with Defaults | HDB 可用 | HDB 可用 | 继续复用已有 HDB 默认修复能力 |
| Retry / Saved Copies | 允许 | 允许 | 接续已保存导入/删除状态，查看已保存备份 |
| Delete Space Permanently | 允许 | 禁止 | 独立删除实体，不要求先逐台删除设备 |

破坏性操作在确认中说明范围、备份及实体设备未复位。Visitor、撤权、密码失效、错误账号/区域/Space/网络身份、OTA 占用均不获得恢复写权限。普通编辑继续受原有完整性保护。

## 四、恢复实现与持久化

复用 `SpaceConfigurationSafety` 的数据库 checkpoint、reviewed import、pending import、generation 和上传回执；不建立另一套同步事务框架。

流程：

1. GET 最新完整配置并更新权限；展示节点差异及计数。
2. 用户确认后再次 GET，比对已审核的业务快照和角色；本机选源还要重新导出并比对本机快照。
3. 保存本机原始备份、数据库 checkpoint、服务器源快照；任一步失败都不替换配置。
4. 用纯候选转换构建修复结果，验证网络密钥、完整业务结构和导入解码，再持久化选择并切换 generation。
5. 通过现有事务导入替换相关记录。已审核候选先于损坏源数据进入解码，因此清空操作不要求旧 schedules/HDB 等业务字段先恢复正常。
6. 导入成功后才归档/结束被替代的引用清理和删除日志；失败保留导入意图。重启或 Retry 接续同一选择；服务器源已改变则要求刷新审核，不能复用旧选择覆盖新版本。
7. 若修复修改了服务器数据或计数，产生大于旧本机/服务器的本地版本，显示“本机修复完成，等待服务器确认”，排入同步并执行完整回读。
8. 原始服务器源未变时，它只作为修复上传的基线，不可重新导入让设备复活。一般冲突恢复与旧 HDB 默认修复区分：前者源变化要求重新审核，不自动套用 HDB 默认配置。
9. generation 变化使旧云端完成回调失效，并为新待上传版本重新排队。Mesh 同步任务的有效性也检查恢复生命周期/导入/离开状态；导入后的通知刷新当前 Space 数据及列表缓存。

同版本自动恢复也走 checkpoint 和已审核导入路径，但它的选源由已确认的服务器优先规则决定。首次尚未建立云端身份的上传回执仍由原有初始化检查处理，不能用新的等版本规则跳过 Owner/密钥确认。

### 引用与清理范围

- 复用已有拓扑规范化：Group 成员、订阅、Proximity 路径/区域及 Space Trigger Zone。
- 清理失效 Timed 节点实例/地址、Group/Scene 目标及不存在的组 Profile 场景；Scene 成员通过选定节点重建。
- 清理开关缺失代理与无效绑定组、组光感地址、消防控制器缺失绑定；保留合法未绑定逻辑记录。
- HDB 选定移除更新设备成员并删除其虚拟 Sensor Group，保留 Lighting Zone 目录组；清空使用可验证的空 HDB 配置，保留网络身份和 Site 地址管理。
- 以完整候选导入完成选定节点移除，复用现有事务和持久化，而不再逐个调用会被配置保护拦截的普通设备删除入口。原方案提到的逐设备删除协调器继续服务正常删除，不让它与恢复导入互相等待。
- 在替换节点及永久删除 Space 前保留废弃地址记录；不回收未确认物理 Reset 的设备地址。
- 永久删除时更新后续 `removeSubnetwork` 实际保存的同 Site Mesh 实例，避免已加载实例的旧排除缓存覆盖新增地址；未加载目标 Site 时仍从持久化 Mesh 收尾。
- 持久记录 Site 引用清理请求。Space 永久删除由 confirmed/left 的删除证据判定其区域成员已失效；只移除目标 Space 的 Gateway 关联。
- Site 自身无管理权限或有独立未完成冲突时，区域清理保持待处理，不改动其他 Space 的业务数据，也不假装 Site 层已同步。

## 五、永久删除的独立终点

沿用当前 `/sitespace/spaces/delete`（siteId、spaces、userId），没有添加虚构的 force 参数。

Owner 确认 → 保存原始副本 → 持久化 deletesSpace 删除意图 → 阻止该 Space 普通同步 → 再查 Owner 身份 → 发删除请求 → 独立 GET 确认资源不存在 → 完成本地 Mesh/业务记录、消防记录、Site 引用和 Gateway 关联清理 → 标记 left。

- 离线或超时保留 queued/unknown，可重启重试。
- POST 返回成功但 GET 仍存在时不报告完成。
- noSpacePermission/noSitePermission 不能证明整个 Space 已删除，保留待确认状态；只有明确不存在才作为删除事实。
- 已确认云端删除后，本地收尾失败保留 confirmed；重试只收尾，不再次发删除请求。
- 删除结果未知时不允许重新导入/上传同一 Space，避免复活。

服务器是否允许删除非空/损坏 Space、删除后 GET 的确定性错误码、关联数据收尾语义尚未线上验证。若接口限制必须先空配置，App 的独立删除请求会明确保留失败；需要后端提供对应能力。App 的清空并上传路径可以使用，但不能替代服务端独立删除合同。

## 六、修改与复用范围

| 入口/机制 | 本次改动 |
| --- | --- |
| SpaceConfigurationSafety / RecoveryState | 同版本服务器权威、选定快照恢复、源变化保护、失败重试及回执衔接 |
| ImportData / SpaceMembershipCoordinator | 已审核数据解码/事务导入，Owner 持久删除与查询确认 |
| SpaceSyncCleanupPolicy / Coordinator | 候选清理、Site 清理请求、Gateway 关联及 Mesh 任务有效性 |
| MeshNetwork+SunSmart / Site Zone classifier | 地址排除、消防记录删除、已确认删除的 Space 引用收尾 |
| SpaceRecovery / Space / More / Site | 统一恢复页、差异及范围确认、异常提示、删除跳转 |
| SpacesViewCell / 本地化 | Devices 标签；English 与简体中文恢复文案 |

仅 App 变更，没有新增 SDK API 或修改 SDK。五品牌共享这些代码和既有本地化资源，没有新增 project 文件引用、资源归属或条件编译分支。代表构建使用 SunSmart。

## 七、验证与待验收

已通过的自动化检查：

| 检查 | 覆盖与结果 |
| --- | --- |
| `check_space_recovery_receipts.py` | 恢复文件、回执、导入准备、同版本服务器优先、较新本地保护、密钥/权限拒绝、源变化重新审核、保存失败重试与损坏配置清空 |
| 本轮恢复源回归（同脚本） | 顶层旧格式 `triggerZones` / `hdb` 完整保存在比较快照中；同时间戳变更/删除在重启重试及修复上传前均被拒绝，等价迁入 `spaceData` 仍可继续。兼容规范化也保留旧格式 `proximityLightingSchemaVersion`，不放宽身份或完整性检查 |
| `check_space_deletion_exclusions.py`（本轮新增） | 修复前复现旧缓存覆盖；执行生产删除、SDK 实例选择与排除列表 SQLite 持久化，覆盖当前/其他 Space、目标 Site 未加载/其他 Site 已加载、空/已有排除列表、删除失败及业务清理失败重试，并检查再次保存和 SQLite 重开后地址仍保留。Mesh 拓扑/密钥和其他业务表是隔离边界 |
| 同脚本现场样本回放 | 本机 2 个节点 → 服务器 1 个节点；服务器声明 3 → 修复为 1；001D 代理清除；导入后保持修复上传意图。样本仅从桌面读取，测试中的加密边界使用合成密钥 |
| `check_space_membership_lifecycle.py` | Owner 删除离线/未知结果/重启重试、POST 成功但仍存在、权限错误不等于删除、不存在确认、本地收尾重试、Editor 拒绝 |
| `check_space_sync_cleanup.py` / `check_hdb_group_lifecycle.py` | 选定移除、引用和计数收敛、有效 Profile 场景保留、损坏 Standard/HDB 清空、HDB Sensor Group 移除与 Lighting Zone 目录保留 |
| `check_cloud_node_import.py --snapshot …` | 现场节点解码兼容、真实导入准备分支、清理意图保存失败时禁止替换及重试 |
| `check_site_zone_cleanup_loading.py` / `check_site_zone_cleanup_batch.py` | Site 引用分类、已确认 Space 删除、真实 SQLite 持久化/重启、批量清理和取消；恢复 generation 更新后自动重新入队，撤权/账号或区域变化时不排队 |
| `check_space_key_integrity.py` / `check_space_protection_snapshot.py` | 密钥身份校验、保护快照、损坏文件、未完成事务及状态变化 |
| 本地化与差异检查 | English / 简体中文 `plutil -lint`，`git diff --check` |

本轮两项审查修复重新执行并通过 `check_space_deletion_exclusions.py`、`check_space_recovery_receipts.py`、`check_space_membership_lifecycle.py` 和 `git diff --check`；上表其他结果属于此前实施验证，并非本轮重跑。

SunSmart 在本轮修复后再次编译通过：`SunSmartLocal.xcworkspace`、Debug、`iphoneos`、`generic/platform=iOS`、`CODE_SIGNING_ALLOWED=NO`。使用既有本地 SDK 映射 `nordic-sig-mesh-sdk-worktrees/one-dev`，revision `9998967`，SDK 工作区无改动。编译仍有已有的捕获/未使用变量等警告，没有把构建成功当作运行验收。

离线回归执行生产策略、恢复文件、导入准备和成员生命周期；网络响应、部分 Mesh/业务持久化为测试边界。Site 测试覆盖真实 SQLite，但不代表整 App 两库事务、实体设备或线上服务端已验收。Mesh 任务的恢复生命周期保护已编译，真实 BLE/网关迟到回调仍待运行验证。

本轮不自动安装或操作真机，不发送线上修改请求。最短人工验收：

1. 使用本次 Space 1 进入：Owner 保持有效，云端同版本修复能落地；总节点为 1，Lights 不再残留 L1，逻辑 Switch 3 的代理不再指向 001D。
2. 修复页核对双方计数/独有节点；同时间戳无本机覆盖选项，Editor 无永久删除选项；取消确认不改数据。
3. 分别验证选定移除和清空：本机结果、上传、GET 回读、退出重进/重启保持一致；断网显示待确认且可重试。
4. 验证 Standard/HDB、保存失败、服务器在确认期间改变内容、撤权/密码变化；不得覆盖新配置或跳过身份检查。
5. Owner 对非空 Space 永久删除：确认请求合同、独立 GET 不存在、Site/Gateway 关联收尾；HTTP 成功但 GET 仍存在时不能显示成功。
6. 被清除的实体设备仍需手工复位；检查重新入网地址与其他 Space 不冲突。真实 Mesh 同步、设备复位和服务端最终一致性均待现场验收。

## 八、后端配套（仅合同，不在本任务实施）

- 主动修复配置时更新配置时间戳，返回节点集合、派生计数及引用一致的完整详情。
- 明确 sync/spaceprops 对空集合与缺字段的语义，上传后能完整回读新成员和引用。
- 确认 Owner 可按 Space 身份删除非空/损坏配置，重复删除及不存在查询有稳定结果，服务端负责关联数据收尾。
- 当前提交前 GET 无法消除其他客户端在 GET/POST 间的竞争；条件版本写入需要后端合同。App 保留快照复核与回读，不承诺跨端原子性。
