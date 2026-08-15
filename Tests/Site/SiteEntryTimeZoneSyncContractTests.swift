import Foundation

@main
struct SiteEntryTimeZoneSyncContractTests {

    static func main() throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 5 || arguments.count == 7 else {
            fatalError(
                "Expected overlay, two localizations, and Site controller paths"
            )
        }

        let overlay = try String(contentsOfFile: arguments[1], encoding: .utf8)
        let english = try String(contentsOfFile: arguments[2], encoding: .utf8)
        let simplifiedChinese = try String(contentsOfFile: arguments[3], encoding: .utf8)
        let siteController = try String(contentsOfFile: arguments[4], encoding: .utf8)

        require(
            overlay.contains("enum State: Equatable") &&
                overlay.contains("case checking") &&
                overlay.contains("case result(") &&
                overlay.contains("site: SiteEntryTimeZoneResult") &&
                overlay.contains("gateways: SiteGatewayCloudTimeZoneBatchState") &&
                !overlay.contains("gatewaysNeedSync"),
            "Overlay state must model checking or the Site result with its Gateway batch"
        )
        require(
            overlay.contains("var onDone: (() -> Void)?") &&
                overlay.contains("func showResult(") &&
                overlay.contains("gateways: SiteGatewayCloudTimeZoneBatchState") &&
                !overlay.contains("onGotIt") &&
                !overlay.contains("onLater") &&
                !overlay.contains("onReviewSync") &&
                !overlay.contains("func dismiss()"),
            "Only DONE may acknowledge a result; processing must expose no independent close API"
        )
        require(
            overlay.contains("private let gatewayStatusView = SiteEntryGatewayTimeZoneStatusView()") &&
                overlay.contains("gatewayStatusView.update(gateways)") &&
                overlay.contains("gatewayStatusView.preferredHeight") &&
                !overlay.contains("gatewayStatusCardView") &&
                !overlay.contains("gatewayTitleLabel") &&
                !overlay.contains("gatewayStatusLabel"),
            "The result sheet must consume Task 5's Gateway component and its height contract"
        )
        require(
            overlay.contains("\"site_entry_sync_status_title\".localizedString") &&
                overlay.contains("siteStatusCardView") &&
                overlay.contains("case .alreadyInSync:") &&
                overlay.contains("case .updatedFromServer:") &&
                overlay.contains("case .updatedToServer:") &&
                overlay.contains("case .failedToUpdateServer:"),
            "The sheet must retain the title and all existing Site result mappings"
        )
        require(
            overlay.contains("UIColor.black.withAlphaComponent(0.4)") &&
                overlay.contains("resultCardView.layer.cornerRadius = SCRYFrom(24)") &&
                overlay.contains("make.width.equalTo(SCRXFrom(343))") &&
                overlay.contains("make.bottom.equalTo(safeAreaLayoutGuide.snp.bottom)") &&
                overlay.contains("make.top.greaterThanOrEqualTo(safeAreaLayoutGuide.snp.top).offset(SCRYFrom(16))") &&
                !overlay.contains("make.height.equalTo(SCRYFrom(296))"),
            "The result is a bottom sheet capped at 343pt that grows upward without crossing the safe-area top"
        )
        require(
            overlay.contains("doneButton.isHidden = !gateways.canDismiss") &&
                overlay.contains("guard case let .result(_, gateways) = state, gateways.canDismiss else { return }") &&
                overlay.contains("\"site_entry_sync_done\".localizedString") &&
                !overlay.contains("gotItButton") &&
                !overlay.contains("laterButton") &&
                !overlay.contains("reviewSyncButton") &&
                !overlay.contains("site_entry_sync_later") &&
                !overlay.contains("site_entry_sync_review_sync"),
            "DONE must be the sole terminal action and remain guarded until every Gateway is terminal"
        )
        require(
            !overlay.contains("UITapGestureRecognizer") &&
                !overlay.contains("addGestureRecognizer") &&
                overlay.contains("accessibilityViewIsModal = true"),
            "The dimmed background is modal and has no tap-to-dismiss path"
        )
        require(
            overlay.contains("private var resultCardHeightConstraint: Constraint!") &&
                overlay.contains("resultCardHeightConstraint.update") &&
                overlay.contains("resultCardHeightConstraint.deactivate()") &&
                overlay.contains("safeAreaLayoutGuide.snp.height") &&
                overlay.contains("availableGatewayViewportHeight") &&
                overlay.contains("UIView.animate"),
            "The result sheet must remove its height constraint while checking and cap the Gateway viewport to its safe-area budget"
        )
        require(
            overlay.contains("private let footerContainerView = UIView()") &&
                overlay.contains("private var footerHeightConstraint: Constraint!") &&
                overlay.contains("footerHeightConstraint.update(offset: gateways.canDismiss ? SCRYFrom(61) : 0)") &&
                overlay.contains("footerContainerView.isHidden = !gateways.canDismiss") &&
                overlay.contains("case let .result(site, gateways):") &&
                overlay.contains("if !wasDismissible && gateways.canDismiss"),
            "The footer must collapse to 0 while pushing, expand to 61 only when terminal, and animate that transition"
        )
        require(
            overlay.contains("UIImage(named: \"site_entry_sync_loading\")") &&
                overlay.contains("UIImage(named: \"site_entry_sync_success\")") &&
                overlay.contains("checkingCardView.layer.cornerRadius = SCRYFrom(20)"),
            "Checking and existing Site status visuals must remain available"
        )

