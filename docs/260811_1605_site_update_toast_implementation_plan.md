# Site 普通属性更新 Toast Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task in the current session. Inline execution is required; do not use subagents unless the user explicitly changes that instruction. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在仅提交 Site name/imageId 时，返回 Sites 页面后使用与 Figma 一致的成功/失败 Toast，同时保持 timezone 状态卡及其他业务 Toast 不变。

**Architecture:** 扩展共享 `ToastStatusView`，以 `Appearance.standard` 和 `Appearance.siteUpdate` 隔离既有视觉与新视觉；Site Edit 路由通过 completion 显式返回最终 Sites host view，普通属性更新完成后只在该 host 上展示新 Toast。字段真值继续由 `SitePropsCommitPlan.includesTimezone` 和 `SitePropsEditCoordinator.submit` 决定，不改变 API、timestamp 或 pending 规则。

**Tech Stack:** Swift、UIKit、SnapKit、Asset Catalog、Foundation-only source contract、Xcode generic iPhoneOS build。

## Global Constraints

- 所有回复、计划记录和测试说明使用简体中文；UI 文案使用 English 与简体中文本地化。
- 失败文案固定为 `Failed to update site.`，简体中文固定为 `场所更新失败。`。
- 成功文案固定为 `Site updated.`，简体中文固定为 `场所已更新。`。
- 最终待发送字段只要包含 timezone，包括历史 pending timezone，就继续使用 Time Zone 专用流程。
- 仅最终待发送字段为 siteName/imageId 时使用 Site Update Toast。
- 现有 `ToastStatusView` 调用默认使用 Standard 外观，Group、Device 等页面视觉不得变化。
- Figma 图标必须来自节点 `425:12304`、`425:12317` 的原始导出，不得手工重画。
- 不新增第三方依赖，不新增 Auth 信息，不顺手重构无关模块。
- 共享资源、本地化或源码变更必须检查 SunSmart、Archipelago、SLG Sync Plus、SylSmart 四个 target。
- iOS 构建直接运行 `xcodebuild`，使用 generic iPhoneOS，不使用 shell 包装、日志重定向或 Simulator。
- 保留 worktree 当前所有既有修改；不得 reset、覆盖或格式化无关文件。
- 未经用户明确授权，不执行 Git commit、push 或 merge；每个任务以 review checkpoint 代替 commit。
- 静态 contract 和 build 通过不等于真实网络、导航动画或真机视觉验收通过。

---

## File Structure

### 新增

- `Tests/Site/SiteUpdateToastUIContractTests.swift`
  - 独立验证 Toast 外观、Figma 资源、Site 普通更新 wiring、返回时序、本地化和共享 target 归属。
- `SunSmart/Assets.xcassets/Common/site_update_toast_success.imageset/Contents.json`
- `SunSmart/Assets.xcassets/Common/site_update_toast_success.imageset/site_update_toast_success.svg`
- `SunSmart/Assets.xcassets/Common/site_update_toast_failure.imageset/Contents.json`
- `SunSmart/Assets.xcassets/Common/site_update_toast_failure.imageset/site_update_toast_failure.svg`
  - 保存 Figma 原始线框成功/失败图标，启用矢量保留。

### 修改

- `SunSmart/Common/View/ToastStatusView.swift`
  - 增加 Standard/Site Update 外观，保留现有默认 API 和动画。
- `SunSmart/Main/Site/Controller/SiteEditViewController.swift`
  - 接收必传 return handler；普通更新使用返回的 Sites host 展示新 Toast。
- `SunSmart/Main/Site/Controller/SitesViewController.swift`
  - modal dismiss 后把当前 Sites view 传回编辑器 completion。
- `SunSmart/Main/Site/Controller/SiteViewController.swift`
  - dismiss、pop 并等待 transition 完成后，把 Sites view 传回 completion。
- `Tests/Site/SiteTimeZoneUIContractTests.swift`
  - 更新 `SiteEditViewController` 初始化契约，不放宽 timezone 原有断言。

### 核对但原则上不修改

- `SunSmart/en.lproj/Localizable.strings`
- `SunSmart/zh-Hans.lproj/Localizable.strings`
- `SunSmart.xcodeproj/project.pbxproj`

