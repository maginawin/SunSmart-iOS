//
//  SpaceDebugViewController.swift
//  SunSmart
//
//  Created on 2026/5/16.
//

import CoreBluetooth
import UIKit
import NordicSigMeshSDK

final class SpaceDebugViewController: UIViewController {
    private let space: SpaceData
    private let session: DebugBluetoothSession
    private let viewModel: SpaceDebugViewModel
    private let onFlowFinished: () -> Void
    private let tableView = UITableView(frame: .zero, style: .grouped)
    private let summaryView = SpaceDebugSummaryView(frame: CGRect(x: 0, y: 0, width: SCREEN_WIDTH, height: SCRYFrom(68)))
    private let uartReceiveContainerView = UIView()
    private let uartReceiveLabel = UILabel()
    private let uartReceiveSwitch = UISwitch()
    private var didPrepare = false
    private var didFinishFlow = false
    private var uartObserverToken: UUID?

    init(space: SpaceData, onFlowFinished: @escaping () -> Void) {
        self.space = space
        self.session = DebugBluetoothSession(space: space)
        self.viewModel = SpaceDebugViewModel(nodes: [])
        self.onFlowFinished = onFlowFinished
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "debug".localizedString
        view.backgroundColor = Background_Color
        setupUI()
        bindViewModel()
        SpaceDebugUARTManager.shared.setActiveSpace(space)
        bindUARTManager()
        prepareAndStartScan()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        installListDisconnectHandler()
        viewModel.setConnectedNode(session.currentConnectedNodeInSpace())
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard isMovingFromParent || navigationController?.isBeingDismissed == true else {
            return
        }
        finishFlow()
    }

    deinit {
        SpaceDebugUARTManager.shared.removeObserver(uartObserverToken)
        finishFlow()
    }

