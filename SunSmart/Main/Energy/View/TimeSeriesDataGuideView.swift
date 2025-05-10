//
//  TimeSeriesDataGuideView.swift
//  SunSmart
//
//  Created by yuankehong on 2025/4/29.
//

import UIKit

class TimeSeriesDataGuideView: UIView {
    
    var sourceImageView: UIImageView!
    var destinationImageView: UIImageView!
    var lineImageView: UIImageView!
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        layer.cornerRadius = SCRYFrom(5)
        layer.borderWidth = 0.5
        layer.borderColor = RGB(220, 220, 220).cgColor
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        
        sourceImageView = UIImageView()
        addSubview(sourceImageView)
        sourceImageView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.centerY.equalToSuperview()
            make.width.height.equalTo(20)
        }
        
        destinationImageView = UIImageView()
        addSubview(destinationImageView)
        destinationImageView.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-20))
            make.centerY.equalToSuperview()
            make.width.height.equalTo(20)
        }
        
        lineImageView = UIImageView(image: UIImage(named: "energy_import_line"))
        addSubview(lineImageView)
        lineImageView.snp.makeConstraints { make in
            make.left.equalTo(sourceImageView.snp.right).offset(SCRXFrom(3))
            make.centerY.equalToSuperview()
            make.right.equalTo(destinationImageView.snp.left).offset(SCRXFrom(-2))
        }
        
        
    }
    
}

