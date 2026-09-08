# SunSmart：MtestiPhone15 / Sep 8 2 / Space 2 真机验证

日期：2026-09-08。工作区：`refactory-sync-devices`。承接 [方案 B 会话迁移](260908_1642_sync_devices_plan_b_session.md)。

## 结果

已将当前工作区 SunSmart 签名构建并原位安装到用户指定的 **MtestiPhone15**，自动进入 **Sep 8 2 → Space 2**，完成真实 App 的导航、成员读取、Profile 保存、STOP、选择失败项、RE-SYNC、立即重试和原值恢复。七个分阶段 XCTest 结果包全部通过：**7 项通过，0 失败，0 跳过**。

最后停留在 Space 2 的 Main 页面，Group 1-L2、Group 1-L3 均显示在线。测试用 Manual override timeout 已从临时的 12 分钟恢复为原始 11 分钟，并完成同步与重新打开页面确认。本轮未发现需要继续修改生产代码的阻断问题。

## 安装与环境

- 物理设备：MtestiPhone15，iPhone 15，iOS 26.6.1（23G83）。
- UDID：`00008120-001445243C44A01E`。
- App：SunSmart 1.2.1（1），`com.azoula.sunsmart`。
- 直接使用 `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart`，Debug、iphoneos、指定物理设备，签名构建成功；随后通过 `devicectl device install app` 原位安装。
- 安装包来自当前工作区，`SunSmart.debug.dylib` UUID：`F68304B4-792A-30A8-9527-9F003E6FDAE6`。
- 测试通过独立 XCTest runner 驱动实际安装的 SunSmart。业务页面与 Mesh 传输使用生产 App；不是独立 Cell 布局 App 的模拟业务结果。
- 仅使用竖屏，未使用 Simulator。

## 实际测试路径

| 阶段 | 实际操作及结果 | XCTest 结果包（位于 `/tmp/SunSmartAppSmoke/`） |
| --- | --- | --- |
| 进入指定环境 | 启动 SunSmart，进入 Sep 8 2，再进入 Space 2 | `Mtest-space2-entry.xcresult`，通过 |
| 成员与连接 | 两盏灯显示在线；进入 Group 1，打开 Members，确认 L2、L3 均为成员 | `Mtest-group-members.xcresult`，通过 |
| 原始参数 | 打开 Profile：Proximity/Predictive Lighting；读取 Manual override timeout = 11 min | `Mtest-profile-original.xcresult`，通过 |
| 保存与 STOP | 只将 timeout 增加一次至 12 min，SAVE 后点击 Stop；出现 RE-SYNC | `Mtest-profile-stop.xcresult`，通过 |
| 失败项重试 | 未选中时 RE-SYNC 禁用；Select all 后启用；重试成功自动返回 Group 1；重新打开 Profile 显示 12 min | `Mtest-profile-retry.xcresult`，通过 |
| 恢复与立即重试 | timeout 减少一次回到 11 min，SAVE → Stop → Select all → RE-SYNC 连续操作；同步结束自动返回 Group 1；重新打开确认 11 min；不再修改并 SAVE，返回 Group 1 | `Mtest-profile-restore-immediate-retry.xcresult`，通过 |
| 最终状态 | 返回 Space 2 Main，断言两盏灯存在、在线图标数量为 2，检查竖屏窗口并截图 | `Mtest-final-space2.xcresult`，通过 |

第一次 STOP 截图显示 Configuration 共四项：PIR Disable、L2、L3 已成功，PIR Enabled 被停止并显示失败，底部进度为 3/4。重试只选择失败项；已成功项的显示未被清空。

恢复原值的一轮没有在 STOP 与 RE-SYNC 之间人为等待。XCTest 事件记录中 Stop 点击约在测试第 3.36 秒，RE-SYNC 点击约在第 4.37 秒；随后正常结束。该记录验证用户快速重试路径可完成，不能单独证明内部补偿的每条消息及毫秒级顺序。

已查看 STOP、重试、恢复参数及最终页面的真实截图。Sync Devices 页的标题、状态图标、任务进度和底部选择控件没有发现遮挡或重叠。此次四项配置任务不覆盖长列表复用；长列表布局另见 [MiPAD 竖屏验证](260908_1652_sync_devices_mipad_portrait_validation.md)。

## 证据

- [指定 Site](assets/260908_sunsmart_mtest_space2/site-sep-8-2.png)、[在线成员](assets/260908_sunsmart_mtest_space2/members-online.png)。
- [STOP 后状态](assets/260908_sunsmart_mtest_space2/sync-stopped.png)、[重试中](assets/260908_sunsmart_mtest_space2/retry-running.png)、[重试成功返回](assets/260908_sunsmart_mtest_space2/retry-completed.png)。
- [恢复时立即重试](assets/260908_sunsmart_mtest_space2/immediate-retry.png)。
- [原始 11 min](assets/260908_sunsmart_mtest_space2/original-timeout.png)、[重新打开后恢复为 11 min](assets/260908_sunsmart_mtest_space2/restored-timeout.png)。
- [最终 Space 2 页面](assets/260908_sunsmart_mtest_space2/final-space2.png)。
- 测试源码快照：[STOP](assets/260908_sunsmart_mtest_space2/ProfileStopUITests.swift)、[重试](assets/260908_sunsmart_mtest_space2/ProfileRetryUITests.swift)、[恢复与立即重试](assets/260908_sunsmart_mtest_space2/ProfileRestoreImmediateRetryUITests.swift)、[最终检查](assets/260908_sunsmart_mtest_space2/FinalSpaceStateUITests.swift)。

这些源码为本次分阶段执行快照，各自依赖上一阶段留下的页面状态；不能将同名测试类直接合并编译，也不能当作任意账户的通用测试。完整执行记录、时间线和附件保存在上述 xcresult 中。

## 验收边界

本次已验证真实 App、在线灯具环境中的 Profile 同步与停止／重试页面流程，成功回调可以正常返回调用页面，并恢复本次修改的配置值。

仍未进行独立协议抓包、设备侧参数 Get 读回、断电重启后的持久化验证或实际人体感应行为观测。因此，页面显示成功及 App 保存值恢复不能替代 PIR／Lux 补偿的硬件行为验收。网关授权、电池激活、Dongle、消防删除、其他任务类型及全部跨页面竞争场景也不属于此次两盏灯的覆盖范围。

本轮没有更改成员、Profile 类型、邻居拓扑或认证信息，没有卸载清空 App；未新增生产业务代码改动，未提交或推送已有工作区改动。
