import UIKit

/// This screen never activates Mesh or starts configuration synchronization.
final class SpaceRecoveryViewController: UIViewController {
    let spaceID: String
    private let message = UILabel()
    private let retry: () -> Void
    private let leave: (() -> Void)?
    private let space: SpaceData
    private let defaultRepairCompleted: ((SpaceData) -> Void)?
    private var defaultRepairButton: UIButton?
    private static var repairsInProgress = Set<String>()
    private var reason: String
    private let scope: SpaceMembershipRecord.Scope
    init(space: SpaceData, reason: String, retry: @escaping () -> Void, leave: (() -> Void)?,
         defaultRepairCompleted: ((SpaceData) -> Void)? = nil) {
        spaceID = space.id; self.reason = reason; self.retry = retry; self.leave = leave
        self.space = space; self.defaultRepairCompleted = defaultRepairCompleted
        scope = SpaceMembershipCoordinator.scope(space)
        super.init(nibName: nil, bundle: nil)
        title = space.name
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func update(reason: String) {
        self.reason = reason; message.text = Self.message(reason)
        defaultRepairButton?.isHidden = !Self.canRepairDefaults(space)
    }

    static func message(_ reason: String) -> String {
        switch reason {
        case "spaceLeaving": return "space_leave_pending".localizedString
        case "leaveConfirmed": return "space_leave_cleanup_pending".localizedString
        case "configurationNodeDecodeFailed", "configurationGroupDecodeFailed", "configurationSchedulerRestoreFailed",
             "invalidRemoteSchedulerModelStates", "missingRequiredArray": return "space_recovery_data_failed".localizedString
        case "configurationPersistenceFailed", "configurationStagingFailed", "configurationReferenceStagingFailed": return "space_recovery_storage_failed".localizedString
        case "configurationFinalizationFailed": return "space_recovery_finalize_failed".localizedString
        case "networkIdentityMismatch", "invalidNetworkIdentity": return "space_recovery_identity_failed".localizedString
        case "staleMembershipResponse", "staleImportPreparation", "recoverySourceChanged": return "space_recovery_changed".localizedString
        case "networkUnavailable": return "space_recovery_network_failed".localizedString
        case "invalidHDBPayload": return "space_recovery_hdb_invalid".localizedString
        case "configurationDefaultRepairUnavailable": return "space_recovery_default_unavailable".localizedString
        default: return "space_recovery_unavailable".localizedString
        }
    }
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        NotificationCenter.default.addObserver(self, selector: #selector(membershipChanged),
            name: .init(SitesDataRefreshNotifiacationName), object: nil)
        let scroll = UIScrollView(); scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        let stack = UIStackView(); stack.axis = .vertical; stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false; scroll.addSubview(stack)
        message.numberOfLines = 0; message.font = .preferredFont(forTextStyle: .body)
        message.adjustsFontForContentSizeCategory = true; message.text = Self.message(reason)
        stack.addArrangedSubview(message)
        addButton("space_recovery_retry", action: #selector(retryAction), to: stack)
        if SpaceRepairViewController.canOpen(space) { addButton("space_repair_title", action: #selector(repairAction), to: stack) }
        let fix = UIButton(type: .system)
        fix.setTitle("space_recovery_fix_defaults".localizedString, for: .normal)
        fix.titleLabel?.numberOfLines = 0
        fix.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        fix.addTarget(self, action: #selector(defaultRepairAction), for: .touchUpInside)
        fix.isHidden = !Self.canRepairDefaults(space)
        stack.addArrangedSubview(fix); defaultRepairButton = fix
        if leave != nil { addButton("space_leave_action", action: #selector(leaveAction), to: stack) }
        addButton("space_saved_copies", action: #selector(copiesAction), to: stack)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 32),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -48)
        ])
    }
    @objc private func membershipChanged() {
        guard scope.account == UserData.currentUserId,
              scope.region == String(describing: UserData.currentServerRegion),
              let record = try? SpaceMembershipCoordinator.store.read(scope) else { return }
        if record.phase == .left {
            if navigationController?.topViewController === self { navigationController?.popViewController(animated: true) }
        } else if record.phase == .confirmed { update(reason: "leaveConfirmed") }
    }
    private func addButton(_ key: String, action: Selector, to stack: UIStackView) {
        let button = UIButton(type: .system)
        button.setTitle(key.localizedString, for: .normal)
        button.titleLabel?.numberOfLines = 0
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        button.addTarget(self, action: action, for: .touchUpInside)
        stack.addArrangedSubview(button)
    }
    @objc private func retryAction() { retry() }
    @objc private func repairAction() { navigationController?.pushViewController(SpaceRepairViewController(space: space), animated: true) }
    @objc private func defaultRepairAction() {
        Self.offerDefaultRepair(space, from: self) { [weak self] repaired in
            self?.defaultRepairCompleted?(repaired)
        }
    }
    @objc private func leaveAction() { leave?() }
    @objc private func copiesAction() { navigationController?.pushViewController(SpaceSavedCopiesViewController(), animated: true) }

    static func canRepairDefaults(_ space: SpaceData) -> Bool {
        guard let latest = SpaceData.load(siteId: space.siteId, spaceId: space.id).first,
              SpaceConfigurationSafety.canAutomaticallyUpload(latest),
              !SpaceMembershipCoordinator.isLeaving(latest),
              !SpaceConfigurationSafety.hasPendingImport(latest),
              !SpaceConfigurationSafety.hasPendingDeletionCleanup(latest) else { return false }
        return latest.hdbLoadFailed || latest.hdb != nil
            || (try? SiteData.load(siteId: latest.siteId)?.loadIsHdbSite()) == true
    }

    static func offerDefaultRepair(_ space: SpaceData, from presenter: UIViewController,
                                   completed: @escaping (SpaceData) -> Void) {
        guard presenter.presentedViewController == nil, canRepairDefaults(space) else { return }
        let scope = SpaceMembershipCoordinator.scope(space)
        let alert = UIAlertController(title: "space_recovery_fix_defaults".localizedString,
            message: "space_recovery_fix_defaults_confirm".localizedString, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "cancel".localizedString, style: .cancel))
        alert.addAction(UIAlertAction(title: "space_recovery_fix_defaults".localizedString, style: .destructive) { [weak presenter] _ in
            guard let presenter else { return }
            Task { @MainActor in
                guard scope.account == UserData.currentUserId,
                      scope.region == String(describing: UserData.currentServerRegion) else { return }
                let operation = "\(scope.account)|\(scope.region)|\(scope.siteID)|\(scope.spaceID)"
                guard repairsInProgress.insert(operation).inserted else { return }
                defer { repairsInProgress.remove(operation) }
                guard let latest = SpaceData.load(siteId: space.siteId, spaceId: space.id).first,
                      canRepairDefaults(latest) else { return }
                XWHUDManager.showCustomHUD(withMessage: "syncing_data".localizedString, isWindow: true)
                let response = await NetworkRequest.shared.request(.spaceInfo(siteId: latest.siteId,
                    spaceId: latest.id, password: latest.authorizationPassword))
                guard !Task.isCancelled, scope.account == UserData.currentUserId,
                      scope.region == String(describing: UserData.currentServerRegion),
                      presenter.viewIfLoaded?.window != nil else { XWHUDManager.hide(); return }
                switch response {
                case .failure(let error):
                    XWHUDManager.hide()
                    SpaceConfigurationSafety.handleAuthorityError(error, space: latest)
                    XWHUDManager.showErrorTipHUD(error.localizedDescription)
                case .success(let response):
                    guard let remote = response["data"] as? [String: Any] else {
                        XWHUDManager.hide()
                        XWHUDManager.showErrorTipHUD("space_recovery_default_unavailable".localizedString); return
                    }
                    let outcome = await latest.restoreConfiguration(spaceJsonData: remote,
                        authoritativeGET: true, fixWithDefaults: true)
                    XWHUDManager.hide()
                    guard scope.account == UserData.currentUserId,
                          scope.region == String(describing: UserData.currentServerRegion),
                          presenter.viewIfLoaded?.window != nil else { return }
                    guard outcome.status == .applied, !SpaceConfigurationSafety.isBlocked(latest) else {
                        XWHUDManager.showErrorTipHUD(message(outcome.rejectionReason ?? "configurationDefaultRepairUnavailable")); return
                    }
                    if latest.needUploadCloud {
                        CloudSynchronizationManager.shared.addSynchronizationHandle(operation: .syncSpace(space: latest), level: .promptly)
                    }
                    completed(latest)
                }
            }
        })
        presenter.present(alert, animated: true)
    }
}

final class SpaceSavedCopiesViewController: UITableViewController {
    private var files: [URL] = []
    private var account = "", region = ""
    private let descriptionLabel = UILabel()
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "space_saved_copies".localizedString
        account = UserData.currentUserId; region = String(describing: UserData.currentServerRegion)
        files = ((try? FileManager.default.contentsOfDirectory(at: SpaceMembershipCoordinator.savedCopiesDirectory,
            includingPropertiesForKeys: [.creationDateKey])) ?? []).filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        descriptionLabel.numberOfLines = 0
        descriptionLabel.text = "space_saved_copies_description".localizedString
        descriptionLabel.font = .preferredFont(forTextStyle: .body)
        descriptionLabel.adjustsFontForContentSizeCategory = true
        let header = UIView(); header.addSubview(descriptionLabel)
        tableView.tableHeaderView = header
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard let header = tableView.tableHeaderView else { return }
        let width = max(1, tableView.bounds.width - 40)
        let height = descriptionLabel.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        descriptionLabel.frame = CGRect(x: 20, y: 16, width: width, height: height)
        if header.frame.height != height + 32 || header.frame.width != tableView.bounds.width {
            header.frame = CGRect(x: 0, y: 0, width: tableView.bounds.width, height: height + 32)
            tableView.tableHeaderView = header
        }
    }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { files.count }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.text = files[indexPath.row].lastPathComponent
        cell.textLabel?.numberOfLines = 0; cell.accessoryType = .disclosureIndicator
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard account == UserData.currentUserId, region == String(describing: UserData.currentServerRegion), presentedViewController == nil else { return }
        let activity = UIActivityViewController(activityItems: [files[indexPath.row]], applicationActivities: nil)
        activity.popoverPresentationController?.sourceView = tableView
        activity.popoverPresentationController?.sourceRect = tableView.rectForRow(at: indexPath)
        present(activity, animated: true)
    }
}

/// Recovery stays available independently of ordinary configuration editing.
/// Destructive choices are previewed against a fresh server snapshot.
final class SpaceRepairViewController: UITableViewController {
    private enum Action: String, CaseIterable {
        case copies = "space_saved_copies"
        case retry = "space_recovery_retry"
        case defaults = "space_recovery_fix_defaults"
        case cloud = "configuration_reload_cloud"
        case local = "configuration_use_local"
        case references = "space_repair_references"
        case remove = "space_repair_remove_selected"
        case clear = "space_repair_clear"
        case delete = "space_repair_delete"
    }
    private let space: SpaceData
    private let scope: SpaceMembershipRecord.Scope
    private var remote: [String: Any]?
    private var local: [String: Any]?
    private var selected = Set<String>()
    private var busy = false
    private var status = "space_repair_explanation".localizedString
    private var nodes: [[String: Any]] { remote?["nodes"] as? [[String: Any]] ?? [] }
    private var actions: [Action] {
        guard Self.canOpen(space) else { return [] }
        if (try? SpaceMembershipCoordinator.store.read(scope))?.deletesSpace == true { return [.delete, .copies] }
        guard remote != nil else { return [.copies] }
        return Action.allCases.filter {
            if $0 == .retry { return SpaceConfigurationSafety.hasPendingImport(space) }
            if $0 == .defaults { return space.hdb != nil || space.hdbLoadFailed }
            if $0 == .references, SpaceConfigurationIntegrityPolicy.integer(remote?["updateTimestamp"]) != space.lastUpdate {
                guard let local, let remote,
                      let lhs = SpaceCloudNodeRemovalPolicy.instances(local), let rhs = SpaceCloudNodeRemovalPolicy.instances(remote) else { return false }
                return lhs.sorted { $0.uuid < $1.uuid } == rhs.sorted { $0.uuid < $1.uuid }
            }
            if $0 == .delete { return space.permission == .owner }
            if $0 == .local {
                return local != nil && SpaceConfigurationIntegrityPolicy.integer(remote?["updateTimestamp"]) != space.lastUpdate
            }
            return true
        }
    }
    static func canOpen(_ space: SpaceData) -> Bool {
        space.state == .normal && (space.permission == .owner || space.permission == .editor)
            && !space.requiresPasswordVerification && !space.disableEditorPermission && !space.meshOTADistribution
    }
    init(space: SpaceData) {
        self.space = space
        scope = SpaceMembershipCoordinator.scope(space)
        super.init(style: .insetGrouped)
        title = "space_repair_title".localizedString
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .refresh, target: self, action: #selector(refresh))
        refresh()
    }
    private var isCurrent: Bool { scope == SpaceMembershipCoordinator.scope(space) && navigationController?.viewControllers.contains(where: { $0 === self }) == true }
    private func setBusy(_ value: Bool) {
        busy = value
        navigationItem.rightBarButtonItem?.isEnabled = !value
        tableView.isUserInteractionEnabled = !value
        tableView.reloadData()
    }
    @objc private func refresh() {
        guard !busy else { return }
        setBusy(true)
        Task { @MainActor in
            defer { setBusy(false) }
            if let latest = SpaceData.load(siteId: space.siteId, spaceId: space.id).first { space.applyConfigurationState(from: latest) }
            let result = await NetworkRequest.shared.request(.spaceInfo(siteId: space.siteId, spaceId: space.id,
                                                                        password: space.authorizationPassword))
            guard isCurrent else { return }
            switch result {
            case .failure(let error):
                SpaceConfigurationSafety.handleAuthorityError(error, space: space)
                status = error.localizedDescription
            case .success(let response):
                guard let payload = response["data"] as? [String: Any], payload["uuid"] as? String == space.id,
                      SpaceMembershipCoordinator.accepts(payload) else { return }
                space.applyRemoteSpaceMetadata(payload)
                remote = payload
                local = await space.export(allowsProtectedInspection: true)
                guard isCurrent else { return }
                selected.removeAll()
                status = "space_repair_explanation".localizedString + "\n\n" + String(format: "space_repair_counts".localizedString,
                    (local?["nodes"] as? [Any])?.count ?? space.deviceCount, nodes.count,
                    SpaceConfigurationIntegrityPolicy.integer(payload["deviceCount"]) ?? Int64(nodes.count))
                status += "\n\n" + differenceDescription
                if SpaceConfigurationIntegrityPolicy.integer(payload["updateTimestamp"]) == space.lastUpdate {
                    status += "\n\n" + "space_repair_server_priority".localizedString
                }
            }
        }
    }
    private var differenceDescription: String {
        let phoneNodes = local?["nodes"] as? [[String: Any]] ?? []
        let cloudIDs = Set(nodes.compactMap { $0["uuid"] as? String })
        let phoneIDs = Set(phoneNodes.compactMap { $0["uuid"] as? String })
        func names(_ values: [[String: Any]]) -> String {
            values.map { ($0["name"] as? String ?? "device".localizedString) + " (" + ($0["unicastAddress"] as? String ?? "?") + ")" }.joined(separator: ", ")
        }
        return String(format: "space_repair_differences".localizedString,
            names(phoneNodes.filter { !cloudIDs.contains($0["uuid"] as? String ?? "") }),
            names(nodes.filter { !phoneIDs.contains($0["uuid"] as? String ?? "") }))
    }
    override func numberOfSections(in tableView: UITableView) -> Int { 3 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? 1 : section == 1 ? nodes.count : actions.count
    }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 1 ? "space_repair_server_devices".localizedString : nil
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.textLabel?.numberOfLines = 0
        if indexPath.section == 0 {
            cell.textLabel?.text = status
            cell.selectionStyle = .none
        } else if indexPath.section == 1 {
            let node = nodes[indexPath.row]
            cell.textLabel?.text = node["name"] as? String ?? "device".localizedString
            cell.detailTextLabel?.text = node["unicastAddress"] as? String
            cell.accessoryType = selected.contains(node["uuid"] as? String ?? "") ? .checkmark : .none
        } else {
            let action = actions[indexPath.row]
            cell.textLabel?.text = action.rawValue.localizedString
            cell.textLabel?.textColor = [.remove, .clear, .delete].contains(action) ? .systemRed : .systemBlue
            cell.accessoryType = .disclosureIndicator
        }
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard !busy else { return }
        if indexPath.section == 1, let uuid = nodes[indexPath.row]["uuid"] as? String {
            if !selected.insert(uuid).inserted { selected.remove(uuid) }
            tableView.reloadRows(at: [indexPath], with: .none)
        } else if indexPath.section == 2 { confirm(actions[indexPath.row]) }
    }
    private func confirm(_ action: Action) {
        if action == .copies {
            navigationController?.pushViewController(SpaceSavedCopiesViewController(), animated: true); return
        }
        if action == .remove, selected.isEmpty {
            XWHUDManager.showErrorTipHUD("space_repair_select_devices".localizedString); return
        }
        let chosenNames = nodes.filter { selected.contains($0["uuid"] as? String ?? "") }
            .map { "\($0["name"] as? String ?? "") (\($0["unicastAddress"] as? String ?? ""))" }.joined(separator: "\n")
        let detail: String
        switch action {
        case .local: detail = "configuration_use_local_confirm".localizedString
        case .clear: detail = "space_repair_clear_confirm".localizedString
        case .delete: detail = "space_repair_delete_confirm".localizedString
        case .references: detail = "space_repair_references_confirm".localizedString
        default: detail = "space_repair_confirm".localizedString
        }
        let alert = UIAlertController(title: action.rawValue.localizedString,
            message: detail + "\n\n" + differenceDescription + (action == .remove ? "\n\n" + chosenNames : ""), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "cancel".localizedString, style: .cancel))
        alert.addAction(UIAlertAction(title: "confirm".localizedString, style: .destructive) { [weak self] _ in self?.perform(action) })
        present(alert, animated: true)
    }
    private func perform(_ action: Action) {
        guard !busy, Self.canOpen(space) else { return }
        let reviewed = remote, reviewedLocal = local, selection = selected
        let reviewedRevision = space.lastUpdate
        setBusy(true)
        Task { @MainActor in
            defer { setBusy(false) }
            if action == .delete, (try? SpaceMembershipCoordinator.store.read(scope))?.deletesSpace == true {
                await finishDeletion(); return
            }
            let response = await NetworkRequest.shared.request(.spaceInfo(siteId: space.siteId, spaceId: space.id,
                                                                          password: space.authorizationPassword))
            guard isCurrent else { return }
            guard case .success(let value) = response, let fresh = value["data"] as? [String: Any],
                  fresh["uuid"] as? String == space.id, SpaceMembershipCoordinator.accepts(fresh) else {
                if case .failure(let error) = response {
                    SpaceConfigurationSafety.handleAuthorityError(error, space: space); status = error.localizedDescription
                }
                return
            }
            space.applyRemoteSpaceMetadata(fresh)
            guard Self.canOpen(space), let role = fresh["role"] as? String,
                  role == "owner" || role == "editor", let reviewed,
                  Self.matches(fresh, reviewed), space.lastUpdate == reviewedRevision,
                  SpaceData.load(siteId: space.siteId, spaceId: space.id).first?.lastUpdate == reviewedRevision else { status = "space_recovery_changed".localizedString; return }
            do {
                // Preserve even malformed local business rows before any replacement.
                let copy = try await SpaceMembershipCoordinator.preserveCopy(space)
                guard isCurrent, Self.canOpen(space), space.lastUpdate == reviewedRevision,
                      SpaceData.load(siteId: space.siteId, spaceId: space.id).first?.lastUpdate == reviewedRevision else {
                    status = "space_recovery_changed".localizedString; return
                }
                CloudSynchronizationManager.shared.cancelSynchronizationHandle(space: space)
                if action == .delete {
                    guard role == "owner", let site = SiteData.load(siteId: space.siteId) else { return }
                    try await SpaceMembershipCoordinator.queueLeave(space, site: site, savedCopy: copy, deletesSpace: true)
                    await finishDeletion(); return
                }
                let candidate: [String: Any]
                if action == .retry {
                    let outcome = await space.restoreConfiguration(spaceJsonData: fresh, authoritativeGET: true)
                    completeImport(outcome); return
                }
                if action == .defaults {
                    let outcome = await space.restoreConfiguration(spaceJsonData: fresh, authoritativeGET: true, fixWithDefaults: true)
                    completeImport(outcome); return
                }
                switch action {
                case .local:
                    guard let reviewedLocal, let current = await space.export(allowsProtectedInspection: true),
                          Self.matches(current, reviewedLocal),
                          SpaceConfigurationIntegrityPolicy.integer(fresh["updateTimestamp"]) != space.lastUpdate else {
                        status = "space_recovery_changed".localizedString; return
                    }
                    candidate = current
                case .references:
                    if let version = SpaceConfigurationIntegrityPolicy.integer(fresh["updateTimestamp"]), version < space.lastUpdate {
                        guard let reviewedLocal, let current = await space.export(allowsProtectedInspection: true), Self.matches(current, reviewedLocal) else {
                            status = "space_recovery_changed".localizedString; return
                        }
                        candidate = current
                    } else { candidate = fresh }
                case .remove: candidate = try SpaceRecoveryPayloadPolicy.removing(selection, from: fresh)
                case .clear:
                    candidate = try SpaceRecoveryPayloadPolicy.clearing(fresh, hdb: space.hdb != nil || space.hdbLoadFailed
                        || (try? SiteData.load(siteId: space.siteId)?.loadIsHdbSite()) == true)
                default: candidate = fresh
                }
                guard isCurrent, SpaceConfigurationSafety.prepareRecoveryImport(space, remote: fresh, selected: candidate) else {
                    status = "configuration_repair_unavailable".localizedString; return
                }
                let outcome = await space.restoreConfiguration(spaceJsonData: fresh, authoritativeGET: true)
                completeImport(outcome)
            } catch { status = "space_recovery_storage_failed".localizedString }
        }
    }
    private func completeImport(_ outcome: SpaceImportOutcome) {
        guard isCurrent else { return }
        guard outcome.status == .applied else {
            status = SpaceRecoveryViewController.message(outcome.rejectionReason ?? "configurationPersistenceFailed"); return
        }
        status = space.needUploadCloud ? "space_repair_pending_upload".localizedString : "done!".localizedString
        if space.needUploadCloud {
            CloudSynchronizationManager.shared.addSynchronizationHandle(operation: .syncSpace(space: space), level: .promptly)
        }
        NotificationCenter.default.post(name: .init(SitesDataRefreshNotifiacationName), object: nil)
        NotificationCenter.default.post(name: .init(spacePermissionChangedNotificaitonName), object: nil)
        remote = nil; local = nil; selected.removeAll()
    }
    private static func matches(_ lhs: [String: Any], _ rhs: [String: Any]) -> Bool {
        if let left = SpaceCloudNodeRemovalPolicy.Snapshot.make(lhs), let right = SpaceCloudNodeRemovalPolicy.Snapshot.make(rhs) {
            return left == right
        }
        // Damaged payloads can still be explicitly cleared, but must be exactly
        // the snapshot reviewed by the user. Transport provenance is not data.
        func bytes(_ value: [String: Any]) -> Data? {
            try? JSONSerialization.data(withJSONObject: value.filter { $0.key != SpaceMembershipResponseContext.payloadKey }, options: .sortedKeys)
        }
        guard let left = bytes(lhs), let right = bytes(rhs) else { return false }
        return left == right
    }
    private func finishDeletion() async {
        if let error = await SpaceMembershipCoordinator.resumeLeave(scope) {
            status = "space_repair_delete_pending".localizedString + "\n\n" + error.localizedDescription
        } else if isCurrent {
            navigationController?.popToViewController(vcClass: SiteViewController.classForCoder())
        }
    }
}
