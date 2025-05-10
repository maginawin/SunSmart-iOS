//
//  EnergyTimeSeriesDataExportView.swift
//  SunSmart
//
//  Created by yuankehong on 2025/4/29.
//

import UIKit

class EnergyTimeSeriesDataExportView: UIView {

    private var titleLabel: UILabel!
    private var exportRangeLabel: UILabel!
    var exportRangeBtn: UIButton!
    var exportRangeEditBtn: UIButton!
    private var buildingTypeLabel: UILabel!
    var buildingTypeBtn: UIButton!
    private var startDateLabel: UILabel!
    var startDateBtn: UIButton!
    private var endDateLabel: UILabel!
    var endDateBtn: UIButton!
    private var guideView: TimeSeriesDataGuideView!
    var exportBtn: UIButton!
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        backgroundColor = .white
        layer.cornerRadius = SCRYFrom(10)
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        updateBtnEdgeInsets(exportRangeBtn)
        updateBtnEdgeInsets(buildingTypeBtn)
        updateBtnEdgeInsets(startDateBtn)
        updateBtnEdgeInsets(endDateBtn)
    }
    
    private func updateBtnEdgeInsets(_ button: UIButton) {
        
        let spacing = SCRXFrom(8)
        let imageW = button.imageView?.frame.width ?? 0
        button.contentHorizontalAlignment = .left
        button.imageEdgeInsets = UIEdgeInsets(top: 0, left: button.width - imageW - 2, bottom: 0, right: 0)
        button.titleEdgeInsets = UIEdgeInsets(top: 0, left: spacing - imageW, bottom: 0, right: imageW + spacing)
    }
    
    private func setupUI() {
        
        titleLabel = UILabel(text: "energy_export_title".localizedString, textColor: TextBlack_Color, fontSize: 14)
        addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.equalTo(SCRYFrom(14))
        }
        
        exportRangeLabel = UILabel(text: "export_range:".localizedString, textColor: SubText_Color, fontSize: 14, fontWeight: .light)
        addSubview(exportRangeLabel)
        exportRangeLabel.snp.makeConstraints { make in
            make.left.equalTo(titleLabel)
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(24))
        }
        
        exportRangeBtn = UIButton(title: "space".localizedString, titleSize: 13, titleWeight: .light, titleColor: TextBlack_Color, normalImageName: "arrow_down_small")
        exportRangeBtn.backgroundColor = Background_Color
        exportRangeBtn.layer.cornerRadius = SCRYFrom(5)
        addSubview(exportRangeBtn)
        exportRangeBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.centerY.equalTo(exportRangeLabel)
            make.width.equalTo(SCRXFrom(156))
            make.height.equalTo(SCRYFrom(32))
        }
        
        exportRangeEditBtn = UIButton(normalImageName: "edit_icon")
        exportRangeEditBtn.isHidden = true
        addSubview(exportRangeEditBtn)
        exportRangeEditBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-17))
            make.centerY.equalTo(exportRangeBtn)
        }
        
        buildingTypeLabel = UILabel(text: "building_type:".localizedString, textColor: SubText_Color, fontSize: 14, fontWeight: .light)
        addSubview(buildingTypeLabel)
        buildingTypeLabel.snp.makeConstraints { make in
            make.left.equalTo(exportRangeLabel)
            make.top.equalTo(exportRangeBtn.snp.bottom).offset(SCRYFrom(15))
        }
        
        buildingTypeBtn = UIButton(title: "automotive_facility".localizedString, titleSize: 13, titleWeight: .light, titleColor: TextBlack_Color, normalImageName: "arrow_down_small")
        buildingTypeBtn.backgroundColor = Background_Color
        buildingTypeBtn.layer.cornerRadius = SCRYFrom(5)
        addSubview(buildingTypeBtn)
        buildingTypeBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.centerY.equalTo(buildingTypeLabel)
            make.width.equalTo(SCRXFrom(156))
            make.height.equalTo(SCRYFrom(32))
        }
        
        startDateLabel = UILabel(text: "export_start_date:".localizedString, textColor: SubText_Color, fontSize: 14, fontWeight: .light)
        addSubview(startDateLabel)
        startDateLabel.snp.makeConstraints { make in
            make.left.equalTo(buildingTypeLabel)
            make.top.equalTo(buildingTypeBtn.snp.bottom).offset(SCRYFrom(15))
        }
        
        startDateBtn = UIButton(title: "2025-02-18", titleSize: 13, titleWeight: .light, titleColor: TextBlack_Color, normalImageName: "calendar")
        startDateBtn.backgroundColor = Background_Color
        startDateBtn.layer.cornerRadius = SCRYFrom(5)
        startDateBtn.layer.borderColor = RGB(220, 220, 220).cgColor
        startDateBtn.layer.borderWidth = 0.5
        addSubview(startDateBtn)
        startDateBtn.snp.makeConstraints { make in
            make.right.width.height.equalTo(buildingTypeBtn)
            make.top.equalTo(buildingTypeBtn.snp.bottom).offset(SCRYFrom(8))
        }
        
        endDateLabel = UILabel(text: "export_end_date:".localizedString, textColor: SubText_Color, fontSize: 14, fontWeight: .light)
        addSubview(endDateLabel)
        endDateLabel.snp.makeConstraints { make in
            make.left.equalTo(startDateLabel)
            make.top.equalTo(startDateBtn.snp.bottom).offset(SCRYFrom(15))
        }
        
        endDateBtn = UIButton(title: "2025-10-18", titleSize: 13, titleWeight: .light, titleColor: TextBlack_Color, normalImageName: "calendar")
        endDateBtn.backgroundColor = Background_Color
        endDateBtn.layer.cornerRadius = SCRYFrom(5)
        endDateBtn.layer.borderColor = RGB(220, 220, 220).cgColor
        endDateBtn.layer.borderWidth = 0.5
        addSubview(endDateBtn)
        endDateBtn.snp.makeConstraints { make in
            make.right.width.height.equalTo(buildingTypeBtn)
            make.top.equalTo(startDateBtn.snp.bottom).offset(SCRYFrom(8))
        }
        
        guideView = TimeSeriesDataGuideView()
        guideView.sourceImageView.image = UIImage(named: "energy_phone")
        guideView.destinationImageView.image = UIImage(named: "energy_csv")
        addSubview(guideView)
        guideView.snp.makeConstraints { make in
            make.left.equalTo(endDateLabel)
            make.top.equalTo(endDateBtn.snp.bottom).offset(SCRYFrom(12))
            make.width.equalTo(SCRXFrom(180))
            make.height.equalTo(SCRYFrom(32))
        }
        
        exportBtn = UIButton(title: "export".localizedString, titleSize: 14, titleWeight: .light, titleColor: .white)
        exportBtn.layer.cornerRadius = SCRYFrom(5)
        exportBtn.backgroundColor = Bar_Color
        addSubview(exportBtn)
        exportBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.bottom.height.equalTo(guideView)
            make.width.equalTo(SCRXFrom(114))
        }
        
    }

}
