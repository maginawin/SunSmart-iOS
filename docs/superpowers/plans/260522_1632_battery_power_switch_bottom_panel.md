# Battery Power Switch Bottom Panel UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 按 Figma 优化 Battery Power Switch 设备页底部 Settings 面板的收起/展开 UI。

**Architecture:** 改动集中在 `PJEightKeySwitchMonitorStatusSetView`，保留现有 `configure(state:)`、`enableChanged`、`groupLinkAction` 数据流。真实 Enable 开关继续由 header `UISwitch` 触发现有下发流程；展开态 `all status tag` 改成不可交互图例。组列表放入独立滚动区域，sheet 高度固定。

**Tech Stack:** Swift、UIKit、SnapKit、现有 `RGB` / `SCRXFrom` / `SCRYFrom` / `Bar_Color` 样式工具。

---

## File Structure

- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchMonitorStatusSetView.swift`
  - 负责底部面板布局、展开收起、header Enable 交互、Group link 点击。
  - 新增私有 `MiniSwitchLegendView`，绘制 30x20 的开关图例。
  - 新增私有图标绘制方法，生成 linked/unlinked 图标，避免依赖临时 Figma asset URL。
  - 将组列表改成 `UIScrollView + UIStackView`。
- No change: `PJEightKeySwitchMonitorVC.swift`
  - 现有 `bottomView.configure(state:)`、`enableChanged`、`groupLinkAction` 已满足需求。
- No change: localization files
  - 现有英文和中文 key 已存在，文案符合需求。

---

### Task 1: Add Bottom Panel Visual Helpers

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchMonitorStatusSetView.swift`

- [ ] **Step 1: Add layout constants and color helpers**

在 `Layout` enum 中替换现有常量。保留 collapsed 高度，展开高度改为 Figma 确认值。

```swift
private enum Layout {
    static let collapsedHeight = SCRYFrom(40) + kSafeAreaBottomHeight
    static let expandedHeight = SCRYFrom(330) + kSafeAreaBottomHeight
    static let headerHeight = SCRYFrom(40)
    static let legendHeight = SCRYFrom(32)
    static let miniSwitchSize = CGSize(width: SCRXFrom(30), height: SCRYFrom(20))
}

private enum Palette {
    static let primaryText = RGB(30, 35, 41)
    static let titleText = RGB(39, 37, 54)
    static let legendText = RGB(64, 79, 102)
    static let secondaryText = RGB(100, 116, 139)
    static let auxiliary = RGB(148, 163, 184)
    static let iconDark = RGB(20, 46, 79)
    static let tagBackground = RGB(250, 250, 250)
    static let switchDisabledTrack = RGB(238, 238, 238)
    static let switchDisabledKnob = UIColor.white
}
```

- [ ] **Step 2: Add the mini switch legend view**

在文件底部新增私有视图。该视图只负责绘制图例，不响应触摸。

```swift
private final class PJEightKeySwitchMiniSwitchLegendView: UIView {

    var isOn = true {
        didSet { setNeedsLayout() }
    }

    private let trackView = UIView()
    private let knobView = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        addSubview(trackView)
        addSubview(knobView)
        trackView.layer.masksToBounds = true
        knobView.backgroundColor = .white
        knobView.layer.shadowColor = UIColor.black.cgColor
        knobView.layer.shadowOpacity = 0.12
        knobView.layer.shadowRadius = 2
        knobView.layer.shadowOffset = CGSize(width: 0, height: 1)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        trackView.frame = bounds.insetBy(dx: SCRXFrom(2.5), dy: SCRYFrom(2.5))
        trackView.layer.cornerRadius = trackView.bounds.height / 2
        trackView.backgroundColor = isOn ? Bar_Color : Palette.switchDisabledTrack

        let knobSide = SCRXFrom(16)
        let knobX = isOn ? bounds.width - SCRXFrom(2.5) - knobSide : SCRXFrom(2.5)
        knobView.frame = CGRect(x: knobX, y: (bounds.height - knobSide) / 2, width: knobSide, height: knobSide)
        knobView.layer.cornerRadius = knobSide / 2
        knobView.backgroundColor = isOn ? .white : Palette.switchDisabledKnob
    }
}
```

- [ ] **Step 3: Add icon image factory helpers**

在 `PJEightKeySwitchMonitorStatusSetView` 的 private extension 或 class 内新增方法。目标是用代码绘制 16pt 图标，保持颜色可控，不依赖 asset 是否存在。