---

### Task 1: 建立 Site Update Toast 失败契约

**Files:**

- Create: `Tests/Site/SiteUpdateToastUIContractTests.swift`
- Reference: `docs/260811_1600_site_update_toast_design.md`

**Interfaces:**

- Consumes: Toast 源码路径、两个 imageset Contents 路径、Site 三个控制器路径、双语本地化路径、project 文件路径。
- Produces: `/tmp/SiteUpdateToastUIContractTests`；支持 `component` 与 `routing` 两种运行模式。

- [ ] **Step 1: 新建 focused contract 源文件**

写入以下完整测试骨架。测试只读取源码和资源，不依赖 UIKit 或 XCTest target：

```swift
import Foundation

@main
struct SiteUpdateToastUIContractTests {

    static func main() throws {
        let arguments = CommandLine.arguments
        guard arguments.count >= 2 else {
            fatalError("Expected component or routing mode")
        }

        switch arguments[1] {
        case "component":
            guard arguments.count == 5 else {
                fatalError("Expected ToastStatusView and two imageset Contents paths")
            }
            try testComponent(arguments: arguments)
        case "routing":
            guard arguments.count == 8 else {
                fatalError("Expected Edit, Sites, Site, English, Chinese, and project paths")
            }
            try testRouting(arguments: arguments)
        default:
            fatalError("Unknown mode: \(arguments[1])")
        }

        print("SiteUpdateToastUIContractTests passed")
    }

    private static func testComponent(arguments: [String]) throws {
        let toast = try String(contentsOfFile: arguments[2], encoding: .utf8)
        let successContents = try String(contentsOfFile: arguments[3], encoding: .utf8)
        let failureContents = try String(contentsOfFile: arguments[4], encoding: .utf8)

        require(
            toast.contains("enum Appearance") &&
                toast.contains("case standard") &&
                toast.contains("case siteUpdate") &&
                toast.contains("appearance: Appearance = .standard"),
            "Toast must add an opt-in Site Update appearance and keep Standard as default"
        )
        require(
            toast.contains("site_update_toast_success") &&
                toast.contains("site_update_toast_failure"),
            "Site Update appearance must use dedicated Figma assets"
        )
        require(
            toast.contains("equalToSuperview().offset(-32)") &&
                toast.contains("lessThanOrEqualTo(343)") &&
                toast.contains("equalTo(44)") &&
                toast.contains("equalTo(30)") &&
                toast.contains("equalTo(16)"),
            "Site Update Toast must encode 16pt margins, 343pt max width, 44pt height, and 30/16pt icon sizes"
        )
        require(
            toast.contains("systemFont(ofSize: 15, weight: .light)") &&
                toast.contains("stackView.spacing = 10") &&
                toast.contains("layer.cornerRadius = 13"),
            "Site Update Toast must encode the Figma typography, gap, and radius"
        )
        require(
            toast.contains("shadowOpacity = 0.15") &&
                toast.contains("height: 2") &&
                toast.contains("withAlphaComponent(0.6)"),
            "Site Update Toast must encode the Figma shadow and black overlay"
        )
        require(
            successContents.contains("site_update_toast_success.svg") &&
                successContents.contains("preserves-vector-representation"),
            "Success imageset must preserve the exact Figma vector"
        )
        require(
            failureContents.contains("site_update_toast_failure.svg") &&
                failureContents.contains("preserves-vector-representation"),
            "Failure imageset must preserve the exact Figma vector"
        )
    }

    private static func testRouting(arguments: [String]) throws {
        let edit = try String(contentsOfFile: arguments[2], encoding: .utf8)
        let sites = try String(contentsOfFile: arguments[3], encoding: .utf8)
        let site = try String(contentsOfFile: arguments[4], encoding: .utf8)
        let english = try String(contentsOfFile: arguments[5], encoding: .utf8)
        let chinese = try String(contentsOfFile: arguments[6], encoding: .utf8)
        let project = try String(contentsOfFile: arguments[7], encoding: .utf8)

        let ordinary = substring(
            in: edit,
            from: "private func finishOrdinaryCommit",
            through: "private func finishTimeZoneCommit"
        )
        require(
            edit.contains("typealias SiteReturnCompletion = (UIView) -> Void") &&
                edit.contains("typealias ReturnToSitesHandler = (@escaping SiteReturnCompletion) -> Void") &&
                edit.contains("private let returnToSitesHandler: ReturnToSitesHandler"),
            "Edit Site must require an escaping route completion that returns the final host view"
        )
        require(
            ordinary.contains("returnToSites {") &&
                ordinary.contains("toastHost in") &&
                ordinary.contains("ToastStatusView.show") &&
                ordinary.contains("appearance: .siteUpdate") &&
                ordinary.contains("\"site_updated_toast\".localizedString") &&
                ordinary.contains("\"site_update_failed_toast\".localizedString") &&
                !ordinary.contains("XWHUDManager"),
            "Ordinary update results must use the Site Update Toast on the returned Sites host"
        )
        require(
            occurrences(of: "XWHUDManager.showErrorTipHUD", in: edit) == 1 &&
                edit.contains("SiteTimeZoneSyncStatusView"),
            "Only local persistence failure keeps the old HUD and timezone keeps its status card"
        )
        require(
            sites.contains("returnToSitesHandler:") &&
                sites.contains("completion(self.view)"),
            "Sites entry must pass its visible view after modal dismissal"
        )
        require(
            site.contains("returnToSitesHandler:") &&
                site.contains("transitionCoordinator") &&
                site.contains("context.isCancelled") &&
                site.contains("completion(destinationView)") &&
                site.contains("assertionFailure"),
            "Site entry must wait for pop completion and provide a safe visible host"
        )
        require(
            english.contains("\"site_updated_toast\" = \"Site updated.\";") &&
                english.contains("\"site_update_failed_toast\" = \"Failed to update site.\";") &&
                chinese.contains("\"site_updated_toast\" = \"场所已更新。\";") &&
                chinese.contains("\"site_update_failed_toast\" = \"场所更新失败。\";"),
            "Site update copy must remain exact in both supported languages"
        )
        let sourcePhase = substring(
            in: project,
            from: "/* Begin PBXSourcesBuildPhase section */",
            through: "/* End PBXSourcesBuildPhase section */"
        )
        let resourcePhase = substring(
            in: project,
            from: "/* Begin PBXResourcesBuildPhase section */",
            through: "/* End PBXResourcesBuildPhase section */"
        )
        require(
            occurrences(of: "ToastStatusView.swift in Sources", in: sourcePhase) == 4 &&
                occurrences(of: "Localizable.strings in Resources", in: resourcePhase) == 4 &&
                occurrences(of: "/* Assets.xcassets in Resources */", in: resourcePhase) == 4,
            "Shared Toast, localization, and assets must remain available to all four targets"
        )
    }

    private static func substring(in text: String, from start: String, through end: String) -> String {
        guard let startRange = text.range(of: start),
              let endRange = text.range(of: end, range: startRange.upperBound..<text.endIndex) else {
            return ""
        }
        return String(text[startRange.lowerBound..<endRange.lowerBound])
    }

    private static func occurrences(of needle: String, in haystack: String) -> Int {
        return haystack.components(separatedBy: needle).count - 1
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }
}
```

