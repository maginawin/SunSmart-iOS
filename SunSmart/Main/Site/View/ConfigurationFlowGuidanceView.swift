//
//  ConfigurationFlowGuidanceView.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/4/15.
//

import UIKit

class ConfigurationFlowGuidanceView: UIView {

    enum Options: Int {
        
        var data: (title: String, message: String?) {
            var title = ""
            var message: String?
            switch self {
            case .createSitesAndSpaces:
                title = "guidance_create_sites"
                message = "done!"
            case .createGroups:
                title = "guidance_create_groups"
                message = "guidance_create_groups_message"
            case .createScenes:
                title = "guidance_create_scenes"
            case .createSwitchs:
                title = "guidance_create_switchs"
            case .createSchedules:
                title = "guidance_create_schedules"
            case .configuration:
                title = "guidance_configuration"
                message = "guidance_configuration_message"
            case .switchBinding:
                title = "guidance_switch_binding"
            case .lightSensorCalibration:
                title = "guidance_sensor_calibration"
            case .fineAdjustment:
                title = "guidance_adjustment"
            case .share:
                title = "guidance_share"
            }
            return (title.localizedString, message?.localizedString)
        }
        
        /// 场景场所/空间
        case createSitesAndSpaces = 1
        /// 创建组
        case createGroups = 2
        /// 创建场景
        case createScenes = 3
        /// 创建日程
        case createSchedules = 4
        /// 创建虚拟开关
        case createSwitchs = 5
        /// 同步配置
        case configuration = 6
        /// 绑定动能开关
        case switchBinding = 7
        /// 传感器校准
        case lightSensorCalibration = 8
        /// 调节
        case fineAdjustment = 9
        /// 分享
        case share = 10
    }
    
    private var shadeView: UIView!
    private var contentView: UIView!
    private var titleView: UIView!
    private var titleLabel: UILabel!
    private var tableView: UITableView!
    private var bottomView: UIView?
    private var cancelBtn: UIButton?
    private var continueBtn: UIButton?
    private var lineView: UIView?
    private var hLineView: UIView?
    
    private var continueCallback: (()->Void)?
    
    private var options: [[Options]] = [[.createSitesAndSpaces, .createGroups, .createScenes, .createSchedules, .createSwitchs], [.configuration, .switchBinding, .lightSensorCalibration, .fineAdjustment, .share]]
    
    init(continueBack: (()->Void)? = nil) {
        super.init(frame: UIScreen.main.bounds)
        self.continueCallback = continueBack
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func show() {
        
        if superview == nil {
            UIApplication.shared.keyWindow().addSubview(self)
            self.layoutIfNeeded()
        }
        shadeView.alpha = 0
        contentView.y = self.height
        UIView.animate(withDuration: 0.3) {
            self.shadeView.alpha = 1
            self.contentView.y = SCRYFrom(36)
        }
        
    }
    
    static func current() -> ConfigurationFlowGuidanceView? {
        return UIApplication.shared.keyWindow().subviews.first(where: { $0.isKind(of: self.classForCoder()) }) as? ConfigurationFlowGuidanceView
    }
    
    @objc func hide() {
        
        UIView.animate(withDuration: 0.3) {
            self.shadeView.alpha = 0
            self.contentView.y = self.height
        } completion: { _ in
            self.removeFromSuperview()
        }
    }
    
    @objc private func cancelBtnAction() {
        hide()
    }
    
    @objc private func continueBtnAction() {
        hide()
        continueCallback?()
    }
    
    private func setupUI() {
        
        shadeView = UIView()
        shadeView.backgroundColor = RGB(0, 0, 0, 0.3)
        addSubview(shadeView)
        shadeView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        contentView = UIView()
        contentView.backgroundColor = .white
        contentView.layer.cornerRadius = 20
        contentView.layer.masksToBounds = true
        addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(8))
            make.right.equalTo(SCRXFrom(-7))
            make.top.equalTo(SCRYFrom(36))
            make.bottom.equalTo(SCRYFrom(-36))
        }
        
        titleView = UIView()
        titleView.backgroundColor = Background_Color
        contentView.addSubview(titleView)
        titleView.snp.makeConstraints { make in
            make.left.right.top.equalToSuperview()
            make.height.equalTo(SCRYFrom(44))
        }
        
        titleLabel = UILabel(text: "configuration_flow_guidance".localizedString, textColor: TextBlack_Color, fontSize: 16)
        titleView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
        
