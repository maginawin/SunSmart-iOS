//
//  PreCreateEmerFireVC.swift
//  SunSmart
//
//  Created by Plato Jobs on 2026/4/20.
//

import UIKit

final class PreCreateEmerFireVC: UIViewController {

    private enum Section: Int, CaseIterable {
        case name
        case reportStatus
        case powerLossEmergency
        case fireAlarmEmergency
    }

    private struct ToggleItem {
        let title: String
        var isOn: Bool
    }

    var editable = true

    private var deviceName = "Emer&Fire Controller 1"
    private var isLinked = true
    private var isSynced = false
    private var toggleItems: [ToggleItem] = [
        .init(title: "Report To Gateway".localizedString, isOn: true),
        .init(title: "Enable Power Loss Emergency".localizedString, isOn: false),
        .init(title: "Enable Fire Alarm Emergency".localizedString, isOn: true)
    ]

    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .grouped)
        tableView.backgroundColor = Background_Color
        tableView.separatorStyle = .none
        tableView.showsVerticalScrollIndicator = false
        tableView.contentInset = UIEdgeInsets(top: SCRYFrom(8), left: 0, bottom: SCRYFrom(20), right: 0)
        tableView.keyboardDismissMode = .onDrag
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(EmerFireNameCell.self)
        tableView.register(EmerFireToggleCell.self)
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
            let controller = LinkedEmerFireEditVC(config: LinkedEmerFireStore.shared.currentConfig)
            let navigationController = NavigationViewController(rootViewController: controller)
            self?.present(navigationController, animated: true)
        }
    }

    private func setupNavigation() {
        title = editable ? "Edit" : "Create"
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

extension PreCreateEmerFireVC: UITableViewDataSource, UITableViewDelegate {

    func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        1
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let section = Section(rawValue: indexPath.section) else {
            return UITableViewCell()
        }

        switch section {
        case .name:
            let cell: EmerFireNameCell = tableView.dequeueReusableCell(for: indexPath)
            cell.configure(name: deviceName, synced: isSynced)
            cell.nameDidChange = { [weak self] name in
                self?.deviceName = name
            }
            cell.syncAction = {
                XWHUDManager.showTipHUD("Devices not synced.", isLineFeed: false)
            }
            return cell

        case .reportStatus, .powerLossEmergency, .fireAlarmEmergency:
            let cell: EmerFireToggleCell = tableView.dequeueReusableCell(for: indexPath)
            let item = toggleItems[indexPath.section - 1]
            let title = item.title
            let isOn = item.isOn
            cell.configure(title: title, isOn: isOn)
            cell.switchValueDidChange = { [weak self] isOn in
                self?.toggleItems[indexPath.section - 1].isOn = isOn
            }
            return cell
        }
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        switch indexPath.section {
        case 0:
            return SCRYFrom(92)
        case 1, 2, 3:
            return SCRYFrom(56)
        default:
            return 0
        }
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        section == 0 ? CGFloat.leastNormalMagnitude : SCRYFrom(8)
    }

    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        CGFloat.leastNormalMagnitude
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let view = UIView()
        view.backgroundColor = .clear
        return view
    }
}
