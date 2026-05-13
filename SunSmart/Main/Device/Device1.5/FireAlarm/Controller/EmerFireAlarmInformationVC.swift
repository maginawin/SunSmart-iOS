//
//  EmerFireAlarmInformationVC.swift
//  SunSmart
//
//  Created by Plato Jobs on 2026/4/21.
//
//应急火警设备信息页
import UIKit
import NordicSigMeshSDK

final class EmerFireAlarmInformationVC: UIViewController {

    private enum Section: Int, CaseIterable {
        case device
        case group
    }

    private struct InfoRow {
        let title: String
        let value: String
        let showsCopyButton: Bool
    }

    private let device: DeviceEmerFireData?
    private let config: LinkedEmerFireConfig?

    private var deviceSectionExpanded = true

    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .grouped)
        tableView.backgroundColor = Background_Color
        tableView.separatorStyle = .none
        tableView.showsVerticalScrollIndicator = false
        if #available(iOS 15.0, *) {
            tableView.sectionHeaderTopPadding = 0
        }
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = SCRYFrom(44)
        tableView.sectionHeaderHeight = SCRYFrom(44)
        tableView.sectionFooterHeight = CGFloat.leastNormalMagnitude
        tableView.contentInsetAdjustmentBehavior = .never
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(EmerFireAlarmInfoRowCell.self)
        tableView.register(EmerFireAlarmInfoSectionHeaderView.self, forHeaderFooterViewReuseIdentifier: "EmerFireAlarmInfoSectionHeaderView")
        return tableView
    }()

    init(device: DeviceEmerFireData? = nil, config: LinkedEmerFireConfig? = nil) {
        self.device = device
        self.config = config
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupNavigation()
    }

    @objc private func backAction() {
        if let navigationController, navigationController.viewControllers.first != self {
            navigationController.popViewController(animated: true)
        } else {
            dismiss(animated: true)
        }
    }

    private func setupUI() {
        view.backgroundColor = Background_Color

        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top)
            make.left.right.bottom.equalToSuperview()
        }
    }

    private func setupNavigation() {
        title = "Information"
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(named: "navigation_back")?.withRenderingMode(.alwaysOriginal),
            style: .plain,
            target: self,
            action: #selector(backAction)
        )
       
    }

    private func rows(for section: Section) -> [InfoRow] {
        switch section {
        case .device:
            return deviceSectionExpanded ? makeDeviceRows() : []
        case .group:
            return makeGroupRows()
        }
    }

    private func copy(text: String) {
        UIPasteboard.general.string = text
        XWHUDManager.showTipHUD("copy_success".localizedString, isLineFeed: false)
    }

    private func makeDeviceRows() -> [InfoRow] {
        let resolvedConfig = config ?? device.map(makeConfig(from:))
        let addressText = device?.bindNodeAddress?.hex ?? "--"
        let gatewayText = device?.gateWayData?.name ?? (resolvedConfig?.reportToGateway == true ? "Configured" : "Waiting for setup")
        let syncText = resolvedConfig?.isSynced == true ? "synchronized".localizedString : "unsynced".localizedString
        return [
            .init(title: "Name", value: resolvedConfig?.deviceName ?? device?.name ?? "EFC 1", showsCopyButton: false),
            .init(title: "Address", value: addressText, showsCopyButton: false),
            .init(title: "Gateway", value: gatewayText, showsCopyButton: false),
            .init(title: "Device Type", value: "Emergency Controller", showsCopyButton: false),
            .init(title: "Sync Status", value: syncText, showsCopyButton: false)
        ]
    }

    private func makeGroupRows() -> [InfoRow] {
        let resolvedConfig = config ?? device.map(makeConfig(from:))
        let powerLossAddresses = resolvedConfig?.configuration.powerLossSettings.associateGroupAddresses ?? []
        let fireAlarmAddresses = resolvedConfig?.configuration.fireAlarmSettings.associateGroupAddresses ?? []
        let powerLossNames = groupNames(for: powerLossAddresses)
        let fireAlarmNames = groupNames(for: fireAlarmAddresses)
        return [
            .init(title: "Power Loss Group", value: powerLossAddresses.isEmpty ? "Not yet linked to a group" : powerLossNames.joined(separator: ", "), showsCopyButton: false),
            .init(title: "Fire Alarm Group", value: fireAlarmAddresses.isEmpty ? "Not yet linked to a group" : fireAlarmNames.joined(separator: ", "), showsCopyButton: false)
        ]
    }

    private func groupNames(for addresses: [UInt16]) -> [String] {
        addresses.map { address in
            if let group = MeshNetworkManager.instance.groups.first(where: { $0.address.address == address }) {
                return group.name
            }
            if let group = MeshNetworkManager.instance.meshNetwork?.group(withAddress: MeshAddress(address)) {
                return group.name
            }
            return address.hex
        }
    }

    private func makeConfig(from device: DeviceEmerFireData) -> LinkedEmerFireConfig {
        LinkedEmerFireConfig(
            deviceId: device.id,
            spaceId: device.spaceId,
            meshUUID: device.meshUUID,
            meshNetworkId: device.meshNetworkId,
            deviceName: device.name,
            isSynced: device.isSynced,
            reportToGateway: device.reportToGateway,
            publishGroupAddress: device.publishGroupAddress,
            configuration: device.configuration
        )
    }
}

extension EmerFireAlarmInformationVC: UITableViewDataSource, UITableViewDelegate {

    func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let section = Section(rawValue: section) else {
            return 0
        }
        return rows(for: section).count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell: EmerFireAlarmInfoRowCell = tableView.dequeueReusableCell(for: indexPath)
        guard let section = Section(rawValue: indexPath.section) else {
            return cell
        }

        let sectionRows = rows(for: section)
        let row = sectionRows[indexPath.row]
        let showsSeparator = indexPath.row < sectionRows.count - 1
        cell.configure(
            title: row.title,
            value: row.value,
            showsCopyButton: row.showsCopyButton,
            showsSeparator: showsSeparator
        ) { [weak self] text in
            self?.copy(text: text)
        }
        if indexPath.section==0{
            cell.updateTitlConstant(update: true)
        }else{
            cell.updateTitlConstant(update: false)
        }
        return cell
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard
            let section = Section(rawValue: section),
            let header = tableView.dequeueReusableHeaderFooterView(withIdentifier: "EmerFireAlarmInfoSectionHeaderView") as? EmerFireAlarmInfoSectionHeaderView
        else {
            return nil
        }

        switch section {
        case .device:
            header.configure(title: "Device", showsArrow: true, isExpanded: deviceSectionExpanded)
            header.tapHandler = { [weak self] in
                guard let self else {
                    return
                }
                self.deviceSectionExpanded.toggle()
                self.tableView.reloadSections(IndexSet(integer: section.rawValue), with: .automatic)
            }
        case .group:
            header.configure(title: "", showsArrow: false, isExpanded: true)
            header.tapHandler = nil
        }
        return header
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        let section = Section(rawValue: section)
        return (section == .device ? SCRYFrom(44) : 0.01)
      
    }
    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        CGFloat.leastNormalMagnitude
    }
}
