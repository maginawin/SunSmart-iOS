# Gateway 同步误报 Space 不可用：原因与修复方案

日期：2026-11-03。分析分支：`feat/device-scene-261028`，HEAD：`eb18924707c17ee5ba2fc8b77a09172f9e2ecfb9`。分析开始时工作树干净；初次仅增加本文档。用户确认后已实施，结果见末节。

## 结论

Gateway 从 Site 进入，使用 Site 主网络；共享 `SyncDevicesViewController` 却无条件要求当前 Space 页面、Space 子网及恢复状态。正常网关入口没有这个 Space 上下文，因此在生成任务、发送网关命令之前就提示 `Space data is unavailable. Reopen this Space to retry.`。连接网关不能满足这个错误的页面上下文前提。

当前文案对应的直接拦截由 `eb189247` 于 2026-11-03 10:13:04 +08:00 引入。继续向前追溯，`c1a7bd2a` 的 Device Scene 改动已将 Scene 专用准备无条件加入网关同步，形成更早的同类阻断。不能把整个问题只归因于今天的新文案，也不建议简单回滚今天的提交。

修复应在共享同步页区分 Space 配置同步与 Site 网关同步，复用既有网关权限、任务组装和执行机制。无需修改服务器、固件、SDK 或现有 Space 数据。

## 输入数据核对

输入为用户提供的 App export JSON 和 `server data.txt`，未请求线上服务器。App 文件采集时间为 2026-11-03 10:14:48 +08:00。

| 检查项 | 结果 |
| --- | --- |
| Space 名称、UUID、创建及更新时间 | 两份数据一致；Space 为“日出日落” |
| 配置集合 | 均为 14 个节点、1 个 Group、0 个 Scene、0 个 Schedule、0 个 Switch；Group 与 spaceData 一致 |
| 网络与节点身份 | NetKey/AppKey 对象一致；14 个节点 UUID 集合、单播地址、Device Key、绑定的 NetKey/AppKey、PID、Group 地址一致；仅比较，不在本文记录密钥 |
| 本地诊断 | `issues=[]`，`configurationInitialized=true`，`hasCompleteExportSnapshot=true` |
| 恢复与成员状态 | `recoveryPhase=active`、`recoveryAuthority=writable`、`membershipPhase=joined`，网络身份匹配 |
| 待处理状态 | 无 pendingImport、pendingUpload、pendingDeletionCleanup；不要求远端重新导入；最近读回确认成功 |

这些证据不支持“此 Space 配置损坏”作为本次报错原因。两份 Space 节点列表都是 PID `0x2502` 的设备，不含 `gateway1` 的主网节点及完整 GatewayModel。服务器的 `gatewayId` 只表明关联关系，不能据此还原网关当前读回值。

`Devices not synced` 的显示依据是 `node.getNodeSyncGatewayData(gateway:)` 返回非空，比较内容包括项目 ID、关联子网/模型 AppKey 绑定、激活子网列表、4G APN 和 MQTT 配置。它不等同于 Space 云端数据不一致。本次材料不足以确定 gateway1 具体是哪一项尚未同步；若修复入口后该标记仍存在，再读取对应 Gateway 差异与回执，无需先扩大排查。

## 已证实的调用链

1. [SiteViewController.swift](../SunSmart/Main/Site/Controller/SiteViewController.swift) 的 `gatewayOperationClickAction` 从 Site 打开 Gateway/WiFiGateway，使用单独的导航控制器展示。Site 进入时切换到主网络。
2. [GatewayViewController.swift](../SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift) 的名称区按钮先检查 `site.canConfigureGateway`，再调用 `resync(trigger: .devicesNotSynced)`，创建 `.gatewayRecovery` 类型的共享同步页。此入口原本只准备任务列表，等待用户执行 RE-SYNC。
3. [SyncDevicesViewController.swift](../SunSmart/Main/Space/Controller/SyncDevicesViewController.swift) 初始化时，对所有 SyncType 无差别调用 `SpaceSyncAccess.captureIdentity()`。
4. [SpaceViewController.swift](../SunSmart/Main/Space/Controller/SpaceViewController.swift) 的主线程 `currentSpace()` 只从根导航栈的 SpaceViewController 获取 Space。Site → Gateway 路径正常没有该页面，得到 nil。
5. [SpaceSyncCleanupCoordinator.swift](../SunSmart/Common/Data/SpaceSyncCleanupCoordinator.swift) 的 `captureIdentity()` 在 nil 时返回固定的 `{ false }`。同步页的 `rebuildTaskPlan` 第一个身份 guard 随即失败，显示当前提示；尚未调用 Scene 恢复、引用清理、任务构建或设备命令。
6. 同页 RE-SYNC 继续使用原来的固定失败闭包，仍然失败。即使另行打开 Space，Site 主网也不应被当作该 Space 子网；“重开 Space”不是这条网关路径的修复办法。

