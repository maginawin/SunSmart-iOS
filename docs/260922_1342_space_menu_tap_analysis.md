# Space 关闭进入提示框后菜单点击无响应：分析与修复

日期：2026-09-22。工作树：`fix`，HEAD：`ddba3707`。修复已完成，未提交。用户确认正确分支已解决本问题，之前“修复无效”的日志来自运行错误分支。generic iOS Debug 构建和隔离回归通过；临时排查日志已撤去。

## 结论与证据边界

用户确认关闭的是带加载动画、提示文字和右上角 × 的连接提示框；点击需要几秒才恢复，检查按钮上方没有其他视图层覆盖，顶层侧滑一直正常。

源码定位到 HUD 遗留路径：进入 Space 后异步校验成功再次执行 `reloadData()`，重建 Devices 页面；旧页面创建的连接 HUD 挂在 Space 父视图上，未随旧页面清理，被新建的内容滚动视图压到下方。新页面再次创建连接 HUD。若用户关闭新 HUD 后旧 HUD 仍是 unfinished，会导致两层菜单的 `!XWHUDManager.isVisible()` 判断拒绝点击；旧 HUD 自动超时或被连接成功路径结束后，点击恢复。该路径已做隔离复现；生命周期修复后，用户确认正确分支上的问题已解决。

这条链同时解释“按钮上方没有遮挡”“侧滑正常”“等几秒恢复”。用户进一步提供 Group 点击断点结果：`po !XWHUDManager.isVisible()` 返回 `false`。由此已确认故障现场点击进入菜单准入判断，并被 HUD 状态拒绝；直接原因已有用户现场运行证据。二次重建遗留旧 HUD 的来源链由源码支持，尚未通过现场对象标识确认实际两份 HUD；本轮未由代理运行真机。

## 最终现场确认

用户确认：“已修复此问题；刚刚运行错了 branch 代码。”因此此前的失败日志不属于修复版本的回归失败，不再据其扩大修改。

为继续排查临时添加的 `[SpaceHUD]` 日志及菜单判断包装已全部撤去。`ProgressHUD+Extension.swift` 与 `SpaceViewController.swift` 恢复为 HEAD 内容，生产改动仍仅在 `DevicesViewController.swift`。

撤去诊断后，控制器内容 hash 为 `85d71ff78eb5adf250b3f0971457b1d7cdb82386`，与首次已通过构建及回归的修复版本一致；复用该验证结果，不重复构建。源码归属和用户运行确认分开记录：用户确认本问题修复，不代表下列所有边界场景均做过真机验收。

## 修复前重复创建与遗留过程

前提：首次与再次创建 Devices 页面时均有真实设备，Mesh 尚未连接，蓝牙为 poweredOn/unknown；异步 Space 校验在首次连接 HUD 的 10 秒期限内成功，重建时仍停留在 Main。

1. `SpaceViewController.setNetworkConnected()` 的扩展数据加载完成回调位于主线程。它启动 `reconcileLegacyProximityLightingTopology()` 的 MainActor Task，然后立即 `reloadData()`，创建第一份 Devices 页面与连接 HUD A。
2. 后台校验的 `SpaceSyncCleanupCoordinator.prepare` 返回成功后再次 `reloadData()`。这里的 Bool 表示准备成功，并不表示数据发生变化；即使 `didChange == false`，校验正常结束也会成功返回。因此不要求 Space 有待修复的旧数据。
3. `WMPageController.wm_clearDatas` 移除旧子控制器及其 view；`wm_resetScrollView` 移除旧内容滚动视图，再把新内容滚动视图加入 Space 根 view。
4. HUD A 是 `DevicesViewController.viewDidLoad` 添加到 `wm_pageController.view` 的，即 Space 根 view，不属于被移除的 Devices view。旧页面的 `viewDidDisappear` 仅停止引导计时器，`deinit` 也没有结束该 HUD。新内容视图后加入，位于 HUD A 上方。
5. 新 Devices 页面在同样的未连接条件下创建 HUD B。GIF 创建 API 直接分配并添加新对象，不复用、不结束旧 HUD。此时父视图从后向前包含：旧 HUD A、新内容视图、新 HUD B，以及菜单视图。菜单在重建末尾还会被置前。
6. 用户点击 B 的 ×，仅结束 B。`HUDForView` 遍历 Space 根 view 的直属子视图，仍找到 `hasFinished == NO` 的 A；不考虑 A 是否位于内容视图后方。
7. 两层菜单直接拒绝点击。侧滑绕过判断，继续有效。A 从创建时起 10 秒自动隐藏，或被首次 Mesh 连接成功回调结束，菜单恢复；这解释了用户关闭 B 后只需再等剩余的几秒。

