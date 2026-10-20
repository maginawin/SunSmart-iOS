import UIKit
import NordicSigMeshSDK

final class HDBConfigurationViewController: UITableViewController, CustomSegmentedControlDelegate {
    private let site: SiteData
    private let space: SpaceData
    private let service: HDBLightingZoneService
    private var config = HDBConfiguration()
    private var devices: [Node] = []
    private var selectedSegment = 0
    private let account = UserData.currentUserId
    private let region = String(describing: UserData.currentServerRegion)

    init(site: SiteData, space: SpaceData) {
        self.site = site; self.space = space
        service = HDBLightingZoneService(site: site, space: space)
        super.init(style: .insetGrouped)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "hdb_configuration".localizedString
        view.backgroundColor = Background_Color
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(closePage))
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "ellipsis"), style: .plain, target: self, action: #selector(showMenu))
        navigationItem.rightBarButtonItem?.accessibilityLabel = "more".localizedString
        refreshControl = UIRefreshControl()
        refreshControl?.addTarget(self, action: #selector(refreshLocal), for: .valueChanged)
        service.didChange = { [weak self] in self?.reload() }
        service.didFinish = { [weak self] error in if let error = error { self?.show(error) } }
    }
    override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); reload() }
    override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); service.cancel() }
    @objc private func refreshLocal() { reload(); refreshControl?.endRefreshing() }
    @objc private func closePage() { service.cancel(); dismiss(animated: true) }

    private var editable: Bool {
        guard account == UserData.currentUserId, region == String(describing: UserData.currentServerRegion),
              let latest = SpaceData.load(siteId: space.siteId, spaceId: space.id).first else { return false }
        return (try? site.loadIsHdbSite()) == true && latest.canEditing && space.groupOperates.contains(.edit) && !SpaceConfigurationSafety.isBlocked(latest) && !service.isRunning
    }

    private var canAddZone: Bool {
        selectedSegment == 0 && editable && config.lightingZones.count < 63
    }

    private func reload() {
        do { config = try HDBConfigurationStore.load(space: space) }
        catch { config = HDBConfiguration(); show(error) }
        config.lightingZones.sort { $0.zoneId < $1.zoneId }
        if let network = MeshNetworkManager.instance.meshNetwork, network.uuid.uuidString == space.meshUUID {
            devices = network.nodes.filter { $0.subNetworkId == space.meshNetworkId && !$0.isProvisioner && !$0.isConfigComplete && $0.deviceType == .light }.sorted { $0.primaryUnicastAddress < $1.primaryUnicastAddress }
        } else { devices = [] }
        updateSegmentHeader()
        updateMoreButton()
        tableView.reloadData()
    }

    private func updateSegmentHeader() {
        let header = UIView(frame: CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 60))
        let titles = ["\("hdb_lighting_zones".localizedString) (\(config.lightingZones.count))",
                      "\("hdb_devices".localizedString) (\(devices.count))"]
        let control = CustomSegmentedControl(frame: CGRect(x: 16, y: 8, width: max(0, header.bounds.width - 32), height: 44), titles: titles)
        control.autoresizingMask = [.flexibleWidth]
        control.selectedIndex = selectedSegment
        control.delegate = self
        header.addSubview(control)
        tableView.tableHeaderView = header
    }

    private func updateMoreButton() {
        navigationItem.rightBarButtonItem?.isEnabled = !service.isRunning
    }

    func segmentedControl(_ segmentedControl: CustomSegmentedControl, didSelectedItem index: Int) {
        selectedSegment = index
        updateMoreButton()
        tableView.reloadData()
        tableView.setContentOffset(CGPoint(x: 0, y: -tableView.adjustedContentInset.top), animated: false)
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 1 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { selectedSegment == 0 ? config.lightingZones.count : devices.count }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if selectedSegment == 0 {
            let latest = SpaceData.load(siteId: space.siteId, spaceId: space.id).first ?? space
            let cloud = latest.showSyncCloudError.map { $0.localizedDescription }
                ?? (latest.needUploadCloud ? "hdb_cloud_pending" : "hdb_cloud_synced").localizedString
            return "hdb_zone_help".localizedString + "\n" + String(format: "hdb_cloud_status".localizedString, cloud)
        }
        return (devices.isEmpty ? "hdb_add_devices_help" : "hdb_device_help").localizedString
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.textLabel?.numberOfLines = 0; cell.detailTextLabel?.numberOfLines = 0
        cell.accessoryType = .disclosureIndicator
        if selectedSegment == 0 {
            let zone = config.lightingZones[indexPath.row]
            cell.textLabel?.text = "\(zone.zoneId) · \(zone.name)"
            let members = HDBPresentation.members(zoneId: zone.zoneId, in: config)
            let pending = members.filter { $0.lightingZonesStatus != .synced }.count
            cell.detailTextLabel?.text = String(format: "hdb_zone_summary".localizedString, Int(zone.groupAddress), members.count, pending)
        } else {
            let node = devices[indexPath.row]
            cell.textLabel?.text = node.name ?? String(format: "%04X", node.primaryUnicastAddress)
            cell.detailTextLabel?.text = service.supports(node) ? String(format: "hdb_device_address".localizedString, Int(node.primaryUnicastAddress)) : "hdb_unsupported".localizedString
        }
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard !service.isRunning else { return }
        if selectedSegment == 1 {
            navigationController?.pushViewController(HDBLightingZoneDeviceViewController(site: site, space: space, nodeUuid: devices[indexPath.row].uuid), animated: true)
        } else {
            let zone = config.lightingZones[indexPath.row]
            navigationController?.pushViewController(HDBLightingZoneDetailViewController(site: site, space: space, zone: zone), animated: true)
        }
    }

    @objc private func showMenu() {
        guard !service.isRunning else { return }
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "hdb_lighting_configuration".localizedString, style: .default) { [weak self] _ in
            self?.openLightingConfiguration()
        })
        alert.addAction(UIAlertAction(title: "cancel".localizedString, style: .cancel))
        alert.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItem
        present(alert, animated: true)
    }

    private func openLightingConfiguration() {
        guard !service.isRunning else { return }
        navigationController?.pushViewController(HDBLightingConfigurationViewController(site: site, space: space), animated: true)
    }

    private func addZone() {
        guard canAddZone else { return }
        editName(nil)
    }
    private func editName(_ zone: HDBLightingZone?) {
        guard editable else { show(HDBConfigurationError.permissionDenied); return }
        guard let id = zone?.zoneId ?? (1...63).first(where: { id in !config.lightingZones.contains { $0.zoneId == id } }) else { return }
        let alert = UIAlertController(title: (zone == nil ? "hdb_add_zone" : "hdb_rename").localizedString, message: nil, preferredStyle: .alert)
        if zone == nil {
            alert.addTextField { $0.placeholder = "hdb_zone_id".localizedString; $0.keyboardType = .numberPad; $0.text = String(id) }
        }
        alert.addTextField { $0.placeholder = "hdb_zone_name".localizedString; $0.text = zone?.name ?? String(format: "hdb_default_zone_name".localizedString, id) }
        alert.addAction(UIAlertAction(title: "cancel".localizedString, style: .cancel))
        alert.addAction(UIAlertAction(title: "save".localizedString, style: .default) { [weak self, weak alert] _ in
            guard let self = self, self.editable, let name = alert?.textFields?.last?.text else { return }
            do {
                if let zone = zone {
                    try HDBConfigurationStore.update(space: self.space) { config in
                        guard let index = config.lightingZones.firstIndex(where: { $0.zoneId == zone.zoneId }) else { throw HDBConfigurationError.invalidZones }
                        config.lightingZones[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                } else {
                    guard let text = alert?.textFields?.first?.text, let enteredID = Int(text) else { throw HDBConfigurationError.invalidZones }
                    _ = try HDBConfigurationStore.createZone(space: self.space, zoneId: enteredID, name: name)
                }
                self.reload()
            } catch HDBConfigurationError.addressUnavailable { self.requestAddresses() }
            catch { self.show(error) }
        })
        present(alert, animated: true)
    }

    private func requestAddresses() {
        let alert = UIAlertController(title: "hdb_configuration".localizedString, message: "group_address_insufficient".localizedString, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "cancel".localizedString, style: .cancel))
        alert.addAction(UIAlertAction(title: "hdb_request_addresses".localizedString, style: .default) { [weak self] _ in
            guard let self = self, self.editable else { return }
            NetworkRequest.shared.request(.applyAddress(siteId: self.site.id, type: .group, number: 16)) { [weak self] result in
                guard let self = self, self.editable else { return }
                switch result {
                case .success(let response):
                    guard let data = response["data"] as? [String: Any], let provisioner = data["provisioner"] as? [String: Any], let site = SiteData.load(siteId: self.site.id) else { self.show(HDBConfigurationError.unavailable); return }
                    site.setProvisioner(provisionerData: provisioner)
                    self.addZone()
                case .failure(let error): self.show(error)
                }
            }
        })
        present(alert, animated: true)
    }

    private func show(_ error: Error) { XWHUDManager.showErrorTipHUD(HDBUIError.message(error)) }
}

