//
//  DeviceRatedPowerCalibrationHeaderView.swift
//  SunSmart
//
//  Created by yuankehong on 2025/12/6.
//

import UIKit

class DeviceRatedPowerCalibrationHeaderView: UIView {

    private var step1TitleLabel: UILabel!
    private var step1NoteLabel: UILabel!
    var dimSaveBtn: UIButton!
    
    private var step2TitleLabel: UILabel!
    var segmentControl: CustomSegmentedControl!
    var dimSaveNoteLabel: UILabel!

    override init(frame: CGRect) {
        super.init(frame: frame)
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        
        step1TitleLabel = UILabel(text: "calibration_step_1_title".localizedString, textColor: TextBlack_Color, fontSize: 15, fit: false)
        addSubview(step1TitleLabel)
        step1TitleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16)).priority(.high)
            make.right.equalTo(SCRXFrom(-16)).priority(.high)
            make.top.equalTo(SCRYFrom(8)).priority(.high)
        }
        
        dimSaveBtn = UIButton(title: "Dim&Save".localizedString, titleSize: 12, titleColor: ImportantText_Color)
        dimSaveBtn.backgroundColor = .white
        dimSaveBtn.layer.cornerRadius = SCRYFrom(10)
        dimSaveBtn.layer.borderWidth = 0.5
        dimSaveBtn.layer.borderColor = Border_Color.cgColor
        addSubview(dimSaveBtn)
        dimSaveBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16)).priority(.high)
            make.top.equalTo(step1TitleLabel.snp.bottom).offset(SCRYFrom(9)).priority(.high)
            make.width.equalTo(SCRXFrom(80))
            make.height.equalTo(SCRYFrom(30))
        }
        
        step1NoteLabel = UILabel(text: "calibration_step_1_note".localizedString, textColor: SubText_Color, fontSize: 12, fontWeight: .light)
        step1NoteLabel.numberOfLines = 0
        addSubview(step1NoteLabel)
        step1NoteLabel.snp.makeConstraints { make in
            make.left.equalTo(step1TitleLabel)
            make.right.equalTo(dimSaveBtn.snp.left).offset(SCRXFrom(-21)).priority(.high)
            make.centerY.equalTo(dimSaveBtn)
        }
        
        step2TitleLabel = UILabel(text: "calibration_step_2_title".localizedString, textColor: TextBlack_Color, fontSize: 15, fit: false)
        addSubview(step2TitleLabel)
        step2TitleLabel.snp.makeConstraints { make in
            make.left.right.equalTo(step1TitleLabel)
            make.top.equalTo(dimSaveBtn.snp.bottom).offset(SCRYFrom(16)).priority(.high)
        }
        
        segmentControl = CustomSegmentedControl(frame: .zero, titles: ["set_separately".localizedString, "set_all".localizedString])
        segmentControl.margin = 2
        segmentControl.titleFont = UIFont.systemFont(ofSize: FontFit(14), weight: .light)
        addSubview(segmentControl)
        segmentControl.snp.makeConstraints { make in
            make.left.right.equalTo(step2TitleLabel)
            make.top.equalTo(step2TitleLabel.snp.bottom).offset(SCRYFrom(8)).priority(.high)
            make.height.equalTo(SCRYFrom(36))
        }
        
        dimSaveNoteLabel = UILabel(text: "calibration_dim_save_note".localizedString, textColor: SubText_Color, fontSize: 12, fontWeight: .light, fit: false)
        dimSaveNoteLabel.textAlignment = .center
        addSubview(dimSaveNoteLabel)
        dimSaveNoteLabel.snp.makeConstraints { make in
            make.left.right.equalTo(step2TitleLabel)
            make.top.equalTo(segmentControl.snp.bottom).offset(SCRYFrom(8)).priority(.high)
        }
        
    }
    
}