- [ ] **Step 2: 编译 contract executable**

Run:

```bash
swiftc -parse-as-library Tests/Site/SiteUpdateToastUIContractTests.swift -o /tmp/SiteUpdateToastUIContractTests
```

Expected：编译成功。

- [ ] **Step 3: 验证 component 模式先失败**

Run:

```bash
/tmp/SiteUpdateToastUIContractTests component SunSmart/Common/View/ToastStatusView.swift SunSmart/Assets.xcassets/Common/site_update_toast_success.imageset/Contents.json SunSmart/Assets.xcassets/Common/site_update_toast_failure.imageset/Contents.json
```

Expected：FAIL；首先因为 Site Update imageset 尚不存在，或 Toast 尚无 `Appearance.siteUpdate`。

- [ ] **Step 4: 验证 routing 模式先失败**

Run:

```bash
/tmp/SiteUpdateToastUIContractTests routing SunSmart/Main/Site/Controller/SiteEditViewController.swift SunSmart/Main/Site/Controller/SitesViewController.swift SunSmart/Main/Site/Controller/SiteViewController.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings SunSmart.xcodeproj/project.pbxproj
```

Expected：FAIL，提示 ordinary update 尚未使用 Site Update Toast 或 return handler 尚未返回 host view。

- [ ] **Step 5: Review checkpoint**

