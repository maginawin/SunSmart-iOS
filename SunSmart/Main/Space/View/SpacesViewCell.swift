//
//  SpacesViewCell.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/9/25.
//

import UIKit

protocol SpacesViewCellDelegate: AnyObject {
    
    /// 点击更多回调
    func cell(_ cell: SpacesViewCell, moreAction point: CGPoint)
    
    /// 点击收藏回调
    func cell(_ cell: SpacesViewCell, favouriteChanged favourite: Bool)
    
    /// 点击同步异常回调
    func spacesViewCellSyncFailedAction(_ cell: SpacesViewCell)
}

class SpacesViewCell: UITableViewCell {

    private var bgView: UIView!
    private var iconImageView: UIImageView!
    private var nameLabel: UILabel!
    private var favoriteBtn: UIButton!
    private var moreBtn: UIButton!
    private var luminairesLabel: UILabel!
    private var switchesLabel: UILabel!
    private var groupsLabel: UILabel!
    private var scenesLabel: UILabel!
    private var schedulesLabel: UILabel!
    private var timeLabel: UILabel!
    /// 存在子管理员
    private var editorImageView: UIImageView!
    /// 权限
    private var permissionLabel: UILabel!
    /// 没有权限图标
    private var lockImageView: UIImageView!
    /// 同步失败标识
    var syncFailedImageBtn: UIButton!
    
    weak var delegate: SpacesViewCellDelegate?
    /// 点击更多回调
//    var clickMoreCallback: ((CGPoint)->Void)?
    /// 点击收藏回调
//    var clickFavouriteCallback: ((Bool)->Void)?
    
    var space: SpaceData! {
        didSet {
            nameLabel.text = space.name
            iconImageView.image = UIImage(named: "space_picture_\(space.imageId)")
            timeLabel.text = String.dateConvert(timestamp: "\(space.create)", dateFormat: "M/d/yyyy hh:mm a")
            luminairesLabel.text = "luminaires".localizedString + ":\(space.luminairesCount)"
            switchesLabel.text = "switches".localizedString + ":\(space.switchesCount)"
            groupsLabel.text = "groups".localizedString + ":\(space.groupCount)"
            scenesLabel.text = "scenes".localizedString + ":\(space.sceneCount)"
            schedulesLabel.text = "schedules".localizedString + ":\(space.scheheduleCount)"
            favoriteBtn.isSelected = space.isFavourite
            
            permissionLabel.text = space.permission.rawString
            lockImageView.isHidden = true
            nameLabel.textColor = TextBlack_Color
            nameLabel.snp.updateConstraints { make in
                make.left.equalTo(SCRXFrom(16))
            }
            editorImageView.isHidden = true
            syncFailedImageBtn.isHidden = space.showSyncCloudError == nil
            
            
            if space.permission == .owner {
                
                if space.editor != nil {
                    editorImageView.isHidden = false
                    syncFailedImageBtn.snp.remakeConstraints { make in
                        make.right.equalTo(editorImageView.snp.left).offset(SCRXFrom(-8))
                        make.centerY.equalTo(editorImageView)
                    }
                }else {
                    editorImageView.isHidden = true
                    syncFailedImageBtn.snp.remakeConstraints { make in
                        make.right.equalTo(favoriteBtn.snp.left).offset(SCRXFrom(-8))
                        make.centerY.equalTo(favoriteBtn)
                    }
                }
                
            }else {
                permissionLabel.textColor = Message_Color
                // 判断是否回收权限
                if space.state == .waitDeleted {
    //                lockImageView.isHidden = false
                    nameLabel.textColor = Red_Color
                    permissionLabel.textColor = TextBlack_Color
                    
                }else { // 判断是否修改密码
                    
                    if true {
                        lockImageView.isHidden = false
                        permissionLabel.textColor = TextBlack_Color
                        nameLabel.snp.updateConstraints { make in
                            make.left.equalTo(SCRXFrom(50))
                        }
                    }
                }
                
                syncFailedImageBtn.snp.remakeConstraints { make in
                    make.right.equalTo(editorImageView.snp.left).offset(SCRXFrom(-8))
                    make.centerY.equalTo(editorImageView)
                }
            }
           
            
        }
    }
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        backgroundColor = .clear
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    /// 更多
    @objc private func moreBtnClick() {
        
        let morePoint = CGPoint(x: self.moreBtn.center.x, y: self.moreBtn.frame.maxY)
        
        let point = bgView.convert(morePoint, to: self)
//        clickMoreCallback?(point)
        delegate?.cell(self, moreAction: point)
//        delegate?.sitesViewCell(self, didClickMore: point)
    }
    /// 收藏
    @objc private func favoriteBtnClick() {
        
        favoriteBtn.isSelected = !favoriteBtn.isSelected
//        delegate?.sitesViewCell(self, didClickFavourite: favoriteBtn.isSelected)
//        clickFavouriteCallback?(favoriteBtn.isSelected)
        delegate?.cell(self, favouriteChanged: favoriteBtn.isSelected)
    }
    
    /// 同步失败
    @objc private func syncFailedImageBtnAction() {
        delegate?.spacesViewCellSyncFailedAction(self)
    }
    
    private func setupUI() {
        bgView = UIView()
        bgView.backgroundColor = .white
        bgView.layer.cornerRadius = SCRYFrom(10)
        bgView.layer.shadowColor = RGB(0, 0, 0, 0.05).cgColor
        bgView.layer.shadowOffset = CGSizeMake(0,3)
        bgView.layer.shadowOpacity = 1
        bgView.layer.shadowRadius = 5
        contentView.addSubview(bgView)
        bgView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalToSuperview()
            make.bottom.equalTo(SCRYFrom(-16))
        }
        
