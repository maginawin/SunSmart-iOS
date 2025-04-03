//
//  ContinuousTapGestureRecognizer.swift
//  AIROMesh
//
//  Created by 袁科鸿 on 2023/6/1.
//

import UIKit

class ContinuousTapGestureRecognizer: UITapGestureRecognizer {
    
    /// 触发事件的点击次数
    var touchsRequiredNumber: Int = 1
    /// 当前点击次数
    var currentTouchsNumber: Int = 0
    /// 点击时效
    var touchsRequiredDuration: TimeInterval = 0
    /// 事件触发对象
    fileprivate weak var responseTarget: AnyObject?
    /// 事件触发对象方法
    private var responseAction: Selector?
    /// 计时定时器
    private var timer: Timer?
    
    
    convenience init(target: Any?, action: Selector?, numberOfTouchesRequired: Int = 1, duration: TimeInterval = 0) {
        
        self.init()
        self.touchsRequiredNumber = numberOfTouchesRequired
        self.touchsRequiredDuration = duration
        self.responseTarget = target as AnyObject?
        self.responseAction = action
        self.addTarget(self, action: #selector(touchsTapAction))
    }
    
    /// 点击事件
    @objc private func touchsTapAction() {
        if timer == nil {
            startTimer()
        }
        currentTouchsNumber += 1
        if self.currentTouchsNumber >= self.touchsRequiredNumber {
            stopTimer()
            if let target = responseTarget, let action = self.responseAction {
                _ = target.perform(action)
            }
        }
    }
    
    private func startTimer() {
        print("开始计数")
        timer = Timer(timeInterval: self.touchsRequiredDuration, repeats: false, block: {[weak self] _ in
            self?.stopTimer()
            print("未通过")
        })
        RunLoop.current.add(timer!, forMode: .common)
    }
    
    private func stopTimer() {
        currentTouchsNumber = 0
        timer?.invalidate()
        timer = nil
    }
    
    deinit {
        stopTimer()
    }
    
}
