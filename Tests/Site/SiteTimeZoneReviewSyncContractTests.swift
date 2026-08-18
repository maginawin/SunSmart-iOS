import Foundation

@main
struct SiteTimeZoneReviewSyncContractTests {

    static func main() throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 9 else {
            fatalError(
                "Expected review view, header, Site controller, Sync gateways " +
                    "controller, English, Chinese, project, and warning asset paths"
            )
        }

        let reviewView = try String(contentsOfFile: arguments[1], encoding: .utf8)
        let header = try String(contentsOfFile: arguments[2], encoding: .utf8)
        let siteController = try String(contentsOfFile: arguments[3], encoding: .utf8)
        let syncController = try String(contentsOfFile: arguments[4], encoding: .utf8)
        let english = try String(contentsOfFile: arguments[5], encoding: .utf8)
        let simplifiedChinese = try String(contentsOfFile: arguments[6], encoding: .utf8)
        let project = try String(contentsOfFile: arguments[7], encoding: .utf8)
        let warningAsset = try String(contentsOfFile: arguments[8], encoding: .utf8)

        require(reviewView.contains("final class SiteTimeZoneReviewSyncView: UIView"))
        require(reviewView.contains("RGB(255, 249, 239)"))
        require(reviewView.contains("layer.cornerRadius = SCRYFrom(14)"))
        require(reviewView.contains("UIImage(named: \"site_entry_sync_warning\")"))
        require(reviewView.contains("make.size.equalTo(SCRYFrom(16))"))
        require(reviewView.contains("RGB(100, 116, 139)"))
        require(reviewView.contains("RGB(151, 60, 0)"))
        require(reviewView.contains("make.height.equalTo(SCRYFrom(28))"))
        require(reviewView.contains("numberOfLines = 2"))
        require(reviewView.contains("var onReviewSync: (() -> Void)?"))

        for key in [
            "site_time_zone_review_sync_single",
            "site_time_zone_review_sync_multiple",
            "site_time_zone_review_sync_action"
        ] {
            require(
                occurrences(of: "\"\(key)\" =", in: english) == 1,
                "English must define \(key) exactly once"
            )
            require(
                occurrences(of: "\"\(key)\" =", in: simplifiedChinese) == 1,
                "Simplified Chinese must define \(key) exactly once"
            )
            require(
                reviewView.contains("\"\(key)\".localizedString"),
                "Review view must consume \(key)"
            )
        }

        require(header.contains("let timeZoneReviewSyncView = SiteTimeZoneReviewSyncView()"))
        require(header.contains("var timeZoneReviewState: SiteTimeZoneReviewState"))
        require(header.contains("var onReviewSync: (() -> Void)?"))
        require(header.contains("timeZoneReviewSyncView.isHidden = true"))
        require(siteController.contains("headerView.timeZoneReviewState = timeZoneReviewState"))
        require(siteController.contains("SiteGatewayHeaderLayoutPolicy.height("))
        require(
            siteController.contains("private func siteGatewayHeaderHeight(") &&
                occurrences(
                    of: "siteGatewayHeaderHeight(for:",
                    in: siteController
                ) == 2,
            "Header size and empty frame must share one height calculation"
        )
        require(
            occurrences(of: "emptyFrame(", in: siteController) == 4,
            "Three empty states must use the shared empty frame helper"
        )
        require(
            !siteController.contains("SCRYFrom(96)"),
            "Empty states must not retain the pre-review fixed header offset"
        )
        let reviewStateSetter = sourceSection(
            in: siteController,
            from: "private func setTimeZoneReviewState(",
            to: "private func setEntrySyncNavigationLocked("
        )
        require(
            appearsInOrder(
                [
                    "guard state != timeZoneReviewState else { return }",
                    "timeZoneReviewState = state",
                    "favouritesCollectionView.reloadData()",
                    "updateEmptyView()"
                ],
                in: reviewStateSetter
            ),
            "Review state changes must refresh existing empty frames"
        )
        require(siteController.contains("headerView.onReviewSync = { [weak self] in"))
        require(siteController.contains("self?.showSyncGatewaysPage()"))
        require(siteController.contains("private func showSyncGatewaysPage()"))
        require(siteController.contains("latestTimeZoneRemoteSnapshot"))
        require(siteController.contains("SyncGatewaysContextBuilder.make("))
        require(siteController.contains("SyncGatewaysViewController("))
        require(siteController.contains("context: context"))
        require(siteController.contains("cloudBridge: syncGatewaysCloudBridge"))
        require(siteController.contains("canStartSync:"))
        require(siteController.contains("navigationController?.pushViewController(controller, animated: true)"))

