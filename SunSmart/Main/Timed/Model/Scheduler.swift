//
//  Scheduler.swift
//  SunSmart
//
//  Created by yuankehong on 2025/12/18.
//

import Foundation
import NordicSigMeshSDK

class Schedule: Codable, Copyable {
    
    /// 重复周期字符串list
    static let weeklyStrs = ["week_mo".localizedString, "week_tu".localizedString, "week_we".localizedString, "week_th".localizedString, "week_fr".localizedString, "week_sa".localizedString, "week_su".localizedString]
    /// 所有月份
    static let allMonths: [Month] = [.January,.February,.March,.April,.May,.June,.July,.August,.September,.October,.November,.December]
    
    /// 日程执行目标类型
    enum TargetType: Int {
        /// 组
        case groups = 0
        /// 设备
        case devices = 1
        /// 场景
        case scene = 2
        /// 组profile
        case profile = 3
    }
    
    /// 日程profile数据
    struct ScheduleProfile: Codable, Equatable {
        let groupAddress: Address
        let profileSceneNumber: SceneNumber
        
        static func == (lhs: ScheduleProfile, rhs: ScheduleProfile) -> Bool {
            return lhs.groupAddress == rhs.groupAddress && lhs.profileSceneNumber == rhs.profileSceneNumber
        }
    }
    
    /// 计划id  0~15
    var id: Int = 0
    /// 是否启用
    var enabled: Bool = false
    /// 名称
    var name: String = ""
    /// 设置的节点list nodes、groups、scenes三选一
    var nodeAddresses: [Address] = []
    var nodes: [Node] {
        return MeshNetworkManager.instance.realNodes.filter({ nodeAddresses.contains($0.primaryUnicastAddress) })
    }
    /// 设置的组list nodes、groups、scenes三选一
    var groupAddresses: [Address] = []
    var groups: [Group] {
        return MeshNetworkManager.instance.groups.filter({ groupAddresses.contains($0.address.address) })
    }
    /// 设置执行的场景，目前只能设置一个，并且nodes、groups、scenes三选一
    var sceneNumber: SceneNumber?
    var scene: Scene? {
        guard let number = sceneNumber else { return nil }
        return MeshNetworkManager.instance.scenes.first(where: { $0.number == number })
    }
    /// 选择的执行目标类型
    var selectTargetType: TargetType = .groups
    /// 执行的场景id
//    var actionSceneId: SceneNumber = 0
    /// 执行动作 off、on、recall scene、no action
    var action: SchedulerAction = .noAction
    /// 渐变时间（s）
    var fadeTime: Int = 0
    /// 周重复
    var weekDays: [WeekDay] = []
    /// 时
    var hour: Int = 0
    /// 分
    var minute: Int = 0
    /// 日程profile
    var profiles: [ScheduleProfile] = []

