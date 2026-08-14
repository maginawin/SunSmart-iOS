# Edit Site Result Host Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. This project explicitly requires Inline Execution and prohibits subagents unless the user asks for them.

**Goal:** 关闭 Edit Site 后保留发起编辑的 Sites 或 Site 页面；普通更新 Toast 在来源页展示，Time Zone 状态卡由 active window 全屏展示并覆盖 navigation bar。

**Architecture:** 保留 `SiteEditViewController` 的路由依赖注入结构，把“统一返回 Sites”改为“结束编辑并返回来源结果宿主”。两个入口各自负责关闭 modal 和提供自身 view；Site 详情入口不再查找 Sites 或执行 pop。普通 Toast 使用来源 view；Time Zone 状态卡在编辑结束后使用 active window，以满足全屏遮罩层级。

**Tech Stack:** Swift、UIKit、Foundation、源码契约测试、generic iPhoneOS `xcodebuild`。

## Global Constraints

- 采用已确认的方案 A，执行方式为 Inline Execution，不使用 subagents。
- 本地持久化失败继续停留 Edit Site，不提交服务器，保留现有失败 HUD。
- 普通 name/imageId 更新的成功、服务器失败、响应不匹配和离线结果继续使用现有 Site Update Toast。
- Time Zone 在线更新继续使用现有 saving/success/failure 状态卡；离线保存继续不新增结果卡。
- 无变化、Cancel、Close 不展示更新结果。
- 不改变成功判定、pending、timestamp、API、文案、视觉、资源、target 配置、依赖或 `NordicSigMeshSDK`。
- 不格式化或重构无关代码，不新增 Auth 信息。
- 未经用户明确要求，不执行 Git commit、push 或 merge。
- iOS 构建直接运行 `xcodebuild`，使用 generic iPhoneOS，不使用 shell 包装、日志重定向或 Simulator。
- 构建成功只证明静态集成，不替代真实服务器、导航动画和真机视觉验收。

---

## File Map

- Modify: `Tests/Site/SiteUpdateToastUIContractTests.swift`
  - 把普通更新的旧“最终返回 Sites”契约改成“两个入口各自提供来源 host”。
- Modify: `Tests/Site/SiteTimeZoneUIContractTests.swift`
  - 把 Site 入口必须 pop 的旧契约改成保留 Site，并验证状态卡使用 active window 全屏展示。
- Modify: `SunSmart/Main/Site/Controller/SiteEditViewController.swift`
  - 重命名结果宿主接口；普通更新使用来源 host，Time Zone 更新使用 active window。
- Modify: `SunSmart/Main/Site/Controller/SitesViewController.swift`
  - 适配新接口，保持关闭 modal、刷新列表和回传自身 view。
- Modify: `SunSmart/Main/Site/Controller/SiteViewController.swift`
  - 适配新接口；关闭 modal 后刷新标题并回传自身 view，不再 pop。
- Create: `docs/260814_1840_edit_site_result_host_implementation_summary.md`
  - 记录实际改动、验证证据和真机验收边界。

## Interface Contract

- `SiteResultHostCompletion = (UIView) -> Void`
  - 接收关闭 Edit Site 后仍可见的来源页 view。
- `FinishEditingHandler = (@escaping SiteResultHostCompletion) -> Void`
  - 入口负责完成 modal dismiss，再调用 completion。
- `finishEditingHandler`
  - Sites 入口传入 `SitesViewController.view`；Site 入口传入 `SiteViewController.view`。
- `finishEditing(completion:)`
  - `SiteEditViewController` 内部统一结束编辑并等待来源 host。

---

### Task 1: 用契约测试锁定来源页结果宿主

**Files:**

- Modify: `Tests/Site/SiteUpdateToastUIContractTests.swift:110-156`
- Modify: `Tests/Site/SiteTimeZoneUIContractTests.swift:111-270`

**Interfaces:**

- Consumes: 当前三个 Site controller 的源码文本。
- Produces: 明确要求新接口命名、Site 入口不 pop、两个入口回传自身 view、Time Zone 状态卡使用 active window 的 RED 契约。

