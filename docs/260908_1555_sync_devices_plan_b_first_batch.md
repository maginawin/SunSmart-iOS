# Sync Devices 方案 B 首批实施记录

日期：2026-09-08。工作区：`refactory-sync-devices`。实施基线：`c01276bd`。

对应[方案 B 计划](260908_1544_sync_devices_plan_b.md)。本批完成普通设备／Group 构建抽离（1A）、网关恢复构建抽离（1B）以及相应构建行为基线。五品牌 iPhoneOS 构建和本批相关自动回归通过。

这不是整个方案 B 完成：其他场景总装、执行策略、同步会话、完整会话时序测试和实际设备验收仍有后续工作。

## 1. 代码改动

| 文件 | 结果 |
| --- | --- |
| `SunSmart/Main/Space/Model/SyncDeviceTaskBuilder.swift` | 新增普通设备／Group 构建器，477 行；复用 `Node.getSyncData`，显式接收有效成员数量、Profile 上下文及 PIR 保护标志 |
| `SunSmart/Main/Space/Model/SyncGatewayTaskBuilder.swift` | 新增完整恢复和服务器恢复构建器，280 行；注入当前网络及 Space 名称读取；区分非网关、缺少网络、缺少关联 Space 密钥三类失败 |
| `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift` | 普通构建保留薄委托，网关分支接收 Builder 结果并保持原失败提示；从 4,034 行减少到 3,327 行 |
| `SunSmart.xcodeproj/project.pbxproj` | 仅增加两个 Builder 的 24 行文件及编译引用；五个 target 各编译一次 |

新构建器不持有控制器、不调用 HUD、不发送消息。Space 名称及网络仍在构建需要时读取；消息工厂仍在执行阶段调用，避免提前冻结 TimeSet 或授权后的服务器信息。

外部 initializer、嵌套 SyncType、回调及初始自动开始行为保持兼容。现有模型、分区组装和 UI 生命周期继续由控制器管理，这是职责抽离的过渡阶段，尚不是完整独立同步领域模型。

未修改用户可见文案、资源、布局、本地化、SDK 或依赖版本。普通构建中的历史标题原样迁移，没有在本批混入文案调整。

## 2. 兼容性核对

使用迁移前控制器源码建立临时基线，同一组 Swift 行为断言在迁移前方法及迁移后生产 Builder 上均通过。日常检查默认读取新生产文件，不依赖临时基线文件。

另外完成源码差异核对：

- 普通构建方法除名称、显式 PIR 参数及 Space 读取依赖外，业务分支与原方法一致。
- 网关构建方法除名称、依赖读取和明确失败分类外，业务链与原方法一致。
- 排除三处有意修改的构建接口后，控制器剩余源码逐字一致，包括其他场景、发送、ACK 回写、停止、补偿、重试、导航回调和 UI 刷新。
- 两个 Builder 在五个 App target 的实际 Sources phase 中各出现一次；工程配置解析通过。

因此，本批不声称修复轮次竞争或改变已有同步协议行为。

## 3. 新增行为测试

新增 `Tests/Sync/SyncTaskBuilderFixtures.swift`、`Tests/Sync/SyncTaskBuilderTests.swift` 和 `scripts/check_sync_task_builders.py`。

检查脚本加载实际生产 Builder、NodeSyncData 枚举及优先级、列表模型和 TimeSet／退组策略；只以夹具替换 SDK、数据库及协议输入。覆盖：

- 空计划、Group／全部设备作用域、有效成员数量与 Profile 上下文透传、PIR 保护。
- 初始化／入组／Profile 顺序，Lux 锁、阈值、切换、Store 的对象依赖。
- TimeSet 前置，禁用日程先于依赖 TimeSet 的启用日程，缺少 Time Model、非阻塞退组清理。
- 电池／动能开关配置与删除、所属 Group 回退、混合 Scene／参数／消防关联任务。
- 设备、步骤、任务的实际父级身份和初始状态。
- 两种网关恢复 trigger，缺网络／缺密钥／绑定错误，关联新增与旧关联清理、服务器授权子链、最终全链验证。
- 非 WiFi 网关原 MQTT 分支、停用时空活动子网列表、授权之后的 Gateway 对象引用保持动态。
- 注入网络／Space 读取接口，下一次构建重新读取网络、准确失败分类。
- Proxy 优先、Group／设备排序例外，以及可见行与执行遍历的区别。

