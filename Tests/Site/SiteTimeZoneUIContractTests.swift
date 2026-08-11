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
            let editTimeZoneSection = substring(
                in: edit,
                from: "private func setupTimeZoneSection()",
                through: "private func setupSiteIconSection()"
            )
            let timeZoneContainerConstraints = substring(
                in: editTimeZoneSection,
                from: "timeZoneContainer.snp.makeConstraints",
                through: "timeZoneNameLabel.font"
            )
            require(
                appearsInOrder(
                    [
                        "timeZoneContainer.addSubview(timeZoneNameLabel)",
                        "timeZoneContainer.addSubview(timeZoneOffsetLabel)",
                        "timeZoneNameLabel.snp.makeConstraints"
                    ],
                    in: edit
                ),
                "Edit Site timezone siblings must share a superview before activating their cross-view constraint"
            )
            require(
                editTimeZoneSection.contains("contentView.addSubview(localTimeLabel)") &&
                    !editTimeZoneSection.contains("timeZoneContainer.addSubview(localTimeLabel)") &&
                    !edit.contains("timeZoneSeparator"),
                "Edit Site Local time must use the transparent content area outside the Time Zone row"
            )
            require(
                timeZoneContainerConstraints.contains("make.height.equalTo(SCRYFrom(44))") &&
                    !timeZoneContainerConstraints.contains("SCRYFrom(80)") &&
                    appearsInOrder(
                        [
                            "timeZoneContainer.addSubview(timeZoneButton)",
                            "contentView.addSubview(localTimeLabel)",
                            "localTimeLabel.snp.makeConstraints"
                        ],
                        in: editTimeZoneSection
                    ),
                "Edit Site Time Zone row must stay 44pt with Local time laid out below it"
            )
            require(
                edit.contains("init(") &&
                    edit.contains("site: SiteData") &&
                    edit.contains("draft: SitePropsEditDraft") &&
                    edit.contains("coordinator: SitePropsEditCoordinator") &&
                    edit.contains("returnToSitesHandler: @escaping ReturnToSitesHandler") &&
                    edit.contains("title = site.name"),
                "Dedicated Edit Site must receive prepared draft/coordinator and keep the Site name title"
            )
            require(
                appearsInOrder(
                    ["nameLabel", "timeZoneTitleLabel", "siteIconTitleLabel", "collectionView"],
                    in: edit
                ),
                "Edit Site content order must be Name, Time Zone, then Site Icon and icons"
            )
            require(
                edit.contains("\"site_time_zone_not_configured\".localizedString") &&
                    edit.contains("localTimeLabel.isHidden = true") &&
                    edit.contains("timeZoneValue.ianaId") &&
                    edit.contains("timeZoneValue.displayOffset"),
                "Timezone row must distinguish unconfigured and configured states"
            )
            require(
                edit.contains("SiteTimeZoneSelectionViewController") &&
                    edit.contains("draft.values.timezone = value") &&
                    edit.contains("updateTimeZoneDisplay()"),
                "Timezone selection must update only the edit draft and display"
            )
            require(
                edit.contains("private var modalDismissalStateBeforeTimeZone: Bool?") &&
                    edit.contains("restoreModalStackDismissalAfterTimeZoneIfNeeded()") &&
                    edit.contains("navigationController.isModalInPresentation = true") &&
                    edit.contains("navigationController?.isModalInPresentation = previousState") &&
                    edit.contains("modalDismissalStateBeforeTimeZone = nil") &&
                    !edit.contains("navigationController?.isModalInPresentation = false"),
                "Timezone flow must restore the modal stack's previous dismissal state after protecting it"
            )
            require(
                appearsInOrder(
                    [
                        "preventModalStackDismissalForTimeZone()",
                        "pushViewController(controller, animated: true)"
                    ],
                    in: edit
                ),
                "Timezone flow must protect the modal stack before pushing the selection page"
            )
            require(
                edit.contains("withTimeInterval: 0.5") &&
                    edit.contains("formattedLocalDate(at: Date())") &&
                    edit.contains("override func viewDidAppear") &&
                    edit.contains("override func viewWillDisappear") &&
                    edit.contains("UIApplication.didEnterBackgroundNotification") &&
                    edit.contains("UIApplication.willEnterForegroundNotification") &&
                    edit.contains("deinit"),
                "Local time must refresh from a fresh Date with complete visible/foreground lifecycle"
            )
            require(
                occurrences(of: "action: #selector(doneBtnClick)", in: edit) >= 2 &&
                    edit.contains("pendingSitePropsMask.isEmpty"),
                "Not synced and Done must share one action and pending visibility source"
            )
            require(
                edit.contains("\"site_icon\".localizedString") &&
                    edit.contains("(1...28).map { \"site_\\($0)\" }") &&
                    edit.contains("make.top.equalTo(localTimeLabel.snp.bottom)"),
                "Site Icon title must appear above the existing 28 Site icon assets"
            )
            require(
                edit.contains("make.height.equalTo(collectionView.snp.width)") &&
                    !edit.contains("make.height.equalTo(1)") &&
                    !edit.contains("updateCollectionHeightIfNeeded"),
                "Site Icon grid height must resolve from its width even when timezone is not configured"
            )
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
                    edit.contains("\"site_updated_toast\".localizedString") &&
                    edit.contains("\"site_update_failed_toast\".localizedString"),
                "Timezone uses status card while ordinary updates use exact Toasts"
            )
            require(
                status.contains("enum State") &&
                    status.contains("case saving") &&
                    status.contains("case success") &&
                    status.contains("case failure") &&
                    status.contains("doneButton.isHidden = state == .saving"),
                "Sync status must keep saving non-dismissible and expose terminal states"
            )
            require(
                status.contains("\"site_time_zone_sync_status\".localizedString") &&
                    status.contains("\"site_time_zone_saved_successfully\".localizedString") &&
                    status.contains("\"site_time_zone_saved_failed\".localizedString") &&
                    status.contains("\"site_no_gateways\".localizedString") &&
                    status.contains("\"site_no_gateways_sync_needed\".localizedString"),
                "Sync status copy must be localized and fixed to No gateways on success"
            )
            require(
                !status.localizedCaseInsensitiveContains("GatewayModel") &&
                    !status.localizedCaseInsensitiveContains("MeshNetwork") &&
                    !edit.contains("CloudSynchronizationManager"),
                "Edit Site status must not start gateway, Mesh, or whole-site synchronization"
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
                    siteEdit.contains("popViewController") &&
                    !siteEdit.contains("InfoEditViewController") &&
                    !siteEdit.contains("CloudSynchronizationManager"),
                "Site entry must use the same editor and return committed changes to Sites"
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
            "site_no_gateways_sync_needed"
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
                occurrences(of: "\(filename) in Sources", in: sourcePhase) == 4,
                "\(filename) must belong to all four Sources phases"
            )
        }

        let resourcePhase = substring(
            in: project,
            from: "/* Begin PBXResourcesBuildPhase section */",
            through: "/* End PBXResourcesBuildPhase section */"
        )
        require(
            occurrences(of: "all_utc_timezones.json in Resources", in: resourcePhase) == 4,
            "Timezone JSON must belong to all four Resources phases"
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
