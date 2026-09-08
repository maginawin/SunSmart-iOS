//
//  UIButton+Extension.swift
//  nRFMeshDemo
//
//  Created by 袁科鸿 on 2022/11/28.
//

import UIKit

public enum ImagePosition {
    case left //图片在左，文字在右，默认
    case right  //图片在右，文字在左
    case top   //图片在上，文字在下
    case bottom  //图片在下，文字在上
}

extension UIButton {
    
//    private static var showsTouchHighlightedKey = "showsTouchHighlighted"
//    
//    var showsTouchHighlighted: Bool {
//        get {
//            objc_getAssociatedObject(self, &UIButton.showsTouchHighlightedKey) as? Bool ?? false
//        } set {
//            objc_setAssociatedObject(self, &UIButton.showsTouchHighlightedKey, newValue, .OBJC_ASSOCIATION_ASSIGN)
//        }
//    }
    
    convenience init(title: String? = nil, titleSize: CGFloat? = nil, titleWeight: UIFont.Weight? = nil, titleColor: UIColor? = nil, fit: Bool = true, normalImageName: String? = nil, selectedImageName: String? = nil, target: AnyObject? = nil, action: Selector? = nil) {
        self.init()
        
        if title != nil {
            self.setTitle(title!, for: .normal)
        }
        if titleSize != nil {
            self.titleLabel?.font = UIFont.systemFont(ofSize: fit ? SCRYFrom(titleSize!) : titleSize!, weight: titleWeight ?? .regular)
        }
        if titleColor != nil {
            self.setTitleColor(titleColor!, for: .normal)
        }
        if let imageName = normalImageName, !imageName.isEmpty {
            self.setImage(UIImage(named: imageName), for: .normal)
        }
        if let imageName = selectedImageName, !imageName.isEmpty {
            self.setImage(UIImage(named: imageName), for: .selected)
        }
        if target != nil && action != nil {
            self.addTarget(target, action: action!, for: .touchUpInside)
        }
    }
    

    func setImagePosition(position: ImagePosition, spacing: CGFloat, btnMaxWidth: CGFloat? = nil) {
        
        var btnW = self.width
        if btnMaxWidth != nil {
            btnW = min(btnMaxWidth!, btnW)
        }
        
        let imageWidth = self.currentImage?.size.width ?? 0
        let imageHeight = self.currentImage?.size.height ?? 0
//    #pragma clang diagnostic push
//    #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        // Single line, no wrapping. Truncation based on the NSLineBreakMode.
        
        let attibutes = [NSAttributedString.Key.font : self.titleLabel?.font ?? FONTS(14)]
        
        var size = (self.currentTitle as? NSString)?.size(withAttributes: attibutes) ?? .zero
        if self.titleLabel?.numberOfLines != 1 {
            size = (self.currentTitle as? NSString)?.boundingRect(with: CGSize(width: btnW, height: CGFloat(MAXFLOAT)), options: .usesLineFragmentOrigin, attributes: attibutes, context: nil).size ?? .zero
        }
        var labelWidth = size.width
        
        
        
        if position == .left || position == .right {
            if btnW > 0 && labelWidth > btnW - imageWidth - self.contentEdgeInsets.left - self.contentEdgeInsets.right {
                labelWidth = btnW - imageWidth - spacing - self.contentEdgeInsets.left - self.contentEdgeInsets.right
            }
        }
    
        let labelHeight = size.height
        
        let imageOffsetX = (imageWidth + labelWidth) / 2 - imageWidth / 2;//image中心移动的x距离
        let imageOffsetY = imageHeight / 2 + spacing / 2;//image中心移动的y距离
        let labelOffsetX = (imageWidth + labelWidth / 2) - (imageWidth + labelWidth) / 2;//label中心移动的x距离
        let labelOffsetY = labelHeight / 2 + spacing / 2;//label中心移动的y距离
        
        let tempWidth = max(labelWidth, imageWidth)
        let changedWidth = labelWidth + imageWidth - tempWidth
        let tempHeight = max(labelHeight, imageHeight)
        let changedHeight = labelHeight + imageHeight + spacing - tempHeight
        
        var imageEdgeInsets = UIEdgeInsets.zero
        var titleEdgeInsets = UIEdgeInsets.zero
        var contentEdgeInsets = UIEdgeInsets.zero
        
        
        switch position {
        case .left:
            
            imageEdgeInsets = UIEdgeInsets(top: 0, left: -spacing/2, bottom: 0, right: spacing/2)
            titleEdgeInsets = UIEdgeInsets(top: 0, left: spacing/2, bottom: 0, right: -spacing/2)
            contentEdgeInsets = UIEdgeInsets(top: 0, left: spacing/2, bottom: 0, right: spacing/2)
                
        case .right:
                imageEdgeInsets = UIEdgeInsets(top: 0, left: labelWidth + spacing/2, bottom: 0, right: -(labelWidth + spacing/2))
                titleEdgeInsets = UIEdgeInsets(top: 0, left: -(imageWidth + spacing/2), bottom: 0, right: imageWidth + spacing/2)
                contentEdgeInsets = UIEdgeInsets(top: 0, left: spacing/2, bottom: 0, right: spacing/2)
                
        case .top:
//            imageOffsetY = (labelHeight + imageHeight + spacing) / 2
            imageEdgeInsets = UIEdgeInsets(top: -imageOffsetY, left: imageOffsetX, bottom: imageOffsetY, right: -imageOffsetX)
            titleEdgeInsets = UIEdgeInsets(top: labelOffsetY, left: -labelOffsetX, bottom: -labelOffsetY, right: labelOffsetX)
            contentEdgeInsets = UIEdgeInsets(top: imageOffsetY, left: -changedWidth/2, bottom: changedHeight-imageOffsetY, right: -changedWidth/2)
                
        case .bottom:
            imageEdgeInsets = UIEdgeInsets(top: imageOffsetY, left: imageOffsetX, bottom: -imageOffsetY, right: -imageOffsetX)
            titleEdgeInsets = UIEdgeInsets(top: -labelOffsetY, left: -labelOffsetX, bottom: labelOffsetY, right: labelOffsetX)
            contentEdgeInsets = UIEdgeInsets(top: changedHeight, left: -changedWidth/2, bottom: 0, right: -changedWidth/2)
        }
        
        self.imageEdgeInsets = imageEdgeInsets
        self.titleEdgeInsets = titleEdgeInsets
        if self.contentEdgeInsets == .zero {
            self.contentEdgeInsets = contentEdgeInsets
        }
        
    }
    
}

