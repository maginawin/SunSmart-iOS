import UIKit
import NordicSigMeshSDK

final class HDBLightingZoneDetailViewController: UITableViewController {
    private let site: SiteData
    private let space: SpaceData
    private let zoneId: Int
    private let groupAddress: UInt16
    private let service: HDBLightingZoneService
    private let account = UserData.currentUserId
    private let region = String(describing: UserData.currentServerRegion)
    private var zone: HDBLightingZone?
    private var members: [HDBDeviceConfiguration] = []
    private var controlIssue: String?
    private var requested: String?
    private var requestedControlKey: String?
    private var requestedPresence: Bool?
    private var controlButtons: [String: UIButton] = [:]
    private var requestedBrightness = 100
    private var pageActive = false
    private var brightnessEdited = false
    private var connectionObserver: UUID?
    private var emergencyObserver: NSObjectProtocol?
    private let brightnessPanel = DeviceLightControlPanelView()
    private let requestLabel = UILabel()
    private let triggerRequestLabel = UILabel()

    init(site: SiteData, space: SpaceData, zone: HDBLightingZone) {
        self.site = site; self.space = space; self.zone = zone
        zoneId = zone.zoneId; groupAddress = zone.groupAddress
        service = HDBLightingZoneService(site: site, space: space)
        super.init(style: .insetGrouped)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Background_Color
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "ellipsis"), style: .plain, target: self, action: #selector(showMenu))
        navigationItem.rightBarButtonItem?.accessibilityLabel = "more".localizedString
        refreshControl = UIRefreshControl()
        refreshControl?.addTarget(self, action: #selector(refreshLocal), for: .valueChanged)
        service.didChange = { [weak self] in self?.reload() }
        service.didFinish = { [weak self] error in
            self?.reload()
            if let error { self?.show(error) }
        }
        brightnessPanel.brightnessValueChanged = { [weak self] value in
            guard let self, self.pageActive else { return }
            self.brightnessEdited = true
            self.requestedBrightness = value
        }
        brightnessPanel.brightnessThrottleValueChanged = { [weak self] value, _ in
            guard let self, self.pageActive, self.brightnessEdited else { return }
            self.send(.brightness(value))
        }
        brightnessPanel.editBrightnessRequested = { [weak self] in self?.editBrightness() }
        observeControlAvailability()
    }
    private func observeControlAvailability() {
        connectionObserver = MeshLibManager.manager.addGlobalConnectionObserver { [weak self] _, _ in
            DispatchQueue.main.async { if self?.pageActive == true { self?.reload() } }
        }
        emergencyObserver = NotificationCenter.default.addObserver(
            forName: .init(emergencyFireControllerManualControlStateDidChangeNotificationName),
            object: nil, queue: .main
        ) { [weak self] _ in
            if self?.pageActive == true { self?.reload() }
        }
    }
    deinit {
        MeshLibManager.manager.removeGlobalConnectionObserver(connectionObserver)
        if let emergencyObserver { NotificationCenter.default.removeObserver(emergencyObserver) }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        pageActive = true; brightnessEdited = false
        reload()
    }
    override func viewWillDisappear(_ animated: Bool) {
        pageActive = false; brightnessEdited = false
        // cancel() only stops this service's configuration executor, never the test control queue.
        service.cancel()
        super.viewWillDisappear(animated)
    }
    @objc private func refreshLocal() { reload(); refreshControl?.endRefreshing() }

    private var editable: Bool {
        guard pageActive, account == UserData.currentUserId, region == String(describing: UserData.currentServerRegion),
              let latest = SpaceData.load(siteId: space.siteId, spaceId: space.id).first else { return false }
        return latest.meshUUID == space.meshUUID && latest.meshNetworkId == space.meshNetworkId
            && latest.canEditing && space.groupOperates.contains(.edit)
            && !SpaceConfigurationSafety.isBlocked(latest) && !service.isRunning
    }

