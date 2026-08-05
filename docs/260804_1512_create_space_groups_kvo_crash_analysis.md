# Create Space Groups KVO Crash 根因分析与修复方案

## 1. 分析范围

- Bugly 异常：`#8002 NSRangeException`
- 异常信息：`GroupsViewController` 从 `NetworkRequest.networkable` 移除 KVO 时，系统发现该实例从未注册。
- 用户场景：App 端创建 Space 期间发生 Crash。
- 当前源码：`fix` worktree，2026-08-04。
- 本文只做源码分析和修复规划，不修改业务代码。

## 2. 结论

Crash 的直接根因已能够从异常文本和当前源码互相印证：

`GroupsViewController` 只在 `viewDidLoad` 中注册旧式 KVO，但在 `deinit` 中无条件移除 KVO。只要某个实例完成初始化后、尚未加载 View 就被释放，注册逻辑不会执行，而析构逻辑仍会执行，最终抛出 `NSRangeException`。

create space 是该生命周期缺陷的高概率触发场景，而不是异常的真正根因。空间页在 Mesh 扩展数据加载完成前向 `WMPageController` 报告 0 个子页面；配置引导或页面切换又可能提前缓存一个仅初始化、未加载 View 的 Group 页面。加载完成后的 `reloadData()` 会清理页面缓存，释放该实例并触发不对称的 KVO 移除。

根因置信度：高。

create space 精确交互时序置信度：中高。Bugly 堆栈没有包含本次操作前的全部 UI 事件，因此无法仅凭这份 Log 证明是哪一次菜单切换制造了未加载实例，但缓存释放、析构和未注册 KVO 三段证据是闭合的。

## 3. 源码证据

### 3.1 直接异常点

`SunSmart/Main/Group/Controller/GroupsViewController.swift`：

- 第 62-76 行：`viewDidLoad` 调用 `addNotificationObserver()`。
- 第 103-106 行：`deinit` 无条件调用旧式 `removeObserver`。
- 第 108-136 行：KVO 的 `addObserver` 位于 `viewDidLoad` 间接调用的方法内。
- 第 138-142 行：旧式 `observeValue` 处理网络变化。

因此实例的真实生命周期存在以下不对称：

1. `init` 完成；
2. View 从未加载，KVO 未注册；
3. 实例被释放；
4. `deinit` 仍移除 KVO；
5. Foundation 抛出“not registered as an observer”。

Bugly 顶层符号 `$s8SunSmart20GroupsViewControllerCfD` 是 `GroupsViewController` 的析构路径，与当前第 103-106 行一致。

### 3.2 为什么堆栈会出现 WMPageController.reloadData

`SunSmart/Main/Space/Controller/SpaceViewController.swift`：

- 第 230 行：父页面自身已使用 `NSKeyValueObservation` token 管理 `networkable`，说明工程内已有更安全的参考模式。
- 第 667-706 行：Mesh 扩展数据加载完成后，将 `loadNetworkData` 设为 `true` 并调用 `reloadData()`。
- 第 1448-1452 行：`loadNetworkData == false` 时，WMPageController 的子页面数量为 0；完成后变为菜单项数量。
- 第 1455-1464 行：索引 1 创建 `GroupsViewController`。
- 第 568-570 行及第 659 行：配置流程和通知能够修改 `selectIndex`。

`SunSmart/Thirdparty/WMPageController/WMPageController.m`：

- 第 128-140 行：页面尚未完成布局时修改 `selectIndex`，会先初始化控制器并放入 `memCache`，但不会访问其 View。
- 第 176-185 行：`reloadData` 重建显示页面后调用 `removeAllObjects` 清理缓存。
- 第 317-321 行：缓存对象由 Space 页的数据源直接初始化。

Bugly 堆栈同时出现 `cache_remove_all`、`-[WMPageController reloadData]`、`SpaceViewController.setNetworkConnected` 回调和 `GroupsViewController` 析构，正好对应这条释放链。

### 3.3 create space 的高概率触发时序

1. 新 Space 进入 `SpaceViewController`，`loadNetworkData` 初始为 `false`，父容器暂时没有正式子页面。
2. Space 页面并行读取 Mesh 网络与扩展数据。
3. 空 Space 的配置引导或后续流程修改菜单索引；WMPageController 在未完成初始化的状态下缓存一个未加载 View 的 `GroupsViewController`。
4. 后续菜单通知还可能把当前索引切到 Scene、Schedule、Device 等页面，使未加载的 Group 页面只保留在缓存中。
5. `loadExtensionData` 完成，主线程执行 `reloadData()`。
6. WMPageController 清空旧缓存，未加载 View 的 Group 页面析构。
7. `deinit` 移除从未注册的 `networkable` KVO，App Crash。

该问题具有明显时序性：Mesh 数据加载速度、用户操作速度、配置引导步骤和页面切换顺序都会影响是否命中，因此可能无法每次复现。

## 4. 可能存在的问题分级

### P0：旧式 KVO 注册/移除与 View 生命周期不对称

这是本次 Crash 的直接根因。Controller 可以在 `viewDidLoad` 之前析构，但当前实现假设每个实例都完成过注册。

### P1：KVO 回调直接执行 UI 行为，线程边界不明确

当前 `observeValue` 会直接进入 `applyGroupAddressAlert()`。`networkable` 的变更来源于网络可达性回调，当前代码没有在 Group 页面明确切回主线程。即使本次异常不是线程问题，保留现状仍可能引入非主线程 UI 风险。

### P1：WMPageController 允许缓存“仅 init、未加载 View”的页面