夹具的消息工厂在构建期被调用会直接失败，用于发现提前生成消息的回归。测试未执行真实 SDK 消息发送和设备状态收敛，也不是 UIKit 布局测试。

## 4. 回归与构建结果

下列十个检查脚本本轮均通过：

| 检查脚本 | 验证内容 |
| --- | --- |
| `python3 scripts/check_sync_task_builders.py` | 新生产构建器行为，以及迁移后的 Gateway 关联清理源码契约；迁移前基线模式也通过 |
| `python3 scripts/check_sync_devices_progress.py` | 连续任务进度、位数切换、首任务失败、重试 |
| `python3 scripts/check_sync_devices_row_display.py` | 设备／Group 显示状态、复用、旧轮次开始事件、重复 UI 写入 |
| `bash scripts/check_wifi_gateway_repair_recovery.sh` | 恢复入口、初始化与最终验证契约 |
| `bash scripts/check_wifi_gateway_server_information_recovery.sh` | 授权入口及共享服务器恢复子链契约 |
| `bash scripts/check_efc_controller_flows.sh` | 消防流程契约及缓存测试 |
| `zsh scripts/check_timed_scheduler_single_owner.sh` | 日程 owner 策略、构建依赖与执行入口契约 |
| `zsh scripts/check_site_timeset_call_sites.sh` | Site TimeSet 调用边界 |
| `bash scripts/check_path_topology_persistence.sh` | 当前脚本包含的拓扑、生命周期、导入、持久化与读回测试组 |
| `bash scripts/check_nordic_sdk_dependency.sh` | 五 target 共享远程 SDK 配置 |

消防、日程、网关的源码检查已迁至实际职责文件，并增加控制器委托关系检查，没有删除业务断言。SDK 源码契约脚本默认使用本地 one-dev；实际 App 构建使用共享锁定的远程 SDK，两个证据范围分别记录。

依次直接运行 `xcodebuild`，workspace 为 `SunSmart.xcworkspace`、Debug、iphoneos、`generic/platform=iOS`、`CODE_SIGNING_ALLOWED=NO`：SunSmart、Archipelago、SylSmart、SLG Sync Plus、Lumineux 均返回 `BUILD SUCCEEDED`。未使用 Simulator、shell 包装或日志重定向。

首次构建因工作区缺失 CocoaPods 生成配置失败；执行 `pod install --deployment` 补齐后通过。未升级版本、未改变锁文件；已移除该命令引入的无关工程排序／注释变化，仅保留 Builder 引用。构建仍有工程原有的 Info.plist 资源和重复 FSCalendar 编译项等警告，本批未调整这些无关配置。

`git diff --check`、新增文件空白检查和工程配置解析通过。未执行 Git 提交或推送；原有两份分析／计划文档保留。

## 5. 后续阶段与验收边界

- 阶段 0 已完成本批构建行为及兼容基线；14 类入口矩阵已在计划中记录，但完整可执行场景覆盖和会话时序用例尚未全部实现。
- 轮次隔离缺口尚未修复。下一批在迁移会话前，需要验证 STOP 后完成、旧轮次收尾晚于新轮次、页面退出后构建完成等时序，并独立修复已复现问题。
- Dongle 删除日程遗漏尚未修复。迁移该场景前，以“仅删除／混合增删”输入建立失败用例并独立修复。
- 后续按 1C → 2 → 3 → 4 推进其他场景构建、执行策略、同步会话和展示收尾；不将本批两个 Builder 视为完整方案 B。
- 本批没有改动 UI 约束、绑定或刷新实现，未进行实际 UIKit 布局测试；已有闪烁修复的真机视觉验收状态不因本批自动测试通过而改变。
- 真实页面全流程、BLE／Mesh、服务器授权读回、PIR／Lux／Profile 补偿仍需按原计划验收。五品牌编译通过不等于设备配置完成。
