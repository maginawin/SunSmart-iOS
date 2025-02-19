//
//  GroupSwitchPanelViewCell.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/3/12.
//

import UIKit

protocol GroupSwitchPanelViewCellDelegate: AnyObject {
    
    /// 删除事件
    func switchPanelViewCellDeleteAction(_ cell: GroupSwitchPanelViewCell)
    /// 保存事件
    func switchPanelViewCellSaveAction(_ cell: GroupSwitchPanelViewCell)
    
}

class GroupSwitchPanelViewCell: UITableViewCell {

    var switchContentView: UIView!
    private var panelImageView: UIImageView!
    private var sceneAKeyBtn: UIButton!
    private var sceneBKeyBtn: UIButton!
    var deleteBtn: UIButton!
    var saveBtn: UIButton!
    weak var delegate: GroupSwitchPanelViewCellDelegate?
    
    var margin: CGFloat = SCRXFrom(16) {
        didSet {
            switchContentView.snp.updateConstraints { make in
                make.left.equalTo(margin)
                make.right.equalTo(margin)
            }
        }
    }
    
    
    var sceneNameA: String? {
        didSet {
            sceneAKeyBtn.setTitle(sceneNameA ?? "switch_key_sceneA".localizedString, for: .normal)
        }
    }
    
    var sceneNameB: String? {
        didSet {
            sceneBKeyBtn.setTitle(sceneNameB ?? "switch_key_sceneB".localizedString, for: .normal)
        }
    }
    
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
        switchContentView.addSubview(panelImageView)
        panelImageView.snp.makeConstraints { make in
//            make.left.equalTo(SCRXFrom(16))
//            make.right.equalTo(SCRXFrom(-16))
//            make.top.equalTo(SCRYFrom(8))
            make.center.equalToSuperview()
            make.width.equalTo(SCRXFrom(160))
            make.height.equalTo(panelImageView.snp.width).multipliedBy(108.0 / 160)
//            make.bottom.equalTo(SCRYFrom(-68))
        }
        
        /// 按键信息
        let onKeyBtn = initSwitchKeyBtn(name: "switch_key_on".localizedString, shortPress: true)
        switchContentView.addSubview(onKeyBtn)
        onKeyBtn.snp.makeConstraints { make in
            make.top.equalTo(SCRYFrom(14))
            make.left.equalTo(panelImageView).offset(SCRXFrom(-53))
        }
        
        let dimUpKeyBtn = initSwitchKeyBtn(name: "switch_key_dim_up".localizedString, shortPress: false)
        switchContentView.addSubview(dimUpKeyBtn)
        dimUpKeyBtn.snp.makeConstraints { make in
            make.top.equalTo(onKeyBtn.snp.bottom).offset(SCRYFrom(4))
            make.left.equalTo(onKeyBtn)
        }
        
        let dimDownKeyBtn = initSwitchKeyBtn(name: "switch_key_dim_down".localizedString, shortPress: false)
        switchContentView.addSubview(dimDownKeyBtn)
        dimDownKeyBtn.snp.makeConstraints { make in
            make.bottom.equalTo(SCRYFrom(-14))
            make.left.equalTo(onKeyBtn)
        }
        
        let offKeyBtn = initSwitchKeyBtn(name: "switch_key_off".localizedString, shortPress: true)
        switchContentView.addSubview(offKeyBtn)
        offKeyBtn.snp.makeConstraints { make in
            make.bottom.equalTo(dimDownKeyBtn.snp.top).offset(SCRYFrom(-4))
            make.left.equalTo(dimDownKeyBtn)
        }
        
        sceneAKeyBtn = initSwitchKeyBtn(name: "Scene A", shortPress: true)
        switchContentView.addSubview(sceneAKeyBtn)
        sceneAKeyBtn.snp.makeConstraints { make in
            make.centerY.equalTo(onKeyBtn)
            make.left.equalTo(switchContentView.snp.centerX).offset(SCRXFrom(35))
            make.width.lessThanOrEqualTo(SCRXFrom(120))
        }
        
        let coolerKeyBtn = initSwitchKeyBtn(name: "switch_key_cooler".localizedString, shortPress: false)
        switchContentView.addSubview(coolerKeyBtn)
        coolerKeyBtn.snp.makeConstraints { make in
            make.top.equalTo(sceneAKeyBtn.snp.bottom).offset(SCRYFrom(4))
            make.left.equalTo(sceneAKeyBtn)
        }
        
        sceneBKeyBtn = initSwitchKeyBtn(name: "Scene B", shortPress: true)
        switchContentView.addSubview(sceneBKeyBtn)
        sceneBKeyBtn.snp.makeConstraints { make in
            make.centerY.equalTo(offKeyBtn)
            make.left.equalTo(sceneAKeyBtn)
            make.width.lessThanOrEqualTo(SCRXFrom(120))
        }
        
        let warmerKeyBtn = initSwitchKeyBtn(name: "switch_key_warmer".localizedString, shortPress: false)
        switchContentView.addSubview(warmerKeyBtn)
        warmerKeyBtn.snp.makeConstraints { make in
            make.centerY.equalTo(dimDownKeyBtn)
            make.left.equalTo(sceneBKeyBtn)
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
