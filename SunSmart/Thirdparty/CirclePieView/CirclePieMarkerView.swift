//
//  CirclePieMarkerView.swift
//  PieChart
//
//  Created by yuankehong on 2025/5/14.
//

import UIKit

class CirclePieMarkerView: UIView {

    var pointsView: UIView!
    var titleLabel: UILabel!
    var percentLabel: UILabel!

    override init(frame: CGRect) {
        super.init(frame: frame)
        
        backgroundColor = .white
        layer.cornerRadius = 5
        layer.borderWidth = 0.5
        layer.borderColor = UIColor(red: 220 / 255.0, green: 220 / 255.0, blue: 220 / 255.0, alpha: 0.2).cgColor
        layer.shadowColor = UIColor.black.withAlphaComponent(0.1).cgColor
        layer.shadowOffset = CGSize(width: 1, height: 5)
        layer.shadowOpacity = 1
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func updateData(data: LYAnglePercent, color: UIColor) {
        
        pointsView.backgroundColor = color
        titleLabel.text = data.title
        percentLabel.text = "\(Int(data.percentLength * 100.0))%"
    }
    
    private func setupUI() {
        
        pointsView = UIView()
        pointsView.layer.cornerRadius = 3
        addSubview(pointsView)
        pointsView.snp.makeConstraints { make in
            make.left.equalTo(12)
            make.centerY.equalToSuperview()
            make.width.height.equalTo(6)
        }
        
        titleLabel = UILabel()
        titleLabel.textColor = UIColor(red: 46 / 255.0, green: 49 / 255.0, blue: 93 / 255.0, alpha: 1)
        titleLabel.font = UIFont.systemFont(ofSize: 12)
        addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(pointsView.snp.right).offset(6)
            make.centerY.equalTo(pointsView)
        }
        
        percentLabel = UILabel()
        percentLabel.textColor = UIColor(red: 46 / 255.0, green: 49 / 255.0, blue: 93 / 255.0, alpha: 1)
        percentLabel.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        addSubview(percentLabel)
        percentLabel.snp.makeConstraints { make in
            make.left.equalTo(titleLabel.snp.right).offset(8)
            make.centerY.equalTo(titleLabel)
            make.right.equalTo(-12)
        }
    }
    
}
