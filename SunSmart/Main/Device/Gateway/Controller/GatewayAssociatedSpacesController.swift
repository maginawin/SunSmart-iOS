//
//  GatewayAssociatedSpacesController.swift
//  SunSmart
//
//  Created by yuankehong on 2025/7/28.
//

import UIKit

class GatewayAssociatedSpacesController: UIViewController {

    private var tableView: UITableView!
    private var bottomView: DeviceAddBottomView!
    private var headerView: UIView!
    private var messageLabel: UILabel!
    private var countLabel: UILabel!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        title = "associated_spaces".localizedString
        
        view.backgroundColor = Background_Color
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(named: "help")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(help))
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        if self.tableView.firstShowFlashScrollIndicators {
            self.tableView.flashScrollIndicatorsIfNeeded()
        }
    }
    
    @objc private func help() {
        
        navigationController?.pushViewController(GatewayAssociatedSpacesInstructionsController(), animated: true)
    }
    
    @objc private func selectAllBtnAction(sender: UIButton) {
        
    }
    
    @objc private func addSelectedBtnAction() {
        
    }
    
    private func setupUI() {
        
        bottomView = DeviceAddBottomView()
        bottomView.selectCountLabel.text = "1/4"
        bottomView.selectAllBtn.addTarget(self, action: #selector(selectAllBtnAction), for: .touchUpInside)
        bottomView.addSelectedBtn.addTarget(self, action: #selector(addSelectedBtnAction), for: .touchUpInside)
        view.addSubview(bottomView)
        bottomView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(SCRYFrom(60) + kSafeAreaBottomHeight)
        }
        
        headerView = UIView(frame: CGRect(x: 0, y: 0, width: view.width - SCRXFrom(32), height: SCRYFrom(43)))
        
        messageLabel = UILabel(text: String(format: "associated_spaces_message", 16, 200), textColor: SubText_Color, fontSize: 14, fontWeight: .light)
        headerView.addSubview(messageLabel)
        messageLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(4))
            make.right.equalTo(SCRXFrom(-80))
            make.centerY.equalToSuperview()
        }
        
        countLabel = UILabel(text: "154/200", textColor: SubText_Color, fontSize: 14, fontWeight: .light)
        let countAttStr = NSMutableAttributedString(string: "154/200")
        countAttStr.addAttribute(.foregroundColor, value: TextBlack_Color, range: (countAttStr.string as NSString).range(of: "154"))
        countLabel.attributedText = countAttStr
        headerView.addSubview(countLabel)
        countLabel.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-4))
            make.centerY.equalTo(messageLabel)
        }
        
        tableView = UITableView()
        tableView.separatorStyle = .none
        tableView.register(CustomTableViewCell.classForCoder(), forCellReuseIdentifier: "cell")
        tableView.rowHeight = SCRYFrom(44)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.tableHeaderView = headerView
        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(view.safeAreaLayoutGuide)
            make.bottom.equalTo(bottomView.snp.top)
        }
    }
    

}

extension GatewayAssociatedSpacesController: UITableViewDataSource, UITableViewDelegate {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return 4
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! CustomTableViewCell
        cell.cellStyle = .icon
        cell.titleLabel.text = "Space \(indexPath.row + 1)"
        cell.titleLabel.font = UIFont.systemFont(ofSize: SCRYFrom(14), weight: .light)
        cell.iconX = SCRXFrom(10)
        cell.titleX = SCRXFrom(48)
        cell.contentLabel.text = "Nodes: 64"
        cell.contentLabel.snp.updateConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
        }
        cell.configureCell(isFirst: true, isLast: true)
        return cell
    }
    
}
