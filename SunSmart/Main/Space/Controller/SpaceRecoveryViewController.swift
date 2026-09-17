import UIKit

/// This screen never activates Mesh or starts configuration synchronization.
final class SpaceRecoveryViewController: UIViewController {
    let spaceID: String
    private let message = UILabel()
    private let retry: () -> Void
    private let leave: (() -> Void)?
    private var reason: String
    private let scope: SpaceMembershipRecord.Scope
    init(space: SpaceData, reason: String, retry: @escaping () -> Void, leave: (() -> Void)?) {
        spaceID = space.id; self.reason = reason; self.retry = retry; self.leave = leave
        scope = SpaceMembershipCoordinator.scope(space)
        super.init(nibName: nil, bundle: nil)
        title = space.name
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func update(reason: String) { self.reason = reason; message.text = Self.message(reason) }

    static func message(_ reason: String) -> String {
        switch reason {
        case "spaceLeaving": return "space_leave_pending".localizedString
        case "leaveConfirmed": return "space_leave_cleanup_pending".localizedString
        case "configurationPersistenceFailed", "configurationStagingFailed": return "space_recovery_storage_failed".localizedString
        case "networkIdentityMismatch", "invalidNetworkIdentity": return "space_recovery_identity_failed".localizedString
        case "staleMembershipResponse", "staleImportPreparation": return "space_recovery_changed".localizedString
        case "networkUnavailable": return "space_recovery_network_failed".localizedString
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
    @objc private func leaveAction() { leave?() }
    @objc private func copiesAction() { navigationController?.pushViewController(SpaceSavedCopiesViewController(), animated: true) }
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
