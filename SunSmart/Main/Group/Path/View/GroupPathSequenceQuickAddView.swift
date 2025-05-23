//
//  GroupPathSequenceQuickAddView.swift
//  SunSmart
//
//  Created by yuankehong on 2025/5/19.
//

import UIKit

/// 快速添加状态
enum QuickAddState {
    /// 添加中
    case adding
    /// 暂停
    case pause
    /// 停止
    case stop
}

protocol GroupPathSequenceQuickAddViewDelegate: AnyObject {
    
    /// 快速添加状态更新
    func quickAddView(_ view: GroupPathSequenceQuickAddView, addStateChanged addState: QuickAddState)
    
    /// 快速添加是否显示已添加设备状态更新  showAdded：是否展示已添加设备
    func quickAddView(_ view: GroupPathSequenceQuickAddView, showAddedDevicesChanged showAdded: Bool)
}


class GroupPathSequenceQuickAddView: UIView {
    
    private var titleLabel: UILabel!
    var addView: UIView!
//    private var showAddedSwitch: UISwitch!
    private var switchBtn: UIButton!
    private var startBtn: UIButton!
    private var stopBtn: UIButton!
//    private var pauseBtn: UIButton!
    private var addStateLabel: UILabel!
    private var messageLabel: UILabel!
    
    
    var guideView: GroupPathSequenceDeviceAddStepView!
    
    var showAdded: Bool = false
    var isSequence: Bool = true
    weak var delegate: GroupPathSequenceQuickAddViewDelegate?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        backgroundColor = .white
        layer.cornerRadius = SCRYFrom(10)
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    /// 展示流程UI
    func showStepGuideUI() {
        guideView.isHidden = false
        addView.isHidden = true
        stopBtn.isHidden = true
        startBtn.snp.updateConstraints { make in
            make.centerX.equalToSuperview()
        }
    }
    
    /// 更新快速添加状态
    func updateQuickAddState(_ state: QuickAddState) {
        guideView.isHidden = true
        addView.isHidden = false
        switch state {
        case .adding:
            stopBtn.isHidden = false
            addStateLabel.text = "Adding…".localizedString
            addStateLabel.textColor = Green_Color
            startBtn.snp.updateConstraints { make in
                make.centerX.equalToSuperview().offset(SCRXFrom(-40))
            }
            startBtn.isSelected = true
        case .pause:
            stopBtn.isHidden = false
            addStateLabel.text = "pause_add".localizedString
            addStateLabel.textColor = Red_Color
            startBtn.isSelected = true
            startBtn.snp.updateConstraints { make in
                make.centerX.equalToSuperview().offset(SCRXFrom(-40))
            }
            
        case .stop:
            stopBtn.isHidden = true
            startBtn.isSelected = false
            startBtn.snp.updateConstraints { make in
                make.centerX.equalToSuperview()
            }
        }
    }
    
    @objc private func startBtnAction(sender: UIButton) {
        sender.isSelected = !sender.isSelected
        
        if sender.isSelected {
            addStateLabel.text = "Adding…".localizedString
            addStateLabel.textColor = Green_Color
        }else {
            addStateLabel.text = "pause_add".localizedString
            addStateLabel.textColor = Red_Color
        }
        startBtn.snp.updateConstraints { make in
            make.centerX.equalToSuperview().offset(SCRXFrom(-40))
        }
        
        stopBtn.isHidden = false
        delegate?.quickAddView(self, addStateChanged: sender.isSelected ? .adding : .pause)
    }
    
    @objc private func stopBtnAction() {
        stopBtn.isHidden = true
        
        startBtn.isSelected = false
        startBtn.isHidden = false
        startBtn.snp.updateConstraints { make in
            make.centerX.equalToSuperview()
        }
        addStateLabel.text = "click_to_start".localizedString
        addStateLabel.textColor = TextBlack_Color
        delegate?.quickAddView(self, addStateChanged: .stop)
    }
    
