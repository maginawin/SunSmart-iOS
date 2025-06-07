//
//  MeshSelectUpgradeDevicesViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/11/5.
//

import UIKit
import NordicSigMeshSDK

internal extension FirmwareDistributionError {
    var message: String {
        switch self {
        case .noTargets:
            return "No Targets"
        case .deviceNotSupported:
            return "firmware_update_notSupport".localizedString
        case .targetsCheckFailure(let failureNodes):
            return "firmware_update_check_error".localizedString
        case .targetsExceeded(let max):
            return "升级设备超出分发上限"
        case .subscribeTargetsFailure(let failureNodes):
            return "升级设备订阅失败"
        case .distributionReceiversAddFailure:
            return "升级设备关联分发设备失败"
        case .waitFailure:
            return "设置分发排队等待失败"
        case .startFailure:
            return "设置开始分发失败"
        case .stop:
            return "已停止升级"
        case .underway:
            return "正在升级中"
        case .noUpgradeableTargets:
            return "没有可升级设备"
        }
    }
}

class MeshSelectUpgradeDevicesViewController: UIViewController {

    /// 状态
    enum State {
        /// 无
    case normal
        /// 等待
    case waiting
    }
    
    private var tableView: UITableView!
    private var headerView: MeshFirmwareUpgradeHeaderView!
    private var bottomView: UIView!
    private var selectAllBtn: UIButton!
    private var selectAllLabel: UILabel!
    private var selectCountLabel: UILabel!
    private var upgradeBtn: UIButton!
    
    private var nodes: [Node] = []
    private var selectNodes: [Node] = []
    var state: State = .normal
    
    let distributorNode: Node
    /// 分发中
    let distributorData: MeshDistributionData?
    
