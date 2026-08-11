# Edit Site Alert Exit Sequence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task in the current session. Do not use subagents unless the user explicitly changes the execution preference.

**Goal:** 在 Edit Site 的 Time Zone 在线确认和离线提示中，确保自定义弹窗从视图层级移除后才开始保存并返回 Sites。

**Architecture:** 为共享 `SRAlertView` 增加默认关闭的 action-after-dismiss 能力；组件通过真实 dismiss completion 串联 action，Edit Site 仅对两个会继续退出页面的 action 显式启用。现有 Sites/Site 详情返回路由、Site 属性持久化与服务器提交逻辑保持不变。

**Tech Stack:** Swift、UIKit、Foundation、源码契约测试、Xcode generic iPhoneOS build。

## Global Constraints

- 默认使用简体中文记录分析、计划与总结；现有 UI 文案保持 English/简体中文国际化，不新增硬编码文案。
- 采用已确认的方案 A，只修改共享弹窗的 opt-in 能力和 Edit Site 两个接入点。
- `SRAlertAction.performsActionAfterDismiss` 默认必须为 `false`，其他现有调用点不得改变时序。
- 不修改弹窗视觉、动画参数、Site API、timestamp、pending、响应校验、状态卡或 Toast 规则。
- 不修改 `SitesViewController`、`SiteViewController` 的既有返回路由。
- 不修改资源、本地化、target 配置、依赖或 `NordicSigMeshSDK`。
- 保留 worktree 中用户已有改动；不要格式化或重构无关代码。
- 使用 Inline Execution 和阶段性 review checkpoint；不要使用 subagents。
- 未经用户明确授权，不执行 Git commit、push 或 merge。
- iOS 构建必须直接运行 `xcodebuild`，使用 generic iPhoneOS，不使用 shell 包装、日志重定向或 Simulator。
- 构建成功只代表静态集成通过，不代表真机动画和交互已经验收。

---

## File Map

- Create: `Tests/Site/SiteEditAlertTransitionContractTests.swift`
  - 独立验证 `SRAlertView` 关闭完成契约、默认兼容性和 Edit Site 两个 opt-in 接入点。
- Modify: `SunSmart/Common/View/SRAlertView.swift:594-608`
  - 为 dismiss 增加 completion，并保证先移除视图再回调。
- Modify: `SunSmart/Common/View/SRAlertView.swift:627-660`
  - 统一左右 action 的 opt-in/legacy 执行顺序。
- Modify: `SunSmart/Common/View/SRAlertView.swift:1295-1340`
  - 为 `SRAlertAction` 增加默认关闭的 `performsActionAfterDismiss`。
- Modify: `SunSmart/Main/Site/Controller/SiteEditViewController.swift:347-380`
  - 仅在线 `Update Time Zone` 和离线 `Got it` 启用新能力。
- Create: `docs/260811_1726_edit_site_alert_exit_sequence_implementation_summary.md`
  - 记录实际改动、自动化/构建证据和仍需真机验收的边界。

## Interface Contract

- `SRAlertView.dismiss(animation:completion:)`
  - 输入：是否展示既有关闭过渡、可选的关闭完成回调。
  - 保证：有无动画都先 `removeFromSuperview()`，再调用 completion。
- `SRAlertAction.performsActionAfterDismiss`
  - 默认：`false`。
  - 仅当 `closeAlert == true` 且该值为 `true` 时，handler 在 dismiss completion 中执行。
  - 当 `closeAlert == false` 时保持立即执行 handler，不等待不存在的关闭过程。
- `SiteEditViewController.performCommit(online:)`
  - 签名与内部职责不变，只改变两个调用点到达它之前的 UI 时序。

---

### Task 1: 新增 Edit Site 弹窗退出时序 RED 契约

**Files:**

- Create: `Tests/Site/SiteEditAlertTransitionContractTests.swift`
- Reference: `SunSmart/Common/View/SRAlertView.swift:594-660`
- Reference: `SunSmart/Common/View/SRAlertView.swift:1295-1340`
- Reference: `SunSmart/Main/Site/Controller/SiteEditViewController.swift:347-380`

**Interfaces:**

- Consumes: 当前 `SRAlertView` 与 Edit Site 源码文本。
- Produces: `/tmp/SiteEditAlertTransitionContractTests`，支持 `component` 和 `edit-site` 两种模式。

- [ ] **Step 1: 创建聚焦契约测试**

