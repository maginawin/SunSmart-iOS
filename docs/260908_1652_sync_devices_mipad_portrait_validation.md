# Sync Devices：MiPAD 竖屏验证

日期：2026-09-08。承接 [方案 B 会话迁移结果](260908_1642_sync_devices_plan_b_session.md)。

## 方向支持确认

生产 App 在 iPad 上仅支持竖屏：`Config/Common/AppBase.xcconfig` 声明 `UIRequiresFullScreen = YES`、`UISupportedInterfaceOrientations = UIInterfaceOrientationPortrait`。五个品牌的源码 Info.plist 均没有 iPad 专用方向覆盖，也未找到业务控制器或 AppDelegate 的方向放开逻辑。

再次读取当前 DerivedData 中 SunSmart、Archipelago、SylSmart、SLG Sync Plus、Lumineux 的实际 App Info.plist，五者均为全屏、仅竖屏，无 `UISupportedInterfaceOrientations~ipad` 覆盖。

此前独立布局工程继承通用模板，额外允许横屏，范围与生产 App 不一致。横屏测试曾发现 29.82 pt 行高小于 30 pt 箭头，但此方向不属于生产 App 支持范围。按用户要求删除横屏测试，并撤回为此临时增加的 44 pt 行高下限；生产行高恢复为原来的 `SCRYFrom(44)`。

## 最终改动

- `prepare_sync_devices_row_ui_tests.py` 仅生成 `testPortrait`，独立 App 配置为全屏、仅竖屏。
- 测试直接提取生产 `heightForRowAt`，与现有生产 Cell、约束、可见行刷新、任务开始事件共同运行，避免测试自行复制行高策略。
- 布局失败通过 XCTest 报告详细坐标并保留截图，不再主动触发 `fatalError`。额外断言实际窗口高度大于宽度。
- 本次方向确认未修改生产方向配置、品牌资源、本地化或 SDK。横屏不再列为待验收项。

## MiPAD 实际执行

设备：MiPAD，iPad Air（第 5 代），iPadOS 26.6.1（23G83）。使用独立测试 App `com.sunricher.sync-row-layout-test`，直接运行 `xcodebuild test` 指向该物理设备，未使用 Simulator。

最终结果：`SyncRowUITests.testPortrait` 通过，**1 项测试，0 失败，0 跳过**，测试用例耗时约 7.76 秒；`xcodebuild` 返回 `TEST SUCCEEDED`。已读取 xcresult 汇总并人工查看导出的截图。

竖屏下覆盖连续 12 个任务、首任务失败、9→10 进度、任务间隙、重试、重新绑定模拟离屏返回、展开状态刷新、旧轮次事件与页面关闭后的事件隔离。检查箭头居中及范围、进度与状态图标无重叠、任务间隙图标可见性及 Cell 身份稳定。最终截图显示重试中的 `11/12`，属于测试预期。

结果包：`/tmp/SyncDevicesRowLayout/MiPAD-portrait-20260908.xcresult`。

截图：[MiPAD 竖屏](assets/260908_sync_devices_mipad/portrait.png)。

补充检查：`python3 scripts/check_sync_devices_row_display.py` 与 `git diff --check` 通过。此前方案 B 五品牌构建记录见会话迁移文档；本次最终生产代码未保留横屏行高改动。

## 验收边界

本次完成真实 iPad 上的 UIKit 行布局与事件显示验证。独立工程的传输和业务对象仍有替身，未执行真实 BLE／Mesh 配置，也不覆盖生产页面完整导航、进度弹层、电池激活和服务器授权。实际设备同步、STOP 后重试、Profile／PIR／Lux 恢复、Dongle／消防删除等业务验收仍需另行执行。

未提交、推送或合并 Git 改动，保留此前工作区修改。