        let viewWillAppearFlow = sourceSection(
            in: siteController,
            from: "override func viewWillAppear(",
            to: "@objc private func backAction("
        )
        require(
            appearsInOrder(
                [
                    "setupData()",
                    "refreshCurrentGatewayTimeZoneReviewProjection()"
                ],
                in: viewWillAppearFlow
            ),
            "Returning to the Site page must re-project cached Review state after local setup"
        )

        let siteEditFlow = sourceSection(
            in: siteController,
            from: "private func editSite()",
            to: "private func deleteSite()"
        )
        require(
            siteEditFlow.contains("vc.siteDidChange = { [weak self] in") &&
                appearsInOrder(
                    [
                        "self?.title = self?.site.name",
                        "self?.refreshCurrentGatewayTimeZoneReviewProjection()"
                    ],
                    in: siteEditFlow
                ),
            "A local Site edit must immediately re-project cached Review state"
        )

        let showReviewFlow = sourceSection(
            in: siteController,
            from: "private func showSyncGatewaysPage()",
            to: "private func pendingTimeZoneSyncGatewayIDs("
        )
        let pendingReviewFlow = sourceSection(
            in: siteController,
            from: "private func pendingTimeZoneSyncGatewayIDs()",
            to: "private func makeGatewayListItems("
        )
        let onsiteReviewFlow = showReviewFlow + pendingReviewFlow
        let missingRemoteShowGuard = sourceSection(
            in: showReviewFlow,
            from: "private func showSyncGatewaysPage()",
            to: "let projection = gatewayTimeZoneReviewProjection(from: remote)"
        )
        let hiddenProjectionShowGuard = sourceSection(
            in: showReviewFlow,
            from: "let projection = gatewayTimeZoneReviewProjection(from: remote)",
            to: "guard let meshNetwork = sitePrimaryMeshNetwork()"
        )
        require(
            missingRemoteShowGuard.contains("invalidateGatewayTimeZoneReview()") &&
                hiddenProjectionShowGuard.contains("invalidateGatewayTimeZoneReview()") &&
                !hiddenProjectionShowGuard.contains("if gatewayTimeZoneReviewContext != nil"),
            "A Review action without remote data or an actionable target must unconditionally hide stale UI"
        )
        require(
            occurrences(
                of: "confirmedOffsetMinutesByGatewayID: confirmedGatewayOffsetMinutesByID",
                in: onsiteReviewFlow
            ) == 2,
            "Both onsite Review target builders must receive the in-memory confirmed offsets"
        )
        require(
            occurrences(
                of: "requiredGatewayIDs: reviewContext?.failedGatewayIDs",
                in: onsiteReviewFlow
            ) == 2 &&
                occurrences(
                    of: "gatewayTimeZoneReviewProjection(from: remote)",
                    in: onsiteReviewFlow
                ) == 2 &&
                onsiteReviewFlow.contains("reviewContext: reviewContext"),
            "Onsite Review must consume the explicit failed-ID context and its target timezone"
        )
        require(
            showReviewFlow.contains("invalidateGatewayTimeZoneReview()") &&
                !onsiteReviewFlow.contains("resolveGatewayReviewTargetTimeZone("),
            "A hidden or empty explicit Review action must use the atomic invalidation path"
        )
        require(
            !pendingReviewFlow.contains("gatewayTimeZoneReviewContext =") &&
                !pendingReviewFlow.contains("setTimeZoneReviewState(") &&
                !pendingReviewFlow.contains("invalidateGatewayTimeZoneReview()") &&
                !pendingReviewFlow.contains("reloadData()"),
            "Gateway-list pending projection must remain a read-only datasource query"
        )

