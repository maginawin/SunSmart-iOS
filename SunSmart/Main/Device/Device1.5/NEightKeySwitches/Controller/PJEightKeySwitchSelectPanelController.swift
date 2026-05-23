//
//  PJEightKeySwitchSelectPanelController.swift
//  SunSmart
//
//  Created by Plato Jobs.
//

import UIKit

final class PJEightKeySwitchSelectPanelController: UIViewController {

    var selectPanelTypeCallback: ((PJEightKeySwitchPanelDefinition.PanelType) -> Void)?

    private var viewModel: PJEightKeySwitchSelectPanelViewModel

    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .grouped)
        tableView.backgroundColor = Background_Color
        tableView.separatorStyle = .none
        tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: SCRYFrom(16), right: 0)
        tableView.register(PJEightKeySwitchSelectPanelCell.self, forCellReuseIdentifier: "panel")
        tableView.register(SyncDevicesTitleHeaderView.self, forHeaderFooterViewReuseIdentifier: "header")
        tableView.dataSource = self
        tableView.delegate = self
        return tableView
    }()

    init(selectedPanelType: PJEightKeySwitchPanelDefinition.PanelType) {
        self.viewModel = PJEightKeySwitchSelectPanelViewModel(selectedPanelType: selectedPanelType)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "select_panel".localizedString
        view.backgroundColor = Background_Color

        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        if let selectedIndex = viewModel.panelTypes.firstIndex(of: viewModel.selectedPanelType) {
            DispatchQueue.main.async { [weak self] in
                self?.tableView.scrollToRow(at: IndexPath(row: 0, section: selectedIndex), at: .middle, animated: false)
            }
        }
    }
}

extension PJEightKeySwitchSelectPanelController: UITableViewDataSource, UITableViewDelegate {

    func numberOfSections(in tableView: UITableView) -> Int {
        viewModel.panelTypes.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        1
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "panel", for: indexPath) as! PJEightKeySwitchSelectPanelCell
        let definition = viewModel.definition(at: indexPath.section)
        cell.configure(definition: definition, selected: definition.type == viewModel.selectedPanelType)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let type = viewModel.panelTypes[indexPath.section]
        if type != viewModel.selectedPanelType {
            viewModel.selectedPanelType = type
            tableView.reloadData()
            selectPanelTypeCallback?(type)
        }
        navigationController?.popViewController(animated: true)
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let headerView = tableView.dequeueReusableHeaderFooterView(withIdentifier: "header") as! SyncDevicesTitleHeaderView
        headerView.titleLabel.text = viewModel.panelTypes[section].title
        headerView.titleLabel.font = FONTS(14)
        headerView.titleLabel.textColor = TextBlack_Color
        headerView.titleLeftMargin = SCRXFrom(28)
        headerView.bottomMargin = SCRYFrom(6)
        return headerView
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        section == 0 ? SCRYFrom(33) : SCRYFrom(41)
    }

    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        0.01
    }

    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        UIView()
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        let width = tableView.bounds.width
        let definition = viewModel.definition(at: indexPath.section)
        let cell = PJEightKeySwitchSelectPanelCell(style: .default, reuseIdentifier: nil)
        cell.configure(definition: definition, selected: definition.type == viewModel.selectedPanelType)
        return cell.preferredHeight(for: width)
    }
}
