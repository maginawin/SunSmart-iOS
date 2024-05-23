//
//  DaylightSensorInstructionsHeaderView.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/2/28.
//

import UIKit

class DaylightSensorInstructionsHeaderView: UICollectionReusableView {
        
    private var titleLabel: UILabel!
    private var itemContentView: UIView!
    
    private var itemDatas: [(imageName: String, name: String, bgImageName: String?)] = [
        ("profile_device_luminaire", "light_without_sensor".localizedString, nil),
        ("daylight_light_sensor", "light_with_sensor".localizedString, nil),
        ("daylight_standalone_sensor", "standalone_daylight_sensor".localizedString, nil),
        ("light_with_sensor", "selected_light_with_sensor".localizedString, "sensor_circle_select"),
        ("profile_device_lightsensor", "selected_standalone_daylight_sensor".localizedString, "sensor_circle_select"),
        ("sensor_square_select", "control_range_of_the_selected_device".localizedString, nil)
    ]
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        
        titleLabel = UILabel(text: "daylight_sensor_instruction_title".localizedString, textColor: TextBlack_Color, fontSize: 14, fontWeight: .light, fit: false)
        titleLabel.numberOfLines = 0
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 4
        let attStr = NSAttributedString(string: "daylight_sensor_instruction_title".localizedString, attributes: [.paragraphStyle: paragraphStyle])
        titleLabel.attributedText = attStr
        
        addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.top.equalTo(SCRYFrom(6))
            make.right.equalTo(SCRXFrom(-20))
        }
        
        itemContentView = UIView()
        addSubview(itemContentView)
        itemContentView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(17))
            make.right.equalTo(SCRXFrom(17))
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(13))
        }
        
        for index in 0..<itemDatas.count {
            let data = itemDatas[index]
            
            let width = SCRXFrom(161)
            let height = SCRYFrom(36)
            let row = index / 2
            let col = index % 2
            
            let itemView = UIView(frame: CGRect(x: CGFloat(col) * (width + SCRXFrom(23)), y: (height + SCRYFrom(8)) * CGFloat(row), width: width, height: height))
            itemContentView.addSubview(itemView)
            
            
            let btn = UIButton(normalImageName: data.imageName)
//            btn.imageView?.width = 30
            btn.isUserInteractionEnabled = false
            
            if let imageName = data.bgImageName {
                btn.setBackgroundImage(UIImage(named: imageName), for: .normal)
            }
            itemView.addSubview(btn)
            btn.snp.makeConstraints { make in
                make.left.equalToSuperview()
                make.width.height.equalTo(SCRYFrom(30))
                make.centerY.equalToSuperview()
            }
            
            let label = UILabel(text: data.name, textColor: SubText_Color, fontSize: 14, fontWeight: .light, fit: false)
            label.numberOfLines = 2
            label.adjustsFontSizeToFitWidth = true
            itemView.addSubview(label)
            label.snp.makeConstraints { make in
                make.left.equalTo(btn.snp.right).offset(SCRXFrom(8))
                make.right.equalToSuperview()
                make.centerY.equalToSuperview()
            }
            
        }
        
        
    }
    
}
