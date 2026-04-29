//
//  PreCreateEmerFireVC.swift
//  SunSmart
//
//  Created by Plato Jobs on 2026/4/20.
//

// 预创建--应急火警设备编辑
import UIKit

final class PreCreateEmerFireVC: UIViewController {

    private enum Section: Int, CaseIterable {
        case name
        case reportStatus
        case powerLossEmergency
        case fireAlarmEmergency
    }

    private let viewModel: PreCreateEmerFireViewModel

    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .plain)
        tableView.backgroundColor = Background_Color
        tableView.separatorStyle = .none
        tableView.showsVerticalScrollIndicator = false
        tableView.contentInset = UIEdgeInsets(top: SCRYFrom(8), left: 0, bottom: SCRYFrom(20), right: 0)
        tableView.keyboardDismissMode = .onDrag
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(EmerFireNameCell.self)
        tableView.register(EmerFireStatusTextCell.self)
        tableView.register(EmerFireToggleCell.self)
        return tableView
    }()

    private lazy var linkeBt: DeviceBottomActionView = {
        DeviceBottomActionView(frame: .zero)
    }()

    init(space: SpaceData, deviceData: DeviceEmerFireData? = nil) {
        viewModel = PreCreateEmerFireViewModel(space: space, deviceData: deviceData)
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

    @objc private func saveAction() {
        view.endEditing(true)
        viewModel.save()
        backAction()
    }

    @objc private func deleteAction() {
        view.endEditing(true)
        viewModel.delete()
        backAction()
    }

    private func setupUI() {
        view.backgroundColor = Background_Color

        view.addSubview(linkeBt)
        linkeBt.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(DeviceBottomActionView.preferredHeight)
        }
        linkeBt.setCreateMode(!viewModel.isEditMode)
        linkeBt.createAction = { [weak self] in self?.saveAction() }
        linkeBt.saveAction = { [weak self] in self?.saveAction() }
        linkeBt.deleteAction = { [weak self] in self?.deleteAction() }

        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top)
            make.left.right.equalToSuperview()
            make.bottom.equalTo(linkeBt.snp.top).offset(-SCRYFrom(8))
        }
    }

    private func setupNavigation() {
       // title = isEditMode ? "Edit" : "Create"
        title = "Emer&Fire Controller"  //类型名
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(named: "navigation_back")?.withRenderingMode(.alwaysOriginal),
            style: .plain,
            target: self,
            action: #selector(backAction)
        )
        navigationItem.rightBarButtonItem = nil
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
            cell.configure(name: viewModel.deviceName, synced: viewModel.isSynced)
            cell.nameDidChange = { [weak self] name in
                self?.viewModel.deviceName = name
            }
            cell.syncAction = {
                XWHUDManager.showTipHUD("Devices not synced.", isLineFeed: false)
            }
            return cell

        case .reportStatus:
            if viewModel.gateWayData == nil {
                let cell: EmerFireStatusTextCell = tableView.dequeueReusableCell(for: indexPath)
                cell.configure(
                    leftText: "Report To Gateway".localizedString,
                    rightText: "Waiting for setup",
                    rightTextColor: RGB(247, 99, 95)
                )
                return cell
            }

            let cell: EmerFireToggleCell = tableView.dequeueReusableCell(for: indexPath)
            cell.configure(title: "Report To Gateway".localizedString, isOn: viewModel.reportToGateway)
            cell.switchValueDidChange = { [weak self] isOn in
                self?.viewModel.reportToGateway = isOn
            }
            return cell

        case .powerLossEmergency, .fireAlarmEmergency:
            let cell: EmerFireToggleCell = tableView.dequeueReusableCell(for: indexPath)
            let title: String
            let isOn: Bool

            switch section {
            case .powerLossEmergency:
                title = "Enable Power Loss Emergency".localizedString
                isOn = viewModel.enablePowerLossEmergency
            case .fireAlarmEmergency:
                title = "Enable Fire Alarm Emergency".localizedString
                isOn = viewModel.enableFireAlarmEmergency
            default:
                title = ""
                isOn = false
            }

            cell.configure(title: title, isOn: isOn)
            cell.switchValueDidChange = { [weak self] isOn in
                guard let self else { return }
                switch section {
                case .powerLossEmergency:
                    self.viewModel.enablePowerLossEmergency = isOn
                case .fireAlarmEmergency:
                    self.viewModel.enableFireAlarmEmergency = isOn
                default:
                    break
                }
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
