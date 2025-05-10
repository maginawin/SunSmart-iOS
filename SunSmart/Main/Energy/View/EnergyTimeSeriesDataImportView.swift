//
//  EnergyTimeSeriesDataImportView.swift
//  SunSmart
//
//  Created by yuankehong on 2025/4/29.
//

import UIKit

class EnergyTimeSeriesDataImportView: UIView {

    private var titleLabel: UILabel!
    var noDataLabel: UILabel!
    var fileDataView: UIView!
    var fileImageView: UIImageView!
    var fileNameLabel: UILabel!
    var fileSizeLabel: UILabel!
    private var guideView: TimeSeriesDataGuideView!
    var importBtn: UIButton!
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        backgroundColor = .white
        layer.cornerRadius = SCRYFrom(10)
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        
        titleLabel = UILabel(text: "energy_import_title".localizedString, textColor: TextBlack_Color, fontSize: 14)
        addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.equalTo(SCRYFrom(14))
            make.right.equalTo(SCRXFrom(-16))
        }
        
        noDataLabel = UILabel(text: "energy_import_no_data".localizedString, textColor: SubText_Color, fontSize: 13, fontWeight: .light, fit: false)
        noDataLabel.textAlignment = .center
        addSubview(noDataLabel)
        noDataLabel.snp.makeConstraints { make in
            make.left.right.equalTo(titleLabel)
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(24))
        }
        
        fileDataView = UIView()
        fileDataView.isHidden = true
        fileDataView.backgroundColor = Background_Color
        fileDataView.layer.cornerRadius = SCRYFrom(5)
        addSubview(fileDataView)
        fileDataView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(16))
            make.right.equalTo(SCRXFrom(-10))
            make.height.equalTo(SCRYFrom(30))
        }
        
        fileImageView = UIImageView(image: UIImage(named: "energy_csv"))
        fileImageView.sizeToFit()
        fileDataView.addSubview(fileImageView)
        fileImageView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(8))
            make.centerY.equalToSuperview()
            make.width.equalTo(fileImageView.width)
        }
        
        fileNameLabel = UILabel(text: "Time Series Data 2-20-2025 10:30 PM", textColor: TextBlack_Color, fontSize: 13, fontWeight: .light)
        fileDataView.addSubview(fileNameLabel)
        fileNameLabel.snp.makeConstraints { make in
            make.left.equalTo(fileImageView.snp.right).offset(SCRXFrom(8))
            make.right.equalTo(SCRXFrom(-36))
            make.centerY.equalToSuperview()
        }
        
        fileSizeLabel = UILabel(text: "10M", textColor: TextBlack_Color, fontSize: 13, fontWeight: .light)
        fileDataView.addSubview(fileSizeLabel)
        fileSizeLabel.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-8))
            make.centerY.equalToSuperview()
        }
        
        guideView = TimeSeriesDataGuideView()
        guideView.sourceImageView.image = UIImage(named: "energy_device")
        guideView.destinationImageView.image = UIImage(named: "energy_phone")
        addSubview(guideView)
        guideView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.bottom.equalTo(SCRYFrom(-16))
            make.width.equalTo(SCRXFrom(181))
            make.height.equalTo(SCRYFrom(32))
        }
        
        importBtn = UIButton(title: "import".localizedString, titleSize: 14, titleWeight: .light, titleColor: .white)
        importBtn.layer.cornerRadius = SCRYFrom(5)
        importBtn.backgroundColor = Bar_Color
        addSubview(importBtn)
        importBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.bottom.height.equalTo(guideView)
            make.width.equalTo(SCRXFrom(114))
        }
        
    }
    
}


