//
//  GroupSwitchPanelViewCell.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/3/12.
//

import UIKit
import NordicSigMeshSDK

protocol GroupSwitchPanelViewCellDelegate: AnyObject {
    
    /// 删除事件
    func switchPanelViewCellDeleteAction(_ cell: GroupSwitchPanelViewCell)
    /// 保存事件
    func switchPanelViewCellSaveAction(_ cell: GroupSwitchPanelViewCell)
    
}

class GroupSwitchPanelViewCell: UITableViewCell {

    var switchContentView: UIView!
    private var panelImageView: UIImageView!
//    private var sceneAKeyBtn: UIButton!
//    private var sceneBKeyBtn: UIButton!
    
    var key1ShortPressBtn: UIButton!
    var key1LongPressBtn: UIButton!
    
    var key2ShortPressBtn: UIButton!
    var key2LongPressBtn: UIButton!
    
    var key3ShortPressBtn: UIButton!
    var key3LongPressBtn: UIButton!
    
    var key4ShortPressBtn: UIButton!
    var key4LongPressBtn: UIButton!
    
    var deleteBtn: UIButton!
    var saveBtn: UIButton!
    weak var delegate: GroupSwitchPanelViewCellDelegate?
    
    var margin: CGFloat = SCRXFrom(16) {
        didSet {
            switchContentView.snp.updateConstraints { make in
                make.left.equalTo(margin)
                make.right.equalTo(-margin)
            }
        }
    }
    
    var panelType: DeviceSwitchData.PanelType = .default_4key {
        didSet {
            key1ShortPressBtn.isHidden = false
            key1LongPressBtn.setImage(UIImage(named: "switch_press_long"), for: .normal)
            key2LongPressBtn.isHidden = false
            key3ShortPressBtn.isHidden = false
            key3LongPressBtn.setImage(UIImage(named: "switch_press_long"), for: .normal)
            key4LongPressBtn.isHidden = false
            key4ShortPressBtn.setImage(UIImage(named: "switch_press"), for: .normal)
            
            switch panelType {
            case .default_4key:
                panelImageView.image = UIImage(named: "switch_key")
                key1ShortPressBtn.setTitle("switch_key_on".localizedString, for: .normal)
                key1LongPressBtn.setTitle("switch_key_dim_up".localizedString, for: .normal)
                key2ShortPressBtn.setTitle("switch_key_off".localizedString, for: .normal)
                key2LongPressBtn.setTitle("switch_key_dim_down".localizedString, for: .normal)
                key3ShortPressBtn.setTitle("switch_key_sceneA".localizedString, for: .normal)
                key3LongPressBtn.setTitle("switch_key_cooler".localizedString, for: .normal)
                key4ShortPressBtn.setTitle("switch_key_sceneB".localizedString, for: .normal)
                key4LongPressBtn.setTitle("switch_key_warmer".localizedString, for: .normal)
            case .scenes_4key:
                panelImageView.image = UIImage(named: "switch_key")
                key1ShortPressBtn.setTitle("switch_key_sceneA".localizedString, for: .normal)
                key1LongPressBtn.setTitle("switch_key_dim_up".localizedString, for: .normal)
                key2ShortPressBtn.setTitle("switch_key_sceneB".localizedString, for: .normal)
                key2LongPressBtn.setTitle("switch_key_dim_down".localizedString, for: .normal)
                key3ShortPressBtn.setTitle("switch_key_sceneC".localizedString, for: .normal)
                key3LongPressBtn.setTitle("switch_key_cooler".localizedString, for: .normal)
                key4ShortPressBtn.setTitle("switch_key_sceneD".localizedString, for: .normal)
                key4LongPressBtn.setTitle("switch_key_warmer".localizedString, for: .normal)
            case .default_2key:
                panelImageView.image = UIImage(named: "switch_key_2")
                key1ShortPressBtn.isHidden = true
                key1LongPressBtn.setImage(UIImage(named: "switch_press"), for: .normal)
                key1LongPressBtn.setTitle("switch_key_on".localizedString, for: .normal)
                key2LongPressBtn.isHidden = true
                key2ShortPressBtn.setTitle("switch_key_off".localizedString, for: .normal)
                key3ShortPressBtn.isHidden = true
                key3LongPressBtn.setTitle("switch_key_dim_up".localizedString, for: .normal)
                key4LongPressBtn.isHidden = true
                key4ShortPressBtn.setTitle("switch_key_dim_down".localizedString, for: .normal)
                key4ShortPressBtn.setImage(UIImage(named: "switch_press_long"), for: .normal)
            case .scenes_2key:
                panelImageView.image = UIImage(named: "switch_key_2")
                key1ShortPressBtn.isHidden = true
                key1LongPressBtn.setImage(UIImage(named: "switch_press"), for: .normal)
                key1LongPressBtn.setTitle("switch_key_sceneA".localizedString, for: .normal)
                key2LongPressBtn.isHidden = true
                key2ShortPressBtn.setTitle("switch_key_sceneB".localizedString, for: .normal)
                key3ShortPressBtn.isHidden = true
                key3LongPressBtn.setTitle("switch_key_dim_up".localizedString, for: .normal)
                key4LongPressBtn.isHidden = true
                key4ShortPressBtn.setTitle("switch_key_dim_down".localizedString, for: .normal)
                key4ShortPressBtn.setImage(UIImage(named: "switch_press_long"), for: .normal)
            }
            
        }
    }
    
//    var sceneNameA: String? {
//        didSet {
//            sceneAKeyBtn.setTitle(sceneNameA ?? "switch_key_sceneA".localizedString, for: .normal)
//        }
//    }
//    
//    var sceneNameB: String? {
//        didSet {
//            sceneBKeyBtn.setTitle(sceneNameB ?? "switch_key_sceneB".localizedString, for: .normal)
//        }
//    }
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        selectionStyle = .none
        backgroundColor = Background_Color
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func deleteBtnAction() {
        delegate?.switchPanelViewCellDeleteAction(self)
    }
    
