import Foundation

@main
struct SiteTimeZoneUIContractTests {

    static func main() throws {
        let arguments = CommandLine.arguments
        if arguments.count == 5 {
            try testLocalizationAndTargetMembership(arguments: arguments)
            print("SiteTimeZoneUIContractTests passed")
            return
        }
        guard arguments.count == 3 || arguments.count == 4 || arguments.count == 7 else {
            fatalError("Expected selection, Edit Site, or full routing UI paths")
        }

        let selectionIndex = arguments.count >= 4 ? 2 : 1
        let controller = try String(contentsOfFile: arguments[selectionIndex], encoding: .utf8)
        let cell = try String(contentsOfFile: arguments[selectionIndex + 1], encoding: .utf8)

        require(
            controller.contains("private let catalog: SiteTimeZoneCatalog") &&
                controller.contains("sections = catalog.allSections") &&
                controller.contains("catalog.sections(matching: searchField.text ?? \"\")"),
            "Selection UI must consume catalog sections and catalog search"
        )
        require(
            !controller.contains("JSONDecoder") && !cell.contains("JSONDecoder"),
            "Selection UI must not parse the bundled JSON again"
        )
        require(
            controller.contains("\"site_time_zone_title\".localizedString") &&
                controller.contains("\"site_time_zone_search_placeholder\".localizedString") &&
                controller.contains("\"site_time_zone_empty\".localizedString"),
            "Title, search placeholder, and empty message must be localized"
        )
        let searchFieldSetup = substring(
            in: controller,
            from: "private func setupSearchField()",
            through: "private func setupTableView()"
        )
        require(
            appearsInOrder(
                [
                    "searchField.borderStyle = .none",
                    "searchField.backgroundColor = .white",
                    "searchField.layer.cornerRadius"
                ],
                in: searchFieldSetup
            ) &&
                !searchFieldSetup.contains("searchField.background =") &&
                !searchFieldSetup.contains("backgroundImage") &&
                !searchFieldSetup.contains(".subviews"),
            "Time Zone search field must disable the system rounded style before drawing its white background"
        )
        require(
            controller.contains("sections[section].region") &&
                cell.contains("ianaIdLabel.text = entry.ianaId") &&
                cell.contains("utcOffsetLabel.text = entry.value.displayOffset"),
            "Region headers and rows must show region, IANA identifier, and display offset"
        )
        require(
            controller.contains("onSelect(entry.value)") &&
                controller.contains("navigationController?.popViewController(animated: true)"),
            "Selecting a row must return the value and pop"
        )
        require(
            cell.contains("accessoryType = .none") &&
                !controller.contains("clearTimezone") &&
                !controller.contains("selectedTimeZone"),
            "This release must not show a checkmark or clear-timezone row"
        )
        if arguments.count >= 4 {
            let edit = try String(contentsOfFile: arguments[1], encoding: .utf8)
            let directory = URL(fileURLWithPath: arguments[1]).deletingLastPathComponent()
            let form = try String(contentsOf: directory.appendingPathComponent("SiteCreateViewController.swift"), encoding: .utf8)
            require(edit.contains("SiteEditViewController: SiteFormViewController") &&
                    edit.contains("draft: SitePropsEditDraft") && edit.contains("coordinator: SitePropsEditCoordinator"),
                    "Edit must consume the prepared draft through the shared form")
            require(form.contains("\"site_edit_title\"") && form.contains("\"done\"") && !edit.contains("title = site.name"),
                    "Edit must have a fixed localized title and DONE action")
            require(form.contains("timeSection.addArrangedSubview(localTimeLabel)") &&
                    form.contains("formDraft.timezone?.ianaId") && form.contains("formDraft.timezone?.displayOffset"),
                    "Shared time zone row retains its local time display")
            require(form.contains("formDraft.selectManualTimezone(value)") && form.contains("SiteTimeZoneSelectionViewController"),
                    "Time zone selection modifies the shared draft")
            require(form.contains("navigationController.isModalInPresentation = true") &&
                    form.contains("navigationController?.isModalInPresentation = previous") &&
                    form.contains("modalDismissalStateBeforeTimeZone = nil"),
                    "Time zone navigation must restore the previous modal dismissal policy")
            // Clock arithmetic is exercised by SiteTimeZoneSnapshotTests, independently of source spelling.
            require(form.contains("override func viewDidAppear") &&
                    form.contains("override func viewWillDisappear") && form.contains("UIApplication.didEnterBackgroundNotification") &&
                    form.contains("UIApplication.didBecomeActiveNotification"), "Shared clock retains its visible/active lifecycle")
            require(occurrences(of: "action: #selector(submit)", in: form) == 2 &&
                    form.contains("pendingSitePropsMask.contains(.timezone)") && form.contains("notSyncedButton.isEnabled = createButton.isEnabled"),
                    "Pending timezone and DONE must share validation and submission")
            require(form.contains("SiteFormDraft.canSubmit") && form.contains("editingSite == nil ? .button : .staticText"),
                    "Shared validation and read-only Site type must be used by Edit")
        }

        require(
            appearsInOrder(
                [
                    "cardView.addSubview(ianaIdLabel)",
                    "cardView.addSubview(utcOffsetLabel)",
                    "ianaIdLabel.snp.makeConstraints"
                ],
                in: cell
            ),
            "Timezone cell siblings must share a superview before activating their cross-view constraint"
        )

        if arguments.count == 7 {
            let edit = try String(contentsOfFile: arguments[1], encoding: .utf8)
            let status = try String(contentsOfFile: arguments[4], encoding: .utf8)
            let sites = try String(contentsOfFile: arguments[5], encoding: .utf8)
            let site = try String(contentsOfFile: arguments[6], encoding: .utf8)

            require(
                edit.contains("coordinator.makeCommitPlan") &&
                    edit.contains("coordinator.persist") &&
                    edit.contains("await coordinator.submit") &&
                    edit.contains("NetworkRequest.shared.networkable"),
                "Done must plan, persist, and submit through the coordinator"
            )
            require(
                edit.contains("plan.includesTimezone") &&
                    edit.contains("showTimeZoneConfirmation") &&
                    edit.contains("showOfflineTimeZoneAlert") &&
                    edit.contains("\"site_update_time_zone_title\".localizedString") &&
                    edit.contains("\"site_you_are_offline\".localizedString"),
                "Timezone commits must branch to the approved online confirmation or offline alert"
            )
            require(
                edit.contains("SiteTimeZoneSyncStatusView") &&
                    edit.contains("statusView.show()") &&
                    !edit.contains("statusView.show(in: resultHost)") &&
                    status.contains("func show(in parentView: UIView? = nil)") &&
                    status.contains("parentView ?? Self.activeWindow") &&
                    edit.contains("\"site_updated_toast\".localizedString") &&
                    edit.contains("\"site_update_failed_toast\".localizedString"),
                "Timezone status must cover the active window while ordinary updates use source-hosted Toasts"
            )
            require(
                status.contains("var onDone: (() -> Void)?") &&
                    status.contains("func update(state: SiteTimeZoneSyncPresentationState)") &&
                    status.contains("private(set) var state: SiteTimeZoneSyncPresentationState") &&
                    !status.contains("enum State"),
                "Sync status must consume only the shared presentation state and expose the optional DONE callback"
            )
            let statusUpdate = substring(
                in: status,
                from: "func update(state: SiteTimeZoneSyncPresentationState)",
                through: "private func setupUI()"
            )
            let workingUpdate = substring(
                in: statusUpdate,
                from: "case .working(let stage):",
                through: "case let .result(site, gateways):"
            )
            let resultUpdate = substring(
                in: status,
                from: "case let .result(site, gateways):",
                through: "private func setupUI()"
            )
            require(
                appearsInOrder(
                    [
                        "let wasWorking = self.state.isWorking",
                        "self.state = state"
                    ],
                    in: statusUpdate
                ) &&
                    workingUpdate.contains("if !wasWorking") &&
                    workingUpdate.contains("resultContentScrollView.setContentOffset(.zero, animated: false)") &&
                    !resultUpdate.contains("setContentOffset") &&
                    occurrences(of: "resultContentScrollView.setContentOffset(.zero, animated: false)", in: statusUpdate) == 1,
                "Only a new working session may reset the reused result scroll position; batch and terminal updates must preserve it"
            )
            require(
                status.contains("private let gatewayStatusView = SiteEntryGatewayTimeZoneStatusView()") &&
                    status.contains("gatewayStatusView.update(gateways)") &&
                    status.contains("gatewayStatusView.preferredHeight") &&
                    !status.contains("gatewayStatusView.minimumViewportHeight") &&
                    status.contains("case .notStarted:") &&
                    status.contains("gatewayStatusView.isHidden = true") &&
                    !status.contains("private let gatewayCard") &&
                    !status.contains("\"site_no_gateways\".localizedString") &&
                    !status.contains("\"site_no_gateways_sync_needed\".localizedString"),
                "Sync status must use the shared Gateway component, hide not-started, and remove its fixed No gateways card"
            )
            let scrollConfiguration = substring(
                in: status,
                from: "private func configureResultContentScrollView()",
                through: "private func configureResultTitle()"
            )
            require(
                status.contains("private let resultContentScrollView = UIScrollView()") &&
                    status.contains("private let resultContentView = UIView()") &&
                    scrollConfiguration.contains("resultCardView.addSubview(resultContentScrollView)") &&
                    scrollConfiguration.contains("resultContentScrollView.addSubview(resultContentView)") &&
                    scrollConfiguration.contains("make.edges.equalTo(resultContentScrollView.contentLayoutGuide)") &&
                    scrollConfiguration.contains("make.width.equalTo(resultContentScrollView.frameLayoutGuide)") &&
                    scrollConfiguration.contains("resultContentScrollView.alwaysBounceVertical = false"),
                "Result title, Site, and Gateway content must live in one vertically scrolling container"
            )
            let gatewayStatusConfiguration = substring(
                in: status,
                from: "private func configureGatewayStatusView()",
                through: "private func configureDoneFooter()"
            )
            require(
                gatewayStatusConfiguration.contains("gatewayStatusView.onPreferredHeightChanged = { [weak self] in") &&
                    gatewayStatusConfiguration.contains("guard let self") &&
                    gatewayStatusConfiguration.contains("case let .result(_, gateways) = self.state") &&
                    gatewayStatusConfiguration.contains("self.updateResultSheetLayout(for: gateways)"),
                "Sync status must weakly consume Gateway height changes only while showing a result"
            )
            let siteStatusUpdate = substring(
                in: status,
                from: "private func updateSiteStatus(",
                through: "private func updateStatusIndicator()"
            )
            require(
                status.contains("\"site_time_zone_sync_status\".localizedString") &&
                    status.contains("siteStatusCardView") &&
                    siteStatusUpdate.contains("_: SiteTimeZoneSyncSitePresentation") &&
                    siteStatusUpdate.contains("\"site_time_zone_row_title\".localizedString") &&
                    siteStatusUpdate.contains("\"site_time_zone_saved_successfully\".localizedString") &&
                    !siteStatusUpdate.contains("site_entry_sync_updated") &&
                    !siteStatusUpdate.contains("failedToUpdateServer"),
                "Edit sync status must use the Time zone title and local Saved successfully semantics"
            )
            let checkingConfiguration = substring(
                in: status,
                from: "private func setupCheckingCard()",
                through: "private func setupResultSheet()"
            )
            require(
                checkingConfiguration.contains("make.height.greaterThanOrEqualTo(SCRYFrom(188))") &&
                    checkingConfiguration.contains("make.top.greaterThanOrEqualTo(safeAreaLayoutGuide.snp.top)") &&
                    checkingConfiguration.contains("make.bottom.lessThanOrEqualTo(safeAreaLayoutGuide.snp.bottom)") &&
                    checkingConfiguration.contains("make.height.greaterThanOrEqualTo(SCRYFrom(26))") &&
                    checkingConfiguration.contains("make.height.greaterThanOrEqualTo(SCRYFrom(44))") &&
                    checkingConfiguration.contains("make.bottom.equalToSuperview().inset(SCRYFrom(24))") &&
                    !checkingConfiguration.contains("make.height.equalTo(SCRYFrom(188))") &&
                    !checkingConfiguration.contains("make.height.equalTo(SCRYFrom(26))") &&
                    !checkingConfiguration.contains("make.height.equalTo(SCRYFrom(44))"),
                "Checking card copy must use multiline intrinsic heights, expand from its Figma minimum, and remain within the safe area"
            )
            let resultTitleConfiguration = substring(
                in: status,
                from: "private func configureResultTitle()",
                through: "private func configureSiteStatusCard()"
            )
            let siteStatusConfiguration = substring(
                in: status,
                from: "private func configureSiteStatusCard()",
                through: "private func configureGatewayStatusView()"
            )
            require(
                resultTitleConfiguration.contains("resultTitleLabel.numberOfLines = 0") &&
                    resultTitleConfiguration.contains("resultContentView.addSubview(resultTitleLabel)") &&
                    resultTitleConfiguration.contains("make.height.greaterThanOrEqualTo(SCRYFrom(25))") &&
                    !resultTitleConfiguration.contains("make.height.equalTo(SCRYFrom(25))") &&
                    siteStatusConfiguration.contains("resultContentView.addSubview(siteStatusCardView)") &&
                    siteStatusConfiguration.contains("make.height.greaterThanOrEqualTo(SCRYFrom(64))") &&
                    siteStatusConfiguration.contains("siteValueLabel.numberOfLines = 0") &&
                    siteStatusConfiguration.contains("siteStatusLabel.numberOfLines = 0") &&
                    siteStatusConfiguration.contains("make.top.bottom.equalToSuperview().inset(SCRYFrom(14))") &&
                    !siteStatusConfiguration.contains("make.height.equalTo(SCRYFrom(64))") &&
                    !siteStatusConfiguration.contains("make.height.equalTo(SCRYFrom(20))") &&
                    !siteStatusConfiguration.contains("make.height.equalTo(SCRYFrom(16))"),
                "Result title and Site status card must grow from intrinsic multiline content instead of fixed single-line heights"
            )
            let resultSheetConfiguration = substring(
                in: status,
                from: "private func setupResultSheet()",
                through: "private func configureResultShadows()"
            )
            require(
                status.contains("UIColor.black.withAlphaComponent(0.4)") &&
                    status.contains("resultCardView.layer.cornerRadius = SCRYFrom(24)") &&
                    resultSheetConfiguration.contains("make.left.right.equalToSuperview()") &&
                    !resultSheetConfiguration.contains("make.width.equalTo(SCRXFrom(343))") &&
                    !resultSheetConfiguration.contains("make.centerX.equalToSuperview()") &&
                    resultSheetConfiguration.contains("make.bottom.equalTo(safeAreaLayoutGuide.snp.bottom)") &&
                    resultSheetConfiguration.contains("make.top.greaterThanOrEqualTo(safeAreaLayoutGuide.snp.top).offset(SCRYFrom(16))"),
                "Sync status result sheet must stay full-width and grow upward within the safe area"
            )
            require(
                status.contains("private let bottomSafeAreaBackgroundView = UIView()") &&
                    resultSheetConfiguration.contains("bottomSafeAreaBackgroundView.backgroundColor = .white") &&
                    appearsInOrder(
                        [
                            "addSubview(bottomSafeAreaBackgroundView)",
                            "addSubview(resultCardView)",
                            "configureResultShadows()",
                            "bringSubviewToFront(resultCardView)"
                        ],
                        in: resultSheetConfiguration
                    ) &&
                    resultSheetConfiguration.contains("make.top.equalTo(safeAreaLayoutGuide.snp.bottom)") &&
                    resultSheetConfiguration.contains("make.left.right.bottom.equalToSuperview()") &&
                    status.contains("bottomSafeAreaBackgroundView.isHidden = state.isWorking") &&
                    status.contains("footerHeightConstraint.update(offset: state.canDismiss ? SCRYFrom(61) : 0)"),
                "Sync status must keep a result-only white bottom safe area without moving DONE"
            )
            require(
                status.contains("doneButton.isHidden = !state.canDismiss") &&
                    status.contains("guard state.canDismiss else { return }") &&
                    status.contains("if let onDone") &&
                    status.contains("onDone()") &&
                    status.contains("removeFromSuperview()") &&
                    status.contains("\"site_entry_sync_done\".localizedString"),
                "DONE must remain guarded, delegate to a host callback, or self-remove for callback-free terminal flows"
            )
            require(
                !status.contains("UITapGestureRecognizer") &&
                    !status.contains("addGestureRecognizer") &&
                    status.contains("accessibilityViewIsModal = true"),
                "The unified status background must remain modal with no tap-to-dismiss path"
            )
            require(
                status.contains("private var resultCardHeightConstraint: Constraint!") &&
                    status.contains("resultCardHeightConstraint.update") &&
                    status.contains("resultCardHeightConstraint.deactivate()") &&
                    status.contains("safeAreaLayoutGuide.snp.height") &&
                    status.contains("SiteTimeZoneSyncResultLayoutPolicy.makeLayout(") &&
                    status.contains("contentHeight: measuredContentHeight") &&
                    status.contains("availableHeight: availableResultHeight") &&
                    !status.contains("availableGatewayViewportHeight") &&
                    status.contains("UIView.animate"),
                "The unified result sheet must drop its height while working and cap the complete scroll content plus fixed footer to its safe-area budget"
            )
            let resultMeasurement = substring(
                in: status,
                from: "private func measuredResultContentHeight(",
                through: "private func updateSiteStatus("
            )
            require(
                resultMeasurement.contains("systemLayoutSizeFitting(") &&
                    resultMeasurement.contains("withHorizontalFittingPriority: .required") &&
                    resultMeasurement.contains("verticalFittingPriority: .fittingSizeLevel") &&
                    resultMeasurement.contains("measuredResultTitleHeight") &&
                    resultMeasurement.contains("measuredSiteStatusCardHeight") &&
                    resultMeasurement.contains("gatewayStatusView.preferredHeight") &&
                    resultMeasurement.contains("resultCardView.bounds.width") &&
                    resultMeasurement.contains("bounds.width") &&
                    !resultMeasurement.contains("24 + 25 + 16 + 64 + 16"),
                "Result sheet fixed content must measure title and Site card Auto Layout heights with a pre-layout width fallback"
            )
            let traitRemeasurement = substring(
                in: status,
                from: "override func traitCollectionDidChange(",
                through: "func show(in parentView:"
            )
            require(
                traitRemeasurement.contains("preferredContentSizeCategory") &&
                    traitRemeasurement.contains("invalidateIntrinsicContentSize()") &&
                    traitRemeasurement.contains("updateResultSheetLayout(for: gateways)") &&
                    traitRemeasurement.contains("setNeedsLayout()"),
                "Content size category changes must invalidate intrinsic sizes and remeasure the result sheet and Gateway viewport"
            )
            require(
                status.contains("private let footerContainerView = UIView()") &&
                    status.contains("private var footerHeightConstraint: Constraint!") &&
                    status.contains("footerHeightConstraint.update(offset: state.canDismiss ? SCRYFrom(61) : 0)") &&
                    status.contains("footerContainerView.isHidden = !state.canDismiss") &&
                    status.contains("if !wasDismissible && state.canDismiss") &&
                    status.contains("let requestedFooterHeight = state.canDismiss ? SCRYFrom(61) : 0"),
                "The unified footer must collapse while working or pushing and expand to 61 only at terminal state"
            )
            let footerConfiguration = substring(
                in: status,
                from: "private func configureDoneFooter()",
                through: "private func updateWorkingCopy("
            )
            require(
                footerConfiguration.contains("make.left.right.bottom.equalToSuperview()") &&
                    footerConfiguration.contains("make.bottom.equalTo(footerContainerView.snp.top)") &&
                    !footerConfiguration.contains("make.top.equalTo(gatewayStatusView.snp.bottom)") &&
                    gatewayStatusConfiguration.contains("resultContentView.addSubview(gatewayStatusView)") &&
                    gatewayStatusConfiguration.contains("make.bottom.equalToSuperview().inset(SCRYFrom(16))"),
                "DONE footer must stay pinned to the result card while the scroll content has a complete title-to-Gateway bottom chain"
            )
            require(
                status.contains("UIImage(named: \"site_entry_sync_loading\")") &&
                    status.contains("UIImage(named: \"site_entry_sync_success\")") &&
                    status.contains("checkingCardView.layer.cornerRadius = SCRYFrom(20)"),
                "The unified status must preserve the checking animation and Site success visual"
            )
            require(
                !status.localizedCaseInsensitiveContains("GatewayModel") &&
                    !status.localizedCaseInsensitiveContains("MeshNetwork") &&
                    !edit.contains("CloudSynchronizationManager"),
                "Edit Site status must not start gateway, Mesh, or whole-site synchronization"
            )

            let timeZoneCommit = substring(
                in: edit,
                from: "private func finishTimeZoneCommit(",
                through: "private func finishEditing("
            )
            require(
                edit.contains(
                    "var timeZoneSyncDidFinish: ((SiteTimeZoneEditSyncOutcome) -> Void)?"
                ) &&
                    appearsInOrder(
                        [
                            "guard online else",
                            "SiteTimeZoneSyncStatusView()"
                        ],
                        in: timeZoneCommit
                    ) &&
                    timeZoneCommit.contains("SiteGatewayLocalTimeZoneContextBuilder.make(") &&
                    timeZoneCommit.contains("SiteGatewayCloudTimeZoneSessionCoordinator(") &&
                    timeZoneCommit.contains("SiteTimeZoneEditSyncCoordinator(") &&
                    !timeZoneCommit.contains("SiteTimeZoneRemoteSnapshotProvider") &&
                    !timeZoneCommit.contains("remoteSnapshot"),
                "Offline timezone commits must exit before local Gateway targets are created, and online Edit must not fetch another Site snapshot"
            )
            require(
                timeZoneCommit.contains("statusView.update(state: .working(.savingSite))") &&
                    timeZoneCommit.contains("statusView.show()") &&
                    timeZoneCommit.contains("await editSyncCoordinator.run(") &&
                    timeZoneCommit.contains("snapshot: snapshot") &&
                    timeZoneCommit.contains("statusView.update(state: state)") &&
                    !timeZoneCommit.contains("await coordinator.submit") &&
                    !timeZoneCommit.contains("success ? .success : .failure"),
                "Online timezone commits must stream the shared Edit coordinator into the unified view"
            )
            require(
                timeZoneCommit.contains("guard snapshot.values.timezone != nil else") &&
                    timeZoneCommit.contains("guard let snapshot else") &&
                    timeZoneCommit.contains("site: .savedSuccessfully") &&
                    timeZoneCommit.contains("gateways: .notStarted") &&
                    timeZoneCommit.contains("callback?(.siteFailed)") &&
                    timeZoneCommit.contains(
                        "[statusView, editSyncCoordinator, callback, siteDidChange]"
                    ) &&
                    timeZoneCommit.contains("callback?(outcome)"),
                "Missing snapshots after persistence must retain local save success, stop cloud work, and keep the post-dismiss flow strongly owned"
            )

            let sitesEdit = substring(in: sites, from: "private func editSite(site: SiteData)", through: "/// 删除场所")
            let siteEdit = substring(in: site, from: "private func editSite()", through: "/// 删除场所")
            require(
                sitesEdit.contains("SitePropsEditCoordinator") &&
                    sitesEdit.contains("await coordinator.prepareDraft") &&
                    sitesEdit.contains("SiteEditViewController") &&
                    !sitesEdit.contains("InfoEditViewController") &&
                    !sitesEdit.contains("CloudSynchronizationManager"),
                "Sites entry must await retrieve before presenting the dedicated editor"
            )
            require(
                siteEdit.contains("SitePropsEditCoordinator") &&
                    siteEdit.contains("await coordinator.prepareDraft") &&
                    siteEdit.contains("SiteEditViewController") &&
                    siteEdit.contains("finishEditingHandler:") &&
                    siteEdit.contains("completion(self.view)") &&
                    !siteEdit.contains("popViewController") &&
                    !siteEdit.contains("SitesViewController") &&
                    !siteEdit.contains("InfoEditViewController") &&
                    !siteEdit.contains("CloudSynchronizationManager"),
                "Site entry must use the same editor and keep committed changes on Site"
            )
            require(
                sitesEdit.contains("vc.timeZoneSyncDidFinish = { [weak self] _ in") &&
                    sitesEdit.contains("self?.reloadSiteData(site)") &&
                    !sitesEdit.contains("gatewayTimeZoneReviewContext") &&
                    !sitesEdit.contains("silentGatewayReconcile"),
                "Sites terminal timezone outcomes must only reload the existing Site cell"
            )
            require(
                siteEdit.contains(
                    "vc.timeZoneSyncDidFinish = { [weak self] outcome in"
                ) &&
                    siteEdit.contains("self?.reconcileEditTimeZoneSyncOutcome(outcome)") &&
                    site.contains(
                        "private func reconcileEditTimeZoneSyncOutcome("
                    ) &&
                    site.contains(
                        "confirmedGatewayOffsetMinutesByID = result.confirmedOffsetMinutesByGatewayID"
                    ) &&
                    site.contains("gatewayTimeZoneReviewContext = result.reviewContext") &&
                    site.contains("refreshCurrentGatewayTimeZoneReviewProjection()") &&
                    site.contains("performSiteLoad(presentation: .silentGatewayReconcile)"),
                "Site terminal timezone outcomes must reconcile the shared result and silently refresh"
            )
        }

        print("SiteTimeZoneUIContractTests passed")
    }

