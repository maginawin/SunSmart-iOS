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

class SpacesViewCell: UICollectionViewCell {

//    private var bgView: UIView!
    private var iconImageView: UIImageView!
    private var nameLabel: UILabel!
    private var stackView: UIStackView!
    private var favoriteBtn: UIButton!
    private var moreBtn: UIButton!
    /// 存在子管理员
    private var editorImageView: UIImageView!
    /// 权限
    private var permissionLabel: UILabel!
    /// 网关在离线图标
    private var gatewayStateImageView: UIImageView!
    
    private var luminairesLabel: UILabel!
    private var switchesLabel: UILabel!
    private var groupsLabel: UILabel!
    private var scenesLabel: UILabel!
    private var schedulesLabel: UILabel!
    private var timeLabel: UILabel!

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
            
            var stackSubViews: [UIView] = []
            
            // 清除旧的视图
            stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
            stackSubViews.append(moreBtn)
            stackSubViews.append(favoriteBtn)
            
            nameLabel.text = space.name
            iconImageView.image = UIImage(named: "space_picture_\(space.imageId)")
            timeLabel.text = space.create > 0 ? String.dateConvert(timestamp: "\(space.create)", dateFormat: "M/d/yyyy hh:mm a") : "--"
            luminairesLabel.text = "luminaires".localizedString + ":\(space.deviceCount)"
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

            if space.permission == .owner {
                permissionLabel.isHidden = true
                if space.editor != nil {
                    stackSubViews.append(editorImageView)
                }
            }else {
//                permissionLabel.isHidden = false
                permissionLabel.textColor = Message_Color
                // 判断是否回收权限
                if space.state == .waitDeleted {
    //                lockImageView.isHidden = false
                    nameLabel.textColor = Red_Color
                    permissionLabel.textColor = TextBlack_Color
                    
                }else { // 判断是否修改密码
                    // 是否需要验证密码
                    var passwordVerification = false
                    if space.permission == .editor {
                        passwordVerification = space.authorizationPassword?.isEmpty ?? true || space.requiresPasswordVerification
                    }else {
                        passwordVerification = (space.vistorPasswordEnable && (space.authorizationPassword?.isEmpty ?? true)) || space.requiresPasswordVerification
                    }
                    
                    if passwordVerification {
                        lockImageView.isHidden = false
                        permissionLabel.textColor = TextBlack_Color
                        nameLabel.snp.updateConstraints { make in
                            make.left.equalTo(SCRXFrom(50))
                        }
                    }
                }
                stackSubViews.append(permissionLabel)
            }
            
            gatewayStateImageView.image = UIImage(named: "gateway_internet_online_big")
            stackSubViews.append(gatewayStateImageView)
            
            if space.showSyncCloudError != nil && space.permission != .visitor {
//                syncFailedImageBtn.isHidden = false
                nameLabel.textColor = Message_Color
                stackSubViews.append(syncFailedImageBtn)
            }
            
            stackSubViews.reversed().forEach({
                $0.setContentCompressionResistancePriority(.required, for: .horizontal)
                $0.setContentHuggingPriority(.required, for: .horizontal)
                stackView.addArrangedSubview($0)
            })
            
            // 自定义间隔，权限label左右间距调整
            if let index = stackSubViews.firstIndex(of: permissionLabel) {
                var customSpacingViews: [UIView] = [permissionLabel]
                if index + 1 < stackSubViews.count {
                    customSpacingViews.append(stackSubViews[index + 1])
                }
                customSpacingViews.forEach({
                    stackView.setCustomSpacing(SCRXFrom(8), after: $0)
                })
            }
        }
    }
    
    override init(frame: CGRect) {
      
        super.init(frame: frame)
        
        backgroundColor = .white
        layer.cornerRadius = SCRYFrom(10)
        layer.shadowColor = RGB(0, 0, 0, 0.05).cgColor
        layer.shadowOffset = CGSizeMake(0,3)
        layer.shadowOpacity = 1
        layer.shadowRadius = 5
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    /// 更多
    @objc private func moreBtnClick() {
        
        let morePoint = CGPoint(x: self.moreBtn.center.x, y: self.moreBtn.frame.maxY)
        
        let point = stackView.convert(morePoint, to: self)
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
//        bgView = UIView()
//        bgView.backgroundColor = .white
//        bgView.layer.cornerRadius = SCRYFrom(10)
//        bgView.layer.shadowColor = RGB(0, 0, 0, 0.05).cgColor
//        bgView.layer.shadowOffset = CGSizeMake(0,3)
//        bgView.layer.shadowOpacity = 1
//        bgView.layer.shadowRadius = 5
//        contentView.addSubview(bgView)
//        bgView.snp.makeConstraints { make in
//            make.left.equalTo(SCRXFrom(16))
//            make.right.equalTo(SCRXFrom(-16))
//            make.top.equalToSuperview()
//            make.bottom.equalTo(SCRYFrom(-16))
//        }
        
        stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.spacing = SCRXFrom(4)
        stackView.setContentCompressionResistancePriority(.required, for: .horizontal)
        stackView.setContentHuggingPriority(.required, for: .horizontal)
//        stackView.alignment = .trailing
        contentView.addSubview(stackView)
        stackView.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-4))
            make.top.equalTo(SCRYFrom(9))
            make.height.equalTo(30)
//            make.width.greaterThanOrEqualTo(60)
        }
        
        nameLabel = UILabel(text: "Frist Floor", textColor: TextBlack_Color, fontSize: 14, fontWeight: .light)
        nameLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        contentView.addSubview(nameLabel)
        nameLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