    init(distributorNode: Node, distributorData: MeshDistributionData?) {
        self.distributorNode = distributorNode
        self.distributorData = distributorData
        if case .await = distributorData?.distributionState {
            state = .waiting
        }
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        title = "select_upgrade_device(s)".localizedString
        view.backgroundColor = Background_Color
        if state == .waiting {
            navigationItem.rightBarButtonItem = UIBarButtonItem(title: "cancel".localizedString, color: RGB(0, 0, 0, 0.85), target: self, sel: #selector(cancelWaiting))
        }
        setupUI()
        
        nodes = MeshNetworkManager.instance.realNodes.filter({ $0.productIdentifier == distributorNode.productIdentifier })
        updateBottomUIState()
    }
    
    /// 开始分发
    private func startDistribution() {
        
        // 分发设备也需要升级时将分发设备放到最后
        if let index = selectNodes.firstIndex(where: { $0.primaryUnicastAddress == distributorNode.primaryUnicastAddress }) {
            selectNodes.remove(at: index)
            selectNodes.append(distributorNode)
        }
        
        XWHUDManager.showCustomHUD(withMessage: nil, isWindow: true)
        MeshFirmwareDistributionManager.shared.startDistribution(distributionNode: self.distributorNode, targetNodes: self.selectNodes) {[weak self] _, state
            in
            guard let self = self else { return }
            switch state {
            case .check:
                print("分发设备检查固件中")
            case .relation:
                print("关联分发设备中")
            case .await, .started, .waitManualInstall:
                XWHUDManager.hide()
                var distributionData = MeshDistributionData(distributionAddress: distributorNode.primaryUnicastAddress, targetAddresses: selectNodes.map({ $0.primaryUnicastAddress }), distributionState: .await)
                
                switch state {
                case .started, .waitManualInstall:
                    if case .waitManualInstall = state {
                        distributionData.distributionState = .waitingInstall(currentDistributionNode: nil)
                    }
                    distributionData.distributionState = .updating(updatePhase: .blob(progress: 0, estimateTime: -1))
                    let vc = MeshFirmwareUpdateViewController(distributorData: distributionData, initial: true)
                    self.navigationController?.pushViewController(vc, animated: true)
//                    self.navigationController?.removeVc(vc: self)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: {
                        if let selectDistributorVc = self.navigationController?.viewControllers.first(where: { $0.isKind(of: MeshSelectDistributorViewController.classForCoder()) }) {
                            self.navigationController?.removeViewControllers(viewControllers: [self, selectDistributorVc])
                        }
                    })
                case .await: // 排队中
                    self.state = .waiting
                    self.updateBottomUIState()
                    self.tableView.reloadData()
                    if let selectDistributorVc = self.navigationController?.viewControllers.first(where: { $0.isKind(of: MeshSelectDistributorViewController.classForCoder()) }) {
                        self.navigationController?.removeVc(vc: selectDistributorVc)
                    }
                default:
                    break
                }
                distributionData.save(productId: distributorNode.productIdentifier!)
                
                NotificationCenter.default.post(name: .init(firmwareListRefreshNotificationName), object: nil)
                
            case .failure(let error):
                XWHUDManager.hide()
                XWHUDManager.showErrorTipHUD(error.message)
            }
        }
        
    }
    
    /// 取消排队
    @objc private func cancelWaiting() {
        
        XWHUDManager.showCustomHUD(withMessage: nil, isWindow: true)
        MeshFirmwareDistributionManager.shared.stopDistribution(distributionNode: distributorNode) {[weak self] result in
            XWHUDManager.hide()
            guard let self = self else { return }
            if result {
                self.distributorData?.delete(productId: self.distributorNode.productIdentifier!)
                self.navigationController?.popViewController(animated: true)
            }else {
                XWHUDManager.showErrorTipHUD("failed".localizedString + "!")
            }
        }
        
    }
    
    @objc private func selectAllBtnAction(sender: UIButton) {
        
        if sender.isSelected {
            selectNodes.removeAll()
            sender.isSelected = false
        }else {
            // 可升级设备
            let upgradableNodes = nodes.filter({ $0.state && ($0.firmwareVersion == nil || distributorNode.distributionVersion?.compare($0.firmwareVersion!, options: .numeric) == .orderedDescending) })

            // 判断是否超出限制
            if let maxSize = distributorNode.maxDistributionReceiversListSize, selectNodes.count >= maxSize {
                XWHUDManager.showTipHUD(String(format: "mesh_distributor_targets_overrun_message".localizedString, maxSize), isLineFeed: true)
                return
            }
            
            selectNodes = upgradableNodes
            sender.isSelected = upgradableNodes.count > 0
        }
        tableView.reloadSections(IndexSet(integer: 0), with: .automatic)
        updateBottomUIState()
    }
    
    @objc private func upgradeBtnAction() {
        
        XWHUDManager.showCustomHUD(withMessage: nil, isWindow: true)
        Task {
            // 判断是否需要排队，获取最后一个分发者，如果有分发者则提示
            if let lastDistributionNode = await MeshFirmwareDistributionManager.shared.lastFirmwareDistributionNodeGet() {
                XWHUDManager.hide()
                SRAlertView(title: "notification".localizedString, message: "mesh_upgrade_waiting_message".localizedString, actions: [.cancelAction, SRAlertAction(title: "ok".localizedString, actionHandler: {[weak self] _ in
                    // 进入排队
                    self?.startDistribution()
                })]).show()
                return
            }
            XWHUDManager.hide()
            // 没有分发者
            self.startDistribution()
        }
        
    }
    
    private func setupUI() {
        
        bottomView = UIView()
        bottomView.backgroundColor = .white
        view.addSubview(bottomView)
        bottomView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo((isIPad ? 0 : kSafeAreaBottomHeight) + SCRYFrom(60))
        }
        
        let lineView = UIView()
        lineView.backgroundColor = Line_Color1
        bottomView.addSubview(lineView)
        lineView.snp.makeConstraints { make in
            make.left.right.top.equalToSuperview()
            make.height.equalTo(0.5)
        }
        
        selectAllBtn = UIButton(normalImageName: "device_select_un", selectedImageName: "device_select", target: self, action: #selector(selectAllBtnAction))
        bottomView.addSubview(selectAllBtn)
        selectAllBtn.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(8))
            make.top.equalTo(SCRYFrom(15))
            make.width.height.equalTo(SCRYFrom(30))
        }
        
        selectAllLabel = UILabel(text: "select_all".localizedString, textColor: TextBlack_Color, fontSize: 15, fontWeight: .light)
        bottomView.addSubview(selectAllLabel)
        selectAllLabel.snp.makeConstraints { make in
            make.left.equalTo(selectAllBtn.snp.right).offset(SCRXFrom(8))
            make.top.equalTo(SCRYFrom(12))
        }
        
        selectCountLabel = UILabel(text: "0/0", textColor: Message_Color, fontSize: 14, fontWeight: .light)
        bottomView.addSubview(selectCountLabel)
        selectCountLabel.snp.makeConstraints { make in
            make.top.equalTo(selectAllLabel.snp.bottom).offset(SCRYFrom(3))
            make.left.equalTo(selectAllLabel)
        }
        
        upgradeBtn = UIButton(title: "mesh_upgrade".localizedString, titleSize: 14, titleWeight: .light, titleColor: .white, target: self, action: #selector(upgradeBtnAction))
        let btnSize = CGSize(width: CGFloat(Int(SCRXFrom(114))), height: CGFloat(Int(SCRYFrom(40))))
        upgradeBtn.setBackgroundImage(UIImage.image(size: btnSize, color: Bar_Color.withAlphaComponent(0.5)), for: .disabled)
        upgradeBtn.setBackgroundImage(UIImage.image(size: btnSize, color: Bar_Color), for: .normal)
        upgradeBtn.isEnabled = false
        upgradeBtn.layer.cornerRadius = btnSize.height * 0.5
        upgradeBtn.layer.masksToBounds = true
        bottomView.addSubview(upgradeBtn)
        upgradeBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.centerY.equalTo(selectAllBtn)
            make.width.equalTo(btnSize.width)
            make.height.equalTo(btnSize.height)
        }
        
        headerView = MeshFirmwareUpgradeHeaderView(frame: CGRect(x: 0, y: 0, width: view.width, height: SCRYFrom(126)))
        headerView.step = .upgradeNodes
        headerView.promptCallback = {
            MeshFirmwareUpgradeGuideView(title: "how_to_mesh_upgrade".localizedString, message: "mesh_upgrade_prompt_message".localizedString, steps: [.selectDistributor, .selectDevices, .waiting], contentHeight: SCREEN_HEIGHT * 0.821).show()
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
            make.top.equalTo(view.safeAreaLayoutGuide)
            make.bottom.equalTo(bottomView.snp.top)
        }
    }
    
    private func updateBottomUIState() {
        
        /// 可升级的设备
        let upgradableNodes = nodes.filter({ $0.state && ($0.firmwareVersion == nil || distributorNode.distributionVersion?.compare($0.firmwareVersion!, options: .numeric) == .orderedDescending) })
        
        selectAllBtn.isSelected = selectNodes.count == upgradableNodes.count
        selectCountLabel.text = "\(selectNodes.count)/\(upgradableNodes.count)"
        
        if state == .normal {
            upgradeBtn.isEnabled = selectNodes.count > 0
            upgradeBtn.setTitle("mesh_upgrade".localizedString, for: .normal)
            upgradeBtn.imageView?.layer.removeAnimation(forKey: "waiting")
            upgradeBtn.setImage(nil, for: .normal)
            selectAllBtn.isEnabled = true
        }else {
            upgradeBtn.isEnabled = false
            upgradeBtn.setImage(UIImage(named: "loading_small_white"), for: .normal)
            upgradeBtn.imageView?.layer.addRotationAnimation(duration: 1.2, repeatCount: .max, animationKey: "waiting")
            upgradeBtn.setTitle("waiting".localizedString, for: .normal)
            selectAllBtn.isEnabled = false
        }
        
    }

}