- [ ] **Step 1: 更新普通 Toast 路由断言**

将 `SiteUpdateToastUIContractTests` routing 模式改为验证：

```swift
edit.contains("typealias SiteResultHostCompletion = (UIView) -> Void")
edit.contains("typealias FinishEditingHandler = (@escaping SiteResultHostCompletion) -> Void")
edit.contains("private let finishEditingHandler: FinishEditingHandler")
sites.contains("finishEditingHandler:")
sites.contains("completion(self.view)")
site.contains("finishEditingHandler:")
site.contains("completion(self.view)")
!siteEdit.contains("popViewController")
!siteEdit.contains("transitionCoordinator")
!siteEdit.contains("SitesViewController")
```

保留现有 Toast 外观、本地化和四 target membership 断言。

- [ ] **Step 2: 更新时间区完整路由断言**

将 `SiteTimeZoneUIContractTests` 改为验证：

```swift
edit.contains("finishEditingHandler: @escaping FinishEditingHandler")
timeZoneCommit.contains("statusView.show()")
!timeZoneCommit.contains("statusView.show(in: resultHost)")
status.contains("parentView ?? Self.activeWindow")
siteEdit.contains("finishEditingHandler:")
siteEdit.contains("completion(self.view)")
!siteEdit.contains("popViewController")
!siteEdit.contains("SitesViewController")
```

保留 Time Zone 选择、状态、文案、Coordinator、资源和 target 契约。

- [ ] **Step 3: 编译两个契约程序**

Run:

```bash
swiftc -parse-as-library Tests/Site/SiteUpdateToastUIContractTests.swift -o /tmp/SiteUpdateToastUIContractTests
swiftc -parse-as-library Tests/Site/SiteTimeZoneUIContractTests.swift -o /tmp/SiteTimeZoneUIContractTests
```

Expected：两条编译命令退出码均为 0。

- [ ] **Step 4: 运行新路由契约并确认 RED**

Run:

```bash
/tmp/SiteUpdateToastUIContractTests routing SunSmart/Main/Site/Controller/SiteEditViewController.swift SunSmart/Main/Site/Controller/SitesViewController.swift SunSmart/Main/Site/Controller/SiteViewController.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings SunSmart.xcodeproj/project.pbxproj
/tmp/SiteTimeZoneUIContractTests SunSmart/Main/Site/Controller/SiteEditViewController.swift SunSmart/Main/Site/Controller/SiteTimeZoneSelectionViewController.swift SunSmart/Main/Site/View/SiteTimeZoneSelectionCell.swift SunSmart/Main/Site/View/SiteTimeZoneSyncStatusView.swift SunSmart/Main/Site/Controller/SitesViewController.swift SunSmart/Main/Site/Controller/SiteViewController.swift
```

Expected：Toast routing 因旧 `ReturnToSitesHandler` 失败；Time Zone routing 因 Site 入口仍包含 `popViewController` 或状态卡未使用 active window 失败。失败必须来自新行为尚未实现，而不是路径、参数或编译错误。

---

### Task 2: 实现来源页结果宿主路由

**Files:**

- Modify: `SunSmart/Main/Site/Controller/SiteEditViewController.swift:10-56,409-455`
- Modify: `SunSmart/Main/Site/Controller/SitesViewController.swift:638-671`
- Modify: `SunSmart/Main/Site/Controller/SiteViewController.swift:1334-1391`
- Test: `Tests/Site/SiteUpdateToastUIContractTests.swift`
- Test: `Tests/Site/SiteTimeZoneUIContractTests.swift`

**Interfaces:**

- Consumes: Task 1 的 RED 契约。
- Produces: `SiteResultHostCompletion`、`FinishEditingHandler`、`finishEditingHandler`、`finishEditing(completion:)`，以及 Time Zone 全屏状态卡。

- [ ] **Step 1: 重命名编辑器路由契约**

在 `SiteEditViewController` 中执行一致重命名：

```swift
typealias SiteResultHostCompletion = (UIView) -> Void
typealias FinishEditingHandler = (@escaping SiteResultHostCompletion) -> Void
private let finishEditingHandler: FinishEditingHandler
```