正常关闭 B 会立即标记 finished 并取消 B 的延迟隐藏，0.3 秒关闭动画不足以解释持续数秒的现象。在上述遗留路径中，等待的是旧 A 的生命周期。

历史定位：`54804a091`（2026-09-15）将入口校验接入异步 `prepare` 并在成功后增加第二次 `reloadData()`；旧版本的该方法没有这次分页重建。连接 HUD 缺少所属页面清理的问题原本就存在，此入口使其可触发。此项是源码历史定位，不代表已进行旧版/新版设备对照测试。

## 实际调用链

| 环节 | 当前代码行为 | 位置 |
| --- | --- | --- |
| 顶层点击 | `shouldSelesctedIndex` 返回 `!XWHUDManager.isVisible()` | `SunSmart/Main/Space/Controller/SpaceViewController.swift` |
| Main 分类点击 | 使用完全相同的条件，Lights 也受其约束 | `SunSmart/Main/Device/Controller/DevicesViewController.swift` |
| 菜单分发 | `didPressedMenuItem` 在条件为 false 时直接返回，不更新选中项、不调用页面切换 | `SunSmart/Thirdparty/WMPageController/WMMenuView/WMMenuView.m` |
| 顶层侧滑 | 通过滚动回调更新页面与菜单，不调用上述准入判断 | `SunSmart/Thirdparty/WMPageController/WMPageController.m` |
| HUD 判断 | 查找 window 和当前控制器 view 的直属 HUD | `SunSmart/Thirdparty/WYHUDManager/Classes/XWHUDManager.m` |
| HUD 查找 | `HUDForView` 以 `hasFinished == NO` 为返回条件，不判断 hidden、alpha 或是否被其他视图覆盖 | `SunSmart/Thirdparty/WYHUDManager/Classes/WYProgressHUD.m` |

顶层 `SpaceMenuView.isUserInteractionEnabled = false` 是现有展示层设计：实际点击由下层 WMMenuView 接收，其菜单项已启用交互。不能简单把这个 false 改成 true；展示按钮没有配置 action，这样可能反而截断现有点击。

Main 内部分类明确设置 `scrollEnable = false`，与顶层分页的侧滑设置不同。

## 修复前连接提示框关闭路径

1. `DevicesViewController.viewDidLoad` 在 Space 有真实节点、Mesh 尚未连接且蓝牙状态为 poweredOn/unknown 时，创建连接引导 GIF HUD，安排 10 秒后关闭。
2. 随后用全局 `XWHUDManager.currentHUD()` 取对象，保存弱引用并添加关闭按钮。该查找优先取 window HUD，再取当前控制器 HUD，未直接返回刚创建的实例；多个 HUD 时需要明确实例归属。上述两份 Space HUD 的路径中，反向遍历通常取到最新的 B。
3. `ProgressHUD+Extension.closeButtonTapped` 先执行业务回调，再调用该实例的 `hide(animated: true)`。
4. 业务回调停止引导计时器；必要时展示设备地址申请提示。
5. `WYProgressHUD.hideAnimated` 同步设置 `finished = YES`，取消延迟隐藏并执行关闭动画；完成后按 `removeFromSuperViewOnHide` 移除视图。GIF 创建路径已经设置该属性为 YES。

因此，仅重复调用 B 的 hide 不能清理 A。弱引用也不会使 A 自动释放，因为 Space 根 view 仍持有 A。

## 最小修复方案

