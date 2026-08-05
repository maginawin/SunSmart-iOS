# Groups KVO Crash 修复实施总结

## 1. 实施结果

已按确认的方案 A 完成 `GroupsViewController` 的最小 KVO 生命周期修复：

- 将 `networkable` 从旧式手动 KVO 迁移为 `NSKeyValueObservation` token。
- Controller 的 View 从未加载时，token 保持为 nil，析构不再移除未注册的观察者。
- 移除旧式 `addObserver`、`removeObserver` 和通用 `observeValue`。
- 网络状态变化后先切回主线程，再进入 Group 地址申请提示逻辑。
- 未修改 `WMPageController`、create space 流程、地址申请条件、本地化、资源、target 配置或依赖。

## 2. 改动文件

- `SunSmart/Main/Group/Controller/GroupsViewController.swift`
- `Tests/Group/GroupsViewControllerKVOContractTests.swift`
- `docs/260804_1512_create_space_groups_kvo_crash_analysis.md`
- `docs/260804_1537_groups_kvo_crash_implementation_summary.md`

## 3. TDD 证据

### RED

新增契约后，在旧实现上运行失败，退出码为 133，失败信息为：

`GroupsViewController must retain an optional KVO observation token`

该失败直接对应本次缺陷：旧实现没有 token，并在析构时无条件移除观察者。

### GREEN

完成最小修改后，同一契约编译并运行通过：

`GroupsViewControllerKVOContractTests passed`

契约覆盖：

- 持有可选 KVO token；
- 使用 token-based `networkable` 观察；
- 回调弱引用 Controller；
- UI 分支进入主线程；
- 不再包含旧式手动注册、移除和通用 KVO 回调。

说明：这是 standalone 源码契约，不是 UIKit 真机生命周期测试；它用于防止实现回退，不能替代真机复现。

## 4. 构建验证

以下命令均使用 Debug、generic iPhoneOS、`CODE_SIGNING_ALLOWED=NO`，没有使用 Simulator：

- `SunSmart`：BUILD SUCCEEDED。
- `Archipelago`：BUILD SUCCEEDED。
- `SLG Sync Plus`：BUILD SUCCEEDED。
- `SylSmart`：BUILD SUCCEEDED。

构建日志仍包含工程既有警告，例如重复 asset symbol、历史 API deprecated 和无 AppIntents 依赖；本次改动没有新增 target、资源或依赖。

## 5. 真机稳定复现方法

建议对修复前 build 和修复后 build 使用完全相同的步骤。

### LLDB 稳定复现

1. 使用 Debug build，在 Xcode 添加 `All Objective-C Exceptions` 异常断点。
2. 创建并进入一个空 Space。
3. 在 `SpaceViewController.setNetworkConnected()` 的 Mesh 扩展数据完成回调中，对 `self.loadNetworkData = true` 设置源码断点；当前约第 700 行。
4. 命中断点后确认当前 frame 能看到 `self`。
5. 在 LLDB 依次执行：
   - `expression -l Swift -- self.selectIndex = 1`
   - `expression -l Swift -- self.selectIndex = 0`
6. Continue。

这两个赋值会先缓存一个未加载 View 的 `GroupsViewController`，再让当前页面回到 Device。继续执行后，`reloadData()` 会清理未加载的 Group 页面缓存。

修复前预期：

- 在 `GroupsViewController.deinit` 的旧式 `removeObserver` 处抛出 `NSRangeException`。
- 异常信息包含 `networkable` 和 `not registered as an observer`。

修复后预期：

- 同一缓存清理路径不会抛出 KVO 异常。
- Space 页面继续完成 `reloadData()`。

### 纯 UI 概率复现

1. 创建空 Space 并立即进入。
2. 在 Mesh 扩展数据尚未完成时，快速进入 Group 配置引导。
3. 继续后续配置并触发 Scene、Schedule 或 Device 页面切换。
4. 重复创建/退出 Space，并在弱网络或 Mesh 数据加载较慢时测试。

该方式依赖加载与操作时序，不能把“多次未复现”单独当作修复成功证据。

## 6. 尚未验证

- 当前会话没有连接真机执行上述 LLDB 时序。
- 没有执行真实 create space、Mesh 硬件或服务器链路验收。
- 没有线上 Bugly 新版本数据，不能宣称 `#8002` 已在线上归零。

真机验证应重点确认：同一 LLDB 时序不再 Crash、Group 地址申请提示条件不变、有网/断网/恢复网络时没有重复提示或非主线程 UI 异常。
