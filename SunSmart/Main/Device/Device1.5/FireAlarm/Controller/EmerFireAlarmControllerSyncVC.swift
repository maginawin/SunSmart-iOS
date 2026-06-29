//
//  EmerFireAlarmControllerSyncVC.swift
//  SunSmart
//
//  Created by Plato Jobs on 2026/5/8.
//

import UIKit
import NordicSigMeshSDK

final class EmerFireAlarmControllerSyncVC: UIViewController {

    private enum SyncState {
        case inSync
        case syncFailure
        case syncSuccess
    }

    private let space: SpaceData
    private let data: DeviceEmerFireData
    private let suppliedItems: [EmergencyFireControllerSyncItem]?
    private let syncSuccessCallback: (() -> Void)?
    private let persistsSyncResult: Bool
    private var didCallSyncSuccessCallback = false

    private var tableView: UITableView!
    private var bottomView: UIView!
    private var selectAllBtn: UIButton!
    private var progressLabel: UILabel!
    private lazy var backBtn: UIButton = {
        UIButton(normalImageName: "navigation_back", target: self, action: #selector(backAction))
    }()

    private var items: [EmergencyFireControllerSyncItem] = []
    private var syncState: SyncState = .inSync
    private var bottomContentHeight: CGFloat {
        SCRYFrom(56) + (isIPad ? 0 : kSafeAreaBottomHeight)
    }

    init(
        space: SpaceData,
        data: DeviceEmerFireData,
        items: [EmergencyFireControllerSyncItem]? = nil,
        persistsSyncResult: Bool = true,
        syncSuccessCallback: (() -> Void)? = nil
    ) {
        self.space = space
        self.data = data
        self.suppliedItems = items
        self.syncSuccessCallback = syncSuccessCallback
        self.persistsSyncResult = persistsSyncResult
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        isModalInPresentation = true
        title = "sync_device(s)".localizedString
        view.backgroundColor = Background_Color
        navigationItem.leftBarButtonItem = UIBarButtonItem(customView: backBtn)
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "re_sync".localizedString, color: Title_Color, font: UIFont.systemFont(ofSize: 16, weight: .light), target: self, sel: #selector(rightItemAction))

        setupUI()
        setupDataSource()
        tableView.reloadData()
        updateProgress()

        if syncState == .inSync {
            startSync()
        }
    }

    private func setupUI() {
        bottomView = UIView()
        bottomView.backgroundColor = .white
        view.addSubview(bottomView)
        bottomView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(bottomContentHeight)
        }

        progressLabel = UILabel(text: "", textColor: TextBlack_Color, fontSize: 12)
        bottomView.addSubview(progressLabel)
        progressLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(18))
            make.top.equalTo(SCRYFrom(25))
        }

        selectAllBtn = UIButton(title: "select_all".localizedString, titleSize: 12, titleWeight: .light, titleColor: TextBlack_Color, normalImageName: "device_select_un", selectedImageName: "device_select", target: self, action: #selector(selectAllBtnAction))
        selectAllBtn.setImagePosition(position: .left, spacing: SCRXFrom(8))
        bottomView.addSubview(selectAllBtn)
        selectAllBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-26))
            make.top.equalTo(SCRYFrom(17))
        }

        tableView = UITableView(frame: .zero, style: .plain)
        tableView.backgroundColor = Background_Color
        tableView.separatorStyle = .none
        tableView.dataSource = self
        tableView.delegate = self
        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(view.safeAreaLayoutGuide)
            make.bottom.equalToSuperview()
        }
    }

    private func setupDataSource() {
        if let suppliedItems {
            items.append(contentsOf: suppliedItems)
            return
        }
        do {
            let planner = EmergencyFireControllerSyncPlanner(data: data, meshUUID: space.meshUUID, subnetworkId: space.meshNetworkId)
            items.append(contentsOf: try planner.makeItems())
        } catch {
            finishSync(success: false)
            XWHUDManager.showErrorTipHUD(error.localizedDescription)
        }
    }

    private var allTasks: [EmergencyFireControllerSyncTask] {
        items.flatMap { $0.tasks }
    }

    private var visibleRows: [Any] {
        var rows: [Any] = []
        items.forEach { item in
            rows.append(item)
            if item.isExpanded {
                rows.append(contentsOf: item.tasks)
            }
        }
        return rows
    }

    private func startSync() {
        let tasks = allTasks.filter { $0.state == .none || ($0.state == .failed && $0.isUnsupported) }
        guard !tasks.isEmpty else {
            finishSync(success: true)
            updateProgress()
            return
        }
        send(taskIndex: 0, tasks: tasks)
    }

    private func send(taskIndex: Int, tasks: [EmergencyFireControllerSyncTask]) {
        guard syncState == .inSync else { return }
        guard taskIndex < tasks.count else {
            finishSync(success: !allTasks.contains(where: { $0.state == .failed }))
            updateProgress()
            tableView.reloadData()
            return
        }

        let task = tasks[taskIndex]
        guard !task.isUnsupported else {
            task.state = .failed
            task.isSelected = false
            updateProgress()
            send(taskIndex: taskIndex + 1, tasks: tasks)
            return
        }
        guard !task.messageHandles.isEmpty else {
            task.state = .successful
            data.clearPending(for: task, meshUUID: space.meshUUID, subnetworkId: space.meshNetworkId)
            updateProgress()
            send(taskIndex: taskIndex + 1, tasks: tasks)
            return
        }

        task.state = .inSettings
        tableView.reloadData()
        updateProgress()
        MeshProxyMessageCommand.shared.addMessage(messageHandles: task.messageHandles, progressBack: nil) { [weak self] handle, _ in
            guard handle.isSuccessful, let node = MeshNetworkManager.instance.meshNetwork?.node(withAddress: task.address) else { return }
            node.updateData(message: handle.message)
            self?.tableView.reloadData()
        } failedBack: { _ in
        } finishedBack: { [weak self] handles in
            guard let self else { return }
            let successful = handles.allSatisfy { $0.isSuccessful }
            task.state = successful ? .successful : .failed
            task.isSelected = false
            if successful {
                self.data.clearPending(for: task, meshUUID: self.space.meshUUID, subnetworkId: self.space.meshNetworkId)
            }
            if let node = MeshNetworkManager.instance.meshNetwork?.node(withAddress: task.address) {
                node.save()
            }
            self.updateProgress()
            self.tableView.reloadData()
            self.send(taskIndex: taskIndex + 1, tasks: tasks)
        }
    }

    private func updateProgress() {
        let total = allTasks.count
        let done = allTasks.filter { $0.state == .successful }.count
        progressLabel.text = "\(done)/\(total)"
        switch syncState {
        case .inSync:
            navigationItem.rightBarButtonItem?.title = "stop".localizedString
            navigationItem.rightBarButtonItem?.isEnabled = true
            bottomView.isHidden = false
            tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: bottomContentHeight, right: 0)
            backBtn.isHidden = true
            selectAllBtn.isHidden = true
        case .syncFailure:
            navigationItem.rightBarButtonItem?.title = "re_sync".localizedString
            bottomView.isHidden = false
            backBtn.isHidden = false
            selectAllBtn.isHidden = false
            tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: bottomContentHeight, right: 0)
            let failedTasks = retryableFailedTasks
            let selectedFailedTasks = failedTasks.filter { $0.isSelected }
            selectAllBtn.isSelected = !failedTasks.isEmpty && selectedFailedTasks.count == failedTasks.count
            navigationItem.rightBarButtonItem?.isEnabled = !failedTasks.isEmpty
        case .syncSuccess:
            bottomView.isHidden = true
            tableView.contentInset = .zero
            navigationItem.rightBarButtonItem = UIBarButtonItem()
            backBtn.isHidden = false
        }
    }

    private var retryableFailedTasks: [EmergencyFireControllerSyncTask] {
        allTasks.filter { $0.state == .failed && !$0.isUnsupported }
    }

    @objc private func rightItemAction() {
        switch syncState {
        case .inSync:
            MeshProxyMessageCommand.shared.stopSendMessage(finishedBack: nil)
            allTasks.filter { $0.state == .none || $0.state == .inSettings }.forEach {
                $0.state = .failed
                $0.isSelected = false
            }
            finishSync(success: false)
            updateProgress()
            tableView.reloadData()
        case .syncFailure:
            let failedTasks = retryableFailedTasks
            let selectedTasks = failedTasks.filter { $0.isSelected }
            let tasksToRetry = selectedTasks.isEmpty ? failedTasks : selectedTasks
            guard !tasksToRetry.isEmpty else {
                updateProgress()
                return
            }
            tasksToRetry.forEach {
                $0.state = .none
                $0.isSelected = false
            }
            syncState = .inSync
            updateProgress()
            tableView.reloadData()
            startSync()
        case .syncSuccess:
            NotificationCenter.default.post(name: .init(deviceOthersRefreshNotificationName), object: nil)
            NotificationCenter.default.postLinkedEmerFireConfigDidChange(data.toConfig())
            if syncSuccessCallback != nil {
                performSyncSuccessCallback()
                return
            }
            closeAfterSync()
        }
    }

    @objc private func backAction() {
        if syncState == .syncSuccess, syncSuccessCallback != nil {
            performSyncSuccessCallback()
            return
        }
        closeAfterSync()
    }

    @objc private func selectAllBtnAction(sender: UIButton) {
        sender.isSelected.toggle()
        retryableFailedTasks.forEach { $0.isSelected = sender.isSelected }
        updateProgress()
        tableView.reloadData()
    }

    private func closeAfterSync() {
        let isNavigationRoot = navigationController?.viewControllers.first === self
        if isNavigationRoot, presentingViewController != nil || navigationController?.presentingViewController != nil {
            dismiss(animated: true)
        } else {
            navigationController?.popViewController(animated: true)
        }
    }

    private func finishSync(success: Bool) {
        syncState = success ? .syncSuccess : .syncFailure
        if persistsSyncResult {
            refreshControllerSelfSyncPending()
            data.refreshEmergencyFireControllerSyncState(
                meshUUID: space.meshUUID,
                subnetworkId: space.meshNetworkId
            )
        }
        if !success {
            retryableFailedTasks.forEach { $0.isSelected = true }
        }
        if persistsSyncResult {
            DeviceEmerFireStore.shared.save(data)
            notifySpaceDataChangedForPersistedResult()
        }
        NotificationCenter.default.post(name: .init(deviceOthersRefreshNotificationName), object: nil)
        NotificationCenter.default.postLinkedEmerFireConfigDidChange(data.toConfig())
        if success {
            performSyncSuccessCallback()
        }
    }

    private func refreshControllerSelfSyncPending() {
        let selfTasks = allTasks.filter { isControllerSelfTaskKind($0.kind) }
        guard !selfTasks.isEmpty else {
            return
        }
        data.controllerSelfSyncPending = !selfTasks.allSatisfy { $0.state == .successful }
    }

    private func isControllerSelfTaskKind(_ kind: EmergencyFireControllerSyncTaskKind) -> Bool {
        switch kind {
        case .publication, .workingMode, .resend, .restoreDelay, .actionConfig:
            return true
        case .lightnessSubscription, .lightLCSubscription, .associationSubscription, .associationCleanup, .deleteCleanup, .deleteConfiguration:
            return false
        }
    }

    private func notifySpaceDataChangedForPersistedResult() {
        NotificationCenter.default.post(
            name: .init(spaceDataChangedNotificaitonName),
            object: SpaceChangeDataType.device
        )
    }

    private func performSyncSuccessCallback() {
        guard let syncSuccessCallback, !didCallSyncSuccessCallback else {
            return
        }
        didCallSyncSuccessCallback = true
        syncSuccessCallback()
    }

    private func stateText(_ state: SyncDevicesState) -> String {
        switch state {
        case .none:
            return ""
        case .wait:
            return "waiting".localizedString
        case .successful:
            return "done".localizedString
        case .failed:
            return "failed".localizedString
        case .inSettings:
            return "syncing_data".localizedString
        }
    }

    private func stateColor(_ state: SyncDevicesState) -> UIColor {
        switch state {
        case .successful:
            return Green_Color
        case .failed:
            return Red_Color
        case .inSettings:
            return Bar_Color
        default:
            return SubText_Color
        }
    }

    private func itemState(_ item: EmergencyFireControllerSyncItem) -> SyncDevicesState {
        guard !item.tasks.isEmpty else { return .successful }
        if item.tasks.contains(where: { $0.state == .failed }) {
            return .failed
        }
        if item.tasks.contains(where: { $0.state == .inSettings }) {
            return .inSettings
        }
        if item.tasks.allSatisfy({ $0.state == .successful }) {
            return .successful
        }
        return .wait
    }
}

