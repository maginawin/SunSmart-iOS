//
//  DaliSettingViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2025/2/27.
//

import UIKit
import NordicSigMeshSDK

/// dali扫描设备错误
enum ScanDaliDevicesWarn {
    
    var title: String {
        switch self {
        case .unaddressedGearPresent:
            return "unaddressed_gear_present".localizedString
        case .addressConflictsDetected:
            return "address_conflicts_detected".localizedString
        }
    }
    
    /// 有设备未分配地址
    case unaddressedGearPresent
    /// 有设备地址重复
    case addressConflictsDetected
}

class DaliSettingViewController: UIViewController {
     
    private var options: [Options] = [.replaceTheMaster, .daliConfiguration, .scanDaliDevices]
    private var warns: [ScanDaliDevicesWarn] = []
    private var daliDevices: [AnyObject] = []
    private var tableView: UITableView!
    private weak var scanAddressContentLabel: UILabel?
    private lazy var loadingImageView: UIImageView = {
        let imageView = UIImageView(image: UIImage(named: "loading"))
        imageView.isHidden = true
        return imageView
    }()
    
    /// 扫描dali设备完成
    private var scanDevicesOK: Bool = false
    
    
    let node: Node
    
    init(node: Node) {
        self.node = node
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        title = "dali_setting".localizedString
        view.backgroundColor = Background_Color
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: loadingImageView)
        setupTableView()
    }
    

    private func setupTableView() {
        
        tableView = UITableView(frame: .zero, style: .grouped)
        tableView.separatorStyle = .none
        tableView.backgroundColor = Background_Color
        tableView.register(CustomTableViewCell.classForCoder(), forCellReuseIdentifier: "cell")
        tableView.register(DaliSettingDeviceWarnViewCell.classForCoder(), forCellReuseIdentifier: "warnCell")
//        tableView.register(DaliSettingDeviceWarnHeaderView.classForCoder(), forHeaderFooterViewReuseIdentifier: "header")
        tableView.showsVerticalScrollIndicator = false
        tableView.rowHeight = SCRYFrom(44)
        tableView.dataSource = self
        tableView.delegate = self
        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(view.safeAreaInsets.top)
            make.bottom.equalToSuperview()
        }
    }
    
    /// 替换dali主机
    private func replaceTheMaster() {
        DaliReplaceMasterSelectView(selectMaster: node, nodes: MeshNetworkManager.instance.realNodes) {[weak self] selectMaster in
            guard let self = self, self.node != selectMaster else { return }
            print("替换dali主机")
            
        }.show()
    }
    /// dali配置
    private func daliConfiguration() {
        
        let actions: [SRAlertAction] = [
            SRAlertAction(title: "identify_address".localizedString, style: .cancel, actionHandler: {[weak self] _ in
                self?.identifyAddress()
            }),
            SRAlertAction(title: "initialize_dali_address".localizedString, style: .cancel, actionHandler: {[weak self] _ in
                self?.initializeOrExtendDaliAddresses()
            }),
            SRAlertAction(title: "fixture_initialization_commands".localizedString, style: .cancel, actionHandler: {[weak self] _ in
                self?.fixtureInitializationCommands()
            }),
            SRAlertAction(title: "reset_dali_devices".localizedString, style: .cancel, actionHandler: {[weak self] _ in
                self?.resetDaliDevices()
            }),
            SRAlertAction(title: "remove_dali_addresses".localizedString, style: .cancel, actionHandler: {[weak self] _ in
                self?.removeDaliAddresses()
            }),
            SRAlertAction(title: "readdress_dali_addresses".localizedString, style: .cancel, actionHandler: {[weak self] _ in
                self?.reAddressDaliDevices()
            }),
            SRAlertAction(title: "clear_dali_details".localizedString, style: .cancel, actionHandler: {[weak self] _ in
                self?.clearDaliDetails()
            }),
            SRAlertAction(title: "scan_dali_devices".localizedString, style: .cancel, actionHandler: {[weak self] _ in
                self?.scanDaliDevices()
            })
        ]
        SRSheetView(actions: actions).show()
    }
    
    // MARK: - Dali
    
    /// 识别dali地址
    private func identifyAddress() {
        
    }
    
    /// 初始化或扩展dali地址
    private func initializeOrExtendDaliAddresses() {
        
    }
    
    /// 重置灯具指令
    private func fixtureInitializationCommands() {
        
        let alertView = SRAlertView(title: "dali_addressing".localizedString, message: "dali_address_scan_message".localizedString, actions: [.cancelAction, SRAlertAction(title: "comfirm".localizedString, actionHandler: { _ in
            
            // 开始搜索dali设备
            
            
        })])
        
        let contentLabel = UILabel(text: "dali_address_scan_ready_message".localizedString, textColor: ImportantText_Color, fontSize: 15, fit: false)
        alertView.contentView.addSubview(contentLabel)
        self.scanAddressContentLabel = contentLabel
        contentLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(alertView.messageLabel.snp.bottom).offset(SCRYFrom(20))
        }
        alertView.hLineView.snp.remakeConstraints { make in
            make.left.right.equalTo(0)
            make.height.equalTo(1)
            make.top.equalTo(contentLabel.snp.bottom).offset(SCRYFrom(22)).priority(.low)
        }
        alertView.show()
    }
    
    /// 重置dali指令
    private func resetDaliDevices() {
        
        
    }
    
    /// 删除dali地址
    private func removeDaliAddresses() {
        
    }
    
    /// 重新分配dali地址
    private func reAddressDaliDevices() {
        
    }
    
    /// 清除dali设备详细信息
    private func clearDaliDetails() {
        
    }
    
    // MARK: - Scan Dali Devices
    /// 搜索dali设备
    private func scanDaliDevices() {
        scanDevicesOK = false
        
        loadingImageView.isHidden = false
        loadingImageView.layer.addRotationAnimation(duration: 1.2, repeatCount: 9999, animationKey: "loading")
    }
    
    /// 停止搜索dali设备
    private func stopScanDaliDevices() {
        scanDevicesOK = false
        loadingImageView.isHidden = true
        loadingImageView.layer.removeAnimation(forKey: "loading")
    }
    
 

}