使用以下完整内容创建 `Tests/Site/SiteEditAlertTransitionContractTests.swift`：

```swift
import Foundation

@main
struct SiteEditAlertTransitionContractTests {

    static func main() throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 3 else {
            fatalError("Expected mode and source path")
        }

        switch arguments[1] {
        case "component":
            try testAlertComponent(path: arguments[2])
        case "edit-site":
            try testEditSiteRouting(path: arguments[2])
        default:
            fatalError("Unknown mode: \(arguments[1])")
        }

        print("SiteEditAlertTransitionContractTests passed")
    }

    private static func testAlertComponent(path: String) throws {
        let source = try String(contentsOfFile: path, encoding: .utf8)
        let dismiss = substring(
            in: source,
            from: "public func dismiss(",
            through: "/// 更新进度条进度"
        )
        let actionRouting = substring(
            in: source,
            from: "private func handleAction(_ action: SRAlertAction)",
            through: "/// 左侧按钮点击"
        )
        let buttonRouting = substring(
            in: source,
            from: "@objc private func firstBtnClick()",
            through: "/// 点击背景遮罩"
        )
        let actionType = substring(
            in: source,
            from: "struct SRAlertAction",
            through: "extension SRAlertView"
        )

        require(
            dismiss.contains("completion: (() -> Void)? = nil") &&
                appearsInOrder(
                    ["let finishDismiss", "self?.removeFromSuperview()", "completion?()"],
                    in: dismiss
                ) &&
                occurrences(of: "finishDismiss()", in: dismiss) == 2,
            "Dismiss must remove the alert before completing in animated and immediate paths"
        )
        require(
            actionType.contains("var performsActionAfterDismiss: Bool = false") &&
                actionType.contains("performsActionAfterDismiss: Bool = false") &&
                actionType.contains("self.performsActionAfterDismiss = performsActionAfterDismiss"),
            "SRAlertAction must expose an opt-in flag that defaults to false"
        )
        require(
            actionRouting.contains("action.closeAlert && action.performsActionAfterDismiss") &&
                appearsInOrder(
                    [
                        "dismiss(animation: action.hideAnimation) {",
                        "action.actionHandler?(action)",
                        "} else {",
                        "action.actionHandler?(action)",
                        "if action.closeAlert",
                        "dismiss(animation: action.hideAnimation)"
                    ],
                    in: actionRouting
                ),
            "Opt-in actions must run in dismiss completion while legacy actions keep their order"
        )
        require(
            occurrences(of: "handleAction(action)", in: buttonRouting) == 2,
            "Left and right alert buttons must use the same action routing"
        )
    }

    private static func testEditSiteRouting(path: String) throws {
        let source = try String(contentsOfFile: path, encoding: .utf8)
        let online = substring(
            in: source,
            from: "private func showTimeZoneConfirmation()",
            through: "private func showOfflineTimeZoneAlert()"
        )
        let offline = substring(
            in: source,
            from: "private func showOfflineTimeZoneAlert()",
            through: "private func performCommit(online: Bool)"
        )

        require(
            online.contains(".cancelAction") &&
                online.contains("performsActionAfterDismiss: true") &&
                online.contains("self?.performCommit(online: true)"),
            "Online timezone confirmation must dismiss fully before commit while Cancel remains non-committing"
        )
        require(
            offline.contains("performsActionAfterDismiss: true") &&
                offline.contains("self?.performCommit(online: false)"),
            "Offline timezone acknowledgement must dismiss fully before local commit"
        )
        require(
            occurrences(of: "performsActionAfterDismiss: true", in: source) == 2,
            "Only the two approved Edit Site actions may opt in"
        )
    }

    private static func substring(
        in text: String,
        from start: String,
        through end: String
    ) -> String {
        guard let startRange = text.range(of: start),
              let endRange = text.range(
                  of: end,
                  range: startRange.upperBound..<text.endIndex
              ) else {
            return ""
        }
        return String(text[startRange.lowerBound..<endRange.lowerBound])
    }

    private static func appearsInOrder(_ needles: [String], in text: String) -> Bool {
        var remaining = text[text.startIndex...]
        for needle in needles {
            guard let range = remaining.range(of: needle) else { return false }
            remaining = remaining[range.upperBound...]
        }
        return true
    }

    private static func occurrences(of needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    private static func require(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) {
        guard condition() else { fatalError(message) }
    }
}
```

- [ ] **Step 2: 编译测试程序**

Run:

```bash
swiftc -parse-as-library Tests/Site/SiteEditAlertTransitionContractTests.swift -o /tmp/SiteEditAlertTransitionContractTests
```

Expected：编译成功，退出码为 0。

- [ ] **Step 3: 运行 component 模式并确认 RED**

Run:

```bash
/tmp/SiteEditAlertTransitionContractTests component SunSmart/Common/View/SRAlertView.swift
```

Expected：失败，首个相关错误为 `Dismiss must remove the alert before completing in animated and immediate paths`。

- [ ] **Step 4: 运行 Edit Site 模式并确认 RED**

Run:

```bash
/tmp/SiteEditAlertTransitionContractTests edit-site SunSmart/Main/Site/Controller/SiteEditViewController.swift
```

Expected：失败，错误为在线或离线 action 尚未设置 `performsActionAfterDismiss: true`。

- [ ] **Step 5: Review checkpoint**

确认测试只读取两个目标源码文件，没有依赖 UIKit test host，也没有把实现细节扩展到其他业务页面；不提交 Git。

---

### Task 2: 为 SRAlertView 增加向后兼容的关闭完成能力

**Files:**

- Modify: `SunSmart/Common/View/SRAlertView.swift:594-608`
- Modify: `SunSmart/Common/View/SRAlertView.swift:627-660`
- Modify: `SunSmart/Common/View/SRAlertView.swift:1295-1340`
- Test: `Tests/Site/SiteEditAlertTransitionContractTests.swift`

**Interfaces:**

- Consumes: Task 1 的 component RED 契约。
- Produces: `dismiss(animation:completion:)`、`SRAlertAction.performsActionAfterDismiss` 和统一的 `handleAction(_:)`。

- [ ] **Step 1: 为 dismiss 增加 completion，并在移除后调用**

将现有 dismiss 方法改为：

```swift
public func dismiss(
    animation: Bool = true,
    completion: (() -> Void)? = nil
) {
    self.isDismiss = true
    let finishDismiss = { [weak self] in
        self?.removeFromSuperview()
        completion?()
    }
    if animation {
        UIView.animate(withDuration: 0.15) {
            self.shadeView.alpha = 0
            self.contentView.layer.addScaleAnimation(
                fromScale: 1,
                toScale: 0.7,
                duration: 0.2
            )
        } completion: { _ in
            finishDismiss()
        }
    } else {
        finishDismiss()
    }

    NSObject.cancelPreviousPerformRequests(
        withTarget: self,
        selector: #selector(textExceededHide),
        object: nil
    )
}
```

保持 0.15 秒遮罩过渡、0.2 秒缩放参数和既有取消延迟调用逻辑不变。

- [ ] **Step 2: 为 SRAlertAction 增加默认关闭的 opt-in 属性**

在 `hideAnimation` 后增加：

```swift
/// 是否在弹窗关闭完成后执行点击事件
var performsActionAfterDismiss: Bool = false
```

将初始化方法增加同名默认参数：

```swift
init(
    title: String,
    titleColor: UIColor? = nil,
    titleFont: UIFont? = nil,
    style: SRAlertActionStyle = .default,
    closeAlert: Bool = true,
    hideAnimation: Bool = true,
    performsActionAfterDismiss: Bool = false,
    actionHandler: ((SRAlertAction) -> Void)? = nil
)
```

在现有 `self.hideAnimation = hideAnimation` 后增加：

```swift
self.performsActionAfterDismiss = performsActionAfterDismiss
```

不要修改其他默认参数或 style 赋值逻辑。

- [ ] **Step 3: 增加统一 action 路由**

在按钮 action 区域增加：

```swift
private func handleAction(_ action: SRAlertAction) {
    if action.closeAlert && action.performsActionAfterDismiss {
        dismiss(animation: action.hideAnimation) {
            action.actionHandler?(action)
        }
    } else {
        action.actionHandler?(action)
        if action.closeAlert {
            dismiss(animation: action.hideAnimation)
        }
    }
}
```

该分支确保：

- opt-in 且 `closeAlert == true`：先移除弹窗，再执行 handler；
- 默认 action：保持 handler → dismiss；
- `closeAlert == false`：只执行 handler。

- [ ] **Step 4: 让左右按钮复用统一路由**

将两个按钮中的重复 action/dismiss 代码替换为：

