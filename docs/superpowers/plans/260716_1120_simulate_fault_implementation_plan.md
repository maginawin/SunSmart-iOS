# Simulate Fault 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Project instructions require Inline Execution and prohibit subagent-driven execution unless the user explicitly requests it.

**Goal:** 仅在具备有效编辑能力的 Light 设备详情页菜单末尾增加 `Simulate Fault`，展示内容高度自适应的底部弹窗，并把 9 种按钮事件传给 `DeviceLightViewController`。

**Architecture:** `DeviceLightViewController` 只负责权限、菜单、弹窗生命周期和事件接收；独立 overlay 负责遮罩、动态高度、滚动与动画；独立 section view 负责固定 tag、collection view 换行和按压反馈。事件与网格计算放在无 UIKit 依赖的模型文件中，使用独立 Swift 测试验证。

**Tech Stack:** Swift、UIKit、SnapKit、UICollectionView、Auto Layout、Asset Catalog、Localizable.strings、standalone Swift tests、shell contract、xcodebuild。

## Global Constraints

- 仅修改 `DeviceLightViewController` 的 More 菜单；其他设备页面保持现状。
- 菜单显示条件必须是 `space.deviceOperates.contains(.edit)`。
- `Simulate Fault` 必须是 Light 菜单最后一项，图标使用 `menu_debug`。
- 弹窗 overlay 只能覆盖 `DeviceLightViewController.view`，不能添加到全局 window。
- 弹窗不设固定高度；自然高度超出页面时才启用内部垂直滚动。
- collection view item 固定为 71 × 28 pt；375 pt 页面宽度下 Light Status 为 4+1 两行，足够宽时五个按钮一行。
- 按钮只传强类型事件，不发送 Mesh/vendor 命令，不显示结果提示，不关闭弹窗，不保留选中态。
- tag 固定为 Minor (3)、Major (2)、Critical (1)，不随状态变化。
- English 与简体中文必须同步；最终中文采用“紧急 (1)”“调光”“调光闪烁”。
- SunSmart、Archipelago、SLG Sync Plus、SylSmart 全部支持。
- 复用现有未提交的 `menu_debug`、`black_debug` 资源，不重新生成或改图。
- 保持当前 NordicSigMeshSDK 依赖状态，不修改 SDK 或依赖配置。
- 最终验证直接使用 iPhoneOS `xcodebuild`，不使用 shell 包装、不重定向日志、不使用 Simulator。

---

## 文件结构

- Create `SunSmart/Main/Device/Model/SimulateFaultAction.swift`：9 种事件与纯网格计算。
- Create `SunSmart/Main/Device/View/SimulateFaultSectionView.swift`：状态区、固定 tag、按钮 cell、collection 高度更新。
- Create `SunSmart/Main/Device/View/SimulateFaultOverlayView.swift`：遮罩、header、三个 section、动态高度、滚动、动画。
- Modify `SunSmart/Main/Device/Controller/DeviceLightViewController.swift`：权限、菜单末项、弹窗生命周期、事件接收。
- Modify `SunSmart/en.lproj/Localizable.strings`：英文文案。
- Modify `SunSmart/zh-Hans.lproj/Localizable.strings`：简体中文文案。
- Add existing `SunSmart/Assets.xcassets/Common/menu_debug.imageset/*`：菜单图标。
- Add existing `SunSmart/Assets.xcassets/Common/black_debug.imageset/*`：弹窗 header 图标。
- Modify `SunSmart.xcodeproj/project.pbxproj`：三个 Swift 文件加入 Device Model/View group，并加入四个 app target 的 Sources。
- Create `Tests/Device/SimulateFaultModelTests.swift`：事件唯一性和网格计算测试。
- Create `scripts/check_simulate_fault.sh`：菜单、权限、范围、本地化、资源、target membership 和无命令副作用 contract。

## PBX target membership 合同

三个新增 Swift 文件各需要一个 `PBXFileReference`，并各需要四个 `PBXBuildFile`，分别进入以下 Sources phase：

- Archipelago：`C88553B12DE6B44C00C8B688`
- SylSmart：`C886E0012E30DE4900D0C3A6`
- SunSmart：`C896B9A02A930BA800217512`
- SLG Sync Plus：`C8BB65AF2ED3F056000C63EE`

`SimulateFaultAction.swift` 加入 `C89941962AD4FB05008DCD76 /* Model */`；两个 View 文件加入 `C898EA6D2AC2D59C0023B480 /* View */`。每次编辑 `project.pbxproj` 后运行 `plutil -lint SunSmart.xcodeproj/project.pbxproj` 和 contract，禁止遗漏任一 target。

---

### Task 1: 强类型事件与网格计算

