//
//  Profile.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/3/5.
//

import Foundation
import NordicSigMeshSDK

class Profile: Copyable {
    
    /// 灯光阶段调节数据
    class LightData: Copyable {
         
        struct TimePickerData {
            enum TimeType {
                case t1
                case t2
                case t3
                case t4
                case t5
            }
            // 每个时间单元
            struct TimeItem {
                /// 描述
                let name: String
                /// 秒
                let second: Int
            }
            
            let type: String
            let title: String
            let items: [TimeItem]
            
            /// 可供选择的时间数据
            static var pickerTimes: [TimeType: TimePickerData] = {
                
                // 过渡时间 T1 T3 T5
                var fadeTimeItems: [TimePickerData.TimeItem] = []
                for i in 0...60 {
                    fadeTimeItems.append(TimePickerData.TimeItem(name: "\(i) sec", second: i))
                }

                // 阶段时间 T2 T4
                var phasesTimeItems: [TimePickerData.TimeItem] = []
                phasesTimeItems.append(TimePickerData.TimeItem(name: "5 sec", second: 5))
                phasesTimeItems.append(TimePickerData.TimeItem(name: "10 sec", second: 10))
                for i in 1...60 {
                    phasesTimeItems.append(TimePickerData.TimeItem(name: "\(i) min", second: i * 60))
                }
                phasesTimeItems.append(TimePickerData.TimeItem(name: "infinite".localizedString, second: 0xFFFFFF))
                
                var t4TimeItems = phasesTimeItems
                t4TimeItems.insert(TimePickerData.TimeItem(name: "0 sec", second: 0), at: 0)
                
                let t1 = TimePickerData(type: "T1", title: "fade_time".localizedString, items: fadeTimeItems)
                let t2 = TimePickerData(type: "T2", title: "hold_time".localizedString, items: phasesTimeItems)
                let t3 = TimePickerData(type: "T3", title: "fade_time".localizedString, items: fadeTimeItems)
                let t4 = TimePickerData(type: "T4", title: "prolong_time".localizedString, items: t4TimeItems)
                let t5 = TimePickerData(type: "T5", title: "fade_time".localizedString, items: fadeTimeItems)
                
                return [.t1: t1, .t2: t2, .t3: t3, .t4: t4, .t5: t5]
            }()
            
            /// 时间描述
            static func timeDetail(type: TimeType, second: Int) -> String {
                guard let time = pickerTimes[type], let item = time.items.first(where: { $0.second == second }) else {
                    return second >= 60 ? "\(second / 60) min" : "\(second) sec"
                }
                var name = item.name.replacingOccurrences(of: " ", with: "")
                name = name.replacingOccurrences(of: "sec", with: "s")
                return name
            }
            
        }
        
        /// 灯光数据
        var data: (highEndTrim: Int, lowEndTrim: Int, occupancyLevel: Int, vacantLevel: Int, taskLevel: Int, autoMinLevel: Int, autoMinLevelEnabled: Bool, t1: Int, t2: Int, t3: Int, t4: Int, t5: Int) {
            
            var highEndTrim = 100
            var lowEndTrim = 0
            var occupancyLevel = 100
            var vacantLevel = 50
            var taskLevel = 100
            var autoMinLevel = 0
            var autoMinLevelEnabled = false
            var t1 = 2
            var t2 = 1200
            var t3 = 2
            var t4 = 600
            var t5 = 2
            
            levels.forEach { type in
                switch type {
                case .lightnessRange(let range):
                    highEndTrim = range.upperBound
                    lowEndTrim = range.lowerBound
                    autoMinLevel = lowEndTrim
                case .occupancyLevel(let value):
                    occupancyLevel = value
                case .vacantLevel(let value):
                    vacantLevel = value
                case .autoMinValue(let value, let enabled):
                    if enabled {
                        autoMinLevel = value
                    }
                    autoMinLevelEnabled = enabled
                case .taskLevel(let value):
                    taskLevel = value
                }
            }
            
            times.forEach { time in
                switch time {
                case .t1(let value):
                    t1 = value
                case .t2(let value):
                    t2 = value
                case .t3(let value):
                    t3 = value
                case .t4(let value):
                    t4 = value
                case .t5(let value):
                    t5 = value
                }
            }
            return (highEndTrim, lowEndTrim, occupancyLevel, vacantLevel, taskLevel, autoMinLevel, autoMinLevelEnabled, t1, t2, t3, t4, t5)
        }
        
