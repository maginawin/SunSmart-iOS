//
//  GroupProfilesViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/1/13.
//

import UIKit
import NordicSigMeshSDK

class GroupProfilesViewController: UIViewController {

    private lazy var tableView: UITableView = {
        let navHeight = navigationController?.navigationBar.height ?? kNavigationHeight
        let tableV = UITableView(frame: CGRect(x: 0, y: navHeight, width: self.view.width, height: self.view.height - navHeight))
        tableV.contentInset = UIEdgeInsets(top: SCRYFrom(12), left: 0, bottom: 0, right: 0)
        tableV.rowHeight = SCRYFrom(44)
        tableV.separatorStyle = .none
        tableV.backgroundColor = .clear
        tableV.register(CustomTableViewCell.classForCoder(), forCellReuseIdentifier: "cell")
        tableV.dataSource = self
        tableV.delegate = self
        return tableV
    }()
    
    var profiles: [String] = ["Copy from…", "Occupancy sensing with daylight harvesting", "Vacancy sensing with daylight harvesting", "Occupancy sensing", "Daylight harvesting", "Manual control", "Photocell", "Occupancy sensing with photocell", "Vacancy sensing with photocell"]
    
    let group: Group
    
    init(group: Group) {
        self.group = group
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        title = group.name
        view.backgroundColor = Background_Color
        
        view.addSubview(tableView)
    }
    

}

extension GroupProfilesViewController: UITableViewDataSource, UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return profiles.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! CustomTableViewCell
        cell.cellStyle = .icon
        cell.iconImageView.image = UIImage(named: "device_select_un")
        cell.titleLabel.text = profiles[indexPath.row]
        cell.titleLabel.font = UIFont.systemFont(ofSize: SCRYFrom(14), weight: .light)
        cell.lineView.isHidden = false
        cell.arrowImageView.isHidden = true
        
//        cell.selectionStyle = .none
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        XWHUDManager.showTipHUD("Oops！coming soon.", isLineFeed: false)
    }
    
}
