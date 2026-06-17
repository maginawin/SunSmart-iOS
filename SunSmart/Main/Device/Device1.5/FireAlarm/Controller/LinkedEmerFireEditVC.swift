//
//  LinkedEmerFireEditVC.swift
//  SunSmart
//
//  Created by Plato Jobs on 2026/4/20.
//

//应急火警设备编辑页
import UIKit

final class LinkedEmerFireEditVC: UIViewController {

    private let viewModel: LinkedEmerFireEditViewModel
    private let space: SpaceData?
    private var hasRefreshedInitialTableLayout = false
    private var isCreateMode: Bool { state.deviceId == nil }
    private var isUnlinkedVirtualMode: Bool {
        !isCreateMode && viewModel.currentDevice()?.bindNode == nil
    }
    var state: LinkedEmerFireEditState { viewModel.state }
    var shouldShowSyncStatus: Bool { viewModel.shouldShowSyncStatus }
    var editable: Bool {
        get { state.editable }
        set { state.editable = newValue }
    }

    init(config: LinkedEmerFireConfig? = nil, space: SpaceData? = nil) {
        self.space = space
        viewModel = LinkedEmerFireEditViewModel(config: config, space: space)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .plain                                                                     )
        tableView.backgroundColor = Background_Color
        tableView.separatorStyle = .none
        tableView.showsVerticalScrollIndicator = false
        tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: SCRYFrom(20), right: 0)
        tableView.keyboardDismissMode = .onDrag
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = SCRYFrom(84)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(EmerFireNameCell.self)
        tableView.register(EmerFireToggleCell.self)
        tableView.register(EmerFireStatusTextCell.self)
        tableView.register(EmerFireSelectionCell.self)
        tableView.register(EmerFireRestoreActionCell.self)
        tableView.register(EmerFireInfoCell.self)
        tableView.register(EmerFireStepperCell.self)
        tableView.register(EmerFireDualStepperCell.self)
        return tableView
    }()

    private lazy var bottomView: DeviceBottomBtnView = {
        DeviceBottomBtnView(frame: .zero)
    }()

    private lazy var linkView: PJLinkedStaOpertionsView = {
        let view = PJLinkedStaOpertionsView()
        view.createAction = { [weak self] in
            self?.linkRealDeviceAction()
        }
        return view
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupNavigation()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !hasRefreshedInitialTableLayout else { return }
        hasRefreshedInitialTableLayout = true
        tableView.performBatchUpdates(nil)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if viewModel.refreshSyncStatusFromStore() {
            tableView.reloadData()
        }
        if !isCreateMode {
            linkView.configure(isLinked: viewModel.currentDevice()?.bindNode != nil)
        }
    }

    @objc private func backAction() {
        if let navigationController, navigationController.viewControllers.first != self {
            navigationController.popViewController(animated: true)
        } else {
            dismiss(animated: true)
        }
    }

    @objc private func saveAction() {
        view.endEditing(true)
        guard validateBeforeSaving() else { return }
        if isCreateMode {
            createVirtualDevice()
            return
        }
        guard viewModel.save() != nil else {
            XWHUDManager.showTipHUD("failed".localizedString, isLineFeed: false)
            return
        }
        NotificationCenter.default.post(name: .init(deviceOthersRefreshNotificationName), object: nil)
        notifySpaceDataChanged(type: .device)
        if let savedDevice = viewModel.currentDevice(), let space, savedDevice.bindNode != nil, viewModel.lastSavedRequiresSync {
            let controller = SyncDevicesViewController(type: .emergencyFire(data: savedDevice, items: nil, context: .saveConfiguration(persistsSyncResult: true, changedFromConfiguration: viewModel.lastSavedConfigurationChange?.old)))
            controller.syncSuccessCallback = { [weak self] _ in
                self?.finishAfterSuccessfulSaveSync()
            }
            navigationController?.pushViewController(controller, animated: true)
            return
        }
        finishAfterSuccessfulSaveSync()
    }

    @objc private func createAction() {
        view.endEditing(true)
        guard validateBeforeSaving() else { return }
        createVirtualDevice()
    }

    private func createVirtualDevice() {
        guard let space else {
            XWHUDManager.showTipHUD("failed".localizedString, isLineFeed: false)
            return
        }
        guard viewModel.create(in: space) != nil else {
            XWHUDManager.showTipHUD("failed".localizedString, isLineFeed: false)
            return
        }
        NotificationCenter.default.post(name: .init(deviceOthersRefreshNotificationName), object: nil)
        notifySpaceDataChanged(type: .device)
        XWHUDManager.showSuccessTipHUD("done!".localizedString)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.dismiss(animated: true)
        }
    }

    @objc private func deleteAction() {
        view.endEditing(true)
        guard state.editable else {
            XWHUDManager.showTipHUD("no_permission".localizedString, isLineFeed: true)
            return
        }
        SRAlertView(title: "notification".localizedString, message: "device_delete_message".localizedString, actions: [
            .cancelAction,
            SRAlertAction(title: "alert_item_delete".localizedString, style: .destructive, actionHandler: { [weak self] _ in
                guard let self = self, self.viewModel.delete() else {
                    XWHUDManager.showTipHUD("failed".localizedString, isLineFeed: false)
                    return
                }
                NotificationCenter.default.post(name: .init(deviceOthersRefreshNotificationName), object: nil)
                self.notifySpaceDataChanged(type: .device)
                XWHUDManager.showSuccessTipHUD("done!".localizedString)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    self.dismiss(animated: true)
                }
            })
        ]).show()
    }

    func openSyncForCurrentDevice() {
        guard let space, let device = viewModel.currentDevice() else {
            XWHUDManager.showTipHUD("failed".localizedString, isLineFeed: false)
            return
        }
        let controller = SyncDevicesViewController(type: .emergencyFire(data: device, items: nil, context: .saveConfiguration(persistsSyncResult: true, changedFromConfiguration: nil)))
        navigationController?.pushViewController(controller, animated: true)
    }

    private func linkRealDeviceAction() {
        view.endEditing(true)
        guard state.editable else {
            XWHUDManager.showTipHUD("no_permission".localizedString, isLineFeed: true)
            return
        }
        guard validateBeforeSaving() else { return }
        guard let space, let device = viewModel.save() else {
            XWHUDManager.showTipHUD("failed".localizedString, isLineFeed: false)
            return
        }
        guard device.bindNode == nil else {
            XWHUDManager.showTipHUD("LINKED", isLineFeed: false)
            return
        }

        let controller = DeviceAddViewController(space: space)
        controller.title = "add_device".localizedString
        controller.bindTarget = .emergencyFire(device)
        controller.addBehavior = .init(
            allowsTargetSelection: false,
            allowsCategorySelection: false,
            allowedTypes: [.others],
            blockedDeviceTypes: [.dongle, .gateway, .unknown],
            selectionMode: .single,
            forbiddenSelectionTip: "You can't choose other devices.",
            forbiddenDeviceTypeTip: "Cannot add, type mismatch"
        )
        controller.deviceAddCallback = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                _ = self.viewModel.refreshLinkedDeviceFromStore()
                self.linkView.configure(isLinked: true)
                self.tableView.reloadData()
                NotificationCenter.default.post(name: .init(deviceOthersRefreshNotificationName), object: nil)
                NotificationCenter.default.post(name: .deviceEmerFireDataDidChange, object: nil)
                self.dismiss(animated: true) { [weak self] in
                    self?.openSyncAfterLinkedDeviceIfNeeded()
                }
            }
        }

        present(NavigationViewController(rootViewController: controller), animated: true)
    }

    @discardableResult
    private func openSyncAfterLinkedDeviceIfNeeded() -> Bool {
        guard let device = viewModel.currentDevice(),
              device.bindNode != nil,
              device.configuration.hasSyncIntent else {
            return false
        }
        let controller = SyncDevicesViewController(type: .emergencyFire(data: device, items: nil, context: .saveConfiguration(persistsSyncResult: true, changedFromConfiguration: nil)))
        navigationController?.pushViewController(controller, animated: true)
        return true
    }

    private func finishAfterSuccessfulSaveSync() {
        XWHUDManager.showSuccessTipHUD("done!".localizedString)
        let presentedNavigationController = navigationController
        if let navigationController,
           let currentIndex = navigationController.viewControllers.firstIndex(of: self),
           currentIndex > 0 {
            let previousController = navigationController.viewControllers[currentIndex - 1]
            navigationController.popToViewController(previousController, animated: true)
        } else if presentedNavigationController?.presentingViewController != nil {
            presentedNavigationController?.dismiss(animated: true)
        } else if let navigationController = navigationController ?? presentedNavigationController {
            navigationController.popToDeviceOthersIfPossible()
        } else {
            dismiss(animated: true)
        }
    }

    private func notifySpaceDataChanged(type: SpaceChangeDataType) {
        NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: type)
    }

    private func setupUI() {
        view.backgroundColor = Background_Color

        if isCreateMode {
            bottomView.showCreateUI()
            bottomView.createBtn.addTarget(self, action: #selector(createAction), for: .touchUpInside)
            bottomView.isHidden = !state.editable
            view.addSubview(bottomView)
            bottomView.snp.makeConstraints { make in
                make.left.right.bottom.equalToSuperview()
                make.height.equalTo(SCRYFrom(56) + (isIPad ? 0 : kSafeAreaBottomHeight))
            }
        }

        let showsLinkView = !isCreateMode && state.editable
        linkView.configure(isLinked: viewModel.currentDevice()?.bindNode != nil)
        linkView.isHidden = !showsLinkView
        if showsLinkView {
            view.addSubview(linkView)
            linkView.snp.makeConstraints { make in
                make.left.right.equalToSuperview()
                make.bottom.equalToSuperview().offset(isIPad ? 0 : -kSafeAreaBottomHeight)
                make.height.equalTo(SCRYFrom(56))
            }
        }

        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top)
            make.left.right.equalToSuperview()
            if state.editable {
                if showsLinkView {
                    make.bottom.equalTo(linkView.snp.top).offset(-SCRYFrom(8))
                } else if isCreateMode {
                    make.bottom.equalTo(bottomView.snp.top).offset(-SCRYFrom(8))
                }
            } else {
                make.bottom.equalToSuperview()
            }
        }
    }

    private func validateBeforeSaving() -> Bool {
        guard state.editable else {
            XWHUDManager.showTipHUD("no_permission".localizedString, isLineFeed: true)
            return false
        }
        guard !state.deviceName.isAllInputTextEmpty() else {
            XWHUDManager.showTipHUD("name_empty".localizedString, isLineFeed: true)
            return false
        }
        if let space,
           DeviceEmerFireStore.shared.isNameDuplicated(state.deviceName, space: space, excluding: state.deviceId) {
            XWHUDManager.showTipHUD("name_already_exists".localizedString, isLineFeed: true)
            return false
        }
        let conflictingGroupNames = state.conflictingAssociatedGroupNames()
        if !conflictingGroupNames.isEmpty {
            let message = String(
                format: "emer_fire_same_function_group_occupied".localizedString,
                conflictingGroupNames.joined(separator: ",")
            )
            XWHUDManager.showTipHUD(message, isLineFeed: true)
            return false
        }
        return true
    }

    private func setupNavigation() {
        title = isCreateMode ? "Emer&Fire Controller" : "Edit"
        let closeBarButtonItem = UIBarButtonItem(
            image: UIImage(named: "close")?.withRenderingMode(.alwaysOriginal),
            style: .done,
            target: self,
            action: #selector(backAction)
        )
        let backBarButtonItem = UIBarButtonItem(
            image: UIImage(named: "navigation_back")?.withRenderingMode(.alwaysOriginal),
            style: .done,
            target: self,
            action: #selector(backAction)
        )
        if isCreateMode {
            navigationItem.leftBarButtonItem = nil
            navigationItem.rightBarButtonItem = closeBarButtonItem
        } else {
            navigationItem.leftBarButtonItem = backBarButtonItem
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                title: "save".localizedString,
                color: Bar_Color,
                target: self,
                sel: #selector(saveAction)
            )
            if !state.editable {
                navigationItem.rightBarButtonItem = nil
            }
        }
    }
}

private extension UINavigationController {
    func popToDeviceOthersIfPossible() {
        if let deviceOthersViewController = viewControllers.last(where: { $0 is DeviceOthersViewController }) {
            popToViewController(deviceOthersViewController, animated: true)
        } else {
            popViewController(animated: true)
        }
    }
}
