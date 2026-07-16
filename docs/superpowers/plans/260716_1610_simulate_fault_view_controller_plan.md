# Simulate Fault View Controller Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Project instructions require Inline Execution and prohibit subagents unless the user explicitly authorizes them. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 light 设备页内的 Simulate Fault UIView overlay 改为系统 `.automatic` modal View Controller，并将按钮 action 收口到新 VC 内部。

**Architecture:** `DeviceLightViewController` 仅保留权限校验和 `present` 入口；`SimulateFaultViewController` 承载现有 header、Scroll View 和 section，使用 UIKit `.automatic` presentation 提供系统半透明背景与下滑关闭。删除 overlay outside-tap policy、自定义 dismiss 动画和对底层 interactive-pop 的状态操作。

**Tech Stack:** Swift、UIKit、SnapKit、shell contract、`swiftc`、`xcodebuild`。

## Global Constraints

- 范围仅限 light 设备页的 Simulate Fault，其他设备页和 popup 保持现状。
- `modalPresentationStyle` 必须为 `.automatic`，不自定义 detent、dimming、outside tap 或 pan gesture。
- 接受 UIKit 决定宽度、高度、圆角、半透明背景和交互式关闭行为。
- 按钮 action 在 `SimulateFaultViewController` 内部处理，不回传给其他控制器。
- 按钮点击不关闭弹窗，不保留选中状态，不发送 Mesh 命令。
- 固定内容、图标、国际化和 effective edit capability 权限规则保持现状。
- 不修改 SDK 或增加依赖。
- 校验使用 iPhoneOS Debug，不使用 Simulator。
- 不纳入用户现有 `AGENTS.md` 和无关文档改动。

---

## File Structure

- Create: `SunSmart/Main/Device/View/SimulateFaultViewController.swift` — 系统 modal 容器、内容布局、权限监听和内部 action handler。
- Delete: `SunSmart/Main/Device/View/SimulateFaultOverlayView.swift` — 移除 UIView overlay、外部点击和自定义 dismiss。
- Modify: `SunSmart/Main/Device/Controller/DeviceLightViewController.swift` — 从 overlay 生命周期改为标准 modal presentation。
- Modify: `SunSmart/Main/Device/Model/SimulateFaultAction.swift` — 删除不再需要的 outside-tap dismissal policy。
- Modify: `SunSmart.xcodeproj/project.pbxproj` — 将四个 target 的 overlay 文件引用更名为 View Controller。
- Modify: `Tests/Device/SimulateFaultModelTests.swift` — 删除 outside-tap policy 测试，保留 action/grid 纯逻辑回归。
- Modify: `scripts/check_simulate_fault.sh` — 将 overlay 契约更换为 `.automatic` View Controller、内部 action 和无手势管理契约。
- Create: `docs/260716_1610_simulate_fault_view_controller_summary.md` — 实施与验证总结。

---

### Task 1: 建立 View Controller 转换的失败契约

**Files:**
- Modify: `scripts/check_simulate_fault.sh`

**Interfaces:**
- Consumes: 现有 `SimulateFaultAction`、`SimulateFaultSectionView` 和 light 菜单入口。
- Produces: 一组在旧 overlay 实现上必然失败、在最终 VC 实现上通过的静态契约。

- [ ] **Step 1: 将 overlay 契约改为 View Controller 契约**

将脚本开头的 overlay 检查替换为以下内容：