enum HDBUIError {
    static func message(_ error: Error) -> String {
        if let lightingError = error as? HDBLightingError {
            return (lightingError == .notPrepared ? "hdb_prepare_required" : "hdb_response_mismatch").localizedString
        }
        if let controlError = error as? HDBZoneControlError {
            switch controlError {
            case .disconnected: return "hdb_control_disconnected".localizedString
            case .emptyZone: return "hdb_empty_zone_help".localizedString
            case .emergency: return "Uncontrollable in emergency situations".localizedString
            case .invalidBrightness: return "illegal_input".localizedString
            }
        }
        guard let error = error as? HDBConfigurationError else { return error.localizedDescription }
        switch error {
        case .unsupportedModels: return "hdb_unsupported".localizedString
        case .invalidMAC: return "hdb_mac_required".localizedString
        case .invalidZones, .invalidData: return "hdb_invalid_configuration".localizedString
        case .permissionDenied: return "hdb_editing_unavailable".localizedString
        case .persistenceFailed: return "save_failure".localizedString
        case .addressUnavailable: return "group_address_insufficient".localizedString
        case .busy: return "hdb_busy".localizedString
        case .unavailable: return "hdb_unavailable".localizedString
        case .applicationKeyUnavailable: return "hdb_app_key_unavailable".localizedString
        case .modelNotBound: return "hdb_model_not_bound".localizedString
        case .unexpectedApplicationKey: return "hdb_unexpected_app_key".localizedString
        case .responseMismatch: return "hdb_response_mismatch".localizedString
        }
    }
}