    @objc private func saveBtnAction() {
        delegate?.switchPanelViewCellSaveAction(self)
    }
    
    private func setupUI() {
        
        switchContentView = UIView()
        switchContentView.layer.borderColor = RGB(220, 220, 220).cgColor
        switchContentView.layer.borderWidth = 0.6
        switchContentView.layer.cornerRadius = 15
        switchContentView.backgroundColor = .white
        contentView.addSubview(switchContentView)
        switchContentView.snp.makeConstraints { make in
            make.left.equalTo(margin)
            make.right.equalTo(-margin)
            make.top.equalTo(SCRYFrom(8))
            make.height.equalTo(SCRYFrom(288))
//            make.height.equalTo(switchContentView.snp.width).multipliedBy(288.0 / 343)
        }
        
        panelImageView = UIImageView(image: UIImage(named: "switch_key"))
        panelImageView.contentMode = .center
        switchContentView.addSubview(panelImageView)
        panelImageView.snp.makeConstraints { make in
//            make.left.equalTo(SCRXFrom(16))
//            make.right.equalTo(SCRXFrom(-16))
//            make.top.equalTo(SCRYFrom(8))
            make.center.equalToSuperview()
            make.width.equalTo(SCRXFrom(160))
//            make.height.equalTo(panelImageView.snp.width).multipliedBy(108.0 / 160)
//            make.bottom.equalTo(SCRYFrom(-68))
        }
        
        /// 按键信息
        key1ShortPressBtn = initSwitchKeyBtn(name: "switch_key_on".localizedString, shortPress: true)
        switchContentView.addSubview(key1ShortPressBtn)
        key1ShortPressBtn.snp.makeConstraints { make in
            make.top.equalTo(SCRYFrom(14))
            make.left.equalTo(panelImageView).offset(SCRXFrom(-53))
        }
        
        key1LongPressBtn = initSwitchKeyBtn(name: "switch_key_dim_up".localizedString, shortPress: false)
        switchContentView.addSubview(key1LongPressBtn)
        key1LongPressBtn.snp.makeConstraints { make in
            make.top.equalTo(key1ShortPressBtn.snp.bottom).offset(SCRYFrom(4))
            make.left.equalTo(key1ShortPressBtn)
        }
        
        key2LongPressBtn = initSwitchKeyBtn(name: "switch_key_dim_down".localizedString, shortPress: false)
        switchContentView.addSubview(key2LongPressBtn)
        key2LongPressBtn.snp.makeConstraints { make in
            make.bottom.equalTo(SCRYFrom(-14))
            make.left.equalTo(key1ShortPressBtn)
        }
        
        key2ShortPressBtn = initSwitchKeyBtn(name: "switch_key_off".localizedString, shortPress: true)
        switchContentView.addSubview(key2ShortPressBtn)
        key2ShortPressBtn.snp.makeConstraints { make in
            make.bottom.equalTo(key2LongPressBtn.snp.top).offset(SCRYFrom(-4))
            make.left.equalTo(key1ShortPressBtn)
        }
        
        key3ShortPressBtn = initSwitchKeyBtn(name: "Scene A", shortPress: true)
        switchContentView.addSubview(key3ShortPressBtn)
        key3ShortPressBtn.snp.makeConstraints { make in
            make.centerY.equalTo(key1ShortPressBtn)
            make.left.equalTo(switchContentView.snp.centerX).offset(SCRXFrom(35))
            make.width.lessThanOrEqualTo(SCRXFrom(120))
        }
        
        key3LongPressBtn = initSwitchKeyBtn(name: "switch_key_cooler".localizedString, shortPress: false)
        switchContentView.addSubview(key3LongPressBtn)
        key3LongPressBtn.snp.makeConstraints { make in
            make.top.equalTo(key3ShortPressBtn.snp.bottom).offset(SCRYFrom(4))
            make.left.equalTo(key3ShortPressBtn)
        }
        
        key4ShortPressBtn = initSwitchKeyBtn(name: "Scene B", shortPress: true)
        switchContentView.addSubview(key4ShortPressBtn)
        key4ShortPressBtn.snp.makeConstraints { make in
            make.centerY.equalTo(key2ShortPressBtn)
            make.left.equalTo(key3ShortPressBtn)
            make.width.lessThanOrEqualTo(SCRXFrom(120))
        }
        
        key4LongPressBtn = initSwitchKeyBtn(name: "switch_key_warmer".localizedString, shortPress: false)
        switchContentView.addSubview(key4LongPressBtn)
        key4LongPressBtn.snp.makeConstraints { make in
            make.centerY.equalTo(key2LongPressBtn)
            make.left.equalTo(key4ShortPressBtn)
        }
        
        deleteBtn = UIButton(normalImageName: "switch_delete", target: self, action: #selector(deleteBtnAction))
        contentView.addSubview(deleteBtn)
        deleteBtn.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(56))
            make.top.equalTo(switchContentView.snp.bottom).offset(SCRYFrom(16))
//            make.bottom.equalTo(SCRYFrom(-16))
            make.height.equalTo(40)
        }
        
        saveBtn = UIButton(normalImageName: "switch_save", target: self, action: #selector(saveBtnAction))
        saveBtn.setImage(UIImage(named: "switch_save_un"), for: .disabled)
        contentView.addSubview(saveBtn)
        saveBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-56))
            make.centerY.height.equalTo(deleteBtn)
        }
        
    }
    
    private func initSwitchKeyBtn(name: String, shortPress: Bool) -> UIButton {
        let btn = UIButton(title: name, titleSize: 13, titleWeight: .light, titleColor: RGB(30, 35, 41), normalImageName: shortPress ? "switch_press" : "switch_press_long")
        btn.titleLabel?.lineBreakMode = .byTruncatingHead
//        btn.contentHorizontalAlignment = .left
        btn.isUserInteractionEnabled = false
        return btn
    }
    
}
