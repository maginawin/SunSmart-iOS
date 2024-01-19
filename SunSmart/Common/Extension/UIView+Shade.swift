//
//  UIView+Shade.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/1/15.
//

import Foundation

extension UIView {
    
    func show(inView: UIView = UIApplication.shared.keyWindow(), animation: (()->Void)?) {
        
        let shadeView = UIView(frame: inView.bounds)
        shadeView.backgroundColor = RGB(0, 0, 0, 0.3)
        inView.addSubview(shadeView)
        
        inView.addSubview(self)
        
        shadeView.alpha = 0
        UIView.animate(withDuration: 0.3) {
            shadeView.alpha = 1
            animation?()
        }
    }

    
}
