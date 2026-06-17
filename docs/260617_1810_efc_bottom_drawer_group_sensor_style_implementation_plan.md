# EFC Bottom Drawer GroupSensor Style Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 EFC 设备页底部 `EmerFireAlarmStatusSetView` 的收起/展开 UI 更新为接近 `P.Occupancy sensing with daylight harvesting` group 页 `GroupSensorView` 的 bottom drawer 样式。

**Architecture:** `EmerFireAlarmStatusSetView` 负责 bottom drawer shell：shade、固定高度 content panel、topView header、内部展开动画。`EmerFireAlarmMonitorVC` 只持有外部 height constraint，并通过回调更新高度和 modal 状态；EFC status 数据、header action 和业务状态不变。

**Tech Stack:** UIKit, SnapKit, Swift, Xcode iPhoneOS build.

---

## File Structure

- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/views/EmerFireAlarmStatusSetView.swift`
  - 负责 EFC bottom drawer 的折叠/展开 shell、shade、panel height、header 布局和动画。
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorVC.swift`
  - 负责持有 `statusSetView` height constraint，并把 root view 高度提供给 `statusSetView`。
- Docs: `docs/260617_1800_efc_bottom_drawer_group_sensor_style_plan.md`
  - 已确认的设计方案，不再改动。

## Task 1: 为 StatusSetView 建立 GroupSensorView 风格 shell

- [x] **Step 1: 更新 layout constants**

在 `EmerFireAlarmStatusSetView.Layout` 中替换高度定义：

```swift
static let collapsedHeight = SCRYFrom(40) + kSafeAreaBottomHeight
static let panelHeight = SCRYFrom(352) + kSafeAreaBottomHeight
static let cornerRadius = SCRYFrom(20)
static let headerHeight = SCRYFrom(40)
static let expandedHeaderTopInset = SCRYFrom(8)
```

- [x] **Step 2: 暴露 host callbacks**

在 `headerActionHandler` 附近加入：

```swift
var collapsedHeight: CGFloat { Layout.collapsedHeight }
var expandedOverlayHeightProvider: (() -> CGFloat)?
var heightChangeHandler: ((CGFloat) -> Void)?
var expansionChangedHandler: ((Bool) -> Void)?
```

- [x] **Step 3: 替换内部约束状态**

把旧的：

```swift
private var heightConstraint: Constraint?
```

替换为：

```swift
private var contentTopConstraint: Constraint?
private var topViewTopConstraint: Constraint?
```

- [x] **Step 4: 新增 shadeView 和 topView**

在 `contentView` 之前新增：

```swift
private lazy var shadeView: UIView = {
    let view = UIView()
    view.backgroundColor = .clear
    view.isHidden = true
    view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(shadeViewAction)))
    return view
}()
```

在 `headerButton` 之前新增：

```swift
private lazy var topView: UIView = {
    let view = UIView()
    return view
}()
```

- [x] **Step 5: 调整 setupUI 分层**

在 `setupUI()` 中：

```swift
clipsToBounds = true

addSubview(shadeView)
shadeView.snp.makeConstraints { make in
    make.edges.equalToSuperview()
}

addSubview(contentView)
contentView.snp.makeConstraints { make in
    make.left.right.equalToSuperview()
    contentTopConstraint = make.top.equalToSuperview().constraint
    make.height.equalTo(Layout.panelHeight)
}

contentView.addSubview(topView)
topView.snp.makeConstraints { make in
    make.left.right.equalToSuperview()
    topViewTopConstraint = make.top.equalToSuperview().constraint
    make.height.equalTo(Layout.headerHeight)
}
```

然后把 `headerButton`、`arrowImageView`、`headerActionsStackView`、`titleLabel` 从添加到 `contentView` 改为添加到 `topView`，并让 `headerButton.edges == topView`。

- [x] **Step 6: 调整 expanded content 位置**

把 `legendHeaderView.top` 从 `headerButton.snp.bottom` 改为：

```swift
make.top.equalTo(topView.snp.bottom)
```

`tableView` 继续接在 `legendHeaderView` 下面，bottom 继续避让 safe area。

## Task 2: 实现展开/收起动画