```swift
@objc private func firstBtnClick() {
    if isDismiss {
        return
    }
    if let action = actions.first {
        handleAction(action)
    }
}

@objc private func secondBtnClick() {
    if isDismiss {
        return
    }
    if let action = actions.last {
        handleAction(action)
    }
    if self.inputDoneBack != nil {
        self.inputDoneBack!(self.textField.text ?? "")
    }
}
```

保留 `inputDoneBack` 的现有位置和语义，不扩展输入型弹窗范围。

- [ ] **Step 5: 运行 component 契约并确认 GREEN**

Run:

```bash
swiftc -parse-as-library Tests/Site/SiteEditAlertTransitionContractTests.swift -o /tmp/SiteEditAlertTransitionContractTests
/tmp/SiteEditAlertTransitionContractTests component SunSmart/Common/View/SRAlertView.swift
```

Expected：输出 `SiteEditAlertTransitionContractTests passed`，退出码为 0。

- [ ] **Step 6: 确认 Edit Site 模式仍为 RED**

Run:

```bash
/tmp/SiteEditAlertTransitionContractTests edit-site SunSmart/Main/Site/Controller/SiteEditViewController.swift
```

Expected：仍失败，因为 Task 3 尚未启用两个 action；这证明测试能够区分共享能力与业务接入。

- [ ] **Step 7: Review checkpoint**

检查 `git diff -- SunSmart/Common/View/SRAlertView.swift`：默认值必须为 false，非 opt-in 分支顺序必须保持不变，动画参数不得改变；不提交 Git。

---

### Task 3: 仅在 Edit Site 两个 Time Zone action 启用新时序

**Files:**

- Modify: `SunSmart/Main/Site/Controller/SiteEditViewController.swift:347-380`
- Test: `Tests/Site/SiteEditAlertTransitionContractTests.swift`
- Verify: `SunSmart/Main/Site/Controller/SitesViewController.swift:639-671`
- Verify: `SunSmart/Main/Site/Controller/SiteViewController.swift:850-897`

**Interfaces:**

- Consumes: Task 2 的 `SRAlertAction.performsActionAfterDismiss`。
- Produces: 两个 action 的严格序列：alert remove → `performCommit` → 既有 return-to-Sites 路由。

- [ ] **Step 1: 在线确认 action 显式 opt in**

只在 `site_update_time_zone_action` 对应的 `SRAlertAction` 中增加：

```swift
SRAlertAction(
    title: "site_update_time_zone_action".localizedString,
    performsActionAfterDismiss: true,
    actionHandler: { [weak self] _ in
        self?.performCommit(online: true)
    }
)
```

保持 `.cancelAction` 不变。

- [ ] **Step 2: 离线 Got it action 显式 opt in**

将离线 action 调整为：

```swift
SRAlertAction(
    title: "site_got_it".localizedString,
    performsActionAfterDismiss: true,
    actionHandler: { [weak self] _ in
        self?.performCommit(online: false)
    }
)
```

不要修改 `performCommit`、`finishTimeZoneCommit` 或 `returnToSitesHandler`。

- [ ] **Step 3: 运行 Edit Site 契约并确认 GREEN**

Run:

```bash
/tmp/SiteEditAlertTransitionContractTests edit-site SunSmart/Main/Site/Controller/SiteEditViewController.swift
```

Expected：输出 `SiteEditAlertTransitionContractTests passed`。

- [ ] **Step 4: 同时运行 component 与 Edit Site 模式**

Run:

```bash
/tmp/SiteEditAlertTransitionContractTests component SunSmart/Common/View/SRAlertView.swift
/tmp/SiteEditAlertTransitionContractTests edit-site SunSmart/Main/Site/Controller/SiteEditViewController.swift
```

Expected：两次均输出 `SiteEditAlertTransitionContractTests passed`。

- [ ] **Step 5: Review checkpoint**

人工确认整个 `SiteEditViewController.swift` 中恰好只有两个 `performsActionAfterDismiss: true`，Cancel、普通属性保存、Close、Time Zone Selection 和 return handler 均未改变；不提交 Git。

---

### Task 4: 执行 Site focused regression 与 diff 检查

**Files:**

- Verify: `Tests/Site/SiteEditAlertTransitionContractTests.swift`
- Verify: `Tests/Site/SiteTimeZoneUIContractTests.swift`
- Verify: `Tests/Site/SiteUpdateToastUIContractTests.swift`
- Verify: `Tests/Site/SitePropsEditPolicyTests.swift`
- Verify: `Tests/Site/SitePropsAPIContractTests.swift`
- Verify: `Tests/Site/SiteTimeZonePersistenceContractTests.swift`
- Verify: 本计划涉及的全部源码与文档。