```swift
private func linkIconImage(linked: Bool, color: UIColor) -> UIImage {
    let size = CGSize(width: SCRXFrom(16), height: SCRXFrom(16))
    return UIGraphicsImageRenderer(size: size).image { context in
        let cg = context.cgContext
        cg.setStrokeColor(color.cgColor)
        cg.setLineWidth(SCRXFrom(1.2))
        cg.setLineCap(.round)
        cg.setLineJoin(.round)

        if linked {
            drawChainLink(in: cg, size: size, offset: CGPoint(x: -SCRXFrom(2), y: SCRXFrom(2)))
            drawChainLink(in: cg, size: size, offset: CGPoint(x: SCRXFrom(2), y: -SCRXFrom(2)))
        } else {
            drawChainLink(in: cg, size: size, offset: CGPoint(x: -SCRXFrom(2), y: SCRXFrom(2)))
            drawChainLink(in: cg, size: size, offset: CGPoint(x: SCRXFrom(2), y: -SCRXFrom(2)))
            cg.move(to: CGPoint(x: SCRXFrom(4), y: SCRXFrom(12)))
            cg.addLine(to: CGPoint(x: SCRXFrom(12), y: SCRXFrom(4)))
            cg.strokePath()
        }
    }.withRenderingMode(.alwaysOriginal)
}

private func drawChainLink(in context: CGContext, size: CGSize, offset: CGPoint) {
    context.saveGState()
    context.translateBy(x: size.width / 2 + offset.x, y: size.height / 2 + offset.y)
    context.rotate(by: -.pi / 4)
    let rect = CGRect(x: -SCRXFrom(5), y: -SCRXFrom(2), width: SCRXFrom(10), height: SCRXFrom(4))
    context.addPath(UIBezierPath(roundedRect: rect, cornerRadius: SCRXFrom(2)).cgPath)
    context.strokePath()
    context.restoreGState()
}
```

- [ ] **Step 4: Commit helper-only changes**

Run:

```bash
git diff --check
git add SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchMonitorStatusSetView.swift
git commit -m "feat: add battery switch bottom panel helpers"
```

Expected:

- `git diff --check` has no output.
- Commit succeeds.

---

### Task 2: Rebuild Expanded Panel Layout

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchMonitorStatusSetView.swift`

- [ ] **Step 1: Replace expandable subview properties**

替换展开态相关属性。移除 `innerEnableSwitch`，新增两个 mini switch 图例和滚动容器。

```swift
private let expandedContainerView = UIView()
private let statusCardView = UIView()
private let linkedIconView = UIImageView()
private let linkedLabel = UILabel(text: "neightkeyswitches_linked".localizedString, textColor: Palette.legendText, fontSize: 12, fontWeight: .light, fit: false)
private let unlinkedIconView = UIImageView()
private let unlinkedLabel = UILabel(text: "neightkeyswitches_unlinked".localizedString, textColor: Palette.legendText, fontSize: 12, fontWeight: .light, fit: false)
private let enableLegendSwitch = PJEightKeySwitchMiniSwitchLegendView()
private let enableLegendLabel = UILabel(text: "enable".localizedString, textColor: Palette.legendText, fontSize: 12, fontWeight: .light, fit: false)
private let disabledLegendSwitch = PJEightKeySwitchMiniSwitchLegendView()
private let disabledLegendLabel = UILabel(text: "disabled".localizedString, textColor: Palette.legendText, fontSize: 12, fontWeight: .light, fit: false)
private let groupsTitleLabel = UILabel(text: "neightkeyswitches_groups_it_controls".localizedString, textColor: Palette.primaryText, fontSize: 15, fontWeight: .light, fit: false)
private let emptyLabel = UILabel(text: "neightkeyswitches_group_empty_tip".localizedString, textColor: Palette.secondaryText, fontSize: 13, fontWeight: .light)
private let groupsScrollView = UIScrollView()
private let groupsStackView = UIStackView()
```

- [ ] **Step 2: Update sheet container style**

在 `setupUI()` 中配置 `contentView` 的阴影和圆角。不要改变外部约束接口。

```swift
contentView.backgroundColor = .white
contentView.layer.cornerRadius = SCRYFrom(20)
contentView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
contentView.layer.shadowColor = UIColor.black.cgColor
contentView.layer.shadowOpacity = 0.07
contentView.layer.shadowRadius = SCRYFrom(6)
contentView.layer.shadowOffset = CGSize(width: 0, height: -SCRYFrom(2))
```

- [ ] **Step 3: Update header styling and constraints**

保持 header 真实 `enableSwitch` 可操作，设置主题色。Group link icon 容器保持 20pt，图标由 `configure(state:)` 设置。

```swift
titleLabel.textColor = Palette.titleText
groupLinkTitleLabel.textColor = Palette.primaryText
enableTitleLabel.textColor = Palette.primaryText
enableSwitch.onTintColor = Bar_Color
enableSwitch.tintColor = RGB(207, 207, 207)
enableSwitch.thumbTintColor = .white
```

`groupLinkButton` 约束调整为 20pt 容器：

```swift
groupLinkButton.snp.makeConstraints { make in
    make.centerY.equalTo(headerButton)
    make.right.equalTo(enableTitleLabel.snp.left).offset(-SCRXFrom(16))
    make.width.height.equalTo(SCRXFrom(20))
}
```

- [ ] **Step 4: Rebuild all status tag layout**

将 `statusCardView` 改为 Figma 尺寸和四个固定图例项。使用 horizontal stack 可以减少约束冲突。

```swift
statusCardView.backgroundColor = Palette.tagBackground
statusCardView.layer.cornerRadius = SCRYFrom(10)

