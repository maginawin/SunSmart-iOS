//
//  MeshFirmwareUpdateViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/11/6.
//

import UIKit
import NordicSigMeshSDK

class MeshFirmwareUpdateViewController: UIViewController {
    
    private var stateTimer: Timer?
    
    private var tableView: UITableView!
    private var operationBtn: UIButton!
    
    private var updateDatas: [UpdateData] = []
    
    var distributorData: MeshDistributionData
    /// 是否连续性查看分发状态（开始分发进入=>查看状态）
    private var isInitial: Bool
    
    /// 分发状态更新回调
    var distributorDataUpdateCallback: ((MeshDistributionData?)->Void)?
    
    
    init(distributorData: MeshDistributionData, initial: Bool = false) {
        self.distributorData = distributorData
        self.isInitial = initial
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        title = "firmware_update".localizedString
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "ok".localizedString, color: TextBlack_Color, target: self, sel: #selector(rightItemAction))
        view.backgroundColor = Background_Color
        
        
        setupData()
        
        setupUI()
        updateUI()
        
        startStateTimer()
    }
    
    private func setupData() {
        
        let targetNodes = distributorData.targetNodes
        let distributeStepData =  UpdateData(step: .distributeFirmware(progress: 0), logs: [])
        let installStepData = UpdateData(step: .installFirmware(completeCount: 0, totalCount: targetNodes.count), logs: [])
        
        switch distributorData.distributionState {
        case .none:
            break
        case .await:
            distributeStepData.logs = [.notExecuted]
            installStepData.logs = [.notExecuted]
            
        case .updating(let updatePhase):
  
            switch updatePhase {
            case .verifying:
                distributeStepData.step = .distributeFirmware(progress: 0)
                distributeStepData.logs = [.notExecuted]
                
                installStepData.logs = [.notExecuted]
                
            case .blob(let progress, let estimateSec):
                distributeStepData.step = .distributeFirmware(progress: progress)
                if isInitial {
                    distributeStepData.logs = [.checkFirmware, .someDevicesNotFirmware]
                }else {
                    distributeStepData.logs = [.omit]
                }
                // 剩余分钟
                let minute = Int(ceil(Double(estimateSec) / 60.0))
                distributeStepData.logs.append(.transferBlob(distributionName: distributorData.distributionNode?.name ?? "", version: distributorData.distributionNode?.distributionVersion ?? "", estimateTime: "\(minute) \("minutes".localizedString)"))
                
            case .apply(let successNodes):
                distributeStepData.step = .distributeFirmware(progress: 100)
                distributeStepData.logs = [.omit, .transferBlobComplete]
                
                installStepData.step = .installFirmware(completeCount: successNodes.count, totalCount: targetNodes.count)
                installStepData.logs = [.installFirmware]
            }
            updateDatas = [distributeStepData, installStepData]
        case .waitingInstall(let currentDistributionNode):
            distributeStepData.step = .distributeFirmware(progress: 100)
            distributeStepData.logs = [.omit, .transferBlobComplete]
            
            installStepData.step = .installFirmware(completeCount: 0, totalCount: targetNodes.count)
//            installStepData.logs = [.installFirmware]
            // 等待后续分发者升级
            if currentDistributionNode != nil {
                installStepData.logs = [.checkDistributionQueued, .waitInstall]
            }else { // 无分发者
                installStepData.logs = [.checkDistributionQueued, .waitInstall, .manuallyInstall]
            }
        case .complete:
            distributeStepData.step = .distributeFirmware(progress: 100)
            distributeStepData.logs = [.transferBlobComplete]
            
            installStepData.step = .installFirmware(completeCount: targetNodes.count, totalCount: targetNodes.count)
            installStepData.logs = [.installFirmwareComplete]
        case .failure(let updatePhase, let failedNodes):
            
            switch updatePhase {
            case .verifying:
                break
            case .blob(let progress, let estimateSec):
                
                // 剩余分钟
                let minute = Int(ceil(Double(estimateSec) / 60.0))
                
                distributeStepData.step = .distributeFirmware(progress: progress)
                distributeStepData.logs = [.omit, .transferBlob(distributionName: distributorData.distributionNode?.name ?? "", version: distributorData.distributionNode?.distributionVersion ?? "", estimateTime: "\(minute) \("minutes".localizedString)"), .transferBlobFailed]
                
                installStepData.logs = [.notExecuted]
            case .apply(let successNodes):
                distributeStepData.step = .distributeFirmware(progress: 100)
                distributeStepData.logs = [.transferBlobComplete]
                
                installStepData.step = .installFirmware(completeCount: successNodes.count, totalCount: targetNodes.count)
                installStepData.logs = [.omit, .installFirmware, .installFirmwareFailed(failedNodes: failedNodes)]
            }
        }
        updateDatas = [distributeStepData, installStepData]
    }
    
