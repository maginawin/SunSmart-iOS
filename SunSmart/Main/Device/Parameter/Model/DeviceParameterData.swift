//
//  DeviceParameterData.swift
//  SunSmart
//
//  Created by yuankehong on 2025/5/8.
//

import Foundation

class DeviceParameterData {
    /// 类型
    let type: ParameterType
    /// 数据
    var data: Any?
    /// 是否启用
    var enable: Bool = true
    
    init(type: ParameterType, data: Any? = nil, enable: Bool = true) {
        self.type = type
        self.data = data
        self.enable = enable
    }
    
    /// 参数类型
    enum ParameterType: Equatable {
        
        var data: (title: String, message: String, range: ClosedRange<Int>?, unit: String) {
            switch self {
            case .pwmFrequency:
                return ("pwm_frequency".localizedString, "pwm_frequency_message".localizedString, nil, "Hz")
            case .ratedPower:
                return ("rated_power".localizedString, "rated_power_message".localizedString, 1...99999, "W")
            }
        }
        
        var rawValue: Int {
            switch self {
            case .pwmFrequency:
                return 1
            case .ratedPower:
                return 2
            }
        }
        
        /// pwm频率
        case pwmFrequency
        /// 额定功率
        case ratedPower
    }

    
}


