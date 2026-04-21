//
//  LinkedEmerFireGroupSelectionVC.swift
//  SunSmart
//
//  Created by Plato Jobs on 2026/4/21.
//

import UIKit

final class LinkedEmerFireGroupSelectionVC: UIViewController {

    private let options: [String]
    private var selectedIndex: Int
    private let selectionHandler: (Int) -> Void

    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .grouped)
        tableView.backgroundColor = Background_Color
        tableView.separatorStyle = .none
        tableView.dataSource = self
        tableView.delegate = self
        return tableView
    }()

    init(options: [String], selectedIndex: Int, selectionHandler: @escaping (Int) -> Void) {
        self.options = options
        self.selectedIndex = selectedIndex
        self.selectionHandler = selectionHandler
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Associate With Group(s)".localizedString
        view.backgroundColor = Background_Color

        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }
}

extension LinkedEmerFireGroupSelectionVC: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        options.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.selectionStyle = .none
        cell.backgroundColor = .white
        cell.textLabel?.text = options[indexPath.row]
        cell.textLabel?.font = FONTS(14)
        cell.textLabel?.textColor = Title_Color
        cell.accessoryType = selectedIndex == indexPath.row ? .checkmark : .none
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        selectedIndex = indexPath.row
        selectionHandler(indexPath.row)
        navigationController?.popViewController(animated: true)
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        CGFloat.leastNormalMagnitude
    }

    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        CGFloat.leastNormalMagnitude
    }
}