    /// 更新日志数据
    private func updateData() {
        
        guard updateDatas.count == 2 else {
            setupData()
            tableView.reloadData()
            return
        }
        
        let targetNodes = distributorData.targetNodes
        let distributeStepData = updateDatas[0]
        let installStepData = updateDatas[1]
        
        switch distributorData.distributionState {
        case .none:
            break
        case .await:
            distributeStepData.logs = [.waitTransfer]
            installStepData.logs = [.notExecuted]
            
        case .updating(let updatePhase):
  
            switch updatePhase {
            case .verifying:
                distributeStepData.step = .distributeFirmware(progress: 0)
                if distributeStepData.logs.isEmpty {
                    distributeStepData.logs = [.notExecuted]
                }
                if distributeStepData.logs.isEmpty {
                    installStepData.logs = [.notExecuted]
                }
                
            case .blob(let progress, let estimateSec):
                distributeStepData.step = .distributeFirmware(progress: progress)
                // 剩余分钟
                let minute = Int(ceil(Double(estimateSec) / 60.0))
                let blobTransferLog: UpdateLog = .transferBlob(distributionName: distributorData.distributionNode?.name ?? "", version: distributorData.distributionNode?.distributionVersion ?? "", estimateTime: "\(minute) \("minutes".localizedString)")
                
                if let index = distributeStepData.logs.lastIndex(where: { $0.rawValue == UpdateLog.transferBlob(distributionName: "", version: "", estimateTime: "").rawValue }) {
                    distributeStepData.logs.replaceSubrange(index...index, with: [blobTransferLog])
                }else {
                    distributeStepData.logs.append(blobTransferLog)
                }
                
                installStepData.logs = [.notExecuted]
                
            case .apply(let successNodes):
                distributeStepData.step = .distributeFirmware(progress: 100)
                if !distributeStepData.logs.contains(where: { $0.rawValue == UpdateLog.transferBlobComplete.rawValue }) {
                    distributeStepData.logs.append(.transferBlobComplete)
                }
                
                installStepData.step = .installFirmware(completeCount: successNodes.count, totalCount: targetNodes.count)
                if !installStepData.logs.contains(where: { $0.rawValue == UpdateLog.installFirmware.rawValue }) {
                    installStepData.logs.append(.installFirmware)
                }
            }
        case .waitingInstall(let currentDistributionNode):
            // 等待后续分发者升级
            
            distributeStepData.step = .distributeFirmware(progress: 100)
            if !distributeStepData.logs.contains(where: { $0.rawValue == UpdateLog.transferBlobComplete.rawValue }) {
                distributeStepData.logs.append(.transferBlobComplete)
            }
            
            installStepData.step = .installFirmware(completeCount: 0, totalCount: targetNodes.count)

            if !installStepData.logs.contains(where: { $0.rawValue == UpdateLog.checkDistributionQueued.rawValue }) {
                installStepData.logs.append(contentsOf: [.checkDistributionQueued, .waitInstall])
            }
            
            // 无分发者
            if currentDistributionNode == nil {
                if !installStepData.logs.contains(where: { $0.rawValue == UpdateLog.manuallyInstall.rawValue }) {
                    installStepData.logs.append(.manuallyInstall)
                }
            }
        case .complete:
            distributeStepData.step = .distributeFirmware(progress: 100)
            if !distributeStepData.logs.contains(where: { $0.rawValue == UpdateLog.transferBlobComplete.rawValue }) {
                distributeStepData.logs.append(.transferBlobComplete)
            }
            
            installStepData.step = .installFirmware(completeCount: targetNodes.count, totalCount: targetNodes.count)
            installStepData.logs.append(.installFirmwareComplete)
        case .failure(let updatePhase, let failedNodes):
            
            switch updatePhase {
            case .verifying:
                break
            case .blob(let progress, let estimateSec):
                distributeStepData.step = .distributeFirmware(progress: progress)
                // 剩余分钟
                let minute = Int(ceil(Double(estimateSec) / 60.0))
                let blobTransferLog: UpdateLog = .transferBlob(distributionName: distributorData.distributionNode?.name ?? "", version: distributorData.distributionNode?.distributionVersion ?? "", estimateTime: "\(minute) \("minutes".localizedString)")
                if let index = distributeStepData.logs.lastIndex(where: { $0.rawValue == UpdateLog.transferBlob(distributionName: "", version: "", estimateTime: "").rawValue }) {
                    distributeStepData.logs.replaceSubrange(index...index, with: [blobTransferLog])
                }else {
                    distributeStepData.logs.append(blobTransferLog)
                }
                distributeStepData.logs.append(.transferBlobFailed)
                
                installStepData.logs = [.notExecuted]
            case .apply(let successNodes):
                distributeStepData.step = .distributeFirmware(progress: 100)
                if !distributeStepData.logs.contains(where: { $0.rawValue == UpdateLog.transferBlobComplete.rawValue }) {
                    distributeStepData.logs.append(.transferBlobComplete)
                }
                
                installStepData.step = .installFirmware(completeCount: successNodes.count, totalCount: targetNodes.count)
                if !installStepData.logs.contains(where: { $0.rawValue == UpdateLog.installFirmware.rawValue }) {
                    installStepData.logs.append(.installFirmware)
                }
                installStepData.logs.append(.installFirmwareFailed(failedNodes: failedNodes))
            }
        }
        
        
        
    }
    