检查本任务只新增测试文件；不提交 Git，等待进入 Task 2。

---

### Task 2: 导入 Figma 图标并实现 Site Update Toast 外观

**Files:**

- Create: `SunSmart/Assets.xcassets/Common/site_update_toast_success.imageset/Contents.json`
- Create: `SunSmart/Assets.xcassets/Common/site_update_toast_success.imageset/site_update_toast_success.svg`
- Create: `SunSmart/Assets.xcassets/Common/site_update_toast_failure.imageset/Contents.json`
- Create: `SunSmart/Assets.xcassets/Common/site_update_toast_failure.imageset/site_update_toast_failure.svg`
- Modify: `SunSmart/Common/View/ToastStatusView.swift`
- Test: `Tests/Site/SiteUpdateToastUIContractTests.swift`

**Interfaces:**

- Consumes: Figma success node `425:12304`、failure node `425:12317`；现有 `ToastType`、`Position` 和 `show` API。
- Produces: `ToastStatusView.Appearance.standard/siteUpdate`；`show(... appearance: Appearance = .standard)`；两个共享矢量图标。

- [ ] **Step 1: 重新读取并保存 Figma 原始图标**

通过 Figma connector 分别对节点 `425:12304`、`425:12317` 调用 design context，取得当次有效的 SVG asset URL。把原始 SVG 下载到 `/tmp`，验证文件是可解析 SVG；不要使用当前文档中的过期 URL，不要手工修改 path、stroke 或颜色。

Run after download:

```bash
xmllint --noout /tmp/site_update_toast_success.svg
xmllint --noout /tmp/site_update_toast_failure.svg
```

Expected：两条命令退出码均为 0。

- [ ] **Step 2: 新增两个共享 imageset**

两个 `Contents.json` 分别使用以下结构，仅替换对应文件名：

```json
{
  "images" : [
    {
      "filename" : "site_update_toast_success.svg",
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  },
  "properties" : {
    "preserves-vector-representation" : true
  }
}
```

失败 imageset 的 filename 必须是 `site_update_toast_failure.svg`。使用 `apply_patch` 把 `/tmp` 中未经修改的 SVG 文本加入对应目录；不得替换现有 `toast_success`、`toast_failed`。

- [ ] **Step 3: 在 ToastStatusView 增加外观接口**

在 `ToastType` 后新增：

```swift
enum Appearance {
    case standard
    case siteUpdate
}
```

让 `ToastType` 根据外观选择资源：

```swift
func icon(for appearance: Appearance) -> UIImage? {
    switch (self, appearance) {
    case (.success, .standard):
        return UIImage(named: "toast_success")
    case (.failure, .standard):
        return UIImage(named: "toast_failed")
    case (.success, .siteUpdate):
        return UIImage(named: "site_update_toast_success")
    case (.failure, .siteUpdate):
        return UIImage(named: "site_update_toast_failure")
    }
}
```

保留现有 Standard 的布局函数，不更改其字体、图标、左右约束、行数或动画。

- [ ] **Step 4: 实现 Site Update 专用视图层次**

新增 `siteContentView`、`overlayView`、`iconContainerView`。Site Update setup 必须满足：

```swift
layer.cornerRadius = 13
layer.masksToBounds = false
layer.shadowColor = UIColor.black.cgColor
layer.shadowOpacity = 0.15
layer.shadowOffset = CGSize(width: 0, height: 2)
layer.shadowRadius = 2.5

siteContentView.layer.cornerRadius = 13
siteContentView.layer.masksToBounds = true
overlayView.backgroundColor = UIColor.black.withAlphaComponent(0.6)

messageLabel.font = .systemFont(ofSize: 15, weight: .light)
messageLabel.textColor = .white
messageLabel.textAlignment = .center
messageLabel.numberOfLines = 1

stackView.axis = .horizontal
stackView.spacing = 10
stackView.alignment = .center
```

