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
    private var didPrepare = false
    private var didFinishFlow = false

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
        prepareAndStartScan()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard isMovingFromParent || navigationController?.isBeingDismissed == true else {
            return
        }
        finishFlow()
    }

    deinit {
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

        tableView.backgroundColor = Background_Color
        tableView.separatorStyle = .none
        tableView.rowHeight = SCRYFrom(72)
        tableView.register(SpaceDebugDeviceCell.self, forCellReuseIdentifier: SpaceDebugDeviceCell.reuseIdentifier)
        tableView.dataSource = self
        tableView.delegate = self
        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.top.equalTo(summaryView.snp.bottom)
            make.left.right.bottom.equalToSuperview()
        }
    }

    private func bindViewModel() {
        viewModel.onSnapshotChanged = { [weak self] in
            self?.reloadSnapshot()
        }
        reloadSnapshot()
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
        session.prepare { [weak self] success in
            guard let self = self else {
                return
            }
            self.viewModel.replaceNodes(MeshNetworkManager.instance.realNodes)
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

    private func reloadSnapshot() {
        summaryView.update(state: viewModel.currentScanState, found: viewModel.foundCount, total: viewModel.totalCount)
        tableView.reloadData()
    }

    private func connect(_ item: SpaceDebugNodeItem) {
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
                let detail = SpaceDebugDeviceViewController(session: self.session, space: self.space, item: item)
                self.navigationController?.pushViewController(detail, animated: true)
            } else {
                self.showConnectionFailedAlert()
            }
        }
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
        cell.update(item: viewModel.item(at: indexPath))
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        connect(viewModel.item(at: indexPath))
    }
}