let legendStackView = UIStackView(arrangedSubviews: [
    makeLegendItem(iconView: linkedIconView, label: linkedLabel),
    makeLegendItem(iconView: unlinkedIconView, label: unlinkedLabel),
    makeSwitchLegendItem(switchView: enableLegendSwitch, label: enableLegendLabel),
    makeSwitchLegendItem(switchView: disabledLegendSwitch, label: disabledLegendLabel)
])
legendStackView.axis = .horizontal
legendStackView.alignment = .center
legendStackView.spacing = SCRXFrom(16)
statusCardView.addSubview(legendStackView)
legendStackView.snp.makeConstraints { make in
    make.center.equalToSuperview()
}

statusCardView.snp.makeConstraints { make in
    make.top.equalToSuperview().offset(SCRYFrom(4))
    make.left.equalToSuperview().offset(SCRXFrom(20))
    make.right.equalToSuperview().offset(-SCRXFrom(20))
    make.height.equalTo(Layout.legendHeight)
}
```

新增两个 helper：

```swift
private func makeLegendItem(iconView: UIImageView, label: UILabel) -> UIStackView {
    iconView.contentMode = .scaleAspectFit
    iconView.snp.makeConstraints { make in
        make.width.height.equalTo(SCRXFrom(20))
    }
    let stackView = UIStackView(arrangedSubviews: [iconView, label])
    stackView.axis = .horizontal
    stackView.alignment = .center
    stackView.spacing = SCRXFrom(4)
    return stackView
}

private func makeSwitchLegendItem(switchView: PJEightKeySwitchMiniSwitchLegendView, label: UILabel) -> UIStackView {
    switchView.snp.makeConstraints { make in
        make.width.equalTo(Layout.miniSwitchSize.width)
        make.height.equalTo(Layout.miniSwitchSize.height)
    }
    let stackView = UIStackView(arrangedSubviews: [switchView, label])
    stackView.axis = .horizontal
    stackView.alignment = .center
    stackView.spacing = SCRXFrom(0)
    return stackView
}
```

- [ ] **Step 5: Add scrollable group list area**

把组名列表放入 `groupsScrollView`，让滚动只发生在列表区域。

```swift
expandedContainerView.addSubview(groupsTitleLabel)
groupsTitleLabel.snp.makeConstraints { make in
    make.top.equalTo(statusCardView.snp.bottom).offset(SCRYFrom(16))
    make.left.equalTo(statusCardView).offset(SCRXFrom(8))
    make.right.equalTo(statusCardView).offset(-SCRXFrom(8))
}

emptyLabel.numberOfLines = 0
expandedContainerView.addSubview(emptyLabel)
emptyLabel.snp.makeConstraints { make in
    make.top.equalTo(groupsTitleLabel.snp.bottom).offset(SCRYFrom(16))
    make.left.equalTo(groupsTitleLabel)
    make.right.equalTo(groupsTitleLabel)
}

groupsScrollView.showsVerticalScrollIndicator = false
groupsScrollView.alwaysBounceVertical = false
expandedContainerView.addSubview(groupsScrollView)
groupsScrollView.snp.makeConstraints { make in
    make.top.equalTo(groupsTitleLabel.snp.bottom).offset(SCRYFrom(16))
    make.left.equalTo(groupsTitleLabel)
    make.right.equalTo(groupsTitleLabel)
    make.bottom.equalToSuperview().offset(-SCRYFrom(8))
}

