# Sync Devices 方案 B：当前代码核对与分阶段修复计划

日期：2026-09-08。工作区：`refactory-sync-devices`。代码基线：`c01276bd`（`fix: sync device(s) jump flash`）。

参考：[原始重构分析](260908_1525_sync_devices_refactoring_analysis.md)。本轮仅分析、运行现有回归并新增计划，不修改业务代码、SDK 或工程配置。原有未跟踪分析文档保留。

## 1. 决策与首批范围

采用用户选定的 **方案 B：按职责渐进抽离**。目标是让任务构建、业务策略、同步会话和页面展示具有明确边界，并能分别验证行为。

建议首批交付阶段 0、1A、1B：冻结现有行为和测试入口，抽离普通设备／Group 构建器，再抽离两类网关恢复构建。随后依次处理其他场景、执行策略和会话。每批独立验证，未通过不继续扩大迁移范围。

范围约束：

- 保留 `SyncDevicesViewController(type:reSync:)`、嵌套 `SyncType`／`GatewayRecoveryTrigger`／`EmergencyFireSyncContext` 和现有回调接口，避免修改 35 个调用文件。
- 首批继续使用 `SyncDevices*Model`，不提前生成或缓存全部 Mesh 消息，不改协议、ACK 判定、业务 planner 和发送机制。
- 保留进度及设备行闪烁修复，不把任务运行状态与显示状态重新混合。
- 不引入新授权机制或 Auth 信息；网关授权继续使用现有服务。不切换 SDK 引用、不升级依赖。
- 本方案不包含后台同步、持久化任务恢复、独立领域任务 ID 等方案 C 能力。

## 2. 与参考文档相比，当前基线的变化

| 项目 | 当前核对结果 | 对计划的影响 |
| --- | --- | --- |
| 控制器 | 4,034 行，14 类 SyncType | 仍存在构建、发送、回写、展示混合 |
| 模型文件 | 1,476 行 | 不应继续作为全部逻辑的接收文件 |
| 创建入口 | 排除整行注释后 57 处、35 个文件 | 保留外部接口，按入口语义分类回归 |
| 行显示修复 | 已有 `SyncDevicesDisplayContext`、Cell 显示快照与可见行刷新 | 作为最新基线，不能按旧文档仅保留进度文字修复 |
| target | SunSmart、Archipelago、SylSmart、SLG Sync Plus、Lumineux | 新生产文件必须进入全部五个 Sources phase |
| SDK | 共享工程为远程 `release`，锁定 `86f5ec9e40148b9cd93e0512702337fcec41dd40` | 使用锁定依赖验证；本地 SDK 检查结果不能冒充锁定依赖构建结果 |

控制器内容哈希：`1e83d93b115cbdf3e0fa30233f503d63efca36fb`。原文档记录的是其他工作区和更早内容，本计划以当前读取结果为准。

当前关键位置（行号对应上述基线）：

| 文件／方法 | 位置 | 核对结论 |
| --- | --- | --- |
| `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`：`setupDataSource()` | 143 行附近 | 构建同时修改 sections、初始失败状态和 HUD；消防 planner 失败也直接操作 UI |
| 同文件：`getSyncDeviceModel(...)` | 1333 行 | 依赖 Group、Node、有效成员数量、Profile 切换上下文以及 PIR 保护上下文是否存在 |
| 同文件：网关构建方法 | 1799、1856 行 | 依赖当前 Mesh 网络、关联 Space 密钥及名称；完整恢复与服务器恢复共享子链 |
| 同文件：`backAction()`／`rightItemAction()` | 2057、2142 行附近 | 回调汇总、停止、补偿和重试混合；不能只迁移发送循环 |
| 同文件：`startSync()` | 2394 行 | 调度、动态消息、专用成功判定、回写和 UI 更新集中 |
| 同文件：`getNextHandleModel()` | 3453 行 | 按 `allModels` 顺序选任务，不按可见 `rowModels` 执行 |
| `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift`：`messageHandles` | 467 行 | 每次访问调用消息工厂；网关授权后的信息等依赖执行时状态 |
| 同文件：`allModels`／`rowModels`／显示上下文 | 1097、1142、1438 行 | 执行遍历与展开列表不同；显示上下文按对象身份记录本轮实际开始的设备和 Group |

## 3. 必须保留和单独验证的行为