层次顺序固定为：`siteContentView` → `blurView` → `overlayView` → `stackView`；stack 内为 `iconContainerView`、`messageLabel`。图标容器 30 × 30 pt，`iconView` 在容器内居中且为 16 × 16 pt。stack 水平居中，并保证左右至少 22 pt 内容空间。

- [ ] **Step 5: 扩展 show API 并保持默认兼容**

公开接口增加默认外观参数：

```swift
static func show(
    in superview: UIView,
    message: String,
    type: ToastType,
    appearance: Appearance = .standard,
    position: Position = .bottom,
    duration: TimeInterval = 1.5
)
```

Standard 继续使用原左右 20 pt、最小高度 44 pt 约束。Site Update 使用：

```swift
make.centerX.equalToSuperview()
make.width.equalToSuperview().offset(-32).priority(.high)
make.width.lessThanOrEqualTo(343)
make.height.equalTo(44)
```

位置、0.25 秒进出动画、bottom 安全区上方 24 pt、默认 1.5 秒时长保持不变。

- [ ] **Step 6: 运行 component contract**

Run:

```bash
/tmp/SiteUpdateToastUIContractTests component SunSmart/Common/View/ToastStatusView.swift SunSmart/Assets.xcassets/Common/site_update_toast_success.imageset/Contents.json SunSmart/Assets.xcassets/Common/site_update_toast_failure.imageset/Contents.json
```

Expected：`SiteUpdateToastUIContractTests passed`。

- [ ] **Step 7: 核对 Standard 调用未被扩散修改**

Run:

```bash
rg -n "ToastStatusView.show" SunSmart --glob '*.swift'
```

Expected：Group、Device 既有调用没有新增 `appearance: .siteUpdate`；只有后续 Site 普通更新调用会显式使用该外观。

- [ ] **Step 8: Review checkpoint**

检查新 SVG 与 Figma 导出完全一致，Standard diff 聚焦；不提交 Git。

---

### Task 3: 将普通更新结果绑定到返回后的 Sites host

**Files:**

- Modify: `SunSmart/Main/Site/Controller/SiteEditViewController.swift`
- Modify: `SunSmart/Main/Site/Controller/SitesViewController.swift`
- Modify: `SunSmart/Main/Site/Controller/SiteViewController.swift`
- Modify: `Tests/Site/SiteTimeZoneUIContractTests.swift`
- Test: `Tests/Site/SiteUpdateToastUIContractTests.swift`

**Interfaces:**

- Consumes: `SitePropsCommitPlan.includesTimezone`、`SitePropsEditCoordinator.submit`、`ToastStatusView.Appearance.siteUpdate`。
- Produces: `SiteReturnCompletion = (UIView) -> Void`、`ReturnToSitesHandler = (@escaping SiteReturnCompletion) -> Void`；两个入口在 Sites 可见后提供 host。

- [ ] **Step 1: 将 return handler 变为初始化依赖**

在 `SiteEditViewController` 中定义并保存：

```swift
typealias SiteReturnCompletion = (UIView) -> Void
typealias ReturnToSitesHandler = (@escaping SiteReturnCompletion) -> Void

private let returnToSitesHandler: ReturnToSitesHandler
```

初始化器改为：

```swift
init(
    site: SiteData,
    draft: SitePropsEditDraft,
    coordinator: SitePropsEditCoordinator,
    returnToSitesHandler: @escaping ReturnToSitesHandler
)
```

删除可选 `var returnToSitesHandler` 和无 handler 时查找 presenting/navigation controller 的 fallback。两个已知入口必须显式传入 handler。

- [ ] **Step 2: 普通更新在 host 上展示新 Toast**

`finishOrdinaryCommit` 保持先返回、后提交。completion 接收 `toastHost`，统一封装结果展示：

```swift
private func showOrdinaryUpdateToast(in host: UIView, success: Bool) {
    ToastStatusView.show(
        in: host,
        message: success
            ? "site_updated_toast".localizedString
            : "site_update_failed_toast".localizedString,
        type: success ? .success : .failure,
        appearance: .siteUpdate
    )
}
```

分支必须是：

