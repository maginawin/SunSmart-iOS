import Foundation

@main
struct SiteGatewayCloudTimeZoneUIContractTests {

    static func main() throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 4 else {
            fatalError("Expected gateway status view and two localization paths")
        }

        let viewPath = arguments[1]
        require(
            FileManager.default.fileExists(atPath: viewPath),
            "Gateway time zone status view must exist"
        )

        let view = try String(contentsOfFile: viewPath, encoding: .utf8)
        let english = try String(contentsOfFile: arguments[2], encoding: .utf8)
        let simplifiedChinese = try String(contentsOfFile: arguments[3], encoding: .utf8)

        let gatewayCardSetup = sourceSection(
            in: view,
            from: "private func setupGatewayCard()",
            to: "private func setupEmptyState()"
        )
        let emptyStateSetup = sourceSection(
            in: view,
            from: "private func setupEmptyState()",
            to: "private func setupFailureSummary()"
        )
        let heightMeasurement = sourceSection(
            in: view,
            from: "private func updateMeasuredHeightsIfNeeded(width: CGFloat)",
            to: "private func fittingHeight(of view: UIView"
        )
        let contentSizeCategoryUpdate = sourceSection(
            in: view,
            from: "override func traitCollectionDidChange(",
            to: "func update(_ state:"
        )
        requireAll([
            (
                appearsInOrder(
                    [
                        "gatewayHeaderView.addSubview(gatewayHeaderLabel)",
                        "gatewayHeaderView.addSubview(gatewayCountLabel)",
                        "gatewayHeaderLabel.snp.makeConstraints",
                        "make.right.lessThanOrEqualTo(gatewayCountLabel.snp.left)"
                    ],
                    in: gatewayCardSetup
                ),
                "Both Gateway header labels must share their parent before activating a cross-label constraint"
            ),
            (
                heightMeasurement.contains("sizingCell.preferredHeight(") &&
                    heightMeasurement.contains(
                        "items.prefix(Self.maximumVisibleGatewayCount)"
                    ) &&
                    !heightMeasurement.contains("SCRYFrom(176)") &&
                    !heightMeasurement.contains("tableView.rectForRow") &&
                    !heightMeasurement.contains("tableView.contentSize"),
                "Preferred height must independently size up to three real rows without a fixed three-row floor or UITableView cache data"
            ),
            (
                contentSizeCategoryUpdate.contains("tableView.reloadData()") &&
                    contentSizeCategoryUpdate.contains("tableView.setNeedsLayout()") &&
                    contentSizeCategoryUpdate.contains("needsHeightMeasurement = true"),
                "A content-size category change must invalidate both UITableView rows and outer height measurement"
            ),
            (
                view.contains("private var gatewayHeaderHeightConstraint: Constraint!") &&
                    heightMeasurement.contains(
                        "temporarilyDeactivating: gatewayHeaderHeightConstraint"
                    ) &&
                    heightMeasurement.contains(
                        "gatewayHeaderHeightConstraint.update(offset: headerHeight)"
                    ) &&
                    view.contains("heightConstraint.deactivate()") &&
                    view.contains("defer { heightConstraint.activate() }"),
                "Measured header height must bind back to layout without its old exact height contaminating fitting"
            )
        ])

