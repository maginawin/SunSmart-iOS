# Sync Devices 方案 B：会话迁移与停止补偿

日期：2026-09-08。工作区：`refactory-sync-devices`。承接 [第二批结果](260908_1619_sync_devices_plan_b_second_batch.md) 与 [方案 B](260908_1544_sync_devices_plan_b.md)。

## 1. 本轮结果

完成剩余执行职责迁移和 `SyncExecutionSession` 接入。控制器从第二批的 2,176 行降到 839 行，保留入口、展示、展开、选择、激活提示与导航回调。代码迁移和自动验证可以独立完成；实际布局及 BLE／Mesh 全路径验收仍需真机，不能用构建成功代替。

| 组件 | 职责 |
| --- | --- |
| `SyncExecutionSession` | 拥有 sections、运行状态、当前任务、授权取消、任务推进、补偿与自动重试 |
| `SyncSessionCoordinator` | 管理等待通道、运行、补偿、退出和每轮一次完成；补偿期间只记录待开始的重试 |
| `SyncSessionTransportLane` | 在 Sync Devices 会话之间串行交接发送通道，页面关闭后的补偿完成前不启动下一会话 |
| `SyncExecutionEnvironment` | 发送、停止、授权、延迟以及配置／蓝牙可用性接口；将 SDK 回调交到主线程 |
| `SyncCommandStopGate` | 区分 SDK 队列尚未安装与真正完成，避免刚提交消息就 STOP 时误判为空闲 |
| Session 的 Tasks／Operations／Acknowledgement／Result／Daylight／EmergencyFire 文件 | 任务选择、电池规则、动态追加、状态回写、Daylight 修复与消防持久化；共享状态归 Session 所有 |
| `Node+SyncIdentify.swift` | 共用 Identify 方法，不再放在控制器文件中；现有调用方保持不变 |

Session 仍使用现有兼容模型和调用方的嵌套枚举，并未升级为方案 C 的独立领域模型。没有修改 SDK、依赖锁、认证配置、用户文案或品牌资源。

## 2. 执行与停止规则

### 主线程状态所有权

发送循环改为回调推进，应用层任务选择、状态写入、业务回写、补偿和展示事件均在主线程执行。主线程不等待信号量，也不使用 `Thread.sleep`。SDK 成功／失败事件同步交回状态队列，以保留初始化和 Daylight 动态追加时机；整批完成异步交付，使 SDK 可以先清理前一批队列再开始下一批。

后台任务构建方式保留。SDK 内部 Node／Handle 仍由其自身机制管理，本轮不声称解决整个 SDK 的线程安全问题。

### STOP、补偿与重试

1. 从 Session 的真实当前任务记录尚未完成的 Profile 恢复操作，不再根据最后展开的设备猜测。
2. 使旧轮次失效并取消授权等待；旧 ACK、完成、延迟和授权结果不得修改任务状态或启动下一步。
3. 停止传输完成后，按原 0.5 秒延迟执行 Profile 恢复，再执行剩余 PIR 目标恢复，最后发出 Lux 解锁。
4. 补偿完成后交还通道，才执行排队重试或后一同步页面。补偿期间再次 STOP／关闭页面不重复停止 SDK，以免替换补偿自己的完成回调。
5. 页面尚未开始发送时关闭，也通过通道处理已有补偿；没有任务的关闭不会停止别人的发送。页面释放时补充 close，避免异常退出留下等待的会话。

普通任务、每次发送尝试、SDK 停止和补偿阶段均保留一次完成保护。补偿期间关闭会丢弃原成功回调和待开始重试，补偿本身继续收尾。

这条通道只协调新的 Sync Devices 会话，不是整个 App／SDK 所有发送入口的统一锁。没有改动其他页面的传输所有权。

### SDK 首批启动窗口

锁定 SDK 在 `addMessage` 内通过后台队列安装首批 handles 和回调；`stopSendMessage` 在队列为空时直接返回。如果 App 在安装前调用 STOP，不能据此认为该批已经停止。

适配器现在等待 SDK 的进度／响应开始事件后再停止；如果连接失败或整批完成先到达，直接完成停止等待。回调携带批次身份，旧批次完成不能结束新批次。此规则通过可控门禁测试，不以固定睡眠推测队列是否已经安装。

### 保留的业务行为

- 消息在实际轮到任务时生成；服务器授权完成后才创建下一步服务器信息消息。
- 先按 Handle 结果调用 Node 回写和清缓存，再计算业务成功。
- Repair、普通恢复、电池本体与消防删除保留原成功例外；消防删除 5 秒超时、3 次尝试、0.2 秒间隔不变。
- 电池初始等待 1 秒、按键配置成功后等待 0.5 秒不变，激活界面仍由控制器展示。
- 自动恢复仍最多两次附加重试；通过会话意图重试，不再模拟点击“全选”和“重试”按钮。电池激活继续通过明确的 UI 请求处理。
- `backActionCallback` 仍由调用方负责关闭；结果汇总范围和成功回调接口不变。

