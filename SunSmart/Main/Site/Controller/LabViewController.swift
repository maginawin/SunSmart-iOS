//
//  LabViewController.swift
//  SunSmart
//

import UIKit

final class LabViewController: UIViewController {

    private enum Row: Int, CaseIterable {
        case displayLightAckDetails
        case overrideOutgoingMeshTTL
        case outgoingMeshTTL

        static var visibleRows: [Row] {
            var rows: [Row] = [.displayLightAckDetails, .overrideOutgoingMeshTTL]
            if LabSettings.overrideOutgoingMeshTTL {
                rows.append(.outgoingMeshTTL)
            }
            return rows
        }
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
        return Row.visibleRows.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! CustomTableViewCell
        cell.titleLabel.font = UIFont.systemFont(ofSize: SCRYFrom(15), weight: .light)
        cell.titleLabel.textColor = TextBlack_Color
        cell.contentLabel.font = UIFont.systemFont(ofSize: SCRYFrom(13), weight: .light)
        cell.contentLabel.textColor = SubText_Color
        cell.switchActionCallback = nil
        cell.selectionStyle = .none

        let rows = Row.visibleRows
        guard rows.indices.contains(indexPath.row) else {
            return cell
        }
        let row = rows[indexPath.row]

        switch row {
        case .displayLightAckDetails:
            cell.cellStyle = .switch
            cell.titleLabel.text = "display_light_ack_details".localizedString
            cell.contentLabel.text = nil
            cell.enabledSwitch.isOn = LabSettings.displayLightAckDetails
            cell.switchActionCallback = { [weak cell] enabled in
                LabSettings.displayLightAckDetails = enabled
                cell?.enabledSwitch.isOn = enabled
            }

        case .overrideOutgoingMeshTTL:
            cell.cellStyle = .switch
            cell.titleLabel.text = "override_outgoing_mesh_ttl".localizedString
            cell.contentLabel.text = nil
            cell.enabledSwitch.isOn = LabSettings.overrideOutgoingMeshTTL
            cell.switchActionCallback = { [weak self, weak cell] enabled in
                LabSettings.overrideOutgoingMeshTTL = enabled
                cell?.enabledSwitch.isOn = enabled
                self?.tableView.reloadData()
            }

        case .outgoingMeshTTL:
            cell.cellStyle = .arrow
            cell.titleLabel.text = "outgoing_mesh_ttl".localizedString
            cell.contentLabel.text = "\(LabSettings.outgoingMeshTTL)"
            cell.selectionStyle = .default

        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let rows = Row.visibleRows
        guard rows.indices.contains(indexPath.row),
              rows[indexPath.row] == .outgoingMeshTTL else {
            return
        }
        showOutgoingMeshTTLInput()
    }

    private func showOutgoingMeshTTLInput() {
        let alert = UIAlertController(
            title: "outgoing_mesh_ttl".localizedString,
            message: "outgoing_mesh_ttl_range".localizedString + "\n\n" + "outgoing_mesh_ttl_scope".localizedString,
            preferredStyle: .alert
        )
        alert.addTextField { textField in
            textField.keyboardType = .numberPad
            textField.textAlignment = .center
            textField.text = "\(LabSettings.outgoingMeshTTL)"
        }
        alert.addAction(UIAlertAction(title: "cancel".localizedString, style: .cancel))
        alert.addAction(UIAlertAction(title: "done".localizedString, style: .default) { [weak self, weak alert] _ in
            guard let text = alert?.textFields?.first?.text,
                  let rawValue = Int(text) else {
                XWHUDManager.showTipHUD("illegal_input".localizedString, isLineFeed: true)
                return
            }
            let value = UInt8(min(max(rawValue, 0), 127))
            LabSettings.outgoingMeshTTL = value
            self?.tableView.reloadData()
        })
        present(alert, animated: true)
    }
}
