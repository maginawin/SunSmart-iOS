//
//  MeshNetwork+SunSmart.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/9/18.
//

import Foundation
import NordicSigMeshSDK

public enum DataError: Error {
    /// 空间已超出最大范围
    case exceededMaxSpaces
    
    
}

extension SiteData {
    
    /// 添加场所
    /// - Parameter name: 场所名称
    /// - Returns: 场所
    static func add(name: String) -> SiteData {
        let time = CLongLong(Date().timeIntervalSince1970 * 1000)
        let site = SiteData(id: UUID().uuidString, name: name, imageId: 1, type: .office, create: "\(time)",isFavourite: false, sourceType: .create)
        site.save()
        return site
    }
    
    /// 场所添加空间
    /// - Parameters:
    ///   - name: 空间名称
    ///   - id: 空间id
    ///   - imageId: 空间图片id
    /// - Returns: 空间
    func addSpace(name: String, id: String = UUID().uuidString, imageId: Int = 1) -> SpaceData {
        
        let time = CLongLong(Date().timeIntervalSince1970 * 1000)
        let space = SpaceData(name: name, id: id, siteId: self.id, imageId: imageId, create: "\(time)", isFavourite: false, sourceType: .create, meshUUID: id)
        addSpace(space)
        return space
    }
     
    /// 场所添加空间
    /// - Parameter space: 空间数据
    func addSpace(_ space: SpaceData) {
        // 没有对应mesh网络时创建一个网络
        if MeshNetworkManager.loadMeshNetwork(meshUUID: space.meshUUID) == nil {
            MeshLibManager.manager.createMeshNetwork(meshUUID: space.meshUUID, meshNetworkName: space.name, connected: false)
        }
        space.save()
        spaces.append(space)
    }
    
    /// 克隆场所数据
    /// - Parameter save: 是否本地缓存
    func clone(_ save: Bool = false) -> SiteData {
        let siteData = self.cloneData()
        let spaces = self.spaces.map({ $0.clone() })
        siteData.spaces = spaces
        if save {
            siteData.save(allData: true)
        }
        return siteData
    }
}

extension SpaceData {
    
    private struct AssociatedKey {
        static var meshManagerKey = 1
    }
    
