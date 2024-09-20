//
//  CustomTableViewCell.swift
//  BLE-OTA
//
//  Created by 袁科鸿 on 2022/12/8.
//

import UIKit
import SnapKit

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
    /// 标题-开关
    case `switch`
}

class CustomTableViewCell: UITableViewCell {

    var iconImageView: UIImageView!
    var titleLabel : UILabel!
    var contentLabel : UILabel!
    var arrowImageView : UIImageView!
    var enabledSwitch: UISwitch!
    private var enabledBtn: UIButton!
    var lineView : UIView!
    var iconImageClickCallback: (()->Void)? {
        didSet {
            iconImageView.isUserInteractionEnabled = true
        }
    }
    /// 开关点击事件
    var switchActionCallback: ((Bool)->Void)?
    
    var cellStyle : CustomCellStyle = .none {
        didSet {
            
            self.enabledSwitch.isHidden = true
            
            switch cellStyle {
            case .none:
                self.arrowImageView.isHidden = true
                self.iconImageView.isHidden = true
                self.titleLabel.snp.remakeConstraints { make in
                    make.left.equalTo(SCRXFrom(16))
                    make.centerY.equalToSuperview()
                }
                self.contentLabel.snp.remakeConstraints { make in
//                    make.left.equalTo(SCRXFrom(140))
                    make.width.lessThanOrEqualTo(SCRXFrom(200))
                    make.right.equalTo(SCRXFrom(-16))
                    make.centerY.equalTo(titleLabel)
                }
            case .bottomSubtitle:
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
            case .icon, .iconAddBottomSubtitle:
                self.iconImageView.isHidden = false
                
                if cellStyle == .iconAddBottomSubtitle {
                    self.arrowImageView.isHidden = true
                    
//                    self.iconImageView.snp.remakeConstraints { make in
//                        make.left.equalTo(iconX)
//                        make.top.equalTo(SCRYFrom(3))
//                    }
                    
                    self.titleLabel.snp.remakeConstraints { make in
                        make.left.equalTo(self.titleX)
                        make.centerY.equalTo(self.iconImageView)
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
                        make.width.lessThanOrEqualTo(SCRXFrom(200))
                    }
                }
            case .switch:
                self.enabledSwitch.isHidden = false
                self.contentLabel.snp.updateConstraints { make in
                    make.right.equalTo(SCRXFrom(-66))
                }
                
                self.arrowImageView.isHidden = true
            default:
                self.titleLabel.snp.remakeConstraints { make in
                    make.left.equalTo(SCRXFrom(16))
                    make.centerY.equalToSuperview()
                }
                self.arrowImageView.isHidden = false
                self.contentLabel.snp.remakeConstraints { make in
                    make.right.equalTo(SCRXFrom(-36))
                    make.centerY.equalToSuperview()
//                    make.left.equalTo(SCRXFrom(140))
                    make.width.lessThanOrEqualTo(SCRXFrom(200))
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
    
    var iconY: CGFloat? {
        didSet {
            guard let y = iconY else { return }
            self.iconImageView.snp.remakeConstraints { make in
                if iconSize != nil {
                    make.size.equalTo(iconSize!)
                }
                make.left.equalTo(iconX)
                make.top.equalTo(y)
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
    
    var titleY: CGFloat? {
        didSet {
            guard let y = titleY else { return }
            self.titleLabel.snp.remakeConstraints { make in
                make.left.equalTo(titleX)
                make.top.equalTo(y)
            }
        }
    }
    
    var titleMaxWidth: CGFloat? {
        didSet {
            guard let maxWidth = titleMaxWidth else {
                return
            }
            self.titleLabel.snp.remakeConstraints { make in
                make.left.equalTo(titleX)
                if let y = titleY {
                    make.top.equalTo(y)
                }else {
                    make.centerY.equalToSuperview()
                }
                make.width.lessThanOrEqualTo(maxWidth)
            }
        }
    }
    
    /// 设置内容文本与标题水平布局优先级
    var contentHorizontalPriority: UILayoutPriority? {
        didSet {
            
            contentLabel.setContentCompressionResistancePriority(contentHorizontalPriority ?? .defaultLow, for: .horizontal)
            contentLabel.snp.remakeConstraints { make in
                make.left.equalTo(titleLabel.snp.right).offset(SCRXFrom(20))
                if cellStyle == .switch {
                    make.right.equalTo(SCRXFrom(-66))
                }else {
                    make.right.equalTo(SCRXFrom(-16))
                }
                make.centerY.equalTo(titleLabel)
            }
        }
    }
    
    
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
//        self.backgroundColor = RGB(19, 19, 23)
        
        iconImageView = UIImageView()
        iconImageView.isHidden = true
        iconImageView.isUserInteractionEnabled = false
        iconImageView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(iconImageViewAction)))
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
        
        enabledSwitch = UISwitch()
        enabledSwitch.onTintColor = Bar_Color
        enabledSwitch.tintColor = RGB(207, 207, 207)
        enabledSwitch.isHidden = true
        contentView.addSubview(enabledSwitch)
        enabledSwitch.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-12))
            make.centerY.equalTo(titleLabel)
        }
        
        enabledBtn = UIButton(target: self, action: #selector(enabledBtnAction))
        enabledSwitch.addSubview(enabledBtn)
        enabledBtn.snp.makeConstraints { make in
            make.edges.equalTo(enabledSwitch)
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
    
    @objc private func iconImageViewAction() {
        
        iconImageClickCallback?()
    }
    
    @objc private func enabledBtnAction() {
        switchActionCallback?(!enabledSwitch.isOn)
    }
    
}

class CustomCellModel {
    
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
   
    init(icon: UIImage? = nil, iconUrl: String? = nil, title: String, titleColor: UIColor? = nil, titleFont: UIFont? = nil, content: String? = nil, contentColor: UIColor? = nil, contentFont: UIFont? = nil, showLine: Bool = true, style: CustomCellStyle = .none) {
        self.icon = icon
        self.iconUrl = iconUrl
        self.title = title
        if titleColor != nil {
            self.titleColor = titleColor!
        }
        if titleFont != nil {
            self.titleFont = titleFont!
        }
        self.content = content
        if contentColor != nil {
            self.contentColor = contentColor!
        }
        if contentFont != nil {
            self.contentFont = contentFont!
        }
        self.showLine = showLine
        self.style = style
    }
    
}

extension UITableViewCell {
    
    func configureCell(isFirst: Bool, isLast: Bool) {
        let cornerRadius: CGFloat = SCRYFrom(10)
        var corners: CACornerMask = []
        
        // 设置顶部圆角
        if isFirst {
            corners.insert(.layerMinXMinYCorner)
            corners.insert(.layerMaxXMinYCorner)
        }
        
        // 设置底部圆角
        if isLast {
            corners.insert(.layerMinXMaxYCorner)
            corners.insert(.layerMaxXMaxYCorner)
        }
        
        // 设置圆角
        self.backgroundColor = .clear
        self.contentView.backgroundColor = .white
        if isFirst || isLast {
            self.contentView.layer.cornerRadius = cornerRadius
            self.contentView.layer.maskedCorners = corners
            self.contentView.layer.masksToBounds = true
        }
    }
    
}