groupsStackView.axis = .vertical
groupsStackView.alignment = .fill
groupsStackView.spacing = SCRYFrom(10)
groupsScrollView.addSubview(groupsStackView)
groupsStackView.snp.makeConstraints { make in
    make.edges.equalTo(groupsScrollView.contentLayoutGuide)
    make.width.equalTo(groupsScrollView.frameLayoutGuide)
}
```

- [ ] **Step 6: Commit layout rebuild**

Run:

```bash
git diff --check
git add SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchMonitorStatusSetView.swift
git commit -m "feat: rebuild battery switch bottom panel layout"
```

Expected:

- `git diff --check` has no output.
- Commit succeeds.

---

### Task 3: Wire State Rendering

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchMonitorStatusSetView.swift`

- [ ] **Step 1: Update `configure(state:)` for header and legend**

真实 header switch 根据 state 更新；header Group link icon 根据 linked/unlinked 切换。`all status tag` 固定为图例，不根据 state 改变颜色或交互。

```swift
func configure(state: State) {
    enableSwitch.setOn(state.isEnabled, animated: false)
    enableSwitch.isEnabled = !state.isPending

    let headerIcon = linkIconImage(
        linked: state.isGroupLinked,
        color: state.isGroupLinked ? Palette.iconDark : Palette.auxiliary
    )
    groupLinkButton.setImage(headerIcon, for: .normal)

    linkedIconView.image = linkIconImage(linked: true, color: Palette.iconDark)
    unlinkedIconView.image = linkIconImage(linked: false, color: Palette.auxiliary)
    enableLegendSwitch.isOn = true
    disabledLegendSwitch.isOn = false

    renderGroupNames(state.groupNames)
}
```

- [ ] **Step 2: Replace group rendering with a dedicated method**

新增方法，保证组名单行截断，空状态隐藏 scroll view。

```swift
private func renderGroupNames(_ names: [String]) {
    groupsStackView.arrangedSubviews.forEach {
        groupsStackView.removeArrangedSubview($0)
        $0.removeFromSuperview()
    }

    if names.isEmpty {
        emptyLabel.isHidden = false
        groupsScrollView.isHidden = true
        return
    }

    emptyLabel.isHidden = true
    groupsScrollView.isHidden = false
    names.forEach { name in
        let label = UILabel(text: name, textColor: Palette.secondaryText, fontSize: 13, fontWeight: .light, fit: false)
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        groupsStackView.addArrangedSubview(label)
    }
}
```

- [ ] **Step 3: Keep only header switch as an event source**

确认文件中只有 header `enableSwitch` 调用 `addTarget`。删除 `innerEnableSwitch.addTarget` 相关代码。

Run:

```bash
rg -n "innerEnableSwitch|enableLegendSwitch.addTarget|disabledLegendSwitch.addTarget" SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchMonitorStatusSetView.swift
```

Expected:

- No output.

- [ ] **Step 4: Verify static requirements**

Run:

```bash
rg -n "expandedHeight = SCRYFrom\\(330\\)|groupsScrollView|PJEightKeySwitchMiniSwitchLegendView|enableSwitch.onTintColor = Bar_Color|setImage\\(headerIcon" SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchMonitorStatusSetView.swift
```

Expected:

- Output includes all five implementation markers.

- [ ] **Step 5: Commit state rendering**

Run:

```bash
git diff --check
git add SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchMonitorStatusSetView.swift
git commit -m "fix: render battery switch bottom panel states"
```

Expected:

- `git diff --check` has no output.
- Commit succeeds.

---

### Task 4: Build and Manual Verification

**Files:**
- Verify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchMonitorStatusSetView.swift`

- [ ] **Step 1: Run iPhoneOS build**

Run exactly:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected:

- Build exits 0.
- Output includes `** BUILD SUCCEEDED **`.

- [ ] **Step 2: Confirm no unrelated working tree changes**

Run:

```bash
git status --short
```

Expected:

- Only intended files are clean after commits.

- [ ] **Step 3: Manual UI checklist**

Use simulator or device when available. Verify these states:

- 收起态，已绑定目标组：Group link 显示 linked icon，Enable switch 使用 `Bar_Color`。
- 收起态，未绑定目标组：Group link 显示 unlinked icon，颜色为辅助色。
- 收起态，pending 下发时：Enable switch 不可操作。
- 展开态，已绑定目标组：sheet 高度固定，`all status tag` 展示 Linked、Unlinked、Enable、Disabled 四个图例，组名列表显示。
- 展开态，目标组过多：只有组名列表滚动，sheet 高度不变。
- 展开态，未绑定目标组：展示空状态文案，`all status tag` 与 linked 状态完全一致。
- 展开态 `all status tag` 中的 mini switch 不可点击，不触发启用/禁用弹窗。

- [ ] **Step 4: Final status**

Run:

```bash
git status --short
```

Expected:

- No output.
