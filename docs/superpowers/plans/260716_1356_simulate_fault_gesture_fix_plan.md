# Simulate Fault Gesture Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan inline. Project instructions prohibit subagents unless explicitly authorized.

**Goal:** 保证只有弹窗内容区域外的点击才关闭 Simulate Fault，并让遮罩覆盖整个 Navigation Bar。

**Architecture:** 使用纯逻辑 dismissal policy 判定 model/presentation content frame；overlay 手势代理在触摸开始时过滤内容区触摸。控制器将 overlay 挂载到 Navigation Controller 根视图以扩大遮罩范围，并在弹窗生命周期内暂停、退出后恢复交互式侧滑返回。

**Tech Stack:** Swift、UIKit、SnapKit、shell contract、`swiftc`、`xcodebuild`。

## Global Constraints

- 仅修改 Simulate Fault 相关模型、弹窗、light 页面和对应测试。
- 只传递 Simulate Fault 事件，不发送设备命令。
- 不使用 Simulator；四品牌均使用 iPhoneOS Debug 构建。
- 保留用户现有未提交文件和无关文档。

---

### Task 1: 内容区域 dismissal policy

**Files:**
- Modify: `Tests/Device/SimulateFaultModelTests.swift`
- Modify: `SunSmart/Main/Device/Model/SimulateFaultAction.swift`

**Interfaces:**
- Produces: `SimulateFaultDismissalPolicy.shouldRecognizeOutsideTap(at:contentFrame:presentationFrame:) -> Bool`

- [ ] **Step 1: 添加失败测试**

增加三个断言：触点在 model frame 内返回 `false`；只在 presentation frame 内返回 `false`；同时位于两者之外返回 `true`。

- [ ] **Step 2: 验证 RED**

Run: `swiftc SunSmart/Main/Device/Model/SimulateFaultAction.swift Tests/Device/SimulateFaultModelTests.swift -o /tmp/SimulateFaultModelTests`

Expected: FAIL，提示找不到 `SimulateFaultDismissalPolicy`。

- [ ] **Step 3: 增加最小纯逻辑实现**

在模型文件中增加：

```swift
enum SimulateFaultDismissalPolicy {
    static func shouldRecognizeOutsideTap(
        at location: CGPoint,
        contentFrame: CGRect,
        presentationFrame: CGRect?
    ) -> Bool {
        guard !contentFrame.contains(location) else { return false }
        guard presentationFrame?.contains(location) != true else { return false }
        return true
    }
}
```

- [ ] **Step 4: 验证 GREEN**

Run: `swiftc SunSmart/Main/Device/Model/SimulateFaultAction.swift Tests/Device/SimulateFaultModelTests.swift -o /tmp/SimulateFaultModelTests && /tmp/SimulateFaultModelTests`

Expected: `SimulateFaultModelTests passed`。

### Task 2: Overlay 手势过滤与 Navigation Bar 覆盖

**Files:**
- Modify: `scripts/check_simulate_fault.sh`
- Modify: `SunSmart/Main/Device/View/SimulateFaultOverlayView.swift`
- Modify: `SunSmart/Main/Device/Controller/DeviceLightViewController.swift`

**Interfaces:**
- Consumes: `SimulateFaultDismissalPolicy.shouldRecognizeOutsideTap(...)`
- Produces: 仅内容区域外 tap 关闭的 overlay；Navigation Controller 级遮罩。

- [ ] **Step 1: 扩展失败 contract**

检查 overlay 遵循 `UIGestureRecognizerDelegate`、实现 `shouldReceive touch`、读取 `layer.presentation()?.frame`、outside tap 不取消内容事件，并检查控制器使用 `navigationController?.view ?? view` 作为 host。同时检查弹窗提供退出清理回调，交互式侧滑返回在显示期间禁用并于退出后恢复。

- [ ] **Step 2: 验证 RED**

Run: `bash scripts/check_simulate_fault.sh`

Expected: FAIL，提示缺少 dismissal gesture delegate。

- [ ] **Step 3: 实施最小 UI 修复**

- outside tap 改为 overlay 自身手势。
- delegate 先排除 content 子树触摸，再调用 dismissal policy 检查 model/presentation frame。
- `cancelsTouchesInView`、`delaysTouchesBegan`、`delaysTouchesEnded` 均设为 `false`。
- 控制器用 `navigationController?.view ?? view` 调用 `overlay.present(in:)`。
- 记录交互式侧滑返回的原状态，弹窗显示期间禁用，在 outside tap、权限变更或页面退出导致的 dismiss 完成后统一恢复。

- [ ] **Step 4: 运行针对性验证**

Run:

```bash
bash scripts/check_simulate_fault.sh
bash scripts/check_device_menu_icons.sh
bash scripts/check_device_i18n_titles.sh
swiftc SunSmart/Main/Device/Model/SimulateFaultAction.swift Tests/Device/SimulateFaultModelTests.swift -o /tmp/SimulateFaultModelTests
/tmp/SimulateFaultModelTests
plutil -lint SunSmart.xcodeproj/project.pbxproj SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings
git diff --check
```

Expected: 全部通过。

- [ ] **Step 5: 四品牌构建**

分别运行 SunSmart、Archipelago、`SLG Sync Plus`、SylSmart 的 iPhoneOS Debug `xcodebuild`，均预期 `BUILD SUCCEEDED`。

- [ ] **Step 6: 提交修复和总结**

仅提交本计划列出的实现、测试、契约和本次修复总结，不纳入用户现有未提交内容。
