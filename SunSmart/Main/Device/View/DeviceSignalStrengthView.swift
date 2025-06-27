//
//  DeviceSignalStrengthView.swift
//  SunSmart
//
//  Created by yuankehong on 2025/6/20.
//

import UIKit

class DeviceSignalStrengthView: UIView {
    
    private let totalBars = 5
    private var barViews: [UIView] = []
    
    private let barWidth: CGFloat = SCRXFrom(8)
    private let barSpacing: CGFloat = SCRXFrom(4)
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupBars()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupBars()
    }
    
    private func setupBars() {
        for _ in 0..<totalBars {
            let bar = UIView()
            bar.backgroundColor = RGB(220, 220, 200)
            addSubview(bar)
            barViews.append(bar)
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
//        let maxHeight = bounds.height
        for (index, bar) in barViews.enumerated() {
//            let heightMultiplier = CGFloat(index + 1) / CGFloat(totalBars)
//            let barHeight = maxHeight * heightMultiplier
            let x = CGFloat(index) * (barWidth + barSpacing)
//            let y = maxHeight - barHeight
            bar.frame = CGRect(x: x, y: 0, width: barWidth, height: self.height)
        }
    }
    
    /// 设置 RSSI（信号强度）值
    func setSignalStrength(rssi: Int) {
        let level = signalLevel(for: rssi)
        let color = colorForLevel(level)
        
        for (index, bar) in barViews.enumerated() {
            if index < level {
                bar.backgroundColor = color
            } else {
                bar.backgroundColor = RGB(220, 220, 200)
            }
        }
    }
    
    /// 根据 RSSI 值获取格数（1~5）
    private func signalLevel(for rssi: Int) -> Int {
        switch rssi {
        case -40...(-25):
            return 5
        case -55...(-41):
            return 4
        case -70...(-56):
            return 3
        case -85...(-71):
            return 2
        case -100...(-86):
            return 1
        default:
            return 0
        }
    }
    
    /// 根据信号等级返回颜色
    private func colorForLevel(_ level: Int) -> UIColor {
        switch level {
        case 5, 4, 3:
            return Green_Color
        case 2:
            return Yellow_Color
        case 1:
            return RGB(255, 72, 49)
        default:
            return RGB(220, 220, 220)
        }
    }
    
    
}