    /// 需要移出日程的设备
    var needDeleteNodeAddresses: [Address] = []
    var needDeleteNodes: [Node] {
        return MeshNetworkManager.instance.realNodes.filter({ needDeleteNodeAddresses.contains($0.primaryUnicastAddress) })
    }
    /// 需要移出日程的组
    var needDeleteGroupAddresses: [Address] = []
    var needDeleteGroups: [Group] {
        return MeshNetworkManager.instance.groups.filter({ needDeleteGroupAddresses.contains($0.address.address) })
    }
    /// 需要移出的日程的场景
    var needDeleteSceneNumbers: [SceneNumber] = []
    var needDeleteScenes: [Scene] {
        return MeshNetworkManager.instance.scenes.filter({ needDeleteSceneNumbers.contains($0.number) })
    }
    /// 存在的设备
    var exitNodes: [Node] {
        var nodes: [Node] = []
        nodes.append(contentsOf: self.nodes)
        nodes.append(contentsOf: self.needDeleteNodes.filter({ !nodes.contains($0) }))
        
        groups.forEach({
            nodes.append(contentsOf: $0.nodes.filter({ !nodes.contains($0) }))
        })
        needDeleteGroups.forEach({
            nodes.append(contentsOf: $0.nodes.filter({ !nodes.contains($0) }))
        })
        
        scene?.info.groups.forEach({
            nodes.append(contentsOf: $0.nodes.filter({ !nodes.contains($0) }))
        })
        needDeleteScenes.forEach { scene in
            scene.info.groups.forEach({
                nodes.append(contentsOf: $0.nodes.filter({ !nodes.contains($0) }))
            })
        }
        return nodes
    }
    
    
    /// 重复周期描述
    var weekStr: String {
        
        let allWeekDays: [WeekDay] = [.Monday, .Tuesday, .Wednesday, .Thursday, .Friday, .Saturday, .Sunday]
        
        var weekStr = ""
        if weekDays == allWeekDays { // 每天
            weekStr = "everyday".localizedString
        }else if weekDays == allWeekDays.dropLast(2) { // 工作日
            weekStr = "workday".localizedString
        }else if weekDays == allWeekDays.suffix(2) { // 周末
            weekStr = "weekend".localizedString
        }else { // 无规律 Mo, Tu, We, Fr, Sa, Su
            let weekStrs = weekDays.compactMap({
                if let index = allWeekDays.firstIndex(of: $0) {
                    return Schedule.weeklyStrs[min(Schedule.weeklyStrs.count, index)]
                }
                return nil
            })
            
            weekStrs.forEach({
                weekStr.append(weekStr.isEmpty ? $0 : ",\($0)")
            })
        }
        
        return weekStr
    }
    
    
    /// 设置的数据
    var data: Data {
        return SchedulerRegistryEntry.marshal(index: UInt8(id), entry: schedulerEntry)
    }
    /// 设备的日程数据
    var schedulerEntry: SchedulerRegistryEntry {
//        日程删除 => (action==noAction && month==0 && dayOfWeek==0)
//        日程关闭 => (year == 0)
        
        var year: SchedulerYear = .any()
        // 未启用
        if !enabled {
            year = .specific(year: 0)
        }
        
        let entry = SchedulerRegistryEntry(year: year, month: .any(of: Schedule.allMonths), day: .any(), hour: .specific(hour: hour), minute: .specific(minute: minute), second: .specific(second: 0), dayOfWeek: .any(of: weekDays), action: action, transitionTime: .init(steps: UInt8(fadeTime), stepResolution: .seconds), sceneNumber: scene?.number ?? 0)
        
        return entry
    }
    
    init(id: Int, name: String, enabled: Bool, nodeAddresses: [Address] = [], groupAddresses: [Address] = [], sceneNumber: SceneNumber?, profiles: [ScheduleProfile] = [], selectTargetType: TargetType = .groups, action: SchedulerAction, fadeTime: Int, weekDays: [WeekDay], hour: Int, minute: Int) {
        self.id = id
        self.enabled = enabled
        self.name = name
        self.nodeAddresses = nodeAddresses
        self.groupAddresses = groupAddresses
        self.sceneNumber = sceneNumber
        self.profiles = profiles
        self.selectTargetType = selectTargetType
        self.action = action
        self.fadeTime = fadeTime
        self.weekDays = weekDays
        self.hour = hour
        self.minute = minute
    }
    
    init(id: Int, name: String, scheduleEntry: SchedulerRegistryEntry, nodeAddresses: [Address] = [], groupAddresses: [Address] = [], sceneNumber: SceneNumber?, selectTargetType: TargetType = .groups) {
        
        self.id = id
        self.name = name
        self.selectTargetType = selectTargetType
        self.nodeAddresses = nodeAddresses
        self.groupAddresses = groupAddresses
        self.sceneNumber = sceneNumber
        
        updata(entry: scheduleEntry)
    }
    
