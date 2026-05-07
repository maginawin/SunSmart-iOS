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
    private let isLinkedToRealDevice: Bool
    private let space: SpaceData?
    var state: LinkedEmerFireEditState { viewModel.state }
    var editable: Bool {
        get { state.editable }
        set { state.editable = newValue }
    }

    init(config: LinkedEmerFireConfig? = nil, isLinkedToRealDevice: Bool = false, space: SpaceData? = nil) {
        self.isLinkedToRealDevice = isLinkedToRealDevice
        self.space = space
        viewModel = LinkedEmerFireEditViewModel(config: config)
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

    private lazy var linkeBt: PJLinkedStaOpertionsView = {
        PJLinkedStaOpertionsView(frame: .zero)
    }()

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

    @objc private func saveAction() {
        view.endEditing(true)
        viewModel.save()
        XWHUDManager.showTipHUD("save".localizedString)
    }

    private func setupUI() {
        view.backgroundColor = Background_Color

        view.addSubview(linkeBt)
        linkeBt.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(SCRYFrom(56) + kSafeAreaBottomHeight)
        }
        linkeBt.configure(isLinked: isLinkedToRealDevice)

        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top)
            make.left.right.equalToSuperview()
            make.bottom.equalTo(linkeBt.snp.top).offset(-SCRYFrom(8))
        }
        linkeBt.createAction = { [weak self] in
            self?.handleBottomAction()
        }
    }

    private func handleBottomAction() {
        if isLinkedToRealDevice {
            let controller = EmerFireAlarmMonitorVC(space: space, config: state.makeConfig())
            let navigationController = NavigationViewController(rootViewController: controller)
            present(navigationController, animated: true)
            return
        }

        guard let space else {
            XWHUDManager.showTipHUD("failed".localizedString, isLineFeed: false)
            return
        }

        let context = PJDevicesAddEntryContext(
            source: .fireAlarm,
            space: space,
            title: "add_device".localizedString,
            appointGroup: nil,
            forceBindToDongle: nil,
            addBehavior: .init(
                allowsTargetSelection: false,
                allowsCategorySelection: false,
                allowedTypes: [.others],
                blockedDeviceTypes: [.dongle],
                selectionMode: .single,
                forbiddenSelectionTip: "You can't choose other devices.",
                forbiddenDeviceTypeTip: "You can't choose this type of device."
            )
        )
        let controller = PJDevicesAddFlowFactory.make(context: context)
        let navigationController = NavigationViewController(rootViewController: controller)
        present(navigationController, animated: true)
    }

    private func setupNavigation() {
        title = state.editable ? "Edit" : "Create"
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(named: "navigation_back")?.withRenderingMode(.alwaysOriginal),
            style: .plain,
            target: self,
            action: #selector(backAction)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "save".localizedString,
            style: .plain,
            target: self,
            action: #selector(saveAction)
        )
        navigationItem.rightBarButtonItem?.setTitleTextAttributes(
            [
                .font: FONTS(16),
                .foregroundColor: Title_Done_Color
            ],
            for: .normal
        )
    }
}