extension EmerFireAlarmControllerSyncVC: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        visibleRows.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "cell")
        cell.backgroundColor = .white
        cell.selectionStyle = .none
        cell.textLabel?.font = UIFont.systemFont(ofSize: SCRYFrom(14), weight: .light)
        cell.detailTextLabel?.font = UIFont.systemFont(ofSize: SCRYFrom(12), weight: .light)
        cell.detailTextLabel?.textColor = SubText_Color

        let row = visibleRows[indexPath.row]
        if let item = row as? EmergencyFireControllerSyncItem {
            let state = itemState(item)
            cell.imageView?.image = UIImage(named: item.iconName)
            cell.textLabel?.text = item.name
            cell.detailTextLabel?.text = stateText(state)
            cell.detailTextLabel?.textColor = stateColor(state)
            cell.indentationLevel = 0
            if syncState == .syncFailure, state == .failed {
                let failedTasks = item.tasks.filter { $0.state == .failed && !$0.isUnsupported }
                cell.accessoryType = !failedTasks.isEmpty && failedTasks.allSatisfy { $0.isSelected } ? .checkmark : .none
            } else {
                cell.accessoryType = item.tasks.isEmpty ? .none : .disclosureIndicator
            }
        } else if let task = row as? EmergencyFireControllerSyncTask {
            cell.imageView?.image = nil
            cell.textLabel?.text = task.kind.localizedTitle
            cell.detailTextLabel?.text = stateText(task.state)
            cell.detailTextLabel?.textColor = stateColor(task.state)
            cell.indentationLevel = 2
            cell.accessoryType = syncState == .syncFailure && task.state == .failed && task.isSelected ? .checkmark : .none
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let row = visibleRows[indexPath.row]
        if let item = row as? EmergencyFireControllerSyncItem, !item.tasks.isEmpty {
            if syncState == .syncFailure, itemState(item) == .failed {
                let failedTasks = item.tasks.filter { $0.state == .failed && !$0.isUnsupported }
                let shouldSelect = failedTasks.contains { !$0.isSelected }
                failedTasks.forEach { $0.isSelected = shouldSelect }
                updateProgress()
            } else {
                item.isExpanded.toggle()
            }
            tableView.reloadData()
        } else if let task = row as? EmergencyFireControllerSyncTask,
                  syncState == .syncFailure,
                  task.state == .failed,
                  !task.isUnsupported {
            task.isSelected.toggle()
            updateProgress()
            tableView.reloadData()
        }
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        SCRYFrom(44)
    }
}
