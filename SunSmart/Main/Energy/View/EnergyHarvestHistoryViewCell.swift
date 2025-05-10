//
//  EnergyHarvestHistoryViewCell.swift
//  SunSmart
//
//  Created by yuankehong on 2025/5/6.
//

import UIKit

class EnergyHarvestHistoryViewCell: UITableViewCell {

    var selectImageView: UIImageView!
    var fileNameLabel: UILabel!
    var exportBtn: UIButton!
    var lineView: UIView!
    
    var isSelect: Bool = false {
        didSet {
            selectImageView.image = UIImage(named: isSelect ? "device_select" : "device_select_un")
        }
    }
    
    var exportCallback: (()->Void)?
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        selectionStyle = .none
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func exportBtnAction() {
        exportCallback?()
    }
    
    private func setupUI() {
        
        selectImageView = UIImageView(image: UIImage(named: "device_select_un"))
        contentView.addSubview(selectImageView)
        selectImageView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.centerY.equalToSuperview()
        }
        
        fileNameLabel = UILabel(text: "Static Data 2-18-2025 10:30 PM", textColor: TextBlack_Color, fontSize: 15, fontWeight: .light, fit: false)
        contentView.addSubview(fileNameLabel)
        fileNameLabel.snp.makeConstraints { make in
            make.left.equalTo(selectImageView.snp.right).offset(SCRXFrom(8))
            make.centerY.equalToSuperview()
        }
        
        exportBtn = UIButton(normalImageName: "energy_export", target: self, action: #selector(exportBtnAction))
        contentView.addSubview(exportBtn)
        exportBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-8))
            make.centerY.equalToSuperview()
        }
        
        lineView = UIView()
        lineView.backgroundColor = Line_Color1
        contentView.addSubview(lineView)
        lineView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(14.6))
            make.right.bottom.equalToSuperview()
            make.height.equalTo(0.5)
        }
        
    }
    
}
