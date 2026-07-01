//
//  UserSettingsViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/7/8.
//

import UIKit

class UserSettingsViewController: UIViewController {

    private enum Row: Int, CaseIterable {
        case name
        case lab
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
        tableV.tableHeaderView = headerView
        return tableV
    }()
    
    private lazy var headerView: UIView = {
        let header = UIView(frame: CGRect(x: 0, y: 0, width: self.view.width, height: SCRYFrom(136)))
        header.backgroundColor = .white
        let iconImageView = UIImageView(image: UIImage(named: "user_big"))
        iconImageView.sizeToFit()
        iconImageView.frame = CGRect(x: (header.width - iconImageView.width) * 0.5, y: (header.height - iconImageView.height) * 0.5, width: iconImageView.width, height: iconImageView.height)
        header.addSubview(iconImageView)
        
        let lineView = UIView(frame: CGRect(x: SCRXFrom(16), y: header.height - 1, width: header.width - SCRXFrom(16), height: 1))
        lineView.backgroundColor = Line_Color
        header.addSubview(lineView)
        return header
    }()
    
    
    override func viewDidLoad() {
        super.viewDidLoad()

        title = "user_settings".localizedString
        view.backgroundColor = Background_Color
        
        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide)
            make.left.right.bottom.equalToSuperview()
        }
    }
    
    /// 修改用户名称请求
    private func updateUserInfoReqeust(userName: String) {
        XWHUDManager.showCustomHUD(withMessage: nil, isWindow: true)
        NetworkRequest.shared.request(.userInfoSet(name: userName)) {[weak self] result in
            XWHUDManager.hide()
            guard let self = self else { return }
            switch result {
            case .success(_):
                SRAlertView.hide()
                UserData.currentUserName = userName
                self.tableView.reloadRows(at: [IndexPath(row: 0, section: 0)], with: .none)
            case .failure(let error):
                XWHUDManager.showErrorTipHUD(error.localizedDescription)
            }
        }
        
    }
    

}

extension UserSettingsViewController: UITableViewDataSource, UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return Row.allCases.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! CustomTableViewCell
        cell.cellStyle = .arrow
        cell.titleLabel.font = UIFont.systemFont(ofSize: SCRYFrom(15), weight: .light)
        cell.contentLabel.textColor = SubText_Color
        cell.contentLabel.font = UIFont.systemFont(ofSize: SCRYFrom(14), weight: .light)
        cell.selectionStyle = .none

        switch Row(rawValue: indexPath.row) {
        case .name:
            cell.titleLabel.text = "name".localizedString
            cell.contentLabel.text = UserData.currentUserName
        case .lab:
            cell.titleLabel.text = "lab".localizedString
            cell.contentLabel.text = nil
        case .none:
            cell.titleLabel.text = nil
            cell.contentLabel.text = nil
        }

        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        switch Row(rawValue: indexPath.row) {
        case .name:
            SRAlertView(title: "name".localizedString, messageColor: Red_Color, inputText: UserData.currentUserName, inputFieldStyle: .init(borderColor: RGB(220, 220, 220)), actions: [.cancelAction, SRAlertAction(title: "ok".localizedString, closeAlert: false)]) { text, validRange in
                if !validRange && !text.isEmpty {
                    return "text_length_exceeded".localizedString
                }
                return nil
            } inputDoneBack: { [weak self] name in
                self?.updateUserInfoReqeust(userName: name)
            }.show()
        case .lab:
            navigationController?.pushViewController(LabViewController(), animated: true)
        case .none:
            break
        }

    }
    
}
