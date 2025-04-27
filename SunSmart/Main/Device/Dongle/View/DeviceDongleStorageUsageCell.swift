//
//  DeviceDongleStorageUsageCell.swift
//  SunSmart
//
//  Created by yuankehong on 2025/4/22.
//

import UIKit

class DeviceDongleStorageUsageCell: UITableViewCell {

    private var iconImageView: UIImageView!
    var progressView: CustomProgressView!
    var progressLabel: UILabel!
    var clearBtn: UIButton!
    var storageClearCallback: (()->Void)?
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        selectionStyle = .none
        
        setupUI()
    }
    
    
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        progressLabel.snp.updateConstraints { make in
            make.centerX.equalTo(progressView.snp.left).offset(progressView.progressView.frame.maxX)
        }
    }
    
    @objc private func clearBtnAction() {
        storageClearCallback?()
    }
    
    private func setupUI() {
        
        iconImageView = UIImageView(image: UIImage(named: "dongle_sd"))
        iconImageView.sizeToFit()
        contentView.addSubview(iconImageView)
        iconImageView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.centerY.equalToSuperview()
            make.width.equalTo(iconImageView.width)
        }
        
        clearBtn = UIButton(normalImageName: "dongle_storage_clear", target: self, action: #selector(clearBtnAction))
        clearBtn.sizeToFit()
        contentView.addSubview(clearBtn)
        clearBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-12))
            make.centerY.equalToSuperview()
            make.width.equalTo(clearBtn.width)
        }
        
        progressView = CustomProgressView()
        progressView.cornerRadius = 2
        progressView.trackColor = RGB(225, 227, 234)
        progressView.progressColor = Bar_Color
        progressView.progress = 0
        contentView.addSubview(progressView)
        progressView.snp.makeConstraints { make in
            make.left.equalTo(iconImageView.snp.right).offset(SCRXFrom(16))
            make.right.equalTo(clearBtn.snp.left).offset(SCRXFrom(-20))
            make.centerY.equalToSuperview()
            make.height.equalTo(4)
        }
        
        progressLabel = UILabel(text: "70%", textColor: TextBlack_Color, fontSize: 14)
        contentView.addSubview(progressLabel)
        progressLabel.snp.makeConstraints { make in
            make.centerX.equalTo(progressView.snp.left).offset(0)
            make.bottom.equalTo(progressView.snp.top).offset(SCRYFrom(-10))
        }
        
        
    }
}