- offline 或 snapshot nil：立即 failure；
- online submit 完整校验成功：success；
- online submit 请求/解析/字段校验失败：failure。

删除普通更新返回后的 `XWHUDManager.showSuccessTipHUD` 和 `showErrorTipHUD`。`performCommit` 中本地 `persist` 失败仍保留唯一一处 `XWHUDManager.showErrorTipHUD`，并停留编辑页。

- [ ] **Step 3: timezone completion 适配 host 参数但不使用 Toast**

`finishTimeZoneCommit` 改为接收但忽略 host：

```swift
returnToSites { [coordinator, siteDidChange] _ in
    // 保留现有 SiteTimeZoneSyncStatusView 流程
}
```

不得改变 confirmation、offline alert、status view state 或 submit 规则。

- [ ] **Step 4: Sites 入口在 dismiss 完成后提供 host**

构造 `SiteEditViewController` 时直接传入：

```swift
returnToSitesHandler: { [weak self] completion in
    guard let self = self else { return }
    self.dismiss(animated: true) {
        self.reloadSiteData(site)
        completion(self.view)
    }
}
```

删除构造后的可选属性赋值；`siteDidChange` 继续保留即时刷新。

- [ ] **Step 5: Site 详情入口等待 pop transition 完成**

在创建编辑器前从导航栈获取 `SitesViewController` 弱引用：

```swift
let sitesViewController = navigationController?.viewControllers
    .last(where: { $0 is SitesViewController }) as? SitesViewController
```

return handler 的顺序固定为 dismiss → 更新 title → pop → 等待 transition → completion：

```swift
returnToSitesHandler: { [weak self, weak sitesViewController] completion in
    guard let self = self else { return }
    self.dismiss(animated: true) {
        self.title = self.site.name
        guard let navigationController = self.navigationController else { return }

        let destinationView: UIView
        if let sitesView = sitesViewController?.view {
            destinationView = sitesView
        } else {
            assertionFailure("SitesViewController is missing from the navigation stack")
            destinationView = navigationController.view
        }

        navigationController.popViewController(animated: true)
        guard let transitionCoordinator = navigationController.transitionCoordinator else {
            completion(destinationView)
            return
        }
        transitionCoordinator.animate(alongsideTransition: nil) { context in
            completion(context.isCancelled ? navigationController.view : destinationView)
        }
    }
}
```

completion 必须只调用一次。不要用固定 delay，不要查找 UIApplication 全局 window。

- [ ] **Step 6: 更新现有 timezone UI contract 的初始化断言**

将旧的单行初始化器断言替换为以下组合断言：

```swift
edit.contains("init(") &&
    edit.contains("site: SiteData") &&
    edit.contains("draft: SitePropsEditDraft") &&
    edit.contains("coordinator: SitePropsEditCoordinator") &&
    edit.contains("returnToSitesHandler: @escaping ReturnToSitesHandler")
```

保留其余 timezone、状态卡、两个入口和本地化断言；不得删除断言来让测试通过。

- [ ] **Step 7: 重新编译并运行 routing contract**

Run:

```bash
swiftc -parse-as-library Tests/Site/SiteUpdateToastUIContractTests.swift -o /tmp/SiteUpdateToastUIContractTests
/tmp/SiteUpdateToastUIContractTests routing SunSmart/Main/Site/Controller/SiteEditViewController.swift SunSmart/Main/Site/Controller/SitesViewController.swift SunSmart/Main/Site/Controller/SiteViewController.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings SunSmart.xcodeproj/project.pbxproj
```

Expected：`SiteUpdateToastUIContractTests passed`。

- [ ] **Step 8: 运行完整 timezone UI contract**

Run:

```bash
swiftc -parse-as-library Tests/Site/SiteTimeZoneUIContractTests.swift -o /tmp/SiteTimeZoneUIContractTests
/tmp/SiteTimeZoneUIContractTests SunSmart/Main/Site/Controller/SiteEditViewController.swift SunSmart/Main/Site/Controller/SiteTimeZoneSelectionViewController.swift SunSmart/Main/Site/Controller/SitesViewController.swift SunSmart/Main/Site/Controller/SiteViewController.swift SunSmart/Main/Site/View/SiteTimeZoneSelectionCell.swift SunSmart/Main/Site/View/SiteTimeZoneSyncStatusView.swift
```

