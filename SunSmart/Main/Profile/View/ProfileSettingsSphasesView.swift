//
//  ProfileSettingsSphasesView.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/2/28.
//

import UIKit

protocol ProfileSettingsSphasesViewDelegate: AnyObject {
    
    /// 帮助
    func sphasesViewHelpAction(_ view: ProfileSettingsSphasesView)
    
    /// High-end/Low-end trim
    func sphasesViewHighAndLowEndTrimAction(_ view: ProfileSettingsSphasesView)
    
    /// Occupancy/Vacant level
    func sphasesViewOccupancyAndVacantLevelAction(_ view: ProfileSettingsSphasesView)
    
    /// Auto min level
    func sphasesViewAutoMinValueAction(_ view: ProfileSettingsSphasesView)
    
    /// Task level (%/lx)
    func sphasesViewTaskLevelAction(_ view: ProfileSettingsSphasesView)
    
    /// Time  T1/T2/T3/T4/T5
    func view(_ view: ProfileSettingsSphasesView, timeAction timeType: Profile.LightData.TimePickerData.TimeType)
    
}

class ProfileSettingsSphasesView: UIView {

    private var titleLabel: UILabel!
    private var imageView: UIImageView!
    private var helpBtn: UIButton!
    /// 阶段图
    private var chartImageView: UIImageView!
    
    //************  Light Level  **********/
    /// Max.light output
    private var maxLightOutputLabel: UILabel!
    /// High-end trim
    private var highEndTrimBtn: UIButton!
    private var highEndTrimLabel: UILabel!
    /// Occupancy level
    private var occupancyLevelBtn: UIButton!
    private var occupancyLevelLabel: UILabel!
    /// Vacant level
    private var vacantLevelBtn: UIButton!
    private var vacantLevelLabel: UILabel!
    /// Task Level
    private var taskLevelBtn: UIButton!
    private var taskLevelLabel: UILabel!
    /// Auto min level
    private var autoMinLevelBtn: UIButton!
    private var autoMinLevelLabel: UILabel!
    /// Low-end trim
    private var lowEndTrimBtn: UIButton!
    private var lowEndTrimLabel: UILabel!
    /// Off
    private var offLabel: UILabel!
    
    //************  Light Time  **********/
    /// T1
    private var timeT1Btn: UIButton!
    private var timeT1Label: UILabel!
    /// T2
    private var timeT2Btn: UIButton!
    private var timeT2Label: UILabel!
    /// T3
    private var timeT3Btn: UIButton!
    private var timeT3Label: UILabel!
    /// T4
    private var timeT4Btn: UIButton!
    private var timeT4Label: UILabel!
    /// T5
    private var timeT5Btn: UIButton!
    private var timeT5Label: UILabel!
    
    weak var delegate: ProfileSettingsSphasesViewDelegate?
    