//            make.width.lessThanOrEqualTo(SCRXFrom(140))
//            make.top.equalTo(SCRYFrom(16))
            make.centerY.equalTo(stackView)
            make.right.equalTo(stackView.snp.left).offset(SCRXFrom(-20))
        }
        
  
        
        moreBtn = UIButton(normalImageName: "more_vertical", target: self, action: #selector(moreBtnClick))
        stackView.addArrangedSubview(moreBtn)
//        contentView.addSubview(moreBtn)
//        moreBtn.snp.makeConstraints { make in
//            make.right.equalTo(SCRXFrom(-4))
//            make.centerY.centerY.equalTo(nameLabel)
//        }
        
        favoriteBtn = UIButton(normalImageName: "favourite_normal", selectedImageName: "favourite_selected", target: self, action: #selector(favoriteBtnClick))
        stackView.addArrangedSubview(favoriteBtn)
//        contentView.addSubview(favoriteBtn)
//        favoriteBtn.snp.makeConstraints { make in
//            make.right.equalTo(moreBtn.snp.left).offset(SCRXFrom(-4))
//            make.centerY.equalTo(moreBtn)
//        }
        
        editorImageView = UIImageView(image: UIImage(named: "space_editor"))
//        editorImageView.isHidden = true
//        stackView.addArrangedSubview(editorImageView)
//        contentView.addSubview(editorImageView)
//        editorImageView.snp.makeConstraints { make in
//            make.right.equalTo(favoriteBtn.snp.left).offset(SCRXFrom(-8))
//            make.centerY.equalTo(favoriteBtn)
//        }
        
        permissionLabel = UILabel(text: "", textColor: Message_Color, fontSize: 14, fontWeight: .light)
//        permissionLabel.isHidden = true
//        contentView.addSubview(permissionLabel)
//        permissionLabel.snp.makeConstraints { make in
//            make.right.equalTo(favoriteBtn.snp.left).offset(SCRXFrom(-8))
//            make.centerY.equalTo(favoriteBtn)
//        }
        
        syncFailedImageBtn = UIButton(normalImageName: "cloud_sync_failed", target: self, action: #selector(syncFailedImageBtnAction))
//        UIImageView(image: UIImage(named: "cloud_sync_failed"))
//        contentView.addSubview(syncFailedImageBtn)
//        syncFailedImageBtn.snp.makeConstraints { make in
//            make.right.equalTo(editorImageView.snp.left).offset(SCRXFrom(-8))
//            make.centerY.equalTo(editorImageView)
//        }
        
        gatewayStateImageView = UIImageView()
        
        
        iconImageView = UIImageView()
        iconImageView.backgroundColor = RGB(247, 247, 255)
        iconImageView.contentMode = .center
        iconImageView.layer.cornerRadius = SCRYFrom(8)
        contentView.addSubview(iconImageView)
        iconImageView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.equalTo(SCRYFrom(48))
            make.bottom.equalTo(SCRYFrom(-24))
//            make.height.equalTo(SCRYFrom(120))
            make.width.equalTo(iconImageView.snp.height).multipliedBy(160 / 120.0)
        }
        
        luminairesLabel = UILabel(text: "Luminaires: 20", textColor: RGB(100, 136, 139), fontSize: 13, fontWeight: .light)
        contentView.addSubview(luminairesLabel)
        luminairesLabel.snp.makeConstraints { make in
            make.top.equalTo(iconImageView)
            make.left.equalTo(iconImageView.snp.right).offset(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-10))
        }
        
        switchesLabel = UILabel(text: "Switches: 20", textColor: RGB(100, 136, 139), fontSize: 13, fontWeight: .light)
        contentView.addSubview(switchesLabel)
        switchesLabel.snp.makeConstraints { make in
            make.top.equalTo(luminairesLabel.snp.bottom).offset(SCRYFrom(4))
            make.left.right.equalTo(luminairesLabel)
        }
        
        groupsLabel = UILabel(text: "Groups: 4", textColor: RGB(100, 136, 139), fontSize: 13, fontWeight: .light)
        contentView.addSubview(groupsLabel)
        groupsLabel.snp.makeConstraints { make in
            make.top.equalTo(switchesLabel.snp.bottom).offset(SCRYFrom(9))
            make.left.right.equalTo(switchesLabel)
        }
        
        scenesLabel = UILabel(text: "Scenes: 2", textColor: RGB(100, 136, 139), fontSize: 13, fontWeight: .light)
        contentView.addSubview(scenesLabel)
        scenesLabel.snp.makeConstraints { make in
            make.top.equalTo(groupsLabel.snp.bottom).offset(SCRYFrom(4))
            make.left.right.equalTo(groupsLabel)
        }
        
        schedulesLabel = UILabel(text: "Schedules: 2", textColor: RGB(100, 136, 139), fontSize: 13, fontWeight: .light)
        contentView.addSubview(schedulesLabel)
        schedulesLabel.snp.makeConstraints { make in
            make.top.equalTo(scenesLabel.snp.bottom).offset(SCRYFrom(4))
            make.left.right.equalTo(scenesLabel)
        }
        
        timeLabel = UILabel(text: "8/7/2023 12:00 AM", textColor: RGB(100, 136, 139), fontSize: 13, fontWeight: .light)
        contentView.addSubview(timeLabel)
        timeLabel.snp.makeConstraints { make in
            make.left.right.equalTo(scenesLabel)
            make.bottom.equalTo(iconImageView)
        }
        
        lockImageView = UIImageView(image: UIImage(named: "locked"))
        lockImageView.isHidden = true
        contentView.addSubview(lockImageView)
        lockImageView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
//            make.top.equalTo(SCRYFrom(9))
            make.centerY.equalTo(nameLabel)
        }
        
    }
    


}

