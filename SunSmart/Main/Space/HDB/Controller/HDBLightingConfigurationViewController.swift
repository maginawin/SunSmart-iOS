import UIKit
import NordicSigMeshSDK

final class HDBLightingConfigurationViewController: UITableViewController {
    private let space: SpaceData
    private let service: HDBLightingConfigurationService
    private var targetUuid: UUID?
    private var didSelectInitialTarget = false
    private var values = HDBLightingValues.defaults
    private var lights: [Node] = []
    private var saved: HDBLightingConfiguration?
    private let fields = [["LightingControl", "FailsafeDelay"], ["DimIntensity", "BrightIntensity"],
                          ["RampUpTime", "RampDownTime"], ["HoldTime"], ["InstallDate"]]

    init(site: SiteData, space: SpaceData) {
        self.space = space; service = HDBLightingConfigurationService(site: site, space: space)
        super.init(style: .insetGrouped)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "hdb_lighting_configuration".localizedString
        view.backgroundColor = Background_Color
        service.didChange = { [weak self] in self?.refresh(resetDraft: false) }
        service.didFinish = { [weak self] error in
            guard let self = self else { return }
            if let error = error, !(error is CancellationError) { self.show(error) }
            self.refresh(resetDraft: false)
        }
        refresh(resetDraft: true)
    }
    override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); refresh(resetDraft: false) }
    override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); service.cancel() }

    private var editable: Bool {
        let latest = SpaceData.load(siteId: space.siteId, spaceId: space.id).first
        return targetUuid != nil && latest?.canEditing == true && space.groupOperates.contains(.edit) && !service.isRunning
    }
    private func refresh(resetDraft: Bool) {
        do {
            _ = try HDBConfigurationStore.load(space: space)
            let active = MeshNetworkManager.instance.meshNetwork
            let network = active?.uuid.uuidString == space.meshUUID ? active : MeshNetwork.load(meshUUID: space.meshUUID, subnetworkId: space.meshNetworkId)
            lights = network?.nodes.filter { $0.subNetworkId == space.meshNetworkId && !$0.isProvisioner && !$0.isConfigComplete && $0.deviceType == .light }.sorted { $0.primaryUnicastAddress < $1.primaryUnicastAddress } ?? []
            let previous = targetUuid
            if !didSelectInitialTarget {
                targetUuid = lights.first?.uuid
                didSelectInitialTarget = true
            } else if !lights.contains(where: { $0.uuid == targetUuid }) {
                targetUuid = nil
            }
            saved = try targetUuid.flatMap { try service.saved(nodeUuid: $0) }
            if resetDraft || previous != targetUuid { values = HDBLightingValues.defaults.merging(saved?.values ?? .init()) }
        } catch { targetUuid = nil; saved = nil; values = .defaults; lights = []; show(error) }
        tableView.reloadData()
    }
    override func numberOfSections(in tableView: UITableView) -> Int { 6 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? 1 : fields[section - 1].count + 2 + (section == 1 ? 1 : 0)
    }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? "hdb_lighting_target".localizedString : HDBLightingCommand.allCases[section - 1].titleKey.localizedString
    }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if section == 0 { return (lights.isEmpty ? "hdb_add_devices_help" : "hdb_lighting_scope_help").localizedString }
        let command = HDBLightingCommand.allCases[section - 1]
        let status = saved?.status(for: command)
        let statusText = status.map { ("hdb_" + $0.rawValue).localizedString } ?? "hdb_not_set".localizedString
        return statusText + (command == .override ? "\n" + "hdb_metadata_help".localizedString : "")
    }
    private var targetTitle: String {
        guard let id = targetUuid else { return "hdb_select_light".localizedString }
        return lights.first { $0.uuid == id }?.name ?? id.uuidString
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 1 && indexPath.row == 0 {
            let controls = HDBLightingControl.allCases
            let control = UISegmentedControl(items: controls.map { ("hdb_control_" + $0.rawValue).localizedString })
            control.selectedSegmentIndex = controls.firstIndex { $0 == values.lightingControl } ?? UISegmentedControl.noSegment
            control.isEnabled = editable
            control.addTarget(self, action: #selector(lightingControlChanged(_:)), for: .valueChanged)
            return choiceCell(title: "hdb_field_LightingControl".localizedString, control: control)
        }
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        cell.textLabel?.numberOfLines = 0; cell.detailTextLabel?.numberOfLines = 0
        if indexPath.section == 0 {
            cell.textLabel?.text = "hdb_lighting_target".localizedString
            cell.detailTextLabel?.text = targetTitle
            cell.accessoryType = lights.isEmpty ? .none : .disclosureIndicator
        } else {
            let list = fields[indexPath.section - 1]
            if indexPath.row < list.count {
                let field = list[indexPath.row]
                cell.textLabel?.text = ("hdb_field_" + field).localizedString
                cell.detailTextLabel?.text = text(field) ?? "hdb_not_set".localizedString
                cell.accessoryType = .disclosureIndicator
            } else {
                let action = indexPath.row - list.count
                cell.textLabel?.text = (action == 0 ? "hdb_set" : (action == 1 ? "hdb_get" : "hdb_save_failsafe")).localizedString
                cell.textLabel?.textColor = .systemBlue
                cell.textLabel?.isEnabled = action == 1 ? targetUuid != nil && !service.isRunning : editable
            }
        }
        if indexPath.section == 0 {
            cell.isUserInteractionEnabled = !service.isRunning && !lights.isEmpty
        } else {
            let isGet = indexPath.row == fields[indexPath.section - 1].count + 1
            cell.isUserInteractionEnabled = isGet ? targetUuid != nil && !service.isRunning : editable
            cell.textLabel?.isEnabled = cell.isUserInteractionEnabled
        }
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard !service.isRunning else { return }
        if indexPath.section == 0 {
            chooseTarget()
            return
        }
        guard let targetUuid else { return }
        if indexPath.section == 1 && indexPath.row == 0 { return }
        let list = fields[indexPath.section - 1], command = HDBLightingCommand.allCases[indexPath.section - 1]
        if indexPath.row < list.count { edit(list[indexPath.row]); return }
        do {
            if indexPath.row == list.count + 1 {
                try service.get(nodeUuid: targetUuid, command: command) { [weak self] text in
                    guard let self = self, self.view.window != nil else { return }
                    self.navigationController?.pushViewController(HDBLightingReadbackViewController(text: text), animated: true)
                }
            } else {
                guard editable else { throw HDBConfigurationError.permissionDenied }
                let selected = indexPath.row == list.count + 2 ? HDBLightingValues(failsafeDelay: values.failsafeDelay) : values.selected(command)
                try service.set(nodeUuid: targetUuid, command: command, values: selected)
            }
        } catch { show(error) }
    }
    private func choiceCell(title: String, control: UISegmentedControl) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.selectionStyle = .none
        let label = UILabel()
        label.text = title
        label.font = .preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        control.accessibilityLabel = title
        let stack = UIStackView(arrangedSubviews: [label, control])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        cell.contentView.addSubview(stack)
        let margins = cell.contentView.layoutMarginsGuide
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: margins.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: margins.trailingAnchor),
            stack.topAnchor.constraint(equalTo: margins.topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: margins.bottomAnchor, constant: -4),
            control.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])
        return cell
    }
    @objc private func lightingControlChanged(_ sender: UISegmentedControl) {
        let controls = HDBLightingControl.allCases
        guard editable, controls.indices.contains(sender.selectedSegmentIndex) else { tableView.reloadData(); return }
        values.lightingControl = controls[sender.selectedSegmentIndex]
    }
    private func chooseTarget() {
        let options: [(String, () -> Void)] = lights.map { node in
            (node.name ?? String(format: "%04X", node.primaryUnicastAddress), { [weak self] in
                self?.targetUuid = node.uuid
                self?.refresh(resetDraft: true)
            })
        }
        guard !options.isEmpty else { return }
        choose(title: "hdb_lighting_target".localizedString, options: options)
    }
    private func choose(title: String, options: [(String, () -> Void)]) {
        let alert = UIAlertController(title: title, message: nil, preferredStyle: .actionSheet)
        for (title, action) in options { alert.addAction(UIAlertAction(title: title, style: .default) { _ in action() }) }
        alert.addAction(UIAlertAction(title: "cancel".localizedString, style: .cancel))
        alert.popoverPresentationController?.sourceView = view
        alert.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        present(alert, animated: true)
    }
    private func text(_ field: String) -> String? {
        switch field {
        case "LightingControl": return values.lightingControl.map { ("hdb_control_" + $0.rawValue).localizedString }
        case "FailsafeDelay": return values.failsafeDelay.map(String.init)
        case "DimIntensity": return values.dimIntensity.map(String.init)
        case "BrightIntensity": return values.brightIntensity.map(String.init)
        case "RampUpTime": return values.rampUpTime.map(String.init)
        case "RampDownTime": return values.rampDownTime.map(String.init)
        case "HoldTime": return values.holdTime.map(String.init)
        default: return values.installDate
        }
    }
    private func edit(_ field: String) {
        guard editable else { return }
        let alert = UIAlertController(title: ("hdb_field_" + field).localizedString, message: ("hdb_hint_" + field).localizedString, preferredStyle: .alert)
        alert.addTextField { input in
            input.text = self.text(field)
            if field == "InstallDate" && (input.text?.isEmpty ?? true) {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.calendar = Calendar(identifier: .gregorian)
                formatter.timeZone = .current
                formatter.dateFormat = "dd-MM-yyyy"
                input.text = formatter.string(from: Date())
            }
            input.keyboardType = field == "InstallDate" ? .numbersAndPunctuation : .numberPad
        }
        alert.addAction(UIAlertAction(title: "cancel".localizedString, style: .cancel))
        alert.addAction(UIAlertAction(title: "save".localizedString, style: .default) { [weak self, weak alert] _ in
            guard let self = self, self.editable else { return }
            let raw = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let number = Int(raw)
            guard field == "InstallDate" || raw.isEmpty || number != nil else { self.show(HDBConfigurationError.invalidData); return }
            var next = self.values
            switch field {
            case "FailsafeDelay": next.failsafeDelay = number
            case "DimIntensity": next.dimIntensity = number
            case "BrightIntensity": next.brightIntensity = number
            case "RampUpTime": next.rampUpTime = number
            case "RampDownTime": next.rampDownTime = number
            case "HoldTime": next.holdTime = number
            default: next.installDate = raw.isEmpty ? nil : raw
            }
            do { try next.validate(); self.values = next; self.tableView.reloadData() } catch { self.show(error) }
        })
        present(alert, animated: true)
    }
    private func show(_ error: Error) { XWHUDManager.showErrorTipHUD(HDBUIError.message(error)) }
}

private final class HDBLightingReadbackViewController: UIViewController {
    private let text: String
    init(text: String) { self.text = text; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad(); title = "hdb_get_json".localizedString
        let textView = UITextView(); textView.isEditable = false; textView.text = text
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular); textView.backgroundColor = Background_Color
        view = textView
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "hdb_copy_json".localizedString, style: .plain, target: self, action: #selector(copyText))
    }
    @objc private func copyText() { UIPasteboard.general.string = text }
}
