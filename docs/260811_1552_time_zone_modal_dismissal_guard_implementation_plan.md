# Time Zone 模态下拉关闭保护实施计划

> **执行要求：** 使用 `superpowers:executing-plans` 在当前会话中按步骤执行；根据项目约束，不使用 subagents，不创建 Git commit。

**目标：** Time Zone 选择页显示期间禁止下拉关闭 Edit Site 的整个模态导航栈，并在返回 Edit Site 后恢复进入前状态。

**架构：** 由发起 push 的 `SiteEditViewController` 保存 `NavigationViewController.isModalInPresentation` 原值、进入 Time Zone 前锁定导航栈，并在 Edit Site 再次显示时恢复。Time Zone 页面本身不持有或修改模态关闭状态。

**技术栈：** Swift、UIKit、UINavigationController、Swift 源码契约测试、xcodebuild。

## 全局约束

- 仅修改 Edit Site 发起 Time Zone 子流程所需代码和对应回归测试。
- 保持导航栏返回、左滑返回、选择时区后自动返回及其他保存流程不变。
- 恢复保存的原状态，禁止直接写死恢复为 `false`。
- 不修改通用 `NavigationViewController`，不影响其他模态页面。
- 不新增用户可见文案、资源、依赖或认证信息。
- 不创建 Git commit。

---

### Task 1：用 TDD 增加 Time Zone 模态关闭保护

**文件：**

- 修改：`Tests/Site/SiteTimeZoneUIContractTests.swift:80-148`
- 修改：`SunSmart/Main/Site/Controller/SiteEditViewController.swift:30-90`
- 修改：`SunSmart/Main/Site/Controller/SiteEditViewController.swift:471-479`

**接口：**

- 使用：`UINavigationController.isModalInPresentation: Bool`
- 新增私有状态：`modalDismissalStateBeforeTimeZone: Bool?`
- 新增私有方法：`preventModalStackDismissalForTimeZone()`
- 新增私有方法：`restoreModalStackDismissalAfterTimeZoneIfNeeded()`

- [ ] **Step 1：先写失败的 UI 契约测试**

在 Edit Site 契约段增加断言，要求源码同时满足：

```swift
edit.contains("private var modalDismissalStateBeforeTimeZone: Bool?")
edit.contains("restoreModalStackDismissalAfterTimeZoneIfNeeded()")
edit.contains("preventModalStackDismissalForTimeZone()")
edit.contains("navigationController.isModalInPresentation = true")
edit.contains("navigationController?.isModalInPresentation = previousState")
edit.contains("modalDismissalStateBeforeTimeZone = nil")
!edit.contains("navigationController?.isModalInPresentation = false")
```

并用 `appearsInOrder` 验证 `preventModalStackDismissalForTimeZone()` 出现在 `pushViewController(controller, animated: true)` 之前。

- [ ] **Step 2：运行测试并确认 RED**

运行：

```bash
swiftc -parse-as-library Tests/Site/SiteTimeZoneUIContractTests.swift -o /tmp/SiteTimeZoneUIContractTests
/tmp/SiteTimeZoneUIContractTests SunSmart/Main/Site/Controller/SiteEditViewController.swift SunSmart/Main/Site/Controller/SiteTimeZoneSelectionViewController.swift SunSmart/Main/Site/View/SiteTimeZoneSelectionCell.swift SunSmart/Main/Site/View/SiteTimeZoneSyncStatusView.swift SunSmart/Main/Site/Controller/SitesViewController.swift SunSmart/Main/Site/Controller/SiteViewController.swift
```

预期：测试因 Edit Site 尚未保存、锁定和恢复模态关闭状态而失败。

- [ ] **Step 3：实现最小状态保护**

在 `SiteEditViewController` 中增加状态快照：

```swift
private var modalDismissalStateBeforeTimeZone: Bool?
```

在 `selectTimeZone()` push 前调用：

```swift
preventModalStackDismissalForTimeZone()
```

锁定方法只在首次进入时保存原状态，然后锁定整个导航控制器：

```swift
private func preventModalStackDismissalForTimeZone() {
    guard let navigationController else { return }
    if modalDismissalStateBeforeTimeZone == nil {
        modalDismissalStateBeforeTimeZone = navigationController.isModalInPresentation
    }
    navigationController.isModalInPresentation = true
}
```

恢复方法使用保存值并清空快照：

```swift
private func restoreModalStackDismissalAfterTimeZoneIfNeeded() {
    guard let previousState = modalDismissalStateBeforeTimeZone else { return }
    navigationController?.isModalInPresentation = previousState
    modalDismissalStateBeforeTimeZone = nil
}
```

在 `viewDidAppear` 首行生命周期处理后调用恢复方法。初次显示时快照为空，因此不会改变原状态；从 Time Zone 返回时恢复进入前状态。

- [ ] **Step 4：运行局部测试并确认 GREEN**

重新编译并运行 Step 2 的完整 UI 契约命令。

预期：`SiteTimeZoneUIContractTests passed`。

- [ ] **Step 5：运行 Time Zone 全量测试**

重新编译并运行以下 7 个测试入口：

- `SiteTimeZoneValueTests`
- `SiteTimeZoneCatalogTests`
- `SitePropsEditPolicyTests`
- `SiteTimeZonePersistenceContractTests`
- `SitePropsAPIContractTests`
- `SiteTimeZoneUIContractTests` 完整路由契约
- `SiteTimeZoneUIContractTests` 本地化与四 target 成员关系契约

预期：7 个测试全部输出 `passed`，退出码均为 0。

- [ ] **Step 6：构建四个品牌 scheme**

依次直接运行：

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -workspace SunSmart.xcworkspace -scheme Archipelago -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -workspace SunSmart.xcworkspace -scheme 'SLG Sync Plus' -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -workspace SunSmart.xcworkspace -scheme SylSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

预期：四个命令均以 `** BUILD SUCCEEDED **` 和退出码 0 结束；既有 warning 单独记录，不扩展修复范围。

- [ ] **Step 7：完成差异和交付检查**

运行：

```bash
git diff --check
git status --short
```

确认没有空白错误，只包含既有 Time Zone 功能改动、本次两个源码/测试改动和 `docs/` 文档；记录真机仍需验证下拉关闭、返回恢复和选择时区三条路径。