**Files:**
- Create: `Tests/Device/SimulateFaultModelTests.swift`
- Create: `SunSmart/Main/Device/Model/SimulateFaultAction.swift`
- Modify: `SunSmart.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces: `SimulateFaultAction: Hashable`
- Produces: `SimulateFaultGridMetrics.columns(availableWidth:itemCount:) -> Int`
- Produces: `SimulateFaultGridMetrics.rows(availableWidth:itemCount:) -> Int`
- Produces: `SimulateFaultGridMetrics.collectionHeight(availableWidth:itemCount:) -> CGFloat`

- [ ] **Step 1: 写失败的纯逻辑测试**

Create `Tests/Device/SimulateFaultModelTests.swift`:

```swift
import Foundation

@main
struct SimulateFaultModelTests {
    static func main() {
        let actions: Set<SimulateFaultAction> = [
            .motionSensor(.normal), .motionSensor(.fault),
            .photocellSensor(.normal), .photocellSensor(.fault),
            .lightStatus(.normal), .lightStatus(.dim), .lightStatus(.flicker),
            .lightStatus(.dimFlicker), .lightStatus(.off)
        ]
        precondition(actions.count == 9)

        precondition(SimulateFaultGridMetrics.columns(availableWidth: 311, itemCount: 5) == 4)
        precondition(SimulateFaultGridMetrics.rows(availableWidth: 311, itemCount: 5) == 2)
        precondition(SimulateFaultGridMetrics.collectionHeight(availableWidth: 311, itemCount: 5) == 71)

        precondition(SimulateFaultGridMetrics.columns(availableWidth: 387, itemCount: 5) == 5)
        precondition(SimulateFaultGridMetrics.rows(availableWidth: 387, itemCount: 5) == 1)
        precondition(SimulateFaultGridMetrics.collectionHeight(availableWidth: 387, itemCount: 5) == 36)

        precondition(SimulateFaultGridMetrics.columns(availableWidth: 50, itemCount: 2) == 1)
        precondition(SimulateFaultGridMetrics.rows(availableWidth: 50, itemCount: 2) == 2)
        precondition(SimulateFaultGridMetrics.collectionHeight(availableWidth: 50, itemCount: 0) == 0)

        print("SimulateFaultModelTests passed")
    }
}
```

- [ ] **Step 2: 运行测试并确认失败**

Run:

```bash
swiftc Tests/Device/SimulateFaultModelTests.swift SunSmart/Main/Device/Model/SimulateFaultAction.swift -o /tmp/SimulateFaultModelTests
```

Expected: FAIL，提示 `SimulateFaultAction.swift` 不存在或找不到 `SimulateFaultAction`。

- [ ] **Step 3: 实现最小模型与布局逻辑**

Create `SunSmart/Main/Device/Model/SimulateFaultAction.swift`:

```swift
import Foundation

enum SimulateFaultAction: Hashable {
    enum SensorState: Hashable {
        case normal
        case fault
    }

    enum LightState: Hashable {
        case normal
        case dim
        case flicker
        case dimFlicker
        case off
    }

    case motionSensor(SensorState)
    case photocellSensor(SensorState)
    case lightStatus(LightState)
}

enum SimulateFaultGridMetrics {
    static let itemWidth: CGFloat = 71
    static let itemHeight: CGFloat = 28
    static let interitemSpacing: CGFloat = 8
    static let lineSpacing: CGFloat = 7
    static let topInset: CGFloat = 8

    static func columns(availableWidth: CGFloat, itemCount: Int) -> Int {
        guard itemCount > 0 else { return 0 }
        let count = Int((availableWidth + interitemSpacing) / (itemWidth + interitemSpacing))
        return min(itemCount, max(1, count))
    }

    static func rows(availableWidth: CGFloat, itemCount: Int) -> Int {
        let columnCount = columns(availableWidth: availableWidth, itemCount: itemCount)
        guard columnCount > 0 else { return 0 }
        return Int(ceil(Double(itemCount) / Double(columnCount)))
    }

    static func collectionHeight(availableWidth: CGFloat, itemCount: Int) -> CGFloat {
        let rowCount = rows(availableWidth: availableWidth, itemCount: itemCount)
        guard rowCount > 0 else { return 0 }
        return topInset
            + CGFloat(rowCount) * itemHeight
            + CGFloat(rowCount - 1) * lineSpacing
    }
}
```

Add the file to the Model PBX group and all four Sources phases defined above.

- [ ] **Step 4: 运行纯逻辑测试并确认通过**

Run:

```bash
swiftc Tests/Device/SimulateFaultModelTests.swift SunSmart/Main/Device/Model/SimulateFaultAction.swift -o /tmp/SimulateFaultModelTests
/tmp/SimulateFaultModelTests
plutil -lint SunSmart.xcodeproj/project.pbxproj
```

Expected: `SimulateFaultModelTests passed` and `SunSmart.xcodeproj/project.pbxproj: OK`.

- [ ] **Step 5: 提交模型任务**

```bash
git add Tests/Device/SimulateFaultModelTests.swift SunSmart/Main/Device/Model/SimulateFaultAction.swift SunSmart.xcodeproj/project.pbxproj
git commit -m "feat: add simulate fault event model"
```

---

### Task 2: 状态区与 collection view 按钮

**Files:**
- Create: `scripts/check_simulate_fault.sh`
- Create: `SunSmart/Main/Device/View/SimulateFaultSectionView.swift`
- Modify: `SunSmart.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `SimulateFaultAction`, `SimulateFaultGridMetrics`
- Produces: `SimulateFaultSectionView.Configuration`
- Produces: `SimulateFaultSectionView.onAction: ((SimulateFaultAction) -> Void)?`