    var meshManager: MeshNetworkManager? {
        get {
            objc_getAssociatedObject(self, &AssociatedKey.meshManagerKey) as? MeshNetworkManager ??
            MeshNetworkManager.loadMeshNetwork(meshUUID: id)
        }set {
            objc_setAssociatedObject(self, &AssociatedKey.meshManagerKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    
    var nodes: [Node] {
        return meshManager?.realNodes ?? []
    }
    
    var groups: [Group] {
        return meshManager?.groups ?? []
    }
    
    var scenes: [Scene] {
        return meshManager?.scenes ?? []
    }
    
    var schedules: [Schedule] {
        return meshManager?.schedules ?? []
    }
    
    /// 获取下一个节点名称
    /// - Parameter defalutName: 默认名称
    /// - Returns: 分配的节点名称
    func getNextNodeName(_ defalutName: String = "device_defalut_name".localizedString) -> String {
        objc_sync_enter(self)
        
        var resultName = defalutName + "001"
        // 已存在的节点名称
        let existNames = self.nodes.map({ $0.name ?? "" })
        for index in 1...32767 {
            // ID001
            let name = defalutName + String(format: "%03d", index)
            if !existNames.contains(name) {
                resultName = name
                break
            }
        }
        objc_sync_exit(self)
        return resultName
        
    }
    
    /// 设备节点是否重名
    /// - Parameter nodeName: 节点名称
    /// - Returns: 是否重名
    func isNodeTautonym(nodeName: String) -> Bool {
        return nodes.contains(where: { $0.name == nodeName })
    }
    
    /// 获取下一个场景名称
    /// - Parameter defalutName: 默认名称
    /// - Returns: 分配的场景名称
    func getNextSceneName(_ defalutName: String = "scene_defalut_name".localizedString) -> String {
        // 已存在的场景名称
        let existNames = scenes.map({ $0.name })
        for index in 1...16 {
            let name = defalutName + "\(index)"
            if !existNames.contains(name) {
                return name
            }
        }
        return defalutName + "1"
    }
    
    /// 场景是否重名
    /// - Parameter name: 名称
    /// - Returns: 是否重名
    func isSceneTautonym(name: String) -> Bool {
        return scenes.contains(where: { $0.name == name })
    }
    
    /// 获取下一个组名称
    /// - Parameter defalutName: 默认名称
    /// - Returns: 分配的组名称
    func getNextGroupName(_ defalutName: String = "group_defalut_name".localizedString) -> String {
        // 已存在的组名称
        let existNames = groups.map({ $0.name })
        for index in 1...16 {
            let name = defalutName + "\(index)"
            if !existNames.contains(name) {
                return name
            }
        }
        return defalutName + "1"
    }
    
    /// 组是否重名
    /// - Parameter name: 名称
    /// - Returns: 是否重名
    func isGroupTautonym(name: String) -> Bool {
        return groups.contains(where: { $0.name == name })
    }
    
    /// 克隆空间数据（空间信息、mesh网络数据）
    /// - Parameter save: 是否本地缓存
    func clone(_ save: Bool = false) -> SpaceData {
        
        let spaceData = self.cloneData()
        // 创建的mesh网络
        let meshManager = MeshNetworkManager.createMeshNetwork(meshUUID: spaceData.id, meshNetworkName: spaceData.name)
        // 克隆目标的mesh网络，同步数据
        if let cloneMeshManager = spaceData.meshManager {
            // clone 组，场景，日程，节律等这些能够预设的参数。（目前只有组、场景）
            cloneMeshManager.groups.forEach { group in
                try? meshManager.meshNetwork?.add(group: group)
            }
            cloneMeshManager.scenes.forEach { scene in
                try? meshManager.meshNetwork?.add(scene: scene.number, name: scene.info.name ?? scene.name)
            }
        }
        _ = meshManager.save()
        if save {
            spaceData.save()
        }
        return spaceData
    }
    
    /// 删除空间数据+mesh网络
    @discardableResult func delete() -> Bool {
        
        // 删除mesh网络文件并断开连接
//        MeshLibManager.manager.removeMeshNetwork(meshUUID: self.meshUUID)
        if MeshNetworkManager.instance.meshNetwork?.uuid.uuidString == self.meshUUID {
            MeshLibManager.manager.meshNetworkDisconnect()
        }
        _ = MeshNetworkManager.removeMeshNetwork(meshUUID: self.meshUUID)
        // 删除网络扩展数据
        _ = GroupInfo.deleteAll(meshUUID: meshUUID)
        _ = SceneInfo.deleteAll(meshUUID: meshUUID)
        _ = SceneExecuteData.deleteAll(meshUUID: meshUUID)
        _ = Schedule.deleteAll(meshUUID: meshUUID)
        _ = Node.deleteAllInfo(meshUUID: meshUUID)
        _ = Node.deleteAllSchedule(meshUUID: meshUUID)
        
        return self.deleteData()
    }
    
}

extension MeshNetworkManager {
    
    private static var schedulesKey = 0
    
    /// 日程list
    var schedules: [Schedule] {
        get {
            objc_getAssociatedObject(self, &MeshNetworkManager.schedulesKey) as? [Schedule] ?? []
        }set {
            objc_setAssociatedObject(self, &MeshNetworkManager.schedulesKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    /// 获取网络扩展数据
    func loadExtensionData() {
        
        guard let uuid = self.meshNetwork?.uuid.uuidString else { return }
        
        realNodes.forEach({
            $0.loadExtendInfo()
        })
        
        groups.forEach({
            if let info = GroupInfo.load(meshUUID: uuid, address: $0.address.address) {
                $0.info = info
            }
        })
        
        scenes.forEach({
            if let info = SceneInfo.load(meshUUID: uuid, sceneId: Int($0.number)) {
                $0.info = info
            }
        })
        
        schedules = Schedule.loadAll(meshUUID: uuid)
    }
    
}

extension Group {
    
    private static var infoKey = 0
    private static var lightnessKey = 1
    private static var cctKey = 2
    private static var isOnKey = 3
    
    static let defaultLightness: UInt16 = .max
    static let defaultCct: Int = 4500
    
    /// 扩展信息
    var info: GroupInfo {
        get {
            objc_getAssociatedObject(self, &Group.infoKey) as? GroupInfo ?? GroupInfo(address: address.address, name: name, imageId: 0)
        }set {
            objc_setAssociatedObject(self, &Group.infoKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    /// 组亮度值 0~65535
    var lightness: UInt16 {
        get {
            // 缓存值->相同频率最高值->默认值
            // 读取缓存
            guard let lightness = objc_getAssociatedObject(self, &Group.lightnessKey) as? UInt16 else {
                // 计算频率最高值 出现次数>1
                let lightnesss = self.nodes.filter({ $0.lightnessModel != nil }).map({ $0.lightness })
                var lightnessValueList: [NSMutableArray] = []
                lightnesss.forEach { value in
                    if let values = lightnessValueList.first(where: { $0.contains(value) }) {
                        values.add(value)
                    }else {
                        lightnessValueList.append(NSMutableArray(object: value))
                    }
                }
                // 默认值
                var lightness = Group.defaultLightness
                if let values = lightnessValueList.max(by: { $1.count > $0.count }), values.count > 1 {
                    lightness = values.firstObject as! UInt16
                }
                return lightness
            }
            return lightness
        }
    }
    
    /// 组色温值 2700K-6500K
    var cct: Int {
        get {
            // 缓存值->相同频率最高值->默认值
            // 读取缓存
            guard let cct = objc_getAssociatedObject(self, &Group.cctKey) as? Int else {
                // 计算频率最高值 出现次数>1
                let ccts = self.nodes.filter({ $0.temperatureModel != nil || $0.ctlModel != nil }).map({ $0.temperature })
                var cctValueList: [NSMutableArray] = []
                ccts.forEach { value in
                    if let values = cctValueList.first(where: { $0.contains(value) }) {
                        values.add(value)
                    }else {
                        cctValueList.append(NSMutableArray(object: value))
                    }
                }
                // 默认值
                var cct = Group.defaultCct
                if let values = cctValueList.max(by: { $1.count > $0.count }), values.count > 1 {
                    cct = values.firstObject as! Int
                }
                return cct
            }
            return cct
        }
    }
    
    /// 组开关
    var isOn: Bool {
        get {
            objc_getAssociatedObject(self, &Group.isOnKey) as? Bool ?? (nodes.isEmpty || nodes.contains(where: { $0.isOn }))
        }set {
            objc_setAssociatedObject(self, &Group.isOnKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    /// 是否支持onoff
    var supportOnOff: Bool {
        return nodes.contains(where: { $0.onoffModel != nil })
    }
    
    /// 是否支持亮度
    var supportLightness: Bool {
        return nodes.contains(where: { $0.lightnessModel != nil })
    }
    
    /// 是否支持色温
    var supportCct: Bool {
        return nodes.contains(where: { $0.temperatureModel != nil || $0.ctlModel != nil })
    }
    
    /// 删除本地化缓存数据（只处理业务扩展数据）
    func delete() {
        guard let uuid = MeshNetworkManager.instance.meshNetwork?.uuid.uuidString else {
            return
        }
        // 删除基本信息
        GroupInfo.delete(meshUUID: uuid, address: address.address)
        // 删除组设置的场景数据
        SceneExecuteData.deleteData(meshUUID: uuid, address: address.address)
    }
    
    /// 删除组内的场景缓存
    /// - Parameter sceneId: 场景id
    func delete(sceneId: SceneNumber) {
      
        self.info.bindSceneDatas.removeValue(forKey: sceneId)
        guard let uuid = MeshNetworkManager.instance.meshNetwork?.uuid.uuidString else {
            return
        }
        SceneExecuteData.deleteData(meshUUID: uuid, address: address.address, sceneId: Int(sceneId))
    }
    
    /// 更新组内的场景状态
    /// - Parameter sceneId: 场景id
    func updateSceneState(sceneId: SceneNumber, state: SceneExecuteData.State) {
      
        if let sceneData = self.info.bindSceneDatas[sceneId] {
            sceneData.state = state
            guard let uuid = MeshNetworkManager.instance.meshNetwork?.uuid.uuidString else {
                return
            }
            SceneExecuteData.save(meshUUID: uuid, address: address.address, sceneId: Int(sceneId), sceneData: sceneData)
        }
    }
    
    /// 本地化缓存组数据（只处理业务扩展数据）
    func save() {
        
        guard let uuid = MeshNetworkManager.instance.meshNetwork?.uuid.uuidString else {
            return
        }
        // 保存基本信息
        self.info.save(meshUUID: uuid)
        // 保存场景数据
        self.info.bindSceneDatas.forEach({
            SceneExecuteData.save(meshUUID: uuid, address: address.address, sceneId: Int($0.key), sceneData: $0.value)
        })
        
    }

}

extension Scene {
    
    private static var infoKey = 0
    /// 扩展信息
    var info: SceneInfo {
        get {
            objc_getAssociatedObject(self, &Scene.infoKey) as? SceneInfo ?? SceneInfo(sceneId: self.number, name: name, imageId: 0)
        }set {
            objc_setAssociatedObject(self, &Scene.infoKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    /// 删除场景缓存数据
    func delete() {
        guard let uuid = MeshNetworkManager.instance.meshNetwork?.uuid.uuidString else {
            return
        }
        SceneInfo.delete(meshUUID: uuid, sceneId: self.number)
    }
    
    /// 本地化缓存组数据（只处理业务扩展数据）
//    func save() {
//        
//        guard let uuid = MeshNetworkManager.instance.meshNetwork?.uuid.uuidString else {
//            return
//        }
//        // 保存基本信息
//        self.info.save(meshUUID: uuid)
//        // 保存场景数据
//        self.info.groups.forEach({
//            SceneExecuteData.save(meshUUID: uuid, address: $0.address.address, sceneId: Int(sceneId), sceneData: data)
//        })
//    }
    
}

class SceneInfo {
    
    /// 场景id
    var sceneId: UInt16 = 0
    
    /// 场景名称
    var name: String?
    
    /// 图片id
    var imageId: Int = 0
    
    /// 添加的组list
    var groups: [Group] = []
    
    init(sceneId: UInt16, name: String? = nil, imageId: Int, groups: [Group] = []) {
        self.sceneId = sceneId
        self.name = name
        self.imageId = imageId
        self.groups = groups
    }
}

class GroupInfo {
    
    /// 组地址
    var address: UInt16 = 0
    
    /// 组名称
    var name: String?
    
    /// 图片id
    var imageId: Int = 0
    
    /// 图标文本（自定义）
    var imageText: String?
    
    /// 绑定的场景数据
    var bindSceneDatas: [SceneNumber : SceneExecuteData] = [:]
    
    /// 绑定的日程数据
    var bindSchedules: [Schedule] = []
    
    init(address: UInt16, name: String? = nil, imageId: Int, imageText: String? = nil, bindSceneDatas: [SceneNumber : SceneExecuteData] = [:], bindSchedules: [Schedule] = []) {
        self.address = address
        self.name = name
        self.imageId = imageId
        self.imageText = imageText
        self.bindSceneDatas = bindSceneDatas
        self.bindSchedules = bindSchedules
    }
}

/// 场景执行数据
class SceneExecuteData {
    
    /// 场景执行数据色温范围
    static let cctRange: ClosedRange<UInt16> = 2700...6500
    
    /// 状态
    enum State: Int {
        /// 正常
        case normal = 1
        /// 待删除（删除失败）
        case waitDelete = 2
    }
    
    /// 亮度 0~100
    var lightness: Int = 0
    /// 色温
    var cct: Int = 0
    /// 状态 1:正常  2:删除
    var state: State = .normal
    
    init(lightness: Int, cct: Int, state: State = .normal) {
        self.lightness = lightness
        self.cct = cct
        self.state = state
    }
    
    static func == (lhs: SceneExecuteData, rhs: SceneExecuteData) -> Bool {
        return lhs.lightness == rhs.lightness && lhs.cct == rhs.cct
    }
}

class Schedule: Copyable {
    
    /// 重复周期字符串list
    static let weeklyStrs = ["week_mo".localizedString, "week_tu".localizedString, "week_we".localizedString, "week_th".localizedString, "week_fr".localizedString, "week_sa".localizedString, "week_su".localizedString]
    
    /// 日程执行目标类型
    enum TargetType: Int {
        /// 组
        case groups = 0
        /// 设备
        case devices = 1
        /// 设备
        case scene = 2
    }
    
    /// 计划id  0~15
    var id: Int = 0
    /// 是否启用
    var enabled: Bool = false
    /// 名称
    var name: String = ""
    /// 设置的节点list nodes、groups、scenes三选一
    var nodes: [Node] = []
    /// 设置的组list nodes、groups、scenes三选一
    var groups: [Group] = []
    /// 设置执行的场景list，目前只能设置一个，并且nodes、groups、scenes三选一
//    var scenes: [Scene] = []
    /// 选择的执行目标类型
    var selectTargetType: TargetType = .groups
    /// 执行的场景id
    var actionSceneId: SceneNumber = 0
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
    /// 创建时间（时间戳毫秒）
    var create: String
    /// 最近更新的时间（时间戳毫秒）
    var lastUpdate: String
    /// 需要移出日程的设备
    var needDeleteNodes: [Node] = []
    /// 需要移出日程的group
    var needDeleteGroups: [Group] = []
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
        let allMonths: [Month] = [.January,.February,.March,.April,.May,.June,.July,.August,.September,.October,.November,.December]
        let entry = SchedulerRegistryEntry(year: .any(), month: .any(of: allMonths), day: .any(), hour: .specific(hour: hour), minute: .specific(minute: minute), second: .specific(second: 0), dayOfWeek: .any(of: weekDays), action: action, transitionTime: .init(steps: UInt8(fadeTime), stepResolution: .seconds), sceneNumber: actionSceneId)
        return entry
    }
    
    
    
    init(id: Int, name: String, enabled: Bool, nodes: [Node] = [], groups: [Group] = [], actionSceneId: SceneNumber = 0, action: SchedulerAction, fadeTime: Int, weekDays: [WeekDay], hour: Int, minute: Int, create: String, lastUpdate: String? = nil) {
        self.id = id
        self.enabled = enabled
        self.name = name
        self.nodes = nodes
        self.groups = groups
        self.actionSceneId = actionSceneId
        self.action = action
        self.fadeTime = fadeTime
        self.weekDays = weekDays
        self.hour = hour
        self.minute = minute
        self.create = create
        self.lastUpdate = lastUpdate ?? create
    }
    
    /// 复制日程
    func copy() -> Self {
        let schedule = Schedule(id: id, name: name, enabled: enabled, nodes: nodes, groups: groups, actionSceneId: actionSceneId, action: action, fadeTime: fadeTime, weekDays: weekDays, hour: hour, minute: minute, create: create, lastUpdate: lastUpdate)
        return schedule as! Self
    }
    
    
    /// 更新日程数据
    /// - Parameter entry: 设备日程数据
    func updata(entry: SchedulerRegistryEntry) {
        
        self.enabled = entry.month.value > 0 && entry.action != .noAction
        self.action = entry.action
        self.actionSceneId = entry.sceneNumber
        self.fadeTime = Int(entry.transitionTime.steps)
        
        // 计算选中的重复周期
        let allWeekDays: [WeekDay] = [.Monday, .Tuesday, .Wednesday, .Thursday, .Friday, .Saturday, .Sunday]
        var selectWeekDays: [WeekDay] = []
        for (weekInt, weekDay) in allWeekDays.enumerated() {
            if entry.dayOfWeek.value >> weekInt & 1 == 1 {
                selectWeekDays.append(weekDay)
            }
        }
        self.weekDays = selectWeekDays
        self.hour = Int(entry.hour.value)
        self.minute = Int(entry.minute.value)
    }
    
    static func == (lhs: Schedule, rhs: Schedule) -> Bool {
        
        return lhs.id == rhs.id && lhs.name == rhs.name && lhs.enabled == rhs.enabled && lhs.selectTargetType == rhs.selectTargetType && lhs.actionSceneId == rhs.actionSceneId && lhs.action == rhs.action && lhs.fadeTime == rhs.fadeTime && lhs.weekDays == rhs.weekDays && lhs.hour == rhs.hour && lhs.minute == rhs.minute
    }
    
}

extension Node {
    /// 设备对应组状态
    enum GroupState: Int {
        /// 无（未加入）
        case none = 0
        /// 在组内
        case inGroup = 1
        /// 退出组失败
        case exitFailure = 2
    }
    
    static private var bindSceneDatasKey = 1
    static private var schedulesKey = 2
    static private var groupStateKey = 2
    
    /// 设备对应组状态
    var groupState: GroupState {
        get {
            objc_getAssociatedObject(self, &Node.groupStateKey) as? GroupState ?? (group != nil ? .inGroup : .none)
        }set {
            objc_setAssociatedObject(self, &Node.groupStateKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    /// 节点缓存的场景数据
    var sceneDatas: [SceneNumber: SceneExecuteData] {
        get {
            objc_getAssociatedObject(self, &Node.bindSceneDatasKey) as? [SceneNumber: SceneExecuteData] ?? [:]
        }set {
            objc_setAssociatedObject(self, &Node.bindSceneDatasKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    /// 节点缓存的日程数据（设置成功）
    var scheduleDatas: [Int: SchedulerRegistryEntry] {
        get {
            objc_getAssociatedObject(self, &Node.schedulesKey) as? [Int: SchedulerRegistryEntry] ?? [:]
        }set {
            objc_setAssociatedObject(self, &Node.schedulesKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    /// mac地址分割
    var macAddressResult: String? {
        if let macAddress = macAddress, !macAddress.isEmpty {
            var result = ""
            var offset = 0
            for _ in 0..<Int(macAddress.count / 2) {
                if offset + 2 > macAddress.count { break }
                let string = macAddress.subString(rang: NSRange(location: offset, length: 2))
                offset += 2
                result.append(String(format: "%@%@", result.isEmpty ? "" : ":", string))
            }
            return result
        }
        return nil
    }
    
    /// 根据色温范围获取对应色温颜色
    /// - Parameter cct100: 0~100色温
    /// - Returns: 对应色温颜色
    static func getCctMixColor(temperature100: Int) -> UIColor {
        // 暖色
        let components1 = RGB(255, 108, 0).cgColor.components!
        // 过渡色
        let components2 = RGB(255, 255, 255).cgColor.components!
        // 冷色
        let components3 = RGB(114, 179, 255).cgColor.components!
        
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        // 0~1比例
        var ratio: CGFloat = 0
        switch temperature100 {
        case 0...50: // 0~50取暖色到过渡色的混色
            ratio = CGFloat(temperature100) / 50.0
            r = components2[0] * ratio + components1[0] * (1.0 - ratio)
            g = components2[1] * ratio + components1[1] * (1.0 - ratio)
            b = components2[2] * ratio + components1[2] * (1.0 - ratio)
        case 50...100: // 50~100取过渡色到冷色的混色
            ratio = CGFloat(temperature100 - 50) / 50.0
            r = components3[0] * ratio + components2[0] * (1.0 - ratio)
            g = components3[1] * ratio + components2[1] * (1.0 - ratio)
            b = components3[2] * ratio + components2[2] * (1.0 - ratio)
        default:
            break
        }
        let color =  UIColor(red: r, green: g, blue: b, alpha: 1)
        return color
    }
    
    /// 获取设备所有扩展数据
    func loadExtendInfo() {
        
        guard let uuid = MeshNetworkManager.instance.meshNetwork?.uuid.uuidString else {
            return
        }
        if let info = Node.loadNodeInfo(meshUUID: uuid, address: primaryUnicastAddress) {
            self.lightCTLTemperatureRange = info.cctRange
            self.groupState = info.groupState
            self.scheduleDatas = info.schedules
            self.sceneDatas = info.sceneDatas as! [SceneNumber: SceneExecuteData]
            self.scheduleIds = self.scheduleDatas.compactMap({
                if $0.value.isValid {
                    return $0.key
                }
                return nil
            })
            
            self.schedulerActions = self.scheduleDatas.filter({ $0.value.isValid })
//            self.rssi = info.rssi
        }
        
    }
    
    /// 删除设备缓存的所有扩展数据
    func delete() {
        guard let uuid = MeshNetworkManager.instance.meshNetwork?.uuid.uuidString else {
            return
        }
        // 删除设备缓存信息
        Node.deleteInfo(meshUUID: uuid, address: primaryUnicastAddress)
        // 删除设备场景数据
        SceneExecuteData.deleteData(meshUUID: uuid, address: primaryUnicastAddress)
        // 删除设备日程数据
        Node.deleteSchedules(meshUUID: uuid, address: primaryUnicastAddress)
    }
    
    /// 删除节点内的场景缓存
    /// - Parameter sceneId: 场景id
    func delete(sceneId: SceneNumber) {
      
        sceneDatas.removeValue(forKey: sceneId)
        guard let uuid = MeshNetworkManager.instance.meshNetwork?.uuid.uuidString else {
            return
        }
        SceneExecuteData.deleteData(meshUUID: uuid, address: primaryUnicastAddress, sceneId: Int(sceneId))
    }
    
    /// 本地化缓存设备数据
    func save() {
        
        guard let uuid = MeshNetworkManager.instance.meshNetwork?.uuid.uuidString else {
            return
        }
        
        saveNodeInfo(meshUUID: uuid)
        
        scheduleDatas.forEach({
            Node.saveSchedule(meshUUID: uuid, address: primaryUnicastAddress, scheduleId: $0.key, entry: $0.value)
        })
        
        sceneDatas.forEach({
            SceneExecuteData.save(meshUUID: uuid, address: primaryUnicastAddress, sceneId: Int($0.key), sceneData: $0.value)
        })
        
        
    }
    
    
    /// 更新节点缓存数据
    /// - Parameter messageHandle: 消息发送操作对象
    func updateData(message: MeshMessage) {
       
        let meshUUID = MeshNetworkManager.instance.meshNetwork?.uuid.uuidString
//        let isSuccess = messageHandle.isFinished
//        let message = messageHandle.message
        switch message {
        case is ConfigModelSubscriptionAdd:
            self.groupState = .inGroup
            
        case is ConfigModelSubscriptionDelete:
            self.groupState = self.group != nil ? .inGroup : .exitFailure
            
        case is SceneStore:
            let sceneId = (message as! SceneStore).scene
            let executeData = SceneExecuteData(lightness: self.lightness100, cct: self.temperature100, state: .normal)
            self.sceneDatas.updateValue(executeData, forKey: sceneId)
            if let uuid = meshUUID {
                SceneExecuteData.save(meshUUID: uuid, address: primaryUnicastAddress, sceneId: Int(sceneId), sceneData: executeData)
            }
            
        case is SceneDelete:
            let sceneId = (message as! SceneDelete).scene
            self.sceneDatas.removeValue(forKey: sceneId)
            if let uuid = meshUUID {
                SceneExecuteData.deleteData(meshUUID: uuid, address: primaryUnicastAddress, sceneId: Int(sceneId))
            }
            
        case is SchedulerActionSet:
            let actionMessage = (message as! SchedulerActionSet)
            if actionMessage.entry.isValid {
                self.scheduleDatas.updateValue(actionMessage.entry, forKey: Int(actionMessage.index))
                if let uuid = meshUUID {
                    Node.saveSchedule(meshUUID: uuid, address: primaryUnicastAddress, scheduleId: Int(actionMessage.index), entry: actionMessage.entry)
                }
            }else {
                self.scheduleDatas.removeValue(forKey: Int(actionMessage.index))
                if let uuid = meshUUID {
                    Node.deleteSchedule(meshUUID: uuid, address: primaryUnicastAddress, scheduleId: Int(actionMessage.index))
                }
            }
        
        default:
            break
        }
        
        
    }
  
    
}

extension SchedulerRegistryEntry {
    /// 是否开启
    var isEnabled: Bool {
        return self.action != .noAction && self.month.value > 0
    }
    
    /// 是否有效
    var isValid: Bool {
        return self.action != .noAction
    }
    
    static func == (lhs: SchedulerRegistryEntry, rhs: SchedulerRegistryEntry) -> Bool {
        return lhs.year.value == rhs.year.value && lhs.month.value == rhs.month.value && lhs.day.value == rhs.day.value && lhs.hour.value == rhs.hour.value && lhs.minute.value == rhs.minute.value && lhs.second.value == rhs.second.value && lhs.dayOfWeek.value == rhs.dayOfWeek.value && lhs.action == rhs.action && lhs.transitionTime.rawValue == rhs.transitionTime.rawValue && lhs.sceneNumber == rhs.sceneNumber
    }
}