因此仅修改报错文案、移除第一个 guard 或更换 currentSpace 的 UI 查找方式都不完整：后续还有 `SpaceSyncAccess.error`、`captureRecovery`、`prepareForDeviceSync`、Scene 恢复/删除准备，以及执行阶段的 `configurationAvailable`，同样假定存在 Space。

## 引入历史

| 提交 | 时间（+08:00） | 对此问题的影响 |
| --- | --- | --- |
| `c1a7bd2ac59eaf8333254e686e089679f3f4c764`，`feat: device scene` | Author：2026-10-30 08:12:10；Commit：2026-10-31 13:53:45 | 共享同步页新增无条件 Scene Restore 和 `prepareDeletionRetries()`。当时删除准备在检查有无删除任务之前就调用 Scene `validateAccess`，要求持久化及活动 Space，导致合法 Site 网关入口被 Scene 条件拒绝，并可能显示恢复/删除 Scene 错误 |
| `eb18924707c17ee5ba2fc8b77a09172f9e2ecfb9`，`fix: delete scene wrong alert issues` | Author/Commit：2026-11-03 10:13:04 | 新增通用 SpaceSyncAccess 和准备重试管理，但未区分 Site 网关上下文。把拒绝提前到初始化身份检查，形成当前稳定出现的 Space 不可用提示 |

通过 `git log -S`、提交前后源码和 blame 定位上述变化。`c1a7bd2a` 的父提交 `eba3d3d8` 尚未在该公共准备路径调用 Scene 恢复/删除准备；这是源码中可定位的引入边界，不代表已在旧 App 上完成运行回归，也不能从 Git 时间推断安装包实际发布/安装时间。

## 关联影响与实施边界

| 入口 | 当前类型与影响 | 修复要求 |
| --- | --- | --- |
| Gateway 的 Devices not synced | `.gatewayRecovery`；4G/WiFi 共用基础入口 | 以实际 Site、Gateway、Node 身份准备及执行 |
| Gateway 修改后 Save | `.devices([node])`；同样没有活动 Space | 调用方显式提供网关上下文，不能只修两个带 gateway 名称的枚举分支 |
| WiFi Repair | `.gatewayRecovery(..., .repair)` | 保留立即开始、强制初始化、依赖顺序和验证语义 |
| WiFi Authorize | `.gatewayServerRecovery` | 保留服务器授权、信息写入和读回验证链路 |
| 普通 Space 的设备、Group、Profile、Scene、Timed 等同步 | 共用控制器和执行器 | 继续保留 Space 权限、成员状态、配置保护及恢复代次检查 |

4G 自身 Repair/Authorize 还有原有独立实现；不能将 WiFi 覆盖范围机械推广为所有 4G 操作。Site 新增网关通过已有添加流程直接生成附加命令，不经过这里的新页面准备 guard；Site 的独立 `SyncGatewaysViewController` 也不属于同一入口。两者的权限/上下文处理可参考，无需为了本次问题改写。

## 已确认的修复方案

1. **为共享同步页明确操作上下文。** 在现有初始化与准备流程中做小范围扩展，区分默认 Space 上下文与显式 Site/Gateway 上下文。Gateway 的 resync、Save、服务器信息恢复三个创建点传入实际 Site、Gateway 和 Node。继续复用 `SyncTaskPlanBuilder`、`SyncGatewayTaskBuilder`、`SyncExecutionSession`；无需新增一套网关同步控制器。