```bash
section_file="SunSmart/Main/Device/View/SimulateFaultSectionView.swift"
controller_file="SunSmart/Main/Device/View/SimulateFaultViewController.swift"
legacy_overlay_file="SunSmart/Main/Device/View/SimulateFaultOverlayView.swift"

test -f "$controller_file" || fail "SimulateFaultViewController.swift is missing"
test ! -f "$legacy_overlay_file" || fail "legacy SimulateFaultOverlayView.swift must be removed"
grep -Fq 'final class SimulateFaultViewController: UIViewController' "$controller_file" \
  || fail "Simulate Fault must be implemented as a view controller"
grep -Fq 'modalPresentationStyle = .automatic' "$controller_file" \
  || fail "Simulate Fault must use automatic system presentation"
grep -Fq 'private func handleAction(_ action: SimulateFaultAction)' "$controller_file" \
  || fail "Simulate Fault actions must be handled inside the new controller"
grep -Fq 'self?.handleAction(action)' "$controller_file" \
  || fail "section actions must terminate inside the new controller"
grep -Fq 'UIScrollView' "$controller_file" \
  || fail "system sheet content must remain scrollable"
grep -Fq 'spacePermissionChangedNotificaitonName' "$controller_file" \
  || fail "the controller must observe effective permission changes"
grep -Eq 'isModalInPresentation[[:space:]]*=[[:space:]]*true|sheetPresentationController|\.detents[[:space:]]*=' "$controller_file" \
  && fail "automatic presentation must keep the system dismissal policy and sizing"
grep -Eq 'UITapGestureRecognizer|UIPanGestureRecognizer|UIGestureRecognizerDelegate' "$controller_file" \
  && fail "automatic presentation must not install custom dismissal gestures"
grep -Eq 'MeshAPI|sendMessage|NordicSigMeshSDK' "$controller_file" \
  && fail "Simulate Fault must not send device commands"
```

保留 section、国际化、asset 和菜单顺序检查，将 light controller 检查替换为：

```bash
grep -Fq 'let controller = SimulateFaultViewController(space: space)' "$light_file" \
  || fail "Light controller must create the automatic Simulate Fault controller"
grep -Fq 'present(controller, animated: true)' "$light_file" \
  || fail "Light controller must use standard modal presentation"
grep -Eq 'simulateFaultOverlayView|simulateFaultInteractivePop|restoreSimulateFaultInteractivePopGesture|handleSimulateFaultAction' "$light_file" \
  && fail "Light controller must not retain legacy overlay lifecycle code"
grep -Fq 'SimulateFaultViewController.swift' SunSmart.xcodeproj/project.pbxproj \
  || fail "all app targets must reference SimulateFaultViewController.swift"
grep -Fq 'SimulateFaultOverlayView.swift' SunSmart.xcodeproj/project.pbxproj \
  && fail "project must not reference the legacy overlay file"
```

- [ ] **Step 2: 运行契约并验证 RED**

Run: `bash scripts/check_simulate_fault.sh`

Expected: FAIL with `SimulateFaultViewController.swift is missing`.

---

### Task 2: 实现 `.automatic` Simulate Fault View Controller

**Files:**
- Create: `SunSmart/Main/Device/View/SimulateFaultViewController.swift`
- Delete: `SunSmart/Main/Device/View/SimulateFaultOverlayView.swift`
- Modify: `SunSmart/Main/Device/Model/SimulateFaultAction.swift`
- Modify: `Tests/Device/SimulateFaultModelTests.swift`
- Modify: `SunSmart.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `SimulateFaultSectionView.init(configuration:)`、`SimulateFaultSectionView.onAction: ((SimulateFaultAction) -> Void)?`、`SpaceData.deviceOperates` 和 `spacePermissionChangedNotificaitonName`。
- Produces: `SimulateFaultViewController.init(space: SpaceData)`；内部 `handleAction(_ action: SimulateFaultAction)` 作为 action 终点。

- [ ] **Step 1: 创建 View Controller 骨架和系统 presentation 配置**

新建 `SimulateFaultViewController.swift`，写入：

```swift
import UIKit
import SnapKit

final class SimulateFaultViewController: UIViewController {
    private let space: SpaceData
    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private let headerView = UIView()
    private let headerImageView = UIImageView(image: UIImage(named: "black_debug"))
    private let headerLabel = UILabel()