    private func setupUI() {
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "stop".localizedString, style: .plain, target: self, action: #selector(scanButtonTapped))

        view.addSubview(summaryView)
        summaryView.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top)
            make.left.right.equalToSuperview()
            make.height.equalTo(SCRYFrom(68))
        }

        uartReceiveContainerView.backgroundColor = Background_Color
        view.addSubview(uartReceiveContainerView)
        uartReceiveContainerView.snp.makeConstraints { make in
            make.top.equalTo(summaryView.snp.bottom)
            make.left.right.equalToSuperview()
            make.height.equalTo(SCRYFrom(48))
        }

        uartReceiveLabel.font = Font_Medium_Size(14)
        uartReceiveLabel.textColor = Title_Color
        uartReceiveLabel.text = "debug_uart_receive_messages".localizedString
        uartReceiveContainerView.addSubview(uartReceiveLabel)

        uartReceiveSwitch.addTarget(self, action: #selector(uartReceiveSwitchChanged(_:)), for: .valueChanged)
        uartReceiveContainerView.addSubview(uartReceiveSwitch)
        uartReceiveSwitch.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.centerY.equalToSuperview()
        }

        uartReceiveLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.centerY.equalToSuperview()
            make.right.lessThanOrEqualTo(uartReceiveSwitch.snp.left).offset(SCRXFrom(-12))
        }

        tableView.backgroundColor = Background_Color
        tableView.separatorStyle = .none
        tableView.rowHeight = SCRYFrom(72)
        tableView.register(SpaceDebugDeviceCell.self, forCellReuseIdentifier: SpaceDebugDeviceCell.reuseIdentifier)
        tableView.dataSource = self
        tableView.delegate = self
        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.top.equalTo(uartReceiveContainerView.snp.bottom)
            make.left.right.bottom.equalToSuperview()
        }
    }

    private func bindViewModel() {
        viewModel.onSnapshotChanged = { [weak self] in
            self?.reloadSnapshot()
        }
        reloadSnapshot()
    }

    private func bindUARTManager() {
        uartObserverToken = SpaceDebugUARTManager.shared.observe { [weak self] _ in
            guard let self = self else {
                return
            }
            self.uartReceiveSwitch.isOn = SpaceDebugUARTManager.shared.isReceiveEnabled
            let addresses = SpaceDebugUARTManager.shared.cachedKeys(siteId: self.space.siteId, spaceId: self.space.id)
            self.viewModel.setUARTCachedAddresses(addresses)
        }
    }

    private func prepareAndStartScan() {
        guard MeshLibManager.manager.bluetoothState == .poweredOn || MeshLibManager.manager.bluetoothState == .unknown else {
            navigationController?.pushViewController(BluetoothRequiredViewController(), animated: false)
            return
        }
        guard !didPrepare else {
            startScan(reset: false)
            return
        }
        didPrepare = true
        viewModel.setScanState(.preparing)
        session.prepare { [weak self] success, connectedNode in
            guard let self = self else {
                return
            }
            self.viewModel.replaceNodes(MeshNetworkManager.instance.realNodes)
            self.viewModel.setConnectedNode(connectedNode)
            self.installListDisconnectHandler()
            guard self.viewModel.currentScanState == .preparing else {
                return
            }
            if success, self.viewModel.totalCount > 0 {
                self.startScan(reset: false)
            } else {
                self.viewModel.setScanState(.stopped)
                self.navigationItem.rightBarButtonItem?.title = "scan".localizedString
            }
        }
    }

    private func startScan(reset: Bool) {
        if reset {
            viewModel.resetFoundState()
        }
        viewModel.setScanState(.scanning)
        navigationItem.rightBarButtonItem?.title = "stop".localizedString
        navigationItem.rightBarButtonItem?.isEnabled = true
        session.startScan { [weak self] data in
            self?.viewModel.updateFoundNode(data)
        }
    }

    private func stopScan() {
        session.stopScan()
        viewModel.setScanState(.stopped)
        navigationItem.rightBarButtonItem?.title = "scan".localizedString
        navigationItem.rightBarButtonItem?.isEnabled = true
    }

    private func installListDisconnectHandler() {
        session.onUnexpectedDisconnect = { [weak self] node in
            guard let self = self else {
                return
            }
            if self.viewModel.currentScanState == .connecting(node.primaryUnicastAddress) {
                self.viewModel.setConnecting(address: nil)
            }
            self.viewModel.clearConnectedNode()
        }
    }

    @objc private func scanButtonTapped() {
        switch viewModel.currentScanState {
        case .scanning, .preparing:
            stopScan()
        case .idle, .stopped:
            startScan(reset: true)
        case .connecting:
            break
        }
    }

    @objc private func uartReceiveSwitchChanged(_ sender: UISwitch) {
        SpaceDebugUARTManager.shared.setReceiveEnabled(sender.isOn, space: space)
    }

    private func reloadSnapshot() {
        summaryView.update(state: viewModel.currentScanState, found: viewModel.foundCount, total: viewModel.totalCount)
        tableView.reloadData()
    }

    private func connect(_ item: SpaceDebugNodeItem) {
        if item.isConnected {
            stopScan()
            let detail = SpaceDebugDeviceViewController(session: session, space: space, item: item)
            navigationController?.pushViewController(detail, animated: true)
            return
        }

        guard item.isFound else {
            return
        }
        stopScan()
        viewModel.setConnecting(address: item.address)
        navigationItem.rightBarButtonItem?.isEnabled = false
        session.connect(item) { [weak self] success in
            guard let self = self else {
                return
            }
            self.viewModel.setConnecting(address: nil)
            self.navigationItem.rightBarButtonItem?.isEnabled = true
            if success {
                self.viewModel.setConnectedAddress(item.address)
                let detailItem = self.viewModel.item(address: item.address) ?? item
                let detail = SpaceDebugDeviceViewController(session: self.session, space: self.space, item: detailItem)
                self.navigationController?.pushViewController(detail, animated: true)
            } else {
                self.viewModel.setConnectedNode(self.session.currentConnectedNodeInSpace())
                self.showConnectionFailedAlert()
            }
        }
    }

    private func confirmConnect(_ item: SpaceDebugNodeItem) {
        guard item.isFound else {
            return
        }
        let hasCurrentProxy = MeshLibManager.manager.currentProxy != nil
        let message = hasCurrentProxy ? "debug_switch_proxy_message".localizedString : "debug_connect_proxy_message".localizedString
        SRAlertView(title: "debug_connect_proxy_title".localizedString, message: message, actions: [
            .cancelAction,
            SRAlertAction(title: "confirm".localizedString, actionHandler: { [weak self] _ in
                self?.connect(item)
            })
        ]).show()
    }

    private func showConnectionFailedAlert() {
        SRAlertView(title: "failed".localizedString, message: "debug_connection_failed_message".localizedString, actions: [
            SRAlertAction(title: "ok".localizedString, actionHandler: nil),
            SRAlertAction(title: "scan".localizedString, actionHandler: { [weak self] _ in
                self?.startScan(reset: true)
            })
        ]).show()
    }

    private func finishFlow() {
        guard !didFinishFlow else {
            return
        }
        didFinishFlow = true
        session.finish()
        onFlowFinished()
    }

    private func shareUARTLog(for item: SpaceDebugNodeItem, sourceView: UIView) {
        let key = SpaceDebugUARTManager.shared.key(space: space, node: item.node)
        let messages = SpaceDebugUARTManager.shared.cachedMessages(for: key)
        guard !messages.isEmpty else {
            return
        }
        let context = makeExportContext(item: item, droppedMessageCount: SpaceDebugUARTManager.shared.droppedMessageCount(for: key))
        do {
            let fileURL = try SpaceDebugUARTLogExporter.makeFileURL(context: context, messages: messages)
            let controller = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
            if let popoverController = controller.popoverPresentationController {
                popoverController.sourceView = sourceView
                popoverController.sourceRect = sourceView.bounds
            }
            present(controller, animated: true)
        } catch {
            XWHUDManager.showErrorTipHUD("debug_uart_export_failed_message".localizedString)
        }
    }

    private func makeExportContext(item: SpaceDebugNodeItem, droppedMessageCount: Int) -> SpaceDebugUARTLogExportContext {
        let siteName = SiteData.load(siteId: space.siteId)?.name ?? "--"
        let node = item.node
        return SpaceDebugUARTLogExportContext(
            siteName: siteName,
            spaceName: space.name,
            groupName: item.groupName,
            deviceName: item.nodeName,
            macAddress: node.macAddressResult ?? node.macAddress ?? "--",
            companyID: node.companyIdentifier.map { String(format: "0x%04X", $0) } ?? "--",
            productID: node.productIdentifier.map { String(format: "0x%04X", $0) } ?? "--",
            address: "\(node.primaryUnicastAddress)",
            versionIdentifier: "\(node.versionSEQ)",
            model: node.modelName ?? "--",
            deviceType: item.category.title,
            firmwareVersion: node.firmwareVersion ?? node.distributionVersion ?? "--",
            droppedMessageCount: droppedMessageCount,
            generatedAt: Date()
        )
    }
}

extension SpaceDebugViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        viewModel.sections().count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        viewModel.sections()[section].items.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        viewModel.sections()[section].category.title
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: SpaceDebugDeviceCell.reuseIdentifier, for: indexPath) as! SpaceDebugDeviceCell
        cell.delegate = self
        cell.update(item: viewModel.item(at: indexPath))
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let item = viewModel.item(at: indexPath)
        if item.isConnected {
            connect(item)
        } else {
            confirmConnect(item)
        }
    }
}

extension SpaceDebugViewController: SpaceDebugDeviceCellDelegate {
    func spaceDebugDeviceCellDidTapShare(_ cell: SpaceDebugDeviceCell) {
        guard let indexPath = tableView.indexPath(for: cell) else {
            return
        }
        shareUARTLog(for: viewModel.item(at: indexPath), sourceView: cell)
    }
}