        let confirmedSnapshotReconcile = sourceSection(
            in: siteController,
            from: "private func reconcileConfirmedGatewayOffsets(",
            to: "private func effectiveGatewayOffsetOverrides("
        )
        require(
            confirmedSnapshotReconcile.contains("SiteGatewayCloudTimeZoneConfirmationPolicy") &&
                confirmedSnapshotReconcile.contains(".acknowledgedGatewayIDs(") &&
                confirmedSnapshotReconcile.contains("remote: remote.gateways") &&
                confirmedSnapshotReconcile.contains("confirmedGatewayOffsetMinutesByID.removeValue(forKey: id)"),
            "The controller must delegate confirmation clearing to the behavior-tested evidence policy"
        )

        let effectiveOverrides = sourceSection(
            in: siteController,
            from: "private func effectiveGatewayOffsetOverrides(",
            to: "private func setTimeZoneReviewState("
        )

        let reviewProjectionFlow = sourceSection(
            in: siteController,
            from: "private func gatewayTimeZoneReviewProjection(",
            to: "private func invalidateGatewayTimeZoneReview("
        )
        require(
            reviewProjectionFlow.contains("SiteGatewayTimeZoneReviewProjectionPolicy.project(") &&
                reviewProjectionFlow.contains("return projection") &&
                !reviewProjectionFlow.contains("gatewayTimeZoneReviewContext =") &&
                !reviewProjectionFlow.contains("setTimeZoneReviewState(") &&
                !reviewProjectionFlow.contains("reloadData()"),
            "Review projection helper must be a strictly read-only policy query"
        )
        let reviewInvalidationFlow = sourceSection(
            in: siteController,
            from: "private func invalidateGatewayTimeZoneReview(",
            to: "private func refreshCurrentGatewayTimeZoneReviewProjection("
        )
        require(
            occurrences(
                of: "gatewayTimeZoneReviewContext = nil",
                in: reviewInvalidationFlow
            ) == 1 &&
                occurrences(
                    of: "setTimeZoneReviewState(.hidden)",
                    in: reviewInvalidationFlow
                ) == 1,
            "Explicit invalidation must atomically clear context and hide through the guarded setter"
        )
        let refreshReviewProjectionFlow = sourceSection(
            in: siteController,
            from: "private func refreshCurrentGatewayTimeZoneReviewProjection(",
            to: "private func effectiveGatewayOffsetOverrides("
        )
        require(
            refreshReviewProjectionFlow.contains("guard let remote = latestTimeZoneRemoteSnapshot else") &&
                appearsInOrder(
                    [
                        "let projection = gatewayTimeZoneReviewProjection(from: remote)",
                        "guard let targetTimeZone = projection.targetTimeZone else",
                        "invalidateGatewayTimeZoneReview()",
                        "let localGatewayContext = SiteGatewayCloudTimeZoneLocalContextBuilder.make(",
                        "site: site",
                        "remoteSnapshot: remote",
                        "targetTimeZone: targetTimeZone",
                        "applyTimeZoneReviewState(",
                        "from: remote",
                        "localDirtyOffsetMinutesByGatewayID:",
                        "localGatewayContext.dirtyOverridesByID.mapValues(\\.offsetMinutes)"
                    ],
                    in: refreshReviewProjectionFlow
                ) &&
                occurrences(
                    of: "applyTimeZoneReviewState(",
                    in: refreshReviewProjectionFlow
                ) == 1 &&
                !refreshReviewProjectionFlow.contains(
                    "applyTimeZoneReviewState(from: remote)"
                ),
            "Lifecycle refresh must capture dirty offsets for the actionable projection target before applying Review state"
        )
        let applyReviewFlows = sourceSection(
            in: siteController,
            from: "private func applyTimeZoneReviewState(",
            to: "private func setTimeZoneReviewState("
        )
        require(
            occurrences(
                of: "switch gatewayTimeZoneReviewProjection(from: remote)",
                in: applyReviewFlows
            ) == 1 &&
                occurrences(of: "case .hidden:", in: applyReviewFlows) == 1 &&
                occurrences(of: "case .explicit(let context):", in: applyReviewFlows) == 1 &&
                applyReviewFlows.contains("invalidateGatewayTimeZoneReview()") &&
                occurrences(
                    of: "private func applyTimeZoneReviewState(",
                    in: siteController
                ) == 1,
            "The single Review-state application path must consume the pure projection and explicitly invalidate hidden state"
        )
        require(
            appearsInOrder(
                [
                    "var offsets = localDirtyOffsetMinutesByGatewayID",
                    "confirmedGatewayOffsetMinutesByID.forEach",
                    "offsets[id] = offset"
                ],
                in: effectiveOverrides
            ) && effectiveOverrides.contains("localDirtyOffsetMinutesByGatewayID: effectiveGatewayOffsetOverrides("),
            "Review state must resolve Gateway offsets as confirmed, then dirty, then remote"
        )