    init(space: SpaceData) {
        self.space = space
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .automatic
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(spacePermissionDidChange),
            name: .init(spacePermissionChangedNotificaitonName),
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func spacePermissionDidChange() {
        guard !space.deviceOperates.contains(.edit) else { return }
        dismiss(animated: true)
    }
}
```

- [ ] **Step 2: 迁移 header、Scroll View 和 section 布局**

将以下方法插入新 VC 的最后一个类结束大括号之前：

```swift
private func setupUI() {
    view.backgroundColor = .white

    scrollView.alwaysBounceVertical = false
    scrollView.showsHorizontalScrollIndicator = false
    scrollView.contentInsetAdjustmentBehavior = .automatic

    stackView.axis = .vertical
    stackView.spacing = 11

    headerImageView.contentMode = .scaleAspectFit
    headerLabel.text = "simulate_fault".localizedString
    headerLabel.textColor = UIColor(red: 27 / 255, green: 20 / 255, blue: 37 / 255, alpha: 1)
    headerLabel.font = .systemFont(ofSize: 16, weight: .medium)

    view.addSubview(scrollView)
    scrollView.addSubview(stackView)
    stackView.addArrangedSubview(headerView)
    headerView.addSubview(headerImageView)
    headerView.addSubview(headerLabel)

    makeSections().forEach { section in
        section.onAction = { [weak self] action in
            self?.handleAction(action)
        }
        stackView.addArrangedSubview(section)
    }

    scrollView.snp.makeConstraints { make in
        make.edges.equalTo(view.safeAreaLayoutGuide)
    }
    stackView.snp.makeConstraints { make in
        make.top.equalTo(scrollView.contentLayoutGuide).offset(8)
        make.left.equalTo(scrollView.contentLayoutGuide).offset(16)
        make.right.equalTo(scrollView.contentLayoutGuide).offset(-16)
        make.bottom.equalTo(scrollView.contentLayoutGuide).offset(-12)
        make.width.equalTo(scrollView.frameLayoutGuide).offset(-32)
    }
    headerView.snp.makeConstraints { make in
        make.height.equalTo(40)
    }
    headerImageView.snp.makeConstraints { make in
        make.left.equalToSuperview().offset(4)
        make.centerY.equalToSuperview()
        make.width.height.equalTo(24)
    }
    headerLabel.snp.makeConstraints { make in
        make.left.equalTo(headerImageView.snp.right).offset(8)
        make.right.equalToSuperview().offset(-4)
        make.centerY.equalToSuperview()
    }
}

private func handleAction(_ action: SimulateFaultAction) {
    _ = action
}
```

- [ ] **Step 3: 迁移固定 section 配置**

将旧 overlay 的 `makeSections()` 移入新 VC 的类作用域内，方法完整内容为：

```swift
private func makeSections() -> [SimulateFaultSectionView] {
    let motion = SimulateFaultSectionView(configuration: .init(
        titleKey: "simulate_fault_motion_sensor",
        tagKey: "simulate_fault_minor_3",
        tagStyle: .init(
            textColor: UIColor(red: 212 / 255, green: 138 / 255, blue: 0, alpha: 1),
            backgroundColor: UIColor(red: 1, green: 247 / 255, blue: 226 / 255, alpha: 1)
        ),
        items: [
            .init(titleKey: "simulate_fault_normal", action: .motionSensor(.normal)),
            .init(titleKey: "simulate_fault_fault", action: .motionSensor(.fault))
        ]
    ))
    let photocell = SimulateFaultSectionView(configuration: .init(
        titleKey: "simulate_fault_photocell_sensor",
        tagKey: "simulate_fault_major_2",
        tagStyle: .init(
            textColor: UIColor(red: 224 / 255, green: 85 / 255, blue: 66 / 255, alpha: 1),
            backgroundColor: UIColor(red: 1, green: 237 / 255, blue: 234 / 255, alpha: 1)
        ),
        items: [
            .init(titleKey: "simulate_fault_normal", action: .photocellSensor(.normal)),
            .init(titleKey: "simulate_fault_fault", action: .photocellSensor(.fault))
        ]
    ))
    let light = SimulateFaultSectionView(configuration: .init(
        titleKey: "simulate_fault_light_status",
        tagKey: "simulate_fault_critical_1",
        tagStyle: .init(
            textColor: UIColor(red: 189 / 255, green: 53 / 255, blue: 47 / 255, alpha: 1),
            backgroundColor: UIColor(red: 1, green: 228 / 255, blue: 226 / 255, alpha: 1)
        ),
        items: [
            .init(titleKey: "simulate_fault_normal", action: .lightStatus(.normal)),
            .init(titleKey: "simulate_fault_dim", action: .lightStatus(.dim)),
            .init(titleKey: "simulate_fault_flicker", action: .lightStatus(.flicker)),
            .init(titleKey: "simulate_fault_dim_flicker", action: .lightStatus(.dimFlicker)),
            .init(titleKey: "simulate_fault_off", action: .lightStatus(.off))
        ]
    ))
    return [motion, photocell, light]
}
```

- [ ] **Step 4: 删除 overlay 专用 policy 和测试**

从 `SimulateFaultAction.swift` 删除 `import CoreGraphics` 和整个 `SimulateFaultDismissalPolicy`。

从 `SimulateFaultModelTests.swift` 删除 `import CoreGraphics` 以及 `contentFrame` / `presentationFrame` 的三个 dismissal policy 断言；保留 9 个 action 和 grid metrics 的全部断言。

- [ ] **Step 5: 将工程文件引用从 Overlay 更名为 View Controller**

在 `SunSmart.xcodeproj/project.pbxproj` 中将以下两类文本全部替换，保留现有 UUID 和四 target membership：

```text
SimulateFaultOverlayView.swift in Sources
SimulateFaultOverlayView.swift
```

替换为：

```text
SimulateFaultViewController.swift in Sources
SimulateFaultViewController.swift
```

使用 `apply_patch` 删除 `SimulateFaultOverlayView.swift`，不保留 compatibility typealias。

- [ ] **Step 6: 运行纯逻辑测试**

Run:

```bash
swiftc -module-cache-path /tmp/SimulateFaultModuleCache SunSmart/Main/Device/Model/SimulateFaultAction.swift Tests/Device/SimulateFaultModelTests.swift -o /tmp/SimulateFaultModelTests
/tmp/SimulateFaultModelTests
```

Expected: `SimulateFaultModelTests passed`.

---

### Task 3: 将 light 菜单入口改为标准 modal presentation

**Files:**
- Modify: `SunSmart/Main/Device/Controller/DeviceLightViewController.swift`

**Interfaces:**
- Consumes: `SimulateFaultViewController.init(space: SpaceData)`。
- Produces: `showSimulateFault()` 仅执行 effective edit capability 校验、防重入校验和标准 modal presentation。

- [ ] **Step 1: 删除旧 overlay 状态**

删除以下属性：

```swift
private weak var simulateFaultOverlayView: SimulateFaultOverlayView?
private weak var simulateFaultInteractivePopGestureRecognizer: UIGestureRecognizer?
private var simulateFaultInteractivePopWasEnabled: Bool?
```

从 `viewWillDisappear` 删除：

```swift
simulateFaultOverlayView?.dismiss(animated: false)
```

- [ ] **Step 2: 用标准 present 替换 `showSimulateFault()`**

将方法替换为：

```swift
private func showSimulateFault() {
    guard space.deviceOperates.contains(.edit) else { return }
    guard presentedViewController == nil else { return }

    let controller = SimulateFaultViewController(space: space)
    present(controller, animated: true)
}
```

- [ ] **Step 3: 删除 action 回传和 overlay 权限观察者**

删除 `restoreSimulateFaultInteractivePopGesture()` 和 `handleSimulateFaultAction(_:)` 两个完整方法。

当前 `DeviceLightViewController` 中的 `spacePermissionChangedNotificaitonName` observer 与 `spacePermissionDidChange()` 仅服务于 overlay。从 `viewDidLoad` 删除以下 observer：

```swift
NotificationCenter.default.addObserver(
    self,
    selector: #selector(spacePermissionDidChange),
    name: .init(spacePermissionChangedNotificaitonName),
    object: nil
)
```

同时删除整个 `spacePermissionDidChange()` 方法。新 `SimulateFaultViewController` 已独立监听同一通知并处理 dismiss。

- [ ] **Step 4: 运行契约并验证 GREEN**

Run:

```bash
bash scripts/check_simulate_fault.sh
bash scripts/check_device_menu_icons.sh
bash scripts/check_device_i18n_titles.sh
```

Expected:

```text
PASS: Simulate Fault contract is present.
PASS: device menu icons match expected assets.
PASS: targeted device i18n titles are localized.
```

- [ ] **Step 5: 验证工程和文本文件结构**

Run:

```bash
plutil -lint SunSmart.xcodeproj/project.pbxproj SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings
git diff --check
```

Expected: 三个 `plutil` 输入均输出 `OK`，`git diff --check` exit 0 且无输出。

- [ ] **Step 6: 运行 SunSmart iPhoneOS Debug 构建作为首个编译门禁**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: 提交 View Controller 改造**

```bash
git add SunSmart/Main/Device/View/SimulateFaultViewController.swift SunSmart/Main/Device/View/SimulateFaultOverlayView.swift SunSmart/Main/Device/Controller/DeviceLightViewController.swift SunSmart/Main/Device/Model/SimulateFaultAction.swift Tests/Device/SimulateFaultModelTests.swift scripts/check_simulate_fault.sh SunSmart.xcodeproj/project.pbxproj
git commit -m "refactor: present simulate fault as view controller"
```

Commit 前用 `git status --short` 确认未 stage `AGENTS.md`、`docs/260716_0950_site_space_network_key_analysis.md` 和 `docs/260716_1112_energy_data_mesh_protocol_analysis.md`。

---

### Task 4: 四 target 验证与总结

**Files:**
- Create: `docs/260716_1610_simulate_fault_view_controller_summary.md`

**Interfaces:**
- Consumes: Task 2-3 完成的 View Controller 实现。
- Produces: 四品牌构建证据、手势/布局人工验收清单和最终实施总结。

- [ ] **Step 1: 重新运行全部定向验证**

Run:

```bash
bash scripts/check_simulate_fault.sh
bash scripts/check_device_menu_icons.sh
bash scripts/check_device_i18n_titles.sh
swiftc -module-cache-path /tmp/SimulateFaultModuleCache SunSmart/Main/Device/Model/SimulateFaultAction.swift Tests/Device/SimulateFaultModelTests.swift -o /tmp/SimulateFaultModelTests
/tmp/SimulateFaultModelTests
plutil -lint SunSmart.xcodeproj/project.pbxproj SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings
git diff --check
```

Expected: 三个 shell contract PASS，model tests 输出 `SimulateFaultModelTests passed`，`plutil` 全部 `OK`，diff check 无输出。

- [ ] **Step 2: 构建 Archipelago**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme Archipelago -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: 构建 SLG Sync Plus**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme 'SLG Sync Plus' -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: 构建 SylSmart**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SylSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: 编写实施总结**

创建 `docs/260716_1610_simulate_fault_view_controller_summary.md`，必须包含：

```markdown
# Simulate Fault View Controller 改造总结

## 结果
- UIView overlay 已替换为 `.automatic` modal View Controller。
- 系统管理半透明背景、尺寸和下滑关闭。
- action 在新 VC 内部终止，不回传、不发命令。

## 验证
- 列出实际 contract、model test、plutil、diff check 结果。
- 列出 SunSmart、Archipelago、SLG Sync Plus、SylSmart 的 iPhoneOS Debug 构建结果。

## 人工验收
- 从 modal 和 push 两类 Device Light 入口展示。
- 验证系统半透明背景和下滑关闭。
- 验证内容滚动、item 点击不关闭且不保留选中状态。
- 验证关闭后底层 push/modal 手势恢复原生行为。
```

- [ ] **Step 6: 提交验证总结**

```bash
git add docs/260716_1610_simulate_fault_view_controller_summary.md
git commit -m "docs: summarize simulate fault view controller"
```

仅添加本次新总结文档，不添加其他 untracked 文档。

---

## Final Manual Acceptance Checklist

- [ ] Owner/editor 在 light 设备菜单最后一栏看到 `Simulate Fault`，其他权限不显示。
- [ ] 点击后使用当前系统 `.automatic` modal/sheet 样式展示。
- [ ] 弹窗外背景为系统半透明 dimming，不要求精确等于原黑色 `0.3 alpha`。
- [ ] 下滑可交互式关闭；不要求点击弹窗外关闭。
- [ ] Motion Sensor、Photocell Sensor、Light Status 内容和 tag 文案正确。
- [ ] iPad 等宽屏上，系统分配宽度足够时 Light Status 为一排。
- [ ] 内容超过 sheet 高度时可滚动访问全部 item。
- [ ] 点击 item 不关闭、不保留选中状态、不触发 Mesh 命令。
- [ ] Simulate Fault 关闭后，底层 Device Light 的 push 侧滑或 modal 下滑保持原生行为。