- [ ] **Step 1: 写失败的 section contract**

Create `scripts/check_simulate_fault.sh` with executable mode:

```bash
#!/usr/bin/env bash
set -euo pipefail

section_file="SunSmart/Main/Device/View/SimulateFaultSectionView.swift"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

test -f "$section_file" || fail "SimulateFaultSectionView.swift is missing"
grep -Fq 'UICollectionViewDelegateFlowLayout' "$section_file" || fail "section must use collection view flow layout"
grep -Fq 'SimulateFaultGridMetrics.collectionHeight' "$section_file" || fail "section must derive collection height from grid metrics"
grep -Fq 'isHighlighted' "$section_file" || fail "button cell must provide transient highlight feedback"
grep -Fq 'onAction?(configuration.items[indexPath.item].action)' "$section_file" || fail "section must expose the typed action"

printf 'PASS: Simulate Fault section contract is present.\n'
```

- [ ] **Step 2: 运行 contract 并确认失败**

Run: `bash scripts/check_simulate_fault.sh`

Expected: FAIL with `SimulateFaultSectionView.swift is missing`.

- [ ] **Step 3: 实现 section、tag 与 button cell**

Create `SunSmart/Main/Device/View/SimulateFaultSectionView.swift` with these concrete types and constants:

```swift
import UIKit
import SnapKit

final class SimulateFaultSectionView: UIView {
    struct Item {
        let titleKey: String
        let action: SimulateFaultAction
    }

    struct TagStyle {
        let textColor: UIColor
        let backgroundColor: UIColor
    }

    struct Configuration {
        let titleKey: String
        let tagKey: String
        let tagStyle: TagStyle
        let items: [Item]
    }

    var onAction: ((SimulateFaultAction) -> Void)?

    private let configuration: Configuration
    private let titleLabel = UILabel()
    private let tagLabel = UILabel()
    private let flowLayout = UICollectionViewFlowLayout()
    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
    private var collectionHeightConstraint: Constraint?
    private var lastMeasuredWidth: CGFloat = 0

    init(configuration: Configuration) {
        self.configuration = configuration
        super.init(frame: .zero)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = collectionView.bounds.width
        guard width > 0, width != lastMeasuredWidth else { return }
        lastMeasuredWidth = width
        let height = SimulateFaultGridMetrics.collectionHeight(
            availableWidth: width,
            itemCount: configuration.items.count
        )
        collectionHeightConstraint?.update(offset: height)
        flowLayout.invalidateLayout()
    }

    private func setupUI() {
        backgroundColor = UIColor(red: 248 / 255, green: 250 / 255, blue: 252 / 255, alpha: 1)
        layer.cornerRadius = 14

        titleLabel.text = configuration.titleKey.localizedString
        titleLabel.textColor = UIColor(red: 27 / 255, green: 20 / 255, blue: 37 / 255, alpha: 1)
        titleLabel.font = .systemFont(ofSize: 14)

        tagLabel.text = configuration.tagKey.localizedString
        tagLabel.textColor = configuration.tagStyle.textColor
        tagLabel.backgroundColor = configuration.tagStyle.backgroundColor
        tagLabel.font = .systemFont(ofSize: 12)
        tagLabel.textAlignment = .center
        tagLabel.layer.cornerRadius = 6
        tagLabel.clipsToBounds = true

        flowLayout.itemSize = CGSize(width: SimulateFaultGridMetrics.itemWidth, height: SimulateFaultGridMetrics.itemHeight)
        flowLayout.minimumInteritemSpacing = SimulateFaultGridMetrics.interitemSpacing
        flowLayout.minimumLineSpacing = SimulateFaultGridMetrics.lineSpacing
        flowLayout.sectionInset = UIEdgeInsets(top: SimulateFaultGridMetrics.topInset, left: 0, bottom: 0, right: 0)

        collectionView.backgroundColor = .clear
        collectionView.isScrollEnabled = false
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(SimulateFaultButtonCell.self, forCellWithReuseIdentifier: SimulateFaultButtonCell.reuseIdentifier)

        addSubview(titleLabel)
        addSubview(tagLabel)
        addSubview(collectionView)

        titleLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(12)
            make.left.equalToSuperview().offset(16)
            make.height.equalTo(21)
        }
        tagLabel.snp.makeConstraints { make in
            make.centerY.equalTo(titleLabel)
            make.right.equalToSuperview().offset(-16)
            make.height.equalTo(20)
            make.width.greaterThanOrEqualTo(63)
        }
        collectionView.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom)
            make.left.equalToSuperview().offset(16)
            make.right.equalToSuperview().offset(-16)
            make.bottom.equalToSuperview().offset(-12)
            collectionHeightConstraint = make.height.equalTo(0).constraint
        }
    }
}

extension SimulateFaultSectionView: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        configuration.items.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: SimulateFaultButtonCell.reuseIdentifier,
            for: indexPath
        ) as! SimulateFaultButtonCell
        cell.configure(title: configuration.items[indexPath.item].titleKey.localizedString)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        onAction?(configuration.items[indexPath.item].action)
        collectionView.deselectItem(at: indexPath, animated: false)
    }
}

private final class SimulateFaultButtonCell: UICollectionViewCell {
    static let reuseIdentifier = "SimulateFaultButtonCell"
    private let titleLabel = UILabel()

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.1) {
                self.contentView.alpha = self.isHighlighted ? 0.55 : 1
                self.contentView.transform = self.isHighlighted
                    ? CGAffineTransform(scaleX: 0.96, y: 0.96)
                    : .identity
            }
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .white
        contentView.layer.cornerRadius = 8
        contentView.layer.borderWidth = 0.5
        contentView.layer.borderColor = UIColor(red: 236 / 255, green: 236 / 255, blue: 236 / 255, alpha: 1).cgColor
        titleLabel.textColor = UIColor(red: 102 / 255, green: 103 / 255, blue: 171 / 255, alpha: 1)
        titleLabel.font = .systemFont(ofSize: 12)
        titleLabel.textAlignment = .center
        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { $0.edges.equalToSuperview() }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        contentView.alpha = 1
        contentView.transform = .identity
    }

    func configure(title: String) {
        titleLabel.text = title
    }
}
```