        for key in ["site_entry_sync_status_title", "site_entry_sync_done"] {
            let declaration = "\"\(key)\" ="
            require(
                occurrences(of: declaration, in: english) == 1 &&
                    occurrences(of: declaration, in: simplifiedChinese) == 1,
                "Both localizations must define \(key) exactly once"
            )
        }
        require(
            english.contains("\"site_entry_sync_status_title\" = \"Time zone sync status\";") &&
                english.contains("\"site_entry_sync_done\" = \"DONE\";"),
            "The sheet must retain the approved English title and DONE copy"
        )

        require(
            siteController.contains("let localGatewaySnapshotsByID: [String: SiteGatewayCloudTimeZoneLocalSnapshot]") &&
                siteController.contains("private var confirmedGatewayOffsetMinutesByID: [String: Int] = [:]") &&
                siteController.contains("private var gatewayEntrySyncTask: Task<Void, Never>?") &&
                siteController.contains("private var entrySyncSessionToken: UUID?") &&
                siteController.contains("private var reconciledEntrySyncSessionToken: UUID?"),
            "Entry presentation must preserve pre-import Gateway names and offsets and isolate each session"
        )
        require(
            siteController.contains("private lazy var gatewayEntrySyncCoordinator = SiteGatewayCloudTimeZoneSyncCoordinator(") &&
                siteController.contains("api: SiteGatewayCloudTimeZoneAPIClient()") &&
                siteController.contains("timing: SiteGatewayCloudTimeZoneContinuousTiming()") &&
                siteController.contains("overlay.onDone = { [weak self] in") &&
                !siteController.contains("entrySyncOverlay.onGotIt") &&
                !siteController.contains("entrySyncOverlay.onLater") &&
                !siteController.contains("entrySyncOverlay.onReviewSync"),
            "The controller must use the production Gateway coordinator and DONE-only overlay API"
        )

        let loadFlow = sourceSection(
            in: siteController,
            from: "private func performSiteLoad(",
            to: "private func handleEntrySyncDecision("
        )
        require(
            appearsInOrder(
                [
                    "captureDirtyGatewayTimeOverrides(",
                    "makeLocalGatewayTimeZoneSnapshots(",
                    "await self.site.update(siteJsonData: siteData)",
                    "localGatewaySnapshotsByID: localGatewaySnapshotsByID"
                ],
                in: loadFlow
            ),
            "Dirty offsets and display names must be captured before the server import overwrites local state"
        )

