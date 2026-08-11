//
//  SiteTimeZoneSelectionViewController.swift
//  SunSmart
//
//  Created by One on 2026/8/11.
//

import UIKit

final class SiteTimeZoneSelectionViewController: UIViewController {

    private let catalog: SiteTimeZoneCatalog
    private let onSelect: (SiteTimeZoneValue) -> Void
    private var sections: [SiteTimeZoneCatalogSection]

    private let searchField = UISearchTextField()
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let emptyLabel = UILabel()

    init(
        catalog: SiteTimeZoneCatalog,
        onSelect: @escaping (SiteTimeZoneValue) -> Void
    ) {
        self.catalog = catalog
        self.sections = catalog.allSections
        self.onSelect = onSelect
        super.init(nibName: nil, bundle: nil)
    }

    convenience init?(onSelect: @escaping (SiteTimeZoneValue) -> Void) {
        guard let catalog = try? SiteTimeZoneCatalog.bundled() else {
            return nil
        }
        self.init(catalog: catalog, onSelect: onSelect)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "site_time_zone_title".localizedString
        view.backgroundColor = Background_Color
        navigationController?.setNavigationBarBackgroundColor(color: Background_Color)
        setupSearchField()
        setupTableView()
        updateEmptyState()
    }

    private func setupSearchField() {
        searchField.placeholder = "site_time_zone_search_placeholder".localizedString
        searchField.font = UIFont.systemFont(ofSize: SCRYFrom(14))
        searchField.textColor = RGB(27, 20, 37)
        searchField.tintColor = Bar_Color
        searchField.borderStyle = .none
        searchField.backgroundColor = .white
        searchField.layer.cornerRadius = SCRYFrom(10)
        searchField.layer.borderWidth = 0.5
        searchField.layer.borderColor = RGB(220, 220, 220).cgColor
        searchField.clearButtonMode = .whileEditing
        searchField.returnKeyType = .search
        searchField.addTarget(self, action: #selector(searchTextDidChange), for: .editingChanged)
        view.addSubview(searchField)
        searchField.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top).offset(SCRYFrom(8))
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.height.equalTo(SCRYFrom(44))
        }
    }

    private func setupTableView() {
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.keyboardDismissMode = .onDrag
        tableView.showsVerticalScrollIndicator = true
        tableView.rowHeight = SCRYFrom(44)
        if #available(iOS 15.0, *) {
            tableView.sectionHeaderTopPadding = 0
        }
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(
            SiteTimeZoneSelectionCell.self,
            forCellReuseIdentifier: SiteTimeZoneSelectionCell.reuseIdentifier
        )
        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.top.equalTo(searchField.snp.bottom).offset(SCRYFrom(8))
            make.left.right.equalTo(searchField)
            make.bottom.equalToSuperview()
        }

        emptyLabel.text = "site_time_zone_empty".localizedString
        emptyLabel.font = UIFont.systemFont(ofSize: SCRYFrom(14), weight: .light)
        emptyLabel.textColor = RGB(148, 163, 184)
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        view.addSubview(emptyLabel)
        emptyLabel.snp.makeConstraints { make in
            make.left.right.equalTo(searchField)
            make.centerY.equalTo(tableView)
        }
    }

    @objc private func searchTextDidChange() {
        sections = catalog.sections(matching: searchField.text ?? "")
        tableView.reloadData()
        updateEmptyState()
    }

    private func updateEmptyState() {
        emptyLabel.isHidden = !sections.isEmpty
        tableView.isHidden = sections.isEmpty
    }
}

extension SiteTimeZoneSelectionViewController: UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int {
        return sections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return sections[section].entries.count
    }

    func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: SiteTimeZoneSelectionCell.reuseIdentifier,
            for: indexPath
        ) as! SiteTimeZoneSelectionCell
        let entries = sections[indexPath.section].entries
        cell.configure(
            entry: entries[indexPath.row],
            isFirst: indexPath.row == 0,
            isLast: indexPath.row == entries.count - 1
        )
        return cell
    }
}

extension SiteTimeZoneSelectionViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let entry = sections[indexPath.section].entries[indexPath.row]
        onSelect(entry.value)
        navigationController?.popViewController(animated: true)
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return SCRYFrom(section == 0 ? 44 : 48)
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let header = UIView()
        header.backgroundColor = Background_Color
        let label = UILabel()
        label.text = sections[section].region
        label.font = UIFont.systemFont(ofSize: SCRYFrom(14), weight: .semibold)
        label.textColor = RGB(27, 20, 37)
        header.addSubview(label)
        label.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(12))
            make.bottom.equalTo(SCRYFrom(-8))
        }
        return header
    }

    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        return .leastNormalMagnitude
    }
}