        let gatewayDetailConfirmationFlow = sourceSection(
            in: siteController,
            from: "private func recordGatewayDetailTimeZoneConfirmation(",
            to: "private func invalidateGatewayTimeZoneReview("
        )
        require(
            gatewayDetailConfirmationFlow.contains(
                "guard gatewayDetailPresentationSessionID == sessionID"
            ) &&
                gatewayDetailConfirmationFlow.contains(
                    "id == SiteGatewayAccessScope.normalize(expectedGatewayID)"
                ) &&
                gatewayDetailConfirmationFlow.contains(
                    "targetTimeZone.offsetMinutes == offsetMinutes"
                ) &&
                gatewayDetailConfirmationFlow.contains(
                    "confirmedGatewayOffsetMinutesByID[id] = offsetMinutes"
                ),
            "Gateway detail confirmations must be scoped to the active session, expected Gateway, and current Site target"
        )
        require(
            appearsInOrder(
                [
                    "guard gatewayDetailPresentationSessionID == sessionID else { return }",
                    "gatewayDetailPresentationSessionID = nil",
                    "setupData()",
                    "refreshCurrentGatewayTimeZoneReviewProjection()",
                    "retryDirtyGatewayCloudUploads()",
                    "performSiteLoad(presentation: .silentGatewayReconcile)"
                ],
                in: gatewayDetailConfirmationFlow
            ),
            "Returning from Gateway detail must immediately re-project local evidence and then silently reconcile the Site snapshot"
        )

        let gatewayDetailPresentationFlow = sourceSection(
            in: siteController,
            from: "func gatewayOperationClickAction(",
            to: "extension SiteViewController: CustomSegmentedControlDelegate"
        )
        require(
            gatewayDetailPresentationFlow.contains(
                "gatewayVc.timeZoneSyncDidFinish = { [weak self] gatewayID, offsetMinutes in"
            ) &&
                gatewayDetailPresentationFlow.contains(
                    "gatewayVc.gatewayPageDidClose = { [weak self] in"
                ) &&
                gatewayDetailPresentationFlow.contains(
                    "navigationController.presentationController?.delegate = self"
                ) &&
                gatewayDetailPresentationFlow.contains(
                    "extension SiteViewController: UIAdaptivePresentationControllerDelegate"
                ) &&
                gatewayDetailPresentationFlow.contains(
                    "func presentationControllerDidDismiss("
                ) &&
                occurrences(
                    of: "finishGatewayDetailPresentation(sessionID: sessionID)",
                    in: gatewayDetailPresentationFlow
                ) == 2,
            "Gateway detail explicit and interactive dismissal paths must share one idempotent Site reconcile"
        )