        let presentationFlow = sourceSection(
            in: siteController,
            from: "private func presentPendingEntrySyncOverlayIfPossible()",
            to: "private func makeGatewayEntrySyncState("
        )
        let legacyGatewayTaskBeforeAwait = sourceSection(
            in: presentationFlow,
            from: "gatewayEntrySyncTask = Task { [weak self] in",
            to: "await runGatewayEntrySyncIfNeeded("
        )
        require(
            legacyGatewayTaskBeforeAwait.isEmpty ||
                (!legacyGatewayTaskBeforeAwait.contains("guard let self") &&
                    !legacyGatewayTaskBeforeAwait.contains("self.")),
            "The Gateway Task must not strongify the controller before its long coordinator await"
        )
        require(
            appearsInOrder(
                [
                    "entrySyncOverlay.showChecking(in: container)",
                    "entrySyncCoordinator.run(presentation.decision)",
                    "makeGatewayEntrySyncState(",
                    "startGatewayEntrySyncIfNeeded("
                ],
                in: presentationFlow
            ),
            "The Site phase must finish before the Gateway batch is built and started"
        )

        let siteTaskFlow = sourceSection(
            in: presentationFlow,
            from: "entrySyncTask = Task {",
            to: "startGatewayEntrySyncIfNeeded("
        )
        require(
            siteTaskFlow.contains("Task { [weak self, entrySyncCoordinator] in") &&
                appearsInOrder(
                    [
                        "await entrySyncCoordinator.run(presentation.decision)",
                        "guard",
                        "let self"
                    ],
                    in: siteTaskFlow
                ),
            "The Site task may only retain the controller briefly after its long coordinator await"
        )

        let gatewayFlow = sourceSection(
            in: siteController,
            from: "private func startGatewayEntrySyncIfNeeded(",
            to: "private func reconcileGatewayEntrySyncResult("
        )
        let siteFailureFlow = sourceSection(
            in: gatewayFlow,
            from: "case .failedToUpdateServer:",
            to: "case .alreadyInSync, .updatedFromServer, .updatedToServer:"
        )
        require(
            siteFailureFlow.contains("failedState.failPushing()") &&
                siteFailureFlow.contains("performsSilentReconcile: false") &&
                siteFailureFlow.contains("return") &&
                !siteFailureFlow.contains("coordinator.run(") &&
                !siteFailureFlow.contains("silentGatewayReconcile") &&
                gatewayFlow.contains("guard !initialState.requestMACs.isEmpty else") &&
                appearsInOrder(
                    [
                        "entrySyncOverlay.showResult(siteResult, gateways: initialState)",
                        "let coordinator = gatewayEntrySyncCoordinator",
                        "let finalState = await coordinator.run("
                    ],
                    in: gatewayFlow
                ) &&
                gatewayFlow.contains("onUpdate: { [weak self] state in") &&
                gatewayFlow.contains("entrySyncOverlay.showResult(siteResult, gateways: state)") &&
                gatewayFlow.contains("if state.canDismiss {") &&
                gatewayFlow.contains("sessionToken: sessionToken"),
            "Gateway API work must be fail-closed, Site-success-only, and update the visible batch in place"
        )

        let gatewayTaskBeforeAwait = sourceSection(
            in: gatewayFlow,
            from: "gatewayEntrySyncTask = Task {",
            to: "let finalState = await coordinator.run("
        )
        require(
            !gatewayFlow.contains(") async {") &&
                appearsInOrder(
                    [
                        "let coordinator = gatewayEntrySyncCoordinator",
                        "let siteID = site.id",
                        "gatewayEntrySyncTask = Task {"
                    ],
                    in: gatewayFlow
                ) &&
                gatewayTaskBeforeAwait.contains(
                    "[weak self, coordinator, siteID, siteResult, initialState, sessionToken]"
                ) &&
                !gatewayTaskBeforeAwait.contains("guard let self") &&
                !gatewayTaskBeforeAwait.contains("self.") &&
                gatewayFlow.contains("onUpdate: { [weak self] state in") &&
                appearsInOrder(
                    [
                        "let finalState = await coordinator.run(",
                        "let self",
                        "isEntrySyncSessionActive(sessionToken)"
                    ],
                    in: gatewayFlow
                ),
            "The long Gateway task must retain values and its coordinator without retaining the controller across await"
        )

