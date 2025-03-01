//
//  DaliSettingViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2025/2/27.
//

import UIKit

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
    private lazy var loadingImageView: UIImageView = {
        let imageView = UIImageView(image: UIImage(named: "loading"))
        imageView.isHidden = true
        return imageView
    }()
    
    /// 扫描dali设备完成
    private var scanDevicesOK: Bool = false
    
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
        tableView.register(DaliSettingDeviceWarnHeaderView.classForCoder(), forHeaderFooterViewReuseIdentifier: "header")
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
        
    }
    /// dali配置
    private func daliConfiguration() {
        
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
        return daliDevices.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! CustomTableViewCell
        cell.cellStyle = .arrow
        if indexPath.section == 0 {
            cell.titleLabel.text = options[indexPath.row].title
            cell.titleLabel.font = FONTS(15)
        }else {
            cell.titleLabel.font = UIFont.systemFont(ofSize: 14, weight: .light)
        }
        cell.contentLabel.font = UIFont.systemFont(ofSize: 14, weight: .light)
        cell.contentLabel.textColor = SubText_Color
        cell.configureCell(isFirst: indexPath.section == 0 && indexPath.row == 0, isLast: indexPath.section == tableView.numberOfSections - 1 && indexPath.row == tableView.numberOfRows(inSection: indexPath.section))
        return cell
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let headerView = tableView.dequeueReusableHeaderFooterView(withIdentifier: "header") as! DaliSettingDeviceWarnHeaderView
//        headerView.
        return headerView
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