        let presentationUpdate = sourceSection(
            in: view,
            from: "func update(_ presentation: SiteTimeZoneGatewayPresentation)",
            to: "func update(_ state: SiteGatewayCloudTimeZoneBatchState)"
        )
        require(
            view.contains("final class SiteEntryGatewayTimeZoneStatusView: UIView") &&
                presentationUpdate.contains("case .notStarted:") &&
                presentationUpdate.contains("case .unavailable:") &&
                presentationUpdate.contains("case .batch(let state):") &&
                presentationUpdate.contains("update(state)"),
            "Gateway status view must consume the shared presentation and delegate batches to the existing renderer"
        )
        require(
            presentationUpdate.contains("\"site_time_zone_gateway_check_unavailable_title\".localizedString") &&
                presentationUpdate.contains("\"site_time_zone_gateway_check_unavailable_message\".localizedString") &&
                presentationUpdate.contains("configurePresentation(") &&
                !presentationUpdate.contains("SiteGatewayCloudTimeZoneItem("),
            "Unavailable must render its dedicated failure copy without constructing a fake Gateway row"
        )
        require(
            presentationUpdate.contains("case .notStarted:") &&
                presentationUpdate.contains("resetForNotStarted()") &&
                !presentationUpdate.contains("case .notStarted:\n            return"),
            "Not-started Gateway state must clear the child renderer instead of leaving its previous required constraint chain active"
        )
        let notStartedReset = sourceSection(
            in: view,
            from: "private func resetForNotStarted()",
            to: "private func configurePresentation("
        )
        require(
            notStartedReset.contains("deactivatePresentationConstraints()") &&
                notStartedReset.contains("gatewayCardView.isHidden = true") &&
                notStartedReset.contains("emptyStateView.isHidden = true") &&
                notStartedReset.contains("failureSummaryCardView.isHidden = true") &&
                notStartedReset.contains("tableView.visibleCells") &&
                notStartedReset.contains("cell.stopLoadingAnimation()") &&
                notStartedReset.contains("sizingCell.stopLoadingAnimation()") &&
                notStartedReset.contains("items.removeAll()") &&
                notStartedReset.contains("tableView.reloadData()"),
            "Not-started must hide every internal presentation and clear all row/loading state"
        )
        let presentationConstraints = sourceSection(
            in: view,
            from: "private func deactivatePresentationConstraints()",
            to: "private func resetForNotStarted()"
        )
        for constraintName in [
            "gatewayCardTopConstraint",
            "gatewayCardBottomConstraint",
            "emptyStateTopConstraint",
            "emptyStateBottomConstraint",
            "failureSummaryTopConstraint",
            "failureSummaryBottomConstraint"
        ] {
            require(
                presentationConstraints.contains(constraintName),
                "Hidden presentation must deactivate \(constraintName)"
            )
        }
        require(
            presentationConstraints.contains(".forEach { $0?.deactivate() }") &&
                view.contains("private func configurePresentation(") &&
                sourceSection(
                    in: view,
                    from: "private func configurePresentation(",
                    to: "private func updateMeasuredHeightsIfNeeded("
                ).contains("deactivatePresentationConstraints()"),
            "Every hidden/visible transition must first deactivate all six presentation constraints before activating one valid chain"
        )
        require(
            view.contains("UITableView") &&
                view.contains("UITableViewDataSource") &&
                view.contains("private static let maximumVisibleGatewayCount = 3") &&
                view.contains("items.count > Self.maximumVisibleGatewayCount") &&
                view.contains("tableView.isScrollEnabled = shouldScroll") &&
                view.contains("tableView.showsVerticalScrollIndicator = shouldScroll") &&
                view.contains("if !shouldScroll {") &&
                view.contains("tableView.setContentOffset(.zero, animated: false)") &&
                view.contains("items = state.items") &&
                view.contains("tableView.reloadData()"),
            "Gateway rows must keep batch order, scroll only above three rows, and reset stale offsets when scrolling collapses"
        )
        require(
            view.contains("site_entry_sync_gateways_header") &&
                view.contains("String(state.authorizedCount)") &&
                view.contains("make.height.greaterThanOrEqualTo(SCRYFrom(44))") &&
                view.contains("make.height.equalTo(0.5)"),
            "Gateway card must keep its count, minimum 44pt header baseline, and hairlines"
        )
        require(
            view.contains("tableView.rowHeight = UITableView.automaticDimension") &&
                view.contains("tableView.estimatedRowHeight = SCRYFrom(44)"),
            "Gateway rows must use self-sizing heights with the 44pt Figma baseline as their estimate"
        )
        require(
            view.contains("case .pushing:") &&
                view.contains("case .synced:") &&
                view.contains("case .failed:") &&
                view.contains("time-zone-sync-status-gateway") &&
                view.contains("gateway_sync_tz_fail") &&
                view.contains("site_entry_sync_loading") &&
                view.contains("site_entry_sync_success"),
            "All Gateway states must use their approved assets"
        )
        require(
            view.contains("siteEntrySyncLoading") &&
                view.contains("startLoadingAnimation()") &&
                view.contains("stopLoadingAnimation()") &&
                view.contains("prepareForReuse") &&
                view.contains("removeAnimation(forKey: \"siteEntrySyncLoading\")"),
            "Reusable cells must stop the pushing animation when state changes or cells are reused"
        )
        requireAll([
            (
                view.contains("private let emptyHeaderLabel = UILabel()") &&
                    view.contains("private let emptyContentView = UIView()") &&
                    view.contains("private let emptyIconBackgroundView = UIView()"),
                "No-gateways state must expose the Figma header, row, and icon-container structure"
            ),
            (
                emptyStateSetup.contains("\"site_entry_sync_gateways_header\".localizedString") &&
                    emptyStateSetup.contains("\"site_no_gateways\".localizedString") &&
                    emptyStateSetup.contains("\"site_no_gateways_sync_needed\".localizedString") &&
                    emptyStateSetup.contains("emptyTitleLabel.textAlignment = .left") &&
                    emptyStateSetup.contains("emptyMessageLabel.textAlignment = .left") &&
                    emptyStateSetup.contains("emptyTitleLabel.numberOfLines = 0") &&
                    emptyStateSetup.contains("emptyMessageLabel.numberOfLines = 0"),
                "No-gateways copy must use the approved Edit Site localizations and left-aligned Dynamic Type labels"
            ),
            (
                emptyStateSetup.contains("emptyIconBackgroundView.backgroundColor = RGB(148, 163, 184, 0.1)") &&
                    emptyStateSetup.contains("emptyIconBackgroundView.layer.cornerRadius = SCRYFrom(16)") &&
                    emptyStateSetup.contains("make.size.equalTo(SCRYFrom(32))") &&
                    emptyStateSetup.contains("make.size.equalTo(SCRYFrom(16))") &&
                    emptyStateSetup.contains("make.left.equalTo(emptyIconBackgroundView.snp.right).offset(SCRXFrom(12))") &&
                    emptyStateSetup.contains("emptyIconImageView.image = UIImage(named: \"time-zone-sync-status-gateway\")") &&
                    !emptyStateSetup.contains("withTintColor"),
                "No-gateways row must reuse the exact gradient asset inside the 32pt muted icon circle with a 12pt text gap"
            ),
            (
                emptyStateSetup.contains("make.top.equalToSuperview().offset(SCRYFrom(8))") &&
                    emptyStateSetup.contains("make.left.right.equalToSuperview().inset(SCRXFrom(16))") &&
                    emptyStateSetup.contains("make.height.greaterThanOrEqualTo(SCRYFrom(21))") &&
                    emptyStateSetup.contains("make.height.greaterThanOrEqualTo(SCRYFrom(20))") &&
                    emptyStateSetup.contains("make.height.greaterThanOrEqualTo(SCRYFrom(16))") &&
                    !emptyStateSetup.contains("make.height.greaterThanOrEqualTo(SCRYFrom(152))") &&
                    !emptyStateSetup.contains("make.centerX.equalToSuperview()"),
                "No-gateways card must follow the compact Figma insets and line boxes without the old centered 152pt layout"
            ),
            (
                emptyStateSetup.contains("emptyHeaderLabel.accessibilityTraits = .header") &&
                    emptyStateSetup.contains("emptyContentView.isAccessibilityElement = true") &&
                    emptyStateSetup.contains("emptyIconImageView.isAccessibilityElement = false"),
                "No-gateways Header and row must remain separately readable while the icon stays decorative"
            ),
            (
                view.contains("numberOfLines = 1") &&
                    view.contains("lineBreakMode = .byTruncatingTail") &&
                    view.contains("item.displayName.isEmpty ? item.requestMAC : item.displayName"),
                "Gateway row Dynamic Type truncation and MAC fallback must remain readable"
            )
        ])
        require(
            view.contains("state.failedCount == 1") &&
                view.contains("site_entry_sync_one_gateway_failed") &&
                view.contains("site_entry_sync_gateways_failed_format") &&
                view.contains("site_entry_sync_failed_guidance"),
            "Failed Gateway summary must use singular and plural copy with on-site guidance"
        )
        require(
            !view.contains("URLSession") &&
                !view.contains("SiteGatewayCloudTimeZoneAPI") &&
                !view.contains("MeshAPI"),
            "Gateway status view must not own transport behavior"
        )
        require(
            !view.contains("UIStackView") &&
                !view.contains("addArrangedSubview") &&
                view.contains("private func configurePresentation(") &&
                view.contains("gatewayCardView.isHidden = !hasGateways") &&
                view.contains("emptyStateView.isHidden = hasGateways"),
            "State changes must not hide required-height arranged subviews"
        )
        require(
            view.contains("var preferredHeight: CGFloat") &&
                view.contains("var minimumViewportHeight: CGFloat") &&
                view.contains("var onPreferredHeightChanged: (() -> Void)?") &&
                view.contains("override var intrinsicContentSize: CGSize") &&
                view.contains("invalidateIntrinsicContentSize()") &&
                view.contains("systemLayoutSizeFitting") &&
                view.contains("items.prefix(Self.maximumVisibleGatewayCount)") &&
                view.contains("abs(") &&
                view.contains("onPreferredHeightChanged?()"),
            "Gateway heights must be measured from dynamic content, capped to three preferred rows, and notify only on change"
        )
        require(
            occurrences(of: "configureDynamicFont(", in: view) >= 8 &&
                view.contains("adjustsFontForContentSizeCategory = true") &&
                !view.contains("maximumContentSizeCategory"),
            "All user-facing labels must scale through Accessibility Dynamic Type without a category cap"
        )

