//
//  SyncDevicesGroupViewCell.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/12/28.
//

import UIKit

protocol SyncDevicesGroupViewCellDelegate: AnyObject {
    
    /// 选中/取消选中更新回调
    func cell(_ cell: SyncDevicesGroupViewCell, didSelectedAction model: SyncDevicesGroupModel)
    
    /// 展开/收起状态更新回调
//    func view(_ view: SyncDevicesSectionHeaderView, showHideStateChanged isShow: Bool)
    /// 点击内容view回调
//    func cellClickAction(cell: SyncDevicesGroupViewCell)
    
    /// 点击图标回调
    func cellClickIconAction(cell: SyncDevicesGroupViewCell)
}

class SyncDevicesGroupViewCell: UITableViewCell {
    
    var selectBtn: UIButton!
    
    var iconImageBtn: UIButton!
    
    var nameLabel: UILabel!
    
    var stateImageView: UIImageView!
    
    var arrowImageView: UIImageView!
    
    var lineView: UIView!
    
    weak var delegate: SyncDevicesGroupViewCellDelegate?
    
    var groupModel: SyncDevicesGroupModel! {
        didSet {
            
            iconImageBtn.setImage(UIImage(named: groupModel.imageName), for: .normal)
            nameLabel.text = groupModel.name
            
            arrowImageView.isHidden = true
            arrowImageView.image = UIImage(named: groupModel.isShow ? "arrow_up" : "arrow_down")
            stateImageView.snp.updateConstraints { make in
                make.right.equalTo(SCRXFrom(-16))
            }
            selectBtn.isHidden = true
            stateImageView.isHidden = false
            
            if groupModel.isFineshed {
                iconImageBtn.snp.updateConstraints { make in
                    make.left.equalTo(SCRXFrom(48))
                }
            }else {
                iconImageBtn.snp.updateConstraints { make in
                    make.left.equalTo(SCRXFrom(16))
                }
            }
            
            switch groupModel.state {
            case .none, .inSettings:
                stateImageView.isHidden = true
            case .wait:
                stateImageView.isHidden = false
                stateImageView.image = UIImage(named: "device_add_waiting")
//                stateImageView.snp.updateConstraints { make in
//                    make.right.equalTo(SCRXFrom(-16))
//                }
            case .successful:
                stateImageView.image = UIImage(named: "sync_success_small")
                arrowImageView.isHidden = false
                stateImageView.snp.updateConstraints { make in
                    make.right.equalTo(SCRXFrom(-59))
                }
            case .failed:
                stateImageView.image = UIImage(named: "sync_failed_small")
                selectBtn.isHidden = !groupModel.isFineshed
                selectBtn.isSelected = groupModel.isSelected
                arrowImageView.isHidden = false
                stateImageView.snp.updateConstraints { make in
                    make.right.equalTo(SCRXFrom(-59))
                }

            }
        }
    }
    
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        backgroundColor = .white
        selectionStyle = .none
//        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(viewDidClickAction)))
        
        setupUI()
    }

    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func viewDidClickAction() {
//        delegate?.cellClickAction(cell: self)
    }
    
    @objc private func selectBtnAction(sender: UIButton) {
        sender.isSelected = !sender.isSelected
        groupModel.isSelected = sender.isSelected
        delegate?.cell(self, didSelectedAction: groupModel)
    }
    
    @objc private func iconImageBtnAction() {
        delegate?.cellClickIconAction(cell: self)
    }
    
    private func setupUI() {
        
        selectBtn = UIButton(normalImageName: "device_select_un", selectedImageName: "device_select", target: self, action: #selector(selectBtnAction))
        contentView.addSubview(selectBtn)
        selectBtn.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.centerY.equalToSuperview()
        }
        
        iconImageBtn = UIButton(normalImageName: "space_device_count", target: self, action: #selector(iconImageBtnAction))
        contentView.addSubview(iconImageBtn)
        iconImageBtn.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(48))
//            make.left.equalTo(selectBtn.snp.right).offset(SCRXFrom(2))
            make.centerY.equalToSuperview()
        }
        
        nameLabel = UILabel(text: "Group 2", textColor: RGB(30, 35, 41), fontSize: 15, fontWeight: .light)
        contentView.addSubview(nameLabel)
        nameLabel.snp.makeConstraints { make in
            make.left.equalTo(iconImageBtn.snp.right).offset(SCRXFrom(6))
            make.width.lessThanOrEqualTo(SCRXFrom(200))
            make.centerY.equalTo(iconImageBtn)
        }
        
//        sync_success
        stateImageView = UIImageView()
        contentView.addSubview(stateImageView)
        stateImageView.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-60))
            make.centerY.equalToSuperview()
        }
        
        arrowImageView = UIImageView(image: UIImage(named: "arrow_down"))
        contentView.addSubview(arrowImageView)
        arrowImageView.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.centerY.equalToSuperview()
        }
        
        lineView = UIView()
        lineView.backgroundColor = Line_Color
        contentView.addSubview(lineView)
        lineView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.bottom.right.equalToSuperview()
            make.height.equalTo(1)
        }
    }
}
