//
//  DeviceParameterData.swift
//  SunSmart
//
//  Created by yuankehong on 2025/5/8.
//

import Foundation
import NordicSigMeshSDK

class DeviceParameterData {

    /// pwm频率list
    static var pwmFrequencys: [Int] {
        var list: [Int] = []
        for index in 1...40 {
            list.append(index * 490)
        }
        return list
    }

    /// 过渡时间list
    static var transitionTimeDatas: [(timeInterval: TimeInterval, timeStr: String)] {
        var list: [(timeInterval: TimeInterval, timeStr: String)] = []
        for i in 0...29 {
            let time = Double(i) * 0.2
            list.append((TimeInterval(Double(i) * 0.2), timeStr: time.toSimplifyStr(maxDigits: 1) + "s"))
        }
        for i in 6...10 {
            list.append((TimeInterval(i), timeStr: "\(i)s"))
        }
        return list
    }

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
            case .motionSensitivityRange:
                return ("absolute_sensitivity".localizedString, "absolute_sensitivity_messsage".localizedString, 0...100, "%")
            case .defalutTransitionTime:
                return ("transition_time".localizedString, "transition_time_message".localizedString, nil, "s")
            case .behaviorAfterSetupSuccess:
                return ("behavior_after_setup_success".localizedString, "behavior_after_setup_success_note".localizedString, nil, "")
            case .changeControlPage:
                return ("change_control_page".localizedString, "change_control_page_message".localizedString, nil, "")
            case .absoluteCctRange:
                return ("absolute_cct_range".localizedString, "absolute_cct_range_message".localizedString, nil, "K")
            case .photosensorException:
                return ("photosensor_exception".localizedString, "photosensor_exception_note".localizedString, 1...100, "%")
            }
        }

        var rawValue: Int {
            switch self {
            case .pwmFrequency:
                return 1
            case .ratedPower:
                return 2
            case .motionSensitivityRange:
                return 3
            case .defalutTransitionTime:
                return 4
            case .behaviorAfterSetupSuccess:
                return 5
            case .changeControlPage:
                return 7
            case .absoluteCctRange:
                return 6
            case .photosensorException:
                return 8
            }
        }

        /// pwm频率
        case pwmFrequency
        /// 额定功率
        case ratedPower
        /// 移动感应灵敏度范围
        case motionSensitivityRange
        /// 默认过渡时间
        case defalutTransitionTime
        /// 设置参数完成状态
        case behaviorAfterSetupSuccess
        /// 控制页面类型
        case changeControlPage
        /// 绝对色温范围
        case absoluteCctRange
        /// 灯具内置光感异常保护
        case photosensorException
    }


}

struct DeviceParameterCctRangeData: Equatable {
    var lowerBound: UInt16
    var upperBound: UInt16

    static let `default` = DeviceParameterCctRangeData(range: NodeAbsoluteCctRange.defaultRange)

    init(range: ClosedRange<UInt16>) {
        lowerBound = Self.normalizedLower(range.lowerBound)
        upperBound = Self.normalizedUpper(range.upperBound)
    }

    private static func normalizedLower(_ value: UInt16) -> UInt16 {
        let rounded = roundedToStep(value)
        return min(max(rounded, NodeAbsoluteCctRange.minLowerBound), NodeAbsoluteCctRange.maxLowerBound)
    }

    private static func normalizedUpper(_ value: UInt16) -> UInt16 {
        let rounded = roundedToStep(value)
        return min(max(rounded, NodeAbsoluteCctRange.minUpperBound), NodeAbsoluteCctRange.maxUpperBound)
    }

    private static func roundedToStep(_ value: UInt16) -> UInt16 {
        let step = Int(NodeAbsoluteCctRange.step)
        let rounded = ((Int(value) + step / 2) / step) * step
        return UInt16(min(rounded, Int(UInt16.max)))
    }

    var range: ClosedRange<UInt16> {
        lowerBound...upperBound
    }
}