        let cell = sourceSection(
            in: view,
            from: "private final class GatewayTimeZoneStatusCell",
            to: "private func startLoadingAnimation()"
        )
        require(
            !cell.contains("statusImageView") &&
                cell.contains("gatewayImageView.image = UIImage(named: \"site_entry_sync_loading\")") &&
                cell.contains("gatewayImageView.image = UIImage(named: \"site_entry_sync_success\")") &&
                cell.contains("gatewayImageView.image = UIImage(named: \"gateway_sync_tz_fail_circle\")") &&
                cell.contains("nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)") &&
                cell.contains("statusLabel.setContentCompressionResistancePriority(.required, for: .horizontal)") &&
                cell.contains("make.right.lessThanOrEqualTo(statusLabel.snp.left).offset(SCRXFrom(-8))"),
            "Gateway rows must render one state icon on the left and text only on the right"
        )
        require(
            view.contains("gatewayImageView.layer.add(animation, forKey: \"siteEntrySyncLoading\")") &&
                view.contains("gatewayImageView.layer.removeAnimation(forKey: \"siteEntrySyncLoading\")") &&
                !view.contains("statusImageView.layer.add(animation") &&
                !view.contains("statusImageView.layer.removeAnimation"),
            "The left pushing icon must retain its rotation lifecycle"
        )
        let sizingPath = sourceSection(
            in: cell,
            from: "func preferredHeight(",
            to: "private func setupUI()"
        )
        require(
            sizingPath.contains("defer { stopLoadingAnimation() }") &&
                sizingPath.contains("update(item)"),
            "The off-screen sizing cell must stop any pushing animation after measurement"
        )
        require(
            occurrences(of: "make.top.greaterThanOrEqualToSuperview()", in: cell) >= 2 &&
                occurrences(of: "make.bottom.lessThanOrEqualToSuperview()", in: cell) >= 2,
            "Gateway name and status text must both participate in the cell's top and bottom self-sizing constraints"
        )
        require(
            cell.contains("make.top.greaterThanOrEqualToSuperview().offset(SCRYFrom(14))") &&
                cell.contains("make.bottom.lessThanOrEqualToSuperview().offset(SCRYFrom(-14))"),
            "A fixed-size Gateway icon must preserve the 44pt minimum row baseline while text may grow beyond it"
        )
        require(
            !gatewayCardSetup.contains("SCRYFrom(176)") &&
                !view.contains("make.height.greaterThanOrEqualTo(SCRYFrom(96))") &&
                !view.contains("private var failureSummaryHeightConstraint") &&
                heightMeasurement.contains("let gatewayCardHeight = headerHeight + preferredRowsHeight") &&
                heightMeasurement.contains("let failureHeight = ceil(") &&
                heightMeasurement.contains(
                    "fittingHeight(of: failureSummaryCardView, width: width)"
                ) &&
                !heightMeasurement.contains("SCRYFrom(96)") &&
                heightMeasurement.contains("let emptyHeight = fittingHeight(of: emptyStateView, width: width)") &&
                heightMeasurement.contains("newPreferredHeight = emptyHeight") &&
                !heightMeasurement.contains("SCRYFrom(152)") &&
                !view.contains("make.height.greaterThanOrEqualTo(SCRYFrom(152))") &&
                view.contains("gatewayHeaderHeightConstraint"),
            "Gateway, no-gateways, and failure cards must all converge to their measured content"
        )
        let failureSummarySetup = sourceSection(
            in: view,
            from: "private func setupFailureSummary()",
            to: "private func deactivatePresentationConstraints()"
        )
        let failureMessageConstraints = sourceSection(
            in: failureSummarySetup,
            from: "failureMessageLabel.snp.makeConstraints",
            to: "failureSummaryCardView.isAccessibilityElement"
        )
        require(
            view.contains("private static let failureTextVerticalInset: CGFloat = 15") &&
                occurrences(
                    of: "offset(SCRYFrom(Self.failureTextVerticalInset))",
                    in: failureSummarySetup
                ) == 1 &&
                occurrences(
                    of: "inset(SCRYFrom(Self.failureTextVerticalInset))",
                    in: failureSummarySetup
                ) == 1 &&
                failureSummarySetup.contains(
                    "make.bottom.equalToSuperview().inset(SCRYFrom(Self.failureTextVerticalInset))"
                ) &&
                !failureMessageConstraints.contains("make.bottom.lessThanOrEqualToSuperview()"),
            "Failure copy must close its natural-height chain with equal 15pt top and bottom insets"
        )
        require(
            view.contains("override func layoutSubviews()") &&
                view.contains("override func traitCollectionDidChange(") &&
                view.contains("preferredContentSizeCategory") &&
                view.contains("let normalizedPreferredHeight = ceil(") &&
                view.contains("let normalizedMinimumViewportHeight = ceil(") &&
                view.contains("abs(normalizedPreferredHeight - measuredPreferredHeight)"),
            "Content-size category and effective-width changes must trigger guarded height remeasurement"
        )
        require(
            view.contains("isAccessibilityElement = true") &&
                view.contains("accessibilityLabel = item.displayName.isEmpty ? item.requestMAC : item.displayName") &&
                view.contains("accessibilityValue = statusLabel.text") &&
                view.contains("nameLabel.isAccessibilityElement = false") &&
                view.contains("statusLabel.isAccessibilityElement = false") &&
                occurrences(of: "isAccessibilityElement = false", in: view) >= 3 &&
                view.contains("accessibilityTraits = .header"),
            "Gateway cells must expose name and state to VoiceOver while images remain decorative"
        )

