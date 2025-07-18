//
//  GatewayViewController.swift
//  SunSmart
//
//  Created by yuankehong on 2025/6/17.
//

import UIKit

class GatewayViewController: UIViewController {

    private var tableView: UITableView!
    private var bottomView: DeviceBottomBtnView!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        navigationController?.setNavigationBarBackgroundColor(color: Background_Color)
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(named: "close")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(close))
    }

    @objc private func close() {
        dismiss(animated: true)
    }
    
    private func setupUI() {
        
        bottomView = DeviceBottomBtnView()
        view.addSubview(bottomView)
        bottomView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(kSafeAreaBottomHeight + SCRYFrom(56))
        }
        
        tableView = UITableView(frame: .zero, style: .grouped)
        tableView.separatorStyle = .none
        tableView.register(CustomTableViewCell.classForCoder(), forCellReuseIdentifier: "cell")
        tableView.dataSource = self
        tableView.delegate = self
        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(view.safeAreaLayoutGuide)
            make.bottom.equalTo(bottomView.snp.top)
        }
        
        
    }

}

extension GatewayViewController: UITableViewDataSource, UITableViewDelegate {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return 0
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 0
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        return UITableViewCell()
    }
}

extension GatewayViewController {
 
    /// seciton 组类型
    enum SectionType {
        /// 名称
        case name
        /// 空白
        case empty
        /// 关联spaces
        case associatedSpaces
        /// APN
        case apn
        /// MQTT服务器信息
        case serverInformation
    }
    
    enum CellType {
        case name
        case mac
        case activate
        case space
        case apn
        case serverAddress
        case port
        case clientID
    }
}