        let reconcileFlow = sourceSection(
            in: siteController,
            from: "private func reconcileGatewayEntrySyncResult(",
            to: "private func applyTimeZoneReviewState("
        )
        require(
            reconcileFlow.contains("initiallyPendingIDs") &&
                reconcileFlow.contains("guard reconciledEntrySyncSessionToken != sessionToken else { return }") &&
                reconcileFlow.contains("reconciledEntrySyncSessionToken = sessionToken") &&
                reconcileFlow.contains("item.status == .synced") &&
                reconcileFlow.contains("confirmedGatewayOffsetMinutesByID[item.id] = targetOffsetMinutes") &&
                reconcileFlow.contains("SiteGatewayTimeZoneReviewContext.make(") &&
                reconcileFlow.contains("if performsSilentReconcile") &&
                !reconcileFlow.contains("MeshAPI") &&
                !reconcileFlow.contains("node.timezone") &&
                !reconcileFlow.contains("node.timestamp") &&
                !reconcileFlow.contains("savePropertys()") &&
                !reconcileFlow.contains("requestID"),
            "Only initially pending Gateways that finish synced may update the in-memory confirmation override"
        )

        let finishFlow = sourceSection(
            in: siteController,
            from: "private func finishEntrySyncOverlay()",
            to: "private func showSyncGatewaysPage()"
        )
        require(
            finishFlow.contains("entrySyncSessionToken = nil") &&
                finishFlow.contains("entrySyncTask?.cancel()") &&
                finishFlow.contains("gatewayEntrySyncTask?.cancel()") &&
                finishFlow.contains("entrySyncCoordinator.cancel()") &&
                finishFlow.contains("gatewayEntrySyncCoordinator.cancel()") &&
                finishFlow.contains("entrySyncOverlay.removeFromSuperview()") &&
                finishFlow.contains("continuePostImportNavigationIfNeeded()"),
            "DONE must invalidate both phases before removing the overlay and continuing navigation"
        )

        let disappearanceFlow = sourceSection(
            in: siteController,
            from: "override func viewDidDisappear(",
            to: "deinit {"
        )
        let deinitFlow = sourceSection(
            in: siteController,
            from: "deinit {",
            to: "private func updateAddressData()"
        )
        let cancellationFlow = sourceSection(
            in: siteController,
            from: "private func cancelEntrySyncOverlay()",
            to: "private func continuePostImportNavigationIfNeeded()"
        )
        require(
            disappearanceFlow.contains("guard entrySyncNavigationLocked else { return }") &&
                disappearanceFlow.contains("cancelEntrySyncOverlay()") &&
                !disappearanceFlow.contains("isMovingFromParent") &&
                !disappearanceFlow.contains("isBeingDismissed") &&
                !disappearanceFlow.contains("navigationController?.isBeingDismissed") &&
                cancellationFlow.contains("entrySyncSessionToken = nil") &&
                cancellationFlow.contains("gatewayEntrySyncCoordinator.cancel()") &&
                cancellationFlow.contains("entrySyncOverlay.removeFromSuperview()") &&
                cancellationFlow.contains("setEntrySyncNavigationLocked(false)"),
            "Any disappearance during entry sync must invalidate the session and release navigation locking"
        )
        require(
            deinitFlow.contains("entrySyncTask?.cancel()") &&
                deinitFlow.contains("gatewayEntrySyncTask?.cancel()") &&
                !deinitFlow.contains("entrySyncCoordinator") &&
                !deinitFlow.contains("gatewayEntrySyncCoordinator") &&
                !deinitFlow.contains("Task { @MainActor"),
            "deinit must cancel owned Tasks synchronously without initializing or retaining lazy coordinators"
        )

        print("SiteEntryTimeZoneSyncContractTests passed")
    }

    private static func occurrences(of needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
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
        _ message: String
    ) {
        guard condition() else { fatalError(message) }
    }
}
