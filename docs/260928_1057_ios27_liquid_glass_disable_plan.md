# iOS 27 液态玻璃效果禁用方案

日期：2026-09-28。状态：用户已确认方案 A，代码已实施；SunSmart Debug generic iOS 编译及现有扫码导航契约检查通过，实际外观待用户真机验收。

## 结论与已确认选择

当前不能通过增加 Info.plist 开关关闭液态玻璃：五品牌已经设置 `UIDesignRequiresCompatibility = true`，已有五品牌构建产物也包含这个布尔值。当前使用 Xcode 27 / iOS 27 SDK，而 Apple 明确规定此构建方式会忽略兼容开关，即使最低支持版本低于 iOS 27。

建议保留 Xcode 27 和已完成的 Scene 生命周期适配，先统一移除 App 自有导航按钮的玻璃背景，保留原有导航底色。这是有明确公开 API 支持的局部方案，不能称为“全 App 所有系统控件恢复旧外观”。若需求必须是整体旧版 App UI，应选择 Xcode 26 构建的临时兼容路线。

| 方案 | 达到的效果 | 代价与限制 |
| --- | --- | --- |
| A：保留 Xcode 27，统一处理 App 导航栏和导航按钮（推荐） | 去除返回、菜单、更多、保存等 App 自有导航按钮的玻璃背景，维持原有页面配色 | 涉及共享按钮入口及其调用点；系统开关、分段控件、系统弹窗等不会因此全部恢复旧版 |
| B：Xcode 26 + 现有兼容开关 | Apple 确认在 iOS 26、27 上继续采用 App UI 兼容模式，更接近整体旧版外观 | 需要另备工具链并验证 App、Pods、SDK 的编译兼容性；只是过渡方案，不是 Xcode 27 的解决办法 |

若要求继续使用 Xcode 27 且所有可见界面都没有玻璃效果，当前不存在统一的公开开关。App 内控件需要逐类定制或替换，系统接管的权限提示、键盘、分享/文件选择等界面不能承诺由 App 全面还原；这超出方案 A 的范围。

用户已确认采用 A 的导航外观处理范围；B 仅保留为原方案对比，本次不切换工具链。

## 证据与原因

- 当前工作树：`fix-Support-iOS27`；分支：`fix/Support-iOS27`；HEAD：`753d8fd4`（`feat: Support iOS27`）。调查开始时工作树干净。
- 本机 CLI：Xcode `27.0`，build `27A266a`。`/Applications` 下本次仅发现 `Xcode.app`，未准备 Xcode 26 工具链。
- 五品牌实际 Info.plist 为 `SunSmart/Info.plist`、`Archipelago/Archipelago-Info.plist`、`SLGSync/SLGSync-Info.plist`、`SylSmart/SylSmart-Info.plist`、`Lumineux/Lumineux-Info.plist`，均已有兼容开关与 Scene manifest。
- 本次只读检查既有 DerivedData 中五品牌 `.app/Info.plist`，均为 `UIDesignRequiresCompatibility = true`、`DTXcode = 2700`、`DTSDKName = iphoneos27.0`、`MinimumOSVersion = 15.0`。说明已有产物并非漏打包开关；这不是本轮重新构建或真机验证的结果。
- `NavigationViewController` 已使用 `configureWithOpaqueBackground()` 并配置 standard / scrollEdge appearance。底色不透明与按钮玻璃背景是不同层次，不能把重复设置白色导航栏当作完整修复。
- App 源码未发现显式使用 `UIGlassEffect` 或 `glassEffect`；发现的 HUD/Toast 毛玻璃使用既有 `UIBlurEffect`，不能直接归因于本次 SDK 自动采用的新外观。
- 直接证据支持“新 SDK 忽略旧 UI 兼容开关”。没有本次真机截图或视图层级证据，因此具体哪些控件呈现了用户所见效果，仍需运行验收确认，不能断言仅有导航按钮受影响。

