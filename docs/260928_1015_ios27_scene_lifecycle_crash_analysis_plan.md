# iOS 27 启动崩溃分析与修复方案

日期：2026-09-28。状态：用户已确认方案，代码已实施，五品牌 Debug 编译和构建产物检查通过；真机待人工验收。

## 结论

用户日志明确指出 UIKit 因应用未采用 UIScene 生命周期而拒绝启动。当前源码与之吻合：五个品牌的 Info.plist 均无 Scene manifest，AppDelegate 的 Scene 配置回调被注释，也没有 SceneDelegate；主窗口仍在 didFinishLaunchingWithOptions 中通过 UIWindow(frame:) 创建。

Apple 已明确：从 iOS 27 等系统开始，使用最新 SDK 构建的 UIKit 应用必须采用 Scene 生命周期，否则无法启动。该规则针对构建 SDK 和系统组合，降低 Deployment Target 或只提高应用版本号不能补齐缺失的生命周期。

推荐方案：五品牌统一迁移为单 Scene 的 UIKit 生命周期；进程初始化继续由 AppDelegate 负责，窗口和根控制器改由 SceneDelegate 管理，同时兼容现有窗口访问入口。无需引入 SwiftUI，也无需开启多窗口。

来源：[Apple — Transitioning to the UIKit scene-based life cycle](https://developer.apple.com/documentation/uikit/transitioning-to-the-uikit-scene-based-life-cycle?changes=_4)。

## 当前工作树与环境

- 工作树：`/Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/fix-Support-iOS27`。
- 分支：`fix/Support-iOS27`；HEAD：`ce720d0937d7c534889805de1a72c119ed9b6f29`。
- 开始时已有未跟踪目录：`SunSmart.xcodeproj/xcshareddata/xcodecloud/`，保留不动。
- 本机 CLI：Xcode 27.0，build `27A266a`；iPhoneOS SDK 27.0。
- `SunSmartLocal.xcworkspace` 存在，包含 App、Pods 及 `.local-sdk/nordic-sig-mesh-sdk`。
- SDK realpath：`/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`；HEAD：`a05b86979e605c830e3ba932a71b41c11866337f`；本次检查无未提交改动。
- 当前正式 project 的远端依赖实际为 GitHub `maginawin/nordic-sig-mesh-sdk` 的 `release`，与 AGENTS.md 描述的 Gitee 地址不同。这是现存配置差异，与本次 Scene 崩溃无直接关系；本次方案不调整依赖来源。
- 共享 AppBase.xcconfig 的最低系统版本为 iOS 15.0；已有 UIKit Scene API 可覆盖此兼容范围，迁移后旧系统也走 Scene 生命周期。

## 已确认的代码证据（修改前）

| 位置 | 现状 | 对本次问题的意义 |
| --- | --- | --- |
| `SunSmart/AppDelegate/AppDelegate.swift` | `@main` AppDelegate；在 didFinishLaunching 中创建 UIWindow(frame:)，配置 Welcome/Sites 根控制器并显示 | 沿用旧窗口生命周期，未将应用窗口交给 UIWindowScene |
| 同上 | Scene session 配置回调整段注释，仓库无 SceneDelegate 实现 | 没有有效的场景接入 |
| 五品牌 Info.plist | 均无 UIApplicationSceneManifest | 五品牌存在同类配置缺口 |
| `SunSmart.xcodeproj/project.pbxproj` | 五 target 均编译同一个 AppDelegate.swift，配置中未发现生成 Scene manifest 的声明 | 属于共享启动入口问题，不能只补 SunSmart |
| `SunSmart/Thirdparty/WYHUDManager/Classes/XWHUDManager.m` | p_getKeyWindow 直接返回 UIApplication.delegate.window | 简单删除 AppDelegate.window 会破坏现有 HUD 的窗口入口 |
| `UIApplication.keyWindow()` 扩展 | 优先 foregroundActive Scene，再回退 AppDelegate.window，最后新建空 UIWindow | 场景连接初期尚未 active，必须能够获得真正的主窗口，不能误落入空窗口兜底 |
| `SunSmart/Main/Base/WelcomeViewController.swift` | 同意协议后通过 keyWindow() 替换根控制器 | 欢迎页到 Sites 的转换必须继续使用同一个 Scene 窗口 |
| `SunSmart/Common/Cloud/CloudSynchronizationManager.swift` 等 | 通过 UIApplication 前后台通知恢复同步、刷新页面 | 不应在 SceneDelegate 中再手动转发同名通知，造成重复恢复 |

补充：已有提交 `8c6bdee6` 的标题是 `fix: iOS 27 crash`，但实际 diff 仅将五品牌 Debug/Release 的 MARKETING_VERSION 从 1.2.10 调整为 1.2.11，没有实现生命周期迁移。

本次崩溃原因可以由日志、官方规则及源码对应关系确认；未自动安装或运行 App，因此没有本机独立复现记录，也没有修复后运行结果。

## 推荐修复范围

### 1. 五品牌注册同一个 SceneDelegate

在以下五份真实 target 使用的 Info.plist 中增加一致的 Scene manifest：

- `SunSmart/Info.plist`
- `Archipelago/Archipelago-Info.plist`
- `SLGSync/SLGSync-Info.plist`
- `SylSmart/SylSmart-Info.plist`
- `Lumineux/Lumineux-Info.plist`

配置应用角色 `UIWindowSceneSessionRoleApplication` 的 Default Configuration，delegate 为 `$(PRODUCT_MODULE_NAME).SceneDelegate`；明确设置 `UIApplicationSupportsMultipleScenes = false`。项目采用代码创建根界面，故不添加 `UISceneStoryboardFile`；各品牌现有 LaunchScreen 配置保留。

采用静态 manifest 即可，无动态配置需求时无需再添加重复的 AppDelegate configurationForConnecting 实现。仅取消旧注释或仅添加空 manifest 都不构成完整迁移。

### 2. 拆分进程初始化与窗口初始化

新增 `SunSmart/AppDelegate/SceneDelegate.swift`，遵循 UIWindowSceneDelegate，并加入五个 target 的 Sources。

在 scene willConnect 中使用系统传入的 UIWindowScene 创建 UIWindow(windowScene:)，设置当前协议同意状态对应的 NavigationViewController + WelcomeViewController/SitesViewController，继续强制浅色外观，再显示窗口。

AppDelegate 保留 DEBUG tracer、TTL 配置、数据库、HUD 默认样式、Bugly、Mesh 支持设备信息、各品牌服务器区域默认值、网络监听和 UITableView 外观等进程级初始化，以及 applicationWillTerminate 的现有清理。仅移出 UI 窗口创建代码，保证数据库和基础配置在根页面加载前就绪。

初始化只在进程启动执行；前后台切换不重建窗口、不重新打开数据库，也不重置导航栈或用户协议状态。

### 3. 兼容现有窗口入口

由 SceneDelegate 强持有真正的主窗口，AppDelegate.window 保留为指向同一窗口的兼容引用，优先采用 weak，避免多重所有权。建立窗口时先登记兼容引用，再创建和展示根页面。

保留现有 keyWindow() 调用接口，核对它在 Scene 尚未 active 和返回前台时的选择；主界面及 HUD 应始终指向 Scene 窗口。若 Scene 断开需要清理兼容引用，仅在其仍指向该 Scene 窗口时清理，避免旧 Scene 的清理影响重建后的窗口。

本阶段通过这一共享入口兼容现有 HUD、SRAlertView、菜单、分享面板及欢迎页跳转，不批量重写业务页面，也不扩展为多窗口路由框架。

### 4. 保留系统通知驱动的恢复机制

目前没有已实现的 AppDelegate 四个前后台代理方法需要搬迁；现有相关逻辑通过 UIApplication 通知接入。Apple 文档明确区分：Scene 接入后四个旧 delegate 回调不再调用，但 UIApplication 通知仍可用于应用整体状态。

因此先保留 CloudSynchronizationManager、SyncGatewaysViewController、SiteEditViewController、Trigger Zone 等的通知订阅，不在 SceneDelegate 中重复调用业务恢复或手工发布 UIApplication 通知。Scene 重连时也不重复执行进程初始化。

来源：[Apple — 生命周期回调迁移及应用整体通知](https://developer.apple.com/documentation/UIKit/transitioning-to-the-uikit-scene-based-life-cycle?changes=_5_6&language=objc)。

## 风险与实施边界

- 此方案改变启动与窗口时序，需验证首屏布局、服务器选择弹窗、协议跳转及前后台恢复；静态检查或编译无法替代运行验收。
- HUD 的 `delegate.window` 是必须兼容的已证实依赖；保留属性应指向 Scene 创建的同一个窗口，不能再额外创建第二个 legacy UIWindow。
- 扫码控制器仍有 `UIApplication.shared.windows.first!.windowScene!`，LightAckProgressAlertView 和部分 HUD 方法仍使用废弃的全局窗口 API；SDK 的 BLOB 失败提示也有 `UIApplication.shared.keyWindow!`。这些是已有兼容风险，并非此次启动断言的证实原因。单窗口迁移先验证其真实行为；本次不以 API 废弃为由扩展成全仓清理或 SDK 改造。
- 屏幕尺寸和安全区存在全局计算入口。保持现有单窗口设置，并检查迁移后首屏及 iPad 布局；本次不声称完成 iOS 27 所有 UI 兼容性适配。
- 未发现已有入站 URL 或 NSUserActivity 处理实现，五份 plist 的 URL scheme 列表为空；本次没有既有深链处理需要迁移，也不新增深链功能。
- 预计必要生产变更为 AppDelegate、新增 SceneDelegate、五份 Info.plist 和 project.pbxproj。暂不修改 NordicSigMeshSDK、持久化格式、BLE 协议及远端依赖。
- 不以关闭断言、修改应用版本号或调整最低系统版本替代 Scene 接入。

## 确认后的验证计划

1. 解析五份 plist 与工程 target 配置，检查 Scene delegate 名称、模块替换、单窗口设置、新文件 Sources 归属和无 Main storyboard 误配置；检查最终构建产物中的 Info.plist。
2. 检查 Window 在 SceneDelegate、AppDelegate 兼容引用和 keyWindow() 三处的一致性，包含 Scene 连接、非 active 阶段、断开及重建边界。必要诊断仅置于 DEBUG，避免凭空添加生命周期转发。
3. 使用已核对的 SunSmartLocal.xcworkspace，先构建 SunSmart 的 Debug generic iOS；稳定后因涉及五品牌 plist 与源文件归属，串行覆盖其余四品牌 Debug。使用本工作树稳定的 DerivedData 目录，不 clean、不重跑无关 Release，不使用 Simulator。
4. 若实施涉及可独立验证的选择或状态逻辑，运行相应行为回归；现有扫码源码契约测试只能检查原有结构，不作为 Scene 启动或真实布局验收。当前未找到可直接复用的 Scene 生命周期运行测试，不为形式创建临时测试 App。
5. 默认由用户完成下表真机验收；不自动安装 App。构建结果与真机结果分别记录。

| 场景 | 最短操作与预期 |
| --- | --- |
| iOS 27 冷启动，未同意协议 | 使用可测试的首次启动数据进入 Welcome；不再发生该断言；同意协议后进入 Sites，窗口无黑屏 |
| iOS 27 冷启动，已有数据 | 完全结束 App 后打开；进入 Sites，本地数据正常；已有品牌服务器区域配置保持有效 |
| 窗口附着 | 打开菜单、HUD、警告及分享/导入面板；均显示在当前窗口；关闭后页面仍可操作 |
| 系统打断与前后台 | 在页面中锁屏/解锁或切后台再回来；导航栈保持，页面刷新和同步恢复无重复触发迹象 |
| BLE/网关相关 | 在既有扫描或网关同步页面切后台再返回；暂停/恢复沿用原业务语义 |
| 扫码及安全区 | 从 Sites 打开扫码再关闭；无窗口强制解包崩溃，导航及顶部/底部布局正常 |
| 旧系统与 iPad | 可用旧 iOS 真机做一次冷启动、弹窗及前后台冒烟；可用 iPad 检查首屏布局，不启用多 Scene |

## 实施结果与验证记录

用户确认后已完成：

- 新增共享 SceneDelegate，使用 UIWindow(windowScene:) 持有并显示主窗口，保留 Welcome/Sites 分流与浅色外观。
- AppDelegate 保留进程初始化与终止清理，window 改为 weak 兼容引用；SceneDelegate 在创建根控制器前登记该引用，断开时按窗口身份清理。
- 现有 keyWindow() 已有 AppDelegate.window 回退，因此本次无需改其接口或业务调用方；首次连接、Scene 尚未 active 时也能取得已登记窗口。
- 五品牌均配置静态单 Scene manifest，SceneDelegate 已加入五品牌 Sources。
- 现有 UIApplication 前后台通知订阅保持不变，没有新增通知转发或恢复任务。
- 新增 DEBUG 日志 `[AppLifecycle] scene connected root=WelcomeViewController` / `SitesViewController`，用于人工核对 Scene 连接和首屏分流。
- 未修改 SDK、依赖声明/锁文件、HUD 实现或其他业务模块，保留原有 xcodecloud 未跟踪目录。

验证环境：`SunSmartLocal.xcworkspace`；Xcode 27.0 / iPhoneOS 27.0；Debug，generic/platform=iOS，CODE_SIGNING_ALLOWED=NO；串行使用 `/Users/maginawin/Library/Developer/Xcode/DerivedData/SunSmart-fix-Support-iOS27`。

已检查五份 plist 的解析结果与五 target Sources 归属；除新增 Scene manifest 外，plist 内容与 HEAD 一致。SunSmart 编译返回 exit 0，构建产物 manifest 中 delegate 已展开为 `SunSmart.SceneDelegate`，二进制包含 SceneDelegate 符号；生成的 Objective-C 头文件确认 AppDelegate.window 仍暴露为 weak 属性，SceneDelegate.window 为 strong 属性，HUD 的旧入口可继续链接。

| Scheme | Debug generic iOS 编译 | 最终 Info.plist 与二进制核对 |
| --- | --- | --- |
| SunSmart | exit 0 | `SunSmart.SceneDelegate` 已展开，SceneDelegate 已链接 |
| Archipelago | exit 0 | `Archipelago.SceneDelegate` 已展开，SceneDelegate 已链接 |
| SLG Sync Plus | exit 0 | `SLG_Sync_Plus.SceneDelegate` 已展开，SceneDelegate 已链接 |
| SylSmart | exit 0 | `SylSmart.SceneDelegate` 已展开，SceneDelegate 已链接 |
| Lumineux | exit 0 | `Lumineux.SceneDelegate` 已展开，SceneDelegate 已链接 |

所有品牌产物均确认 `UIApplicationSupportsMultipleScenes = false`。`git diff --check` 通过；SDK 工作树仍无改动。没有运行独立测试套件或新增源码文本断言测试，本次自动验证为配置解析、实际编译和产物核对。

构建输出仍有既有 API 弃用、依赖兼容性及部分 target 重复资源/源文件警告；部分编译输出还出现 Xcode 的“command failed with exit code 0 but produced no further output”诊断。五次 xcodebuild 最终均返回 0，且上述对应产物检查通过；未为消除这些输出修改无关依赖或 target 内容。

未自动运行真机；编译和产物检查不代表启动、HUD、布局及 BLE 恢复的实际运行验收。下一步由用户在 iOS 27 真机按上表验证，优先确认冷启动、Welcome 到 Sites、HUD/菜单及切后台返回。