        let expectedLocalizations: [(String, String)] = [
            ("site_entry_sync_status_title", "Sync status"),
            ("site_entry_sync_gateways_header", "GATEWAYS"),
            ("site_entry_sync_gateway_pushing", "Pushing…"),
            ("site_entry_sync_gateway_synced", "Synced"),
            ("site_entry_sync_gateway_failed", "Failed"),
            ("site_entry_sync_no_gateways_title", "No gateways"),
            ("site_entry_sync_no_gateways_message", "No gateways configured - no sync needed."),
            ("site_no_gateways", "No gateways"),
            ("site_no_gateways_sync_needed", "No gateways configured — no sync needed."),
            ("site_entry_sync_one_gateway_failed", "1 gateway failed"),
            ("site_entry_sync_gateways_failed_format", "%d gateways failed"),
            ("site_entry_sync_failed_guidance", "Sync on-site via Bluetooth to complete."),
            ("site_entry_sync_done", "DONE")
        ]

        for (key, englishValue) in expectedLocalizations {
            let declaration = "\"\(key)\" ="
            require(
                occurrences(of: declaration, in: english) == 1,
                "English localization must define \(key) exactly once"
            )
            require(
                occurrences(of: declaration, in: simplifiedChinese) == 1,
                "Simplified Chinese localization must define \(key) exactly once"
            )
            require(
                english.contains("\"\(key)\" = \"\(englishValue)\";"),
                "English localization must keep the approved \(key) copy"
            )
        }