Add the file to the View PBX group and all four Sources phases.

- [ ] **Step 4: 运行 contract、PBX lint 和 SunSmart 构建**

Run:

```bash
bash scripts/check_simulate_fault.sh
plutil -lint SunSmart.xcodeproj/project.pbxproj
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: contract PASS, PBX `OK`, build ends with `** BUILD SUCCEEDED **`.

- [ ] **Step 5: 提交 section 任务**

```bash
git add scripts/check_simulate_fault.sh SunSmart/Main/Device/View/SimulateFaultSectionView.swift SunSmart.xcodeproj/project.pbxproj
git commit -m "feat: add simulate fault status sections"
```

---

### Task 3: 自适应底部 overlay

**Files:**
- Modify: `scripts/check_simulate_fault.sh`
- Create: `SunSmart/Main/Device/View/SimulateFaultOverlayView.swift`
- Modify: `SunSmart.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `SimulateFaultSectionView`, `SimulateFaultAction`
- Produces: `SimulateFaultOverlayView.init(onAction:)`
- Produces: `present(in:)`, `dismiss(animated:)`

- [ ] **Step 1: 扩展 contract 并确认失败**

Append before the PASS line in `scripts/check_simulate_fault.sh`:

```bash
overlay_file="SunSmart/Main/Device/View/SimulateFaultOverlayView.swift"
test -f "$overlay_file" || fail "SimulateFaultOverlayView.swift is missing"
grep -Fq 'make.edges.equalToSuperview()' "$overlay_file" || fail "overlay must match the host view"
grep -Fq 'make.top.greaterThanOrEqualTo(safeAreaLayoutGuide)' "$overlay_file" || fail "content must be bounded by safe area"
grep -Fq 'contentLayoutGuide' "$overlay_file" || fail "overflow must use scroll content layout guide"
grep -Fq 'frameLayoutGuide.heightAnchor.constraint' "$overlay_file" || fail "natural height must be derived from scroll content height"
grep -Fq 'menu_debug' "$overlay_file" && fail "overlay header must not use menu_debug"
grep -Fq 'black_debug' "$overlay_file" || fail "overlay header must use black_debug"
grep -Eq 'MeshAPI|sendMessage|NordicSigMeshSDK' "$overlay_file" && fail "overlay must not access the command layer"
```

Run: `bash scripts/check_simulate_fault.sh`

Expected: FAIL with `SimulateFaultOverlayView.swift is missing`.

- [ ] **Step 2: 实现 overlay 与三个固定 section**

Create `SunSmart/Main/Device/View/SimulateFaultOverlayView.swift`. The implementation must contain:

```swift
import UIKit
import SnapKit

final class SimulateFaultOverlayView: UIView {
    private let onAction: (SimulateFaultAction) -> Void
    private let dimmingView = UIView()
    private let contentView = UIView()
    private let scrollView = UIScrollView()
    private let stackView = UIStackView()

    init(onAction: @escaping (SimulateFaultAction) -> Void) {
        self.onAction = onAction
        super.init(frame: .zero)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present(in hostView: UIView) {
        guard superview == nil else { return }
        hostView.addSubview(self)
        snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        hostView.layoutIfNeeded()
        dimmingView.alpha = 0
        contentView.transform = CGAffineTransform(translationX: 0, y: contentView.bounds.height)
        UIView.animate(withDuration: 0.25) {
            self.dimmingView.alpha = 1
            self.contentView.transform = .identity
        }
    }

    func dismiss(animated: Bool = true) {
        guard superview != nil else { return }
        let animations = {
            self.dimmingView.alpha = 0
            self.contentView.transform = CGAffineTransform(translationX: 0, y: self.contentView.bounds.height)
        }
        let completion: (Bool) -> Void = { _ in self.removeFromSuperview() }
        if animated {
            UIView.animate(withDuration: 0.25, animations: animations, completion: completion)
        } else {
            animations()
            removeFromSuperview()
        }
    }

    private func setupUI() {
        dimmingView.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        dimmingView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(backgroundTapped)))

        contentView.backgroundColor = .white
        contentView.layer.cornerRadius = 20
        contentView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        contentView.clipsToBounds = true

        stackView.axis = .vertical
        stackView.spacing = 11

        addSubview(dimmingView)
        addSubview(contentView)
        contentView.addSubview(scrollView)
        scrollView.addSubview(stackView)

        dimmingView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        contentView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.top.greaterThanOrEqualTo(safeAreaLayoutGuide).offset(8)
        }
        scrollView.snp.makeConstraints { make in
            make.top.left.right.equalToSuperview()
            make.bottom.equalTo(contentView.safeAreaLayoutGuide)
        }
        stackView.snp.makeConstraints { make in
            make.top.equalTo(scrollView.contentLayoutGuide).offset(8)
            make.left.equalTo(scrollView.contentLayoutGuide).offset(16)
            make.right.equalTo(scrollView.contentLayoutGuide).offset(-16)
            make.bottom.equalTo(scrollView.contentLayoutGuide).offset(-12)
            make.width.equalTo(scrollView.frameLayoutGuide).offset(-32)
        }

        let naturalHeightConstraint = scrollView.frameLayoutGuide.heightAnchor.constraint(
            equalTo: scrollView.contentLayoutGuide.heightAnchor
        )
        naturalHeightConstraint.priority = UILayoutPriority(999)
        naturalHeightConstraint.isActive = true

        stackView.addArrangedSubview(makeHeaderView())
        [makeMotionSection(), makePhotocellSection(), makeLightSection()].forEach { section in
            section.onAction = { [weak self] action in self?.onAction(action) }
            stackView.addArrangedSubview(section)
        }
    }

    private func makeHeaderView() -> UIView {
        let header = UIView()
        let icon = UIImageView(image: UIImage(named: "black_debug"))
        let title = UILabel()
        title.text = "simulate_fault".localizedString
        title.textColor = UIColor(red: 46 / 255, green: 49 / 255, blue: 93 / 255, alpha: 1)
        title.font = .systemFont(ofSize: 14)
        header.addSubview(icon)
        header.addSubview(title)
        header.snp.makeConstraints { $0.height.equalTo(40) }
        icon.snp.makeConstraints { make in
            make.left.equalToSuperview().offset(4)
            make.centerY.equalToSuperview()
            make.size.equalTo(30)
        }
        title.snp.makeConstraints { make in
            make.left.equalTo(icon.snp.right).offset(2)
            make.centerY.equalToSuperview()
        }
        return header
    }

    private func makeMotionSection() -> SimulateFaultSectionView {
        SimulateFaultSectionView(configuration: .init(
            titleKey: "simulate_fault_motion_sensor",
            tagKey: "simulate_fault_minor_3",
            tagStyle: .init(
                textColor: UIColor(red: 1, green: 170 / 255, blue: 0, alpha: 1),
                backgroundColor: UIColor(red: 1, green: 170 / 255, blue: 0, alpha: 0.15)
            ),
            items: [
                .init(titleKey: "simulate_fault_normal", action: .motionSensor(.normal)),
                .init(titleKey: "simulate_fault_fault", action: .motionSensor(.fault))
            ]
        ))
    }

    private func makePhotocellSection() -> SimulateFaultSectionView {
        SimulateFaultSectionView(configuration: .init(
            titleKey: "simulate_fault_photocell_sensor",
            tagKey: "simulate_fault_major_2",
            tagStyle: .init(
                textColor: UIColor(red: 240 / 255, green: 119 / 255, blue: 107 / 255, alpha: 1),
                backgroundColor: UIColor(red: 240 / 255, green: 119 / 255, blue: 107 / 255, alpha: 0.15)
            ),
            items: [
                .init(titleKey: "simulate_fault_normal", action: .photocellSensor(.normal)),
                .init(titleKey: "simulate_fault_fault", action: .photocellSensor(.fault))
            ]
        ))
    }

    private func makeLightSection() -> SimulateFaultSectionView {
        SimulateFaultSectionView(configuration: .init(
            titleKey: "simulate_fault_light_status",
            tagKey: "simulate_fault_critical_1",
            tagStyle: .init(
                textColor: UIColor(red: 1, green: 62 / 255, blue: 62 / 255, alpha: 1),
                backgroundColor: UIColor(red: 1, green: 62 / 255, blue: 62 / 255, alpha: 0.15)
            ),
            items: [
                .init(titleKey: "simulate_fault_normal", action: .lightStatus(.normal)),
                .init(titleKey: "simulate_fault_dim", action: .lightStatus(.dim)),
                .init(titleKey: "simulate_fault_flicker", action: .lightStatus(.flicker)),
                .init(titleKey: "simulate_fault_dim_flicker", action: .lightStatus(.dimFlicker)),
                .init(titleKey: "simulate_fault_off", action: .lightStatus(.off))
            ]
        ))
    }

    @objc private func backgroundTapped() {
        dismiss()
    }
}
```