    var profile: Profile! {
        didSet {
            
            
            let data = profile.lightControlData
            
            timeT1Label.text =  Profile.LightData.TimePickerData.timeDetail(type: .t1, second: data.t1)
            timeT2Label.text =  Profile.LightData.TimePickerData.timeDetail(type: .t2, second: data.t2)
            timeT3Label.text =  Profile.LightData.TimePickerData.timeDetail(type: .t3, second: data.t3)
            timeT4Label.text =  Profile.LightData.TimePickerData.timeDetail(type: .t4, second: data.t4)
            timeT5Label.text =  Profile.LightData.TimePickerData.timeDetail(type: .t5, second: data.t5)
            
            highEndTrimLabel.text = "\(data.highEndTrim)%"
            lowEndTrimLabel.text = "\(data.lowEndTrim)%"
            
            if profile.type == .vacancy_daylight || profile.type == .occupancy_daylight || profile.type == .daylight {
                occupancyLevelLabel.text = "\(data.occupancyLevel)lx"
                vacantLevelLabel.text = "\(data.vacantLevel)lx"
                taskLevelLabel.text = "\(data.taskLevel)lx"
            }else {
                occupancyLevelLabel.text = "\(data.occupancyLevel)%"
                vacantLevelLabel.text = "\(data.vacantLevel)%"
                taskLevelLabel.text = "\(data.taskLevel)%"
            }
            
            
            
            autoMinLevelLabel.text = data.autoMinLevelEnabled ? "\(data.autoMinLevel)%" : "N/A"
            
            timeT1Btn.isHidden = true
            timeT1Label.isHidden = true
            timeT2Btn.isHidden = true
            timeT2Label.isHidden = true
            timeT3Btn.isHidden = true
            timeT3Label.isHidden = true
            timeT4Btn.isHidden = true
            timeT4Label.isHidden = true
            timeT5Btn.isHidden = true
            timeT5Label.isHidden = true
            
            taskLevelBtn.isHidden = true
            taskLevelLabel.isHidden = true
            autoMinLevelBtn.isHidden = true
            autoMinLevelLabel.isHidden = true
            titleLabel.isHidden = true
            
            var profileChartImageName = "profile_chart_occupancy"
            switch profile.type {
            case .occupancy_daylight, .vacancy_daylight, .occupancy, .vacancy, .proximityLighting, .proximityLightingWithPhotocell:
                timeT1Btn.isHidden = false
                timeT1Label.isHidden = false
                timeT2Btn.isHidden = false
                timeT2Label.isHidden = false
                timeT3Btn.isHidden = false
                timeT3Label.isHidden = false
                timeT4Btn.isHidden = false
                timeT4Label.isHidden = false
                timeT5Btn.isHidden = false
                timeT5Label.isHidden = false
                vacantLevelBtn.isHidden = false
                vacantLevelLabel.isHidden = false
                occupancyLevelBtn.isHidden = false
                occupancyLevelLabel.isHidden = false
                
                if profile.type == .occupancy || profile.type == .vacancy || profile.type == .proximityLighting {
                    autoMinLevelBtn.isHidden = true
                    autoMinLevelLabel.isHidden = true
                    profileChartImageName = "profile_chart_occupancy"
                    if profile.type == .proximityLighting {
                        titleLabel.isHidden = false
                    }
//                    chartImageView.image = UIImage(named: "profile_chart_occupancy")
                }else {
                    autoMinLevelBtn.isHidden = false
                    autoMinLevelLabel.isHidden = false
//                    chartImageView.image = UIImage(named: "profile_chart_occupancy_daylight")
                    profileChartImageName = "profile_chart_occupancy_daylight"
                }
                autoMinLevelBtn.snp.remakeConstraints { make in
                    make.right.width.height.equalTo(highEndTrimBtn)
                    make.top.equalTo(vacantLevelBtn.snp.bottom).offset(SCRYFrom(8))
                }
                
                
   
            case .daylight:
//                chartImageView.image = UIImage(named: "profile_chart_daylight")
                profileChartImageName = "profile_chart_daylight"
                autoMinLevelBtn.isHidden = false
                autoMinLevelLabel.isHidden = false
                taskLevelBtn.isHidden = false
                taskLevelLabel.isHidden = false
                vacantLevelBtn.isHidden = true
                vacantLevelLabel.isHidden = true
                occupancyLevelBtn.isHidden = true
                occupancyLevelLabel.isHidden = true
                
                timeT1Btn.isHidden = false
                timeT1Label.isHidden = false
                
//                autoMinLevelBtn.snp.remakeConstraints { make in
//                    make.right.width.height.equalTo(highEndTrimBtn)
//                    make.top.equalTo(taskLevelBtn.snp.bottom).offset(SCRYFrom(8))
//                }
                autoMinLevelBtn.snp.remakeConstraints { make in
                    make.right.width.height.equalTo(highEndTrimBtn)
                    make.top.equalTo(vacantLevelBtn.snp.bottom).offset(SCRYFrom(8))
                }
                
            case .manualControl:
//                chartImageView.image = UIImage(named: "profile_chart_manual_control")
                profileChartImageName = "profile_chart_manual_control"
                timeT1Btn.isHidden = false
                timeT1Label.isHidden = false
//                timeT5Btn.isHidden = false
//                timeT5Label.isHidden = false
                
                autoMinLevelBtn.isHidden = true
                autoMinLevelLabel.isHidden = true
                taskLevelBtn.isHidden = false
                taskLevelLabel.isHidden = false
                
                vacantLevelBtn.isHidden = true
                vacantLevelLabel.isHidden = true
                occupancyLevelBtn.isHidden = true
                occupancyLevelLabel.isHidden = true
                
                autoMinLevelBtn.snp.remakeConstraints { make in
                    make.right.width.height.equalTo(highEndTrimBtn)
                    make.top.equalTo(vacantLevelBtn.snp.bottom).offset(SCRYFrom(8))
                }
            }
            if isIPad {
                profileChartImageName.append("_ipad")
            }
            chartImageView.image = UIImage(named: profileChartImageName)
            chartImageView.sizeToFit()
            
            var chartImageTopMargin = SCRYFrom(46)
            var helpTopMargin = SCRYFrom(4)
            var highEndTrimMargin = SCRYFrom(60)
            if profile.type == .proximityLighting {
                chartImageTopMargin = SCRYFrom(62)
                helpTopMargin = SCRYFrom(10)
                highEndTrimMargin = SCRYFrom(76)
            }
            chartImageView.snp.remakeConstraints { make in
                
                make.top.equalTo(chartImageTopMargin)
                if isIPad {
                    make.left.equalTo(SCRXFrom(136))
                    make.right.equalTo(SCRXFrom(-56.7))
//                    make.height.equalTo(chartImageView.snp.width).multipliedBy(230 / 490.0)
                    make.height.equalTo(SCRYFrom(230))
                }else {
                    make.left.equalTo(SCRXFrom(86))
                    make.right.equalTo(SCRXFrom(-45))
                    make.height.equalTo(chartImageView.snp.width).multipliedBy(chartImageView.height / chartImageView.width)
                }
                make.bottom.equalTo(SCRYFrom(-68))
            }
            helpBtn.snp.updateConstraints { make in
                make.top.equalTo(helpTopMargin)
            }
            highEndTrimBtn.snp.updateConstraints { make in
                make.top.equalTo(highEndTrimMargin)
            }
        }
    }
    
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        layer.cornerRadius = 10
        backgroundColor = .white
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        subviews.forEach({
            if $0.isKind(of: UIButton.classForCoder()), let btn = $0 as? UIButton, btn.isUserInteractionEnabled {
//                btn.clipsToBounds = true
//                btn.setBackgroundImage(UIImage.image(size: btn.frame.size, color: .black.withAlphaComponent(0.15)), for: .highlighted)
                btn.addTarget(self, action: #selector(btnTouchDownAction), for: .touchDown)
                btn.addTarget(self, action: #selector(btnTouchUpInside), for: .touchCancel)
            }
        })
        
    }
    
    // MARK: - Action
    /// 帮助
    @objc private func helpBtnAction(sender: UIButton) {
        delegate?.sphasesViewHelpAction(self)
        btnTouchUpInside(sender: sender)
    }
    
    // MARK: - Level
    /// 最高输出亮度
    @objc private func highEndTrimBtnAction(sender: UIButton) {
        delegate?.sphasesViewHighAndLowEndTrimAction(self)
        btnTouchUpInside(sender: sender)
    }
    /// 占用阶段
    @objc private func occupancyLevelBtnAction(sender: UIButton) {
        delegate?.sphasesViewOccupancyAndVacantLevelAction(self)
        btnTouchUpInside(sender: sender)
    }
    /// 维持阶段
    @objc private func vacantLevelBtnAction(sender: UIButton) {
        delegate?.sphasesViewOccupancyAndVacantLevelAction(self)
        btnTouchUpInside(sender: sender)
    }
    /// 日光补偿最低值
    @objc private func autoMinLevelBtnAction(sender: UIButton) {
        delegate?.sphasesViewAutoMinValueAction(self)
        btnTouchUpInside(sender: sender)
    }
    /// 最低输出亮度
    @objc private func lowEndTrimBtnAction(sender: UIButton) {
        delegate?.sphasesViewHighAndLowEndTrimAction(self)
        btnTouchUpInside(sender: sender)
    }
    /// 维持亮度(手动控制On% / 环境光lx)
    @objc private func taskLevelBtnAction(sender: UIButton) {
        delegate?.sphasesViewTaskLevelAction(self)
        btnTouchUpInside(sender: sender)
    }
    
    // MARK: - Time
    
    @objc private func timeT1BtnAction(sender: UIButton) {
        delegate?.view(self, timeAction: .t1)
        btnTouchUpInside(sender: sender)
    }
    
    @objc private func timeT2BtnAction(sender: UIButton) {
        delegate?.view(self, timeAction: .t2)
        btnTouchUpInside(sender: sender)
    }
    
    @objc private func timeT3BtnAction(sender: UIButton) {
        delegate?.view(self, timeAction: .t3)
        btnTouchUpInside(sender: sender)
    }
    
    @objc private func timeT4BtnAction(sender: UIButton) {
        delegate?.view(self, timeAction: .t4)
        btnTouchUpInside(sender: sender)
    }
    
    @objc private func timeT5BtnAction(sender: UIButton) {
        delegate?.view(self, timeAction: .t5)
        btnTouchUpInside(sender: sender)
    }
   
    /// 按键按下回调
    @objc private func btnTouchDownAction(sender: UIButton) {
//        sender.isHighlighted = true
//        sender.backgroundColor = .black.withAlphaComponent(0.15)
        sender.backgroundColor = RGB(0, 0, 0, 0.15)
     
//        UIView.animate(withDuration: 0.25) {
//            sender.backgroundColor = RGB(0, 0, 0, 0.15)
//        } completion: { _ in
//            sender.backgroundColor = .clear
//        }
    }
    
    /// 按键点击抬起回调
    @objc private func btnTouchUpInside(sender: UIButton) {
        UIView.animate(withDuration: 0.25) {
            sender.backgroundColor = .clear
        }
    }
    
  
    
    private func setupUI() {
        
        titleLabel = UILabel(text: "device_trigger_curve".localizedString, textColor: TextBlack_Color, fontSize: 16, fontWeight: .light)
        titleLabel.isHidden = true
        addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.equalTo(SCRYFrom(16))
        }
        
        helpBtn = UIButton(normalImageName: "help", target: self, action: #selector(helpBtnAction))
        addSubview(helpBtn)
        helpBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-4))
            make.top.equalTo(SCRYFrom(4))
        }
        
        chartImageView = UIImageView(image: UIImage(named: "profile_chart_occupancy_daylight"))
        chartImageView.sizeToFit()
        addSubview(chartImageView)
        chartImageView.snp.makeConstraints { make in
            if isIPad {
                make.left.equalTo(SCRXFrom(146))
                make.right.equalTo(SCRXFrom(-56.7))
//                make.height.equalTo(chartImageView.snp.width).multipliedBy(230 / 490.0)
                make.height.equalTo(SCRYFrom(230))
            }else {
                make.left.equalTo(SCRXFrom(86))
                make.right.equalTo(SCRXFrom(-45))
                make.height.equalTo(chartImageView.snp.width).multipliedBy(chartImageView.height / chartImageView.width)
            }
            make.top.equalTo(SCRYFrom(46))
            make.bottom.equalTo(SCRYFrom(-68))
//            if isIPad {
////                make.centerX.equalToSuperview()
//            }else {
//                make.top.equalTo(SCRYFrom(46))
//            }
        }
        
        imageView = UIImageView(image: UIImage(named: "profile_light_level"))
        addSubview(imageView)
        imageView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(isIPad ? 13 : 2))
