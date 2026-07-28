//
//  SpacePathTriggerZoneController.swift
//  SunSmart
//
//  Created by yuankehong on 2026/3/27.
//

import UIKit
import NordicSigMeshSDK

class SpacePathTriggerZoneController: UIViewController {

    private struct QuickAddGroupFilterOption {
        let title: String
        let group: Group?
        let enabled: Bool
    }

    let site: SiteData
    let space: SpaceData
    
    private var tableView: UITableView!
    private var deviceAddView: GroupPathSequenceDeviceAddView!
    private var deviceAddViewHeightConstraint: NSLayoutConstraint?
    private var allowDeviceAddAnimations = false
    private var didApplyInitialEmptyState = false
    
    private var setZones: [SpaceTriggerZone] = []
    private var selectZone: SpaceTriggerZone?
    
    private var deviceAddMode: PathSequenceDeviceAddMode = .quickAdd
    private var quickAddState: QuickAddState = .stop
    private var quickAddingBusy = false
    private var showAddedDevices = false
    private var triggerDevices: [Node] = []
    private var quickAddGroupFilterIndex: Int = 0
    
    init(site: SiteData, space: SpaceData) {
        self.site = site
        self.space = space
        super.init(nibName: nil, bundle: nil)
        self.setZones = space.triggerZones.map { $0.copy() }
        self.setZones.forEach { zone in
            zone.items.removeAll { item in
                item.node == nil || item.group == nil
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        title = "trigger_zone".localizedString
        view.backgroundColor = Background_Color
        navigationController?.setNavigationBarBackgroundColor(color: .clear)
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(title: "save".localizedString, color: TextBlack_Color, target: self, sel: #selector(saveAction)),
            UIBarButtonItem(image: UIImage(named: "path_add")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(addAction))
        ]
        
        setupUI()
        view.layoutIfNeeded()
        updateEmptyUI()
        updateDeviceAddViewUI()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        MeshLibManager.manager.messageDelegate = self
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        allowDeviceAddAnimations = true
        if tableView.firstShowFlashScrollIndicators {
            tableView.flashScrollIndicatorsIfNeeded()
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !didApplyInitialEmptyState else {
            return
        }
        didApplyInitialEmptyState = true
        updateEmptyUI()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if let zone = selectZone, let section = setZones.firstIndex(of: zone) {
            selectZone = nil
            tableView.reloadSections(IndexSet(integer: section), with: .none)
            updateDeviceAddViewUI()
        }
    }
    
    private var spaceGroups: [Group] {
        return MeshNetworkManager.instance.groups.filter { $0.subNetworkId == space.meshNetworkId }.sorted { lhs, rhs in
            if lhs.name != rhs.name {
                return lhs.name < rhs.name
            }
            return lhs.address.address < rhs.address.address
        }
    }

    private var eligibleGroups: [Group] {
        return spaceGroups.filter { group in
            group.info.profile.type == .proximityLighting || group.info.profile.type == .proximityLightingWithPhotocell
        }
    }
    
    private var eligibleNodes: [Node] {
        return deduplicatedNodes(from: eligibleGroups)
    }

    private var quickAddGroupFilterOptions: [QuickAddGroupFilterOption] {
        let options = spaceGroups.map { group in
            QuickAddGroupFilterOption(title: group.name,
                                      group: group,
                                      enabled: group.info.profile.type == .proximityLighting || group.info.profile.type == .proximityLightingWithPhotocell)
        }
        return [.init(title: "space_trigger_zone_all_eligible_groups".localizedString, group: nil, enabled: true)] + options
    }

    private var quickAddFilteredGroups: [Group] {
        guard quickAddGroupFilterIndex > 0,
              quickAddGroupFilterIndex < quickAddGroupFilterOptions.count,
              let group = quickAddGroupFilterOptions[quickAddGroupFilterIndex].group,
              quickAddGroupFilterOptions[quickAddGroupFilterIndex].enabled else {
            return eligibleGroups
        }
        return [group]
    }

    private var quickAddFilteredNodes: [Node] {
        return deduplicatedNodes(from: quickAddFilteredGroups)
    }

    private func deduplicatedNodes(from groups: [Group]) -> [Node] {
        var nodes: [Node] = []
        groups.forEach { group in
            group.nodes.forEach { node in
                let address = normalizedAddress(for: node)
                if !nodes.contains(where: { normalizedAddress(for: $0) == address }) {
                    nodes.append(node)
                }
            }
        }
        return nodes
    }
    
    private func normalizedAddress(for node: Node) -> Address {
        return node.sunricherVendorModel?.parentElement?.unicastAddress ?? node.primaryUnicastAddress
    }
    
    private func allAddedAddresses(usingCurrentZoneOnly: Bool) -> [Address] {
        if usingCurrentZoneOnly {
            return selectZone?.addresses ?? []
        }
        return setZones.flatMap { $0.addresses }
    }

    private func filteredTriggeredNode(for triggerAddress: Address) -> Node? {
        return quickAddFilteredNodes.first(where: { $0.contains(elementWithAddress: triggerAddress) })
    }

    private func shouldIgnoreAddedDevice(address: Address, in zone: SpaceTriggerZone) -> Bool {
        let addedAddresses = showAddedDevices ? zone.addresses : allAddedAddresses(usingCurrentZoneOnly: false)
        return addedAddresses.contains(address)
    }

    private func displayedTriggerDevices() -> [Node] {
        let addedAddresses = allAddedAddresses(usingCurrentZoneOnly: showAddedDevices)
        let filteredAddresses = quickAddFilteredNodes.map { normalizedAddress(for: $0) }
        return triggerDevices.filter {
            let address = normalizedAddress(for: $0)
            return filteredAddresses.contains(address) && !addedAddresses.contains(address)
        }
    }

    private func displayedManualNodes() -> [Node] {
        let addedAddresses = allAddedAddresses(usingCurrentZoneOnly: showAddedDevices)
        return quickAddFilteredNodes.filter { !addedAddresses.contains(normalizedAddress(for: $0)) }
    }

    private func configureQuickAddFilters() {
        let options = quickAddGroupFilterOptions
        if quickAddGroupFilterIndex >= options.count || !options[quickAddGroupFilterIndex].enabled {
            quickAddGroupFilterIndex = 0
        }
        deviceAddView.quickAddView.configureSpaceTriggerZoneQuickAdd(groupTitles: options.map(\.title),
                                                                     enabledStates: options.map(\.enabled),
                                                                     selectedGroupIndex: quickAddGroupFilterIndex,
                                                                     showAddedOnly: showAddedDevices)
        deviceAddView.triggerAddView.configureSpaceTriggerZoneFilterLayout(groupTitles: options.map(\.title),
                                                                          enabledStates: options.map(\.enabled),
                                                                          selectedGroupIndex: quickAddGroupFilterIndex,
                                                                          showAddedOnly: showAddedDevices)
        deviceAddView.manuallyAddView.configureSpaceTriggerZoneFilterLayout(groupTitles: options.map(\.title),
                                                                            enabledStates: options.map(\.enabled),
                                                                            selectedGroupIndex: quickAddGroupFilterIndex,
                                                                            showAddedOnly: showAddedDevices)
    }

    private func refreshAddModeDevices(clearTriggerDevices: Bool = false) {
        if clearTriggerDevices {
            triggerDevices.removeAll()
        }
        if deviceAddMode == .triggerAdd {
            let devices = displayedTriggerDevices()
            deviceAddView.triggerAddView.reloadData(devices: devices, selectDevice: deviceAddView.triggerAddView.selectDevice)
            deviceAddView.refreshBtn.isHidden = devices.isEmpty
        } else if deviceAddMode == .manuallyAdd {
            deviceAddView.manuallyAddView.reloadData(devices: displayedManualNodes(), selectDevice: deviceAddView.manuallyAddView.selectDevice)
            deviceAddView.updateUnfoldState()
        }
    }

    private func applyGroupFilterChange(_ index: Int) {
        guard quickAddGroupFilterIndex != index else {
            return
        }
        quickAddGroupFilterIndex = index
        configureQuickAddFilters()
        refreshAddModeDevices(clearTriggerDevices: true)
    }
    
    private func makeDisplayZone(_ zone: SpaceTriggerZone) -> GroupProximityLightingPathZone {
        return GroupProximityLightingPathZone(addresses: zone.addresses)
    }
    
    private func updateEmptyUI() {
        if setZones.isEmpty {
            tableView.layoutIfNeeded()
            UIView.performWithoutAnimation {
                view.showEmptyDataView(frame: tableView.frame,
                                       title: "no_trigger_zones".localizedString,
                                       backgroundColor: Background_Color,
                                       buttonText: "add_trigger_zone".localizedString,
                                       buttomWidth: SCRXFrom(216),
                                       position: .center,
                                       bottomMargin: SCRYFrom(100)) { [weak self] in
                    self?.addZone()
                }
            }
            tableView.isScrollEnabled = false
        } else {
            view.hideEmptyDataView()
            tableView.isScrollEnabled = true
        }
        updateDeviceAddViewUI()
    }
    
    private func updateDeviceAddViewUI() {
        let hasZones = !setZones.isEmpty
        let hasSelectedZone = selectZone != nil
        let shouldAnimate = allowDeviceAddAnimations && view.window != nil
        quickAddState = .stop
        updateDeviceAddViewHeader()
        if hasZones {
            deviceAddView.isHidden = false
            deviceAddView.alpha = 1
            if hasSelectedZone {
                deviceAddView.setCollapsed(false, animated: shouldAnimate)
            }
            deviceAddView.canAddDevice = hasSelectedZone
            deviceAddView.refreshPreferredHeight()
        } else {
            deviceAddView.canAddDevice = false
            updateDeviceAddViewHeight(0, animated: shouldAnimate)
            deviceAddView.alpha = 0
            deviceAddView.isHidden = true
        }
    }
    
    private func updateDeviceAddViewHeader() {
        let index = selectZone.flatMap { setZones.firstIndex(of: $0) }.map { $0 + 1 }
        deviceAddView.updateHeaderIndex(index)
    }
    
    private func updateDeviceAddViewHeight(_ contentHeight: CGFloat, animated: Bool) {
        let safeHeight = contentHeight <= 0 ? 0 : max(contentHeight, 44)
        deviceAddViewHeightConstraint?.constant = safeHeight
        guard animated else {
            return
        }
        UIView.animate(withDuration: 0.25) {
            self.view.layoutIfNeeded()
        }
    }
    
    func addZone() {
        let remainingZoneCount = SpaceTriggerZone.maxZoneCount - setZones.count
        guard remainingZoneCount > 0 else {
            XWHUDManager.showTipHUD("not_zones_remaining", isLineFeed: true)
            return
        }
        
        let range = 1...remainingZoneCount
        SRAlertView(title: "add_trigger_zone".localizedString,
                    message: String(format: "number_limited_range".localizedString, range.lowerBound, range.upperBound),
                    messageColor: Message_Color,
                    inputFieldStyle: .init(keyboardType: .numberPad, maxInputLength: 2, textAlignment: .center, showClear: true),
                    actions: [.cancelAction, SRAlertAction(title: "COMFIRM".localizedString, style: .default)],
                    textValueChangedBack: nil) { [weak self] text in
            guard let self, let number = Int(text), range.contains(number) else {
                XWHUDManager.showTipHUD(String(format: "number_limited_range".localizedString, range.lowerBound, range.upperBound), isLineFeed: true)
                return
            }
            self.setZones.append(contentsOf: SpaceTriggerZone.default(count: number))
            self.tableView.reloadData()
            self.updateEmptyUI()
        }.show()
    }
    
    func stopSetZone() {
        selectZone = nil
        updateDeviceAddViewUI()
    }
    
    @objc private func addAction() {
        addZone()
    }
    
    @objc private func saveAction() {
        stopSetZone()
        
        let oldZones = space.triggerZones.map { $0.copy() }
        let newZones = setZones.map { $0.copy() }
        let didEdit = !zonesEqual(oldZones, newZones)
        
        if didEdit {
            space.triggerZones = newZones
            space.lastUpdate = Int64(Date().timeIntervalSince1970)
            space.save()
        }
        
        let syncDatas = buildSyncDatas()
        guard syncDatas.count > 0 else {
            if didEdit {
                NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.common)
            }
            navigationController?.popViewController(animated: true)
            return
        }
        
        let vc = SyncDevicesViewController(type: .spaceTriggerZones(datas: syncDatas))
        vc.syncSuccessCallback = { [weak self] _ in
            XWHUDManager.showSuccessTipHUD("done!".localizedString)
            if didEdit {
                NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.common)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self?.navigationController?.popViewController(animated: true)
            }
        }
        navigationController?.pushViewController(vc, animated: true)
    }
    
    private func zonesEqual(_ lhs: [SpaceTriggerZone], _ rhs: [SpaceTriggerZone]) -> Bool {
        guard lhs.count == rhs.count else {
            return false
        }
        return zip(lhs, rhs).allSatisfy { $0 == $1 }
    }
    
    private func buildSyncDatas() -> [(node: Node, syncData: NodeSyncData)] {
        return eligibleNodes.compactMap { node in
            let desiredNeighbors = desiredNeighborAddresses(for: node)
            let relayNumber = node.group?.info.profile.proximityLightingNumber ?? 0
            let neighborsEqual = node.proximityLightingNeighborAddresses.sorted() == desiredNeighbors.sorted()
            
            if desiredNeighbors.isEmpty {
                return node.proximityLightingEnabled ? (node, .proximityLightingEnabled(false)) : nil
            }
            
            if neighborsEqual, node.proximityLightingRelayCount == relayNumber {
                return !node.proximityLightingEnabled ? (node, .proximityLightingEnabled(true)) : nil
            }
            
            if node.proximityLightingEnabled, neighborsEqual, node.proximityLightingRelayCount != relayNumber {
                return (node, .proximityLightingRelayNumber(relayNumber))
            }
            
            return (node, .proximityLightingNeighbor(relayNumber: relayNumber, neighborAddresses: desiredNeighbors))
        }
    }
    
    private func desiredNeighborAddresses(for node: Node) -> [Address] {
        let currentAddress = normalizedAddress(for: node)
        var neighbors: [Address] = []
        
        setZones.forEach { zone in
            guard zone.items.contains(where: { $0.deviceAddress == currentAddress }) else {
                return
            }
            zone.items.forEach { item in
                guard item.deviceAddress != currentAddress, !neighbors.contains(item.deviceAddress) else {
                    return
                }
                neighbors.append(item.deviceAddress)
            }
        }
        return neighbors
    }
    
    private func appendNode(_ node: Node, to zone: SpaceTriggerZone) {
        let address = normalizedAddress(for: node)
        guard !zone.items.contains(where: { $0.deviceAddress == address }),
              let groupAddress = node.group?.address.address else {
            return
        }
        zone.items.append(.init(groupAddress: groupAddress, deviceAddress: address))
    }
    
    private func setupUI() {
        deviceAddView = GroupPathSequenceDeviceAddView()
        deviceAddView.isHidden = true
        deviceAddView.contentHeightPolicy = .dynamicSelected
        deviceAddView.isSequence = false
        deviceAddView.contentHeightChanged = { [weak self] contentHeight in
            guard let self else { return }
            let shouldAnimate = self.allowDeviceAddAnimations && self.view.window != nil
            self.updateDeviceAddViewHeight(contentHeight, animated: shouldAnimate)
        }
        deviceAddView.quickAddView.guideView.steps = [
            .init(imageName: "proximity_lighting_step1", title: "zone_add_step1".localizedString, textColor: SubText_Color),
            .init(imageName: "proximity_lighting_step2", title: "zone_add_step2".localizedString, textColor: SubText_Color),
            .init(imageName: "proximity_lighting_step3", title: "zone_quick_add_step3".localizedString, textColor: SubText_Color),
        ]
        deviceAddView.triggerAddView.guideView.steps = [
            .init(imageName: "proximity_lighting_step1", title: "zone_add_step1".localizedString, textColor: SubText_Color),
            .init(imageName: "proximity_lighting_step2", title: "zone_add_step2".localizedString, textColor: SubText_Color),
            .init(imageName: "proximity_lighting_step3", title: "path_trigger_add_step3".localizedString, textColor: SubText_Color),
        ]
        deviceAddView.manuallyAddView.guideView.steps = [
            .init(imageName: "proximity_lighting_step1", title: "zone_add_step1".localizedString, textColor: SubText_Color),
            .init(imageName: "proximity_lighting_step2", title: "path_trigger_add_step3".localizedString, textColor: SubText_Color),
            .init(imageName: "proximity_lighting_step3", title: "zone_manual_add_step3".localizedString, textColor: SubText_Color),
        ]
        deviceAddView.triggerAddView.usesCompactFilterMenu = true
        deviceAddView.manuallyAddView.usesCompactFilterMenu = true
        deviceAddView.quickAddView.groupFilterChanged = { [weak self] index in
            self?.applyGroupFilterChange(index)
        }
        deviceAddView.triggerAddView.groupFilterChanged = { [weak self] index in
            self?.applyGroupFilterChange(index)
        }
        deviceAddView.manuallyAddView.groupFilterChanged = { [weak self] index in
            self?.applyGroupFilterChange(index)
        }
        configureQuickAddFilters()
        
        deviceAddView.delegate = self
        view.addSubview(deviceAddView)
        deviceAddViewHeightConstraint = deviceAddView.heightAnchor.constraint(equalToConstant: 0)
        deviceAddViewHeightConstraint?.isActive = true
        deviceAddView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.bottom.equalTo(-max(kSafeAreaBottomHeight, SCRYFrom(16)))
        }
        
        tableView = UITableView(frame: .zero, style: .grouped)
        tableView.separatorStyle = .none
        tableView.backgroundColor = .clear
        tableView.layer.cornerRadius = SCRYFrom(10)
        tableView.register(GroupPathSequencePathHeaderView.classForCoder(), forHeaderFooterViewReuseIdentifier: "header")
        tableView.register(GroupPathSequenceTriggerZoneViewCell.classForCoder(), forCellReuseIdentifier: "cell")
        tableView.estimatedRowHeight = isIPad ? SCRYFrom(90) : SCRYFrom(60)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.dataSource = self
        tableView.delegate = self
        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(view.safeAreaLayoutGuide).offset(SCRYFrom(16))
            make.bottom.equalTo(deviceAddView.snp.top)
        }
    }
}

