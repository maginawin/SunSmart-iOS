import Foundation

@main
struct SiteEntryTimeZoneSyncContractTests {
    static func main() throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 9 else {
            fatalError(
                "Expected overlay, Edit status view, two localizations, Site controller, project, script, and warning asset"
            )
        }

        let overlay = try read(arguments[1])
        let editStatusView = try read(arguments[2])
        let english = try read(arguments[3])
        let simplifiedChinese = try read(arguments[4])
        let siteController = try read(arguments[5])
        let project = try read(arguments[6])
        let checkScript = try read(arguments[7])
        let warningAsset = try read(arguments[8])

        require(
            overlay.contains("final class SiteEntryTimeZoneSyncOverlay: UIView") &&
                overlay.contains("case checking") &&
                overlay.contains("case gatewaysNeedSync(SiteEntryTimeZoneResult)") &&
                overlay.contains("case result(SiteEntryTimeZoneResult)"),
            "Site Entry must use a dedicated three-state summary overlay"
        )
        require(
            overlay.contains("var onGotIt: (() -> Void)?") &&
                overlay.contains("var onLater: (() -> Void)?") &&
                overlay.contains("var onReviewSync: (() -> Void)?") &&
                overlay.contains("func showChecking(in container: UIView)") &&
                overlay.contains("func showResult(_ result: SiteEntryTimeZoneResult)") &&
                overlay.contains("func dismiss()"),
            "The summary overlay must expose the approved lifecycle and actions"
        )
        require(
            overlay.contains("if result.site == .failedToUpdateServer") &&
                overlay.contains("case .pending:") &&
                overlay.contains("update(state: .gatewaysNeedSync(result))") &&
                overlay.contains("case .noGateways, .inSync:") &&
                overlay.contains("update(state: .result(result))"),
            "Pending Gateways must show Review actions while Site failure stays dismissible"
        )
        require(
            overlay.contains("UIColor.black.withAlphaComponent(0.4)") &&
                overlay.contains("resultCardView.layer.cornerRadius = SCRYFrom(24)") &&
                overlay.contains("make.width.equalTo(SCRXFrom(343)).priority(.high)") &&
                overlay.contains("make.height.greaterThanOrEqualTo(SCRYFrom(296))") &&
                overlay.contains("make.center.equalToSuperview()"),
            "The result overlay must preserve the centered 343 by 296 Figma baseline"
        )
        require(
            overlay.contains("UIImage(named: \"site_entry_sync_success\")") &&
                overlay.contains("UIImage(named: \"site_entry_sync_warning\")") &&
                overlay.contains("RGB(225, 113, 0)") &&
                overlay.contains("case .noGateways, .inSync:") &&
                overlay.contains("gatewayMessage = \"site_entry_sync_no_gateways\".localizedString"),
            "Gateway summary must use Figma success/warning treatments and one no-sync wording"
        )
        require(
            overlay.contains("gotItButton.isHidden = needsSync") &&
                overlay.contains("laterButton.isHidden = !needsSync") &&
                overlay.contains("reviewSyncButton.isHidden = !needsSync") &&
                overlay.contains("guard case .gatewaysNeedSync = state else { return }"),
            "Only a pending Gateway summary may expose LATER and REVIEW SYNC"
        )

        let requiredKeys = [
            "site_entry_sync_status_title",
            "site_entry_sync_site_time_zone",
            "site_entry_sync_already_in_sync_with_server",
            "site_entry_sync_updated_from_server",
            "site_entry_sync_updated_to_server",
            "site_entry_sync_failed_to_update_server",
            "site_entry_sync_gateway_time_zone",
            "site_entry_sync_no_gateways",
            "site_entry_sync_gateways_need_sync",
            "site_entry_sync_later",
            "site_entry_sync_review_sync",
            "site_entry_sync_got_it"
        ]
        for key in requiredKeys {
            let declaration = "\"\(key)\" ="
            require(
                occurrences(of: declaration, in: english) == 1 &&
                    occurrences(of: declaration, in: simplifiedChinese) == 1,
                "Both localizations must define \(key) exactly once"
            )
        }
        require(
            english.contains("\"site_entry_sync_status_title\" = \"Sync status\";") &&
                simplifiedChinese.contains("\"site_entry_sync_status_title\" = \"同步状态\";"),
            "Sync status title must match the approved summary wording"
        )