        if continueCallback != nil {
            
            bottomView = UIView()
            bottomView!.backgroundColor = .white
            contentView.addSubview(bottomView!)
            bottomView!.snp.makeConstraints { make in
                make.left.right.bottom.equalToSuperview()
                make.height.equalTo(SCRYFrom(60))
            }
            lineView = UIView()
            lineView!.backgroundColor = RGB(0, 0, 0, 0.03)
            bottomView!.addSubview(lineView!)
            lineView!.snp.makeConstraints { make in
                make.left.right.top.equalToSuperview()
                make.height.equalTo(1)
            }
            
            hLineView = UIView()
            hLineView!.backgroundColor = RGB(0, 0, 0, 0.03)
            bottomView!.addSubview(hLineView!)
            hLineView!.snp.makeConstraints { make in
                make.centerX.top.bottom.equalToSuperview()
                make.width.equalTo(1)
            }
            
            cancelBtn = UIButton(title: "cancel".localizedString, titleSize: 15, titleWeight: .light, titleColor: Title_Color, target: self, action: #selector(cancelBtnAction))
            bottomView!.addSubview(cancelBtn!)
            cancelBtn!.snp.makeConstraints { make in
                make.right.equalTo(hLineView!.snp.left).offset(SCRXFrom(-20))
                make.width.equalTo(SCRXFrom(108))
                make.height.equalTo(SCRYFrom(40))
                make.centerY.equalToSuperview()
            }
            
            continueBtn = UIButton(title: "alert_item_continue".localizedString, titleSize: 15, titleWeight: .light, titleColor: Bar_Color, target: self, action: #selector(continueBtnAction))
            bottomView!.addSubview(continueBtn!)
            continueBtn!.snp.makeConstraints { make in
                make.left.equalTo(hLineView!.snp.right).offset(SCRXFrom(20))
                make.centerY.width.height.equalTo(cancelBtn!)
            }
        }else {
            let closeBtn = UIButton(normalImageName: "close", target: self, action: #selector(hide))
            titleView.addSubview(closeBtn)
            closeBtn.snp.makeConstraints { make in
                make.right.equalTo(SCRXFrom(-12))
                make.centerY.equalTo(titleLabel)
            }
        }
        tableView = UITableView(frame: .zero, style: .grouped)
        tableView.separatorStyle = .none
        tableView.backgroundColor = .white
        tableView.contentInset = UIEdgeInsets(top: SCRYFrom(10), left: 0, bottom: 0, right: 0)
        tableView.showsVerticalScrollIndicator = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(ConfigurationFlowGuidanceTitleView.classForCoder(), forHeaderFooterViewReuseIdentifier: "header")
        tableView.register(ConfigurationFlowGuidanceViewCell.classForCoder(), forCellReuseIdentifier: "cell")
        contentView.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(titleView.snp.bottom)
            if bottomView != nil {
                make.bottom.equalTo(bottomView!.snp.top)
            }else {
                make.bottom.equalToSuperview()
            }
        }
        
        
    }
    
}

extension ConfigurationFlowGuidanceView: UITableViewDataSource, UITableViewDelegate {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return options.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return options[section].count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! ConfigurationFlowGuidanceViewCell
        cell.lineView.isHidden = indexPath.row == tableView.numberOfRows(inSection: indexPath.section) - 1
        let option = options[indexPath.section][indexPath.row]
        cell.titleLabel.text = option.data.title
        cell.messageLabel.text = option.data.message
        cell.stepLabel.text = "\(option.rawValue)"
        return cell
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let headerView = tableView.dequeueReusableHeaderFooterView(withIdentifier: "header") as! ConfigurationFlowGuidanceTitleView
        if section == 0 {
            headerView.titleLabel.text = "guidance_off_site".localizedString
        }else {
            headerView.titleLabel.text = "guidance_on_site".localizedString
        }
        return headerView
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return section == 0 ? SCRYFrom(39) : SCRYFrom(45)
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if indexPath.row == tableView.numberOfRows(inSection: indexPath.section) - 1 {
            return SCRYFrom(27)
        }
        return SCRYFrom(67)
    }
    
    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        return UIView()
    }
    
    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        return 0.01
    }
}

class ConfigurationFlowGuidanceTitleView: UITableViewHeaderFooterView {
    
    var titleLabel: UILabel!
    
    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        
        contentView.backgroundColor = .clear
        
        titleLabel = UILabel(text: nil, textColor: RGB(39, 37, 54), fontSize: 14)
        addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.centerY.equalToSuperview()
            make.right.equalTo(SCRXFrom(-16))
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}

class ConfigurationFlowGuidanceViewCell: UITableViewCell {
    
    var stepLabel: UILabel!
    var titleLabel: UILabel!
    var messageLabel: UILabel!
    var lineView: UIView!
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        
        stepLabel = UILabel(text: "1", textColor: SubText_Color, fontSize: 13)
        stepLabel.backgroundColor = .white
        stepLabel.layer.cornerRadius = 10
        stepLabel.layer.borderColor = SubText_Color.cgColor
        stepLabel.layer.borderWidth = 1
        stepLabel.textAlignment = .center
        contentView.addSubview(stepLabel)
        stepLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.equalTo(1)
            make.width.height.equalTo(20)
        }
        
        titleLabel = UILabel(text: "Create Sites and Spaces", textColor: SubText_Color, fontSize: 14, fontWeight: .light)
        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(stepLabel.snp.right).offset(SCRXFrom(9))
            make.right.equalTo(SCRXFrom(-13))
            make.centerY.equalTo(stepLabel)
        }
        
        lineView = UIView()
        lineView.backgroundColor = RGB(156, 163, 175)
        lineView.layer.cornerRadius = 0.5
        contentView.addSubview(lineView)
        lineView.snp.makeConstraints { make in
            make.centerX.equalTo(stepLabel)
            make.top.equalTo(stepLabel.snp.bottom).offset(SCRYFrom(11))
            make.width.equalTo(1)
            make.height.equalTo(SCRYFrom(24))
//            make.bottom.equalTo(SCRYFrom(-12))
        }
        
        messageLabel = UILabel(text: "Done !", textColor: RGB(156, 163, 175), fontSize: 13, fontWeight: .light, fit: false)
        messageLabel.numberOfLines = 2
        messageLabel.adjustsFontSizeToFitWidth = true
        contentView.addSubview(messageLabel)
        messageLabel.snp.makeConstraints { make in
            make.left.equalTo(titleLabel)
            make.centerY.equalTo(lineView)
            make.right.equalTo(SCRXFrom(-10))
        }
        
        
    }
    
}