extension SpacePathTriggerZoneController: UITableViewDataSource, UITableViewDelegate {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return setZones.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! GroupPathSequenceTriggerZoneViewCell
        let zone = setZones[indexPath.section]
        cell.reloadData(zoneIndex: indexPath.section, zone: makeDisplayZone(zone))
        cell.isSelect = zone == selectZone
        cell.delegate = self
        return cell
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let headerView = tableView.dequeueReusableHeaderFooterView(withIdentifier: "header") as! GroupPathSequencePathHeaderView
        let zone = setZones[section]
        headerView.isSelect = selectZone == zone
        headerView.nameLabel.text = "\("zone".localizedString) \(section + 1)"
        let groupCount = Set(zone.items.map { $0.groupAddress.hex }).count
        headerView.testBtn.isEnabled = zone.items.count > 0 && groupCount == 1
        headerView.resetBtn.isEnabled = zone.items.count > 0
        headerView.operationActionCallback = { [weak self] type in
            self?.zoneOperation(zone: zone, type: type)
        }
        headerView.viewSelectActionCallback = { [weak self] in
            guard let self else { return }
            var reloadSections: [Int] = []
            if let lastZone = self.selectZone, let index = self.setZones.firstIndex(of: lastZone) {
                if index == section {
                    return
                }
                if let lastHeaderView = tableView.headerView(forSection: index) as? GroupPathSequencePathHeaderView {
                    lastHeaderView.isSelect = false
                }
                reloadSections.append(index)
            }
            reloadSections.append(section)
            self.selectZone = zone
            
            if self.deviceAddMode == .triggerAdd {
                self.deviceAddView.triggerAddView.reloadData(devices: self.displayedTriggerDevices(), selectDevice: self.deviceAddView.triggerAddView.selectDevice)
            } else if self.deviceAddMode == .manuallyAdd {
                self.deviceAddView.manuallyAddView.reloadData(devices: self.displayedManualNodes(), selectDevice: self.deviceAddView.manuallyAddView.selectDevice)
            }
            
            self.tableView.reloadSections(IndexSet(reloadSections), with: .none)
            self.updateDeviceAddViewUI()
        }
        return headerView
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return SCRYFrom(40)
    }
    
    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        return UIView()
    }
    
    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        return 0.01
    }
    
    private func zoneOperation(zone: SpaceTriggerZone, type: GroupPathSequencePathHeaderView.OperationType) {
        switch type {
        case .save:
            break
        case .test:
            guard let groupAddress = zone.items.first?.groupAddress,
                  zone.items.allSatisfy({ $0.groupAddress == groupAddress }),
                  let group = zone.items.first?.group else {
                return
            }
            GroupPathSequencePathTestView(type: .zone, group: group, addresses: zone.addresses).show()
        case .reset:
            SRAlertView(title: "notification".localizedString, message: "path_reset_devices_message".localizedString, actions: [.cancelAction, SRAlertAction(title: "confirm".localizedString, actionHandler: { [weak self] _ in
                guard let self else { return }
                zone.items.removeAll()
                if let section = self.setZones.firstIndex(of: zone), let cell = self.tableView.cellForRow(at: IndexPath(row: 0, section: section)) as? GroupPathSequenceTriggerZoneViewCell {
                    cell.reloadData(zoneIndex: section, zone: self.makeDisplayZone(zone))
                }
                self.tableView.performBatchUpdates(nil)
                if self.deviceAddMode == .triggerAdd {
                    self.refreshAddModeDevices(clearTriggerDevices: true)
                } else if self.deviceAddMode == .manuallyAdd {
                    self.refreshAddModeDevices()
                }
            })]).show()
        case .delete:
            SRAlertView(title: "notification".localizedString, message: "zone_delete_message".localizedString, actions: [.cancelAction, SRAlertAction(title: "confirm".localizedString, actionHandler: { [weak self] _ in
                guard let self else { return }
                if let index = self.setZones.firstIndex(of: zone) {
                    self.setZones.remove(at: index)
                    if self.selectZone == zone {
                        self.selectZone = nil
                        self.updateDeviceAddViewUI()
                    }
                    self.updateEmptyUI()
                    self.tableView.reloadData()
                }
            })]).show()
        }
    }
}