- [x] **Step 1: 避免 didSet 双重更新**

把：

```swift
var isExpanded = false {
    didSet {
        updateExpandedState(animated: true)
    }
}
```

改为：

```swift
private(set) var isExpanded = false
```

- [x] **Step 2: 调整 setExpanded**

替换 `setExpanded(_:, animated:)`：

```swift
func setExpanded(_ expanded: Bool, animated: Bool) {
    guard isExpanded != expanded else {
        updateExpandedState(animated: animated)
        return
    }
    isExpanded = expanded
    updateExpandedState(animated: animated)
}
```

- [x] **Step 3: 新增 shade tap action**

在 action methods 附近加入：

```swift
@objc private func shadeViewAction() {
    setExpanded(false, animated: true)
}
```

- [x] **Step 4: 替换 updateExpandedState**

使用 root height 驱动 panel 位置：

```swift
private func updateExpandedState(animated: Bool) {
    let targetHeight = isExpanded ? expandedHeight() : Layout.collapsedHeight
    let contentTop = isExpanded ? max(0, targetHeight - Layout.panelHeight) : 0
    heightChangeHandler?(targetHeight)
    expansionChangedHandler?(isExpanded)
    contentTopConstraint?.update(offset: contentTop)
    topViewTopConstraint?.update(offset: isExpanded ? Layout.expandedHeaderTopInset : 0)
    shadeView.isHidden = !isExpanded
    legendHeaderView.isHidden = !isExpanded
    tableView.isHidden = !isExpanded
    arrowImageView.image = UIImage(named: isExpanded ? "arrow_down" : "arrow_up")

    let animations = { [weak self] in
        guard let self else { return }
        self.superview?.layoutIfNeeded()
        self.layoutIfNeeded()
    }

    if animated {
        UIView.animate(withDuration: 0.3, animations: animations)
    } else {
        animations()
    }
}

private func expandedHeight() -> CGFloat {
    if let height = expandedOverlayHeightProvider?(), height > Layout.collapsedHeight {
        return height
    }
    return Layout.panelHeight
}
```

## Task 3: 更新 EmerFireAlarmMonitorVC 宿主约束

- [x] **Step 1: 增加 height constraint 属性**

在 `statusSetView` 属性附近加入：

```swift
private var statusSetViewHeightConstraint: Constraint?
```

- [x] **Step 2: 配置 statusSetView callbacks**

在 lazy `statusSetView` 初始化中加入：

```swift
view.expandedOverlayHeightProvider = { [weak self] in
    guard let self else { return view.collapsedHeight }
    return self.view.bounds.height - self.view.safeAreaInsets.top
}
view.heightChangeHandler = { [weak self] height in
    self?.statusSetViewHeightConstraint?.update(offset: height)
}
view.expansionChangedHandler = { [weak self] expanded in
    self?.isModalInPresentation = expanded
}
```

- [x] **Step 3: 设置外部 height constraint**

把 `statusSetView` 约束改为：

```swift
statusSetView.snp.makeConstraints { make in
    make.left.right.bottom.equalToSuperview()
    statusSetViewHeightConstraint = make.height.equalTo(statusSetView.collapsedHeight).constraint
}
```

- [x] **Step 4: 给主操作区增加折叠抽屉避让**

在 `moniView` 约束中加入：

```swift
make.bottom.lessThanOrEqualTo(statusSetView.snp.top).offset(-SCRYFit(20)).priority(.low)
```

## Task 4: 静态 contract 和构建验证

- [x] **Step 1: RED contract 确认现状**

改代码前运行：

```bash
rg -n "shadeView|topViewTopConstraint|expandedOverlayHeightProvider|statusSetViewHeightConstraint" SunSmart/Main/Device/Device1.5/FireAlarm/views/EmerFireAlarmStatusSetView.swift SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorVC.swift
```

Expected before implementation: no output.

- [x] **Step 2: GREEN contract**

改代码后运行同一命令。

Expected after implementation: output includes all four terms.

- [x] **Step 3: Check whitespace**

Run:

```bash
git diff --check
```

Expected: no output.

- [x] **Step 4: iPhoneOS build**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`.
