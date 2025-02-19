//
//  TimedSelectTypeView.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/1/5.
//

import UIKit

protocol TimedSelectTypeViewDelegate: AnyObject {
    
    /// 选择类型回调
    /// - Parameters:
    ///   - view: 选择view
    ///   - tyoe: 类型
    func view(_ view: TimedSelectTypeView, selectTypeAction tyoe: TimedSelectTypeView.TimedType)
}

class TimedSelectTypeView: UIView {
    
    enum TimedType {
        /// 日程
        case schedule
        /// 生物节律
        case rhythm
        /// 定时
        case time
    }

    private var scheduleBtn: UIButton!
    private var rhythmBtn: UIButton!
    private var timeBtn: UIButton!
    private var lastSelectBtn: UIButton?
    
    var selectIndex: Int = 0 {
        didSet {
            if let btn = viewWithTag(100 + selectIndex) as? UIButton {
                lastSelectBtn?.isSelected = false
                lastSelectBtn?.layer.borderWidth = 0
                btn.isSelected = true
                btn.layer.borderWidth = 0.6
                
                lastSelectBtn = btn
            }
        }
    }
    
    weak var delegate: TimedSelectTypeViewDelegate?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        backgroundColor = .white
        layer.shadowColor = RGB(0, 0, 0, 0.07).cgColor
        layer.shadowOffset = CGSizeMake(0,-2)
        layer.shadowOpacity = 1
        layer.shadowRadius = 6
        
        setupUI()
        scheduleBtn.isSelected = true
        lastSelectBtn = scheduleBtn
    }
    
    /// 日程点击事件
    @objc private func scheduleBtnAction(sender: UIButton) {
        selectIndex = sender.tag - 100
        delegate?.view(self, selectTypeAction: .schedule)
    }
    /// 节律点击事件
    @objc private func rhythmBtnAction(sender: UIButton) {
        selectIndex = sender.tag - 100
        delegate?.view(self, selectTypeAction: .rhythm)
    }
    /// 时间点击事件
    @objc private func timeBtnAction(sender: UIButton) {
        selectIndex = sender.tag - 100
        delegate?.view(self, selectTypeAction: .time)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        
        scheduleBtn = UIButton(title: "schedule".localizedString, titleSize: 14, titleWeight: .light, titleColor: RGB(148, 163, 184), normalImageName: "schedule", selectedImageName: nil, target: self, action: #selector(scheduleBtnAction))
        scheduleBtn.setImage(UIImage(named: "schedule")?.withTintColor(Bar_Color), for: .selected)
        scheduleBtn.setImagePosition(position: .top, spacing: SCRYFrom(4))
        scheduleBtn.setTitleColor(Bar_Color, for: .selected)
        scheduleBtn.layer.cornerRadius = SCRYFrom(6)
        scheduleBtn.layer.borderColor = Bar_Color.cgColor
        scheduleBtn.layer.borderWidth = 0.6
        scheduleBtn.tag = 100
        addSubview(scheduleBtn)
        scheduleBtn.snp.makeConstraints { make in
            make.centerY.equalToSuperview().offset(SCRYFrom(-1))
            if isIPad {
                make.centerX.equalTo(self.snp.centerX).multipliedBy(0.4)
            }else {
                make.left.equalTo(SCRXFrom(6))
            }
            
            make.width.equalTo(SCRXFrom(112))
            make.height.equalTo(SCRYFrom(72))
        }
        
        rhythmBtn = UIButton(title: "rhythm".localizedString, titleSize: 14, titleWeight: .light, titleColor: RGB(148, 163, 184), normalImageName: "rhythm", selectedImageName: nil, target: self, action: #selector(rhythmBtnAction))
        rhythmBtn.setImage(UIImage(named: "rhythm")?.withTintColor(Bar_Color), for: .selected)
        rhythmBtn.setTitleColor(Bar_Color, for: .selected)
        rhythmBtn.layer.cornerRadius = SCRYFrom(6)
        rhythmBtn.layer.borderColor = Bar_Color.cgColor
        rhythmBtn.setImagePosition(position: .top, spacing: SCRYFrom(4))
        rhythmBtn.tag = 101
        addSubview(rhythmBtn)
        rhythmBtn.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.width.height.centerY.equalTo(scheduleBtn)
            make.height.equalTo(SCRYFrom(72))
        }
        
        timeBtn = UIButton(title: "time".localizedString, titleSize: 14, titleWeight: .light, titleColor: RGB(148, 163, 184), normalImageName: "time", selectedImageName: nil, target: self, action: #selector(timeBtnAction))
        timeBtn.setImage(UIImage(named: "time")?.withTintColor(Bar_Color), for: .selected)
        timeBtn.setTitleColor(Bar_Color, for: .selected)
        timeBtn.layer.cornerRadius = SCRYFrom(6)
        timeBtn.layer.borderColor = Bar_Color.cgColor
        timeBtn.setImagePosition(position: .top, spacing: SCRYFrom(4))
        timeBtn.tag = 102
        addSubview(timeBtn)
        timeBtn.snp.makeConstraints { make in
            if isIPad {
                make.centerX.equalTo(self.snp.centerX).multipliedBy(1.6)
            }else {
                make.right.equalTo(SCRXFrom(-7))
            }
            make.width.height.centerY.equalTo(scheduleBtn)
            make.height.equalTo(SCRYFrom(72))
        }
        
    }
}