extension SpacePathTriggerZoneController: GroupPathSequenceTriggerZoneViewCellDelegate {
    
    func cell(_ cell: GroupPathSequenceTriggerZoneViewCell, deviceIdentify device: Node) {
        MeshAPI.identify(address: device.primaryUnicastAddress)
    }
    
    func cell(_ cell: GroupPathSequenceTriggerZoneViewCell, removeDevice device: Node) {
        guard let section = tableView.indexPath(for: cell)?.section else { return }
        let address = normalizedAddress(for: device)
        let zone = setZones[section]
        zone.items.removeAll { $0.deviceAddress == address }
        cell.reloadData(zoneIndex: section, zone: makeDisplayZone(zone))
        if deviceAddMode == .manuallyAdd {
            refreshAddModeDevices()
        }
        tableView.performBatchUpdates(nil)
    }
    
    func cell(_ cell: GroupPathSequenceTriggerZoneViewCell, didSelectZone zone: GroupProximityLightingPathZone) {
        guard let section = tableView.indexPath(for: cell)?.section else { return }
        let selectZone = setZones[section]
        cell.isSelect = true
        
        if let headerView = tableView.headerView(forSection: section) as? GroupPathSequencePathHeaderView {
            headerView.isSelect = true
        }
        let lastSelectZone = self.selectZone
        self.selectZone = selectZone
        
        if let lastSelectZone, lastSelectZone != selectZone, let index = setZones.firstIndex(of: lastSelectZone) {
            tableView.reloadSections(IndexSet(integer: index), with: .none)
            if deviceAddMode == .triggerAdd {
                refreshAddModeDevices(clearTriggerDevices: true)
            } else if deviceAddMode == .manuallyAdd {
                refreshAddModeDevices()
            }
        }
        
        updateDeviceAddViewUI()
    }
    