### 3.1 构建与依赖

普通构建继续调用 `Node.getSyncData(...)`，不在 Builder 复制同步需求计算。Group 成员加入使用 `.memberAdded` 上下文，正常 SAVE 使用调用方的 Profile 上下文；PIR 保护存在时不重复生成普通 PIR 操作。

保留初始化、入组、退组、TimeSet 及 Profile 的依赖关系。退组中的非阻塞清理步骤不能被统一加入阻塞依赖。独立 `.profile` 使用步骤依赖，普通设备 Profile 使用任务依赖，第一轮分别迁移，不直接合并。

默认删除分区在配置分区前；电池开关配置分区在前。Proxy 始终按现有 `allModels` 规则排序，替换 Proxy 的配置步骤显式依赖删除步骤。父级引用、分区索引和对象身份必须保留，不能只比较标题与数量。

### 3.2 执行结果与退出

- 普通操作需要消息成功且业务状态成功；Repair 初始化还要求非空消息及业务成功；Devices not synced 恢复初始化要求非空消息及消息成功。
- 电池开关本体配置、消防删除清理使用专用判定。合法消防本地空消息任务与必需 TimeSet／电池配置消息缺失必须区分。
- ACK 后仍需按现有顺序调用 Node 回写、清缓存，再判断业务成功；服务器授权成功不能代替最终设备验证。
- 普通重试保留成功任务，并重新执行必要的 Profile／TimeSet 前置操作；电池开关重试保留激活与专用重置流程。
- 当前消防删除超时为 5 秒、普通超时为 15 秒；消防删除最多 3 次尝试、间隔 0.2 秒；电池按键配置相关等待为 1 秒和 0.5 秒。迁移不调整这些参数。
- 默认进入自动开始，`reSync: true` 等待用户操作；自动恢复最多两次附加重试，耗尽后保持原失败回调／BLE OTA 返回行为。
- 有 `backActionCallback` 时由调用方关闭页面；没有时使用现有 push／present 关闭适配。`DeviceProtocol.syncPermanentDeletionPeers(...)` 已有一次性 finish，并先 pop 再 completion；`SpaceViewController` 也有成功后自行 pop 的入口。
- 返回汇总目前遍历 section.devices 和 group.deviceModels；不要在重构时未经验证改成遍历全部模型，从而悄悄改变 Proxy 等结果覆盖范围。

### 3.3 本轮发现的两个独立验证项

**轮次隔离存在静态覆盖缺口。** 现有 ACK、失败回调、服务器授权结果及部分开始事件检查 token，但发送后的 `semaphore.wait()` 返回、后置等待、循环最终收尾，以及若干主线程 UI／完成闭包没有逐处复核原轮次。如果 STOP 后模型不再有待执行任务，循环可能直接进入尾部；新轮次开始后的旧收尾也需要验证。当前未执行可控时序复现，因此不能称为已经证实的线上竞争或死锁。

阶段 0 加入“STOP 后完成回调到达”“旧轮次收尾晚于新轮次启动”“页面退出后构建完成”的可控测试。若复现，先以独立修复批次补齐有效轮次检查、一次性收尾和等待释放，再进行会话迁移。不要将已复现缺陷作为必须等价保留的行为。

**Dongle 删除日程在构建阶段遗漏。** 控制器 `.dongle` 分支分别收集 `syncCollectionSchedules` 和 `deleteCollectionSchedules`，后面只遍历前者，导致遍历内部的删除 case 无法接收已收集的删除输入。`Node+SyncData.swift` 的 `.dongle` 分支确实可以产生删除日程数据。这是源码可确认的构建缺口；设备上的实际表现尚未验证。

为“仅删除”和“新增与删除混合”建立输入用例，在迁移 Dongle 构建前以独立小修复补齐删除集合遍历。保留现有删除消息工厂与分区顺序，不顺带修改采集启用／禁用协议。该项不扩大首批普通／网关 Builder 的改动范围。

## 4. 目标职责与接口边界

以下为建议名称，实施时遵循现有目录风格，不要求一次创建全部类型。