    private static func testLocalizationAndTargetMembership(arguments: [String]) throws {
        let english = try String(contentsOfFile: arguments[1], encoding: .utf8)
        let simplifiedChinese = try String(contentsOfFile: arguments[2], encoding: .utf8)
        let project = try String(contentsOfFile: arguments[3], encoding: .utf8)
        let timezoneJSON = try Data(contentsOf: URL(fileURLWithPath: arguments[4]))

        let keys = [
            "site_edit_title",
            "site_time_zone_title",
            "site_time_zone_search_placeholder",
            "site_time_zone_empty",
            "site_time_zone_not_configured",
            "site_not_synced_to_server",
            "site_icon",
            "site_local_time_format",
            "site_update_time_zone_message",
            "site_update_time_zone_title",
            "site_update_time_zone_action",
            "site_you_are_offline",
            "site_time_zone_offline_message",
            "site_got_it",
            "site_update_failed_toast",
            "site_updated_toast",
            "site_time_zone_saving_to_server",
            "site_time_zone_saved_successfully",
            "site_time_zone_saved_failed",
            "site_time_zone_sync_status",
            "site_sync_section_site",
            "site_time_zone_row_title",
            "site_sync_section_gateways",
            "site_no_gateways",
            "site_no_gateways_sync_needed",
            "site_time_zone_gateway_check_unavailable_title",
            "site_time_zone_gateway_check_unavailable_message"
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
        }

        let sourcePhase = substring(
            in: project,
            from: "/* Begin PBXSourcesBuildPhase section */",
            through: "/* End PBXSourcesBuildPhase section */"
        )
        let newSourceFiles = [
            "SiteCreateViewController.swift",
            "SiteEditViewController.swift",
            "SiteCreationDraft.swift",
            "SiteTimeZoneValue.swift",
            "SiteTimeZoneCatalog.swift",
            "SitePropsEditPolicy.swift",
            "SitePropsAPIClient.swift",
            "SitePropsEditCoordinator.swift",
            "SiteTimeZoneSelectionViewController.swift",
            "SiteTimeZoneSelectionCell.swift",
            "SiteTimeZoneSyncStatusView.swift",
            "SiteEntryTimeZoneSyncPolicy.swift",
            "SiteEntryTimeZoneSyncResponseParser.swift",
            "SiteEntryTimeZoneSyncCoordinator.swift",
            "SiteEntryTimeZoneSyncOverlay.swift"
        ]
        for filename in newSourceFiles {
            require(
                occurrences(of: "\(filename) in Sources", in: sourcePhase) == 6,
                "\(filename) must belong to all six Sources phases"
            )
        }
        let resourcePhase = substring(
            in: project,
            from: "/* Begin PBXResourcesBuildPhase section */",
            through: "/* End PBXResourcesBuildPhase section */"
        )
        require(
            occurrences(of: "all_utc_timezones.json in Resources", in: resourcePhase) == 6,
            "Timezone JSON must belong to all six Resources phases"
        )
        let timezoneObject = try JSONSerialization.jsonObject(with: timezoneJSON)
        require(
            timezoneObject is [[String: Any]],
            "Timezone JSON must remain a valid top-level array"
        )
    }

    private static func appearsInOrder(_ needles: [String], in text: String) -> Bool {
        var searchStart = text.startIndex
        for needle in needles {
            guard let range = text.range(of: needle, range: searchStart..<text.endIndex) else {
                return false
            }
            searchStart = range.upperBound
        }
        return true
    }

    private static func occurrences(of needle: String, in text: String) -> Int {
        return text.components(separatedBy: needle).count - 1
    }

    private static func substring(in text: String, from start: String, through end: String) -> String {
        guard let startRange = text.range(of: start),
              let endRange = text.range(of: end, range: startRange.upperBound..<text.endIndex) else {
            return ""
        }
        return String(text[startRange.lowerBound..<endRange.lowerBound])
    }

    private static func require(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) {
        guard condition() else {
            fatalError(message)
        }
    }
}