// Opt-in layout for the Scan and Identify buttons; other legacy buttons are unchanged.
extension UIButton {
    func applyPlainContentLayout(insets: NSDirectionalEdgeInsets, imagePadding: CGFloat = 0) {
        let font = titleLabel?.font ?? UIFont.systemFont(ofSize: 14)
        var content = UIButton.Configuration.plain()
        content.cornerStyle = .fixed
        content.background.cornerRadius = layer.cornerRadius
        content.contentInsets = insets
        content.imagePlacement = .leading
        content.imagePadding = imagePadding
        configuration = content
        configurationUpdateHandler = { button in
            guard var content = button.configuration else { return }
            let color = button.currentTitleColor
            content.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                var attributes = attributes
                attributes.font = font
                attributes.foregroundColor = color
                return attributes
            }
            button.configuration = content
        }
        setNeedsUpdateConfiguration()
    }
}

/// A full-width selection button whose arrow stays at the trailing edge as its title changes.
final class TrailingImageButton: UIButton {
    let contentLabel = UILabel()
    let trailingImageView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentLabel.lineBreakMode = .byTruncatingTail
        contentLabel.isUserInteractionEnabled = false
        contentLabel.isAccessibilityElement = false
        trailingImageView.isUserInteractionEnabled = false
        trailingImageView.isAccessibilityElement = false
        trailingImageView.setContentHuggingPriority(.required, for: .horizontal)
        trailingImageView.setContentCompressionResistancePriority(.required, for: .horizontal)
        addSubview(contentLabel)
        addSubview(trailingImageView)
        contentLabel.translatesAutoresizingMaskIntoConstraints = false
        trailingImageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            contentLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: SCRXFrom(8)),
            contentLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            contentLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingImageView.leadingAnchor, constant: -SCRXFrom(6)),
            trailingImageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            trailingImageView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        contentLabel.text = currentTitle
        contentLabel.font = titleLabel?.font
        contentLabel.textColor = currentTitleColor
        trailingImageView.image = currentImage
        trailingImageView.tintColor = tintColor
        super.layoutSubviews()
        titleLabel?.isHidden = true
        imageView?.isHidden = true
    }
}
