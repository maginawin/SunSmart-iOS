//
//  DeviceDongleData.swift
//  SunSmart
//
//  Created by yuankehong on 2025/4/21.
//

import Foundation
import NordicSigMeshSDK

class DeviceDongleData: Copyable {
    
    private var storedFirstCollectionTimestamp: Int64?
    
    /// id
    let id: String
    /// 名称
    var name: String
    /// 绑定的dongle节点地址
    var bindNodeAddress: Address?
    /// 绑定的设备
    var bindNode: Node? {
        guard let address = bindNodeAddress else { return nil }
        return MeshNetworkManager.instance.meshNetwork?.node(withAddress: address)
    }
    /// 是否启用时间同步
    var timeAuthority: Bool = false
    /// 是否开启采集
    var collectionEnable: Bool = false
    /// 采集日程
    var schedules: [CollectionSchedule] = []
    /// 首次采集能耗时间戳（没有值时判断日程）
     var firstCollectionTimestamp: Int64? {
        get {
            if let timestamp = storedFirstCollectionTimestamp {
                return timestamp
            }
            // 找到最早且启用的日程，判断当前时间是否大于日程时间，大于则认定此次时间就是首次采集能耗时间
            if self.bindNode != nil, let schedule = schedules.sorted(by: { $0.timestamp < $1.timestamp }).filter({ $0.state == .enable }).first, Int64(Date().timeIntervalSince1970) >= schedule.timestamp {
                storedFirstCollectionTimestamp = schedule.timestamp
                return schedule.timestamp
            }
            return nil
        }set {
            storedFirstCollectionTimestamp = newValue
        }
    }
    
    /// 采集日程
    class CollectionSchedule: Equatable, Codable, Copyable {
        
        /// 状态
        enum State: Int {
            /// 启用
            case enable = 1
            /// 禁用
            case disable = 0
        }
        
        /// 日程id 0~15
        let id: UInt8
        /// 时间戳
        var timestamp: Int64
        /// 状态
        var state: State
        
        /// 采集的日程数据
        var schedulerEntry: SchedulerRegistryEntry {
    //        日程删除 => (action==noAction && month==0 && dayOfWeek==0)
//            let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
            // 获取年月日时分数据
            // 获取年尾数 2025=>25
            let yearValue = String.getTimeStringYear(timestamp: "\(timestamp)") % 100
            let monthValue = String.getTimeStringMonth(timestamp: "\(timestamp)")
            let dayValue = String.getTimeStringDay(timestamp: "\(timestamp)")
            let hourValue = String.getTimeStringHour(timestamp: "\(timestamp)")
            let minuteValue = String.getTimeStringMinute(timestamp: "\(timestamp)")

            let year: SchedulerYear = .specific(year: yearValue)
            // 未启用
//            if self.state == .disable {
//                year = .specific(year: 0)
//            }
            let month = Schedule.allMonths[monthValue - 1]
            
            let entry = SchedulerRegistryEntry(year: year, month: .any(of: [month]), day: .specific(day: dayValue), hour: .specific(hour: hourValue), minute: .specific(minute: minuteValue), second: .specific(second: 0), dayOfWeek: .any(of: []), action: state == .enable ? .turnOff : .turnOff, transitionTime: .immediate, sceneNumber: 0)
            
            return entry
        }
        
        
        init(id: UInt8, timestamp: Int64, state: State) {
            self.id = id
            self.timestamp = timestamp
            self.state = state
        }
        
        static func `default`(id: UInt8) -> CollectionSchedule {
            return CollectionSchedule(id: id, timestamp: Int64(Date().timeIntervalSince1970), state: .enable)
        }
        
        func updateData(schedule: CollectionSchedule) {
            self.timestamp = schedule.timestamp
            self.state = schedule.state
        }
        
        func copy() -> Self {
            return CollectionSchedule(id: self.id, timestamp: self.timestamp, state: self.state) as! Self
        }
        
        static func == (lhs: CollectionSchedule, rhs: CollectionSchedule) -> Bool {
            return lhs.id == rhs.id && lhs.timestamp == rhs.timestamp && lhs.state == rhs.state
        }
        
        private enum CodingKeys: String, CodingKey {
            case id
            case timestamp
            case state
        }
        
        required init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            
            self.id = try container.decode(UInt8.self, forKey: .id)
            self.timestamp = try container.decode(Int64.self, forKey: .timestamp)
            self.state = State(rawValue: try container.decode(Int.self, forKey: .state)) ?? .disable
        }
        
        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(self.id, forKey: .id)
            try container.encode(self.timestamp, forKey: .timestamp)
            try container.encode(self.state.rawValue, forKey: .state)
        }
        
    }
    
    
    /// 初始化dongle模板
    /// - Parameters:
    ///   - id: id
    ///   - name: dongle名称
    ///   - bindNodeAddress: 绑定的设备地址
    ///   - timeAuthority: 时间同步启用
    ///   - collectionEnable: 采集启用
    ///   - schedules: 采集日程list
    init(id: String, name: String, bindNodeAddress: Address? = nil, timeAuthority: Bool, collectionEnable: Bool, schedules: [CollectionSchedule]) {
        self.id = id
        self.name = name
        self.bindNodeAddress = bindNodeAddress
        self.timeAuthority = timeAuthority
        self.collectionEnable = collectionEnable
        self.schedules = schedules
    }
    
    /// 默认dongle模板
    static func `default`(id: String = UUID().uuidString) -> DeviceDongleData {
        return DeviceDongleData(id: id, name: MeshNetworkManager.instance.getNextDongleName(), timeAuthority: false, collectionEnable: false, schedules: [])
    }
    
    func copy() -> Self {
        return DeviceDongleData(id: self.id, name: self.name, bindNodeAddress: self.bindNodeAddress, timeAuthority: self.timeAuthority, collectionEnable: self.collectionEnable, schedules: self.schedules) as! Self
    }
    
    static func == (lhs: DeviceDongleData, rhs: DeviceDongleData) -> Bool {
        return lhs.id == rhs.id && lhs.name == rhs.name && lhs.bindNodeAddress == rhs.bindNodeAddress && lhs.timeAuthority == rhs.timeAuthority && lhs.collectionEnable == rhs.collectionEnable && lhs.schedules == rhs.schedules
    }
    
    func update(dongleData: DeviceDongleData) {
        self.name = dongleData.name
        self.collectionEnable = dongleData.collectionEnable
        self.bindNodeAddress = dongleData.bindNodeAddress
        self.timeAuthority = dongleData.timeAuthority
        self.schedules = dongleData.schedules
        
    }
    
    /// 下一个日程id
    func nextScheduleId() -> UInt8? {
        for id in 0...15 {
            if !schedules.contains(where: { $0.id == id }) {
                return UInt8(id)
            }
        }
        return nil
    }
    
}