| 组件 | 输入／输出及职责 | 禁止承担的职责 |
| --- | --- | --- |
| `SyncTaskPlanBuilder` | 接收原 SyncType、初始重同步模式、Profile／PIR／补充邻近任务上下文；返回有序 sections、初始状态、构建诊断及必要任务引用 | 不持有控制器，不弹 HUD，不发送消息 |
| `SyncDeviceTaskBuilder` | Group／Node／有效成员数量／Profile 上下文／PIR 保护标志 → 配置设备与删除设备 | 不重新规划拓扑，不预取执行消息 |
| `SyncGatewayTaskBuilder` | Node／Gateway／恢复触发源及网络读取依赖 → 完整恢复设备或服务器恢复步骤；失败显式返回 | 不调用授权服务，不更新导航状态 |
| 其他场景构建器 | Profile、开关、消防等确有独立规则的组装；Scene／Schedule／参数等简单分支集中处理 | 不按 14 个枚举机械建立 14 个类 |
| 结果／重试／专用策略 | 成功分类、返回结果聚合、必要前置任务重试、消防／电池／Daylight 专用规则 | 不操作 UITableView，不承担所有会话状态 |
| `SyncExecutionSession` | 轮次、当前操作、任务选择、停止／重试、业务回写、补偿与结束事件 | 不导航，不通过 UI 按钮模拟自动重试 |
| 控制器与显示适配 | 外部入口、生命周期、激活提示、用户意图、展开／选择、进度、回调和关闭 | 不继续保留协议分支与发送循环 |

构建结果仍包含可变 Node、操作和 UI 兼容模型，不能称为不可变纯业务计划。构建结果应区分“合法空任务”和“构建失败”，并保持当前不同失败入口是否展示提示的差异，不统一添加提示。

`SyncTaskPlanBuilder` 是装配入口；普通 Builder、网关 Builder 应是独立对象，内部辅助方法继续保持 private。不能为了跨文件 extension 访问，把控制器全部字段改成可见成员。

## 5. 状态所有权与并发处理

### 5.1 构建阶段

构建器独立创建模型，只在完成后一次性交给页面；不得在构建过程中通过控制器不断追加 sections。保留现有后台构建方式及消息创建时机。外部 SDK Node 仍是共享可变对象，此阶段不宣称解决其全部线程安全问题。

构建上下文显式传入当前依赖。涉及全局网络读取和 Space 名称加载的地方先提供窄读取接口／闭包，默认行为与现有生产读取一致；不批量预生成消息，也不悄悄改变读取时点。

### 5.2 会话阶段

建议应用层模型和会话状态统一在主线程串行访问：Session 拥有运行状态，控制器拥有展示状态；主线程上的 Session 状态转换与 UI 读取共享兼容模型。后台驱动继续承担发送等待，主线程绝不等待信号量。

- 从后台选择任务、处理 SDK 回调时，先交回状态所有者验证 token，再更新应用层状态；必须明确回写、业务成功计算、事件发布和释放下一步等待的顺序。
- 暂不全面替换 GCD／信号量为 actor 或 async-await，也不把 SDK 可变 Handle 当作 Sendable 跨队列自由传递。传输适配器需记录实际回调线程、追加消息语义及停止完成语义。
- STOP／退出先使原轮次失效；原轮次待处理完成必须能释放等待，但不能更新新轮次、发出新一轮消息或触发旧成功回调。
- 区分“每轮结束一次”和“页面退出回调一次”；允许用户重试产生新轮次，不能用页面级单次标志吞掉后续合法同步完成。
- PIR 恢复、Lux 解锁、Profile 快照恢复由补偿组件登记与执行。补偿需要自身生命周期，不能被普通任务 token 检查直接丢弃，也不能与新轮次对同一设备的配置交叉覆盖。
- `lastDeviceModel` 当前还用于 STOP 时寻找 Profile 恢复操作。抽离后 Session 保存实际当前执行任务，UI 保留当前展开设备，两者不能继续共用一个字段。
- `SyncDevicesDisplayContext` 留在主线程展示层。Session 的开始、结束事件带轮次；控制器验收轮次后再登记显示身份或刷新。

上述串行边界是阶段 3 的实施与验收要求，不是当前代码已经具备的保证。跨 SDK 的真实回调与取消行为须结合其实际锁定版本验证。

## 6. 实施分批与退出条件

