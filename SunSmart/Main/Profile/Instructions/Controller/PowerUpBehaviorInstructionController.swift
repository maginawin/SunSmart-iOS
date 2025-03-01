//
//  PowerUpBehaviorInstructionController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/2/28.
//

import UIKit

class PowerUpBehaviorInstructionController: UIViewController {

    private var contentLabel: UILabel!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.isModalInPresentation = true
        title = "power_up_behavior_instruction_title".localizedString
        navigationController?.setNavigationBarBackgroundColor(color: Background_Color)
        
        view.backgroundColor = Background_Color
        navigationItem.leftBarButtonItem = UIBarButtonItem()
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(named: "close")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(back))
        
        setupUI()
    }
    
    @objc private func back() {
        navigationController?.popViewController(animated: true)
    }
    
    private func setupUI() {

        let offItem = initPowerStateItem(name: "off".localizedString, imageName: "power_state_off")
        view.addSubview(offItem)
        offItem.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(25))
            make.top.equalTo(view.safeAreaLayoutGuide).offset(SCRYFrom(24))
//            make.top.equalTo(SCRYFrom(24) + (navigationController?.navigationBar.height ?? kNavigationHeight))
            make.width.equalTo(SCRXFrom(66))
            make.height.equalTo(SCRYFrom(102))
        }
        
        let restoreItem = initPowerStateItem(name: "restore".localizedString, imageName: "power_state_restore")
        view.addSubview(restoreItem)
        restoreItem.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.width.height.centerY.equalTo(offItem)
        }
        
        let definedItem = initPowerStateItem(name: "defined".localizedString, imageName: "power_state_defined")
        view.addSubview(definedItem)
        definedItem.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-27))
            make.width.height.centerY.equalTo(offItem)
        }
        
        contentLabel = UILabel(text: "", textColor: SubText_Color, fontSize: 14, fontWeight: .light, fit: false)
        contentLabel.numberOfLines = 0
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 3
        
        let text = "power_up_behavior_instruction_desc".localizedString
        let textAttStr = NSMutableAttributedString(string: text, attributes: [.paragraphStyle: paragraphStyle])
        textAttStr.addAttributes([.foregroundColor: TextBlack_Color, .font: FONTS(14)], range: (text as NSString).range(of: "keep_light_off".localizedString))
        textAttStr.addAttributes([.foregroundColor: TextBlack_Color, .font: FONTS(14)], range: (text as NSString).range(of: "\n" + "restore".localizedString))
        textAttStr.addAttributes([.foregroundColor: TextBlack_Color, .font: FONTS(14)], range: (text as NSString).range(of: "defined_light_level".localizedString))
        
        contentLabel.attributedText = textAttStr
        view.addSubview(contentLabel)
        contentLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(30))
            make.right.equalTo(SCRXFrom(-32))
            make.top.equalTo(offItem.snp.bottom).offset(SCRYFrom(52))
        }
        
    }
    
    private func initPowerStateItem(name: String, imageName: String) -> UIView {
        
        let item = UIView()
        
        let imageView = UIImageView(image: UIImage(named: imageName))
        item.addSubview(imageView)
        imageView.snp.makeConstraints { make in
            make.left.right.top.equalToSuperview()
            make.height.equalTo(imageView.snp.width)
        }
        
        let nameBtn = UIButton(title: name, titleSize: 14, titleColor: TextBlack_Color, fit: false)
        nameBtn.backgroundColor = .white
        nameBtn.layer.shadowOffset = CGSize(width: 0, height: 2)
        nameBtn.layer.shadowColor = RGB(0, 0, 0, 0.1).cgColor
        nameBtn.layer.shadowRadius = 5
        nameBtn.layer.cornerRadius = 5
        nameBtn.titleLabel?.textAlignment = .center
        item.addSubview(nameBtn)
        nameBtn.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(SCRYFrom(24))
        }
        
        return item
    }
  
}
