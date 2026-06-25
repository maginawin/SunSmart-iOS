# Site - Space - Main 页面被上层 UI 阻断交互分析

## 背景

测试反馈：在 `Site - Space - Main` 页面上层出现一层 UI，导致当前页面不能交互，也不能返回。当前还没有稳定复现步骤，需要先按代码事实分析可能来源，再确认修复方案。

本轮只做分析与方案确认，不修改代码。

## 结论

最高概率原因是 window 级自定义遮罩残留，尤其是 `MenuPopView`。它直接加到 `keyWindow`，覆盖全屏，并通过透明 `shadeView` 拦截点击；如果残留在 `Site - Space - Main` 上方，就会表现为页面不能点、导航返回也点不到。

最近 Information push 动画补丁本身不是直接遮罩来源：`pushDeviceInformationController` 只给 `navigationController.view.layer` 添加 `CATransition`，不会创建 view，也不会永久占用触摸。但本轮曾改过全局 `MenuPopView` 的 dismiss 行为，所以需要把菜单残留作为第一优先级排查。

## 可能原因

### 1. `MenuPopView` 叠加或残留

证据：

- `MenuPopView.show(...)` 每次都会创建新的全屏 `MenuPopView(frame: UIScreen.main.bounds)`，并直接 `addSubview` 到 `UIApplication.shared.keyWindow()`。
- `show(...)` 没有先清理已有 `MenuPopView`，如果快速重复点击右上角菜单，理论上可以叠多层。
- `MenuPopView.hide()` 只找 `keyWindow.subviews.first(...)`，不是移除全部，也不是移除最上层。如果已经叠了多层，可能只移除其中一层，剩余全屏透明遮罩继续拦截交互。
- Space Main 的右上角菜单 `SpaceViewController.moreClick()` 也直接调用 `MenuPopView.show(...)`，没有 show 前清理或防重复。
- Space 页面只有蓝牙断开等少数路径会调用 `MenuPopView.hide()`，普通返回、push、present 没有统一清理所有 window 级 menu。

现象匹配：

- 如果残留的是 `MenuPopView`，页面上可能看不到明显黑色蒙层，因为它的 `shadeView.backgroundColor` 被注释了，但仍然是全屏可交互 view。
- 点击返回按钮无效，因为触摸先被 window 顶层的透明遮罩接走。

### 2. `SyncDevicesProgressView` 残留

证据：

- `SyncDevicesProgressView.show(...)` 同样直接把全屏 view 加到 `keyWindow`。
- 它包含半透明黑色 `shadeView` 和中间同步列表，如果 `hide()` 没走到，会阻断页面交互。

现象判断：

- 如果用户看到的是黑色半透明蒙层或同步任务列表，优先怀疑它。
- 如果只是页面像被透明层盖住、没有列表内容，则它不是第一嫌疑。

### 3. `ConfigurationFlowGuidanceView` 残留

证据：

- `ConfigurationFlowGuidanceView.show()` 也加到 `keyWindow`，有半透明遮罩和白色引导面板。
- Space 入口、退出同步时会尝试 `ConfigurationFlowGuidanceView.current()?.hide()`，但如果出现 show/hide 时序错位，也可能短时间残留。

现象判断：

- 如果看到白色引导面板或配置流程提示，才优先怀疑它。
- 如果没有引导内容，则优先级低于 `MenuPopView`。

### 4. `XWHUDManager` window 级 HUD 残留

证据：

- Space 连接、删除、同步等路径会调用 `XWHUDManager.showCustomHUD(...)`。
- `SpaceViewController.menuView(_:shouldSelesctedIndex:)` 和 `DevicesViewController.menuView(_:shouldSelesctedIndex:)` 都会在 `XWHUDManager.isVisible()` 时禁止 tab 切换。

现象判断：

- 如果看到 loading、blur 小面板或文案，可能是 HUD 没有 hide。
- 如果没有 HUD 内容、只是透明遮罩，优先级低于 `MenuPopView`。

### 5. Information push 动画的间接影响

证据：