The priority-999 equality makes the sheet use its natural content height when it fits. When natural content would cross the overlay safe-area top constraint, Auto Layout breaks only that equality, keeps the sheet within the host page, and lets the scroll view expose the complete content. Preserve this constraint contract and do not introduce a fixed overlay height.

Add the file to the View PBX group and all four Sources phases.

- [ ] **Step 3: 运行 contract、模型测试、PBX lint 和 SunSmart 构建**

Run:

```bash
bash scripts/check_simulate_fault.sh
swiftc Tests/Device/SimulateFaultModelTests.swift SunSmart/Main/Device/Model/SimulateFaultAction.swift -o /tmp/SimulateFaultModelTests
/tmp/SimulateFaultModelTests
plutil -lint SunSmart.xcodeproj/project.pbxproj
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: all contracts PASS, PBX `OK`, build succeeds.

- [ ] **Step 4: 提交 overlay 任务**

```bash
git add scripts/check_simulate_fault.sh SunSmart/Main/Device/View/SimulateFaultOverlayView.swift SunSmart.xcodeproj/project.pbxproj
git commit -m "feat: add simulate fault bottom sheet"
```

---

### Task 4: 资源与双语文案

**Files:**
- Modify: `scripts/check_simulate_fault.sh`
- Modify: `SunSmart/en.lproj/Localizable.strings`
- Modify: `SunSmart/zh-Hans.lproj/Localizable.strings`
- Add: `SunSmart/Assets.xcassets/Common/menu_debug.imageset/Contents.json`
- Add: `SunSmart/Assets.xcassets/Common/menu_debug.imageset/menu_debug.png`
- Add: `SunSmart/Assets.xcassets/Common/menu_debug.imageset/menu_debug@2x.png`
- Add: `SunSmart/Assets.xcassets/Common/menu_debug.imageset/menu_debug@3x.png`
- Add: `SunSmart/Assets.xcassets/Common/black_debug.imageset/Contents.json`
- Add: `SunSmart/Assets.xcassets/Common/black_debug.imageset/black_debug.png`
- Add: `SunSmart/Assets.xcassets/Common/black_debug.imageset/black_debug@2x.png`
- Add: `SunSmart/Assets.xcassets/Common/black_debug.imageset/black_debug@3x.png`

**Interfaces:**
- Produces: 13 feature-scoped localization keys in both languages.
- Produces: shared `menu_debug` and `black_debug` named images.

- [ ] **Step 1: 扩展本地化与资源 contract**

Append before the PASS line in `scripts/check_simulate_fault.sh`:

```bash
en_strings="SunSmart/en.lproj/Localizable.strings"
zh_strings="SunSmart/zh-Hans.lproj/Localizable.strings"

check_string() {
  local file="$1"
  local line="$2"
  grep -Fq "$line" "$file" || fail "$file is missing: $line"
}

check_string "$en_strings" '"simulate_fault" = "Simulate Fault";'
check_string "$en_strings" '"simulate_fault_critical_1" = "Critical (1)";'
check_string "$en_strings" '"simulate_fault_dim" = "Dim";'
check_string "$en_strings" '"simulate_fault_dim_flicker" = "Dim Flicker";'
check_string "$zh_strings" '"simulate_fault" = "模拟故障";'
check_string "$zh_strings" '"simulate_fault_critical_1" = "紧急 (1)";'
check_string "$zh_strings" '"simulate_fault_dim" = "调光";'
check_string "$zh_strings" '"simulate_fault_dim_flicker" = "调光闪烁";'

