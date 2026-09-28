//
//  UIBarButtonItem+Extension.swift
//  LightControl
//
//  Created by APPLE on 2019/8/30.
//  Copyright © 2019 lingyun. All rights reserved.
//

import UIKit


extension UIBarButtonItem {

    /// Configure each app-owned item before attaching it, including dynamically replaced items.
    @discardableResult
    func withoutSharedBackground() -> Self {
        if #available(iOS 26.0, *) {
            // Legacy .done image items become prominent buttons with the new system design.
            if image != nil, title == nil, style == .prominent {
                style = .plain
            }
            hidesSharedBackground = true
        }
        return self
    }

    /// Keep navigation-bar layout on a stationary container, separate from the rotating image.
    convenience init(loadingImageView: UIImageView) {
        let diameter: CGFloat = 30
        let container = UIView(frame: CGRect(x: 0, y: 0, width: diameter, height: diameter))
        container.translatesAutoresizingMaskIntoConstraints = false
        loadingImageView.translatesAutoresizingMaskIntoConstraints = false
        loadingImageView.contentMode = .scaleAspectFit
        container.addSubview(loadingImageView)
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: diameter),
            container.heightAnchor.constraint(equalToConstant: diameter),
            loadingImageView.widthAnchor.constraint(equalToConstant: diameter),
            loadingImageView.heightAnchor.constraint(equalToConstant: diameter),
            loadingImageView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            loadingImageView.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        self.init(customView: container)
        withoutSharedBackground()
    }
    
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
        withoutSharedBackground()
        
    }
    
}