Expected：`SiteTimeZoneUIContractTests passed`。

- [ ] **Step 9: Review checkpoint**

检查两个入口 completion 时序、只显示一次 Toast、timezone 分支未变化；不提交 Git。

---

### Task 4: 执行 Site 回归 contracts 与资源/target 检查

**Files:**

- Verify: `Tests/Site/*.swift`
- Verify: `SunSmart/en.lproj/Localizable.strings`
- Verify: `SunSmart/zh-Hans.lproj/Localizable.strings`
- Verify: `SunSmart.xcodeproj/project.pbxproj`
- Verify: `SunSmart/Assets.xcassets/Common/site_update_toast_*.imageset/`

**Interfaces:**

- Consumes: Task 2、Task 3 的全部产物。
- Produces: 所有 Site focused contracts 通过的证据；双语文案和四 target 共享资源证据。

- [ ] **Step 1: 运行 Site props policy contract**

Run:

```bash
swiftc -parse-as-library SunSmart/Common/Data/SiteTimeZoneValue.swift SunSmart/Main/Site/Model/SitePropsEditPolicy.swift Tests/Site/SitePropsEditPolicyTests.swift -o /tmp/SitePropsEditPolicyTests
/tmp/SitePropsEditPolicyTests
```

Expected：`SitePropsEditPolicyTests passed`。

- [ ] **Step 2: 运行 Site props API contract**

Run:

```bash
swiftc -parse-as-library Tests/Site/SitePropsAPIContractTests.swift -o /tmp/SitePropsAPIContractTests
/tmp/SitePropsAPIContractTests SunSmart/Common/Network/NetowrkReqeustApi.swift SunSmart/Main/Site/Model/SitePropsAPIClient.swift SunSmart/Main/Site/Model/SitePropsEditCoordinator.swift SunSmart/Common/Cloud/CloudSynchronizationManager.swift
```

Expected：`SitePropsAPIContractTests passed`。

- [ ] **Step 3: 运行 timezone persistence contract**

Run:

```bash
swiftc -parse-as-library Tests/Site/SiteTimeZonePersistenceContractTests.swift -o /tmp/SiteTimeZonePersistenceContractTests
/tmp/SiteTimeZonePersistenceContractTests SunSmart/Common/Data/Database.swift SunSmart/Common/Data/SiteData.swift SunSmart/Common/Data/ExportData.swift SunSmart/Common/Data/ImportData.swift SunSmart/Common/Data/MeshNetwork+SunSmart.swift
```

Expected：`SiteTimeZonePersistenceContractTests passed`。

- [ ] **Step 4: 运行 Toast component 与 routing contract**

Run:

```bash
/tmp/SiteUpdateToastUIContractTests component SunSmart/Common/View/ToastStatusView.swift SunSmart/Assets.xcassets/Common/site_update_toast_success.imageset/Contents.json SunSmart/Assets.xcassets/Common/site_update_toast_failure.imageset/Contents.json
/tmp/SiteUpdateToastUIContractTests routing SunSmart/Main/Site/Controller/SiteEditViewController.swift SunSmart/Main/Site/Controller/SitesViewController.swift SunSmart/Main/Site/Controller/SiteViewController.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings SunSmart.xcodeproj/project.pbxproj
```

Expected：两次均输出 `SiteUpdateToastUIContractTests passed`。

- [ ] **Step 5: 运行 timezone UI 本地化/资源模式**

Run:

```bash
/tmp/SiteTimeZoneUIContractTests SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings SunSmart.xcodeproj/project.pbxproj SunSmart/all_utc_timezones.json
```

Expected：`SiteTimeZoneUIContractTests passed`。

- [ ] **Step 6: 检查精确文案唯一性**

Run:

```bash
rg -n '"site_(updated|update_failed)_toast"' SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings
```

Expected：每个 Key 在每种语言中恰好出现一次，值与 Global Constraints 一致。

- [ ] **Step 7: 检查 diff 健康度**

Run:

```bash
git diff --check
git status --short
```

