//
//  EmerFireAlarmInformationVC.swift
//  SunSmart
//
//  Created by Plato Jobs on 2026/4/21.
//

import UIKit

final class EmerFireAlarmInformationVC: UIViewController {

    private enum Section: Int, CaseIterable {
        case device
        case group
    }

    private struct InfoRow {
        let title: String
        let value: String
        let showsCopyButton: Bool
    }

    private let deviceRows: [InfoRow] = [
        .init(title: "Name", value: "EFC 1", showsCopyButton: false),
        .init(title: "MAC", value: "DF:EF:32:DG:HJ56:67:DF", showsCopyButton: true),
        .init(title: "Pid", value: "--", showsCopyButton: false),
        .init(title: "Address", value: "52", showsCopyButton: false),
        .init(title: "Version Identifier", value: "0", showsCopyButton: false),
        .init(title: "Model", value: "SR-BL2421-DryCon924", showsCopyButton: false),
        .init(title: "Device Type", value: "Emergency Controller", showsCopyButton: false),
        .init(title: "Firmware", value: "1.1.2", showsCopyButton: false),
        .init(title: "Single strength", value: "-70dB", showsCopyButton: false)
    ]

    private let groupRows: [InfoRow] = [
        .init(title: "Group", value: "Not yet linked to a group", showsCopyButton: false)
    ]

    private var deviceSectionExpanded = true

    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .grouped)
        tableView.backgroundColor = Background_Color
        tableView.separatorStyle = .none
        tableView.showsVerticalScrollIndicator = false
        if #available(iOS 15.0, *) {
            tableView.sectionHeaderTopPadding = 0
        }
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = SCRYFrom(44)
        tableView.sectionHeaderHeight = SCRYFrom(44)
        tableView.sectionFooterHeight = CGFloat.leastNormalMagnitude
        tableView.contentInsetAdjustmentBehavior = .never
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(EmerFireAlarmInfoRowCell.self)
        tableView.register(EmerFireAlarmInfoSectionHeaderView.self, forHeaderFooterViewReuseIdentifier: "EmerFireAlarmInfoSectionHeaderView")
        return tableView
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

    private func setupUI() {
        view.backgroundColor = Background_Color

        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top)
            make.left.right.bottom.equalToSuperview()
        }
    }

    private func setupNavigation() {
        title = "Information"
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(named: "navigation_back")?.withRenderingMode(.alwaysOriginal),
            style: .plain,
            target: self,
            action: #selector(backAction)
        )
       
    }

    private func rows(for section: Section) -> [InfoRow] {
        switch section {
        case .device:
            return deviceSectionExpanded ? deviceRows : []
        case .group:
            return groupRows
        }
    }

    private func copy(text: String) {
        UIPasteboard.general.string = text
        XWHUDManager.showTipHUD("copy_success".localizedString, isLineFeed: false)
    }
}

extension EmerFireAlarmInformationVC: UITableViewDataSource, UITableViewDelegate {

    func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let section = Section(rawValue: section) else {
            return 0
        }
        return rows(for: section).count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell: EmerFireAlarmInfoRowCell = tableView.dequeueReusableCell(for: indexPath)
        guard let section = Section(rawValue: indexPath.section) else {
            return cell
        }

        let sectionRows = rows(for: section)
        let row = sectionRows[indexPath.row]
        let showsSeparator = indexPath.row < sectionRows.count - 1
        cell.configure(
            title: row.title,
            value: row.value,
            showsCopyButton: row.showsCopyButton,
            showsSeparator: showsSeparator
        ) { [weak self] text in
            self?.copy(text: text)
        }
        return cell
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard
            let section = Section(rawValue: section),
            let header = tableView.dequeueReusableHeaderFooterView(withIdentifier: "EmerFireAlarmInfoSectionHeaderView") as? EmerFireAlarmInfoSectionHeaderView
        else {
            return nil
        }

        switch section {
        case .device:
            header.configure(title: "Device", showsArrow: true, isExpanded: deviceSectionExpanded)
            header.tapHandler = { [weak self] in
                guard let self else {
                    return
                }
                self.deviceSectionExpanded.toggle()
                self.tableView.reloadSections(IndexSet(integer: section.rawValue), with: .automatic)
            }
        case .group:
            header.configure(title: "", showsArrow: false, isExpanded: true)
            header.tapHandler = nil
        }
        return header
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        let section = Section(rawValue: section)
        return (section == .device ? SCRYFrom(44) : 0.01)
      
    }
    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        CGFloat.leastNormalMagnitude
    }
}