    @objc private func rightItemAction() {
        
        switch distributorData.distributionState {
        case .none:
            navigationController?.popViewController(animated: true)
        case .await, .updating, .waitingInstall:
            // 停止分发
            SRAlertView(title: "notification".localizedString, message: "mesh_distributor_stop_message".localizedString, actions: [.cancelAction, SRAlertAction(title: "ok".localizedString, actionHandler: {[weak self] _ in
                self?.stopDistributor()
            })]).show()
           
        case .complete:
            navigationController?.popViewController(animated: true)
        case .failure: // 重试
            startDistributor()
        }
    }
    
    /// 开启状态刷新定时器
    private func startStateTimer() {
        
        stopStateTimer()
        
        stateTimer = LCWeakTimer.scheduledTimer(timeInterval: 30, aTarget: self, selector: #selector(getDistributorState), userInfo: nil, repeats: true)
        RunLoop.current.add(stateTimer!, forMode: .common)
        stateTimer?.fire()
    }
    
    /// 停止状态刷新定时器
    private func stopStateTimer() {
        stateTimer?.invalidate()
        stateTimer = nil
    }
    
    /// 获取分发状态
    @objc private func getDistributorState() {
        guard let distributorNode = distributorData.distributionNode else {
            stopStateTimer()
            return
        }
        guard MeshLibManager.manager.isMeshNetworkConnected else {
            return
        }
        MeshFirmwareDistributionManager.shared.getDistributionState(distributionNode: distributorNode) {[weak self] node, state in
            guard let self = self, let distributorState = state, node.primaryUnicastAddress == distributorNode.primaryUnicastAddress else { return }
            switch distributorState {
            case .complete, .failure: // 完成、失败状态停止刷新状态定时器
                self.stopStateTimer()
            default:
                break
            }
            self.distributorData.distributionState = distributorState
            if let productId = distributorNode.productIdentifier {
                self.distributorData.save(productId: productId)
            }
            self.updateData()
            
            self.distributorDataUpdateCallback?(self.distributorData)
        }
    }
    
    /// 开始分发
    private func startDistributor() {
        guard let distributionNode = distributorData.distributionNode else {
            XWHUDManager.showErrorTipHUD("no_distributor".localizedString)
            return
        }
        if distributorData.targetNodes.count > 0 {
            XWHUDManager.showCustomHUD(withMessage: nil, isWindow: true)
            MeshFirmwareDistributionManager.shared.startDistribution(distributionNode: distributionNode, targetNodes: distributorData.targetNodes) {[weak self] _, state in
                XWHUDManager.hide()
                guard let self = self else { return }
                switch state {
                case .await:
                    self.distributorData.distributionState = .await
                    self.updateUI()
                    self.startStateTimer()
                    self.distributorDataUpdateCallback?(self.distributorData)
                    self.updateDatas.first?.logs.append(.restartTransfer)
                    self.updateData()
                case .started:
                    self.distributorData.distributionState = .updating(updatePhase: .verifying)
                    self.startStateTimer()
                    self.distributorDataUpdateCallback?(self.distributorData)
                    self.updateDatas.first?.logs.append(.restartTransfer)
                    self.updateData()
                    
                case .failure(let error):
                    XWHUDManager.showErrorTipHUD(error.message)
                default:
                    break
                }
            }
        }
    }
    
    /// 停止分发
    private func stopDistributor() {
        guard let distributionNode = distributorData.distributionNode else {
            XWHUDManager.showErrorTipHUD("no_distributor".localizedString)
            return
        }
        // 是否继续停止分发者，true: 删除本地缓存并发送到设备 false: 仅删除本地缓存保留设备数据
        var isContinue = true
        switch distributorData.distributionState {
        case .updating(let updatePhase):
            if case .apply = updatePhase {
                isContinue = false
            }
        case .waitingInstall:
            isContinue = false
        case .failure(let updatePhase, _):
            if case .apply = updatePhase {
                isContinue = false
            }
        default:
            break
        }
        if !isContinue {
            self.stopStateTimer()
            // 删除缓存
            self.distributorData.delete(productId: distributionNode.productIdentifier!)
            self.distributorDataUpdateCallback?(nil)
            self.navigationController?.popViewController(animated: true)
            return
        }
        
        XWHUDManager.showCustomHUD(withMessage: nil, isWindow: true)
        MeshFirmwareDistributionManager.shared.stopDistribution(distributionNode: distributionNode) {[weak self] result in
            if result {
                Task {
                    // 获取取消后还有没有分发者正在分发
                    let currentDistributionNode = await MeshFirmwareDistributionManager.shared.currentActiveFirmwareDistributionNodeGet()
                    if currentDistributionNode == nil, let spaceVc = SpaceViewController.currentSpaceVc(), spaceVc.space.meshOTADistribution {
                        spaceVc.space.meshOTADistribution = false
                        NotificationCenter.default.post(name: .init(spacePermissionChangedNotificaitonName), object: nil)
                    }
                    XWHUDManager.hide()
                    self?.stopStateTimer()
                    // 删除缓存
                    self?.distributorData.delete(productId: distributionNode.productIdentifier!)
                    self?.distributorDataUpdateCallback?(nil)
                    
                    self?.navigationController?.popViewController(animated: true)
                }
                
            }else {
                XWHUDManager.hide()
                XWHUDManager.showErrorTipHUD("failed".localizedString + "!")
            }
        }
        
    }
    
    /// 开始安装分发固件
    private func startDistributorApply() {
        guard let distributionNode = distributorData.distributionNode else {
            XWHUDManager.showErrorTipHUD("no_distributor".localizedString)
            return
        }
        XWHUDManager.showCustomHUD(withMessage: nil, isWindow: true)
        MeshFirmwareDistributionManager.shared.distributionApply(distributionNode: distributionNode) {[weak self] result in
            XWHUDManager.hide()
            guard let self = self else { return }
            if result {
                self.getDistributorState()
                if self.updateDatas.last?.logs.contains(where: { $0.rawValue == UpdateLog.installFirmware.rawValue }) ?? false {
                    self.updateDatas.last?.logs.append(.reinstallFirmware)
                }
            }else {
                XWHUDManager.showErrorTipHUD("failed".localizedString + "!")
            }
        }
    }
    
    /// 底部操作按钮点击
    @objc private func operationBtnAction() {
        switch distributorData.distributionState {
        case .failure(let updatePhase, _):
            if case .apply = updatePhase { // apply
                Task {
                    XWHUDManager.showCustomHUD(withMessage: nil, isWindow: true)
                    // 还有设备在分发中
                    if let currentDistributionNode = await MeshFirmwareDistributionManager.shared.currentActiveFirmwareDistributionNodeGet() {
                        XWHUDManager.hide()
                        XWHUDManager.showTipHUD("mesh_distributor_apply_wait_message".localizedString, isLineFeed: true)
                        return
                    }
                    XWHUDManager.hide()
                    startDistributorApply()
                }
            }else { // start
                startDistributor()
            }
        case .waitingInstall: // apply
            startDistributorApply()
        default:
            break
        }
    }
    
    private func updateUI() {
        
        switch distributorData.distributionState {
        case .none:
            navigationItem.rightBarButtonItem?.title = "ok".localizedString
            operationBtn.isHidden = true
        case .await:
            navigationItem.rightBarButtonItem?.title = "cancel".localizedString
            operationBtn.isHidden = true
        case .updating:
 
            navigationItem.rightBarButtonItem?.title = "cancel".localizedString
            operationBtn.isHidden = true
        case .complete:
            navigationItem.rightBarButtonItem?.title = "ok".localizedString
            operationBtn.isHidden = true
        case .failure(let updatePhase, _):
            navigationItem.rightBarButtonItem?.title = "RE-START".localizedString
            operationBtn.isHidden = false
            if case .apply = updatePhase {
                operationBtn.setTitle("re_install".localizedString, for: .normal)
            }else {
                operationBtn.setTitle("RE-START".localizedString, for: .normal)
            }
        case .waitingInstall(let currentDistributionNode):
            navigationItem.rightBarButtonItem?.title = "cancel".localizedString
            if currentDistributionNode == nil {
                operationBtn.isHidden = false
                operationBtn.setTitle("install_manually".localizedString, for: .normal)
            }else {
                operationBtn.isHidden = true
            }
        }
        
    }
    
    private func setupUI() {
        
        tableView = UITableView(frame: .zero, style: .grouped)
        tableView.separatorStyle = .none
        tableView.register(MeshFirmwareUpdateLogViewCell.classForCoder(), forCellReuseIdentifier: "cell")
        tableView.register(MeshFirmwareUpdateStepHeaderView.classForCoder(), forHeaderFooterViewReuseIdentifier: "header")
        tableView.estimatedRowHeight = UITableView.automaticDimension
        tableView.backgroundColor = .white
        tableView.layer.cornerRadius = SCRYFrom(10)
        tableView.contentInset = UIEdgeInsets(top: SCRYFrom(24), left: 0, bottom: SCRYFit(30), right: 0)
        tableView.dataSource = self
        tableView.delegate = self
        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(view.safeAreaLayoutGuide).offset(SCRYFrom(7))
            make.bottom.equalTo(-kSafeAreaBottomHeight - SCRYFit(38))
        }
        
        operationBtn = UIButton(title: "", titleSize: 15, titleWeight: .light, titleColor: .white, target: self, action: #selector(operationBtnAction))
        operationBtn.backgroundColor = Bar_Color
        operationBtn.layer.cornerRadius = SCRYFrom(6)
        view.addSubview(operationBtn)
        operationBtn.snp.makeConstraints { make in
            make.centerX.equalToSuperview().offset(SCRXFrom(5.5))
            make.bottom.equalTo(tableView).offset(SCRYFit(-30))
            make.width.equalTo(SCRXFrom(160))
            make.height.equalTo(SCRYFrom(32))
        }
    }

}

extension MeshFirmwareUpdateViewController: UITableViewDataSource, UITableViewDelegate {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return updateDatas.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return updateDatas[section].logs.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! MeshFirmwareUpdateLogViewCell
        let log = updateDatas[indexPath.section].logs[indexPath.row]
        cell.logLabel.attributedText = log.logMessage
        return cell
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let headerView = tableView.dequeueReusableHeaderFooterView(withIdentifier: "header") as! MeshFirmwareUpdateStepHeaderView
        let data = updateDatas[section]
        switch data.step {
        case .distributeFirmware(let progress):
            headerView.titleLabel.text = "distribute_firmware...".localizedString
            headerView.progressLabel.text = "\(progress)%"
        case .installFirmware(let completeCount, let totalCount):
            headerView.titleLabel.text = "install_firmware...".localizedString
            headerView.progressLabel.text = "\(completeCount)/\(totalCount)"
        }