        nameLabel = UILabel(text: "Frist Floor", textColor: TextBlack_Color, fontSize: 14, fontWeight: .light)
        bgView.addSubview(nameLabel)
        nameLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.width.lessThanOrEqualTo(SCRXFrom(140))
            make.top.equalTo(SCRYFrom(16))
        }
        
        moreBtn = UIButton(normalImageName: "more_vertical", target: self, action: #selector(moreBtnClick))
        bgView.addSubview(moreBtn)
        moreBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-4))
            make.centerY.centerY.equalTo(nameLabel)
        }
        
        favoriteBtn = UIButton(normalImageName: "favourite_normal", selectedImageName: "favourite_selected", target: self, action: #selector(favoriteBtnClick))
        bgView.addSubview(favoriteBtn)
        favoriteBtn.snp.makeConstraints { make in
            make.right.equalTo(moreBtn.snp.left).offset(SCRXFrom(-4))
            make.centerY.equalTo(moreBtn)
        }
        
        iconImageView = UIImageView()
        iconImageView.backgroundColor = RGB(247, 247, 255)
        iconImageView.contentMode = .center
        iconImageView.layer.cornerRadius = SCRYFrom(8)
        bgView.addSubview(iconImageView)
        iconImageView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.equalTo(SCRYFrom(48))
            make.bottom.equalTo(SCRYFrom(-24))
//            make.height.equalTo(SCRYFrom(120))
            make.width.equalTo(iconImageView.snp.height).multipliedBy(160 / 120.0)
        }
        
        luminairesLabel = UILabel(text: "Luminaires: 20", textColor: RGB(100, 136, 139), fontSize: 13, fontWeight: .light)
        bgView.addSubview(luminairesLabel)
        luminairesLabel.snp.makeConstraints { make in
            make.top.equalTo(iconImageView)
            make.left.equalTo(iconImageView.snp.right).offset(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-10))
        }
        
        switchesLabel = UILabel(text: "Switches: 20", textColor: RGB(100, 136, 139), fontSize: 13, fontWeight: .light)
        bgView.addSubview(switchesLabel)
        switchesLabel.snp.makeConstraints { make in
            make.top.equalTo(luminairesLabel.snp.bottom).offset(SCRYFrom(4))
            make.left.right.equalTo(luminairesLabel)
        }
        
        groupsLabel = UILabel(text: "Groups: 4", textColor: RGB(100, 136, 139), fontSize: 13, fontWeight: .light)
        bgView.addSubview(groupsLabel)
        groupsLabel.snp.makeConstraints { make in
            make.top.equalTo(switchesLabel.snp.bottom).offset(SCRYFrom(9))
            make.left.right.equalTo(switchesLabel)
        }
        
        scenesLabel = UILabel(text: "Scenes: 2", textColor: RGB(100, 136, 139), fontSize: 13, fontWeight: .light)
        bgView.addSubview(scenesLabel)
        scenesLabel.snp.makeConstraints { make in
            make.top.equalTo(groupsLabel.snp.bottom).offset(SCRYFrom(4))
            make.left.right.equalTo(groupsLabel)
        }
        
        schedulesLabel = UILabel(text: "Schedules: 2", textColor: RGB(100, 136, 139), fontSize: 13, fontWeight: .light)
        bgView.addSubview(schedulesLabel)
        schedulesLabel.snp.makeConstraints { make in
            make.top.equalTo(scenesLabel.snp.bottom).offset(SCRYFrom(4))
            make.left.right.equalTo(scenesLabel)
        }
        
        timeLabel = UILabel(text: "8/7/2023 12:00 AM", textColor: RGB(100, 136, 139), fontSize: 13, fontWeight: .light)
        bgView.addSubview(timeLabel)
        timeLabel.snp.makeConstraints { make in
            make.left.right.equalTo(scenesLabel)
            make.bottom.equalTo(iconImageView)
        }
        
        editorImageView = UIImageView(image: UIImage(named: "space_editor"))
        editorImageView.isHidden = true
        bgView.addSubview(editorImageView)
        editorImageView.snp.makeConstraints { make in
            make.right.equalTo(favoriteBtn.snp.left).offset(SCRXFrom(-8))
            make.centerY.equalTo(favoriteBtn)
        }
        
        permissionLabel = UILabel(text: "", textColor: Message_Color, fontSize: 14, fontWeight: .light)
        permissionLabel.isHidden = true
        bgView.addSubview(permissionLabel)
        permissionLabel.snp.makeConstraints { make in
            make.right.equalTo(favoriteBtn.snp.left).offset(SCRXFrom(-8))
            make.centerY.equalTo(favoriteBtn)
        }
        
        lockImageView = UIImageView(image: UIImage(named: "locked"))
        lockImageView.isHidden = true
        bgView.addSubview(lockImageView)
        lockImageView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
//            make.top.equalTo(SCRYFrom(9))
            make.centerY.equalTo(nameLabel)
        }
        
        syncFailedImageBtn = UIButton(normalImageName: "cloud_sync_failed", target: self, action: #selector(syncFailedImageBtnAction))
//        UIImageView(image: UIImage(named: "cloud_sync_failed"))
        bgView.addSubview(syncFailedImageBtn)
        syncFailedImageBtn.snp.makeConstraints { make in
            make.right.equalTo(editorImageView.snp.left).offset(SCRXFrom(-8))
            make.centerY.equalTo(editorImageView)
        }
        
    }
    


}

