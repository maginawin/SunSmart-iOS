import UIKit
import NordicSigMeshSDK

final class HDBLightingZoneDeviceViewController: UITableViewController {
    private let space: SpaceData
    private let nodeUuid: UUID
    private let service: HDBLightingZoneService
    private let diagnostics: HDBDeviceDiagnosticsService
    private var expandedDiagnostics = Set<HDBModelTarget>()
    private var config = HDBConfiguration()
    private var device: HDBDeviceConfiguration?
    private var selected = Set<Int>()
    private var jsonText: String?
    private var supported = false
    private let account = UserData.currentUserId
    private let region = String(describing: UserData.currentServerRegion)

    init(site: SiteData, space: SpaceData, nodeUuid: UUID) {
        self.space = space; self.nodeUuid = nodeUuid
        service = HDBLightingZoneService(site: site, space: space)
        diagnostics = HDBDeviceDiagnosticsService(site: site, space: space, nodeUuid: nodeUuid)
        super.init(style: .insetGrouped)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "hdb_lighting_zones".localizedString
        view.backgroundColor = Background_Color
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "hdb_apply".localizedString, style: .done, target: self, action: #selector(apply))
        service.didChange = { [weak self] in self?.reload() }
        service.didFinish = { [weak self] error in
            self?.reload()
            if let error = error { self?.show(error) }
        }
        diagnostics.didChange = { [weak self] in
            guard let self else { return }
            // Preserve the user's unapplied Zone selection while observations arrive.
            self.navigationItem.rightBarButtonItem?.isEnabled = self.editable
            self.tableView.reloadData()
        }
        diagnostics.didFinish = { [weak self] error in
            guard let error, !(error is CancellationError) else { return }
            if error is HDBDiagnosticError {
                XWHUDManager.showErrorTipHUD("hdb_diag_state_changed".localizedString)
            } else { self?.show(error) }
        }
        reload()
    }
    override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); reload() }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated); service.cancel(); diagnostics.cancel(discard: true)
        expandedDiagnostics.removeAll()
    }
    private var editable: Bool {
        guard account == UserData.currentUserId, region == String(describing: UserData.currentServerRegion),
              let latest = SpaceData.load(siteId: space.siteId, spaceId: space.id).first else { return false }
        return latest.canEditing && latest.groupOperates.contains(.edit) && !SpaceConfigurationSafety.isBlocked(latest) && !service.isRunning && !diagnostics.isRunning && supported
    }
    private var zones: [HDBLightingZone] { config.lightingZones.sorted { $0.zoneId < $1.zoneId } }

    private func reload() {
        do {
            config = try HDBConfigurationStore.load(space: space)
            device = try service.getLightingZones(nodeUuid: nodeUuid)
            selected = device.map(HDBPresentation.selectedZones) ?? []
            if let node = MeshNetworkManager.instance.meshNetwork?.nodes.first(where: { $0.uuid == nodeUuid }) {
                supported = service.supports(node)
                title = node.name ?? "hdb_lighting_zones".localizedString
            } else { supported = false }
        } catch { show(error) }
        diagnostics.refreshValidity()
        navigationItem.rightBarButtonItem?.isEnabled = editable
        tableView.reloadData()
    }
    @objc private func apply() {
        guard editable else { show(HDBConfigurationError.permissionDenied); return }
        do { try service.setLightingZones(nodeUuid: nodeUuid, zoneIds: selected.sorted()); reload() }
        catch { show(error) }
    }
    private var diagnosticsSection: Int { jsonText == nil ? 3 : 4 }
    override func numberOfSections(in tableView: UITableView) -> Int { diagnosticsSection + 1 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == diagnosticsSection { return diagnosticItems.count }
        switch section { case 0: return zones.count; case 1: return 2; case 2: return device == nil ? 0 : 1; default: return 2 }
    }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if section == diagnosticsSection { return "hdb_diag_title".localizedString }
        switch section {
        case 0: return String(format: "hdb_selection_count".localizedString, selected.count)
        case 1: return "hdb_commands".localizedString
        case 2: return "hdb_saved_status".localizedString
        default: return "hdb_get_json".localizedString
        }
    }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if section == diagnosticsSection { return "hdb_diag_help".localizedString }
        switch section {
        case 0: return supported ? "hdb_apply_help".localizedString : "hdb_unsupported".localizedString
        case 1: return "hdb_get_help".localizedString
        case 2: return "hdb_sync_device_help".localizedString
        default: return nil
        }
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.textLabel?.numberOfLines = 0; cell.detailTextLabel?.numberOfLines = 0
        if indexPath.section == diagnosticsSection {
            configureDiagnosticCell(cell, item: diagnosticItems[indexPath.row])
            return cell
        }
        switch indexPath.section {
        case 0:
            let zone = zones[indexPath.row]
            cell.textLabel?.text = "\(zone.zoneId) · \(zone.name)"
            cell.accessoryType = selected.contains(zone.zoneId) ? .checkmark : .none
            cell.selectionStyle = editable ? .default : .none
            cell.textLabel?.isEnabled = editable
        case 1:
            cell.textLabel?.text = (indexPath.row == 0 ? "hdb_get" : "sync_device(s)").localizedString
            cell.textLabel?.textColor = .systemBlue
            cell.textLabel?.isEnabled = indexPath.row == 1 ? editable : !diagnostics.isRunning
        case 2:
            if let device {
                cell.textLabel?.text = "hdb_lighting_zones".localizedString
                cell.detailTextLabel?.text = HDBPresentation.statusKey(device).localizedString
                cell.accessoryType = device.lightingZonesStatus == .synced ? .none : .disclosureIndicator
            }
        default:
            if indexPath.row == 0 {
                cell.selectionStyle = .none
                let textView = UITextView()
                textView.translatesAutoresizingMaskIntoConstraints = false
                textView.isEditable = false; textView.text = jsonText
                textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
                textView.backgroundColor = .clear
                cell.contentView.addSubview(textView)
                NSLayoutConstraint.activate([
                    textView.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 12),
                    textView.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -12),
                    textView.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 8),
                    textView.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -8),
                    textView.heightAnchor.constraint(equalToConstant: 320)
                ])
            } else { cell.textLabel?.text = "hdb_copy_json".localizedString; cell.textLabel?.textColor = .systemBlue }
        }
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        do {
            if indexPath.section == diagnosticsSection {
                try selectDiagnosticItem(diagnosticItems[indexPath.row])
                return
            }
            switch indexPath.section {
            case 0:
                guard editable else { return }
                let id = zones[indexPath.row].zoneId
                if selected.contains(id) { selected.remove(id) }
                else { guard selected.count < 8 else { throw HDBConfigurationError.invalidZones }; selected.insert(id) }
                tableView.reloadSections(IndexSet(integer: 0), with: .none)
            case 1:
                guard !diagnostics.isRunning else { return }
                if indexPath.row == 0 {
                    jsonText = try HDBPresentation.json(service.getLightingZones(nodeUuid: nodeUuid))
                    tableView.reloadData()
                } else {
                    guard editable else { throw HDBConfigurationError.permissionDenied }
                    syncDevice()
                }
            case 2:
                guard editable else { return }
                guard device?.lightingZonesStatus == .pending else { return }
                syncDevice()
            default:
                if indexPath.row == 1 { UIPasteboard.general.string = jsonText }
            }
        } catch { show(error) }
    }
    private func syncDevice() {
        guard let node = MeshNetworkManager.instance.meshNetwork?.nodes.first(where: { $0.uuid == nodeUuid }) else { return }
        let vc = SyncDevicesViewController(type: .devices([node]))
        vc.syncSuccessCallback = { [weak self] _ in self?.navigationController?.popViewController(animated: true) }
        vc.backActionCallback = { [weak self] _ in self?.navigationController?.popViewController(animated: true) }
        navigationController?.pushViewController(vc, animated: true)
    }

    private enum DiagnosticItem {
        case read([HDBDiagnosticKind], String), cancel, retry, copy, summary, model(Int)
    }
    private var diagnosticItems: [DiagnosticItem] {
        var items: [DiagnosticItem] = [.read([.subscriptions], "hdb_diag_read_subscriptions"),
            .read([.publication], "hdb_diag_read_publications"), .read(HDBDiagnosticKind.allCases, "hdb_diag_read_all")]
        if diagnostics.isRunning { items.append(.cancel) }
        if diagnostics.canRetry { items.append(.retry) }
        if !diagnostics.rows.isEmpty {
            items.append(.summary)
            items += diagnostics.rows.indices.map { .model($0) }
            if !diagnostics.isRunning { items.append(.copy) }
        }
        return items
    }

    private func configureDiagnosticCell(_ cell: UITableViewCell, item: DiagnosticItem) {
        cell.textLabel?.textColor = .systemBlue
        switch item {
        case .read(_, let key):
            cell.textLabel?.text = key.localizedString
            cell.textLabel?.isEnabled = !diagnostics.isRunning && !service.isRunning
        case .cancel: cell.textLabel?.text = "cancel".localizedString
        case .retry: cell.textLabel?.text = "hdb_diag_retry".localizedString
        case .copy: cell.textLabel?.text = "hdb_diag_copy".localizedString
        case .summary:
            cell.textLabel?.textColor = .label; cell.selectionStyle = .none
            cell.textLabel?.text = diagnostics.kinds.map(\.title).joined(separator: " / ") + "\n" + diagnostics.summary
            let date = diagnostics.startedAt.map { DateFormatter.localizedString(from: $0, dateStyle: .short, timeStyle: .medium) }
            cell.detailTextLabel?.text = [date, diagnostics.warning?.localizedString].compactMap { $0 }.joined(separator: "\n")
        case .model(let index):
            let row = diagnostics.rows[index]
            cell.textLabel?.textColor = .label; cell.textLabel?.text = row.snapshot.title
            let expanded = expandedDiagnostics.contains(row.snapshot.target)
            cell.accessoryType = expanded ? .none : .disclosureIndicator
            cell.detailTextLabel?.text = expanded
                ? row.snapshot.contextText + "\n\n" + HDBDiagnosticKind.allCases.map { row.detail($0) }.joined(separator: "\n\n")
                : row.summary
        }
    }

    private func selectDiagnosticItem(_ item: DiagnosticItem) throws {
        switch item {
        case .read(let kinds, _):
            guard !service.isRunning, !diagnostics.isRunning else { return }
            try diagnostics.read(kinds)
        case .cancel: diagnostics.cancel()
        case .retry:
            guard !service.isRunning, !diagnostics.isRunning else { return }
            try diagnostics.read(diagnostics.kinds, retry: true)
        case .copy: UIPasteboard.general.string = try diagnostics.report()
        case .summary: break
        case .model(let index):
            let target = diagnostics.rows[index].snapshot.target
            if expandedDiagnostics.contains(target) { expandedDiagnostics.remove(target) }
            else { expandedDiagnostics.insert(target) }
            tableView.reloadSections(IndexSet(integer: diagnosticsSection), with: .none)
        }
    }
    private func show(_ error: Error) { XWHUDManager.showErrorTipHUD(HDBUIError.message(error)) }
}
