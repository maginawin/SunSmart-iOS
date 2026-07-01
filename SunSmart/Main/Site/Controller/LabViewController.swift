//
//  LabViewController.swift
//  SunSmart
//

import UIKit

final class LabViewController: UIViewController {

    private enum Row: Int, CaseIterable {
        case displayLightAckDetails
    }

    private lazy var tableView: UITableView = {
        let tableV = UITableView()
        tableV.rowHeight = SCRYFrom(44)
        tableV.register(CustomTableViewCell.classForCoder(), forCellReuseIdentifier: "cell")
        tableV.contentInset = UIEdgeInsets(top: SCRYFrom(16), left: 0, bottom: 0, right: 0)
        tableV.dataSource = self
        tableV.delegate = self
        tableV.separatorStyle = .none
        tableV.backgroundColor = Background_Color
        return tableV
    }()

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "lab".localizedString
        view.backgroundColor = Background_Color

        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide)
            make.left.right.bottom.equalToSuperview()
        }
    }
}

extension LabViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return Row.allCases.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! CustomTableViewCell
        cell.cellStyle = .switch
        cell.titleLabel.text = "display_light_ack_details".localizedString
        cell.titleLabel.font = UIFont.systemFont(ofSize: SCRYFrom(15), weight: .light)
        cell.contentLabel.text = nil
        cell.enabledSwitch.isOn = LabSettings.displayLightAckDetails
        cell.switchActionCallback = { [weak cell] enabled in
            LabSettings.displayLightAckDetails = enabled
            cell?.enabledSwitch.isOn = enabled
        }
        cell.selectionStyle = .none
        return cell
    }
}
