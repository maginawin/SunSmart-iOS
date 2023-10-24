//
//  LCWeakTimer.swift
//  BuiltToLast
//
//  Created by APPLE on 2019/11/15.
//  Copyright © 2019 lingchuang. All rights reserved.
//

import Foundation

class LCWeakTimer: NSObject {
 
    fileprivate weak var target: AnyObject!
    var selector: Selector!
    var timer: Timer!
    
    static func scheduledTimer(timeInterval: TimeInterval, aTarget: Any, selector aSelector: Selector, userInfo: Any?, repeats yesOrNo: Bool) -> Timer {
        
        let weakTimer = LCWeakTimer()
        weakTimer.target = aTarget as AnyObject
        weakTimer.selector = aSelector
        weakTimer.timer = Timer.init(timeInterval: timeInterval, target: weakTimer, selector: #selector(timerBack), userInfo: userInfo, repeats: yesOrNo)
        
        return weakTimer.timer
    }
    
    @objc private func timerBack() {
        if self.target != nil && self.selector != nil {
            self.target.perform(self.selector)
        }
    }
    
}