    func cell(_ cell: GroupPathSequenceTriggerZoneViewCell, addDevice address: Address) {
        guard let section = tableView.indexPath(for: cell)?.section,
              let node = eligibleNodes.first(where: { normalizedAddress(for: $0) == address }) else {
            return
        }
        let zone = setZones[section]
        appendNode(node, to: zone)
        
        if deviceAddMode == .triggerAdd {
            if let index = triggerDevices.firstIndex(where: { normalizedAddress(for: $0) == address }) {
                triggerDevices.remove(at: index)
                refreshAddModeDevices()
            }
        } else if deviceAddMode == .manuallyAdd {
            refreshAddModeDevices()
        }
        tableView.reloadSections(IndexSet(integer: section), with: .none)
    }
}

extension SpacePathTriggerZoneController: GroupPathSequenceDeviceAddViewDelegate {
    
    func deviceAddView(_ view: GroupPathSequenceDeviceAddView, deviceAddModeChanged mode: PathSequenceDeviceAddMode) {
        if deviceAddMode == .triggerAdd {
            refreshAddModeDevices(clearTriggerDevices: true)
        }
        
        deviceAddMode = mode
        
        if mode == .triggerAdd || mode == .manuallyAdd {
            refreshAddModeDevices()
        }
    }
    
    func deviceAddView(_ view: GroupPathSequenceDeviceAddView, showAddedDevices enabled: Bool) {
        showAddedDevices = enabled
        configureQuickAddFilters()
        if deviceAddMode == .triggerAdd {
            refreshAddModeDevices()
        } else if deviceAddMode == .manuallyAdd {
            refreshAddModeDevices()
        }
    }
    