| 批次 | 工作内容 | 完成标准 |
| --- | --- | --- |
| 0：行为基线 | 固定当前提交、14 类输入和入口矩阵；盘点源码契约；建立构建输出及会话时序测试支点 | 能记录操作类别、分区／设备／步骤顺序、依赖边、父级关系、初始状态；已知问题与兼容基线分开记录 |
| 1A：普通构建 | 提取 `getSyncDeviceModel(...)` 为 `SyncDeviceTaskBuilder`；显式传入 PIR 保护标志与 Profile 上下文；原控制器保留薄委托 | Group、devices 及既有调用输出等价；无控制器／UITableView／HUD 依赖；消息工厂不提前执行 |
| 1B：网关构建 | 提取 `makeGatewayRecoveryDeviceModel(...)` 和 `makeGatewayServerRecoverySteps(...)`；构建错误返回调用方 | Repair／Devices not synced／Server Recovery 顺序及依赖一致；缺少关联 Space 密钥不生成部分可执行恢复链；服务器信息仍在授权后动态读取 |
| 1C：其他场景和总装 | 先 Profile 与邻近补充任务，再 Proxy／电池／消防，最后简单 Scene／Schedule／参数／Dongle；建立总 Builder | `setupDataSource()` 仅准备上下文、接收结果和适配初始 UI；消防 pending 持久化留在执行阶段；Dongle 缺口先单独修复验证 |
| 2：执行规则 | 先成功判定、超时／消防重试、普通与电池重置、返回汇总；再迁移 Daylight、PIR 和回写专用规则 | 策略可独立测试；同一结果仅回写一次；专用例外不被普通策略覆盖 |
| 3：同步会话 | 注入发送、停止、授权、延迟及事件接口；迁出调度／轮次／结束／自动重试；落实状态所有权 | 控制器无发送循环；迟到回调、停止等待、动态追加、补偿和重复结束测试通过；UI 更新全部在主线程 |
| 4：展示收尾 | 视控制器剩余职责决定是否提取列表适配；清理迁移后真正无调用的方法 | 结构刷新与进度刷新边界清楚；不重建整表更新连续进度；实际布局与完整操作路径通过 |

共享 `Node.sendHandleCompleteIdentify(...)` 建议迁至 `SunSmart/Common/Data/Node+SyncIdentify.swift`；核对 Sync Devices、Read Devices、Light Sensor Calibration 三类调用方。任务的 `resyncRelevanceCheck()` 随重试策略迁移。`daylightRecallConditionId` 的私有关联存储需与 Daylight 策略一起处理访问边界，不通过公开整个控制器解决。

每批保留可独立撤回的改动边界；需要撤回时只撤回对应批次，不覆盖用户已有工作。计划本身不包含 Git 提交、推送或分支合并操作。

## 7. 验证矩阵与工程落地

### 7.1 14 类输入覆盖

| 输入 | 必须包含的样例 |
| --- | --- |
| group | SAVE、加入、退出、部分退出失败、PIR 前后保护、跨 Group 邻近补充 |
| profile | 独立步骤依赖、Lux 锁／阈值／切换／Store、必要前置重试 |
| scene | 配置与删除、绑定 Schedule 时的前后依赖 |
| schedule | Group 与直接设备入口、TimeSet 前置与缺失消息 |
| enOceanSwitch | 绑定、解绑、Proxy 替换、删除失败阻塞后续配置 |
| batteryPowerSwitch | 本体优先、目标 Group、激活取消／成功、等待时停止、本体失败传播 |
| devices | 初始化动态追加、混合配置／删除、无任务设备 |
| gatewayRecovery | 两种 trigger、缺密钥、清理旧关联、WiFi／其他网关分支、离线及最终验证 |
| gatewayServerRecovery | 非 WiFi 输入、授权失败、成功后动态读取信息、旧授权结果到达 |
| devicesParameter | 参数到操作映射、无参数、功率校准错误 |
| dongle | 新增、仅删除、混合增删、无绑定节点；新增测试先暴露删除遗漏 |
| emergencyFire | 保存、关联修改、删除清理、合法本地任务、部分成功持久化、重试耗尽 |
| proximityLightingPath | 既有 planner 输出、顺序、局部失败、容量约束不重复规划 |
| spaceTriggerZones | 与 Group 补充任务的覆盖范围、自动入口、回调关闭 |

构建测试运行实际生产 Builder，以输入夹具和操作／依赖描述断言行为。旧／新输出比较可在迁移过程中临时保留；最终不维护两套生产 Builder。需要 UIKit／SDK 的集成测试使用真实 iOS target；能解耦的纯策略使用现有 Swift 命令行测试方式。不能复制生产实现到测试替身后声称已验证生产构建器。