1. 明确连接 HUD 的实例所有权。创建后直接获取该宿主上的新实例，或让创建 API 返回实例，避免依赖全局 currentHUD 选中其他操作的 HUD。
2. Devices 页面被分页重建移除时，显式结束自己的连接 HUD，并取消本页引导计时器/延迟回调。收口手动关闭、超时、连接成功、页面移除的结束路径，不能仅在 deinit 清理，因为计时任务可能延迟释放旧控制器。
3. 新页面创建前确保同一个 Space 的旧连接提示已结束；关闭提示后保留正常页面浏览能力。当前默认是先修复 HUD 生命周期，不改两层菜单的全局判断，也不取消已有数据校验。
4. “准备成功即全量重建分页”可以作为后续优化另行评估；仅减少第二次 reload 不能替代 HUD 生命周期修复，实际发生数据变更时仍可能重建页面。

现场确认进度：用户修复前在 Group 点击断点确认 `isVisible == true`，修复后确认正确分支已解决问题。不再要求补充 HUD 实例日志。

## 已实施改动

生产代码仅修改 `DevicesViewController.swift`：

- 创建 HUD 后从确定的宿主 view 取回新实例，页面显式持有；不再通过 window 优先的全局查询获取连接 HUD。
- 增加 `willMove(toParent: nil)` 清理，覆盖 WMPageController 的分页重建和缓存移除；`viewDidDisappear` 同样清理，重复调用安全。
- `stopConnectionGuidance` 统一取消计时器及延迟回调、释放实例并按需立即隐藏。手动关闭由现有关闭按钮扩展隐藏，控制器只结束自身状态；超时和连接成功使用相同清理入口。
- 连接成功只结束本页面持有的 HUD，不再全局隐藏，以免旧页面晚到的回调关闭新页面或其他任务的提示框。
- 移除 viewDidLoad 中第二次无条件启动引导计时器的调用；启动函数同时防止覆盖一个仍有效的 timer。

保留异步数据校验、分页刷新、两层菜单的原有 HUD 准入条件以及设备操作的连接/权限检查；没有修改共享 HUD API、SDK、资源或工程配置。

## 自动化验证

- `python3 scripts/check_space_connection_guidance.py --baseline`：提取 HEAD 的原始创建和生命周期代码，在分页调用移除方法后复现 `pagination removal left an unfinished HUD`。
- `python3 scripts/check_space_connection_guidance.py`：提取修改后的真实方法执行，验证分页重建、旧页面晚到的清理、关闭后菜单解锁、window 上无关 HUD 不被误认领/误关闭、连接成功、超时和页面消失。Foundation RunLoop 实际运行 10.1 秒，验证取消的延迟回调不会再次触发地址提示。
- 测试位于 `Tests/Device/SpaceConnectionGuidanceTests.swift`，UIKit/HUD/Mesh 为隔离边界，生命周期与计时清理方法取自生产代码。它不验证真实 UIKit 层级、动画、触摸或 BLE 连接。
- `SunSmartLocal.xcworkspace` / `SunSmart` / Debug / generic iOS / `CODE_SIGNING_ALLOWED=NO`：BUILD SUCCEEDED。复用 DerivedData `SunSmart-fix-cli`。
- SDK 实际映射为 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`，revision `ebbe1c9`，构建前 SDK 工作树干净，本任务未修改 SDK。
- `git diff --check` 通过。共享控制器没有品牌条件分支，本次未改资源归属或公共依赖，因此采用 SunSmart 代表构建。

## 边界验证参考

- 有设备但尚未连上 Mesh：立即关闭连接提示，逐个点击顶层五页与 Main 四个分类，关闭后立即和超过 10 秒均可正常操作。
- 连接成功自动关闭、10 秒超时自动关闭、空 Space/已连接不出现提示三条正常入口。
- 关闭与连接成功回调相邻发生，以及退出再进入，不产生残留 HUD 或重复提示。
- 若调整共享 HUD 判断或生命周期，补验真正阻塞操作的 HUD 仍保留其交互约束。

用户已确认本次菜单问题解决；未提供上述每项边界场景的逐项真机记录，不将其全部标记为通过。