    func deviceAddView(_ view: GroupPathSequenceDeviceAddView, quickAddStateChanged state: QuickAddState) {
        quickAddState = state
    }
    
    func deviceAddView(_ view: GroupPathSequenceDeviceAddView, selectDevice device: Node) {
        guard let zone = selectZone else {
            return
        }
        let address = normalizedAddress(for: device)
        
        if deviceAddMode == .triggerAdd {
            appendNode(device, to: zone)
            if let index = triggerDevices.firstIndex(where: { normalizedAddress(for: $0) == address }) {
                triggerDevices.remove(at: index)
                refreshAddModeDevices()
            }
        } else if deviceAddMode == .manuallyAdd {
            appendNode(device, to: zone)
            refreshAddModeDevices()
        }
        
        if let section = setZones.firstIndex(of: zone) {
            tableView.reloadSections(IndexSet(integer: section), with: .none)
        }
    }
    
    func deviceAddView(_ view: GroupPathSequenceDeviceAddView, identifyDevice device: Node) {
        MeshAPI.identify(address: device.primaryUnicastAddress)
    }
    
    func deviceAddView(_ view: GroupPathSequenceDeviceAddView, triggerDevicesRefresh triggerView: GroupPathSequenceTriggerAddView) {
        triggerDevices.removeAll()
        refreshAddModeDevices()
    }
}