**Interfaces:**

- Consumes: Task 2、Task 3 的实现。
- Produces: 弹窗时序、Site 路由、Toast、policy、API 和持久化均无静态回归的证据。

- [ ] **Step 1: 重新编译并运行新契约两种模式**

Run:

```bash
swiftc -parse-as-library Tests/Site/SiteEditAlertTransitionContractTests.swift -o /tmp/SiteEditAlertTransitionContractTests
/tmp/SiteEditAlertTransitionContractTests component SunSmart/Common/View/SRAlertView.swift
/tmp/SiteEditAlertTransitionContractTests edit-site SunSmart/Main/Site/Controller/SiteEditViewController.swift
```

Expected：两次均输出 `SiteEditAlertTransitionContractTests passed`。

- [ ] **Step 2: 运行 Time Zone UI 完整路由契约**

Run:

```bash
swiftc -parse-as-library Tests/Site/SiteTimeZoneUIContractTests.swift -o /tmp/SiteTimeZoneUIContractTests
/tmp/SiteTimeZoneUIContractTests SunSmart/Main/Site/Controller/SiteEditViewController.swift SunSmart/Main/Site/Controller/SiteTimeZoneSelectionViewController.swift SunSmart/Main/Site/View/SiteTimeZoneSelectionCell.swift SunSmart/Main/Site/View/SiteTimeZoneSyncStatusView.swift SunSmart/Main/Site/Controller/SitesViewController.swift SunSmart/Main/Site/Controller/SiteViewController.swift
/tmp/SiteTimeZoneUIContractTests SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings SunSmart.xcodeproj/project.pbxproj SunSmart/all_utc_timezones.json
```

Expected：两次均输出 `SiteTimeZoneUIContractTests passed`。

- [ ] **Step 3: 运行 Site Update Toast component 与 routing 契约**

Run:

```bash
swiftc -parse-as-library Tests/Site/SiteUpdateToastUIContractTests.swift -o /tmp/SiteUpdateToastUIContractTests
/tmp/SiteUpdateToastUIContractTests component SunSmart/Common/View/ToastStatusView.swift SunSmart/Assets.xcassets/Common/site_update_toast_success.imageset/Contents.json SunSmart/Assets.xcassets/Common/site_update_toast_failure.imageset/Contents.json
/tmp/SiteUpdateToastUIContractTests routing SunSmart/Main/Site/Controller/SiteEditViewController.swift SunSmart/Main/Site/Controller/SitesViewController.swift SunSmart/Main/Site/Controller/SiteViewController.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings SunSmart.xcodeproj/project.pbxproj
```

Expected：两次均输出 `SiteUpdateToastUIContractTests passed`。

- [ ] **Step 4: 运行 Site props policy 契约**

Run:

```bash
swiftc -parse-as-library SunSmart/Common/Data/SiteTimeZoneValue.swift SunSmart/Main/Site/Model/SitePropsEditPolicy.swift Tests/Site/SitePropsEditPolicyTests.swift -o /tmp/SitePropsEditPolicyTests
/tmp/SitePropsEditPolicyTests
```

Expected：输出 `SitePropsEditPolicyTests passed`。

- [ ] **Step 5: 运行 Site props API 契约**

Run:

```bash
swiftc -parse-as-library Tests/Site/SitePropsAPIContractTests.swift -o /tmp/SitePropsAPIContractTests
/tmp/SitePropsAPIContractTests SunSmart/Common/Network/NetowrkReqeustApi.swift SunSmart/Main/Site/Model/SitePropsAPIClient.swift SunSmart/Main/Site/Model/SitePropsEditCoordinator.swift SunSmart/Common/Cloud/CloudSynchronizationManager.swift
```

Expected：输出 `SitePropsAPIContractTests passed`。

- [ ] **Step 6: 运行 Time Zone 持久化契约**

Run:

```bash
swiftc -parse-as-library Tests/Site/SiteTimeZonePersistenceContractTests.swift -o /tmp/SiteTimeZonePersistenceContractTests
/tmp/SiteTimeZonePersistenceContractTests SunSmart/Common/Data/SiteData.swift SunSmart/Common/Data/Database.swift SunSmart/Common/Data/MeshNetwork+SunSmart.swift SunSmart/Common/Data/ExportData.swift SunSmart/Common/Data/ImportData.swift
```