        let unavailableLocalizations: [(String, String, String)] = [
            (
                "site_time_zone_gateway_check_unavailable_title",
                "Unable to check gateways",
                "无法检查网关"
            ),
            (
                "site_time_zone_gateway_check_unavailable_message",
                "Gateway time zones could not be verified. Try again from the Site.",
                "无法验证网关时区，请稍后在场所页面重试。"
            )
        ]
        for (key, englishValue, simplifiedChineseValue) in unavailableLocalizations {
            let declaration = "\"\(key)\" ="
            require(
                occurrences(of: declaration, in: english) == 1 &&
                    english.contains("\"\(key)\" = \"\(englishValue)\";"),
                "English localization must define the approved \(key) copy exactly once"
            )
            require(
                occurrences(of: declaration, in: simplifiedChinese) == 1 &&
                    simplifiedChinese.contains("\"\(key)\" = \"\(simplifiedChineseValue)\";"),
                "Simplified Chinese localization must define the approved \(key) copy exactly once"
            )
        }

        print("SiteGatewayCloudTimeZoneUIContractTests passed")
    }

    private static func occurrences(of needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    private static func sourceSection(
        in source: String,
        from start: String,
        to end: String
    ) -> String {
        guard let startRange = source.range(of: start),
              let endRange = source.range(
                  of: end,
                  range: startRange.upperBound..<source.endIndex
              ) else {
            return ""
        }
        return String(source[startRange.lowerBound..<endRange.lowerBound])
    }

    private static func appearsInOrder(
        _ needles: [String],
        in text: String
    ) -> Bool {
        var searchStart = text.startIndex
        for needle in needles {
            guard let range = text.range(
                of: needle,
                range: searchStart..<text.endIndex
            ) else {
                return false
            }
            searchStart = range.upperBound
        }
        return true
    }

    private static func requireAll(_ checks: [(Bool, String)]) {
        let failures = checks.compactMap { condition, message in
            condition ? nil : message
        }
        require(failures.isEmpty, failures.joined(separator: "; "))
    }

    private static func require(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) {
        guard condition() else { fatalError(message) }
    }
}