    private func reload() {
        guard isViewLoaded, pageActive else { return }
        do {
            guard account == UserData.currentUserId, region == String(describing: UserData.currentServerRegion) else {
                throw HDBConfigurationError.unavailable
            }
            let config = try HDBConfigurationStore.load(space: space)
            guard let current = config.lightingZones.first(where: { $0.zoneId == zoneId && $0.groupAddress == groupAddress }) else {
                zone = nil; members = []
                navigationController?.popViewController(animated: true)
                return
            }
            zone = current; title = current.name
            members = HDBPresentation.members(zoneId: zoneId, in: config)
            do { try service.validateControl(zoneId: zoneId, groupAddress: groupAddress); controlIssue = nil }
            catch { controlIssue = HDBUIError.message(error) }
        } catch {
            zone = nil; members = []
            controlIssue = HDBUIError.message(error)
        }
        navigationItem.rightBarButtonItem?.isEnabled = editable && zone != nil
        brightnessPanel.configure(.init(controlType: space.controlType, showCCTQuickButtons: false,
                                        showsBrightness: true, showsCCT: false, brightnessValue: requestedBrightness,
                                        brightnessRange: 0...100, cctValue: 2700, cctRange: 2700...6500))
        brightnessPanel.isUserInteractionEnabled = controlIssue == nil
        brightnessPanel.alpha = controlIssue == nil ? 1 : 0.45
        updateRequestLabel()
        tableView.reloadData()
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 4 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section { case 0: return 1; case 1: return 3; case 2: return 2; case 3: return members.count; default: return 0 }
    }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 1: return "hdb_test_controls".localizedString
        case 2: return "trigger_zone".localizedString
        case 3: return "\("hdb_members".localizedString) (\(members.count))"
        default: return nil
        }
    }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch section {
        case 1:
            var parts = ["hdb_control_help".localizedString, "hdb_control_partial".localizedString]
            if let controlIssue { parts.append(controlIssue) }
            return parts.joined(separator: "\n")
        case 2:
            var parts = ["hdb_trigger_help".localizedString]
            if let controlIssue { parts.append(controlIssue) }
            return parts.joined(separator: "\n")
        case 3: return members.isEmpty ? "hdb_empty_zone_help".localizedString : nil
        default: return nil
        }
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.textLabel?.numberOfLines = 0; cell.detailTextLabel?.numberOfLines = 0
        cell.selectionStyle = .none
        if indexPath.section == 0 {
            cell.textLabel?.text = String(format: "hdb_zone_address".localizedString, zoneId, Int(groupAddress))
        } else if indexPath.section == 1 {
            if indexPath.row == 0 {
                let buttons = UIStackView()
                buttons.axis = .horizontal; buttons.distribution = .fillEqually; buttons.spacing = 12
                controlButtons.removeAll()
                for (key, selector) in [("restore_auto", #selector(autoAction(_:))), ("on", #selector(onAction(_:))), ("off", #selector(offAction(_:)))] {
                    let button = makeControlButton(key: key, action: selector)
                    button.isSelected = requestedControlKey == key
                    button.accessibilityValue = button.isSelected ? requestLabel.text : nil
                    controlButtons[key] = button
                    buttons.addArrangedSubview(button)
                }
                embed(buttons, in: cell, minimumHeight: 44)
            } else if indexPath.row == 1 {
                embed(brightnessPanel, in: cell, minimumHeight: 76)
                let edit = UIButton(type: .system)
                edit.setImage(UIImage(systemName: "square.and.pencil"), for: .normal)
                edit.accessibilityLabel = "brightness".localizedString
                edit.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
                edit.isEnabled = controlIssue == nil
                edit.addTarget(self, action: #selector(editBrightness), for: .touchUpInside)
                cell.accessoryView = edit
            }
            else {
                requestLabel.numberOfLines = 0; requestLabel.font = .preferredFont(forTextStyle: .callout)
                embed(requestLabel, in: cell, minimumHeight: 22)
            }
        } else if indexPath.section == 2 {
            if indexPath.row == 0 {
                let buttons = UIStackView()
                buttons.axis = .horizontal; buttons.distribution = .fillEqually; buttons.spacing = 12
                for (key, selector) in [("hdb_publish_occupancy", #selector(publishOccupancy(_:))),
                                        ("hdb_publish_vacancy", #selector(publishVacancy(_:)))] {
                    buttons.addArrangedSubview(makeControlButton(key: key, action: selector))
                }
                embed(buttons, in: cell, minimumHeight: 44)
            } else {
                triggerRequestLabel.numberOfLines = 0
                triggerRequestLabel.font = .preferredFont(forTextStyle: .callout)
                embed(triggerRequestLabel, in: cell, minimumHeight: 22)
            }
        } else if indexPath.section == 3 {
            let device = members[indexPath.row]
            let network = MeshNetworkManager.instance.meshNetwork
            let node = network?.uuid.uuidString == space.meshUUID
                ? network?.nodes.first { $0.uuid == device.nodeUuid && $0.subNetworkId == space.meshNetworkId } : nil
            cell.textLabel?.text = node?.name ?? String(format: "hdb_device_address".localizedString, Int(device.nodeAddress))
            let status = HDBPresentation.statusKey(device).localizedString
            cell.detailTextLabel?.text = String(format: "hdb_member_details".localizedString, Int(device.nodeAddress), device.mac ?? "—", status)
            cell.accessoryType = .disclosureIndicator; cell.selectionStyle = .default
        }
        return cell
    }
    private func makeControlButton(key: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        var configuration = UIButton.Configuration.plain()
        configuration.title = key.localizedString
        configuration.titleAlignment = .center
        configuration.titleLineBreakMode = .byWordWrapping
        configuration.cornerStyle = .fixed
        configuration.background.cornerRadius = 8
        configuration.contentInsets = .init(top: 12, leading: 8, bottom: 12, trailing: 8)
        configuration.baseForegroundColor = Bar_Color
        configuration.background.backgroundColor = Bar_Color.withAlphaComponent(0.12)
        button.configuration = configuration
        button.titleLabel?.numberOfLines = 0
        button.configurationUpdateHandler = { button in
            guard var configuration = button.configuration else { return }
            if !button.isEnabled {
                configuration.baseForegroundColor = .tertiaryLabel
                configuration.background.backgroundColor = .tertiarySystemFill
            } else {
                let emphasized = button.isHighlighted || button.isSelected
                configuration.baseForegroundColor = emphasized ? .white : Bar_Color
                configuration.background.backgroundColor = emphasized
                    ? Bar_Color : Bar_Color.withAlphaComponent(0.12)
            }
            button.configuration = configuration
        }
        button.addTarget(self, action: action, for: .touchUpInside)
        button.isEnabled = controlIssue == nil
        return button
    }
    private func embed(_ content: UIView, in cell: UITableViewCell, minimumHeight: CGFloat) {
        content.removeFromSuperview()
        content.translatesAutoresizingMaskIntoConstraints = false
        cell.contentView.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -16),
            content.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 8),
            content.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -8),
            cell.contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: minimumHeight + 16)
        ])
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard pageActive, indexPath.section == 3, members.indices.contains(indexPath.row), !service.isRunning else { return }
        let device = members[indexPath.row]
        navigationController?.pushViewController(HDBLightingZoneDeviceViewController(site: site, space: space, nodeUuid: device.nodeUuid), animated: true)
    }

    @objc private func autoAction(_ sender: UIButton) { send(.auto, source: sender) }
    @objc private func onAction(_ sender: UIButton) { send(.on, source: sender) }
    @objc private func offAction(_ sender: UIButton) { send(.off, source: sender) }
    @objc private func publishOccupancy(_ sender: UIButton) { publishPresence(true, source: sender) }
    @objc private func publishVacancy(_ sender: UIButton) { publishPresence(false, source: sender) }
    private func publishPresence(_ detected: Bool, source: UIButton) {
        guard pageActive else { return }
        do {
            try service.publishPresence(zoneId: zoneId, groupAddress: groupAddress, detected: detected)
            requestedPresence = detected
            updateRequestLabel()
            showRequestFeedback(source)
            // The requested message can wrap to a different height than the empty label.
            tableView.beginUpdates(); tableView.endUpdates()
        } catch {
            show(error); reload()
        }
    }
    private func send(_ action: HDBZoneControlAction, source: UIButton? = nil) {
        guard pageActive else { return }
        do {
            try service.control(zoneId: zoneId, groupAddress: groupAddress, action: action)
            switch action {
            case .auto: requestedControlKey = "restore_auto"; requested = "restore_auto".localizedString
            case .on: requestedControlKey = "on"; requested = "on".localizedString
            case .off: requestedControlKey = "off"; requested = "off".localizedString
            case .brightness(let value):
                requestedControlKey = nil
                requestedBrightness = value; requested = "\("brightness".localizedString) \(value)%"
            }
            updateRequestLabel()
            if let source { showRequestFeedback(source) }
        } catch {
            brightnessEdited = false
            show(error); reload()
        }
    }
    private func showRequestFeedback(_ source: UIButton) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let feedback = CABasicAnimation(keyPath: UIAccessibility.isReduceMotionEnabled ? "opacity" : "transform.scale")
        feedback.fromValue = UIAccessibility.isReduceMotionEnabled ? 0.55 : 0.9
        feedback.toValue = 1
        feedback.duration = 0.3
        feedback.timingFunction = CAMediaTimingFunction(name: .easeOut)
        source.layer.add(feedback, forKey: "hdbControlRequest")
    }
    private func updateRequestLabel() {
        requestLabel.text = requested.map { String(format: "hdb_control_requested".localizedString, $0) }
            ?? "hdb_control_not_requested".localizedString
        requestLabel.textColor = requested == nil ? .secondaryLabel : Bar_Color
        triggerRequestLabel.text = requestedPresence.map {
            let key = $0 ? "hdb_publish_occupancy" : "hdb_publish_vacancy"
            return String(format: "hdb_control_requested".localizedString, key.localizedString)
        } ?? "hdb_control_not_requested".localizedString
        triggerRequestLabel.textColor = requestedPresence == nil ? .secondaryLabel : Bar_Color
        for (key, button) in controlButtons {
            button.isSelected = requestedControlKey == key
            button.accessibilityValue = button.isSelected ? requestLabel.text : nil
        }
    }
    @objc private func editBrightness() {
        guard pageActive else { return }
        do { try service.validateControl(zoneId: zoneId, groupAddress: groupAddress) }
        catch { show(error); reload(); return }
        SRAlertView(title: "brightness".localizedString, inputText: String(requestedBrightness),
                    inputFieldStyle: .init(keyboardType: .numberPad, maxInputLength: 3, textAlignment: .center, showClear: true),
                    actions: [.cancelAction, SRAlertAction(title: "COMFIRM".localizedString, style: .default)],
                    textValueChangedBack: nil) { [weak self] text in
            guard let self, self.pageActive else { return }
            guard let value = Int(text), (0...100).contains(value) else {
                self.show(HDBZoneControlError.invalidBrightness); return
            }
            self.brightnessPanel.setBrightnessValue(value)
            self.send(.brightness(value))
        }.show()
    }
    @objc private func showMenu() {
        guard editable, let zone else { return }
        let alert = UIAlertController(title: zone.name, message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "hdb_rename".localizedString, style: .default) { [weak self] _ in self?.rename() })
        alert.addAction(UIAlertAction(title: "cancel".localizedString, style: .cancel))
        alert.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItem
        present(alert, animated: true)
    }
    private func rename() {
        guard editable, let zone else { return }
        let alert = UIAlertController(title: "hdb_rename".localizedString, message: nil, preferredStyle: .alert)
        alert.addTextField { $0.text = zone.name; $0.placeholder = "hdb_zone_name".localizedString }
        alert.addAction(UIAlertAction(title: "cancel".localizedString, style: .cancel))
        alert.addAction(UIAlertAction(title: "save".localizedString, style: .default) { [weak self, weak alert] _ in
            guard let self, self.editable, let name = alert?.textFields?.first?.text else { return }
            do {
                try HDBConfigurationStore.update(space: self.space) { config in
                    guard let i = config.lightingZones.firstIndex(where: { $0.zoneId == self.zoneId && $0.groupAddress == self.groupAddress }) else { throw HDBConfigurationError.unavailable }
                    config.lightingZones[i].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                self.reload()
            } catch { self.show(error) }
        })
        present(alert, animated: true)
    }
    private func show(_ error: Error) { XWHUDManager.showErrorTipHUD(HDBUIError.message(error)) }
}