Expected：输出 `SiteTimeZonePersistenceContractTests passed`。

- [ ] **Step 7: 检查 diff 健康度与范围**

Run:

```bash
git diff --check
git status --short
git diff --stat
```

Expected：

- `git diff --check` 无输出；
- 代码改动只包含 `SRAlertView.swift`、`SiteEditViewController.swift` 和新契约测试；
- 文档只包含已确认的设计、实施计划及后续实施总结；
- 没有本地化、资源、project 配置、依赖或 SDK 变更。

- [ ] **Step 8: Review checkpoint**

记录每条命令的实际结果，并明确这些证据不等于真机动画验收；不提交 Git。

---

### Task 5: 执行四品牌 generic iPhoneOS 构建

**Files:**

- Verify: `SunSmart.xcworkspace`
- Verify: `SunSmart.xcodeproj/project.pbxproj`
- Verify: `SunSmart/Common/View/SRAlertView.swift`

**Interfaces:**

- Consumes: Task 4 已通过的 focused contracts。
- Produces: 共享 `SRAlertView` 在四个品牌 target 中可编译集成的证据。

- [ ] **Step 1: 构建 SunSmart**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected：`** BUILD SUCCEEDED **`。

- [ ] **Step 2: 构建 Archipelago**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme Archipelago -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected：`** BUILD SUCCEEDED **`。

- [ ] **Step 3: 构建 SLG Sync Plus**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme 'SLG Sync Plus' -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected：`** BUILD SUCCEEDED **`。

- [ ] **Step 4: 构建 SylSmart**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SylSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected：`** BUILD SUCCEEDED **`。

- [ ] **Step 5: Review checkpoint**

若某个品牌失败，先判断是否为本次 Swift 源码编译错误、既有工程配置问题或环境问题；不得将其他品牌成功当作该品牌通过，也不得使用 Simulator 替代；不提交 Git。

---

### Task 6: 输出实施总结与真机验收清单

**Files:**

- Create: `docs/260811_1726_edit_site_alert_exit_sequence_implementation_summary.md`
- Verify: 本计划授权的全部文件。

**Interfaces:**

- Consumes: Tasks 1–5 的实际 diff、测试和构建结果。
- Produces: 可审阅的完成报告，以及不被自动化证据替代的真机验收边界。

- [ ] **Step 1: 写实施总结**

总结必须包含：

- 实际修改文件与行为；
- 新 action-after-dismiss 契约及默认兼容性；
- 新契约的 RED→GREEN 证据；
- 现有 Site 回归契约结果；
- 四个品牌各自的 build 结果；
- `git diff --check` 结果；
- 未执行 Git commit；
- 真机验收尚未执行时，明确标记为“待验收”，不得写成“已完成”。

- [ ] **Step 2: 列出真机交互清单**

至少包含：

1. Sites 入口、在线、确认更新：弹窗移除后才关闭 Edit Site，随后显示 saving 状态卡。
2. Site 详情入口、在线、确认更新：alert dismiss → modal dismiss → detail pop 严格串行。
3. Sites 入口、离线、`Got it`：弹窗移除后退出，保留 pending，不显示 saving 状态卡。
4. Site 详情入口、离线、`Got it`：三段 UI 过渡严格串行。
5. Cancel：只关闭弹窗，不保存、不退出。
6. 快速重复点击：仅保存和退出一次。
7. 本地持久化失败：弹窗先关闭，停留 Edit Site 并显示失败 HUD。

- [ ] **Step 3: 最终 diff 检查**

Run:

```bash
git diff --check
git status --short
git diff --stat
```

Expected：无空白错误，范围与 Global Constraints 一致。

- [ ] **Step 4: Final review checkpoint**

逐项对照设计文档的 7 条验收标准；完成报告必须区分源码契约、构建验证和真机交互验收，不提交 Git。

---

## Inline Execution Order

实施时严格按以下顺序执行：

1. Task 1：建立两个 RED 契约；
2. Task 2：共享组件 GREEN，Edit Site 仍保持 RED；
3. Task 3：Edit Site 接入 GREEN；
4. Task 4：完整 Site focused regressions 与 diff review；
5. Task 5：四品牌 generic iPhoneOS build；
6. Task 6：总结和真机验收清单。

任何阶段失败都先在当前阶段定位原因，不提前进入后续阶段，不扩展到未授权模块。
