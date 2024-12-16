//
//  BLEUpgradeInstructionsController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/8/30.
//

import UIKit

class BLEUpgradeInstructionsController: UIViewController {
    
    struct InstructionsData {
        /// 图标
        let iconName: String
        /// 名称
        let name: String
        /// 描述
        let message: String
        /// 是否展示箭头
        let showArrow: Bool
        /// 箭头位置
        let arrowX: CGFloat
        /// 内容宽度比例
        let ratio: CGFloat
    }
    
    
    private var headerView: UIView!
    private var serverBtn: UIButton!
    private var initiatorBtn: UIButton!
    private var updatingNodeBtn: UIButton!
    private var arrowImageView1: UIImageView!
    private var arrowImageView2: UIImageView!
    
    private var instructionLabel: UILabel!
    
    
    var datas: [InstructionsData] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = Background_Color
        
        setupUI()
        
        let instrucutionAttStr = NSMutableAttributedString()
        
        datas.forEach { data in
            let serverAttStr = NSMutableAttributedString(string: data.message)
            serverAttStr.addAttributes([.font: FONTS(SCRXFrom(13)), .foregroundColor: TextBlack_Color], range: (serverAttStr.string as NSString).range(of: data.name))
            instrucutionAttStr.append(serverAttStr)
        }
        
//        let serverAttStr = NSMutableAttributedString(string: "server_firmware_message".localizedString + "\n\n")
//        serverAttStr.addAttributes([.font: FONTS(SCRYFrom(14)), .foregroundColor: TextBlack_Color], range: (serverAttStr.string as NSString).range(of: "server_firmware".localizedString))
//        instrucutionAttStr.append(serverAttStr)
//        
//        let initiatorAttStr = NSMutableAttributedString(string: "initiator_message".localizedString + "\n\n")
//        initiatorAttStr.addAttributes([.font: FONTS(SCRYFrom(14)), .foregroundColor: TextBlack_Color], range: (initiatorAttStr.string as NSString).range(of: "initiator".localizedString))
//        instrucutionAttStr.append(initiatorAttStr)
//        
//        let updateAttStr = NSMutableAttributedString(string: "updating_node_message".localizedString + "\n\n")
//        updateAttStr.addAttributes([.font: FONTS(SCRYFrom(14)), .foregroundColor: TextBlack_Color], range: NSRange(location: 0, length: "updating_node".localizedString.count))
//        instrucutionAttStr.append(updateAttStr)
//        
//        instrucutionAttStr.append(NSAttributedString(string: "ble_upgrade_instructions_message".localizedString))
        
        instructionLabel.attributedText = instrucutionAttStr
    }
    
    private func setupUI() {
        
        headerView = UIView()
        headerView.backgroundColor = .white
        headerView.layer.cornerRadius = SCRYFrom(10)
        view.addSubview(headerView)
        headerView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.right.equalTo(SCRXFrom(-20))
            make.top.equalTo(navigationController?.navigationBar.height ?? 0)
            make.height.equalTo(SCRYFrom(108))
        }
        
        var lastItemBtn: UIButton?
        datas.forEach { data in
            
            let itemBtn = UIButton(title: data.name, titleSize: SCRXFrom(12), titleWeight: .light, titleColor: TextBlack_Color, fit: false, normalImageName: data.iconName)
            itemBtn.isUserInteractionEnabled = false
            itemBtn.setImagePosition(position: .top, spacing: SCRYFrom(8))
            headerView.addSubview(itemBtn)
            itemBtn.snp.makeConstraints { make in
                if let btn = lastItemBtn {
                    make.left.equalTo(btn.snp.right)
                }else {
                    make.left.equalToSuperview()
                }
                make.width.equalTo(headerView.snp.width).multipliedBy(data.ratio)
                make.centerY.equalToSuperview()
            }
            
            if data.showArrow {
                let arrowImageView = UIImageView(image: UIImage(named: "step_arrow_right"))
                headerView.addSubview(arrowImageView)
                arrowImageView.snp.makeConstraints { make in
                    make.left.equalTo(data.arrowX)
                    make.top.equalTo(SCRYFrom(37))
                }
            }
            lastItemBtn = itemBtn
        }
        
        
//        serverBtn = UIButton(title: "server_firmware".localizedString, titleSize: 13, titleWeight: .light, titleColor: TextBlack_Color, normalImageName: "server_download")
//        serverBtn.isUserInteractionEnabled = false
//        serverBtn.setImagePosition(position: .top, spacing: SCRYFrom(8))
//        headerView.addSubview(serverBtn)
//        serverBtn.snp.makeConstraints { make in
//            make.left.equalToSuperview()
//            make.width.equalTo(headerView.snp.width).multipliedBy(0.333)
//            make.centerY.equalToSuperview()
//        }
//        
//        initiatorBtn = UIButton(title: "initiator".localizedString, titleSize: 13, titleWeight: .light, titleColor: TextBlack_Color, normalImageName: "initiator")
//        initiatorBtn.isUserInteractionEnabled = false
//        initiatorBtn.setImagePosition(position: .top, spacing: SCRYFrom(8))
//        headerView.addSubview(initiatorBtn)
//        initiatorBtn.snp.makeConstraints { make in
//            make.center.equalToSuperview()
//            make.width.equalTo(serverBtn)
//        }
//        
//        updatingNodeBtn = UIButton(title: "updating_node".localizedString, titleSize: 13, titleWeight: .light, titleColor: TextBlack_Color, normalImageName: "single_device")
//        updatingNodeBtn.isUserInteractionEnabled = false
//        updatingNodeBtn.setImagePosition(position: .top, spacing: SCRYFrom(8))
//        headerView.addSubview(updatingNodeBtn)
//        updatingNodeBtn.snp.makeConstraints { make in
//            make.centerY.equalToSuperview()
//            make.width.equalTo(serverBtn)
//            make.right.equalToSuperview()
//        }
//        
//        arrowImageView1 = UIImageView(image: UIImage(named: "step_arrow_right"))
//        headerView.addSubview(arrowImageView1)
//        arrowImageView1.snp.makeConstraints { make in
//            make.left.equalTo(serverBtn.snp.right).offset(SCRXFrom(6))
//            make.top.equalTo(SCRYFrom(37))
//        }
//        
//        arrowImageView2 = UIImageView(image: UIImage(named: "step_arrow_right"))
//        headerView.addSubview(arrowImageView2)
//        arrowImageView2.snp.makeConstraints { make in
//            make.right.equalTo(updatingNodeBtn.snp.left).offset(SCRXFrom(-6))
//            make.top.equalTo(arrowImageView1)
//        }
        
        instructionLabel = UILabel(text: "", textColor: SubText_Color, fontSize: SCRXFrom(13), fontWeight: .light, fit: false)
        instructionLabel.numberOfLines = 0
        view.addSubview(instructionLabel)
        instructionLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(32))
            make.right.equalTo(SCRXFrom(-32))
            make.top.equalTo(headerView.snp.bottom).offset(SCRYFrom(20))
        }
        
        
    }


}