会话测试使用可控传输、授权和时钟替身，验证实际 Session。模拟回调、取消和动态追加顺序，断言回写次数、事件轮次及导航次数。替身测试不能证明真实 Mesh 设备收敛。

### 7.2 现有检查迁移

需随实际归属更新精确路径／提取边界：

- `check_efc_controller_flows.sh`、`check_wifi_gateway_repair_recovery.sh`、`check_wifi_gateway_server_information_recovery.sh`。
- `Tests/Group/` 下拓扑、生命周期、Trigger Zone 契约，以及 `Tests/Device/GatewayRecoveryAssociatedSpacesContractTests.swift`。
- `check_timed_scheduler_single_owner.sh`、`check_site_timeset_call_sites.sh`、`check_fast_add_dual_scene_verification.sh`、默认 TTL 与设备 Restore 相关模型检查。
- `check_sync_devices_progress.py`、`check_sync_devices_row_display.py`；后者从显示上下文注释提取到文件结尾，搬迁时必须同步调整。
- `prepare_sync_devices_row_ui_tests.py` 按控制器方法边界提取 `refreshVisibleSyncCells()`；展示方法迁移时同步更新真机测试准备脚本。

按最终职责文件精确定位断言，不用“在项目任意文件找到相同文本”替代原断言；入口契约继续核对调用关系，并补充行为测试。

### 7.3 构建和实际验收

新 Swift 文件加入五个 App target 的 PBXFileReference、PBXBuildFile 和 PBXSourcesBuildPhase；不改 Pods 或 Swift Package 配置。每批先验证受影响行为，再顺序构建五个 scheme，避免同一构建数据库并发占用。

构建按项目要求直接调用 `xcodebuild`：workspace 为 `SunSmart.xcworkspace`，分别使用五个共享 scheme，Debug、iphoneos、`generic/platform=iOS`、关闭签名，执行 build。不使用 shell 包装、日志重定向或 Simulator。

涉及 UI 绑定／事件／展开逻辑时，必须执行真实 UIKit 布局测试及页面路径检查：连续任务、9→10 位数变化、首任务失败、横竖屏、展开切换、离屏复用、Group／Proxy 复用、STOP、单项／整批重试、push／present 和调用方自行关闭。现有隔离真机测试工程可作为起点，但不能代替真实同步页面全路径。

BLE／Mesh 验收另列：初始化追加消息、局部失败重试、网关授权与读回、电池激活、消防部分删除、PIR／Lux／Profile 补偿。自动测试、构建、HTTP 成功与设备真实配置完成分别报告。

## 8. 本轮已完成验证与剩余工作

本轮在当前工作区运行并通过：

| 命令／检查 | 结果与边界 |
| --- | --- |
| `python3 scripts/check_sync_devices_progress.py` | 连续 12 个任务、位数切换、首任务失败、重试等通过；使用控件替身 |
| `python3 scripts/check_sync_devices_row_display.py` | 行状态、旧轮次开始事件、复用、重复 UI 写入、选择等通过；不是实际布局测试 |
| `bash scripts/check_wifi_gateway_repair_recovery.sh` | Repair 初始化源码契约通过 |
| `bash scripts/check_wifi_gateway_server_information_recovery.sh` | 授权服务与恢复入口源码契约通过 |
| `bash scripts/check_path_topology_persistence.sh` | 脚本当前包含的拓扑、生命周期、导入、持久化及读回等测试组全部通过 |
| `bash scripts/check_efc_controller_flows.sh` | DeviceEmerFireCacheTests 及消防流程契约通过；脚本默认读取本地 one-dev SDK |
| `bash scripts/check_nordic_sdk_dependency.sh` | 五 target 共享远程依赖配置检查通过 |

这些结果建立当前已有回归基线，不代表新增 Builder、Session、Dongle 修复或轮次时序用例已经实现。未运行 iOS 构建、真实 UIKit 布局、服务器或 BLE／Mesh 操作；本轮仅新增本计划文档。

下一实施批次为阶段 0 → 1A → 1B。完整方案 B 完成还必须交付后续场景、策略、会话及相应验收，不能以首批文件拆分完成宣称整个重构完成。