test -f "SunSmart/Assets.xcassets/Common/menu_debug.imageset/menu_debug@3x.png" || fail "menu_debug assets are incomplete"
test -f "SunSmart/Assets.xcassets/Common/black_debug.imageset/black_debug@3x.png" || fail "black_debug assets are incomplete"
plutil -lint "SunSmart/Assets.xcassets/Common/menu_debug.imageset/Contents.json" >/dev/null
plutil -lint "SunSmart/Assets.xcassets/Common/black_debug.imageset/Contents.json" >/dev/null
```

Run: `bash scripts/check_simulate_fault.sh`

Expected: FAIL on the first missing localization line.

- [ ] **Step 2: 增加完整双语文案**

Append to English strings:

```text
"simulate_fault" = "Simulate Fault";
"simulate_fault_motion_sensor" = "Motion Sensor";
"simulate_fault_photocell_sensor" = "Photocell Sensor";
"simulate_fault_light_status" = "Light Status";
"simulate_fault_minor_3" = "Minor (3)";
"simulate_fault_major_2" = "Major (2)";
"simulate_fault_critical_1" = "Critical (1)";
"simulate_fault_normal" = "Normal";
"simulate_fault_fault" = "Fault";
"simulate_fault_dim" = "Dim";
"simulate_fault_flicker" = "Flicker";
"simulate_fault_dim_flicker" = "Dim Flicker";
"simulate_fault_off" = "Off";
```

Append to Simplified Chinese strings:

```text
"simulate_fault" = "模拟故障";
"simulate_fault_motion_sensor" = "移动传感器";
"simulate_fault_photocell_sensor" = "光感传感器";
"simulate_fault_light_status" = "灯具状态";
"simulate_fault_minor_3" = "轻微 (3)";
"simulate_fault_major_2" = "严重 (2)";
"simulate_fault_critical_1" = "紧急 (1)";
"simulate_fault_normal" = "正常";
"simulate_fault_fault" = "故障";
"simulate_fault_dim" = "调光";
"simulate_fault_flicker" = "闪烁";
"simulate_fault_dim_flicker" = "调光闪烁";
"simulate_fault_off" = "关闭";
```

Do not alter the image bytes. Validate the existing Contents.json filenames match all 1x/2x/3x files.

- [ ] **Step 3: 运行资源、本地化和现有 i18n contract**

Run:

```bash
bash scripts/check_simulate_fault.sh
bash scripts/check_device_i18n_titles.sh
plutil -lint SunSmart/Assets.xcassets/Common/menu_debug.imageset/Contents.json
plutil -lint SunSmart/Assets.xcassets/Common/black_debug.imageset/Contents.json
```

Expected: all commands PASS.

- [ ] **Step 4: 提交资源与本地化任务**

```bash
git add scripts/check_simulate_fault.sh SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings SunSmart/Assets.xcassets/Common/menu_debug.imageset SunSmart/Assets.xcassets/Common/black_debug.imageset
git commit -m "feat: add simulate fault resources"
```

---

### Task 5: Light 菜单与弹窗生命周期接入

**Files:**
- Modify: `scripts/check_simulate_fault.sh`
- Modify: `SunSmart/Main/Device/Controller/DeviceLightViewController.swift`

**Interfaces:**
- Consumes: `SimulateFaultOverlayView`, `SimulateFaultAction`
- Produces: `showSimulateFault()`, `handleSimulateFaultAction(_:)`, permission-change cleanup.

- [ ] **Step 1: 扩展 Light 页面 contract 并确认失败**

Append before the PASS line in `scripts/check_simulate_fault.sh`:

```bash
light_file="SunSmart/Main/Device/Controller/DeviceLightViewController.swift"

grep -Fq 'icon: UIImage(named: "menu_debug")' "$light_file" \
  || fail "Light menu must use menu_debug"
grep -Fq 'title: "simulate_fault".localizedString' "$light_file" \
  || fail "Light menu must use the localized Simulate Fault title"
grep -Fq 'guard space.deviceOperates.contains(.edit)' "$light_file" \
  || fail "presentation must re-check effective edit capability"
grep -Fq 'SimulateFaultOverlayView' "$light_file" \
  || fail "Light controller must present the overlay"
grep -Fq 'handleSimulateFaultAction(_ action: SimulateFaultAction)' "$light_file" \
  || fail "Light controller must receive the typed action"

simulate_line=$(grep -n 'title: "simulate_fault".localizedString' "$light_file" | tail -1 | cut -d: -f1)
refresh_line=$(grep -n 'title: "refresh".localizedString' "$light_file" | tail -1 | cut -d: -f1)
test "$simulate_line" -gt "$refresh_line" || fail "Simulate Fault must be appended after Refresh"

