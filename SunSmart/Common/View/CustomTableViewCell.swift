//
//  CustomTableViewCell.swift
//  BLE-OTA
//
//  Created by 袁科鸿 on 2022/12/8.
//

import UIKit

enum CustomCellStyle {
    /// 样式标题-内容
    case none
    /// 标题-内容-箭头
    case arrow
    /// 标题-内容（标题底部）
    case bottomSubtitle
    /// 样式图标-标题-内容-箭头
    case icon
    /// 样式图标-标题-底部内容
    case iconAddBottomSubtitle
}

class CustomTableViewCell: UITableViewCell {

    var iconImageView: UIImageView!
    var titleLabel : UILabel!
    var contentLabel : UILabel!
    var arrowImageView : UIImageView!
    var lineView : UIView!
    var cellStyle : CustomCellStyle = .none {
        didSet {
            if cellStyle == .none {
                self.arrowImageView.isHidden = true
                self.iconImageView.isHidden = true
                self.titleLabel.snp.remakeConstraints { make in
                    make.left.equalTo(SCRXFrom(16))
                    make.centerY.equalToSuperview()
                }
                self.contentLabel.snp.remakeConstraints { make in
                    make.left.equalTo(SCRXFrom(140))
                    make.right.equalTo(SCRXFrom(-16))
                    make.centerY.equalTo(titleLabel)
                }
            }else if cellStyle == .bottomSubtitle {
                self.iconImageView.isHidden = true
                self.arrowImageView.isHidden = true
                self.titleLabel.snp.remakeConstraints { make in
                    make.left.equalTo(SCRXFrom(16))
                    make.top.equalTo(SCRYFrom(12))
                }
                self.contentLabel.snp.remakeConstraints { make in
                    make.left.equalTo(self.titleLabel)
                    make.top.equalTo(self.titleLabel.snp.bottom).offset(SCRYFrom(3))
                }
                
            }else if cellStyle == .icon || cellStyle == .iconAddBottomSubtitle {
                self.iconImageView.isHidden = false
                
                if cellStyle == .iconAddBottomSubtitle {
                    self.arrowImageView.isHidden = true
                    self.titleLabel.snp.remakeConstraints { make in
                        make.left.equalTo(iconImageView.snp.right).offset(SCRXFrom(8))
                        make.top.equalTo(SCRYFrom(12))
                    }
                    
                    self.contentLabel.snp.remakeConstraints { make in
                        make.left.equalTo(self.titleLabel)
                        make.top.equalTo(self.titleLabel.snp.bottom).offset(SCRYFrom(3))
                    }
                }else {
                    self.arrowImageView.isHidden = false
                    self.titleLabel.snp.remakeConstraints { make in
                        make.left.equalTo(iconImageView.snp.right).offset(SCRXFrom(8))
                        make.centerY.equalToSuperview()
                    }
                    
                    self.contentLabel.snp.remakeConstraints { make in
                        make.right.equalTo(SCRXFrom(-36))
                        make.centerY.equalToSuperview()
//                        make.left.equalTo(SCRXFrom(140))
                    }
                }
                
            }else {
                self.titleLabel.snp.remakeConstraints { make in
                    make.left.equalTo(SCRXFrom(16))
                    make.centerY.equalToSuperview()
                }
                self.arrowImageView.isHidden = false
                self.contentLabel.snp.remakeConstraints { make in
                    make.right.equalTo(SCRXFrom(-36))
                    make.centerY.equalToSuperview()
                    make.left.equalTo(SCRXFrom(140))
                }
            }
        }
    }
    
    var iconX: CGFloat = SCRXFrom(16) {
        didSet {
            self.iconImageView.snp.updateConstraints { make in
                make.left.equalTo(iconX)
            }
            self.titleLabel.snp.remakeConstraints { make in
                make.left.equalTo(titleX)
                make.centerY.equalToSuperview()
            }
        }
    }
    
    var iconSize: CGSize? {
        didSet {
            self.iconImageView.snp.remakeConstraints { make in
                if iconSize != nil {
                    make.size.equalTo(iconSize!)
                }
                make.left.equalTo(iconX)
                make.centerY.equalToSuperview()
            }
        }
    }
    
    var titleX: CGFloat = SCRXFrom(16) {
        didSet {
            self.titleLabel.snp.remakeConstraints { make in
                make.left.equalTo(titleX)
                make.centerY.equalToSuperview()
            }
        }
    }
    
    
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
//        self.backgroundColor = RGB(19, 19, 23)
        
        iconImageView = UIImageView()
        iconImageView.isHidden = true
        contentView.addSubview(iconImageView)
        iconImageView.snp.makeConstraints { make in
            make.left.equalTo(iconX)
            make.centerY.equalToSuperview()
        }
        
        titleLabel = UILabel(text: "", textColor: TextBlack_Color, fontSize: 15)
        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.centerY.equalToSuperview()
        }
        
        contentLabel = UILabel(text: "", textColor: Message_Color, fontSize: 14)
        contentLabel.textAlignment = .right
        contentView.addSubview(contentLabel)
        contentLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(140))
            make.right.equalTo(SCRXFrom(-16))
            make.centerY.equalTo(titleLabel)
        }
        
        arrowImageView = UIImageView(image: UIImage(named: "arrow_right"))
        arrowImageView.isHidden = true
        contentView.addSubview(arrowImageView)
        arrowImageView.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-8))
            make.centerY.equalToSuperview()
        }
        
        lineView = UIView()
        lineView.backgroundColor = Line_Color
        contentView.addSubview(lineView)
        lineView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.bottom.equalTo(0)
            make.height.equalTo(1)
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}

struct CustomCellModel {
    
    /// 图标
    var icon: UIImage?
    /// 图片地址
    var iconUrl: String?
    
    /// 标题
    var title : String = ""
    /// 标题颜色（默认文本白色）
    var titleColor: UIColor = TextBlack_Color
    /// 标题字体
    var titleFont: UIFont = UIFont(name: FontName_Medium, size: SCRYFrom(15)) ?? FONTS(SCRYFrom(15))

    
    /// 内容
    var content: String?
    /// 内容颜色
    var contentColor: UIColor = RGB(134, 138, 160)
    /// 内容字体
    var contentFont: UIFont = FONTS(SCRYFrom(13))
    /// 是否显示箭头
//    var showArrow: Bool = false
    /// 是否显示分割线
    var showLine: Bool = true
    /// cell样式
    var style: CustomCellStyle = .none
   
    
}