        /// 更新level数据
        func updateLevel(lightType: LevelType) {
            if let index = levels.firstIndex(where: { $0.rawValue == lightType.rawValue }) {
                levels.replaceSubrange(index...index, with: [lightType])
            }
        }
        
        /// 更新time数据
        func updateTime(time: Time) {
            if let index = times.firstIndex(where: { $0.rawValue == time.rawValue }) {
                times.replaceSubrange(index...index, with: [time])
            }
        }
        
        enum LevelType {
            var rawValue: Int {
                switch self {
                case .lightnessRange:
                    return 1
                case .occupancyLevel:
                    return 2
                case .vacantLevel:
                    return 3
                case .autoMinValue:
                    return 4
                case .taskLevel:
                    return 5
                }
            }
            /// 亮度范围 High-end trim/Low-end trim
            case lightnessRange(_ range: ClosedRange<Int>)
            /// 占用阶段亮度（第一阶段）Lux/%
            case occupancyLevel(_ value: Int)
            /// 空置阶段亮度（第二阶段）Lux/%
            case vacantLevel(_ value: Int)
            /// 设备根据环境光自动调节的最低亮度
            case autoMinValue(_ value: Int, enabled: Bool = false)
            /// 使区域内环境光维持的lux值 / 手动控制On亮度值
            case taskLevel(_ lux: Int)
        }
        
        enum Time {
            var rawValue: Int {
                switch self {
                case .t1:
                    return 1
                case .t2:
                    return 2
                case .t3:
                    return 3
                case .t4:
                    return 4
                case .t5:
                    return 5
                }
            }
            
            case t1(_ second: Int)
            case t2(_ second: Int)
            case t3(_ second: Int)
            case t4(_ second: Int)
            case t5(_ second: Int)
        }
        /// 阶段调节数据
        var levels: [LevelType] = []
        /// 阶段调节时间
        var times: [Time] = []
        
        init() {
            
        }
        /// 初始化灯光数据
        /// - Parameters:
        ///   - profileType: 配置类型
        ///   - highEndTrim: 亮度最大输出 50~100%
        ///   - lowEndTrim: 亮度最小输出 0~30%
        ///   - occupancyLevel: 第一阶段亮度/照度
        ///   - vacantLevel: 第二阶段亮度/照度
        ///   - taskLevel: 环境光维持照度
        ///   - autoMinLevel: 环境光补偿最低亮度 0~30%  255: unenabled
        ///   - t1: 进入第一阶段过渡时间
        ///   - t2: 第一阶段维持时间
        ///   - t3: 进入第二阶段过渡时间
        ///   - t4: 第二阶段维持时间
        ///   - t5: 进入待机过渡时间
        init(profileType: ProfileType, highEndTrim: Int, lowEndTrim: Int, occupancyLevel: Int, vacantLevel: Int, taskLevel: Int, autoMinLevel: Int, t1: Int, t2: Int, t3: Int, t4: Int, t5: Int) {
            
            switch profileType {
            case .occupancy_daylight, .vacancy_daylight:
                
                levels = [.lightnessRange(lowEndTrim...highEndTrim), .occupancyLevel(occupancyLevel), .vacantLevel(vacantLevel), .autoMinValue(autoMinLevel, enabled: autoMinLevel <= 30)]
                times = [.t1(t1), .t2(t2), .t3(t3), .t4(t4), .t5(t5)]
            case .occupancy, .vacancy:
                levels = [.lightnessRange(lowEndTrim...highEndTrim), .occupancyLevel(occupancyLevel), .vacantLevel(vacantLevel)]
                times = [.t1(t1), .t2(t2), .t3(t3), .t4(t4), .t5(t5)]
            case .daylight:
                levels = [.lightnessRange(lowEndTrim...highEndTrim), .taskLevel(taskLevel), .autoMinValue(autoMinLevel, enabled: autoMinLevel <= 30)]
                times = [.t1(t1)]
            case .manualControl:
                levels = [.lightnessRange(lowEndTrim...highEndTrim), .taskLevel(taskLevel)]
                times = [.t1(t1)]
            }
            
        }
        