extension SpacePathTriggerZoneController: MeshLibManagerMessageDelegate {
    
    func meshNetworkManager(_ manager: MeshNetworkManager, didReceiveMessage message: MeshMessage, sentFrom source: Address, to destination: Address) {
        guard let zone = selectZone else {
            return
        }
        
        var triggerAddress = source
        var pirTrigger = false
        if let sensorStatus = message as? SensorStatus,
           let pirSensorValue = sensorStatus.values.first(where: { $0.property.id == DeviceProperty.presenceDetected.id }),
           case .bool(let presenceDetected) = pirSensorValue.value {
            pirTrigger = presenceDetected
        }
        if let vendorSet = message as? SunricherVendorSet, case .proximityLightingTrigger(_, let source) = vendorSet.function {
            pirTrigger = true
            triggerAddress = source
        }
        
        guard pirTrigger,
              let node = filteredTriggeredNode(for: triggerAddress),
              deviceAddMode == .quickAdd || deviceAddMode == .triggerAdd else {
            return
        }
        
        let address = normalizedAddress(for: node)
        if shouldIgnoreAddedDevice(address: address, in: zone) {
            return
        }
        
        switch deviceAddMode {
        case .quickAdd:
            if quickAddState == .adding, !quickAddingBusy {
                if !zone.addresses.contains(address) {
                    quickAddingBusy = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                        guard let self else { return }
                        self.appendNode(node, to: zone)
                        if let section = self.setZones.firstIndex(of: zone) {
                            self.tableView.reloadSections(IndexSet(integer: section), with: .none)
                        }
                        self.quickAddingBusy = false
                    }
                }
            }
        case .triggerAdd:
            if !triggerDevices.contains(where: { normalizedAddress(for: $0) == address }) {
                triggerDevices.append(node)
                refreshAddModeDevices()
            }
        default:
            break
        }
    }
}