- 当前新增的 `pushDeviceInformationController(...)` 只执行 layer transition + `pushViewController(..., animated: false)`。
- `CALayer.addMoveInAnimation(...)` 使用 `CATransition`，没有 `isRemovedOnCompletion = false` 或 `fillMode = forwards`，不会留下 view。

判断：

- 它不太可能直接造成“上层 UI 蒙住页面”。
- 但如果进入/返回 Information 的操作发生在菜单 dismiss 未完成、或页面切换期间重复点击菜单，仍可能暴露 `MenuPopView` 的全局遮罩叠加问题。

## 建议确认方式

1. 复现时观察蒙层外观：
   - 透明且没有内容：优先 `MenuPopView`。
   - 黑色半透明并有同步列表：优先 `SyncDevicesProgressView`。
   - 白色引导面板：优先 `ConfigurationFlowGuidanceView`。
   - loading/blur 小面板：优先 `XWHUDManager`。

2. 加一条临时调试日志或断点：
   - 在 `keyWindow.subviews` 中统计 `tag == 100` 的 view 类型。
   - 重点看是否存在多个 `MenuPopView`，或是否在 Space Main 顶层残留 `SyncDevicesProgressView` / `ConfigurationFlowGuidanceView`。

3. 尝试复现路径：
   - 快速重复点击 Space Main 右上角菜单。
   - 菜单打开时点击菜单项进入子页面，再快速返回。
   - 进入 Light 设备 Information 后返回 Space Main，再操作 Space Main 菜单。
   - 同步/删除/连接 HUD 出现时切后台、返回、或切页面。

## 推荐修复方案

推荐方案 A：统一收口 window 级菜单/遮罩生命周期。

- `MenuPopView.show(...)` 前先清理所有已有 `MenuPopView`，避免重复叠加。
- `MenuPopView.hide()` 改为清理所有 `MenuPopView`，而不是只清理第一个。
- Space Main 的 `moreClick()` 在 show 前主动调用清理，避免快速重复点击叠层。
- Space 页面普通离开时补最小范围清理：至少清理 `MenuPopView`，不要直接移除所有 `tag == 100`，避免误伤正在展示的合法 alert / sync progress。
- 保持 Information push 动画 helper 不动，除非后续证据证明它和导航状态冲突。

备选方案 B：只在 Space Main 做局部兜底。

- 只在 `SpaceViewController.moreClick()` 前后处理 `MenuPopView`。
- 风险是 Site、Device、Gateway 等其他页面继续可能叠加同类透明菜单。

备选方案 C：加调试探针后再修。

- 先增加 DEBUG 下的 window overlay dump，等用户复现后看真实残留类型。
- 优点是证据最硬；缺点是修复慢，且当前代码已经存在明确的 `MenuPopView` 叠加风险。

## 待确认

建议采用方案 A。它改动范围小，聚焦在 `MenuPopView` 生命周期和 Space 页面离开清理，不改变业务流程，也不会影响 Information push 动画逻辑。

## 执行记录

已确认采用方案 A，并按最小范围执行：

- `MenuPopView.show(...)` 在创建新菜单前先 `hide(animation: false)`，避免快速重复点击菜单时叠加多个全屏透明遮罩。
- `MenuPopView.hide(...)` 改为收集并 dismiss 所有 `MenuPopView`，而不是只移除第一个匹配项。
- `SpaceViewController` 新增 `clearTransientWindowMenus()`，只清理 `MenuPopView`，不误伤 `SyncDevicesProgressView`、`SRAlertView`、`ConfigurationFlowGuidanceView` 等其他 window 级 UI。
- Space Main 打开右上角菜单前主动清理旧菜单。
- Space 页面 `viewWillDisappear` 时清理 transient menu，避免 push / present / 返回过程中遗留透明菜单遮罩。

新增检查脚本：

- `scripts/check_space_main_overlay_cleanup.sh`

已验证该脚本先在旧逻辑下失败，修复后通过。

最终验证：

- `bash scripts/check_space_main_overlay_cleanup.sh` 通过。
- `bash scripts/check_device_information_menu_transition.sh` 通过，确认没有破坏 Information 菜单动画修复合同。
- `git diff --check` 通过。
- `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build` 通过。