        func copy() -> Self {
            let lightData = LightData()
            lightData.levels = levels
            lightData.times = times
            return lightData as! Self
        }
        
        static func == (lhs: LightData, rhs: LightData) -> Bool {
            let lhsData = lhs.data
            let rhsData = rhs.data
            return lhsData.highEndTrim == rhsData.highEndTrim && lhsData.lowEndTrim == rhsData.lowEndTrim && lhsData.occupancyLevel == rhsData.occupancyLevel && lhsData.vacantLevel == rhsData.vacantLevel && lhsData.taskLevel == rhsData.taskLevel && lhsData.autoMinLevel == rhsData.autoMinLevel && lhsData.autoMinLevelEnabled == rhsData.autoMinLevelEnabled && lhsData.t1 == rhsData.t1 && lhsData.t2 == rhsData.t2 && lhsData.t3 == rhsData.t3 && lhsData.t4 == rhsData.t4 && lhsData.t5 == rhsData.t5
        }
        
    }
    
    /// 类型
    enum ProfileType {
        
        var rawValue: Int {
            switch self {
            case .occupancy_daylight:
                return 1
            case .vacancy_daylight:
                return 2
            case .occupancy:
                return 3
            case .vacancy:
                return 4
            case .daylight:
                return 5
            case .manualControl:
                return 6
            }
        }
        
        
        init?(rawValue: Int) {
            switch rawValue {
            case 1:
                self = .occupancy_daylight
            case 2:
                self = .vacancy_daylight
            case 3:
                self = .occupancy
            case 4:
                self = .vacancy
            case 5:
                self = .daylight
            case 6:
                self = .manualControl
            default:
                return nil
            }
        }
        
        /// 所需的设备
        enum RequiredDeviceType {
            var data: (name: String, imageName: String) {
                switch self {
                case .luminaire:
                    return ("profile_required_luminaire".localizedString, "profile_device_luminaire")
                case .lightSensor:
                    return ("profile_required_lightSensor".localizedString, "profile_device_lightsensor")
                case .occupancySensor:
                    return ("profile_required_occupancy_sensor".localizedString, "profile_device_occupancy_sensor")
                case .manualControl:
                    return ("profile_required_manual_control".localizedString, "profile_device_manual_control")
                }
            }
            /// 灯
            case luminaire
            /// 光照传感器
            case lightSensor
            /// 占用传感器
            case occupancySensor
            /// 开关面板
            case manualControl
        }
        
        /// 简介
        var instruction: (name: String, imageName: String, description: String, requireds: [RequiredDeviceType]) {
            switch self {
            case .occupancy_daylight:
                return ("profile_occupancy_daylight".localizedString, "profile_occupancy_daylight", "profile_occupancy_daylight_desc".localizedString, [.luminaire, .lightSensor, .occupancySensor])
            case .vacancy_daylight:
                return ("profile_vacancy_daylight".localizedString, "profile_vacancy_daylight", "profile_vacancy_daylight_desc".localizedString, [.luminaire, .lightSensor, .manualControl, .occupancySensor])
            case .occupancy:
                return ("profile_occupancy".localizedString, "profile_occupancy", "profile_occupancy_desc".localizedString, [.luminaire, .lightSensor])
            case .vacancy:
                return ("profile_vacancy".localizedString, "profile_vacancy", "profile_vacancy_desc".localizedString, [.luminaire, .occupancySensor, .manualControl])
            case .daylight:
                return ("profile_daylight".localizedString, "profile_daylight", "profile_daylight_desc".localizedString, [.luminaire, .lightSensor])
            case .manualControl:
                return ("profile_manual_control".localizedString, "profile_manual_control", "profile_manual_control_desc".localizedString, [.luminaire, .manualControl])
            }
        }
        
