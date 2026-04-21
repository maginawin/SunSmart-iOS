//
//  EmerFireAlarmMoniHead.swift
//  SunSmart
//
//  Created by Plato Jobs on 2026/4/21.
//

import UIKit

class EmerFireAlarmMoniHead: UIView {
    lazy var icon : UIImageView = {
        let icon = UIImageView()
        icon.image = UIImage(named: "Frame")
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
    func config(statusLab: String){
        lab.text = statusLab
      //view.attributedText = NSMutableAttributedString(string: "Unlinked", attributes: [NSAttributedString.Key.underlineStyle: NSUnderlineStyle.single.rawValue])
      
    }
}
