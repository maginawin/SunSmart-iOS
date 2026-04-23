//
//  EmerFireAlarmDevicesRepairView.swift
//  SunSmart
//
//  Created by Plato Jobs on 2026/4/22.
//

import UIKit

class EmerFireAlarmDevicesRepairView: UIView {

    var repairView: UIView!
    var repairCountLabel: UILabel!
    var repairBtn: UIButton!
    var repairAction: (() -> Void)?
    override init(frame: CGRect) {
        super.init(frame: frame)
        setUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func setUI(){
        repairView = UIView()
        repairView.layer.cornerRadius = SCRYFrom(8)
        repairView.layer.shadowColor = RGB(0, 0, 0, 0.1).cgColor
        repairView.layer.shadowOpacity = 1
        repairView.layer.shadowRadius = 6
        repairView.layer.shadowOffset = CGSize(width: 0, height: -2)
        repairView.layer.shadowPath = UIBezierPath(rect: CGRect(x: 0, y: -2, width: self.width, height: SCRYFrom(11))).cgPath
        repairView.isHidden = false
        repairView.backgroundColor = .white
        addSubview(repairView)
        repairView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        repairCountLabel = UILabel(text: "", textColor: TextBlack_Color, fontSize: 16, fontWeight: .light)
        repairView.addSubview(repairCountLabel)
        repairCountLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.centerY.equalToSuperview()
        }
        repairBtn = UIButton(title: "repair".localizedString, titleSize: 14, titleWeight: .light, titleColor: .white, target: self, action: #selector(repairBtnClick))
        repairBtn.layer.cornerRadius = SCRYFrom(5)
        repairBtn.backgroundColor = Bar_Color
        repairView.addSubview(repairBtn)
        repairBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.centerY.equalToSuperview()
            make.width.equalTo(SCRXFrom(80))
            make.height.equalTo(SCRYFrom(32))
        }
    }
    
    @objc func repairBtnClick(){
        repairAction?()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        repairView.layer.shadowPath = UIBezierPath(rect: CGRect(x: 0, y: -2, width: bounds.width, height: SCRYFrom(11))).cgPath
    }
    
}