        return headerView
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return SCRYFrom(32)
    }
    
    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        return UIView()
    }
    
    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        return SCRYFrom(20)
    }
}

extension MeshFirmwareUpdateViewController {
    
    /// 固件更新步骤
    enum UpdateStep {
        /// 分发固件 progress: 进度
        case distributeFirmware(progress: UInt8)
        /// 安装固件 completeCount: 成功数量  totalCount: 总数
        case installFirmware(completeCount: Int, totalCount: Int)
    }
    
    /// 更新日志
    enum UpdateLog {
        
        var logMessage: NSAttributedString {
            var message = ""
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = SCRYFrom(3)
            
            switch self {
            case .omit:
                message = "mesh_distributor_log_omit".localizedString
            case .checkFirmware:
                message = "mesh_distributor_log_check_firmware".localizedString
            case .someDevicesNotFirmware:
                message = "mesh_distributor_log_not_firmware".localizedString
            case .transferBlob(let distributionName, let version, let estimateTime):
                
                let message = String(format: "mesh_distributor_log_transfer".localizedString, " \(distributionName)(\(version))", estimateTime)
                let attStr = NSMutableAttributedString(string: message, attributes: [.paragraphStyle: paragraphStyle])
                attStr.addAttribute(.foregroundColor, value: RGB(222, 160, 84), range: (message as NSString).range(of: message.components(separatedBy: "\n").last ?? estimateTime))
                return attStr
                
            case .transferBlobFailed:
                let failedMessage = "> " + "mesh_distributor_blob_failed".localizedString
                let attStr = NSMutableAttributedString(string: failedMessage, attributes: [.paragraphStyle: paragraphStyle])
                attStr.addAttribute(.foregroundColor, value: Red_Color, range: NSRange(location: 1, length: failedMessage.count - 1))
            
                let conductMessage = "mesh_distributor_log_install_failed_conduct".localizedString
                attStr.append(NSAttributedString(string: conductMessage))
                return attStr
                
            case .restartTransfer:
                message = "mesh_distributor_log_restart".localizedString
            case .transferBlobComplete:
                
                let completeMessage = "> " + "mesh_distributor_blob_complete".localizedString
                let attStr = NSMutableAttributedString(string: completeMessage, attributes: [.paragraphStyle: paragraphStyle])
                attStr.addAttribute(.foregroundColor, value: Green_Color, range: NSRange(location: 1, length: completeMessage.count - 1))
                return attStr
            case .waitTransfer:
                message = "mesh_distributor_log_wait_transfer".localizedString
            case .checkDistributionQueued:
                message = "mesh_distributor_log_check_queued".localizedString
            case .waitInstall:
                message = "mesh_distributor_log_wait_distribution".localizedString
            case .installFirmware:
                message = "mesh_distributor_log_install".localizedString
            case .installFirmwareFailed(let failedNodes):
                
                let failedMessage = "mesh_distributor_log_install_failed".localizedString
                let attStr = NSMutableAttributedString(string: failedMessage + "\n", attributes: [.paragraphStyle: paragraphStyle])
                attStr.addAttribute(.foregroundColor, value: Red_Color, range: NSRange(location: 1, length: failedMessage.count - 1))
                
                var targetStr = ""
                failedNodes.forEach({
                    let name = $0.name ?? ""
                    targetStr.append(String(format: "%@%@", targetStr.isEmpty ? "" : ",", name))
                })
                
                let devicesMessage = String(format: "mesh_distributor_log_install_failed_targets".localizedString, targetStr)
                let devicesMessageAtt = NSMutableAttributedString(string: devicesMessage + "\n")
                devicesMessageAtt.addAttribute(.foregroundColor, value: Red_Color, range: NSRange(location: 1, length: devicesMessage.count - 1))
                attStr.append(devicesMessageAtt)
                
                let conductMessage = "mesh_distributor_log_install_failed_conduct".localizedString
                attStr.append(NSAttributedString(string: conductMessage))
                
                return attStr
            case .reinstallFirmware:
                message = "mesh_distributor_log_reinstall".localizedString
            case .installFirmwareComplete:

                let completeMessage = "> " + "mesh_distributor_apply_complete".localizedString
                let attStr = NSMutableAttributedString(string: completeMessage, attributes: [.paragraphStyle: paragraphStyle])
                attStr.addAttribute(.foregroundColor, value: Green_Color, range: NSRange(location: 1, length: completeMessage.count - 1))
                return attStr
                
            case .manuallyInstall:
                message = "mesh_distributor_log_manually_install".localizedString
            case .notExecuted:
                message = "mesh_distributor_log_not_executed".localizedString
            }
            
            let attStr = NSAttributedString(string: message, attributes: [.paragraphStyle: paragraphStyle])
            return attStr
        }
        
