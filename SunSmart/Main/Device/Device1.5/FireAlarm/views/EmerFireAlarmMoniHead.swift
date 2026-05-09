//
//  EmerFireAlarmMoniHead.swift
//  SunSmart
//
//  Created by Plato Jobs on 2026/4/21.
//

//监控页顶部的状态警示操作
import UIKit

class EmerFireAlarmMoniHead: UIView {
    
    
    var warningAction: (() -> Void)?
    
    lazy var icon : UIButton = {
        let icon = UIButton(title: "", titleSize: nil, titleWeight: nil, titleColor: nil, fit: true, normalImageName:"Frame", selectedImageName: "", target: self, action: #selector(warning))
        return icon
    }()
    var lab : UILabel = {
        let view = UILabel()
        view.font = UIFont.systemFont(ofSize: FontFit(14))
        view.textAlignment = .center
        view.textColor = UIColor(red: 1, green: 0.281, blue: 0.194, alpha: 1)
        view.attributedText = NSMutableAttributedString(string: "Fire Alarm Emergency", attributes: [NSAttributedString.Key.underlineStyle: NSUnderlineStyle.single.rawValue])
        return view
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func setupUI(){
        addSubview(icon)
        addSubview(lab)
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(warning))
        addGestureRecognizer(tapGesture)
        icon.snp.makeConstraints { make in
            make.left.equalToSuperview().offset(SCRYFit(30))
            make.centerY.equalToSuperview()
            make.width.height.equalTo(23)
        }
        lab.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.centerY.equalToSuperview()
        }
    }
    
    @objc func warning(){
        warningAction?()
    }
    
    func config(statusLab: String, textColor: UIColor? = nil){
        lab.textColor = textColor ?? UIColor(red: 1, green: 0.281, blue: 0.194, alpha: 1)
        lab.attributedText = NSMutableAttributedString(string: statusLab, attributes: [NSAttributedString.Key.underlineStyle: NSUnderlineStyle.single.rawValue])
    }
}