初始化参数改为 `finishEditingHandler`；`finishOrdinaryCommit` 和 `finishTimeZoneCommit` 调用 `finishEditing`；私有包装方法调用 `finishEditingHandler(completion)`。

- [ ] **Step 2: 让 Time Zone 状态卡全屏覆盖**

`finishTimeZoneCommit` 只等待编辑页完全关闭，不使用来源 view；调用参数为空的 `show()`，让状态卡回退到 active window：

```swift
statusView.show()
```

不修改 `SiteTimeZoneSyncStatusView` 的视图结构、状态机或文案。

- [ ] **Step 3: 适配 Sites 列表入口**

把初始化标签改为 `finishEditingHandler`。保持既有时序：dismiss modal，刷新列表数据，再调用 `completion(self.view)`。

- [ ] **Step 4: 修改 Site 详情入口**

移除 `sitesViewController` 查找、`popViewController` 和 `transitionCoordinator` 分支。新闭包只执行：

```swift
self.dismiss(animated: true) {
    self.title = self.site.name
    completion(self.view)
}
```

保留现有 `siteDidChange` 标题更新回调和 iPad modal 尺寸。

- [ ] **Step 5: 运行两个 GREEN 路由契约**

Run:

```bash
/tmp/SiteUpdateToastUIContractTests routing SunSmart/Main/Site/Controller/SiteEditViewController.swift SunSmart/Main/Site/Controller/SitesViewController.swift SunSmart/Main/Site/Controller/SiteViewController.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings SunSmart.xcodeproj/project.pbxproj
/tmp/SiteTimeZoneUIContractTests SunSmart/Main/Site/Controller/SiteEditViewController.swift SunSmart/Main/Site/Controller/SiteTimeZoneSelectionViewController.swift SunSmart/Main/Site/View/SiteTimeZoneSelectionCell.swift SunSmart/Main/Site/View/SiteTimeZoneSyncStatusView.swift SunSmart/Main/Site/Controller/SitesViewController.swift SunSmart/Main/Site/Controller/SiteViewController.swift
```

Expected：两次均输出各自的 `passed`，退出码为 0。

---

### Task 3: 回归验证、四品牌构建与总结

**Files:**

- Verify: `Tests/Site/SiteEditAlertTransitionContractTests.swift`
- Verify: `Tests/Site/SiteTimeZoneUIContractTests.swift`
- Verify: `Tests/Site/SiteUpdateToastUIContractTests.swift`
- Verify: `Tests/Site/SitePropsEditPolicyTests.swift`
- Verify: `Tests/Site/SitePropsAPIContractTests.swift`
- Verify: `Tests/Site/SiteTimeZonePersistenceContractTests.swift`
- Create: `docs/260814_1840_edit_site_result_host_implementation_summary.md`

**Interfaces:**

- Consumes: Task 2 的实现。
- Produces: 路由、Toast、Time Zone、policy、API、持久化和四品牌编译均无静态回归的证据。

- [ ] **Step 1: 运行弹窗关闭时序契约**

Run:

```bash
swiftc -parse-as-library Tests/Site/SiteEditAlertTransitionContractTests.swift -o /tmp/SiteEditAlertTransitionContractTests
/tmp/SiteEditAlertTransitionContractTests component SunSmart/Common/View/SRAlertView.swift
/tmp/SiteEditAlertTransitionContractTests edit-site SunSmart/Main/Site/Controller/SiteEditViewController.swift
```

Expected：两次均输出 `SiteEditAlertTransitionContractTests passed`。

- [ ] **Step 2: 运行 Time Zone UI 两种模式**

Run:

```bash
swiftc -parse-as-library Tests/Site/SiteTimeZoneUIContractTests.swift -o /tmp/SiteTimeZoneUIContractTests
/tmp/SiteTimeZoneUIContractTests SunSmart/Main/Site/Controller/SiteEditViewController.swift SunSmart/Main/Site/Controller/SiteTimeZoneSelectionViewController.swift SunSmart/Main/Site/View/SiteTimeZoneSelectionCell.swift SunSmart/Main/Site/View/SiteTimeZoneSyncStatusView.swift SunSmart/Main/Site/Controller/SitesViewController.swift SunSmart/Main/Site/Controller/SiteViewController.swift
/tmp/SiteTimeZoneUIContractTests SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings SunSmart.xcodeproj/project.pbxproj SunSmart/all_utc_timezones.json
```

Expected：两次均输出 `SiteTimeZoneUIContractTests passed`。

- [ ] **Step 3: 运行 Site Update Toast 两种模式**

Run:

```bash
swiftc -parse-as-library Tests/Site/SiteUpdateToastUIContractTests.swift -o /tmp/SiteUpdateToastUIContractTests
/tmp/SiteUpdateToastUIContractTests component SunSmart/Common/View/ToastStatusView.swift SunSmart/Assets.xcassets/Common/site_update_toast_success.imageset/Contents.json SunSmart/Assets.xcassets/Common/site_update_toast_failure.imageset/Contents.json
/tmp/SiteUpdateToastUIContractTests routing SunSmart/Main/Site/Controller/SiteEditViewController.swift SunSmart/Main/Site/Controller/SitesViewController.swift SunSmart/Main/Site/Controller/SiteViewController.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings SunSmart.xcodeproj/project.pbxproj
```

Expected：两次均输出 `SiteUpdateToastUIContractTests passed`。

- [ ] **Step 4: 运行 policy、API 和持久化契约**

Run:

```bash
swiftc -parse-as-library SunSmart/Common/Data/SiteTimeZoneValue.swift SunSmart/Main/Site/Model/SitePropsEditPolicy.swift Tests/Site/SitePropsEditPolicyTests.swift -o /tmp/SitePropsEditPolicyTests
/tmp/SitePropsEditPolicyTests
swiftc -parse-as-library Tests/Site/SitePropsAPIContractTests.swift -o /tmp/SitePropsAPIContractTests
/tmp/SitePropsAPIContractTests SunSmart/Common/Network/NetowrkReqeustApi.swift SunSmart/Main/Site/Model/SitePropsAPIClient.swift SunSmart/Main/Site/Model/SitePropsEditCoordinator.swift SunSmart/Common/Cloud/CloudSynchronizationManager.swift
swiftc -parse-as-library Tests/Site/SiteTimeZonePersistenceContractTests.swift -o /tmp/SiteTimeZonePersistenceContractTests
/tmp/SiteTimeZonePersistenceContractTests SunSmart/Common/Data/SiteData.swift SunSmart/Common/Data/Database.swift SunSmart/Common/Data/MeshNetwork+SunSmart.swift SunSmart/Common/Data/ExportData.swift SunSmart/Common/Data/ImportData.swift
```

Expected：三个测试分别输出自身的 `passed`，退出码均为 0。

- [ ] **Step 5: 检查 diff 健康度与范围**

Run:

```bash
git diff --check
git status --short
git diff --stat
```

Expected：无 whitespace 错误；生产代码只修改三个 Site controller；测试只修改两个 Site contract；文档只包含本需求的分析、计划和总结；没有本地化、资源、project、依赖或 SDK 变更。

- [ ] **Step 6: 依次构建四个品牌 target**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -workspace SunSmart.xcworkspace -scheme Archipelago -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -workspace SunSmart.xcworkspace -scheme 'SLG Sync Plus' -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -workspace SunSmart.xcworkspace -scheme SylSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected：四条命令均以 `** BUILD SUCCEEDED **` 结束，退出码为 0。

- [ ] **Step 7: 写实施总结并复核需求**

总结必须记录：实际改动文件、RED/GREEN 证据、聚焦测试结果、四品牌构建结果、未修改范围，以及以下真机待验收项：

- Sites 与 Site 两个入口；
- 普通更新在线成功、在线失败、响应不匹配、离线；
- Time Zone 在线 success/failure 和离线 pending；
- 本地持久化失败、无变化、Cancel、Close；
- iPhone 与 iPad modal、真实服务器和导航动画。
