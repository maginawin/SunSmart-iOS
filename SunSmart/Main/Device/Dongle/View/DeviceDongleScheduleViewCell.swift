//
//  DeviceDongleScheduleViewCell.swift
//  SunSmart
//
//  Created by yuankehong on 2025/4/21.
//

import UIKit

class DeviceDongleScheduleViewCell: UITableViewCell {

    var selectImageView: UIImageView!
    var iconImageView: UIImageView!
    var timeLabel: UILabel!
    var stateLabel: UILabel!
    var lineView: UIView!
    
    var schedule: DeviceDongleData.CollectionSchedule! {
        didSet {
            
            timeLabel.text = String.dateConvert(timestamp: "\(schedule.timestamp)", dateFormat: "M/d/yyyy hh:mm a")
            stateLabel.text = schedule.state == .enable ? "enable".localizedString : "disable".localizedString
            switch schedule.selectState {
            case .none:
                selectImageView.isHidden = true
            case .unselect:
                selectImageView.isHidden = false
                selectImageView.image = UIImage(named: "device_select_un")
            case .selected:
                selectImageView.isHidden = false
                selectImageView.image = UIImage(named: "device_select")
            }
            
            iconImageView.snp.updateConstraints { make in
                if schedule.selectState == .none {
                    make.left.equalTo(SCRXFrom(16))
                }else {
                    make.left.equalTo(SCRXFrom(44))
                }
            }
            
        }
    }
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        selectionStyle = .none
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        
        selectImageView = UIImageView(image: UIImage(named: "device_select_un"))
        selectImageView.isHidden = true
        contentView.addSubview(selectImageView)
        selectImageView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(10))
            make.centerY.equalToSuperview()
        }
        
        iconImageView = UIImageView(image: UIImage(named: "dongle_schedule"))
        contentView.addSubview(iconImageView)
        iconImageView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.centerY.equalToSuperview()
        }
        
        timeLabel = UILabel(text: "6/10/2025 06:02 PM", textColor: TextBlack_Color, fontSize: 14, fontWeight: .light)
        contentView.addSubview(timeLabel)
        timeLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.centerY.equalToSuperview()
        }
        
        stateLabel = UILabel(text: "Disable", textColor: SubText_Color, fontSize: 14, fontWeight: .light)
        contentView.addSubview(stateLabel)
        stateLabel.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.centerY.equalToSuperview()
        }
        
        lineView = UIView()
        lineView.backgroundColor = Line_Color
        contentView.addSubview(lineView)
        lineView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(14.6))
            make.right.bottom.equalToSuperview()
            make.height.equalTo(1)
        }
    }
}


class DeviceDongleScheduleEmptyCell: UITableViewCell {
    
    var titleLabel: UILabel!
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        selectionStyle = .none
        titleLabel = UILabel(text: "no_settings".localizedString, textColor: TextBlack_Color, fontSize: 14, fontWeight: .light)
        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    
}
