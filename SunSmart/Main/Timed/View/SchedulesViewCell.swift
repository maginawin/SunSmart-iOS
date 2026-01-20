//
//  SchedulesViewCell.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/1/5.
//

import UIKit

class SchedulesViewCell: UICollectionViewCell {
    
    private var nameLabel: UILabel!
    private var enableSwitch: UISwitch!
    private var enableBtn: UIButton!
    private var detailView: UIView!
    private var weeksDayLabel: UILabel!
    private var timeLabel: UILabel!
    private var actionLabel: UILabel!
    private var fadeTimeLabel: UILabel!
    private var failedImageView: UIImageView!
    
    /// 启用/禁用事件回调
    var enabledActionCallback: ((Bool)->Void)?
    
    var schedule: Schedule! {
        didSet {
            nameLabel.text = schedule.name
            enableSwitch.isOn = schedule.enabled
            
            self.detailView.isHidden = !self.schedule.enabled
//            UIView.animate(withDuration: 0.25) {
//                self.detailView.alpha = self.schedule.enabled ? 1 : 0
//            }
            weeksDayLabel.text = schedule.weekStr
            
            if schedule.hour >= 12 {
                timeLabel.text = String(format: "%d:%02d %@", schedule.hour - 12, schedule.minute, "pm".localizedString)
            }else {
                timeLabel.text = String(format: "%d:%02d %@", schedule.hour == 0 ? 12 : schedule.hour, schedule.minute, "am".localizedString)
            }
            
            nameLabel.snp.remakeConstraints { make in
                make.left.equalTo(SCRXFrom(16))
                if schedule.enabled {
                    if isIPad {
                        make.top.equalTo(SCRYFrom(24))
                    }else {
                        make.top.equalTo(SCRYFrom(16))
                    }
                }else {
                    make.centerY.equalToSuperview()
                }
                make.width.lessThanOrEqualTo(SCRXFrom(228))
            }
            
            
            var action = ""
            switch schedule.action {
            case .turnOn:
               action = "AUTO/ON".localizedString
            case .turnOff:
                action = "action_OFF".localizedString
            case .sceneRecall:
                action = "action_reall_scene".localizedString
            case .noAction:
                action = "action_none".localizedString
            }
            actionLabel.text = "\("action".localizedString): " + action
            
            fadeTimeLabel.text = "\("fade_time".localizedString): " + "\(schedule.fadeTime)s"
            
            if schedule.getNeedSyncDatas().isEmpty() {
                failedImageView.isHidden = true
            }else {
                failedImageView.isHidden = false
            }
            
        }
    }
    
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        layer.cornerRadius = SCRYFrom(10)
        layer.shadowColor = RGB(0, 0, 0, 0.05).cgColor
        layer.shadowOffset = CGSizeMake(0,3)
        layer.shadowOpacity = 1
        layer.shadowRadius = 5
        
        backgroundColor = .white
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func enableBtnAction() {
        enabledActionCallback?(!enableSwitch.isOn)
    }
    
    private func setupUI() {
        
        nameLabel = UILabel(text: "Schedule 1", textColor: TextBlack_Color, fontSize: 16, fontWeight: .light)
        contentView.addSubview(nameLabel)
        nameLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            if isIPad {
                make.top.equalTo(SCRYFrom(24))
            }else {
                make.top.equalTo(SCRYFrom(16))
            }
            make.width.lessThanOrEqualTo(SCRXFrom(228))
        }
        
        enableSwitch = UISwitch()
        enableSwitch.onTintColor = Bar_Color
        enableSwitch.tintColor = RGB(207, 207, 207)
        contentView.addSubview(enableSwitch)
        enableSwitch.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.centerY.equalTo(nameLabel)
        }
        
        enableBtn = UIButton(target: self, action: #selector(enableBtnAction))
        enableSwitch.addSubview(enableBtn)
        enableBtn.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        detailView = UIView()
        contentView.addSubview(detailView)
        detailView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.bottom.equalTo(SCRYFrom(-20))
        }
        
        weeksDayLabel = UILabel(text: "Mo, Tu, We, Th, Fr, Sa, Su", textColor: SubText_Color, fontSize: 14, fontWeight: .light)
        detailView.addSubview(weeksDayLabel)
        weeksDayLabel.snp.makeConstraints { make in
            make.left.equalTo(nameLabel)
            make.right.equalTo(detailView.snp.centerX)
            make.top.equalToSuperview()
        }
        
        timeLabel = UILabel(text: "9:14 AM", textColor: SubText_Color, fontSize: 14, fontWeight: .light)
        detailView.addSubview(timeLabel)
        timeLabel.snp.makeConstraints { make in
            make.left.equalTo(detailView.snp.centerX).offset(SCRXFrom(20))
            make.right.equalTo(SCRXFrom(-20))
        }
        
        actionLabel = UILabel(text: "Action: ON", textColor: SubText_Color, fontSize: 14, fontWeight: .light)
        detailView.addSubview(actionLabel)
        actionLabel.snp.makeConstraints { make in
            make.left.equalTo(weeksDayLabel)
            make.top.equalTo(weeksDayLabel.snp.bottom).offset(SCRYFrom(15))
            make.bottom.equalToSuperview()
        }
        
        fadeTimeLabel = UILabel(text: "Fade time: 5s", textColor: SubText_Color, fontSize: 14, fontWeight: .light)
        detailView.addSubview(fadeTimeLabel)
        fadeTimeLabel.snp.makeConstraints { make in
            make.left.right.equalTo(timeLabel)
            make.centerY.equalTo(actionLabel)
        }
        
        failedImageView = UIImageView(image: UIImage(named: "schedule_tips"))
        failedImageView.isHidden = true
        contentView.addSubview(failedImageView)
        failedImageView.snp.makeConstraints { make in
            make.right.equalTo(enableSwitch.snp.left).offset(SCRXFrom(-8))
            make.centerY.equalTo(enableSwitch)
        }
    }
    
}