        let gatewayReconcile = sourceSection(
            in: siteController,
            from: "private func reconcileEditTimeZoneSyncOutcome(",
            to: "/// 删除场所"
        )
        require(
            gatewayReconcile.contains(
                "confirmedGatewayOffsetMinutesByID = result.confirmedOffsetMinutesByGatewayID"
            ) &&
                gatewayReconcile.contains("gatewayTimeZoneReviewContext = result.reviewContext") &&
                occurrences(
                    of: "refreshCurrentGatewayTimeZoneReviewProjection()",
                    in: gatewayReconcile
                ) == 1 &&
                !gatewayReconcile.contains("applyTimeZoneReviewState(") &&
                occurrences(
                    of: "performSiteLoad(presentation: .silentGatewayReconcile)",
                    in: gatewayReconcile
                ) == 1,
            "Edit terminal results must preserve confirmed and dirty Gateway precedence through the shared Review refresh before reconcile"
        )

        let canStartReviewFlow = sourceSection(
            in: siteController,
            from: "private func canStartGatewayTimeSync(",
            to: "private func cancelEntrySyncOverlay("
        )
        require(
            canStartReviewFlow.contains("gatewayTimeZoneReviewProjection(from: remote)") &&
                !canStartReviewFlow.contains("gatewayTimeZoneReviewContext =") &&
                !canStartReviewFlow.contains("setTimeZoneReviewState(") &&
                !canStartReviewFlow.contains("invalidateGatewayTimeZoneReview()") &&
                !canStartReviewFlow.contains("reloadData()"),
            "Gateway sync authorization revalidation must query projection without mutating UI state"
        )

        require(syncController.contains("final class SyncGatewaysViewController: UIViewController"))
        require(syncController.contains("init("))
        require(syncController.contains("context: SyncGatewaysContext"))
        require(syncController.contains("cloudBridge: SyncGatewaysCloudBridge"))
        require(syncController.contains("canStartSync: @escaping (SyncGatewayRuntimeTarget) -> Bool"))
        require(!syncController.contains("override init("))
        require(syncController.contains("title = \"site_sync_gateways_title\".localizedString"))
        require(syncController.contains("view.backgroundColor = SyncGatewaysCopy.pageBackgroundColor"))
        require(
            occurrences(of: "\"site_sync_gateways_title\" =", in: english) == 1,
            "English must define site_sync_gateways_title exactly once"
        )
        require(
            occurrences(of: "\"site_sync_gateways_title\" =", in: simplifiedChinese) == 1,
            "Simplified Chinese must define site_sync_gateways_title exactly once"
        )

        require(
            occurrences(
                of: "SiteTimeZoneReviewSyncView.swift in Sources",
                in: project
            ) == 8,
            "Review view must belong to all four app targets"
        )
        for targetSuffix in 1...4 {
            require(
                occurrences(
                    of: "F260813000000000000140\(targetSuffix) /* SiteTimeZoneReviewSyncView.swift in Sources */",
                    in: project
                ) == 2,
                "Review view must be declared and referenced by target \(targetSuffix)"
            )
        }
        require(
            occurrences(of: "SyncGatewaysViewController.swift in Sources", in: project) == 8,
            "Sync gateways controller must belong to all four app targets"
        )
        for targetSuffix in 1...4 {
            require(
                occurrences(
                    of: "F260813000000000000150\(targetSuffix) /* SyncGatewaysViewController.swift in Sources */",
                    in: project
                ) == 2,
                "Sync gateways controller must be declared and referenced by target \(targetSuffix)"
            )
        }
        require(
            occurrences(
                of: "SiteGatewayHeaderLayoutPolicy.swift in Sources",
                in: project
            ) == 8,
            "Header layout policy must belong to all four app targets"
        )
        for targetSuffix in 1...4 {
            require(
                occurrences(
                    of: "F260814000000000000290\(targetSuffix) /* SiteGatewayHeaderLayoutPolicy.swift in Sources */",
                    in: project
                ) == 2,
                "Header layout policy must be declared and referenced by target \(targetSuffix)"
            )
        }
        require(
            warningAsset.contains("site_entry_sync_warning.svg") &&
                warningAsset.contains("preserves-vector-representation"),
            "Review view must reuse the existing vector warning asset"
        )

        print("SiteTimeZoneReviewSyncContractTests passed")
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

    private static func require(
        _ condition: @autoclosure () -> Bool,
        _ message: String = "Review sync contract failed"
    ) {
        guard condition() else { fatalError(message) }
    }
}