    @objc private func switchBtnAction(sender: UIButton) {
        let menuWidth = SCRXFrom(256)
        let btnPoint = CGPoint(x: self.width - menuWidth, y: sender.frame.maxY)
        let windowPoint = self.convert(btnPoint, to: UIApplication.shared.keyWindow())
        
        var titles = ["quick_add_ignore_added_devices".localizedString, "quick_add_show_added_devices".localizedString]
        if !isSequence {
            titles = ["quick_add_ignore_added_devices".localizedString, "zone_quick_add_show_added_devices".localizedString]
            
        }
      
        TitleSelectView.show(titles: titles, style: .default, anchorPoint: windowPoint, menuWidth: menuWidth, itemHeight: SCRYFrom(44), titleFont: UIFont.systemFont(ofSize: 14, weight: .light)) {[weak self] index in
            guard let self = self else { return }
            self.titleLabel.text = titles[index]
            
            self.showAdded = index == 1
            self.delegate?.quickAddView(self, showAddedDevicesChanged: self.showAdded)
        }
        
    }
    
    private func setupUI() {
        
        addView = UIView()
//        addView.isHidden = true
        addSubview(addView)
        addView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        titleLabel = UILabel(text: "quick_add_ignore_added_devices".localizedString, textColor: TextBlack_Color, fontSize: 14, fontWeight: .light, fit: false)
        addView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(8))
            make.top.equalTo(SCRYFrom(12))
            make.right.equalTo(SCRXFrom(-60))
        }
        
        switchBtn = UIButton(normalImageName: "arrow_down_black", target: self, action: #selector(switchBtnAction))
        addView.addSubview(switchBtn)
        switchBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-8))
            make.top.equalTo(SCRYFrom(4))
        }
        
//        showAddedSwitch = UISwitch()
//        showAddedSwitch.onTintColor = Bar_Color
//        showAddedSwitch.addTarget(self, action: #selector(showAddedSwitchValueChanged), for: .valueChanged)
//        addView.addSubview(showAddedSwitch)
//        showAddedSwitch.snp.makeConstraints { make in
//            make.right.equalTo(SCRXFrom(-4))
//            make.centerY.equalTo(titleLabel)
//        }
        
        startBtn = UIButton(normalImageName: "quick_add_start", selectedImageName: "quick_add_pause", target: self, action: #selector(startBtnAction))
        addView.addSubview(startBtn)
        startBtn.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(SCRYFrom(40))
        }
        
//        pauseBtn = UIButton(normalImageName: "quick_add_pause", target: self, action: #selector(startBtnAction))
//        pauseBtn.isHidden = true
//        addView.addSubview(pauseBtn)
//        pauseBtn.snp.makeConstraints { make in
//            make.right.equalTo(addView.snp.centerX).offset(SCRXFrom(-20))
//            make.top.equalTo(startBtn)
//        }
        
        stopBtn = UIButton(normalImageName: "quick_add_stop", target: self, action: #selector(stopBtnAction))
        stopBtn.isHidden = true
        addView.addSubview(stopBtn)
        stopBtn.snp.makeConstraints { make in
            make.left.equalTo(addView.snp.centerX).offset(SCRXFrom(20))
            make.centerY.equalTo(startBtn)
        }
        
        addStateLabel = UILabel(text: "click_to_start".localizedString, textColor: TextBlack_Color, fontSize: 14, fontWeight: .light, fit: false)
        addView.addSubview(addStateLabel)
        addStateLabel.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.centerY.equalTo(startBtn)
        }
        
        messageLabel = UILabel(text: "path_quick_add_message".localizedString, textColor: SubText_Color, fontSize: 12, fontWeight: .light, fit: false)
        messageLabel.numberOfLines = 2
        messageLabel.textAlignment = .center
        addView.addSubview(messageLabel)
        messageLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(15))
            make.right.equalTo(SCRXFrom(-13))
            make.bottom.equalTo(SCRYFrom(-6))
        }
        
        guideView = GroupPathSequenceDeviceAddStepView()
        guideView.isHidden = true
        addSubview(guideView)
        guideView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
    }
    
}
