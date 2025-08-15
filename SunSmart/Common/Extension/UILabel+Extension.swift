//
//  UILabel+Extension.swift
//  QiongLiaoRunning
//
//  Created by APPLE on 2018/4/12.
//  Copyright © 2018年 net.qiongliao.www. All rights reserved.
//

import UIKit

extension UILabel {

    convenience init(text : String?, textColor : UIColor = TextBlack_Color, fontSize: CGFloat = 15, fontName: String? = nil, fontWeight: UIFont.Weight? = nil, fit: Bool = true) {
        self.init()
        
        self.text = text
        self.textColor = textColor
        
        let size = fit ? FontFit(fontSize) : fontSize
        if fontName != nil {
            self.font = UIFont(name: fontName!, size: size)
        }else if fontWeight != nil {
            self.font = UIFont.systemFont(ofSize: size, weight: fontWeight!)
        }else {
            self.font = UIFont.systemFont(ofSize: size)
        }
        
    }
    
//    class func labelWith(text : String?, textColor : UIColor?, fontSize: CGFloat) -> UILabel {
//        return UILabel.labelWith(text: text, textColor: textColor, fontSize: fontSize, fontName:nil)
//    }
//    
//    class func labelWith(text : String?, textColor : UIColor?, fontSize: CGFloat, fontName : String?) -> UILabel {
//        let label = UILabel()
//        label.text = (text != nil) ? text : ""
//        
//        label.textColor = textColor != nil ? textColor : UIColor.black
//        
//        label.font = fontName != nil ? UIFont.init(name: fontName!, size: fontSize > 0 ? SCRYFrom(fontSize) : SCRYFrom(15)) : UIFont.systemFont(ofSize: fontSize > 0 ? SCRYFrom(fontSize) : SCRYFrom(15))
//        return label
//    }

}