extension DaliSettingViewController: UITableViewDataSource, UITableViewDelegate {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1 + (daliDevices.count > 0 ? 1 : 0)
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 {
            return options.count
        }
        return warns.count + daliDevices.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        if indexPath.section == 1 && indexPath.row < warns.count {
            let warnType = warns[indexPath.row]
            let warnCell = tableView.dequeueReusableCell(withIdentifier: "warnCell", for: indexPath) as! DaliSettingDeviceWarnViewCell
            warnCell.titleLabel.text = warnType.title
            return warnCell
        }
        
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! CustomTableViewCell
        cell.cellStyle = .arrow
        if indexPath.section == 0 { // Options
            cell.titleLabel.text = options[indexPath.row].title
            cell.titleLabel.font = FONTS(15)
        }else { // Dali
            cell.titleLabel.text = ""
            cell.titleLabel.font = UIFont.systemFont(ofSize: 14, weight: .light)
        }
        cell.contentLabel.font = UIFont.systemFont(ofSize: 14, weight: .light)
        cell.contentLabel.textColor = SubText_Color
        cell.configureCell(isFirst: indexPath.section == 0 && indexPath.row == 0, isLast: indexPath.section == tableView.numberOfSections - 1 && indexPath.row == tableView.numberOfRows(inSection: indexPath.section))
        return cell
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        return UIView()
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 0.01
    }
    
    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        return UIView()
    }
    
    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        return 0.01
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if indexPath.section == 0 {
            switch options[indexPath.row] {
            case .replaceTheMaster:
                
                replaceTheMaster()
            case .daliConfiguration:
                daliConfiguration()
            case .scanDaliDevices:
                scanDaliDevices()
            }
            
        }else {
            
        }
    }
    
}

extension DaliSettingViewController {
    
    enum Options {
        
        var title: String {
            switch self {
            case .replaceTheMaster:
                return "replace_the_master".localizedString
            case .daliConfiguration:
                return "dali_configuration".localizedString
            case .scanDaliDevices:
                return "scan_dali_devices".localizedString
            }
        }
        
        /// 替换dali主机
        case replaceTheMaster
        /// dali配置
        case daliConfiguration
        /// 扫描dali设备
        case scanDaliDevices
    }
    
    
    
}
