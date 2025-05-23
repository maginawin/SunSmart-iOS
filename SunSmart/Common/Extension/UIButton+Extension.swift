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
    

    func setImagePosition(position: ImagePosition, spacing: CGFloat) {
        
        let imageWidth = self.currentImage?.size.width ?? 0
        let imageHeight = self.currentImage?.size.height ?? 0
//    #pragma clang diagnostic push
//    #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        // Single line, no wrapping. Truncation based on the NSLineBreakMode.
        
        let attibutes = [NSAttributedString.Key.font : self.titleLabel?.font ?? FONTS(14)]
        
        var size = (self.currentTitle as? NSString)?.size(withAttributes: attibutes) ?? .zero
        if self.titleLabel?.numberOfLines != 1 {
            size = (self.currentTitle as? NSString)?.boundingRect(with: CGSize(width: self.frame.size.width, height: CGFloat(MAXFLOAT)), options: .usesLineFragmentOrigin, attributes: attibutes, context: nil).size ?? .zero
        }
        var labelWidth = size.width
        
        
        
        if position == .left || position == .right {
            if self.width > 0 && labelWidth > self.width - imageWidth - self.contentEdgeInsets.left - self.contentEdgeInsets.right {
                labelWidth = self.width - imageWidth - spacing - self.contentEdgeInsets.left - self.contentEdgeInsets.right
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
