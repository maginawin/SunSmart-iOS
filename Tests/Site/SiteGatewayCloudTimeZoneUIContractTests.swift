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

        require(
            view.contains("final class SiteEntryGatewayTimeZoneStatusView: UIView") &&
                view.contains("func update(_ state: SiteGatewayCloudTimeZoneBatchState)"),
            "Gateway status view must consume only the batch state through update(_:)"
        )
        require(
            view.contains("UITableView") &&
                view.contains("UITableViewDataSource") &&
                view.contains("tableView.isScrollEnabled = true") &&
                view.contains("items = state.items") &&
                view.contains("tableView.reloadData()"),
            "Gateway rows must be a reusable scrolling list rendered in batch-state order"
        )
        require(
            view.contains("site_entry_sync_gateways_header") &&
                view.contains("String(state.authorizedCount)") &&
                view.contains("make.height.equalTo(SCRYFrom(44))") &&
                view.contains("make.height.equalTo(0.5)"),
            "Gateway card must keep its fixed header, count, 44pt rows, and hairlines"
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
        require(
            view.contains("site_entry_sync_no_gateways_title") &&
                view.contains("site_entry_sync_no_gateways_message") &&
                view.contains("make.size.equalTo(SCRYFrom(32))") &&
                view.contains("numberOfLines = 1") &&
                view.contains("lineBreakMode = .byTruncatingTail") &&
                view.contains("item.displayName.isEmpty ? item.requestMAC : item.displayName"),
            "Empty state, Dynamic Type truncation, and MAC fallback must remain readable"
        )
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
                view.contains("override var intrinsicContentSize: CGSize") &&
                view.contains("invalidateIntrinsicContentSize()") &&
                view.contains("make.height.equalTo(SCRYFrom(176)).priority(.high)"),
            "Task 6 must be able to obtain a preferred height while only the internal Gateway table viewport compresses"
        )
        require(
            occurrences(of: "configureDynamicFont(", in: view) >= 8 &&
                view.contains("adjustsFontForContentSizeCategory = true") &&
                view.contains("maximumContentSizeCategory = .large"),
            "All user-facing labels must scale to a bounded size that remains legible inside the fixed Figma rows and cards"
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
            ("site_entry_sync_status_title", "Time zone sync status"),
            ("site_entry_sync_gateways_header", "GATEWAYS"),
            ("site_entry_sync_gateway_pushing", "Pushing…"),
            ("site_entry_sync_gateway_synced", "Synced"),
            ("site_entry_sync_gateway_failed", "Failed"),
            ("site_entry_sync_no_gateways_title", "No gateways"),
            ("site_entry_sync_no_gateways_message", "No gateways configured - no sync needed."),
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

        print("SiteGatewayCloudTimeZoneUIContractTests passed")
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
