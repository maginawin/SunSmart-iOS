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
        case "staleMembershipResponse", "staleImportPreparation": return "space_recovery_changed".localizedString
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