Apple 官方说明：[UIDesignRequiresCompatibility](https://developer.apple.com/documentation/bundleresources/information-property-list/uidesignrequirescompatibility)。Apple Frameworks Engineer 进一步明确：判断依据是构建 SDK，Xcode 27 构建会忽略该值；Xcode 26 构建在 iOS 26、27 上仍会遵守该值。[官方答复](https://developer.apple.com/forums/thread/838637)

因此，降低 Deployment Target、再写一遍兼容开关、改应用版本号、撤回 Scene 迁移，都不能解决当前 SDK 27 下的 UI 选择问题。

## 方案 A：最小完整实施范围

### 1. 在已有按钮扩展中统一配置实例

复用 `SunSmart/Common/Extension/UIBarButtonItem+Extension.swift`，增加清晰、可重复调用的实例配置方法；在 iOS 26 及以上为 App 自有导航按钮设置 `hidesSharedBackground = true`，旧系统保持原有行为。

Apple 说明该属性用于隐藏按钮的标准共享背景，通常即玻璃背景。它不等于全局禁用 Liquid Glass；按钮处于包含多个 item 的显式 `UIBarButtonItemGroup` 时会忽略此设置。当前 App 源码未发现显式构造这种 group，多按钮数组仍须实际验证。[属性文档](https://developer.apple.com/documentation/uikit/uibarbuttonitem/hidessharedbackground)

本机 SDK 头文件未将此属性声明为 `UI_APPEARANCE_SELECTOR`，方案不依赖全局 `UIBarButtonItem.appearance()` 设置。`sharesBackground = false` 只负责取消合组，不能替代隐藏背景。

### 2. 覆盖创建与动态更新入口

已有带颜色/字体的文字按钮初始化方法直接复用统一配置；`NavigationViewController` 创建的返回按钮与页面直接创建的图片、文字、customView 按钮在交给 navigationItem 前完成配置。

当前源码中 `UIBarButtonItem(` 的非整行注释命中约 126 处、分布于 87 个文件，包括已有便利初始化调用。这是定位范围的文本统计，不是承诺修改全部文件；实施时只接入尚未被共享入口覆盖的 App 导航按钮。

重点包括：

- Sites 的菜单/导入，Site、Space/Group 与设备详情的返回/更多。
- 保存、关闭、添加等普通页面及模态页面按钮。
- `SiteTriggerZoneViewController.updateNavigationActions` 的多按钮与异步显示/隐藏。
- `PJPreAddEightKeySwitchesVC` 在不同状态间切换的关闭、返回、保存按钮。
- `PJDevicesLegacyContainerController` 从子控制器复制导航项目的路径。
- 添加设备页面的 customView 返回按钮与扫描状态视图。

将配置落在 item 创建或重建时，可覆盖 viewDidLoad 之后和运行中换按钮的情况。仅在 push 前扫描一次 navigationItem 会漏掉尚未创建及后来替换的按钮，不采用这种不完整方案。

本机 SDK 将旧 `.done` 对应到 `.prominent`；现有返回/更多图片广泛使用 `.done`。实施时普通图标在新系统下采用 `.plain` 并隐藏背景，真正保存/完成操作保留其文字、字重、禁用状态与操作语义，避免遗留突出背景或误改业务行为。[Apple 按钮样式说明](https://developer.apple.com/documentation/uikit/uibarbuttonitem/style-swift.enum)

### 3. 保持已有导航背景与交互

共享位置为 `NavigationViewController.swift` 和 `UIViewController+Extension.swift` 中的 `setNavigationBarBackgroundColor`。检查并一致配置 standard、scrollEdge、compact、compactScrollEdge 对应状态，避免滚动或紧凑布局时回到未指定的外观。保留每个页面已有背景颜色，包括主动请求透明背景的页面，不统一强制白色。

不改变 target/action、menu、enabled、customView、导航返回代理、侧滑返回、按钮顺序及用户可见文案；不通过移除 UIKit 私有子视图或全局方法替换实现。

### 4. 明确覆盖边界

五品牌共享上述代码，统一适用；本轮计划不需要修改五份 plist、SDK、依赖或 Scene 生命周期。

当前 App 使用 `UISwitch`、`UISegmentedControl`、继承 `UISlider` 的自定义控件及系统弹窗/分享/文件选择面板。方案 A 不将这些控件承诺为旧版外观，也不批量删除原有 HUD/Toast 毛玻璃。若用户确认这些也必须处理，先按实际受影响控件扩大明确范围，再决定复用或替换，不能以导航按钮的结果代替全 App 验收。

## 方案 B：临时兼容构建

1. 准备并明确选用 Xcode 26 自带的 iOS 26 SDK，继续保留当前 Scene 生命周期代码及五品牌现有兼容开关。
2. 先核对 App、Pods、本地 Nordic SDK 是否引入仅 Xcode 27 / SDK 27 可编译的接口或工具链要求，再进行代表构建。当前未执行此兼容性验证，不能承诺直接切换即可编译。
3. 如采用独立 Xcode，使用本任务明确指定的工具链和对应稳定 DerivedData，不静默更改全机 Xcode 选择或其他任务的构建环境。
4. 因工具链发生变化，完成五品牌 Debug generic iOS 编译、产物配置核对及 iOS 27 真机 UI 冒烟；发布流水线使用同一已验证 SDK。若用于发布，另核对届时的提交要求，不将此路线视为长期保证。

## 确认后的验证与交付

本地实际入口为 `SunSmartLocal.xcworkspace`；SDK 映射 realpath 为 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`。方案 A 不写 SDK。

方案 A 先进行差异检查和按钮创建/替换路径核对，完成后构建一次 SunSmart Debug、generic iOS、关闭签名，使用既有 `SunSmart-fix-Support-iOS27` DerivedData。若实现保持共享代码、无品牌编译分支及资源归属变化，不机械重复五品牌构建；若新增 target 文件归属、品牌条件或依赖变化，再覆盖受影响品牌。没有可直接证明 UIKit 液态玻璃渲染的现有自动测试，不新增源码字符串断言来充当 UI 验收。

默认由用户完成以下最短运行验收，本任务不自动操作真机：

| 路径 | 预期 |
| --- | --- |
| iOS 27：Sites → Site → Space/Group → 设备详情，再逐级返回 | 菜单、返回、更多按钮无玻璃背景；位置、点击范围、标题和侧滑返回正常 |
| 打开编辑页，修改并保存；关闭模态页面 | 保存/关闭按钮外观一致；禁用、恢复、点击行为正确 |
| 打开 Trigger Zone，触发 Site tasks 按钮出现/消失 | 多按钮均保持预期外观，无共用玻璃底、重叠或截断 |
| 打开添加设备页及八键开关相关配置页 | customView 与运行中切换的按钮均覆盖，扫描状态和操作有效 |
| 页面滚动、切换前后台；可用 iPad 检查紧凑布局 | 导航底色符合原页面设计，切换时不闪回玻璃背景，顶部状态图标和安全区正常 |
| 可用旧版 iOS 做导航与编辑冒烟 | 版本保护有效，原有外观和操作无本次引入的变化 |

构建结果与上述运行表现分别记录。最终交付须明确达到的是导航外观范围，不能将方案 A 写成“已全局禁用所有液态玻璃效果”。

## 方案 A 实施与验证结果

在 `fix/Support-iOS27`、HEAD `753d8fd4` 上完成以下未提交修改：

- `UIBarButtonItem+Extension.swift` 新增返回同一 item 的 `withoutSharedBackground()`，在 iOS 26 及以上设置 `hidesSharedBackground = true`；仅对无标题的 prominent 图片按钮切换为 plain，旧系统保持原样。已有文字按钮初始化继续保留字体、颜色、禁用态配置，并接入该方法。
- 111 处直接初始化（分布于 82 个文件）在 item 附着到导航栏前调用上述方法；另有 15 处调用已有文字按钮初始化，自动覆盖。包括空占位 item、自定义视图、异步重试、多按钮数组、八键开关关闭/返回切换与 DEBUG 导航按钮。
- `NavigationViewController` 与导航颜色扩展补齐 compact / compactScrollEdge appearance，复用各自原有 appearance 和页面底色。没有新建导航控制器、替换代理或修改导航生命周期。
- 共修改 84 个 Swift 文件，其中 3 个为共享配置入口，其余 81 个业务页面仅追加外观配置调用。按字节剥离这项调用后，81 个页面均与 HEAD 内容一致，确认没有附带改动回调、状态更新、原有注释或格式。
- 五品牌的 Sources 均已包含上述 3 个共享文件，无新增文件归属、资源、品牌编译条件、plist、依赖或 SDK 修改。本次仅构建代表 target SunSmart。

已完成的验证：

| 验证 | 结果与边界 |
| --- | --- |
| `git diff --check` | 通过 |
| 调用入口及差异核对 | 111 处直接创建和 15 处共享文字初始化覆盖；动态复制沿用同一已配置 item；业务页面差异限于配置调用 |
| 五品牌共享文件归属 | 三个共享文件均各有一个 Sources 入口，未改工程配置 |
| `LBXScanNavigationLifecycleContractTests` | 通过（exit 0）；现有源码契约检查，覆盖扫码全屏进入/退出与导航恢复结构，不是 UIKit 运行测试 |
| SunSmart Debug generic iOS 编译 | `SunSmartLocal.xcworkspace`，Xcode 27 / iOS 27 SDK，关闭签名，exit 0；使用既有稳定 DerivedData，未 clean |
| 构建产物 | `DTXcode = 2700`、`DTSDKName = iphoneos27.0`、`MinimumOSVersion = 15.0`；`SunSmart.debug.dylib` 包含 `withoutSharedBackground` 符号 |
| SDK 工作树 | `one-dev`，HEAD `a05b869`，仍无未提交修改 |

编译输出包含原有业务闭包的 weak/strong 捕获告警，未为消除这些无关告警扩大修改。未新增测试工程、未运行 Simulator、未安装或运行真机，也未提交 Git。

未完成项仅为本方案表列的实际界面验收：优先检查 iOS 27 的 Sites → Site → Space/Group → 设备详情、编辑保存、Trigger Zone 多按钮及添加设备/八键开关动态按钮；确认玻璃底消失、间距/点击/返回正常。系统开关、分段控件、系统面板和原有 HUD/Toast 毛玻璃仍在方案 A 的覆盖范围之外。
