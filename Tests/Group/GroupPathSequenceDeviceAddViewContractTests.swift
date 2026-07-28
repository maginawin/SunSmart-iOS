import Foundation

@main
struct GroupPathSequenceDeviceAddViewContractTests {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            fatalError("Expected repository root path")
        }

        let root = CommandLine.arguments[1]
        let addView = try source(
            root,
            "SunSmart/Main/Group/Path/View/GroupPathSequenceDeviceAddView.swift"
        )
        let sequenceController = try source(
            root,
            "SunSmart/Main/Group/Path/Controller/GroupPathSequenceViewController.swift"
        )
        let zoneController = try source(
            root,
            "SunSmart/Main/Group/Path/Controller/GroupPathSequenceTriggerZoneController.swift"
        )
        let spaceController = try source(
            root,
            "SunSmart/Main/Space/TriggerZone/Controller/SpacePathTriggerZoneController.swift"
        )
        let spaceMore = try source(
            root,
            "SunSmart/Main/Space/Controller/SpaceMoreViewController.swift"
        )
        let stepView = try source(
            root,
            "SunSmart/Main/Group/Path/View/GroupPathSequenceDeviceAddStepView.swift"
        )
        let quickAddView = try source(
            root,
            "SunSmart/Main/Group/Path/View/GroupPathSequenceQuickAddView.swift"
        )
        let triggerAddView = try source(
            root,
            "SunSmart/Main/Group/Path/View/GroupPathSequenceTriggerAddView.swift"
        )
        let manuallyAddView = try source(
            root,
            "SunSmart/Main/Group/Path/View/GroupPathSequenceManuallyAddView.swift"
        )
        let addDeviceCell = try source(
            root,
            "SunSmart/Main/Group/Path/View/GroupPathSequenceAddDeviceCell.swift"
        )
        let pathCell = try source(
            root,
            "SunSmart/Main/Group/Path/View/GroupPathSequencePathViewCell.swift"
        )
        let zoneCell = try source(
            root,
            "SunSmart/Main/Group/Path/View/GroupPathSequenceTriggerZoneViewCell.swift"
        )
        let pathLayout = try source(
            root,
            "SunSmart/Main/Group/Path/View/GroupPathSequencePathLayout.swift"
        )
        let sequenceEmptyState = section(
            in: sequenceController,
            from: "private func updateEmptyUI()",
            to: "private func updateDeviceAddViewUI()"
        )
        let zoneEmptyState = section(
            in: zoneController,
            from: "private func updateEmptyUI()",
            to: "private func updateDeviceAddViewUI()"
        )

        for (name, emptyState) in [
            ("Sequence", sequenceEmptyState),
            ("Trigger Zone", zoneEmptyState),
        ] {
            require(
                !emptyState.contains("frame: tableView.frame"),
                "\(name) empty state must not depend on a one-time table frame snapshot"
            )
            require(
                emptyState.contains("view.emptyView?.snp.makeConstraints"),
                "\(name) empty state must receive outer Auto Layout constraints"
            )
            require(
                emptyState.contains("make.edges.equalTo(tableView)"),
                "\(name) empty state must track all table view edges"
            )
        }

        require(
            pathLayout.contains("static let controlSize: CGFloat = 44"),
            "Device control must be 44 points"
        )
        require(
            pathLayout.contains("static let controlCornerRadius: CGFloat = 22"),
            "The fixed 44-point device control must retain a 22-point circular radius"
        )
        require(
            pathLayout.contains("static let imageSize: CGFloat = 20"),
            "Device image must be 20 points"
        )
        require(
            pathLayout.contains("static let sequenceLabelHeight: CGFloat = 16"),
            "Sequence label must be 16 points"
        )
        require(
            pathLayout.contains("static let sequenceItemHeight: CGFloat = 60"),
            "Sequence item height must be 60 points"
        )
        require(
            pathCell.contains(
                "make.width.height.equalTo(GroupPathSequenceDeviceItemMetrics.controlSize)"
            ),
            "Sequence control must use fixed 44-point metrics"
        )
        let circularRadiusAssignment =
            "boxView.layer.cornerRadius = "
            + "GroupPathSequenceDeviceItemMetrics.controlCornerRadius"
        require(
            pathCell.components(separatedBy: circularRadiusAssignment).count - 1 >= 2,
            "Sequence device and Add controls must both retain the circular radius"
        )
        require(
            pathCell.contains("private let addItemDashedBorderLayer = CAShapeLayer()"),
            "Path Add item must retain one stable dashed border layer"
        )
        require(
            pathCell.contains("contentView.layoutIfNeeded()"),
            "Path Add item must resolve its fixed box bounds before updating the dashed path"
        )
        require(
            pathCell.contains(
                "UIBezierPath(ovalIn: borderBounds).cgPath"
            ),
            "Path Add item dashed border must use the resolved circular bounds"
        )
        require(
            !pathCell.contains("boxView.addDashedBorder()"),
            "Path Add item must not rebuild its dashed border from unresolved child bounds"
        )
        require(
            pathCell.contains(
                "make.height.equalTo(GroupPathSequenceDeviceItemMetrics.sequenceLabelHeight)"
            ),
            "Sequence label must use fixed 16-point metrics"
        )
        require(
            pathCell.contains(
                "make.width.height.equalTo(GroupPathSequenceDeviceItemMetrics.imageSize)"
            ),
            "Sequence image must use fixed 20-point metrics"
        )
        require(
            !pathCell.contains("SCRYFrom"),
            "Sequence device cell must not retain SCRYFrom"
        )
        require(
            !zoneCell.contains("SCRYFrom"),
            "Trigger Zone device cell must not retain SCRYFrom"
        )
        require(
            !pathLayout.contains("SCRYFrom"),
            "Sequence path layout must not retain SCRYFrom"
        )
        require(
            zoneCell.contains(
                "height: GroupPathSequenceDeviceItemMetrics.controlSize"
            ),
            "Trigger Zone slot height must be fixed at 44 points"
        )
        require(
            zoneCell.contains("max(rowCount - 1, 0)"),
            "Trigger Zone zero rows must not produce negative spacing"
        )
        require(
            zoneController.contains("tableView.estimatedRowHeight = 76"),
            "Trigger Zone estimated row height must be fixed at 76 points"
        )
        require(
            addDeviceCell.contains("var boxView: UIView!"),
            "Add device cell must expose its fixed visual control"
        )
        require(
            addDeviceCell.contains(
                "make.width.height.equalTo(GroupPathSequenceDeviceItemMetrics.controlSize)"
            ),
            "Add device control must use fixed 44-point metrics"
        )
        require(
            addDeviceCell.contains(circularRadiusAssignment),
            "Add device control must retain the circular radius"
        )
        require(
            addDeviceCell.contains(
                "make.width.height.equalTo(GroupPathSequenceDeviceItemMetrics.imageSize)"
            ),
            "Add device image must use fixed 20-point metrics"
        )
        require(
            triggerAddView.contains(
                "flowLayout.itemHeight = GroupPathSequenceDeviceItemMetrics.controlSize"
            ),
            "Trigger Add item height must be fixed at 44 points"
        )
        require(
            triggerAddView.contains(
                "UIEdgeInsets(top: 12, left: 26, bottom: 12, right: 25)"
            ),
            "Trigger Add devices must center vertically in the 68-point collection view"
        )
        require(
            !triggerAddView.contains("make.height.equalTo(isIPad ? 64 : 44)"),
            "Trigger Add must not restore device-dependent collection heights"
        )
        require(
            manuallyAddView.contains(
                "flowLayout.itemHeight = GroupPathSequenceDeviceItemMetrics.controlSize"
            ),
            "Manually Add item height must be fixed at 44 points"
        )
        require(
            manuallyAddView.contains(
                "return GroupPathSequenceDeviceItemMetrics.controlSize * CGFloat(rowNum)"
            ),
            "Manually Add collection height must use fixed 44-point rows"
        )
        require(
            manuallyAddView.contains(
                "return GroupPathSequenceDeviceItemMetrics.controlSize"
            ),
            "Manually Add minimum collection height must be fixed at 44 points"
        )

        let triggerDeviceCellSection = section(
            in: triggerAddView,
            from: "func collectionView(_ collectionView: UICollectionView, cellForItemAt",
            to: "func collectionView(_ collectionView: UICollectionView, didSelectItemAt"
        )
        require(
            triggerDeviceCellSection.contains("cell.boxView.layer.borderColor"),
            "Trigger Add selection border must target the fixed visual control"
        )
        require(
            !triggerDeviceCellSection.contains("cell.layer.borderColor"),
            "Trigger Add selection border must not target the adaptive slot"
        )

        let manuallyDeviceCellSection = section(
            in: manuallyAddView,
            from: "func collectionView(_ collectionView: UICollectionView, cellForItemAt",
            to: "func collectionView(_ collectionView: UICollectionView, didSelectItemAt"
        )
        require(
            manuallyDeviceCellSection.contains("cell.boxView.layer.borderColor"),
            "Manually Add selection border must target the fixed visual control"
        )
        require(
            !manuallyDeviceCellSection.contains("cell.layer.borderColor"),
            "Manually Add selection border must not target the adaptive slot"
        )
        require(
            manuallyAddView.contains("previewForLifting item: UIDragItem,")
                && manuallyAddView.contains("-> UITargetedDragPreview?"),
            "Manually Add must override the adaptive cell's default drag preview"
        )
        require(
            manuallyAddView.contains("cell.contentView.layoutIfNeeded()"),
            "Drag preview must resolve the fixed device box before snapshotting"
        )
        require(
            manuallyAddView.contains("parameters.backgroundColor = .clear"),
            "Drag preview must not add a rectangular system background"
        )
        require(
            manuallyAddView.contains(
                "parameters.visiblePath = UIBezierPath(ovalIn: cell.boxView.bounds)"
            ),
            "Drag preview must clip to the circular 44-point device box"
        )
        require(
            manuallyAddView.contains(
                "return UITargetedDragPreview(view: cell.boxView, parameters: parameters)"
            ),
            "Drag preview must snapshot the fixed 44-point device box, not the adaptive cell"
        )

        require(addView.contains("enum ContentHeightPolicy"), "Missing content height policy")
        require(addView.contains("case fixedBase"), "Missing Group fixed-base policy")
        require(addView.contains("case dynamicSelected"), "Missing Space dynamic-selected policy")
        require(
            addView.contains("private var collapsed: Bool = true"),
            "View must initialize closed"
        )
        require(
            addView.contains("static let headerHeight: CGFloat = 44"),
            "Header height must be 44"
        )
        require(
            addView.contains("static let addTypeBarHeight: CGFloat = 44"),
            "Menu height must be 44"
        )
        require(
            addView.contains("static let contentCardTopSpacing: CGFloat = 8"),
            "Card top spacing must be 8"
        )
        require(
            addView.contains("static let contentCardBottomSpacing: CGFloat = 8"),
            "Card bottom spacing must be 8"
        )
        require(
            addView.contains("static let contentCardHorizontalInset: CGFloat = 16"),
            "Card horizontal inset must be 16"
        )
        require(
            addView.contains("static let baseContentHeight: CGFloat = 160"),
            "Base content height must be 160"
        )
        require(
            addView.contains("self.collapsed ? \"arrow_up_black\" : \"arrow_down_black\""),
            "Arrow mapping must be closed-up/open-down"
        )
        require(
            addView.contains(
                "max(LayoutMetrics.baseContentHeight, manuallyAddView.preferredContentHeight)"
            ),
            "Manual multi-row content must grow above 160"
        )
        let preferredHeightSection = section(
            in: addView,
            from: "private func emitPreferredHeightIfNeeded()",
            to: "private func updateContentHeightConstraints()"
        )
        require(
            preferredHeightSection.contains("contentHeight = LayoutMetrics.headerHeight"),
            "Closed content height must be the fixed 44-point header"
        )
        require(
            preferredHeightSection.contains(
                "contentHeight = LayoutMetrics.headerHeight + bodyHeight"
            ),
            "Expanded content height must include only header and body"
        )
        require(
            !preferredHeightSection.contains("safeAreaInsets.bottom"),
            "Public add view must not include its own safe area in reported content height"
        )
        require(
            !addView.contains("override func safeAreaInsetsDidChange()"),
            "Public add view must not depend on its own safe-area lifecycle"
        )
        require(
            addView.contains("var contentHeightChanged: ((CGFloat) -> Void)?"),
            "Height callback must explicitly report content height"
        )
        require(!addView.contains("SCRXFrom"), "Parent add view must not retain SCRXFrom")
        require(!addView.contains("SCRYFrom"), "Parent add view must not retain SCRYFrom")

        require(
            sequenceController.contains("deviceAddView.contentHeightPolicy = .fixedBase"),
            "Sequence controller must select fixedBase"
        )
        require(
            zoneController.contains("deviceAddView.contentHeightPolicy = .fixedBase"),
            "Group zone controller must select fixedBase"
        )
        require(
            spaceController.contains("deviceAddView.contentHeightPolicy = .dynamicSelected"),
            "Space controller must select dynamicSelected"
        )

        for (name, controller) in [
            ("Sequence", sequenceController),
            ("Group zone", zoneController),
        ] {
            require(
                controller.contains("private var deviceAddContentHeight: CGFloat = 0"),
                "\(name) controller must cache the latest content height"
            )
            require(
                controller.contains(
                    "max(contentHeight, 44) + view.safeAreaInsets.bottom"
                ),
                "\(name) controller must add its own safe-area bottom"
            )
            require(
                controller.contains("override func viewSafeAreaInsetsDidChange()"),
                "\(name) controller must resync when safe area changes"
            )
            require(
                controller.contains("override func viewWillLayoutSubviews()"),
                "\(name) controller must resync before the first container layout"
            )
            require(
                controller.contains("deviceAddView.contentHeightChanged ="),
                "\(name) controller must consume content-height callbacks"
            )
        }

        require(
            spaceController.contains("max(contentHeight, 44)"),
            "Space controller must clamp content height to fixed 44"
        )
        let spaceHeightSection = section(
            in: spaceController,
            from: "private func updateDeviceAddViewHeight",
            to: "func addZone()"
        )
        require(
            !spaceHeightSection.contains("safeAreaInsets.bottom"),
            "Space controller must not duplicate its existing safe-area offset"
        )
        require(
            spaceController.contains("deviceAddView.contentHeightChanged ="),
            "Space controller must consume the content-height callback semantics"
        )

        let makeOptions = section(
            in: spaceMore,
            from: "private func makeOptions()",
            to: "private func reloadOptions()"
        )
        require(!makeOptions.contains(".triggerZone"), "Space Trigger Zone must remain hidden")

        require(stepView.contains("enum LayoutStyle"), "Missing reusable guide layout style")
        require(stepView.contains("case equalColumns"), "Missing equal-column guide layout")
        require(
            stepView.contains("stackView.distribution = .fillEqually"),
            "Equal-column guide must distribute steps equally"
        )
        require(
            stepView.contains("static let equalColumnSpacing: CGFloat = 16"),
            "Equal-column spacing must be 16"
        )
        require(
            stepView.contains("static let equalColumnHorizontalInset: CGFloat = 16"),
            "Equal-column outer inset must be 16"
        )
        require(
            stepView.contains("static let equalColumnTopInset: CGFloat = 40"),
            "Equal-column step images must stay 40 points below the content-card top"
        )
        let stepConstraintSection = section(
            in: stepView,
            from: "private func constrainStackView()",
            to: "private func buildSteps()"
        )
        require(
            stepConstraintSection.contains(
                "make.top.equalToSuperview().offset(LayoutMetrics.equalColumnTopInset)"
            ),
            "Equal-column steps must use the fixed top anchor"
        )
        let equalColumnConstraintSection = section(
            in: stepConstraintSection,
            from: "case .equalColumns:",
            to: "}"
        )
        require(
            !equalColumnConstraintSection.contains("centerY"),
            "Equal-column steps must not move with vertically centered text height"
        )
        require(
            stepView.contains("backgroundColor = .clear"),
            "Equal-column guide must be transparent"
        )
        require(
            stepView.contains("layer.cornerRadius = 0"),
            "Equal-column guide must not draw a second rounded card"
        )
        require(
            stepView.contains("constrainsWidth: layoutStyle == .legacy"),
            "Equal-column steps must not keep legacy width limits"
        )
        require(
            stepView.contains("static let equalColumnTitleSpacing: CGFloat = 8"),
            "Equal-column guide title spacing must be a fixed 8 points"
        )
        require(
            stepView.contains(
                "layoutStyle == .equalColumns ? LayoutMetrics.equalColumnTitleSpacing : SCRYFrom(8)"
            ),
            "Equal-column guide must select fixed title spacing without changing legacy scaling"
        )
        require(
            stepView.contains("titleSpacing: titleSpacing"),
            "Guide must pass the layout-specific title spacing into each step"
        )
        require(
            stepView.contains(
                "make.top.equalTo(imageView.snp.bottom).offset(titleSpacing)"
            ),
            "Step title constraint must consume the injected fixed spacing"
        )
        require(
            !stepView.contains(
                "make.top.equalTo(imageView.snp.bottom).offset(SCRYFrom(8))"
            ),
            "Step title constraint must not call SCRYFrom directly"
        )
        require(
            quickAddView.contains("layoutStyle: .equalColumns"),
            "Quick Add guide must use equal columns"
        )
        require(
            quickAddView.contains("var menuWidth: CGFloat = isIPad ? 300 : 256"),
            "Mutable Quick Add menu width must retain CGFloat typing"
        )
        require(
            quickAddView.contains("private let topContentInset: CGFloat = 8"),
            "Quick Add top inset must retain CGFloat typing"
        )
        require(
            triggerAddView.contains("layoutStyle: .equalColumns"),
            "Trigger Add guide must use equal columns"
        )
        require(
            triggerAddView.contains("let menuWidth: CGFloat = usesCompactFilterMenu"),
            "Trigger Add menu width must retain CGFloat typing"
        )
        require(
            triggerAddView.contains("private let topContentInset: CGFloat = 8"),
            "Trigger Add top inset must retain CGFloat typing"
        )
        require(
            triggerAddView.contains("private let collectionViewHeight: CGFloat = 68"),
            "Trigger Add collection height must be a fixed 68 points"
        )
        require(
            triggerAddView.contains(
                "let extraHintHeight: CGFloat = usesGroupFilterLayout ? 26 : 0"
            ),
            "Trigger Add hint height must retain CGFloat typing"
        )
        require(
            triggerAddView.contains(
                "return topContentInset + 66 + extraHintHeight + collectionViewHeight"
            ),
            "Trigger Add preferred height must use the same 68-point collection height"
        )
        let triggerCollectionConstraints = section(
            in: triggerAddView,
            from: "collectionView.snp.makeConstraints",
            to: "noDevicesLabel ="
        )
        require(
            triggerCollectionConstraints.contains(
                "make.height.equalTo(collectionViewHeight)"
            ),
            "Trigger Add collection constraint must use the shared 68-point height"
        )
        let triggerNoDevicesConstraints = section(
            in: triggerAddView,
            from: "noDevicesLabel.snp.makeConstraints",
            to: "pageControl ="
        )
        require(
            triggerNoDevicesConstraints.contains("make.center.equalToSuperview()"),
            "Trigger Add No devices must center in the whole adding content view"
        )
        require(
            !triggerNoDevicesConstraints.contains("collectionView"),
            "Trigger Add No devices must not center in the collection view"
        )
        require(
            manuallyAddView.contains("layoutStyle: .equalColumns"),
            "Manually Add guide must use equal columns"
        )
        require(
            manuallyAddView.contains("let menuWidth: CGFloat = usesCompactFilterMenu"),
            "Manually Add menu width must retain CGFloat typing"
        )
        require(
            manuallyAddView.contains("private let topContentInset: CGFloat = 8"),
            "Manually Add top inset must retain CGFloat typing"
        )
        for (name, source) in [
            ("Trigger Add", triggerAddView),
            ("Manually Add", manuallyAddView),
        ] {
            let reloadSection = section(
                in: source,
                from: "func reloadData(devices:",
                to: "func setGuideVisible"
            )
            require(
                reloadSection.contains("updateNoDevicesLabelVisibility()"),
                "\(name) reload must preserve guide-controlled empty-state visibility"
            )

            let guideVisibilitySection = section(
                in: source,
                from: "func setGuideVisible",
                to: "@objc private func addTypeSelectAction"
            )
            require(
                guideVisibilitySection.contains("updateNoDevicesLabelVisibility()"),
                "\(name) guide changes must update the same empty-state visibility"
            )
            require(
                source.contains(
                    "noDevicesLabel.isHidden = !guideContentView.isHidden || !devices.isEmpty"
                ),
                "\(name) must show No devices only when the guide is hidden and devices are empty"
            )
        }
        let manuallyNoDevicesConstraints = section(
            in: manuallyAddView,
            from: "noDevicesLabel.snp.makeConstraints",
            to: "pageControl ="
        )
        require(
            manuallyNoDevicesConstraints.contains("make.center.equalToSuperview()"),
            "Manually Add No devices must center in the whole adding content view"
        )
        require(
            !manuallyNoDevicesConstraints.contains("collectionView"),
            "Manually Add No devices must not center in the collection view"
        )
        let quickStartConstraints = section(
            in: quickAddView,
            from: "startBtn.snp.makeConstraints",
            to: "//        pauseBtn"
        )
        require(
            quickStartConstraints.contains("make.centerY.equalToSuperview()"),
            "Quick Add Start and Pause must center vertically in the adding content view"
        )
        require(
            !quickStartConstraints.contains("make.top"),
            "Quick Add Start and Pause must not retain top-chain positioning"
        )
        let quickStopConstraints = section(
            in: quickAddView,
            from: "stopBtn.snp.makeConstraints",
            to: "addStateLabel ="
        )
        require(
            quickStopConstraints.contains("make.centerY.equalTo(startBtn)"),
            "Quick Add Stop must share the Start and Pause center line"
        )
        let quickStateLabelConstraints = section(
            in: quickAddView,
            from: "addStateLabel.snp.makeConstraints",
            to: "messageLabel ="
        )
        require(
            quickStateLabelConstraints.contains("make.centerY.equalTo(startBtn)"),
            "Quick Add state text must share the Start and Pause center line"
        )
        for (name, source) in [
            ("Quick Add", quickAddView),
            ("Trigger Add", triggerAddView),
            ("Manually Add", manuallyAddView),
        ] {
            let guideConstraints = section(
                in: source,
                from: "guideContentView.addSubview(guideView)",
                to: "configureDefault"
            )
            require(
                guideConstraints.contains("make.edges.equalToSuperview()"),
                "\(name) guide must fill the content card so the 40-point top anchor is absolute"
            )
            require(
                !guideConstraints.contains("make.top.equalTo(12)"),
                "\(name) guide must not retain the old nested vertical inset"
            )
        }
        for (name, source) in [
            ("Parent Add", addView),
            ("Quick Add", quickAddView),
            ("Trigger Add", triggerAddView),
            ("Manually Add", manuallyAddView),
            ("Add Device Cell", addDeviceCell),
        ] {
            require(!source.contains("SCRXFrom"), "\(name) must not retain SCRXFrom")
            require(!source.contains("SCRYFrom"), "\(name) must not retain SCRYFrom")
        }

        print("GroupPathSequenceDeviceAddViewContractTests layout passed")
    }

    private static func source(_ root: String, _ relativePath: String) throws -> String {
        try String(contentsOfFile: "\(root)/\(relativePath)", encoding: .utf8)
    }

    private static func section(in source: String, from start: String, to end: String) -> String {
        guard let startRange = source.range(of: start) else {
            fatalError("Missing source marker: \(start)")
        }
        let remainder = source[startRange.lowerBound...]
        guard let endRange = remainder.range(of: end) else {
            fatalError("Missing source marker: \(end)")
        }
        return String(remainder[..<endRange.lowerBound])
    }

    private static func require(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) {
        precondition(condition(), message)
    }
}
