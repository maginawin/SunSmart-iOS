//
//  SceneAddGroupViewCell.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/12/21.
//

import UIKit

protocol SceneAddGroupViewCellDelegate: AnyObject {
    
    /// group选中事件回调
    /// - Parameters:
    ///   - isSelected: 是否选中
//    func cell(_ cell: SceneAddGroupViewCell, didSelectAction isSelected: Bool)
    
    /// group开关事件回调
    /// - Parameters:
    ///   - isOn: 是否开启
    func cell(_ cell: SceneAddGroupViewCell, didOnOffAction isOn: Bool)
    
    /// group长按事件回调
//    func cellDidLongPressAction(_ cell: SceneAddGroupViewCell)
}

class SceneAddGroupViewCell: UICollectionViewCell {
    
    var selectBtn: UIButton!
    var nameLabel: UILabel!
    var dataLabel: UILabel!
    var onoffBtn: UIButton!
    var lineView: UIView!
    weak var delegate: SceneAddGroupViewCellDelegate?
     
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        backgroundColor = .white
        setupUI()
//        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(longPressAction))
//        longPress.minimumPressDuration = 0.5
//        addGestureRecognizer(longPress)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
//    @objc private func longPressAction(sender: UIGestureRecognizer) {
//        if sender.state == .began {
//            delegate?.cellDidLongPressAction(self)
//        }
//    }
    
    @objc private func onoffBtnAction(sender: UIButton) {
        delegate?.cell(self, didOnOffAction: !sender.isSelected)
    }
    
//    @objc private func selectBtnAction(sender: UIButton) {
//        delegate?.cell(self, didSelectAction: !sender.isSelected)
//    }
    
    private func setupUI() {
        
        selectBtn = UIButton(normalImageName: "device_select_un", selectedImageName: "device_select")
        selectBtn.isUserInteractionEnabled = false
        contentView.addSubview(selectBtn)
        selectBtn.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.centerY.equalToSuperview()
        }
        
        nameLabel = UILabel(text: "G2", textColor: RGB(30, 35, 41), fontSize: 15, fontWeight: .light)
        contentView.addSubview(nameLabel)
        nameLabel.snp.makeConstraints { make in
            make.left.equalTo(selectBtn.snp.right).offset(SCRXFrom(14))
            make.centerY.equalToSuperview()
            make.width.lessThanOrEqualTo(SCRXFrom(144))
        }
        
        onoffBtn = UIButton(normalImageName: "scene_group_off", selectedImageName: "scene_group_on", target: self, action: #selector(onoffBtnAction))
//        onoffBtn.setImage(UIImage(named: "scene_group_disable"), for: .disabled)
        contentView.addSubview(onoffBtn)
        onoffBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-10))
            make.centerY.equalToSuperview()
        }
        
        dataLabel = UILabel(text: "50% | 4500K", textColor: RGB(142, 142, 147), fontSize: 14, fontWeight: .light)
        contentView.addSubview(dataLabel)
        dataLabel.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.right.equalTo(onoffBtn.snp.left).offset(SCRXFrom(-12))
        }
        
        lineView = UIView()
        lineView.backgroundColor = RGB(243, 243, 243)
        contentView.addSubview(lineView)
        lineView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(29))
            make.right.bottom.equalToSuperview()
            make.height.equalTo(1)
        }
        
    }
    
}


protocol SceneAddGroupEmptyCellDelegate: AnyObject {
    
    /// 创建组事件回调
    func cellDidCreateGroupAction(_ cell: SceneAddGroupEmptyCell)
}

class SceneAddGroupEmptyCell: UICollectionViewCell {
    
    var titleLabel: UILabel!
    var messageLabel: UILabel!
    var createBtn: UIButton!
    
    weak var delegate: SceneAddGroupEmptyCellDelegate?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func createBtnAction() {
        delegate?.cellDidCreateGroupAction(self)
    }
    
    private func setupUI() {
        
        titleLabel = UILabel(text: "no_groups".localizedString, textColor: RGB(100, 116, 139), fontSize: 15)
        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(SCRYFrom(44))
        }
        
        messageLabel = UILabel(text: "scene_not_groups_message".localizedString, textColor: RGB(148, 163, 184), fontSize: 15, fontWeight: .light)
        contentView.addSubview(messageLabel)
        messageLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(18))
        }
        
        createBtn = UIButton(title: "create_group".localizedString, titleSize: 15, titleColor: Bar_Color, target: self, action: #selector(createBtnAction))
        contentView.addSubview(createBtn)
        createBtn.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(messageLabel.snp.bottom).offset(SCRYFrom(40))
            make.height.equalTo(SCRYFrom(22))
        }
        
    }
    
}