2. **按上下文进行完整的准备与执行校验。** Space 保留现有链路。Site Gateway 复用 `SiteData.canConfigureGateway`，核对账号/服务器区域、Site ID/Mesh UUID/主网、Gateway 的归属与删除状态，以及目标 Node UUID/地址/网络实例；等待后、RE-SYNC 和执行边界复核当前权限及身份。可编辑关联空间参与既有网关授权判断，但不把“必须打开某个 Space 页面”作为授权条件。无权限、目标删除或跨账号/网络时继续拒绝，不用恒定 true 绕过保护。

3. **让准备工作与操作对象匹配。** Site Gateway 不执行 Space Scene Restore、Space 引用清理或 Scene 删除准备，也不依赖 Space recovery generation。其计划校验绑定网关和实际依赖的关联空间/密钥配置；复用现有任务顺序和缺少关联密钥时的失败处理，避免依赖无关 Scene/Profile 状态。普通 Space 路径完整保留原有正常、零 Scene、待恢复及损坏数据处理。Site 网关与普通设备混合目标不得靠“没有 Space 就当网关”自动放行。

4. **保持失败恢复及持久化语义。** 复用准备轮次、取消、STOP、离页、执行通道与迟到回调保护。重试时重新取得有效的 Site/Gateway 目标；已删除或重新入网导致身份变化的旧目标不能继续发送。保留现有读回确认、Node/Gateway 存储、`siteGatewayDataChangedNotificaitonName` 和云端网关同步回调，避免把建计划成功当成设备同步完成。错误使用对应的现有权限/数据/离线文案；确需新文案时同步中英文。

此修复不需要清空空间、重建节点、迁移历史 JSON 或修改远端接口。共享逻辑涉及五个品牌，但当前无品牌条件差异；无新 SDK API、依赖或资源配置需求。实施时若范围变化，再调整构建范围。

## 验证方案与当前证据

本轮已完成：

- 两份输入的结构化比较及安全状态核对。
- `python3 scripts/check_sync_preparation.py` 通过。其现有页面夹具覆盖 devices/group/scene/profile/schedule，但没有 Site Gateway 上下文；权限夹具将活动 Space 为空一律视为不可用，所以绿灯没有覆盖本问题。
- 临时 Swift 探针执行生产 `SpaceSyncAccess`：有效 Space 允许；无活动 Space 时身份闭包为 false、返回 configurationUnavailable；之后出现 Space 也不会修复已捕获的失败闭包；旧 Space 搭配 Site 主网同样拒绝。
- 临时探针执行历史 `c1a7bd2a` 的生产 Scene `validateAccess`：即使持久化配置正常，缺少活动 Space 仍拒绝。
- 临时页面夹具执行当前生产准备/重试方法：gatewayRecovery、gatewayServerRecovery、devices 三类入口均在任务构建前失败，RE-SYNC 再次失败。存储、UIKit、Mesh 和其他外部边界为替身，探针没有连接设备或请求服务器。

实施时最小必要回归：

1. 将上述合法 Site Gateway 场景加入现有同步准备测试，覆盖无 Space、有关联 Space 但未打开页面、合法空关联、Save、Devices not synced、WiFi Repair/Authorize；确认能够建计划，并按入口约定等待或开始。
2. 覆盖 Site Owner、有效关联空间 Editor、无编辑权限、权限撤销、账号/区域/Site/主网切换、Node 被删除或替换、关联密钥缺失；不发送越权/过期目标命令，合法上下文恢复后可重试。
3. 覆盖准备中 STOP/离页、授权失败后重试、迟到授权与 ACK；保留原任务依赖及读回验证。复用 `check_sync_task_builders.py`、`check_sync_execution_session.py`、`check_sync_run_lifecycle.py` 的相关行为测试。网关修复/授权 shell 合约检查只作为补充，不作为运行证明。
4. 复跑 `check_sync_preparation.py` 的 Space 权限/配置用例及相关 Scene deletion 回归，确保本次区分上下文不会削弱普通 Space 的保护。
5. 一轮 Swift 修改完成后，核对实际本地 workspace/SDK 映射，构建一次 SunSmart Debug / generic iOS（不签名、不使用 Simulator）。

