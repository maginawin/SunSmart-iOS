//
//  MeshFirmwareUpgradeResultsView.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/12/12.
//

import UIKit

class MeshFirmwareUpgradeResultsView: UIView {

    private var shadeView: UIView!
    private var contentView: UIView!
    private var titleLabel: UILabel!
    private var tableView: UITableView!
    private var detailsBtn: UIButton!
    private var okBtn: UIButton!
    /// 按键事件点击回调 true: 查看details false: 关闭
    private var actionCallback: ((Bool)->Void)?
    private var results: [FirmwareUpgradeResult] = []
    
    struct FirmwareUpgradeResult {
        
        enum State {
            /// 安装成功
            case installComplete
            /// 安装失败
            case installFailure
        }
        
        /// 设备类型名称
        let name: String
        /// 设备类型
        let productId: UInt16
        /// 升级状态
        let state: State
    }
    
    init(results: [FirmwareUpgradeResult], actionCallback: ((Bool)->Void)?) {
        super.init(frame: UIScreen.main.bounds)
        
        self.results = results
        self.actionCallback = actionCallback
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func show() {
        if self.superview == nil {
            self.tag = 100
            UIApplication.shared.keyWindow().addSubview(self)
            layoutIfNeeded()
        }
        self.contentView.y = self.height
        self.shadeView.alpha = 0
        UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 1, options: .curveEaseInOut) {
            self.contentView.y = (self.height - self.contentView.height) * 0.5
            self.shadeView.alpha = 1
        }completion: { _ in
            if self.tableView.firstShowFlashScrollIndicators {
                self.tableView.flashScrollIndicatorsIfNeeded()
            }
        }
    }
    
    private func hide() {
        UIView.animate(withDuration: 0.15) {
            self.shadeView.alpha = 0
            self.contentView.layer.addScaleAnimation(fromScale: 1, toScale: 0.7, duration: 0.2)
        } completion: { _ in
            self.removeFromSuperview()
        }
    }
    
    @objc private func detailsBtnAction() {
        actionCallback?(true)
        hide()
    }
    
    @objc private func okBtnAction() {
        actionCallback?(false)
        hide()
    }
    
    private func setupUI() {
        
        shadeView = UIView()
        shadeView.backgroundColor = RGB(0, 0, 0, 0.3)
        addSubview(shadeView)
        shadeView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        contentView = UIView()
        contentView.backgroundColor = RGB(239, 239, 239)
        contentView.layer.cornerRadius = SCRYFrom(20)
        addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.left.equalTo(isIPad ? SCRXFrom(150) : SCRXFrom(36))
            make.right.equalTo(isIPad ? SCRXFrom(-150) : SCRXFrom(-37))
            make.height.lessThanOrEqualTo(SCRYFrom(260))
            make.centerY.equalToSuperview()
        }
        
        titleLabel = UILabel(text: "firmware_upgrade_results".localizedString, textColor: TextBlack_Color, fontSize: 15, fit: false)
        titleLabel.textAlignment = .center
        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(30))
            make.right.equalTo(SCRXFrom(-30))
            make.top.equalTo(SCRYFrom(24))
        }
        
        detailsBtn = UIButton(title: "DETAILS".localizedString, titleSize: 14, titleWeight: .light, titleColor: TextBlack_Color, fit: false, target: self, action: #selector(detailsBtnAction))
        detailsBtn.layer.cornerRadius = SCRYFrom(5)
        detailsBtn.backgroundColor = .white
        contentView.addSubview(detailsBtn)
        detailsBtn.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.right.equalTo(contentView.snp.centerX).offset(SCRXFrom(-7))
            make.bottom.equalTo(SCRYFrom(-24))
            make.height.equalTo(SCRYFrom(32))
        }
        
        okBtn = UIButton(title: "GOT IT".localizedString, titleSize: 14, titleWeight: .light, titleColor: Bar_Color, fit: false, target: self, action: #selector(okBtnAction))
        okBtn.layer.cornerRadius = SCRYFrom(5)
        okBtn.backgroundColor = .white
        contentView.addSubview(okBtn)
        okBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-20))
            make.left.equalTo(contentView.snp.centerX).offset(SCRXFrom(7))
            make.bottom.height.equalTo(detailsBtn)
        }
        
        tableView = UITableView()
        tableView.separatorStyle = .none
        tableView.rowHeight = SCRYFrom(66)
        tableView.backgroundColor = .clear
        tableView.register(MeshFirmwareUpgradeResultsViewCell.classForCoder(), forCellReuseIdentifier: "cell")
        tableView.dataSource = self
        tableView.delegate = self
        contentView.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(12))
            make.bottom.equalTo(detailsBtn.snp.top).offset(SCRYFrom(-12))
            make.height.equalTo(CGFloat(results.count) * tableView.rowHeight)
        }
        
        
        
    }
    
}

extension MeshFirmwareUpgradeResultsView: UITableViewDataSource, UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return results.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! MeshFirmwareUpgradeResultsViewCell
        let result = results[indexPath.row]
        cell.nameLabel.text = result.name
        cell.productIdLabel.text = String(format: "0x%04X", result.productId)
        switch result.state {
        case .installComplete:
            cell.stateLabel.text = "install_firmware_complete".localizedString
            cell.stateLabel.textColor = Green_Color
        case .installFailure:
            cell.stateLabel.text = "install_firmware_failure".localizedString
            cell.stateLabel.textColor = Red_Color
        }
        return cell
    }
    
}

class MeshFirmwareUpgradeResultsViewCell: UITableViewCell {
    
    var nameLabel: UILabel!
    var productIdLabel: UILabel!
    private var versionStateTitleLabel: UILabel!
    var stateLabel: UILabel!
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        backgroundColor = .clear
        selectionStyle = .none
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        
        nameLabel = UILabel(text: "BLE to 0-10V converter ", textColor: TextBlack_Color, fontSize: 14, fontWeight: .light, fit: false)
        contentView.addSubview(nameLabel)
        nameLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(26))
            make.width.lessThanOrEqualTo(SCRXFrom(180))
            make.top.equalTo(SCRYFrom(8))
        }
        
        productIdLabel = UILabel(text: "0xBD01", textColor: TextBlack_Color, fontSize: 12, fontWeight: .light, fit: false)
        contentView.addSubview(productIdLabel)
        productIdLabel.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-26))
            make.centerY.equalTo(nameLabel)
        }
        
        versionStateTitleLabel = UILabel(text: "device_version_state".localizedString, textColor: SubText_Color, fontSize: 14, fontWeight: .light, fit: false)
        contentView.addSubview(versionStateTitleLabel)
        versionStateTitleLabel.snp.makeConstraints { make in
            make.left.equalTo(nameLabel)
            make.top.equalTo(nameLabel.snp.bottom).offset(SCRYFrom(6))
        }
        
        stateLabel = UILabel(text: "", textColor: Red_Color, fontSize: 12, fontWeight: .light, fit: false)
        contentView.addSubview(stateLabel)
        stateLabel.snp.makeConstraints { make in
            make.right.equalTo(productIdLabel)
            make.centerY.equalTo(versionStateTitleLabel)
        }
        
    }
    
}

