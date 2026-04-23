//
//  LinkedEmerFireEditVC.swift
//  SunSmart
//
//  Created by Plato Jobs on 2026/4/20.
//

//应急火警设备编辑页
import UIKit

final class LinkedEmerFireEditVC: UIViewController {

    let state: LinkedEmerFireEditState
    var editable: Bool {
        get { state.editable }
        set { state.editable = newValue }
    }

    init(config: LinkedEmerFireConfig? = nil) {
        if let config {
            state = LinkedEmerFireEditState(config: config)
        } else {
            state = LinkedEmerFireEditState()
        }
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
        LinkedEmerFireStore.shared.save(config: state.makeConfig())
        XWHUDManager.showTipHUD("save".localizedString)
    }

    private func setupUI() {
        view.backgroundColor = Background_Color

        view.addSubview(linkeBt)
        linkeBt.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(SCRYFrom(56) + kSafeAreaBottomHeight)
        }

        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top)
            make.left.right.equalToSuperview()
            make.bottom.equalTo(linkeBt.snp.top).offset(-SCRYFrom(8))
        }
        linkeBt.createAction = { [weak self] in
            
            let controller = EmerFireAlarmMonitorVC()
            let navigationController = NavigationViewController(rootViewController: controller)
            self?.present(navigationController, animated: true)
           
        }
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
