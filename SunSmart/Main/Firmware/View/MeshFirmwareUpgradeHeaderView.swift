//
//  MeshFirmwareUpgradeHeaderView.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/11/4.
//

import UIKit

class MeshFirmwareUpgradeHeaderView: UIView {

    private var contentView: UIView!
    private var distributorBtn: UIButton!
    private var upgradeBtn: UIButton!
    private var nodesBtn: UIButton!
    private var promptBtn: UIButton!
    
    var promptCallback: (()->Void)?
    
    var step: MeshFirmwareUpgradeStep = .distributor {
        didSet {
            if step == .distributor {
                distributorBtn.layer.borderColor = Green_Color.cgColor
                distributorBtn.isSelected = true
                nodesBtn.layer.borderColor = Message_Color.cgColor
                nodesBtn.isSelected = false
                promptBtn.setTitle("how_to_select_a_distributor".localizedString, for: .normal)
            }else {
                distributorBtn.layer.borderColor = Message_Color.cgColor
                distributorBtn.isSelected = false
                nodesBtn.layer.borderColor = Green_Color.cgColor
                nodesBtn.isSelected = true
                promptBtn.setTitle("how_to_mesh_upgrade".localizedString, for: .normal)
            }
        }
    }
    

    override init(frame: CGRect) {
        super.init(frame: frame)
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func promptBtnAction() {
        promptCallback?()
    }
    
    private func setupUI() {
        
        contentView = UIView()
        contentView.layer.cornerRadius = SCRYFrom(10)
        contentView.backgroundColor = .white
        addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(SCRYFrom(3))
            make.bottom.equalTo(SCRYFrom(-9))
        }
        
        upgradeBtn = UIButton(title: "upgrade".localizedString, titleSize: 12, titleWeight: .light, titleColor: Message_Color, normalImageName: "step_arrow_right")
        upgradeBtn.setImagePosition(position: .bottom, spacing: SCRYFrom(4))
        upgradeBtn.isUserInteractionEnabled = false
        contentView.addSubview(upgradeBtn)
        upgradeBtn.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(SCRYFrom(27))
        }
        
        distributorBtn = UIButton(title: "Distributor".localizedString, titleSize: 12, titleWeight: .light, titleColor: Message_Color)
        distributorBtn.setImage(UIImage(named: "single_device")?.withTintColor(SubText_Color), for: .normal)
        distributorBtn.setImage(UIImage(named: "single_device"), for: .selected)
        distributorBtn.setTitleColor(Bar_Color, for: .selected)
        distributorBtn.setImagePosition(position: .left, spacing: SCRXFrom(2))
        distributorBtn.isSelected = true
        distributorBtn.isUserInteractionEnabled = false
        distributorBtn.layer.cornerRadius = SCRYFrom(13)
        distributorBtn.layer.borderWidth = 0.5
        distributorBtn.layer.borderColor = Green_Color.cgColor
        contentView.addSubview(distributorBtn)
        distributorBtn.snp.makeConstraints { make in
            make.right.equalTo(upgradeBtn.snp.left).offset(SCRXFrom(-12))
            make.top.equalTo(SCRYFrom(26))
            make.width.equalTo(SCRXFrom(102))
            make.height.equalTo(SCRYFrom(28))
        }
        
        nodesBtn = UIButton(title: "node(s)".localizedString, titleSize: 12, titleWeight: .light, titleColor: Message_Color)
        nodesBtn.setImage(UIImage(named: "updatating_nodes")?.withTintColor(SubText_Color), for: .normal)
        nodesBtn.setImage(UIImage(named: "updatating_nodes"), for: .selected)
        nodesBtn.setTitleColor(Bar_Color, for: .selected)
        nodesBtn.setImagePosition(position: .left, spacing: SCRXFrom(2))
        nodesBtn.isUserInteractionEnabled = false
        nodesBtn.layer.cornerRadius = SCRYFrom(13)
        nodesBtn.layer.borderWidth = 0.5
        nodesBtn.layer.borderColor = RGB(220, 220, 220).cgColor
        contentView.addSubview(nodesBtn)
        nodesBtn.snp.makeConstraints { make in
            make.left.equalTo(upgradeBtn.snp.right).offset(SCRXFrom(12))
            make.centerY.width.height.equalTo(distributorBtn)
        }
        
        promptBtn = UIButton(title: "how_to_select_a_distributor".localizedString, titleSize: 13, titleWeight: .light, titleColor: SubText_Color, normalImageName: "profile_help", target: self, action: #selector(promptBtnAction))
        promptBtn.setImagePosition(position: .right, spacing: SCRXFrom(4))
        contentView.addSubview(promptBtn)
        promptBtn.snp.makeConstraints { make in
            make.bottom.equalTo(SCRYFrom(-24))
            make.centerX.equalToSuperview()
        }
        
    }
    
    
}
