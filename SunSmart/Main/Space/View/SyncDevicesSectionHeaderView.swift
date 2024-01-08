//
//  SyncDevicesSectionHeaderView.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/12/27.
//

import UIKit

protocol SyncDevicesSectionHeaderViewDelegate: AnyObject {
    
    /// 选中/取消选中更新回调
    func view(_ view: SyncDevicesSectionHeaderView, didSelectedAction isSelected: Bool)
    
    /// 展开/收起状态更新回调
//    func view(_ view: SyncDevicesSectionHeaderView, showHideStateChanged isShow: Bool)
    /// 点击内容view回调
    func headerViewClickAction(_ view: SyncDevicesSectionHeaderView)
    
    /// 点击图标回调
    func headerViewClickIconAction(view: SyncDevicesSectionHeaderView)
}

class SyncDevicesSectionHeaderView: UITableViewHeaderFooterView {

    var selectBtn: UIButton!
    
    var iconImageBtn: UIButton!
    
    var nameLabel: UILabel!
    
    var stateImageView: UIImageView!
    
    var arrowImageView: UIImageView!
    
    var lineView: UIView!
    
    weak var delegate: SyncDevicesSectionHeaderViewDelegate?
    
    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        
        contentView.backgroundColor = .white
        
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(viewDidClickAction)))
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func viewDidClickAction() {
        delegate?.headerViewClickAction(self)
    }
    
    @objc private func selectBtnAction(sender: UIButton) {
        sender.isSelected = !sender.isSelected
        delegate?.view(self, didSelectedAction: sender.isSelected)
    }
    
    @objc private func iconImageBtnAction() {
        delegate?.headerViewClickIconAction(view: self)
    }
    
    private func setupUI() {
        
        selectBtn = UIButton(normalImageName: "device_select_un", selectedImageName: "device_select", target: self, action: #selector(selectBtnAction))
        addSubview(selectBtn)
        selectBtn.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.centerY.equalToSuperview()
        }
        
        iconImageBtn = UIButton(normalImageName: "space_device_count", target: self, action: #selector(iconImageBtnAction))
        addSubview(iconImageBtn)
        iconImageBtn.snp.makeConstraints { make in
//            make.left.equalTo(SCRXFrom(48))
            make.left.equalTo(selectBtn.snp.right).offset(SCRXFrom(2))
            make.centerY.equalToSuperview()
        }
        
        nameLabel = UILabel(text: "Group 2", textColor: RGB(30, 35, 41), fontSize: 15, fontWeight: .light)
        addSubview(nameLabel)
        nameLabel.snp.makeConstraints { make in
            make.left.equalTo(iconImageBtn.snp.right).offset(SCRXFrom(6))
            make.width.lessThanOrEqualTo(SCRXFrom(200))
            make.centerY.equalTo(iconImageBtn)
        }
        
//        sync_success
        stateImageView = UIImageView()
        addSubview(stateImageView)
        stateImageView.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-60))
            make.centerY.equalToSuperview()
        }
        
        arrowImageView = UIImageView(image: UIImage(named: "arrow_down"))
        addSubview(arrowImageView)
        arrowImageView.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.centerY.equalToSuperview()
        }
        
        lineView = UIView()
        lineView.backgroundColor = Line_Color
        addSubview(lineView)
        lineView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.bottom.right.equalToSuperview()
            make.height.equalTo(1)
        }
    }
    
}
