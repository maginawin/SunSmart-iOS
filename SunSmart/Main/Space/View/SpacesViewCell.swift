//
//  SpacesViewCell.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/9/25.
//

import UIKit

class SpacesViewCell: UITableViewCell {

    private var bgView: UIView!
    var iconImageView: UIImageView!
    var nameLabel: UILabel!
    var favoriteBtn: UIButton!
    var moreBtn: UIButton!
    var luminairesLabel: UILabel!
    var switchesLabel: UILabel!
    var groupsLabel: UILabel!
    var scenesLabel: UILabel!
    var schedulesLabel: UILabel!
    var timeLabel: UILabel!
    
    
//    var delegate: SitesViewCellDelegate?
    /// 点击更多回调
    var clickMoreCallback: ((CGPoint)->Void)?
    /// 点击收藏回调
    var clickFavouriteCallback: ((Bool)->Void)?
    
    
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
        clickMoreCallback?(point)
//        delegate?.sitesViewCell(self, didClickMore: point)
    }
    /// 收藏
    @objc private func favoriteBtnClick() {
        
        favoriteBtn.isSelected = !favoriteBtn.isSelected
//        delegate?.sitesViewCell(self, didClickFavourite: favoriteBtn.isSelected)
        clickFavouriteCallback?(favoriteBtn.isSelected)
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
        
        nameLabel = UILabel(text: "Frist Floor", textColor: TextBlack_Color, fontSize: 14)
        bgView.addSubview(nameLabel)
        nameLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-99))
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
        
    }
    


}

