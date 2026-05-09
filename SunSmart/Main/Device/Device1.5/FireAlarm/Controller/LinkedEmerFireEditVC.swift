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
    var state: LinkedEmerFireEditState { viewModel.state }
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
        let tableView = UITableView(frame: .zero, style: .grouped)
        tableView.backgroundColor = Background_Color
        tableView.separatorStyle = .none
        tableView.showsVerticalScrollIndicator = false
        tableView.contentInset = UIEdgeInsets(top: SCRYFrom(8), left: 0, bottom: SCRYFrom(20), right: 0)
        tableView.keyboardDismissMode = .onDrag
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = SCRYFrom(84)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(EmerFireNameCell.self)
        tableView.register(EmerFireToggleCell.self)
        tableView.register(EmerFireStatusTextCell.self)
        tableView.register(EmerFireSelectionCell.self)
        tableView.register(EmerFireInfoCell.self)
        tableView.register(EmerFireStepperCell.self)
        return tableView
    }()

    private lazy var bottomView: DeviceBottomBtnView = {
        DeviceBottomBtnView(frame: .zero)
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
        guard viewModel.save() != nil else {
            XWHUDManager.showTipHUD("failed".localizedString, isLineFeed: false)
            return
        }
        NotificationCenter.default.post(name: .init(deviceOthersRefreshNotificationName), object: nil)
        if let savedDevice = viewModel.currentDevice(), let space, savedDevice.bindNode != nil {
            let controller = EmerFireAlarmControllerSyncVC(space: space, data: savedDevice) { [weak self] in
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
        guard let space else {
            XWHUDManager.showTipHUD("failed".localizedString, isLineFeed: false)
            return
        }
        guard viewModel.create(in: space) != nil else {
            XWHUDManager.showTipHUD("failed".localizedString, isLineFeed: false)
            return
        }
        NotificationCenter.default.post(name: .init(deviceOthersRefreshNotificationName), object: nil)
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
        let controller = EmerFireAlarmControllerSyncVC(space: space, data: device)
        navigationController?.pushViewController(controller, animated: true)
    }

    private func finishAfterSuccessfulSaveSync() {
        XWHUDManager.showSuccessTipHUD("done!".localizedString)
        let presentedNavigationController = navigationController
        if presentedNavigationController?.presentingViewController != nil {
            presentedNavigationController?.dismiss(animated: true)
        } else if let navigationController = navigationController ?? presentedNavigationController {
            navigationController.popToDeviceOthersIfPossible()
        } else {
            dismiss(animated: true)
        }
    }

    private func setupUI() {
        view.backgroundColor = Background_Color

        let actionView: UIView
        if isCreateMode {
            bottomView.showCreateUI()
            bottomView.createBtn.addTarget(self, action: #selector(createAction), for: .touchUpInside)
            actionView = bottomView
        } else {
            bottomView.showEditUI()
            bottomView.deleteBtn.addTarget(self, action: #selector(deleteAction), for: .touchUpInside)
            bottomView.saveBtn.addTarget(self, action: #selector(saveAction), for: .touchUpInside)
            actionView = bottomView
        }
        actionView.isHidden = !state.editable
        view.addSubview(actionView)
        actionView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(SCRYFrom(56) + (isIPad ? 0 : kSafeAreaBottomHeight))
        }

        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top)
            make.left.right.equalToSuperview()
            if state.editable {
                make.bottom.equalTo(actionView.snp.top).offset(-SCRYFrom(8))
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
        title = isCreateMode ? "Create" : "Edit"
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(named: "navigation_back")?.withRenderingMode(.alwaysOriginal),
            style: .plain,
            target: self,
            action: #selector(backAction)
        )
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