    // MARK: - Codable
    
    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case enabled
        case nodeAddresses = "deviceAddresses"
        case groupAddresses
        case sceneNumber = "sceneAddress"
        case profiles
        case target = "selectTarget"
        case action
        case fadeTime
        case dayOfWeek
        case hour
        case minute
        case second
    }
    
    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(Int.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.enabled = try container.decode(Bool.self, forKey: .enabled)
        self.selectTargetType = .init(rawValue: try container.decode(Int.self, forKey: .target)) ?? .groups
        self.action = .init(rawValue: try container.decode(UInt8.self, forKey: .action)) ?? .noAction
        self.fadeTime = try container.decode(Int.self, forKey: .fadeTime)
        self.hour = try container.decode(Int.self, forKey: .hour)
        self.minute = try container.decode(Int.self, forKey: .minute)
        self.weekDays = Schedule.getWeekDays(weekValue: try container.decode(Int.self, forKey: .dayOfWeek))
        
        if let nodeAddressStrings = try container.decodeIfPresent([String].self, forKey: .nodeAddresses) {
            nodeAddressStrings.forEach({
                if let address = Address($0) {
                    self.nodeAddresses.append(address)
                }
            })
        }
        
        if let groupAddressStrings = try container.decodeIfPresent([String].self, forKey: .groupAddresses) {
            groupAddressStrings.forEach({
                if let address = Address($0) {
                    self.groupAddresses.append(address)
                }
            })
        }
        
        if let sceneNumber = try? container.decodeIfPresent(SceneNumber?.self, forKey: .sceneNumber) {
            self.sceneNumber = sceneNumber
        }else if let sceneNumberHex = try? container.decodeIfPresent(String.self, forKey: .sceneNumber), let sceneNumber = SceneNumber(hex: sceneNumberHex) {
            self.sceneNumber = sceneNumber
        }
        
        self.profiles = try container.decodeIfPresent([ScheduleProfile].self, forKey: .profiles) ?? []
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.id, forKey: .id)
        try container.encode(self.name, forKey: .name)
        try container.encode(self.enabled, forKey: .enabled)
        try container.encode(self.selectTargetType.rawValue, forKey: .target)
        try container.encode(self.action.rawValue, forKey: .action)
        try container.encode(self.fadeTime, forKey: .fadeTime)
        try container.encode(self.hour, forKey: .hour)
        try container.encode(self.minute, forKey: .minute)
        try container.encode(Schedule.getWeekValue(weekDays: self.weekDays), forKey: .dayOfWeek)
        try container.encode(self.nodeAddresses.map { $0.hex }, forKey: .nodeAddresses)
        try container.encode(self.groupAddresses.map { $0.hex }, forKey: .groupAddresses)
        try container.encode(self.scene?.number.hex, forKey: .sceneNumber)
        try container.encode(self.profiles, forKey: .profiles)
    }
    
    /// 复制日程
    func copy() -> Self {
        let schedule = Schedule(id: id, name: name, enabled: enabled, nodeAddresses: nodeAddresses, groupAddresses: groupAddresses, sceneNumber: sceneNumber, profiles: profiles, selectTargetType: selectTargetType, action: action, fadeTime: fadeTime, weekDays: weekDays, hour: hour, minute: minute)
        return schedule as! Self
    }
    
    
    /// 更新日程数据
    /// - Parameter entry: 设备日程数据
    func updata(entry: SchedulerRegistryEntry) {
        
        self.enabled = entry.isEnabled
//        entry.month.value > 0 && entry.action != .noAction
        self.action = entry.action
        self.sceneNumber = entry.sceneNumber
        self.fadeTime = Int(entry.transitionTime.steps)
        
        // 计算选中的重复周期
        if entry.isEnabled {
            self.weekDays = Schedule.getWeekDays(weekValue: Int(entry.dayOfWeek.value))
        }else {
            self.weekDays = []
        }
        self.hour = Int(entry.hour.value)
        self.minute = Int(entry.minute.value)
    }
    
    /// 根据周重复值获取重复周期
    static func getWeekDays(weekValue: Int) -> [WeekDay] {
        let allWeekDays :[WeekDay] = [.Monday, .Tuesday, .Wednesday, .Thursday, .Friday, .Saturday, .Sunday]
        var selectWeekDays: [WeekDay] = []
        for (weekInt, weekDay) in allWeekDays.enumerated() {
            if weekValue >> weekInt & 1 == 1 {
                selectWeekDays.append(weekDay)
            }
        }
        return selectWeekDays
    }
    
    /// 根据重复周期获取周重复值
    static func getWeekValue(weekDays: [WeekDay]) -> Int {
        return Int(weekDays.reduce(0, { (result, day) -> UInt8 in result + day.rawValue}))
    }
    
    static func == (lhs: Schedule, rhs: Schedule) -> Bool {
        
        return lhs.id == rhs.id && lhs.name == rhs.name && lhs.enabled == rhs.enabled && lhs.selectTargetType == rhs.selectTargetType && lhs.scene?.number == rhs.scene?.number && lhs.profiles == rhs.profiles && lhs.action == rhs.action && lhs.fadeTime == rhs.fadeTime && lhs.weekDays == rhs.weekDays && lhs.hour == rhs.hour && lhs.minute == rhs.minute
    }
    

}