这本身符合 UIKit 的懒加载行为，不应要求所有子控制器都必须加载 View 才能安全释放。它暴露了 Group 页面错误的生命周期假设。直接修改 WMPageController 会影响所有品牌 target 和其他分页页面，风险明显高于修复具体 Controller。

### P2：精确触发路径缺少运行时上下文

现有 Bugly Log 没有 Space ID、页面索引变化、`loadNetworkData` 状态或控制器是否加载 View 等诊断字段。当前源码足以确认 KVO 根因，但若需要统计具体操作分支，还需要在后续测试或灰度监控中补充非敏感生命周期信息。

## 5. 修复方案比较

### 方案 A：将 GroupsViewController 迁移为 token-based KVO（推荐）

范围只落在 `GroupsViewController` 及一个聚焦契约测试：

- 使用可选的 `NSKeyValueObservation` 保存 `networkable` 观察关系。
- 观察 token 只在 View 真正加载时创建；未加载 View 的实例持有 nil token，可以安全析构。
- 移除旧式 `addObserver`、无条件 `removeObserver` 和通用 `observeValue`。
- 在观察回调内明确切回主线程，再判断并展示 Group 地址申请提示。
- 保留现有业务条件，不改变 address 申请流程、文案或页面结构。

优点：修复直接根因；与 `SpaceViewController`、`SiteViewController` 的现有安全模式一致；改动聚焦；不会改变 WMPageController 的共享行为。

风险：共享的 `GroupsViewController.swift` 被四个品牌 target 引用，因此必须完成四 target 编译验证。

### 方案 B：保留旧式 KVO，增加 registered 状态和专用 context

注册成功后记录状态，析构时仅在已注册状态下移除，并用专用 context 限定回调。

优点：代码改动表面上最小。

缺点：继续依赖人工维护 add/remove 对称；后续生命周期调整仍容易再次出错；还需额外处理线程切换。长期可靠性低于方案 A。

### 方案 C：修改 Space/WMPageController 的预加载与缓存清理时序

例如在 `loadNetworkData` 完成前禁止页面索引切换，或调整 WMPageController 的缓存清理行为。

优点：可以缩小 create space 的触发窗口。

缺点：没有消除 Group Controller 本身的非法 KVO 假设；影响所有分页业务和四个品牌 target；容易引入页面选中、缓存、引导流程回归。不建议作为本次主修复。

## 6. 推荐设计

采用方案 A，暂不修改 WMPageController。

设计边界：

- 只修复 Group 列表对 `NetworkRequest.networkable` 的观察生命周期与主线程 UI 边界。
- 不调整 create space 流程、Mesh 扩展数据加载、菜单索引逻辑、地址申请业务或第三方分页缓存策略。
- 不修改本地化、资源、target 配置和依赖。
- 如果方案 A 完成后仍出现 WMPageController 相关的其他 Controller 析构异常，再把容器硬化作为独立问题分析，不与本次修复捆绑。

## 7. 获批后的实施与验证计划

### Task 1：先建立生命周期安全契约

- 新增 `Tests/Group/GroupsViewControllerKVOContractTests.swift`。
- RED 条件应覆盖：当前文件仍包含旧式 `addObserver/removeObserver`，且没有持有可选 KVO token。
- GREEN 条件应覆盖：使用 token-based KVO、回调弱引用 Controller、UI 分支回到主线程、旧式手动移除路径消失。

说明：该契约用于防止源码回退；实际 UIKit 生命周期仍需 App 构建和真机复现覆盖。

### Task 2：实施最小根因修复

- 修改 `SunSmart/Main/Group/Controller/GroupsViewController.swift`。
- 迁移 `networkable` 观察为 token-based KVO。
- 移除旧式 KVO 回调与手动移除。
- 保留 `clearPendingGroupTap()` 的析构清理。
- 不顺手重构 NotificationCenter、Group 地址申请或其他页面逻辑。

### Task 3：静态与构建验证

- 编译并运行聚焦契约测试。
- 运行 `git diff --check`。
- 按项目规则，使用 generic iPhoneOS 且关闭签名，分别构建：
  - `SunSmart`
  - `Archipelago`
  - `SLG Sync Plus`
  - `SylSmart`
- 不使用 Simulator。

### Task 4：真机回归与线上观察

- 真机创建空 Space，在 Mesh 扩展数据仍加载时快速进入配置引导并切换后续页面，覆盖“Controller 已 init、View 未加载、缓存被清理”的时序。
- 覆盖有网/断网/恢复网络，确认 Group 地址申请提示仍只在符合原条件时出现，且 UI 操作在主线程。
- 多次进入/退出 Space、切换 Group 页面、返回 Site，确认没有 KVO Crash 或异常重复提示。
- 发布后按 Bugly 异常编号 `#8002` 观察，区分“代码与构建验证通过”和“线上 Crash 归零”；不能用一次构建成功代替真机及线上验收。

## 8. 验收标准

- `GroupsViewController` 在 View 从未加载的情况下被释放，不再执行非法 KVO 移除。
- 已加载的 Group 页面仍能响应 `networkable` 变化，并保持原有地址申请业务条件。
- 所有 UI 行为明确发生在主线程。
- 聚焦契约、`git diff --check` 和四个品牌 target 的 generic iPhoneOS build 通过。
- 真机 create space 快速配置路径不再复现本 Crash。
- Bugly 后续版本中 `#8002` 不再新增；线上观察结果单独记录，不以静态或构建结果替代。

## 9. 确认状态

2026-08-04 已确认采用方案 A，并按 Inline Execution 完成实现、聚焦契约和四 target generic iPhoneOS 构建。真机与线上 Bugly 验收状态见 `docs/260804_1537_groups_kvo_crash_implementation_summary.md`。