人工最短验收：从 Site 打开 gateway1 → 连接 → Devices not synced，应出现网关任务而不是 Space 不可用；执行 RE-SYNC，确认实际成功及读回一致后待同步提示消失；失败可重试，返回重进不丢状态。补验 Save，以及设备支持时的 WiFi Repair/Authorize。再验证普通 Space 内正常 Owner/Editor 可同步、Visitor 不可越权。

本轮未构建 App、未自动安装/操作真机、未执行真实网关授权或云端往返。业务根因与引入提交已定位；gateway1 具体未同步字段和修复后的 BLE/UI/服务器收敛仍待运行验收。


## 实施结果（2026-11-03）

已按确认方案完成 App 修改，未提交 Git：

- 在既有 GatewayModel 文件中增加 GatewaySyncContext，复用 Site 网关权限规则，绑定账号/区域、Site 主网、原 Node 实例/UUID/地址/Device Key 和网关持久化生命周期。活动及持久化权限、删除状态均参与判断，不依赖 Space 页面。
- Gateway 的 Devices not synced、Save、WiFi Repair/Authorize 三个页面创建点显式传入上下文。共享同步页据此跳过 Space 专用准备与 HDB 初始化准备；普通 Space 路径保留。
- 建计划前刷新持久化 Gateway 配置；计划冻结激活/APN/关联空间索引及相关网络密钥。关联记录使用值快照，原对象原地变化也会使旧计划失效。Node 绑定和读回变化不使本轮失效；恢复/授权流程允许自身 MQTT 写回，普通 Save 仍检查已捕获 MQTT 配置。
- 授权回调应用成功状态前再次校验计划。沿用原执行器取消、STOP、离页和迟到 ACK 保护。缺少关联密钥等建计划失败保留重新准备入口；构建期间上下文失效时提示并等待重试，避免同步递归重建。
- 复用原国际化文案，无资源、target 配置、依赖、SDK、服务器或固件修改。各品牌共用相同编译路径，本次以 SunSmart 代表构建。

验证结果：

| 检查 | 结果 |
| --- | --- |
| check_sync_preparation.py | 通过；新增执行生产 GatewaySyncContext 和 canConfigureGateway 的夹具，覆盖 Owner/Editor、合法空关联、权限撤销/恢复、账号/区域/主网、目标替换/密钥变化、删除、关联配置及密钥变化、授权自身写回；页面夹具覆盖三个网关入口、无 Space、等待/开始、准备失败后重试，并保留原 Space 用例 |
| check_sync_execution_session.py | 通过；新增授权等待中计划失效、迟到成功不确认任务的用例，原取消/重试/Scene/回执/执行通道用例继续通过 |
| check_sync_run_lifecycle.py | 通过；生产计划安装、关闭页面和等待释放 |
| check_sync_task_builders.py | 通过；包括网关恢复及缺失关联密钥等原有构建行为 |
| check_scene_deletion_flow.py | 通过；恢复回执、删除准备、取消/重试、持久化及迟到回执回归 |
| SunSmart Debug / generic iOS | 最终差异编译通过，输出 BUILD SUCCEEDED；CODE_SIGNING_ALLOWED=NO |
| git diff --check | 通过 |

构建入口为 SunSmartLocal.xcworkspace，SDK realpath 为 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`，revision `dbcf6f1`，SDK 工作树无改动。沿用 `SunSmart-feat-device-scene-261028-cli` DerivedData。隔离测试首次遇到系统临时模块缓存权限错误后，指定已有可写 ModuleCache 再运行成功；未清理共享缓存。

上述夹具的 UIKit、存储或 Mesh 边界仍有替身；构建只证明编译，不代表 gateway1 实际配置、BLE/UI 或服务器往返已验收。未安装或操作真机。人工按前述 Site → gateway1 → 连接 → Devices not synced → RE-SYNC 路径验收，并补 Save、适用的 WiFi Repair/Authorize。