        /// 占用+日光感应
        case occupancy_daylight
        /// 空置+日光感应
        case vacancy_daylight
        /// 占用感应
        case occupancy
        /// 空置感应
        case vacancy
        /// 日光感应
        case daylight
        /// 手动控制
        case manualControl
    }
    
    /// 上电状态
    enum PowerUpState {
        var rawValue: Int {
            switch self {
            case .off:
                return 254
            case .restore:
                return 255
            case .definedLightLevel(let level):
                return level
            }
        }
        init(rawValue: Int) {
            switch rawValue {
            case 0...100:
                self = .definedLightLevel(rawValue)
            case 254:
                self = .off
            default:
                self = .restore
            }
        }
        
        /// 关
        case off
        /// 保持上次状态
        case restore
        /// 调节到具体亮度值 0~100
        case definedLightLevel(_ level: Int)
    }
    
    /// 名称
    var name: String = ""
    /// 配置id
    let id: String
    /// profile类型
    var type: ProfileType = .occupancy_daylight
    /// 灯光阶段调节数据
    var lightData: LightData
    /// 上电状态
    var powerUpState: PowerUpState = .restore
    /// 手动控制后进入Standby时间（s）max：无限长
    var manualOverrideTimeout: UInt32 = 600
    /// 调节速率 0~100
    var adjustSpeed: Int = 50
    
    /// 调节速率 0~100
//    var adjustSpeed: Int = 50
    
    init(name: String = "", id: String = UUID().uuidString, type: ProfileType = .occupancy_daylight, lightData: LightData, powerUpState: PowerUpState, manualOverrideTimeout: UInt32, adjustSpeed: Int = 50) {
        self.name = name
        self.id = id
        self.type = type
        self.lightData = lightData
        self.powerUpState = powerUpState
        self.manualOverrideTimeout = manualOverrideTimeout
        self.adjustSpeed = adjustSpeed
    }
    
    init(type: ProfileType) {
        
        self.id = UUID().uuidString
        self.type = type
        
        let highEndTrim = 100
        let lowEndTrim = 0
        let occupancyLevel = 100
        let vacantLevel = 50
        let occupancyLux = 500
        let vacantLux = 100
        let taskLevel = 100
        let taskLux = 500
        let autoMinLevel = 255
        let t1 = 2
        let t2 = 1200
        let t3 = 2
        let t4 = 600
        let t5 = 2
        
        switch type {
        case .occupancy_daylight, .vacancy_daylight, .daylight:
            self.lightData = LightData(profileType: type, highEndTrim: highEndTrim, lowEndTrim: lowEndTrim, occupancyLevel: occupancyLux, vacantLevel: vacantLux, taskLevel: taskLux, autoMinLevel: autoMinLevel, t1: t1, t2: t2, t3: t3, t4: t4, t5: t5)
        default:
            self.lightData = LightData(profileType: type, highEndTrim: highEndTrim, lowEndTrim: lowEndTrim, occupancyLevel: occupancyLevel, vacantLevel: vacantLevel, taskLevel: taskLevel, autoMinLevel: autoMinLevel, t1: t1, t2: t2, t3: t3, t4: t4, t5: t5)
        }
    }
    
    func copy() -> Self {
        return Profile(name: name, id: id, type: type, lightData: lightData.copy(), powerUpState: powerUpState, manualOverrideTimeout: manualOverrideTimeout, adjustSpeed: adjustSpeed) as! Self
    }
    
    static func == (lhs: Profile, rhs: Profile) -> Bool {
        return lhs.id == rhs.id && lhs.type == rhs.type && lhs.lightData == rhs.lightData && lhs.powerUpState.rawValue == rhs.powerUpState.rawValue && lhs.manualOverrideTimeout == rhs.manualOverrideTimeout && lhs.adjustSpeed == rhs.adjustSpeed
    }
    
}
