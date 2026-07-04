# Groups 单击 Bugly 崩溃分析与修复计划

## 背景

Bugly 栈显示崩溃发生在 `GroupsViewController.groupHandleSingleTap(_:)` 内部的 Swift 数组下标访问：

- `Swift.Array.subscript.getter`
- `GroupsViewController.groupHandleSingleTap(_:)`
- `GroupsViewController.collectionView(_:didSelectItemAt:)` 内部 `NSTimer` 回调

对应当前代码位置：

- `SunSmart/Main/Group/Controller/GroupsViewController.swift:204-220`
- `SunSmart/Main/Group/Controller/GroupsViewController.swift:551-575`

## 结论

这是一个真实存在的数组越界崩溃。根因不是 `LightGroupControlCommandSender` 本身，而是组列表单击逻辑用 0.22 秒 `Timer` 延迟判断单击/双击，Timer 回调里继续使用点击时捕获的旧 `IndexPath` 访问最新的 `MeshNetworkManager.instance.groups`。

只要这 0.22 秒内组数组发生删除、刷新、重新排序或数量减少，旧 `indexPath.item` 就可能不再有效，从而在 `MeshNetworkManager.instance.groups[indexPath.item]` 触发 Swift 数组越界。

## 证据链

1. `didSelectItemAt` 首次点击时不会立即执行单击，而是创建 0.22 秒 `Timer`，并在回调中调用 `groupHandleSingleTap(indexPath)`。
2. `groupHandleSingleTap(_:)` 直接读取 `MeshNetworkManager.instance.groups[indexPath.item]`，没有边界检查，也没有按 group identity 重新确认目标是否仍存在。
3. 双击路径和长按路径已有 `indexPath < groups.count` 防护，单击路径缺失该防护。
4. 新增/删除组会触发 `groupsRefreshNotificationName`，列表页收到后执行 `updateUI()` 和 `collectionView.reloadData()`。
5. 删除组最终调用 `meshNetwork.remove(group:)`，会真实改变底层 groups 数组。
6. 当前 HEAD 最近一次相关改动 `a471d8c6 feat: lab custom TTL` 只把下发入口从 `MeshAPI.setGroupOnOffState` 替换为 `LightGroupControlCommandSender.setGroupOnOff`，没有引入数组访问；延迟点击和未检查下标来自 2025-11-07 的历史改动。

## 可触发场景

典型场景是：

1. 用户在 Groups 列表点击某个 group，尤其是最后一个 item。
2. 单击 Timer 尚未触发，等待 0.22 秒内列表发生结构变化，例如删除 group、同步刷新、从其他页面发出 groups refresh。
3. Timer 触发，继续用旧 index 读取最新 groups 数组。
4. 如果旧 index 已越界，App 崩溃。

这个窗口很短，手工不一定稳定复现，但 Bugly 栈和当前代码可以完整闭环。

## 修复方案

### 推荐方案 A：用稳定 group address 作为点击目标

将延迟点击状态从“旧 `IndexPath`”改成“点击时的 group address + 当时 indexPath”。执行单击时按 address 到当前 `MeshNetworkManager.instance.groups` 重新查找 group：

- 如果 group 仍存在：控制这个真实 group。
- 如果 group 已被删除：清理 pending tap 并直接 no-op。
- 如果列表插入或排序导致 index 变化：仍然控制原本点击的 group，而不是误控当前 index 上的其他 group。

同时把单击 handler 改成接收已确认的 group 或 group address，不再在 handler 内盲目使用数组下标。

双击路径保留当前 UI 位置用于弹菜单，但也要先从当前列表安全取出 group，并用 address 与 pending tap 做一致性判断；菜单项闭包里同样按 address 重新解析当前 group，避免菜单显示后 group 被删导致二次越界或误控。

### 备选方案 B：只加下标边界检查

在 `groupHandleSingleTap(_:)` 开头增加 `indexPath.item < groups.count` 防护，越界时直接 return。

这个方案改动最小，但只能防崩溃；如果 0.22 秒内列表前面插入或重排，旧 index 仍可能指向另一个 group，存在误控风险。因此不推荐作为最终方案。

## 具体修改计划

1. 在 `GroupsViewController` 中新增 pending tap 状态，保存 group address 和原始 indexPath；替换现有只保存 `lastTappedIndexPath` 的状态。
2. 在 `didSelectItemAt` 入口先安全读取当前 index 对应的 group；如果 index 已无效，清理 Timer 和 pending tap 后返回。
3. 首次点击时保存 pending tap，并让 Timer 回调按 group address 执行单击。
4. 快速点击不同 group 时，先执行上一个 pending address 对应的单击；如果上一个 group 已不存在，则 no-op。
5. 双击时，比较当前 group address 与 pending address；匹配才走双击菜单，不匹配则按“切换点击目标”处理。
6. `groupHandleSingleTap` 改为 address 或 group 入参，内部不再用 `IndexPath` 访问数组。
7. `groupHandleDoubleTap` 改为先使用已安全解析的 group；菜单闭包内也按 address 重新解析。
8. 在 `deinit` 或页面离开时清理 `tapTimer`，避免页面生命周期结束后仍触发控制命令。

## 验证计划

1. 运行 iPhoneOS 构建：

   `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

2. 手工验证 Groups 列表：

   - 单击 group：ON/OFF 正常切换。
   - 双击同一个 group：AUTO/TEST 菜单正常出现。
   - 0.22 秒内快速点击两个不同 group：前一个单击仍按原 group 执行，不误控新 index。
   - 删除 group 后返回列表：不崩溃，列表刷新正常。
   - 新增 group 后返回列表：不崩溃，列表刷新正常。

3. 回归确认：

   - Emergency manual-control blocked 提示仍生效。
   - Daylight/manualControl group 的 TEST 菜单隐藏逻辑不变。
   - `LightGroupControlCommandSender` 的 TTL 行为不回退。

## 建议

建议采用方案 A。它不仅修复越界，还避免列表结构变化后误控错误 group，属于更完整的根因修复；方案 B 只适合临时止血。
