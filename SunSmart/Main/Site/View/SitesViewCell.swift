//
//  SitesViewCell.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/9/23.
//

import UIKit

class SitesViewCell: UITableViewCell {

        private var bgView: UIView!
        var iconImageView: UIImageView!
        var nameLabel: UILabel!
        var timeLabel: UILabel!
        var spaceNumLabel: UILabel!
        var favoriteBtn: UIButton!
        var moreBtn: UIButton!
        
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
            
            iconImageView = UIImageView()
            bgView.addSubview(iconImageView)
            iconImageView.snp.makeConstraints { make in
                make.left.equalTo(SCRXFrom(8))
                make.centerY.equalToSuperview()
                make.width.height.equalTo(SCRXFrom(44))
            }
            
            nameLabel = UILabel(text: "Frist Floor", textColor: TextBlack_Color, fontSize: 14, fontWeight: .light)
            bgView.addSubview(nameLabel)
            nameLabel.snp.makeConstraints { make in
                make.left.equalTo(iconImageView.snp.right).offset(SCRXFrom(8))
                make.right.equalTo(SCRXFrom(-83))
                make.top.equalTo(SCRYFrom(19))
            }
            
//            timeLabel = UILabel(text: "8/7/2023 12:00 AM", textColor: RGB(100, 116, 139), fontSize: 14, fontWeight: .light)
//            bgView.addSubview(timeLabel)
//            timeLabel.snp.makeConstraints { make in
//                make.left.equalTo(nameLabel)
//                make.top.equalTo(nameLabel.snp.bottom).offset(SCRYFrom(6))
//            }
            
            spaceNumLabel = UILabel(text: "15 Spaces", textColor: RGB(100, 116, 139), fontSize: 14, fontWeight: .light)
            bgView.addSubview(spaceNumLabel)
            spaceNumLabel.snp.makeConstraints { make in
                make.left.equalTo(nameLabel)
                make.top.equalTo(nameLabel.snp.bottom).offset(SCRYFrom(8))
            }
            
            moreBtn = UIButton(normalImageName: "more_vertical", target: self, action: #selector(moreBtnClick))
            bgView.addSubview(moreBtn)
            moreBtn.snp.makeConstraints { make in
                make.right.equalTo(SCRXFrom(-4))
                make.centerY.equalToSuperview()
            }
            
            favoriteBtn = UIButton(normalImageName: "favourite_normal", selectedImageName: "favourite_selected", target: self, action: #selector(favoriteBtnClick))
            bgView.addSubview(favoriteBtn)
            favoriteBtn.snp.makeConstraints { make in
                make.right.equalTo(moreBtn.snp.left).offset(SCRXFrom(-4))
                make.centerY.equalToSuperview()
            }
            
        }
        


    }

//
//protocol SitesViewCellDelegate {
//
//    /// 点击更多事件回调
//    /// - Parameters:
//    ///   - cell: cell
//    ///   - point: 点击位置
//    func sitesViewCell(_ cell: SitesViewCell, didClickMore point: CGPoint)
//
//    /// 点击收藏事件回调
//    /// - Parameters:
//    ///   - cell: cell
//    ///   - isFavourite: 是否收藏
//    func sitesViewCell(_ cell: SitesViewCell, didClickFavourite isFavourite: Bool)
//
//}