        require(
            siteController.contains("private lazy var entrySyncOverlay: SiteEntryTimeZoneSyncOverlay") &&
                siteController.contains("overlay.onGotIt") &&
                siteController.contains("overlay.onLater") &&
                siteController.contains("overlay.onReviewSync"),
            "Site Entry must own the dedicated summary overlay and all actions"
        )
        let presentationFlow = section(
            siteController,
            from: "private func presentPendingEntryTimeZoneSyncStatusIfPossible()",
            to: "private func applyUploadedEntryGatewayReviewContext("
        )
        require(
            presentationFlow.contains("entrySyncOverlay.showChecking(in: container)") &&
                presentationFlow.contains("await entrySyncCoordinator.run(presentation.decision)") &&
                presentationFlow.contains("entrySyncOverlay.showResult(entryResult)") &&
                !presentationFlow.contains("SiteGatewayCloudTimeZoneSessionCoordinator") &&
                !presentationFlow.contains("gateway/datetime/update") &&
                !presentationFlow.contains("SiteGatewayCloudTimeZoneAPIClient"),
            "Site Entry may arbitrate and present only; it must not automatically update Gateways"
        )
        require(
            siteController.contains("private func handleEntrySyncReview()") &&
                appearsInOrder(
                    [
                        "private func handleEntrySyncReview()",
                        "finishEntrySyncOverlay()",
                        "showSyncGatewaysPage()"
                    ],
                    in: siteController
                ),
            "REVIEW SYNC must dismiss the overlay before routing to Sync Gateways"
        )
        require(
            siteController.contains("applyUploadedEntryGatewayReviewContext(") &&
                siteController.contains("SiteGatewayTimeZoneReviewContext(") &&
                siteController.contains("targetTimeZone: result.timezone") &&
                siteController.contains("failedGatewayIDs: pendingIDs"),
            "App-to-server success must preserve its final timezone for Review Sync"
        )
        require(
            !siteController.contains("private lazy var gatewayEntrySyncSession") &&
                !siteController.contains("private lazy var entryTimeZoneSyncStatusView"),
            "Site Entry must not retain the automatic Gateway session or Edit detail view"
        )

        require(
            occurrences(of: "SiteEntryTimeZoneSyncOverlay.swift in Sources", in: project) == 8,
            "The overlay must be included in all four brand targets"
        )
        require(
            checkScript.contains("SiteEntryTimeZoneSyncOverlay.swift") &&
                checkScript.contains("SiteTimeZoneSyncStatusView.swift"),
            "The focused script must cover the Entry overlay and the preserved Edit status view"
        )
        require(
            warningAsset.contains("site_entry_sync_warning.svg") &&
                warningAsset.contains("preserves-vector-representation"),
            "The warning asset must preserve the Figma vector"
        )

        let shadowSection = section(
            editStatusView,
            from: "private func configureResultShadows()",
            to: "private func configureResultContentScrollView()"
        )
        require(
            shadowSection.contains(
                "insertSubview(shadowView, belowSubview: bottomSafeAreaBackgroundView)"
            ),
            "The existing Edit result shadow fix must remain intact"
        )

        print("SiteEntryTimeZoneSyncContractTests passed")
    }

    private static func read(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    private static func section(
        _ source: String,
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

    private static func occurrences(of needle: String, in text: String) -> Int {
        guard !needle.isEmpty else { return 0 }
        var count = 0
        var range = text.startIndex..<text.endIndex
        while let match = text.range(of: needle, range: range) {
            count += 1
            range = match.upperBound..<text.endIndex
        }
        return count
    }

    private static func appearsInOrder(
        _ needles: [String],
        in text: String
    ) -> Bool {
        var lowerBound = text.startIndex
        for needle in needles {
            guard let range = text.range(
                of: needle,
                range: lowerBound..<text.endIndex
            ) else {
                return false
            }
            lowerBound = range.upperBound
        }
        return true
    }

    private static func require(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) {
        guard condition() else { fatalError(message) }
    }
}
