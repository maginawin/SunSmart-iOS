//
//  MeshSelectDistributorViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/10/31.
//

import UIKit
import NordicSigMeshSDK

/// mesh固件升级流程
enum MeshFirmwareUpgradeStep {
    /// 分发
    case distributor
    /// 更新多设备
    case upgradeNodes
}

class MeshSelectDistributorViewController: UIViewController {

    private var tableView: UITableView!
    private var headerView: MeshFirmwareUpgradeHeaderView!
    private var bottomView: UIView!
    private var bottomBtn: UIButton!
    private var nodes: [Node] = []
    /// 分发的固件数据
    let firmwareData: FirmwareData?
    let productId: UInt16
    
    init(productId: UInt16, firmwareData: FirmwareData?) {
        self.productId = productId
        self.firmwareData = firmwareData
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        title = "select_distributor".localizedString
        view.backgroundColor = Background_Color
        
        setupUI()
        
        nodes = MeshNetworkManager.instance.realNodes.filter({ $0.productIdentifier == productId })
    }
    
    @objc private func bottomBtnAction() {
        
        
    }
    
    private func setupUI() {
        
        bottomView = UIView()
        bottomView.backgroundColor = .white
        view.addSubview(bottomView)
        bottomView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(kSafeAreaBottomHeight + SCRYFrom(56))
        }
        
        bottomBtn = UIButton(title: "UPLOAD".localizedString, titleSize: 16, titleWeight: .light, titleColor: Bar_Color, target: self, action: #selector(bottomBtnAction))
        bottomView.addSubview(bottomBtn)
        bottomBtn.snp.makeConstraints { make in
            make.left.right.top.equalToSuperview()
            make.height.equalTo(SCRYFrom(56))
        }
        
        headerView = MeshFirmwareUpgradeHeaderView(frame: CGRect(x: 0, y: 0, width: view.width, height: SCRYFrom(126)))
        headerView.step = .distributor
        headerView.promptCallback = {
            
        }
        
        tableView = UITableView()
        tableView.backgroundColor = Background_Color
        tableView.separatorStyle = .none
        tableView.rowHeight = SCRYFrom(60)
        tableView.register(MeshFirmwareSelectDeviceViewCell.classForCoder(), forCellReuseIdentifier: "cell")
        tableView.register(MeshFirmwareUpgradeSectionView.classForCoder(), forHeaderFooterViewReuseIdentifier: "header")
        tableView.tableHeaderView = headerView
        tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: SCRYFrom(16), right: 0)
        tableView.dataSource = self
        tableView.delegate = self
        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(navigationController?.navigationBar.height ?? 0)
            make.bottom.equalTo(bottomView.snp.top)
        }
    }
    

}

extension MeshSelectDistributorViewController: UITableViewDataSource, UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 10
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! MeshFirmwareSelectDeviceViewCell
//        cell.updateData(device: <#T##Node#>, upgradeStep: <#T##MeshFirmwareUpgradeStep#>, selected: <#T##Bool#>)
        return cell
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let headerView = tableView.dequeueReusableHeaderFooterView(withIdentifier: "header") as! MeshFirmwareUpgradeSectionView
//        Upload 1.2.0 to ID001234563155873849847…
        if firmwareData != nil {
            
        }else {
//            nodes.contains(where: { $0.distributionVersion != nil })
//            distributor_download_firmware_message
        }
        let message = "\("upload".localizedString) 1.2.0 \("to".localizedString) ID001234563155873849847"
        let messageAttStr = NSMutableAttributedString(string: message)
        messageAttStr.addAttributes([.foregroundColor: Message_Color], range: (message as NSString).range(of: "upload".localizedString))
        messageAttStr.addAttributes([.foregroundColor: Message_Color], range: (message as NSString).range(of: "to".localizedString))
        headerView.messageLabel.attributedText = messageAttStr
        return headerView
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return SCRYFrom(71)
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
    }
    
}