extension MeshSelectUpgradeDevicesViewController: UITableViewDataSource, UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return nodes.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! MeshFirmwareSelectDeviceViewCell
        let node = nodes[indexPath.row]
        var upgradable = true
        if let version = node.firmwareVersion, distributorNode.distributionVersion?.compare(version, options: .numeric) != .orderedDescending {
            upgradable = false
        }
        cell.updateData(device: node, upgradeStep: .upgradeNodes, showSelect: node.state && state == .normal && upgradable, selected: selectNodes.contains(where: { $0.primaryUnicastAddress == node.primaryUnicastAddress }), enabled: state == .normal, isDistributor: node.primaryUnicastAddress == distributorNode.primaryUnicastAddress)
        return cell
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let headerView = tableView.dequeueReusableHeaderFooterView(withIdentifier: "header") as! MeshFirmwareUpgradeSectionView
//        Upload 1.2.0 to ID001234563155873849847…
        if state == .waiting || selectNodes.isEmpty {
            headerView.messageView.isHidden = true
        }else {
            headerView.messageView.isHidden = false
            let message = "\("Upgrade".localizedString) \(distributorNode.distributionVersion ?? "--") \("to".localizedString) \("selected_device(s)".localizedString)"
            let messageAttStr = NSMutableAttributedString(string: message)
            messageAttStr.addAttributes([.foregroundColor: Message_Color], range: (message as NSString).range(of: "Upgrade".localizedString))
            messageAttStr.addAttributes([.foregroundColor: Message_Color], range: (message as NSString).range(of: "to".localizedString))
            headerView.messageLabel.attributedText = messageAttStr
        }
        return headerView
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        if state == .waiting || selectNodes.isEmpty {
            return SCRYFrom(31)
        }
        return SCRYFrom(71)
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let node = nodes[indexPath.row]
        guard state == .normal, node.state else {
            return
        }
        
        if selectNodes.contains(node) {
            selectNodes.removeAll(where: { $0.primaryUnicastAddress == node.primaryUnicastAddress })
            if selectNodes.isEmpty {
                tableView.reloadSections(IndexSet(integer: indexPath.section), with: .none)
            }else {
                tableView.reloadRows(at: [indexPath], with: .none)
            }
        }else {
            // 设备版本大于或等于分发版本
            if let version = node.firmwareVersion, distributorNode.distributionVersion?.compare(version, options: .numeric) != .orderedDescending {
                return
            }
            // 判断是否超出限制
            if let maxSize = distributorNode.maxDistributionReceiversListSize, selectNodes.count >= maxSize {
                XWHUDManager.showTipHUD(String(format: "mesh_distributor_targets_overrun_message".localizedString, maxSize), isLineFeed: true)
                return
            }
            selectNodes.append(node)
            if selectNodes.count == 1 {
                tableView.reloadSections(IndexSet(integer: indexPath.section), with: .none)
            }else {
                tableView.reloadRows(at: [indexPath], with: .none)
            }
        }
        updateBottomUIState()
        
    }
    
}
