import Foundation

@main
struct SiteEntryTimeZoneSyncContractTests {

    static func main() throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 7 else {
            fatalError("Expected overlay, English, Simplified Chinese, Site controller, project, and warning asset paths")
        }

        let overlay = try String(contentsOfFile: arguments[1], encoding: .utf8)
        let english = try String(contentsOfFile: arguments[2], encoding: .utf8)
        let simplifiedChinese = try String(contentsOfFile: arguments[3], encoding: .utf8)
        let siteController = try String(contentsOfFile: arguments[4], encoding: .utf8)
        let warningAssetPath = arguments[6]

        require(
            overlay.contains("enum State: Equatable") &&
                overlay.contains("case checking") &&
                overlay.contains("case gatewaysNeedSync(SiteEntryTimeZoneResult)") &&
                overlay.contains("case result(SiteEntryTimeZoneResult)"),
            "Overlay must expose checking, gatewaysNeedSync, and result states"
        )
        require(
            overlay.contains("func showChecking(in container: UIView)") &&
                overlay.contains("func showResult(_ result: SiteEntryTimeZoneResult)") &&
                overlay.contains("func dismiss()") &&
                overlay.contains("var onGotIt: (() -> Void)?") &&
                overlay.contains("var onLater: (() -> Void)?") &&
                overlay.contains("var onReviewSync: (() -> Void)?"),
            "Overlay must expose its approved lifecycle API"
        )
        require(
            overlay.contains("case .pending:") &&
                overlay.contains("update(state: .gatewaysNeedSync(result))") &&
                overlay.contains("case .noGateways, .inSync:") &&
                overlay.contains("update(state: .result(result))"),
            "Pending gateways must select gatewaysNeedSync while completed summaries use result"
        )
        require(
            overlay.contains("UIColor.black.withAlphaComponent(0.4)") &&
                overlay.contains("checkingCardView.layer.cornerRadius = SCRYFrom(20)") &&
                overlay.contains("make.width.equalTo(SCRXFrom(302))") &&
                overlay.contains("make.height.equalTo(SCRYFrom(188))") &&
                overlay.contains("resultCardView.layer.cornerRadius = SCRYFrom(24)") &&
                overlay.contains("make.width.equalTo(SCRXFrom(343))") &&
                overlay.contains("make.height.equalTo(SCRYFrom(296))") &&
                overlay.contains("make.width.equalTo(SCRXFrom(313))") &&
                overlay.contains("make.center.equalToSuperview()"),
            "Overlay must use the two centered Figma card sizes and radii"
        )
        require(
            overlay.contains("UIImage(named: \"site_entry_sync_loading\")") &&
                overlay.contains("UIImage(named: \"site_entry_sync_success\")") &&
                overlay.contains("make.size.equalTo(SCRYFrom(56))") &&
                overlay.contains("make.size.equalTo(SCRYFrom(16))"),
            "Overlay must use the exact Figma loading and success assets at their designed sizes"
        )
        require(
            overlay.contains("RGB(246, 248, 255)") &&
                overlay.contains("RGB(0, 209, 124)") &&
                overlay.contains("RGB(0, 122, 85)") &&
                overlay.contains("RGB(102, 103, 171)") &&
                overlay.contains("UIColor.black.withAlphaComponent(0.03)") &&
                overlay.contains("gotItButton.backgroundColor = .clear") &&
                overlay.contains("make.height.equalTo(SCRYFrom(60))"),
            "Result cards and GOT IT button must match the Figma colors and 60pt footer"
        )
        require(
            overlay.contains("gotItButton.isHidden = state == .checking") &&
                overlay.contains("\"site_entry_sync_got_it\".localizedString") &&
                !overlay.contains("UITapGestureRecognizer"),
            "Checking must be non-dismissible and result must expose only GOT IT"
        )
        require(
            overlay.contains("let gatewaysNeedSync:") &&
                overlay.contains("case .gatewaysNeedSync:") &&
                overlay.contains("laterButton.isHidden = !gatewaysNeedSync") &&
                overlay.contains("reviewSyncButton.isHidden = !gatewaysNeedSync") &&
                overlay.contains("footerVerticalDividerView.isHidden = !gatewaysNeedSync") &&
                overlay.contains("gotItButton.isHidden = state == .checking || gatewaysNeedSync"),
            "Only gatewaysNeedSync may expose LATER and REVIEW SYNC instead of GOT IT"
        )
        require(
            overlay.contains("UIImage(named: \"site_entry_sync_warning\")") &&
                overlay.contains("RGB(225, 113, 0)") &&
                overlay.contains("laterButtonDidTap") &&
                overlay.contains("reviewSyncButtonDidTap") &&
                overlay.contains("guard case .gatewaysNeedSync = state else { return }"),
            "Gateway pending state must use the Figma warning treatment and guarded actions"
        )
        require(
            overlay.contains("UIImage(named: \"site_entry_sync_loading\")"),
            "Checking must use the exported Figma loading treatment"
        )
        require(
            !overlay.contains("SRAlertView") &&
                !overlay.contains("SiteTimeZoneSyncStatusView") &&
                !overlay.contains("MeshAPI"),
            "Entry sync must remain a dedicated read-only Site overlay"
        )

