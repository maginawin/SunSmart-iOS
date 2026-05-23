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
                phasesTimeItems.append(TimePickerData.TimeItem(name: "30 sec", second: 30))
                for i in 1...60 {
                    phasesTimeItems.append(TimePickerData.TimeItem(name: "\(i) min", second: i * 60))
                }
                phasesTimeItems.append(TimePickerData.TimeItem(name: "infinite".localizedString, second: 0xFFFFFE))
                
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
        var data: (highEndTrim: Int, lowEndTrim: Int, occupancyLevel: Int, vacantLevel: Int, taskLevel: Int, standbyLevel: Int, autoMinLevel: Int, autoMinLevelEnabled: Bool, t1: Int, t2: Int, t3: Int, t4: Int, t5: Int) {
            
            var highEndTrim = 100
            var lowEndTrim = 0
            var occupancyLevel = 100
            var vacantLevel = 50
            var taskLevel = 100
            var autoMinLevel = 0
            var standbyLevel = 0
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
                case .standbyLevel(let value):
                    standbyLevel = value
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
            return (highEndTrim, lowEndTrim, occupancyLevel, vacantLevel, taskLevel, standbyLevel, autoMinLevel, autoMinLevelEnabled, t1, t2, t3, t4, t5)
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
                case .standbyLevel:
                    return 6
                }
            }
            /// 亮度范围 High-end trim/Low-end trim
            case lightnessRange(_ range: ClosedRange<Int>)
            /// 占用阶段亮度（第一阶段）Lux/%
            case occupancyLevel(_ value: Int)
            /// 空置阶段亮度（第二阶段）Lux/%
            case vacantLevel(_ value: Int)
            /// 待机阶段亮度（第三阶段）Lux/%
            case standbyLevel(_ value: Int)
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
        
        init(profileType: ProfileType, standbyLevel: Int = 0) {
            
            let highEndTrim = 100
            let lowEndTrim = 0
            let occupancyLevel = 100
            let vacantLevel = 50
//            let occupancyLux = 500
//            let vacantLux = 100
            let taskLevel = 100
//            let taskLux = 500
            let autoMinLevel = 255
            let t1 = 2
            let t2 = 1200
            let t3 = 2
            let t4 = 600
            let t5 = 2
            
            switch profileType {
            case .occupancy_daylight, .vacancy_daylight:
                
                levels = [.lightnessRange(lowEndTrim...highEndTrim), .occupancyLevel(occupancyLevel), .vacantLevel(vacantLevel), .standbyLevel(standbyLevel), .autoMinValue(autoMinLevel, enabled: autoMinLevel <= 30)]
                times = [.t1(t1), .t2(t2), .t3(t3), .t4(t4), .t5(t5)]
            case .occupancy, .vacancy, .proximityLighting, .proximityLightingWithPhotocell:
                levels = [.lightnessRange(lowEndTrim...highEndTrim), .occupancyLevel(occupancyLevel), .vacantLevel(vacantLevel), .standbyLevel(standbyLevel)]
                times = [.t1(t1), .t2(t2), .t3(t3), .t4(t4), .t5(t5)]
            case .daylight:
                levels = [.lightnessRange(lowEndTrim...highEndTrim), .taskLevel(taskLevel), .autoMinValue(autoMinLevel, enabled: autoMinLevel <= 30)]
                times = [.t1(t1)]
            case .manualControl:
                levels = [.lightnessRange(lowEndTrim...highEndTrim), .taskLevel(taskLevel)]
                times = [.t1(t1)]
            }
        }
        
        /// 初始化灯光数据
        /// - Parameters:
        ///   - profileType: 配置类型
        ///   - highEndTrim: 亮度最大输出 50~100%
        ///   - lowEndTrim: 亮度最小输出 0~30%
        ///   - occupancyLevel: 第一阶段亮度/照度
        ///   - vacantLevel: 第二阶段亮度/照度
        ///   - taskLevel: 环境光维持照度
        ///   - standbyLevel: 第三（待机）阶段亮度/照度
        ///   - autoMinLevel: 环境光补偿最低亮度 0~30%  255: unenabled
        ///   - t1: 进入第一阶段过渡时间
        ///   - t2: 第一阶段维持时间
        ///   - t3: 进入第二阶段过渡时间
        ///   - t4: 第二阶段维持时间
        ///   - t5: 进入待机过渡时间
        init(profileType: ProfileType, highEndTrim: Int, lowEndTrim: Int, occupancyLevel: Int, vacantLevel: Int, standbyLevel: Int = 0, taskLevel: Int, autoMinLevel: Int, t1: Int, t2: Int, t3: Int, t4: Int, t5: Int) {
            
            switch profileType {
            case .occupancy_daylight, .vacancy_daylight:
                
                levels = [.lightnessRange(lowEndTrim...highEndTrim), .occupancyLevel(occupancyLevel), .vacantLevel(vacantLevel), .standbyLevel(standbyLevel), .autoMinValue(autoMinLevel, enabled: autoMinLevel <= 30)]
                times = [.t1(t1), .t2(t2), .t3(t3), .t4(t4), .t5(t5)]
            case .occupancy, .vacancy, .proximityLighting, .proximityLightingWithPhotocell:
                levels = [.lightnessRange(lowEndTrim...highEndTrim), .occupancyLevel(occupancyLevel), .vacantLevel(vacantLevel), .standbyLevel(standbyLevel)]
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
    
    /// 触发条件数据
    class TriggerConditionData: Copyable, Codable {
        /// 执行类型
        enum ExecuteType: Int {
            /// 自动三段式调光
            case adjustWhenOccupied = 0
            /// 固定亮度
            case fixedLevel
        }
        /// 条件id
        let id: UInt8
        /// 触发lux
        var startsBelowLux: UInt16
        /// 是否使用校准数据
        var useCalibrationValues: Bool = false
        /// 执行类型
        var executeType: ExecuteType = .adjustWhenOccupied
        /// 场景数据
        var sceneData: LightControlScene
        
        /// 固定待机亮度
        var fixedStandbyLevel: Int
        
        init(id: UInt8, startsBelowLux: UInt16, useCalibrationValues: Bool = false, executeType: ExecuteType = .adjustWhenOccupied, sceneData: LightControlScene, fixedStandbyLevel: Int) {
            self.id = id
            self.startsBelowLux = startsBelowLux
            self.useCalibrationValues = useCalibrationValues
            self.executeType = executeType
            self.sceneData = sceneData
            self.fixedStandbyLevel = fixedStandbyLevel
        }
        
        func update(data: TriggerConditionData) {
            self.startsBelowLux = data.startsBelowLux
            self.useCalibrationValues = data.useCalibrationValues
            self.executeType = data.executeType
            self.sceneData.update(scene: data.sceneData)
        }
        
        func copy() -> Self {
            let data = TriggerConditionData(id: id, startsBelowLux: startsBelowLux, useCalibrationValues: useCalibrationValues, executeType: executeType, sceneData: sceneData.copy(), fixedStandbyLevel: fixedStandbyLevel)
            return data as! Self
        }
        
        static func == (lhs: TriggerConditionData, rhs: TriggerConditionData) -> Bool {
            return lhs.id == rhs.id && lhs.startsBelowLux == rhs.startsBelowLux && lhs.useCalibrationValues == rhs.useCalibrationValues && lhs.executeType.rawValue == rhs.executeType.rawValue && lhs.sceneData == rhs.sceneData && lhs.fixedStandbyLevel == rhs.fixedStandbyLevel
        }
        
        // MARK: - Codable
        
        private enum CodingKeys: String, CodingKey {
            case id
            case startsBelowLux
            case useCalibrationValues
            case executeType
            case sceneData
            case fixedStandbyLevel
        }
        
        required init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.id = try container.decode(UInt8.self, forKey: .id)
            self.startsBelowLux = try container.decode(UInt16.self, forKey: .startsBelowLux)
            self.useCalibrationValues = try container.decode(Bool.self, forKey: .useCalibrationValues)
            let executeTypeValue = try container.decode(Int.self, forKey: .executeType)
            self.executeType = ExecuteType(rawValue: executeTypeValue) ?? .adjustWhenOccupied
            
            self.sceneData = try container.decode(LightControlScene.self, forKey: .sceneData)
            self.fixedStandbyLevel = try container.decode(Int.self, forKey: .fixedStandbyLevel)
        }
        
        func encode(to encoder: any Encoder) throws {
            
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(self.id, forKey: .id)
            try container.encode(self.startsBelowLux, forKey: .startsBelowLux)
            try container.encode(self.useCalibrationValues, forKey: .useCalibrationValues)
            try container.encode(self.executeType.rawValue, forKey: .executeType)
            try container.encode(self.sceneData, forKey: .sceneData)
            try container.encode(self.fixedStandbyLevel, forKey: .fixedStandbyLevel)
        }
        
    }
    
    static let defaultGroupProfileLowEndTrim = 1
    
    static func defaultGroupProfiles() -> [Profile] {
        return ProfileType.defaultGroupProfileTypes.map { Profile.defaultGroupProfile(type: $0) }
    }
    
    static func defaultGroupProfile(type: ProfileType) -> Profile {
        let profile = Profile(type: type)
        profile.applyDefaultGroupProfileLowEndTrim()
        return profile
    }
    
    private func applyDefaultGroupProfileLowEndTrim() {
        scenes.forEach { scene in
            scene.lightControlData.lowEndTrim = Profile.defaultGroupProfileLowEndTrim
        }
    }
    
    /// 灯光控制场景
    class LightControlScene: Copyable, Codable, Equatable {
        /// 场景id
        let sceneNumber: SceneNumber
        /// 名称
        var name: String
        /// 灯光阶段调节数据
        var lightControlData: LightControlData
        
        init(sceneNumber: SceneNumber, name: String, lightControlData: LightControlData) {
            self.sceneNumber = sceneNumber
            self.name = name
            self.lightControlData = lightControlData
        }
        
        /// 默认的场景
        static func generalScene(profileType: ProfileType) -> LightControlScene {
            var occupancyLevel = 100
            var vacantLevel = 50
            if profileType == .occupancy_daylight || profileType == .vacancy_daylight || profileType == .daylight {
                occupancyLevel = 500
                vacantLevel = 100
            }
            return LightControlScene(sceneNumber: .generalLightControlScene, name: "General Scene", lightControlData: .init(occupancyLevel: occupancyLevel, vacantLevel: vacantLevel, standbyLevel: 0))
        }
        
        func copy() -> Self {
            let data = LightControlScene(sceneNumber: sceneNumber, name: name, lightControlData: lightControlData.copy())
            return data as! Self
        }
        
        func update(scene: LightControlScene) {
            self.name = scene.name
            let newLightControlData = scene.lightControlData
            self.lightControlData.highEndTrim = newLightControlData.highEndTrim
            self.lightControlData.lowEndTrim = newLightControlData.lowEndTrim
            self.lightControlData.occupancyLevel = newLightControlData.occupancyLevel
            self.lightControlData.vacantLevel = newLightControlData.vacantLevel
            self.lightControlData.standbyLevel = newLightControlData.standbyLevel
            self.lightControlData.taskLevel = newLightControlData.taskLevel
            self.lightControlData.autoMinLevel = newLightControlData.autoMinLevel
            self.lightControlData.t1 = newLightControlData.t1
            self.lightControlData.t2 = newLightControlData.t2
            self.lightControlData.t3 = newLightControlData.t3
            self.lightControlData.t4 = newLightControlData.t4
            self.lightControlData.t5 = newLightControlData.t5
        }
        
        static func == (lhs: LightControlScene, rhs: LightControlScene) -> Bool {
            return lhs.sceneNumber == rhs.sceneNumber && lhs.name == rhs.name && lhs.lightControlData == rhs.lightControlData
        }
        
    }
    
    /// 灯光控制数据
    class LightControlData: Codable, Copyable {
        
        /// 亮度上限
        var highEndTrim: Int = 100
        /// 亮度下限
        var lowEndTrim: Int = 0
        /// 第一阶段level/lux
        var occupancyLevel: Int = 100
        /// 第二阶段level/lux
        var vacantLevel: Int = 50
        /// 第三（待机）阶段亮度/照度
        var standbyLevel: Int = 0
        /// 环境光维持照度
        var taskLevel: Int = 100
        /// 环境光补偿最低亮度 0~30%  255: unenabled
        var autoMinLevel: Int = 255
        /// 进入第一阶段过渡时间
        var t1 = 2
        /// 第一阶段维持时间
        var t2 = 1200
        /// 进入第二阶段过渡时间
        var t3 = 2
        /// 第二阶段维持时间
        var t4 = 600
        /// 进入待机过渡时间
        var t5 = 2
        /// 是否启用自动调光最小亮度
        var autoMinLevelEnabled: Bool {
            return autoMinLevel != 255
        }
    
        init(highEndTrim: Int = 100, lowEndTrim: Int = 0, occupancyLevel: Int = 100, vacantLevel: Int = 50, standbyLevel: Int = 0, taskLevel: Int = 100, autoMinLevel: Int = 255, t1: Int = 2, t2: Int = 1200, t3: Int = 2, t4: Int = 600, t5: Int = 2) {
            self.highEndTrim = highEndTrim
            self.lowEndTrim = lowEndTrim
            self.occupancyLevel = occupancyLevel
            self.vacantLevel = vacantLevel
            self.standbyLevel = standbyLevel
            self.taskLevel = taskLevel
            self.autoMinLevel = autoMinLevel
            self.t1 = t1
            self.t2 = t2
            self.t3 = t3
            self.t4 = t4
            self.t5 = t5
        }
        
        /// 转换成灯光显示图形数据
        func convertLightData(profileType: ProfileType) -> LightData {
            return LightData(profileType: profileType, highEndTrim: highEndTrim, lowEndTrim: lowEndTrim, occupancyLevel: occupancyLevel, vacantLevel: vacantLevel, standbyLevel: standbyLevel, taskLevel: taskLevel, autoMinLevel: autoMinLevel, t1: t1, t2: t2, t3: t3, t4: t4, t5: t5)
        }
        
        func copy() -> Self {
            return LightControlData(highEndTrim: highEndTrim, lowEndTrim: lowEndTrim, occupancyLevel: occupancyLevel, vacantLevel: vacantLevel, standbyLevel: standbyLevel, taskLevel: taskLevel, autoMinLevel: autoMinLevel, t1: t1, t2: t2, t3: t3, t4: t4, t5: t5) as! Self
        }
        
        static func == (lhs: LightControlData, rhs: LightControlData) -> Bool {
            return lhs.highEndTrim == rhs.highEndTrim && lhs.lowEndTrim == rhs.lowEndTrim && lhs.occupancyLevel == rhs.occupancyLevel && lhs.vacantLevel == rhs.vacantLevel && lhs.standbyLevel == rhs.standbyLevel && lhs.taskLevel == rhs.taskLevel && lhs.autoMinLevel == rhs.autoMinLevel && lhs.t1 == rhs.t1 && lhs.t2 == rhs.t2 && lhs.t3 == rhs.t3 && lhs.t4 == rhs.t4 && lhs.t5 == rhs.t5
        }
    }
    
    
    /// 类型
    enum ProfileType {
        static let defaultGroupProfileTypes: [ProfileType] = [
            .occupancy_daylight,
            .vacancy_daylight,
            .occupancy,
            .vacancy,
            .daylight,
            .manualControl,
            .proximityLighting,
            .proximityLightingWithPhotocell
        ]
        
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
            case .proximityLighting:
                return 7
            case .proximityLightingWithPhotocell:
                return 8
            }
        }
        
        /// 是否是占用类型profile
        var occupancyType: Bool {
            switch self {
            case .occupancy_daylight, .vacancy_daylight, .occupancy, .vacancy, .proximityLighting, .proximityLightingWithPhotocell:
              return true
            default:
                return false
            }
        }
        
        /// 是否是光照类型profile
        var daylightType: Bool {
            switch self {
            case .occupancy_daylight, .vacancy_daylight, .daylight:
              return true
            default:
                return false
            }
        }
        
        /// 是否是临近照明类型profile
        var proximityLightingType: Bool {
            switch self {
            case .proximityLighting, .proximityLightingWithPhotocell:
              return true
            default:
                return false
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
            case 7:
                self = .proximityLighting
            case 8:
                self = .proximityLightingWithPhotocell
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
                case .pathSequenceSetting:
                    return ("path_sequence_setting".localizedString, "profile_path_sequence_setting")
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
            /// 路径
            case pathSequenceSetting
        }
        
        /// 简介
        var instruction: (name: String, imageName: String, descriptionAttStr: NSAttributedString, requireds: [RequiredDeviceType]) {
            
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = 2
            
            switch self {
            case .occupancy_daylight:
                return ("profile_occupancy_daylight".localizedString, "profile_occupancy_daylight", NSAttributedString(string: "profile_occupancy_daylight_desc".localizedString), [.luminaire, .lightSensor, .occupancySensor])
            case .vacancy_daylight:
                return ("profile_vacancy_daylight".localizedString, "profile_vacancy_daylight", NSAttributedString(string: "profile_vacancy_daylight_desc".localizedString), [.luminaire, .lightSensor, .manualControl, .occupancySensor])
            case .occupancy:
                return ("profile_occupancy".localizedString, "profile_occupancy", NSAttributedString(string: "profile_occupancy_desc".localizedString, attributes: [.paragraphStyle: paragraphStyle]), [.luminaire, .occupancySensor])
            case .vacancy:
                return ("profile_vacancy".localizedString, "profile_vacancy", NSAttributedString(string: "profile_vacancy_desc".localizedString, attributes: [.paragraphStyle: paragraphStyle]), [.luminaire, .occupancySensor, .manualControl])
            case .daylight:
                return ("profile_daylight".localizedString, "profile_daylight", NSAttributedString(string: "profile_daylight_desc".localizedString, attributes: [.paragraphStyle: paragraphStyle]), [.luminaire, .lightSensor])
            case .manualControl:
                return ("profile_manual_control".localizedString, "profile_manual_control", NSAttributedString(string: "profile_manual_control_desc".localizedString, attributes: [.paragraphStyle: paragraphStyle]), [.luminaire, .manualControl])
            case .proximityLighting:
                return ("profile_predictive_lighting".localizedString, "profile_proximity_lighting", NSAttributedString(string: "profile_predictive_lighting_desc".localizedString, attributes: [.paragraphStyle: paragraphStyle]), [.luminaire, .occupancySensor, .pathSequenceSetting])
            case .proximityLightingWithPhotocell:
                
                let attStr1 = NSMutableAttributedString(string: "profile_predictive_lighting_with_photocell_desc_1".localizedString + "\n")
                attStr1.addAttributes([.font: UIFont.systemFont(ofSize: 14), .foregroundColor: TextBlack_Color], range: (attStr1.string as NSString).range(of: "proximity/predictive_lighting_with_photocell".localizedString))
                
                let attStr2 = NSMutableAttributedString(string: "profile_predictive_lighting_with_photocell_desc_2".localizedString + "\n")
                attStr2.addAttributes([.font: UIFont.systemFont(ofSize: 14), .foregroundColor: TextBlack_Color], range: (attStr2.string as NSString).range(of: "proximity_lighting".localizedString))
                
                let attStr3 = NSMutableAttributedString(string: "profile_predictive_lighting_with_photocell_desc_3".localizedString + "\n")
                attStr3.addAttributes([.font: UIFont.systemFont(ofSize: 14), .foregroundColor: TextBlack_Color], range: (attStr3.string as NSString).range(of: "predictive_lighting".localizedString))
                
                let attStr4 = NSMutableAttributedString(string: "profile_predictive_lighting_with_photocell_desc_4".localizedString + "\n")
                attStr4.addAttributes([.font: UIFont.systemFont(ofSize: 14), .foregroundColor: TextBlack_Color], range: (attStr4.string as NSString).range(of: "own_ambient_light_sensor".localizedString))
                
                let attStr5 = NSMutableAttributedString(string: "profile_predictive_lighting_with_photocell_desc_5".localizedString)
                
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.lineSpacing = 2
                paragraphStyle.paragraphSpacing = 6
                
                let descriptionAttStr = NSMutableAttributedString()
                descriptionAttStr.append(attStr1)
                descriptionAttStr.append(attStr2)
                descriptionAttStr.append(attStr3)
                descriptionAttStr.append(attStr4)
                descriptionAttStr.append(attStr5)
                descriptionAttStr.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: descriptionAttStr.string.count))
                
                return ("profile_predictive_lighting_with_photocell".localizedString, "profile_proximity_lighting_with_photocell", descriptionAttStr, [.luminaire, .lightSensor, .occupancySensor, .pathSequenceSetting])
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
        /// 邻近照明
        case proximityLighting
        /// 邻近照明+光感条件
        case proximityLightingWithPhotocell
    }
    
    /// 上电状态
    enum PowerUpState {
        var rawValue: UInt8 {
            switch self {
            case .off:
                return 254
            case .restore:
                return 255
            case .definedLightLevel(let level):
                return level
            }
        }
        init(rawValue: UInt8) {
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
        case definedLightLevel(_ level: UInt8)
    }
    
 
    
    /// 名称
    var name: String = ""
    /// 配置id
    let id: String
    /// profile类型
    var type: ProfileType = .occupancy_daylight
    /// 灯光阶段调节数据
    var lightControlData: LightControlData {
        guard let generalScene = scenes.first(where: { $0.sceneNumber == .generalLightControlScene }) else {
            let scene = LightControlScene.generalScene(profileType: self.type)
            scenes.insert(scene, at: 0)
            return scene.lightControlData
        }
        return generalScene.lightControlData
    }
    /// 上电状态
    var powerUpState: PowerUpState = .restore
    /// 手动控制后进入Standby时间（s）max：无限长
    var manualOverrideTimeout: UInt32 = 600
    /// 调节速率 0~100
    var adjustSpeed: Int = 50
    /// 上电色温值
    var powerUpCct: UInt16 = 4500
    /// 调节速率 0~100
//    var adjustSpeed: Int = 50
    /// 灵敏度（移动检测）
    var sensitivity: UInt8 = 95
    /// 邻近照明数量
    var proximityLightingNumber: UInt8 = 2
    /// 晚上时配置数据
    var nightData: TriggerConditionData?
    /// 白天时配置数据
    var dayData: TriggerConditionData?
    /// profile下场景list
    var scenes: [LightControlScene] = []
    /// 光照传感器模板
    var lightSensorTemplates: [ProfileLightSensorTemplate] = []
    
    /// 灯光阶段调节数据（图表）
    var lightData: LightData {
        return LightData(profileType: type, highEndTrim: lightControlData.highEndTrim, lowEndTrim: lightControlData.lowEndTrim, occupancyLevel: lightControlData.occupancyLevel, vacantLevel: lightControlData.vacantLevel, standbyLevel: lightControlData.standbyLevel, taskLevel: lightControlData.taskLevel, autoMinLevel: lightControlData.autoMinLevel, t1: lightControlData.t1, t2: lightControlData.t2, t3: lightControlData.t3, t4: lightControlData.t4, t5: lightControlData.t5)
    }
    
    init(name: String = "", id: String = UUID().uuidString, type: ProfileType = .occupancy_daylight, lightControlData: LightControlData, powerUpState: PowerUpState, powerUpCct: UInt16 = 4500, manualOverrideTimeout: UInt32, adjustSpeed: Int = 50, sensitivity: UInt8 = 95, proximityLightingNumber: UInt8 = 2, nightData: TriggerConditionData? = nil, dayData: TriggerConditionData? = nil, scenes: [LightControlScene] = []) {
        self.name = name
        self.id = id
        self.type = type
//        self.lightControlData = lightControlData
        self.powerUpState = powerUpState
        self.powerUpCct = powerUpCct
        self.manualOverrideTimeout = manualOverrideTimeout
        self.adjustSpeed = adjustSpeed
        self.sensitivity = sensitivity
        self.proximityLightingNumber = proximityLightingNumber
        self.scenes = scenes
        self.dayData = dayData
        self.nightData = nightData
        
        // 不存在通用profile场景时自动创建
        if !scenes.contains(where: { $0.sceneNumber == .generalLightControlScene }) {
            let scene = LightControlScene(sceneNumber: .generalLightControlScene, name: "General Scene", lightControlData: .init(highEndTrim: lightControlData.highEndTrim, lowEndTrim: lightControlData.lowEndTrim, occupancyLevel: lightControlData.occupancyLevel, vacantLevel: lightControlData.vacantLevel, standbyLevel: lightControlData.standbyLevel, taskLevel: lightControlData.taskLevel, autoMinLevel: lightControlData.autoMinLevel, t1: lightControlData.t1, t2: lightControlData.t2, t3: lightControlData.t3, t4: lightControlData.t4, t5: lightControlData.t5))
            self.scenes.insert(scene, at: 0)
        }
        
        if type == .proximityLightingWithPhotocell {
            if self.nightData == nil {
                let scene = LightControlScene(sceneNumber: .generalLightControlScene + 1, name: "Night Scene", lightControlData: .init(standbyLevel: 30))
                self.nightData = TriggerConditionData(id: 0, startsBelowLux: 30, useCalibrationValues: false, executeType: .adjustWhenOccupied, sceneData: scene, fixedStandbyLevel: 30)
                if !scenes.contains(where: { $0.sceneNumber == scene.sceneNumber }) {
                    self.scenes.append(scene)
                }
            }
            
            if self.dayData == nil {
                let scene = LightControlScene(sceneNumber: .generalLightControlScene + 2, name: "Day Scene", lightControlData: .init())
                self.dayData = TriggerConditionData(id: 1, startsBelowLux: 70, useCalibrationValues: false, executeType: .adjustWhenOccupied, sceneData: scene, fixedStandbyLevel: 0)
                if !scenes.contains(where: { $0.sceneNumber == scene.sceneNumber }) {
                    self.scenes.append(scene)
                }
            }
        }
    }
    
    init(type: ProfileType) {
        
        self.id = UUID().uuidString
        self.type = type
        
        if type == .daylight || type == .manualControl {
            self.manualOverrideTimeout = .max
        }

        
        // 创建默认场景
        let generalScene =  LightControlScene.generalScene(profileType: type)
        self.scenes.append(generalScene)
        
        if type == .proximityLightingWithPhotocell {
            
            let nightScene = LightControlScene(sceneNumber: .generalLightControlScene + 1, name: "Night Scene", lightControlData: .init(standbyLevel: 30))
            let dayScene = LightControlScene(sceneNumber: .generalLightControlScene + 2, name: "Day Scene", lightControlData: .init(occupancyLevel: 0, vacantLevel: 0, standbyLevel: 0))
            
            self.nightData = TriggerConditionData(id: 0, startsBelowLux: 30, useCalibrationValues: false, executeType: .adjustWhenOccupied, sceneData: nightScene, fixedStandbyLevel: 30)

            self.dayData = TriggerConditionData(id: 1, startsBelowLux: 70, useCalibrationValues: false, executeType: .adjustWhenOccupied, sceneData: dayScene, fixedStandbyLevel: 0)
            
            self.scenes.append(nightScene)
            self.scenes.append(dayScene)
        }
    }
    
    /// 更新数据
    func updateData(profile: Profile) {
        self.name = profile.name
        self.type = profile.type
//        self.lightControlData = profile.lightControlData
        self.powerUpState = profile.powerUpState
        self.powerUpCct = profile.powerUpCct
        self.manualOverrideTimeout = profile.manualOverrideTimeout
        self.adjustSpeed = profile.adjustSpeed
        self.sensitivity = profile.sensitivity
        self.proximityLightingNumber = profile.proximityLightingNumber
        self.dayData = profile.dayData?.copy()
        self.nightData = profile.nightData?.copy()
        self.scenes = profile.scenes.map({ $0.copy() })
        if let dayScene = self.scenes.first(where: { $0.sceneNumber == self.dayData?.sceneData.sceneNumber }) {
            self.dayData?.sceneData = dayScene
        }
        if let nightScene = self.scenes.first(where: { $0.sceneNumber == self.nightData?.sceneData.sceneNumber }) {
            self.nightData?.sceneData = nightScene
        }
        self.lightSensorTemplates = profile.lightSensorTemplates
    }
    
    func copy() -> Self {
        let profile = Profile(name: name, id: id, type: type, lightControlData: lightControlData.copy(), powerUpState: powerUpState, powerUpCct: powerUpCct, manualOverrideTimeout: manualOverrideTimeout, adjustSpeed: adjustSpeed, sensitivity: sensitivity, proximityLightingNumber: proximityLightingNumber)
        let scenes = self.scenes.map({ $0.copy() })
        let dayData = self.dayData?.copy()
        if let dayScene = scenes.first(where: { $0.sceneNumber == dayData?.sceneData.sceneNumber }) {
            dayData?.sceneData = dayScene
        }
        let nightData = self.nightData?.copy()
        if let nightScene = scenes.first(where: { $0.sceneNumber == nightData?.sceneData.sceneNumber }) {
            nightData?.sceneData = nightScene
        }
        profile.dayData = dayData
        profile.nightData = nightData
        profile.scenes = scenes
        profile.lightSensorTemplates = self.lightSensorTemplates
        return profile as! Self
    }
    
    static func == (lhs: Profile, rhs: Profile) -> Bool {
        
        guard lhs.id == rhs.id && lhs.type == rhs.type && lhs.scenes == rhs.scenes && lhs.powerUpState.rawValue == rhs.powerUpState.rawValue && lhs.powerUpCct == rhs.powerUpCct && lhs.manualOverrideTimeout == rhs.manualOverrideTimeout && lhs.adjustSpeed == rhs.adjustSpeed && lhs.sensitivity == rhs.sensitivity && lhs.proximityLightingNumber == rhs.proximityLightingNumber else {
            return false
        }
        
        if let lhsData = lhs.dayData, let rhsData = rhs.dayData {
            // 两者都不为空，进行比较
            return lhsData == rhsData
        } else {
            // 至少一个为空，比较是否都为空
            return lhs.dayData == nil && rhs.dayData == nil
        }
    }
   
    /// 获取下一个场景号
    func nextAvailableSceneNumber() -> SceneNumber? {
        let existSceneNumbers = scenes.map({ $0.sceneNumber })
        for sceneNumber in SceneNumber.minLightControlScene...SceneNumber.maxLightControlScene {
            if sceneNumber != .generalLightControlScene && !existSceneNumbers.contains(sceneNumber) {
                return sceneNumber
            }
        }
        return nil
    }
    
}

/// profile 光感模板
class ProfileLightSensorTemplate {
    
    let id: String
    /// 名称
    var name: String
    /// 晚上lux
    var nightStartsBelowLux: UInt16
    /// 白天lux
    var dayStartsAboveLux: UInt16
    /// 模板设备地址list
    var deviceAddresses: [Address] = []
    /// 模板设备list
    var devices: [Node] {
        return deviceAddresses.compactMap({ address in
            MeshNetworkManager.instance.realNodes.first(where: { $0.primaryUnicastAddress == address })
        })
    }
    
    init(id: String = UUID().uuidString, name: String, nightStartsBelowLux: UInt16, dayStartsAboveLux: UInt16, deviceAddresses: [Address]) {
        self.id = id
        self.name = name
        self.nightStartsBelowLux = nightStartsBelowLux
        self.dayStartsAboveLux = dayStartsAboveLux
        self.deviceAddresses = deviceAddresses
    }
    
}