        var rawValue: Int {
            switch self {
            case .omit:
                return 0
            case .notExecuted:
                return 1
            case .checkFirmware:
                return 2
            case .someDevicesNotFirmware:
                return 3
            case .transferBlob:
                return 4
            case .transferBlobFailed:
                return 5
            case .restartTransfer:
                return 6
            case .transferBlobComplete:
                return 7
            case .waitTransfer:
                return 8
            case .checkDistributionQueued:
                return 9
            case .waitInstall:
                return 10
            case .installFirmware:
                return 11
            case .installFirmwareFailed:
                return 12
            case .reinstallFirmware:
                return 13
            case .installFirmwareComplete:
                return 14
            case .manuallyInstall:
                return 15
            }
        }
        
        /// 省略（步骤未知）
        case omit
        /// 尚未执行，待续
        case notExecuted
        //*********** Distribute Firmware ************/
        /// 检查固件是否存在
        case checkFirmware
        /// 部分设备没有固件
        case someDevicesNotFirmware
        /// 开始传输 distributionName: 分发者名称  version: 升级版本 estimateTime: 预估时间
        case transferBlob(distributionName: String, version: String, estimateTime: String)
        /// 传输失败
        case transferBlobFailed
        /// 重新传输
        case restartTransfer
        /// 传输完成
        case transferBlobComplete
        /// 等待其它设备分发（未开始分发）
        case waitTransfer
        
        //*********** Install Firmware ************/
        /// 检查到分发队列有别的分发者正在升级
        case checkDistributionQueued
        /// 等待其它设备分发（已分发完成等待安装）
        case waitInstall
        /// 安装固件
        case installFirmware
        /// 安装失败
        case installFirmwareFailed(failedNodes: [Node])
        /// 重新安装
        case reinstallFirmware
        /// 安装完成
        case installFirmwareComplete
        /// 手动安装
        case manuallyInstall
    }
    
    class UpdateData {
        /// 阶段
        var step: UpdateStep
        /// 日志
        var logs: [UpdateLog]
        
        init(step: UpdateStep, logs: [UpdateLog]) {
            self.step = step
            self.logs = logs
        }
    }
    
}