54 个迁移辅助方法在消除空白、注释及传输／刷新委托名称差异后，方法体一致。调度和补偿顺序属于本轮明确改动，不纳入“等价搬迁”结论。

## 3. 自动验证

`check_sync_execution_session.py` 编译执行实际 Session 主体、任务选择、回写、重试、兼容模型、Coordinator 和启动门禁。传输、授权、时钟及部分专用协议对象使用替身。

覆盖：正常推进、重复完成只回写一次、STOP 后立即重试、迟到完成、Profile／PIR 补偿顺序、旧授权取消、授权后动态消息、自动重试预算、补偿期间关闭、跨页面通道顺序、未持有通道的页面退出、SDK 首批启动时停止、迟到停止回调、同步返回的适配器停止完成。

这些测试不能证明真实 SDK／Mesh 收敛，也不等于 14 类业务的端到端执行覆盖。消防及电池协议行为还使用既有源码契约和完整 App 构建验证。

| 检查 | 结果 |
| --- | --- |
| `python3 scripts/check_sync_execution_session.py` | 通过，新增生产会话与协调测试 |
| `python3 scripts/check_sync_run_lifecycle.py` | 通过，实际构建安装函数与轮次兼容测试；旧控制器收尾测试已迁往 Session 测试 |
| `python3 scripts/check_sync_task_builders.py` | 通过，生产构建器、成功矩阵、重试与结果汇总 |
| `python3 scripts/check_sync_devices_progress.py` | 通过 |
| `python3 scripts/check_sync_devices_row_display.py` | 通过 |
| `bash scripts/check_efc_controller_flows.sh` | 通过，执行断言按职责迁至 Session 文件 |
| 两个 WiFi Gateway recovery 脚本 | 通过 |
| `zsh scripts/check_timed_scheduler_single_owner.sh` | 通过 |
| `zsh scripts/check_site_timeset_call_sites.sh` | 通过 |
| `bash scripts/check_path_topology_persistence.sh` | 通过，完成通知归属迁至 Session |
| `bash scripts/check_nordic_sdk_dependency.sh` | 通过 |
| 新文件 Sources 登记 | 累计 25 个新增生产文件，各进入五个 target 一次 |
| `git diff --check` | 通过 |

五品牌使用直接 `xcodebuild`，Debug、iphoneos、generic iOS、关闭签名。SDK 仍锁定远程 release `86f5ec9e40148b9cd93e0512702337fcec41dd40`。

| Scheme | 最终验证 |
| --- | --- |
| SunSmart | 通过 |
| Archipelago | 通过 |
| SylSmart | 通过 |
| SLG Sync Plus | 通过 |
| Lumineux | 通过 |

## 4. 真机验收准备及剩余边界

后续更新：已按用户指定在 MtestiPhone15 安装当前工作区 SunSmart，并在 Sep 8 2 / Space 2 完成 Profile 同步、STOP、RE-SYNC、立即重试和原值恢复。七项分阶段真实 App 测试通过，详见 [MtestiPhone15 验证记录](260908_1725_sunsmart_mtest_space2_validation.md)。

后续更新：已确认生产 App 在 iPad 上仅支持竖屏，并按用户要求移除横屏测试。MiPAD 竖屏实际测试已通过，详见 [MiPAD 竖屏验证](260908_1652_sync_devices_mipad_portrait_validation.md)。以下为本轮结束时的准备记录。

已更新 `prepare_sync_devices_row_ui_tests.py`，将生产 `displayTaskStarted` 和可见行刷新逻辑接入独立布局工程，使用实际 UIKit Cell 和 SnapKit 约束。新增旧轮次／页面关闭后事件不得改变展开状态的检查，保留连续 12 个任务、9→10 进度、首项失败、重试、复用及横竖屏测试。

生成工程：`/tmp/SyncDevicesRowLayout/RecoveryLayout.xcodeproj`。无签名 `build-for-testing` 已通过，尚未安装和运行真机测试，未使用 Simulator。生成脚本修复了重复生成时 SnapKit 只读副本无法覆盖的问题，只调整隔离工程副本。

已向用户请求选择当前可用的 `MtestiPhone15` 或 `MiPAD`，避免把测试 App 安装到错误设备。在设备选定并执行成功前，实际布局验收保持未完成。

独立布局测试之后仍需实际同步页面和设备验证：Group 入退组、Profile SAVE、STOP 后重试、push／present／调用方关闭、网关授权与读回、Dongle 删除、电池激活、消防部分删除及 PIR／Lux／Profile 恢复。代码编译、替身回归、真实 UIKit 布局和真实设备配置分别记录，不能相互替代。

本轮未提交、推送或合并 Git 改动，保留既有未提交修改与用户分析文档。