matches=$(grep -R -l 'title: "simulate_fault".localizedString' SunSmart/Main/Device --include='*.swift')
test "$matches" = "$light_file" || fail "Simulate Fault menu must exist only in DeviceLightViewController"
```

Run: `bash scripts/check_simulate_fault.sh`

Expected: FAIL because the Light menu item is not present.

- [ ] **Step 2: 接入属性、权限观察和页面清理**

Add to `DeviceLightViewController` properties:

```swift
private weak var simulateFaultOverlayView: SimulateFaultOverlayView?
```

Add in `viewDidLoad()` after navigation item setup:

```swift
NotificationCenter.default.addObserver(
    self,
    selector: #selector(spacePermissionDidChange),
    name: .init(spacePermissionChangedNotificaitonName),
    object: nil
)
```

Add to `viewWillDisappear(_:)`:

```swift
simulateFaultOverlayView?.dismiss(animated: false)
```

Add to `deinit`:

```swift
NotificationCenter.default.removeObserver(self)
```

- [ ] **Step 3: 在菜单末尾追加入口并实现无命令事件接收**

Immediately after the existing Refresh item and before menu positioning, add:

```swift
if space.deviceOperates.contains(.edit) {
    items.append(.init(
        icon: UIImage(named: "menu_debug"),
        title: "simulate_fault".localizedString,
        hideAnimation: false,
        performsActionAfterDismiss: true,
        tapItemBack: { [weak self] _ in
            self?.showSimulateFault()
        }
    ))
}
```

Add focused methods:

```swift
private func showSimulateFault() {
    guard space.deviceOperates.contains(.edit) else { return }
    guard simulateFaultOverlayView == nil else { return }

    let overlay = SimulateFaultOverlayView { [weak self] action in
        self?.handleSimulateFaultAction(action)
    }
    simulateFaultOverlayView = overlay
    overlay.present(in: view)
}

private func handleSimulateFaultAction(_ action: SimulateFaultAction) {
    _ = action
}

@objc private func spacePermissionDidChange() {
    guard !space.deviceOperates.contains(.edit) else { return }
    simulateFaultOverlayView?.dismiss()
}
```

The handler intentionally has no Mesh call, status mutation, HUD, or dismiss call. It is the explicit View Controller event boundary for later work.

- [ ] **Step 4: 运行所有 targeted checks 和 SunSmart build**

Run:

```bash
bash scripts/check_simulate_fault.sh
bash scripts/check_device_menu_icons.sh
bash scripts/check_device_i18n_titles.sh
swiftc Tests/Device/SimulateFaultModelTests.swift SunSmart/Main/Device/Model/SimulateFaultAction.swift -o /tmp/SimulateFaultModelTests
/tmp/SimulateFaultModelTests
git diff --check
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: scripts and model test PASS, no whitespace errors, build succeeds.

- [ ] **Step 5: 提交 Light 接入任务**

```bash
git add scripts/check_simulate_fault.sh SunSmart/Main/Device/Controller/DeviceLightViewController.swift
git commit -m "feat: add simulate fault light menu"
```

---

### Task 6: 四品牌构建与最终验收

**Files:**
- Verify only; modify implementation files only if a verification failure directly belongs to this feature.

**Interfaces:**
- Consumes all previous tasks.
- Produces a verified four-target implementation with no SDK or unrelated changes.

- [ ] **Step 1: 运行完整静态与纯逻辑验证**

```bash
bash scripts/check_simulate_fault.sh
bash scripts/check_device_menu_icons.sh
bash scripts/check_device_i18n_titles.sh
swiftc Tests/Device/SimulateFaultModelTests.swift SunSmart/Main/Device/Model/SimulateFaultAction.swift -o /tmp/SimulateFaultModelTests
/tmp/SimulateFaultModelTests
plutil -lint SunSmart.xcodeproj/project.pbxproj
git diff --check
```

Expected: every command PASS.

- [ ] **Step 2: 构建 SunSmart**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: 构建 Archipelago**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme Archipelago -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: 构建 SLG Sync Plus**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme 'SLG Sync Plus' -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: 构建 SylSmart**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SylSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: 手工验收矩阵**

Verify on the current Light detail page:

- Owner and normal Editor show `Simulate Fault` as the final menu item.
- Visitor, downgraded Editor, and Mesh OTA restriction do not show it.
- The menu item uses `menu_debug`; the sheet header uses `black_debug`.
- The sheet width equals `DeviceLightViewController.view` on iPhone and iPad.
- 375 pt content width produces a 4+1 Light Status layout; wide iPad content produces one row.
- Background tap dismisses; content taps do not dismiss.
- All 9 buttons show transient feedback, emit the correct event, remain unselected, and keep the sheet open.
- English and Simplified Chinese match the approved copy.
- Permission loss and page exit close the sheet; repeated presentation does not stack overlays.

- [ ] **Step 7: 核对最终改动边界**

Run:

```bash
git status --short
git diff --stat HEAD~5..HEAD
git diff --name-only HEAD~5..HEAD
```

Expected: only the files listed in this plan plus the approved assets/tests/script/docs are part of the feature; NordicSigMeshSDK and unrelated modules are absent.

---

## 执行方式

按项目指令采用 **Inline Execution**：在当前会话使用 `superpowers:executing-plans`，逐任务执行，每个任务完成测试、构建检查和独立 commit 后再进入下一任务。不得使用 subagents。