//            make.top.equalTo(SCRYFrom(34))
            make.top.equalTo(chartImageView).offset(SCRYFrom(-12))
            make.bottom.equalTo(chartImageView)
        }
        
        maxLightOutputLabel = UILabel(text: "profile_max_light_output".localizedString, textColor: Chart_Text_Color, fontSize: 12)
        maxLightOutputLabel.numberOfLines = 2
        maxLightOutputLabel.textAlignment = .center
        addSubview(maxLightOutputLabel)
        maxLightOutputLabel.snp.makeConstraints { make in
            make.right.equalTo(chartImageView.snp.left)
//            if !isIPad {
//                make.left.equalTo(SCRXFrom(25))
//            }
            if isIPad {
                make.width.equalTo(SCRXFrom(93.8))
            }else {
                make.width.equalTo(SCRXFrom(60))
            }
            make.centerY.equalTo(chartImageView.snp.top)
        }
        
        highEndTrimBtn = UIButton(title: "profile_high_end_trim".localizedString, titleSize: 12, titleColor: Chart_Text_Color, target: self, action: #selector(highEndTrimBtnAction))
        highEndTrimBtn.titleLabel?.numberOfLines = 2
        highEndTrimBtn.titleLabel?.textAlignment = .center
        highEndTrimBtn.layer.cornerRadius = 5
        highEndTrimBtn.layer.borderWidth = 1
        highEndTrimBtn.layer.borderColor = RGB(216, 216, 216).cgColor
        highEndTrimBtn.clipsToBounds = true
        
        addSubview(highEndTrimBtn)
        highEndTrimBtn.snp.makeConstraints { make in
            make.right.equalTo(chartImageView.snp.left)
            make.top.equalTo(SCRYFrom(60))
            if isIPad {
//                make.top.equalTo(maxLightOutputLabel.snp.bottom).offset(SCRYFrom(20))
                make.width.equalTo(SCRXFrom(93.6))
            }else {
                make.width.equalTo(SCRXFrom(64))
            }
            make.height.equalTo(SCRYFrom(32))
        }
        
        highEndTrimLabel = UILabel(text: "100%", textColor: Chart_Text_Color, fontSize: 10)
        addSubview(highEndTrimLabel)
        highEndTrimLabel.snp.makeConstraints { make in
            if isIPad {
                make.left.equalTo(chartImageView.snp.right).offset(SCRXFrom(7))
            }else {
                make.left.equalTo(chartImageView.snp.right).offset(SCRXFrom(1))
            }
            make.centerY.equalTo(highEndTrimBtn)
        }
        
        let levelSphaseMargin = isIPad ? SCRYFrom(7) : SCRYFrom(8)
        
        occupancyLevelBtn = UIButton(title: "profile_occupa-ncy_level".localizedString, titleSize: 12, titleColor: Chart_Text_Color, target: self, action: #selector(occupancyLevelBtnAction))
        occupancyLevelBtn.titleLabel?.numberOfLines = 2
        occupancyLevelBtn.titleLabel?.textAlignment = .center
        occupancyLevelBtn.layer.cornerRadius = 5
        occupancyLevelBtn.layer.borderWidth = 1
        occupancyLevelBtn.layer.borderColor = RGB(216, 216, 216).cgColor
        addSubview(occupancyLevelBtn)
        occupancyLevelBtn.snp.makeConstraints { make in
            make.right.width.height.equalTo(highEndTrimBtn)
            make.top.equalTo(highEndTrimBtn.snp.bottom).offset(levelSphaseMargin)
        }
        
        occupancyLevelLabel = UILabel(text: "1000lx", textColor: Chart_Text_Color, fontSize: 10)
        addSubview(occupancyLevelLabel)
        occupancyLevelLabel.snp.makeConstraints { make in
            make.left.equalTo(highEndTrimLabel)
            make.centerY.equalTo(occupancyLevelBtn)
        }
        
        taskLevelBtn = UIButton(title: "profile_task_level".localizedString, titleSize: 12, titleColor: Chart_Text_Color, target: self, action: #selector(taskLevelBtnAction))
        taskLevelBtn.titleLabel?.textAlignment = .center
        taskLevelBtn.layer.cornerRadius = 5
        taskLevelBtn.layer.borderWidth = 1
        taskLevelBtn.layer.borderColor = RGB(216, 216, 216).cgColor
        taskLevelBtn.isHidden = true
        addSubview(taskLevelBtn)
        taskLevelBtn.snp.makeConstraints { make in
            make.right.width.height.equalTo(highEndTrimBtn)
            make.top.equalTo(highEndTrimBtn.snp.bottom).offset(levelSphaseMargin)
        }
        
        taskLevelLabel = UILabel(text: "500lx", textColor: Chart_Text_Color, fontSize: 10)
        taskLevelLabel.isHidden = true
        addSubview(taskLevelLabel)
        taskLevelLabel.snp.makeConstraints { make in
            make.left.equalTo(highEndTrimLabel)
            make.centerY.equalTo(taskLevelBtn)
        }
        
        vacantLevelBtn = UIButton(title: "profile_vacant_level".localizedString, titleSize: 12, titleColor: Chart_Text_Color, target: self, action: #selector(vacantLevelBtnAction))
        vacantLevelBtn.titleLabel?.numberOfLines = 2
        vacantLevelBtn.titleLabel?.textAlignment = .center
        vacantLevelBtn.contentMode = .center
        vacantLevelBtn.layer.cornerRadius = 5
        vacantLevelBtn.layer.borderWidth = 1
        vacantLevelBtn.layer.borderColor = RGB(216, 216, 216).cgColor
        addSubview(vacantLevelBtn)
        vacantLevelBtn.snp.makeConstraints { make in
            make.right.width.height.equalTo(highEndTrimBtn)
            make.top.equalTo(occupancyLevelBtn.snp.bottom).offset(levelSphaseMargin)
        }
        
        vacantLevelLabel = UILabel(text: "1000lx", textColor: Chart_Text_Color, fontSize: 10)
        addSubview(vacantLevelLabel)
        vacantLevelLabel.snp.makeConstraints { make in
            make.left.equalTo(highEndTrimLabel)
            make.centerY.equalTo(vacantLevelBtn)
        }
        
        autoMinLevelBtn = UIButton(title: "profile_auto_min_value".localizedString, titleSize: 12, titleColor: Chart_Text_Color, target: self, action: #selector(autoMinLevelBtnAction))
        autoMinLevelBtn.titleLabel?.numberOfLines = 2
        autoMinLevelBtn.titleLabel?.textAlignment = .center
        autoMinLevelBtn.layer.cornerRadius = 5
        autoMinLevelBtn.layer.borderWidth = 1
        autoMinLevelBtn.layer.borderColor = RGB(216, 216, 216).cgColor
        addSubview(autoMinLevelBtn)
        autoMinLevelBtn.snp.makeConstraints { make in
            make.right.width.height.equalTo(highEndTrimBtn)
            make.top.equalTo(vacantLevelBtn.snp.bottom).offset(levelSphaseMargin)
        }
        
        autoMinLevelLabel = UILabel(text: "100%", textColor: Chart_Text_Color, fontSize: 10)
        addSubview(autoMinLevelLabel)
        autoMinLevelLabel.snp.makeConstraints { make in
            make.left.equalTo(highEndTrimLabel)
            make.centerY.equalTo(autoMinLevelBtn)
        }
        
        lowEndTrimBtn = UIButton(title: "profile_low_end_trim".localizedString, titleSize: 12, titleColor: Chart_Text_Color, target: self, action: #selector(lowEndTrimBtnAction))
        lowEndTrimBtn.titleLabel?.numberOfLines = 2
        lowEndTrimBtn.titleLabel?.textAlignment = .center
        lowEndTrimBtn.layer.cornerRadius = 5
        lowEndTrimBtn.layer.borderWidth = 1
        lowEndTrimBtn.layer.borderColor = RGB(216, 216, 216).cgColor
        addSubview(lowEndTrimBtn)
        lowEndTrimBtn.snp.makeConstraints { make in
            make.right.width.height.equalTo(highEndTrimBtn)
            make.top.equalTo(autoMinLevelBtn.snp.bottom).offset(levelSphaseMargin)
        }
        
        lowEndTrimLabel = UILabel(text: "0%", textColor: Chart_Text_Color, fontSize: 10)
        addSubview(lowEndTrimLabel)
        lowEndTrimLabel.snp.makeConstraints { make in
            make.left.equalTo(highEndTrimLabel)
            make.centerY.equalTo(lowEndTrimBtn)
        }
        
        offLabel = UILabel(text: "action_off".localizedString, textColor: Chart_Text_Color, fontSize: 12)
        addSubview(offLabel)
        offLabel.snp.makeConstraints { make in
            make.centerX.equalTo(lowEndTrimBtn)
            if isIPad {
                make.bottom.equalTo(chartImageView).offset(SCRYFrom(-4))
            }else {
                make.top.equalTo(lowEndTrimBtn.snp.bottom).offset(levelSphaseMargin)
            }
        }
        
        timeT1Btn = UIButton(title: "T1", titleSize: 12, titleWeight: .light, titleColor: .black, target: self, action: #selector(timeT1BtnAction))
        timeT1Btn.layer.cornerRadius = 5
        timeT1Btn.layer.borderWidth = 1
        timeT1Btn.layer.borderColor = RGB(216, 216, 216).cgColor
        addSubview(timeT1Btn)
        timeT1Btn.snp.makeConstraints { make in
            if isIPad {
                make.left.equalTo(chartImageView).offset(SCRXFrom(2.5))
                make.width.equalTo(SCRXFrom(69.45))
                make.height.equalTo(SCRYFrom(30))
            }else {
                make.left.equalTo(chartImageView).offset(SCRXFrom(-4))
                make.width.height.equalTo(SCRXFrom(30))
            }
            make.bottom.equalTo(SCRYFrom(-12))
        }
        
        timeT1Label = UILabel(text: "2s", textColor: .black, fontSize: 10, fontWeight: .light)
        addSubview(timeT1Label)
        timeT1Label.snp.makeConstraints { make in
            make.bottom.equalTo(timeT1Btn.snp.top).offset(SCRYFrom(-5))
            make.centerX.equalTo(timeT1Btn)
        }
        
        timeT2Btn = UIButton(title: "T2", titleSize: 12, titleWeight: .light, titleColor: .black, target: self, action: #selector(timeT2BtnAction))
        timeT2Btn.layer.cornerRadius = 5
        timeT2Btn.layer.borderWidth = 1
        timeT2Btn.layer.borderColor = RGB(216, 216, 216).cgColor
        addSubview(timeT2Btn)
        timeT2Btn.snp.makeConstraints { make in
            if isIPad {
                make.left.equalTo(timeT1Btn.snp.right).offset(SCRXFrom(64))
            }else {
                make.left.equalTo(timeT1Btn.snp.right).offset(SCRXFrom(34))
            }
            make.bottom.width.height.equalTo(timeT1Btn)
        }
        
        timeT2Label = UILabel(text: "20min", textColor: .black, fontSize: 10, fontWeight: .light)
        addSubview(timeT2Label)
        timeT2Label.snp.makeConstraints { make in
            make.bottom.equalTo(timeT1Label)
            make.centerX.equalTo(timeT2Btn)
        }
        
        timeT3Btn = UIButton(title: "T3", titleSize: 12, titleWeight: .light, titleColor: .black, target: self, action: #selector(timeT3BtnAction))
        timeT3Btn.layer.cornerRadius = 5
        timeT3Btn.layer.borderWidth = 1
        timeT3Btn.layer.borderColor = RGB(216, 216, 216).cgColor
        addSubview(timeT3Btn)
        timeT3Btn.snp.makeConstraints { make in
            if isIPad {
                make.left.equalTo(timeT2Btn.snp.right).offset(SCRXFrom(22))
            }else {
                make.left.equalTo(timeT2Btn.snp.right).offset(SCRXFrom(10))
            }
            make.bottom.width.height.equalTo(timeT1Btn)
        }
        
        timeT3Label = UILabel(text: "2s", textColor: .black, fontSize: 10, fontWeight: .light)
        addSubview(timeT3Label)
        timeT3Label.snp.makeConstraints { make in
            make.bottom.equalTo(timeT1Label)
            make.centerX.equalTo(timeT3Btn)
        }
        
        timeT4Btn = UIButton(title: "T4", titleSize: 12, titleWeight: .light, titleColor: .black, target: self, action: #selector(timeT4BtnAction))
        timeT4Btn.layer.cornerRadius = 5
        timeT4Btn.layer.borderWidth = 1
        timeT4Btn.layer.borderColor = RGB(216, 216, 216).cgColor
        addSubview(timeT4Btn)
        timeT4Btn.snp.makeConstraints { make in
            if isIPad {
                make.left.equalTo(timeT3Btn.snp.right).offset(SCRXFrom(10))
            }else {
                make.left.equalTo(timeT3Btn.snp.right).offset(SCRXFrom(5))
            }
            make.bottom.width.height.equalTo(timeT1Btn)
        }
        
        timeT4Label = UILabel(text: "infinite".localizedString, textColor: .black, fontSize: 10, fontWeight: .light)
        addSubview(timeT4Label)
        timeT4Label.snp.makeConstraints { make in
            make.bottom.equalTo(timeT1Label)
            make.centerX.equalTo(timeT4Btn)
        }
        
        timeT5Btn = UIButton(title: "T5", titleSize: 12, titleWeight: .light, titleColor: .black, target: self, action: #selector(timeT5BtnAction))
        timeT5Btn.layer.cornerRadius = 5
        timeT5Btn.layer.borderWidth = 1
        timeT5Btn.layer.borderColor = RGB(216, 216, 216).cgColor
        addSubview(timeT5Btn)
        timeT5Btn.snp.makeConstraints { make in
            if isIPad {
                make.left.equalTo(timeT4Btn.snp.right).offset(SCRXFrom(10))
            }else {
                make.left.equalTo(timeT4Btn.snp.right).offset(SCRXFrom(5))
            }
            make.bottom.width.height.equalTo(timeT1Btn)
        }
        
        timeT5Label = UILabel(text: "2s".localizedString, textColor: .black, fontSize: 10, fontWeight: .light)
        addSubview(timeT5Label)
        timeT5Label.snp.makeConstraints { make in
            make.bottom.equalTo(timeT1Label)
            make.centerX.equalTo(timeT5Btn)
        }
        
    }
    
}