Expected：`git diff --check` 无输出；status 只包含用户既有修改和本计划授权的文件。

- [ ] **Step 8: Review checkpoint**

记录所有 contract 的实际输出和未覆盖边界；不提交 Git。

---

### Task 5: 四品牌构建与人工验收

**Files:**

- Verify: `SunSmart.xcworkspace`
- Verify: Task 2、Task 3 的所有源码与资源
- Update after verification only: `docs/260811_1605_site_update_toast_implementation_plan.md` 的 checkbox 或执行记录

**Interfaces:**

- Consumes: 所有 focused contracts 通过后的工作树。
- Produces: 四个 generic iPhoneOS build 结果；人工/真机待验收清单；静态、构建和运行时证据边界。

- [ ] **Step 1: 构建 SunSmart**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected：`BUILD SUCCEEDED`。

- [ ] **Step 2: 构建 Archipelago**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme Archipelago -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected：`BUILD SUCCEEDED`。

- [ ] **Step 3: 构建 SLG Sync Plus**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme 'SLG Sync Plus' -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected：`BUILD SUCCEEDED`。

- [ ] **Step 4: 构建 SylSmart**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SylSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected：`BUILD SUCCEEDED`。

- [ ] **Step 5: 静态检查 Site 普通/Timezone 分支**

确认：

- 普通分支只有新 `ToastStatusView`，没有返回后的 XWHUD；
- 本地 persist 失败仍是唯一的 XWHUD 错误提示；
- `plan.includesTimezone` 分支和 `SiteTimeZoneSyncStatusView` 未被改写；
- Standard Toast 的现有 Group、Device 调用没有传 `.siteUpdate`；
- 两个 Figma SVG 只新增、不替换原资源。

- [ ] **Step 6: 人工/真机验收矩阵**

逐项记录结果：

1. Sites 入口：仅改 name，在线成功；
2. Site 详情入口：仅改 icon，返回动画结束后成功 Toast 才出现；
3. 在线请求失败；
4. code 成功但 timestamp 或已发送字段不匹配；
5. 离线 name/icon，显示失败 Toast 并保留 pending；
6. 本地数据库保存失败，停留编辑页；
7. 历史 pending timezone 加本次 name/icon，仍显示 Time Zone 状态卡；
8. 无变化且无 pending，不显示 Toast；
9. English 和简体中文；
10. 小屏 iPhone、375 pt iPhone、iPad；
11. 成功/失败图标、343 × 44、16 pt 边距、13 pt 圆角、Black 60%、blur、阴影、15 pt Light 与 Figma 对照；
12. Group、Device 既有 Standard Toast 无视觉回归。

- [ ] **Step 7: 最终验证重跑**

再次运行：

```bash
git diff --check
/tmp/SiteUpdateToastUIContractTests component SunSmart/Common/View/ToastStatusView.swift SunSmart/Assets.xcassets/Common/site_update_toast_success.imageset/Contents.json SunSmart/Assets.xcassets/Common/site_update_toast_failure.imageset/Contents.json
/tmp/SiteUpdateToastUIContractTests routing SunSmart/Main/Site/Controller/SiteEditViewController.swift SunSmart/Main/Site/Controller/SitesViewController.swift SunSmart/Main/Site/Controller/SiteViewController.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings SunSmart.xcodeproj/project.pbxproj
/tmp/SiteTimeZoneUIContractTests SunSmart/Main/Site/Controller/SiteEditViewController.swift SunSmart/Main/Site/Controller/SiteTimeZoneSelectionViewController.swift SunSmart/Main/Site/Controller/SitesViewController.swift SunSmart/Main/Site/Controller/SiteViewController.swift SunSmart/Main/Site/View/SiteTimeZoneSelectionCell.swift SunSmart/Main/Site/View/SiteTimeZoneSyncStatusView.swift
```

Expected：diff check 无输出，三个 contract invocation 全部通过。

- [ ] **Step 8: Completion report**

最终报告必须分别列出：

- 实际修改文件；
- focused contracts；
- 四品牌 build；
- 已完成的人工/真机项目；
- 未执行的真实网络、真机或视觉项目；
- 未经授权没有 commit/push。
