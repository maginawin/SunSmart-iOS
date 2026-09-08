# SunSmart App：MiPAD 自动化验证

日期：2026-09-08。工作区：`refactory-sync-devices`。

## 结论

能够自动启动并操作 MiPAD 上的真实 SunSmart App。本轮已将当前工作区 Debug 开发包构建、签名并原位安装到 MiPAD，通过 XCTest 执行真实页面点击、导航、截图和断言。最终流程测试 **1 项通过、0 失败、0 跳过**。

本轮测试目标为 `com.azoula.sunsmart`。它与此前仅运行生产 Cell 的独立布局 App 是不同的验证层次；独立 runner 仅负责驱动，实际页面来自已安装的 SunSmart。

## 构建与设备

- MiPAD：iPad Air（第 5 代），iPadOS 26.6.1（23G83）。
- App：SunSmart 1.2.1（1），Bundle ID `com.azoula.sunsmart`。
- 从当前工作区直接运行 `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart`，Debug、iphoneos、MiPAD 物理目标，签名构建成功。
- 通过 `devicectl device install app` 原位安装，没有卸载、清空 App 或重建 Site／Space。安装后原有 Sites 列表仍可访问；本轮不代表完整数据库一致性审计。
- 本次构建的 `SunSmart.debug.dylib` UUID：`F68304B4-792A-30A8-9527-9F003E6FDAE6`。不能仅用相同的版本号推断安装包包含哪些改动，因此记录本次构建与安装链路。
- SDK 保持远程 release `86f5ec9`。仅测试竖屏，未使用 Simulator。

## 实际流程与断言

1. 启动真实 SunSmart，等待前台运行状态和主窗口。
2. 检查 Sites 页面，点击 `FAVOURITES` 并断言选中。
3. 返回 `ALL SITES` 并断言选中。
4. 打开已存在且无 Space 的 `Site 1`，确认导航标题与 `No Spaces!` 空态。
5. 点击 `navigation back`，确认返回 Sites，`ALL SITES` 保持选中。
6. 截图节点检查实际窗口高度大于宽度，保存截图和 Accessibility 层级。

最终测试：`SunSmartAppSmokeUITests.testSunSmartPortraitNavigation`，耗时约 13.03 秒，`TEST SUCCEEDED`。最终 App 留在 Sites 页面。

证据：

- XCTest 结果包：`/tmp/SunSmartAppSmoke/MiPAD-current-worktree.xcresult`。
- 本次 runner 工程：`/tmp/SunSmartAppSmoke/RecoveryLayout.xcodeproj`；使用 `RecoveryLayout` scheme 驱动外部 App。
- [测试源码快照](assets/260908_sunsmart_mipad_app/SunSmartAppSmokeUITests.swift)。该快照依赖本次设备的英文界面和已有 `Site 1` 数据，不能视为任意账户通用用例。
- [收藏列表截图](assets/260908_sunsmart_mipad_app/favourites.png)。
- [Site 1 空间空态截图](assets/260908_sunsmart_mipad_app/empty-spaces.png)。
- [返回 Sites 截图](assets/260908_sunsmart_mipad_app/sites.png)。

正式安装前还用已有安装版验证过启动、读取页面和导航能力；最终结论以当前工作区安装后的结果包为准。

## 剩余范围

后续更新：用户最终指定 MtestiPhone15 / Sep 8 2 / Space 2；已完成该环境的真实同步、STOP、重试和参数恢复，详见 [MtestiPhone15 验证记录](260908_1725_sunsmart_mtest_space2_validation.md)。下面保留本轮 MiPAD 初次自动化结束时的范围记录。

尚未进入指定的测试 Space 执行 Sync Devices、STOP、重试或删除。已向用户请求具体 Site／Space 及可操作测试设备，当前等待该环境信息。

本轮通过证明真实 App 可被自动化驱动以及上述页面流程正常，不能证明真实 Mesh 同步收敛、Profile／PIR／Lux 补偿、网关授权、电池激活、Dongle 或消防删除已完成验收。得到测试目标后，可继续自动执行相应流程并结合真实设备结果判断。

本轮未修改生产业务代码、认证配置或资源；未提交、推送或合并 Git 改动。