        let keys = [
            "site_entry_sync_checking_title",
            "site_entry_sync_checking_message",
            "site_entry_sync_status_title",
            "site_entry_sync_site_time_zone",
            "site_entry_sync_already_in_sync_with_server",
            "site_entry_sync_updated_from_server",
            "site_entry_sync_updated_to_server",
            "site_entry_sync_failed_to_update_server",
            "site_entry_sync_gateway_time_zone",
            "site_entry_sync_no_gateways",
            "site_entry_sync_gateways_need_sync",
            "site_entry_sync_gateways_in_sync",
            "site_entry_sync_later",
            "site_entry_sync_review_sync",
            "site_entry_sync_got_it"
        ]
        for key in keys {
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
                overlay.contains("\"\(key)\".localizedString"),
                "Overlay must consume localized key \(key)"
            )
        }
        require(
            overlay.contains("case .alreadyInSync:") &&
                overlay.contains("\"site_entry_sync_already_in_sync_with_server\".localizedString"),
            "An unchanged Site with pending Gateways must show Already in sync with server"
        )

        let warningAsset = try String(contentsOfFile: warningAssetPath, encoding: .utf8)
        require(
            warningAsset.contains("site_entry_sync_warning.svg") &&
                warningAsset.contains("preserves-vector-representation"),
            "Warning imageset must preserve and reference the exported Figma SVG"
        )

        require(
            siteController.contains("SiteEntryTimeZoneSyncCoordinator") &&
                siteController.contains("SiteEntryTimeZoneSyncOverlay") &&
                siteController.contains("SiteEntryTimeZoneLocalSnapshot"),
            "Site entry must own one coordinator, overlay, and pre-import local snapshot"
        )
        require(
            appearsInOrder(
                [
                    "let localState = sitePropsCoordinator.currentState()",
                    "SiteEntryTimeZoneSyncResponseParser.parse",
                    "await self.site.update(siteJsonData: siteData)"
                ],
                in: siteController
            ),
            "Site entry must capture and parse before importing the successful response"
        )
        require(
            siteController.contains("SiteEntryTimeZoneSyncResponseParser.parse(") &&
                siteController.contains("siteData: siteData") &&
                !siteController.contains("gatewaySyncFlag:") &&
                occurrences(of: "consumeWithoutAction()", in: siteController) >= 2,
            "Production must parse real Gateway offsets and consume malformed first success"
        )
        require(
            appearsInOrder(
                [
                    "XWHUDManager.hideInView(with: self.view)",
                    "handleEntrySyncDecision"
                ],
                in: siteController
            ),
            "The existing loading HUD must finish before entry overlay presentation"
        )
        require(
            siteController.contains("private func handleEntrySyncDecision(") &&
                siteController.contains("case .useVisitorRemote:") &&
                siteController.contains("entrySyncCoordinator.applySilent(decision)") &&
                siteController.contains("case .showGatewayStatus, .useRemote, .useLocal:") &&
                siteController.contains("showEntrySyncOverlay(") &&
                siteController.contains("remoteSnapshot: remoteSnapshot"),
            "Controller must persist Visitor cloud authority silently and show only visible decisions"
        )
        require(
            siteController.contains(
                "private var timeZoneReviewState: SiteTimeZoneReviewState = .hidden"
            ) &&
                siteController.contains("private func applyTimeZoneReviewState(") &&
                siteController.contains("private func setTimeZoneReviewState("),
            "Site must own one non-persistent review state"
        )
        require(
            appearsInOrder(
                [
                    "await self.site.update(siteJsonData: siteData)",
                    "if let remoteSnapshot {",
                    "self.applyTimeZoneReviewState(",
                    "handleEntrySyncDecision("
                ],
                in: siteController
            ),
            "Every valid response must update the page state before entry handling"
        )
        require(
            siteController.contains("remoteSnapshot: remoteSnapshot") &&
                appearsInOrder(
                    [
                        "let result = await entrySyncCoordinator.run(decision)",
                        "if result.site == .updatedToServer",
                        "serverTimezone: result.timezone",
                        "entrySyncOverlay.showResult(result)"
                    ],
                    in: siteController
                ),
            "Successful app-to-cloud sync must update server truth before result actions"
        )
        require(
            occurrences(of: "entrySyncCoordinator.prepare(", in: siteController) == 1 &&
                !siteController.contains("hasConsumedEntryResponse"),
            "Page refresh must preserve the coordinator's existing one-entry gate"
        )
        require(
            siteController.contains("guard !entrySyncNavigationLocked else { return }") &&
                siteController.contains("navigationController?.interactivePopGestureRecognizer") &&
                siteController.contains("gesture?.isEnabled") &&
                siteController.contains("interactivePopGestureWasEnabled") &&
                siteController.contains("setEntrySyncNavigationLocked(_ locked: Bool)"),
            "Back action and interactive pop must remain locked until acknowledgement"
        )
        require(
            siteController.contains("overlay.onGotIt") &&
                siteController.contains("overlay.onLater") &&
                siteController.contains("overlay.onReviewSync") &&
                siteController.contains("handleEntrySyncReview()") &&
                siteController.contains("finishEntrySyncOverlay()") &&
                siteController.contains("entrySyncCoordinator.cancel()") &&
                siteController.contains("entrySyncTask?.cancel()"),
            "All result actions and controller teardown must clean up overlay work"
        )
        require(
            appearsInOrder(
                [
                    "overlay.onLater = { [weak self] in",
                    "self?.finishEntrySyncOverlay()",
                    "overlay.onReviewSync = { [weak self] in",
                    "self?.handleEntrySyncReview()"
                ],
                in: siteController
            ) &&
                appearsInOrder(
                    [
                        "private func handleEntrySyncReview()",
                        "finishEntrySyncOverlay()",
                        "showSyncGatewaysPage()"
                    ],
                    in: siteController
                ),
            "LATER must finish directly and REVIEW SYNC must finish before routing"
        )

        print("SiteEntryTimeZoneSyncContractTests passed")
    }

    private static func occurrences(of needle: String, in text: String) -> Int {
        guard !needle.isEmpty else { return 0 }
        var count = 0
        var searchRange = text.startIndex..<text.endIndex
        while let range = text.range(of: needle, range: searchRange) {
            count += 1
            searchRange = range.upperBound..<text.endIndex
        }
        return count
    }

    private static func appearsInOrder(_ needles: [String], in text: String) -> Bool {
        var lowerBound = text.startIndex
        for needle in needles {
            guard let range = text.range(of: needle, range: lowerBound..<text.endIndex) else {
                return false
            }
            lowerBound = range.upperBound
        }
        return true
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }
}
