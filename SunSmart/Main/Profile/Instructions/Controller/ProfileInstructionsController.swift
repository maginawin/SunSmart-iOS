//
//  ProfileInstructionsController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/2/27.
//

import UIKit

class ProfileInstructionsController: UIViewController {

    private lazy var tableView: UITableView = {
        let tableV = UITableView(frame: .zero, style: .grouped)
        tableV.separatorStyle = .none
        tableV.backgroundColor = Background_Color
        tableV.contentInset = UIEdgeInsets(top: SCRYFrom(7), left: 0, bottom: SCRYFrom(10), right: 0)
        tableV.register(ProfileInstructionsHeaderView.classForCoder(), forHeaderFooterViewReuseIdentifier: "header")
        tableV.register(ProfileInstructionsViewCell.classForCoder(), forCellReuseIdentifier: "cell")
        tableV.estimatedRowHeight = SCRYFrom(300)
        tableV.dataSource = self
        tableV.delegate = self
        return tableV
    }()
    
    private var profiles: [Profile.ProfileType] = [.occupancy_daylight, .vacancy_daylight, .occupancy, .vacancy, .daylight, .manualControl, .proximityLighting]
    
    /// 是否展开
    private var showProfileMap: [Profile.ProfileType: Bool] = [
        .occupancy_daylight: false,
        .vacancy_daylight: false,
        .occupancy: false,
        .vacancy: false,
        .daylight: false,
        .manualControl: false,
        .proximityLighting: false
    ]
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.isModalInPresentation = true
        title = "profiles_instructions".localizedString
        navigationController?.setNavigationBarBackgroundColor(color: Background_Color)
        
        view.backgroundColor = Background_Color
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(named: "close")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(back))
//        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(named: "close")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(back))
        
        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
//            let navHeight = navigationController?.navigationBar.height ?? kNavigationHeight
            make.top.equalTo(view.safeAreaLayoutGuide)
            make.left.right.bottom.equalToSuperview()
        }
    }
    
    @objc private func back() {
        
        navigationController?.popViewController(animated: true)
    }

}

extension ProfileInstructionsController: UITableViewDataSource, UITableViewDelegate {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return profiles.count
    }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let type = profiles[section]
        return (showProfileMap[type] ?? false) ? 1 : 0
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! ProfileInstructionsViewCell
        cell.type = profiles[indexPath.section]
        return cell
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let headerView = tableView.dequeueReusableHeaderFooterView(withIdentifier: "header") as! ProfileInstructionsHeaderView
        let type = profiles[section]
        headerView.titleLabel.text = type.instruction.name
        headerView.isShow = showProfileMap[type] ?? false
        headerView.viewActionCallback = {[weak self] isShow in
            self?.showProfileMap[type] = isShow
            headerView.isShow = isShow
            tableView.reloadSections(IndexSet(integer: section), with: .automatic)
        }
        return headerView
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return SCRYFrom(44)
    }
    
    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        return UIView()
    }
    
    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        return 0.01
    }
    
}
