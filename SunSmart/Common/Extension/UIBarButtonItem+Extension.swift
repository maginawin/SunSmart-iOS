//
//  UIBarButtonItem+Extension.swift
//  LightControl
//
//  Created by APPLE on 2019/8/30.
//  Copyright © 2019 lingyun. All rights reserved.
//

import UIKit


extension UIBarButtonItem {
    
    convenience init(title: String, color: UIColor, font: UIFont = UIFont.systemFont(ofSize: 16, weight: .light), target: AnyObject?, sel: Selector?) {
        //        let barButtonItem = UIBarButtonItem(title: title, style: .done, target: tagter, action: sel)
        self.init()
        self.title = title
        if target != nil && sel != nil {
            self.target = target
            self.action = sel!
        }
        
        var attributes = [NSAttributedString.Key.font: font, NSAttributedString.Key.foregroundColor: color]
        self.setTitleTextAttributes(attributes, for: .normal)
        self.setTitleTextAttributes(attributes, for: .highlighted)
        
        attributes.updateValue(color.withAlphaComponent(0.5), forKey: .foregroundColor)
        self.setTitleTextAttributes(attributes, for: .disabled)
        
    }
    
}
