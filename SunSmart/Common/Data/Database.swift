//
//  Database.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/8/24.
//

import Foundation
import NordicSigMeshSDK
import SQLite

private var jsonEncoder: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = .withoutEscapingSlashes
    return encoder
}

private var jsonDecoder: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
}

/// 缓存场所/空间数据库名称
let sqliteDBName = "sunsmart.sqlite"

class SunSmartDataManager {
    
    static let shared = SunSmartDataManager()
    
    private let docPath = NSHomeDirectory() + "/Documents"
    private(set) var db: Connection?
    
    init() {
        db = try? Connection("\(docPath)/sunsmart.sqlite3")
        db?.busyTimeout = 1.5
    }
    
    public func initDatabase() {
        SiteData.initDatabase()
        // 初始化网络数据库
        MeshDataManager.shared.initDatabase()
    }
}

extension SiteData {
    
    private static let sitesTable = Table("sites")
    
    struct ExpressionKey {
        static let id = Expression<Int64>("id")
        static let uuid = Expression<String>("uuid")
        static let name = Expression<String>("name")
        static let imageId = Expression<Int>("imageId")
        static let type = Expression<Int>("type")
        static let source = Expression<Int>("source")
        static let favourite = Expression<Bool>("favourite")
        static let createTimestamp = Expression<Int64>("createTimestamp")
        static let lastUpdateTimestamp = Expression<Int64>("lastUpdateTimestamp")
    }
    
    /// 初始化场所表
    static func initDatabase() {
        
        _ = try? SunSmartDataManager.shared.db?.run(SiteData.sitesTable.create(temporary: false, ifNotExists: true, withoutRowid: false, block: { builder in
            builder.column(ExpressionKey.id, primaryKey: true)
            builder.column(ExpressionKey.uuid, unique: true)
            builder.column(ExpressionKey.name)
            builder.column(ExpressionKey.imageId)
            builder.column(ExpressionKey.type)
            builder.column(ExpressionKey.source)
            builder.column(ExpressionKey.favourite)
            builder.column(ExpressionKey.createTimestamp)
            builder.column(ExpressionKey.lastUpdateTimestamp)
        }))
        
        SpaceData.initDatabase()
    }
    
    /// 获取所有的场所
    /// - Returns: mesh网络list
    static func loadAll() -> [SiteData] {
        
        var sites: [SiteData] = []
        if let rows = try? SunSmartDataManager.shared.db?.prepare(SiteData.sitesTable.order(ExpressionKey.createTimestamp.asc)) {
            for row in rows {
                let site = SiteData(id: row[ExpressionKey.uuid], meshUUID: row[ExpressionKey.uuid], name: row[ExpressionKey.name], imageId: row[ExpressionKey.imageId], type: .init(rawValue: row[ExpressionKey.type]) ?? .office, create: "\(row[ExpressionKey.createTimestamp])", lastUpdate: "\(row[ExpressionKey.lastUpdateTimestamp])", isFavourite: row[ExpressionKey.favourite], sourceType: .init(rawValue: row[ExpressionKey.source]) ?? .create)
                sites.append(site)
            }
        }
        
        for site in sites {
            /// 获取场所下空间list
            site.spaces = SpaceData.load(siteId: site.id)
        }
        
        return sites
    }
    
    /// 根据场所id获取对应场所
    /// - Parameter siteId: 场所id
    /// - Returns: 返回场所对象
    static func load(siteId: String) -> SiteData? {
        
        let filter = SiteData.sitesTable.filter(ExpressionKey.uuid == siteId)
        
        var site: SiteData?
        if let rows = try? SunSmartDataManager.shared.db?.prepare(filter) {
            for row in rows {
                site = SiteData(id: row[ExpressionKey.uuid], meshUUID: row[ExpressionKey.uuid], name: row[ExpressionKey.name], imageId: row[ExpressionKey.imageId], type: .init(rawValue: row[ExpressionKey.type]) ?? .office, create: "\(row[ExpressionKey.createTimestamp])", lastUpdate: "\(row[ExpressionKey.lastUpdateTimestamp])", isFavourite: row[ExpressionKey.favourite], sourceType: .init(rawValue: row[ExpressionKey.source]) ?? .create)
                break
            }
        }
        site?.spaces = SpaceData.load(siteId: siteId)
        
        return site
    }
    
    /// 删除当前场所数据
    @discardableResult func deleteData() -> Bool {
        let filter = SiteData.sitesTable.filter(ExpressionKey.uuid == id)
        do {
            try SunSmartDataManager.shared.db?.run(filter.delete())
        } catch {
            print(error)
            return false
        }
        spaces.forEach({
            $0.delete()
        })
        return true
    }
    
    /// 删除所有场所数据
//    static func deleteAllData() -> Bool {
//        do {
//            try SunSmartDataManager.shared.db?.run(SiteData.sitesTable.delete())
//        } catch {
//            print(error)
//            return false
//        }
//        return true
//    }
    
    /// 获取下一个site名称
    /// - Parameter defalutName: 查询的site默认名称  ”Site “
    /// - Returns: 默认的site名称
    static func getNextSiteName(_ defalutName: String = "site_defalut_name".localizedString) -> String {
        
        var result = "\(defalutName)1"
        // 场所已使用的名称索引
        var siteIndexs: [Int] = []
        let sql = SiteData.sitesTable.filter(ExpressionKey.name.like(defalutName + "%"))
        if let rows = try? SunSmartDataManager.shared.db?.prepare(sql) {
            for row in rows {
                let siteName = row[ExpressionKey.name]
                if let index = Int(siteName.replacingOccurrences(of: defalutName, with: "")) {
                    siteIndexs.append(index)
                }
            }
        }
        // 获取未被使用的site索引
        for index in 1...1000 {
            if !siteIndexs.contains(index) {
                result = defalutName + "\(index)"
                break
            }
        }
        return result
    }
    
    /// 克隆当前场所
    func cloneData() -> SiteData {
        let site = self.copy()
        site.id = UUID().uuidString
        site.name = SiteData.getNextCloneSiteName(site.name)
        site.sourceType = .clone
        let time = CLongLong(Date().timeIntervalSince1970 * 1000)
        site.create = "\(time)"
        site.lastUpdate = "\(time)"
        // 克隆场所内空间
        var spaces: [SpaceData] = []
        site.spaces.forEach { space in
            space.siteId = site.id
            let data = space.cloneData()
            spaces.append(data)
        }
        site.spaces = spaces
//        guard site.save() else {
//            return nil
//        }
        return site
    }
    
    /// 获取下一个克隆site名称
    /// - Parameter siteName: 克隆的场所名称
    /// - Returns: 默认的site名称
    static func getNextCloneSiteName(_ siteName: String) -> String {
        
        var result = "\(siteName)(1)"
        // 场所已使用的名称索引
        var siteIndexs: [Int] = []
        // 匹配名称
        let matching = "\(siteName)("
        
        let sql = SiteData.sitesTable.filter(ExpressionKey.name.like(matching + "%"))
        if let rows = try? SunSmartDataManager.shared.db?.prepare(sql) {
            for row in rows {
                let siteName = row[ExpressionKey.name]
                var cloneName = siteName.replacingOccurrences(of: "\(matching)", with: "")
                cloneName = cloneName.replacingOccurrences(of: ")", with: "")
                if let index = Int(cloneName) {
                    siteIndexs.append(index)
                }
            }
        }
        
        // 获取未被使用的site索引
        for index in 1...1000 {
            if !siteIndexs.contains(index) {
                result = siteName + "(\(index))"
                break
            }
        }
        return result
    }
    
    
    /// 判断场所名称是否重名
    /// - Parameter siteName: 场所名称
    /// - Returns: 是否重名
    static func isTautonym(siteName: String) -> Bool {
        
        let filter = SiteData.sitesTable.filter(ExpressionKey.name == siteName)
        let reuslt = try? SunSmartDataManager.shared.db?.prepareRowIterator(filter)
        if reuslt?.next() != nil {
            return true
        }
        return false
    }
    
    /// 缓存当前场所数据
    /// allData：是否保存所有数据（true：场所基本信息+保存spaces数据，false：场所基本信息）
    @discardableResult func save(allData: Bool = false) -> Bool {
        
        let table = SiteData.sitesTable
        let createTimestamp = Int64(self.create) ?? Int64(Date().timeIntervalSince1970 * 1000)
        let insetOrUpdate = table.insert(or: .replace, [
            ExpressionKey.uuid <- self.id,
            ExpressionKey.name <- self.name,
            ExpressionKey.imageId <- self.imageId,
            ExpressionKey.type <- self.type.rawValue,
            ExpressionKey.source <- self.sourceType.rawValue,
            ExpressionKey.favourite <- self.isFavourite,
            ExpressionKey.createTimestamp <- createTimestamp,
            ExpressionKey.lastUpdateTimestamp <- Int64(self.lastUpdate) ?? createTimestamp
        ])
        do {
            try SunSmartDataManager.shared.db?.run(insetOrUpdate)
        } catch {
            print(error)
            return false
        }
        if allData {
            self.spaces.forEach({ $0.save() })
        }
        return true
    }
       
}

extension SpaceData {
    
    private static let spacesTable = Table("spaces")
    
    struct ExpressionKey {
        static let id = Expression<Int64>("id")
        static let uuid = Expression<String>("uuid")
        static let siteUUID = Expression<String>("siteUUID")
        static let subNetworkKey = Expression<String>("subNetworkKey")
        static let name = Expression<String>("name")
        static let imageId = Expression<Int>("imageId")
        static let source = Expression<Int>("source")
        static let favourite = Expression<Bool>("favourite")
        static let deviceSortType = Expression<Int>("deviceSortType")
        static let deviceNumber = Expression<Int>("deviceNumber")
        static let luminaireNumber = Expression<Int>("luminaireNumber")
        static let groupNumber = Expression<Int>("groupNumber")
        static let sceneNumber = Expression<Int>("sceneNumber")
        static let scheduleNumber = Expression<Int>("scheduleNumber")
        static let switchesNumber = Expression<Int>("switchesNumber")
        static let createTimestamp = Expression<Int64>("createTimestamp")
        static let lastUpdateTimestamp = Expression<Int64>("lastUpdateTimestamp")
    }
    
    /// 初始化空间表
    static func initDatabase() {
        
        _ = try? SunSmartDataManager.shared.db?.run(SpaceData.spacesTable.create(temporary: false, ifNotExists: true, withoutRowid: false, block: { builder in
            builder.column(ExpressionKey.id, primaryKey: true)
            builder.column(ExpressionKey.uuid, unique: true)
            builder.column(ExpressionKey.siteUUID)
            builder.column(ExpressionKey.subNetworkKey)
            builder.column(ExpressionKey.name)
            builder.column(ExpressionKey.imageId)
            builder.column(ExpressionKey.source)
            builder.column(ExpressionKey.favourite)
            builder.column(ExpressionKey.deviceSortType)
            builder.column(ExpressionKey.deviceNumber)
            builder.column(ExpressionKey.luminaireNumber)
            builder.column(ExpressionKey.groupNumber)
            builder.column(ExpressionKey.sceneNumber)
            builder.column(ExpressionKey.scheduleNumber)
            builder.column(ExpressionKey.switchesNumber)
            builder.column(ExpressionKey.createTimestamp)
            builder.column(ExpressionKey.lastUpdateTimestamp)
        }))
        GroupInfo.initDatabase()
        Profile.initDatabase()
        SceneInfo.initDatabase()
        Schedule.initDatabase()
        GroupSwitch.initDatabase()
    }
 
    
    /// 根据场所id获取所属空间list
    /// - Parameters:
    ///   - siteId: 场所id
    ///   - spaceId: 空间id（传入指定获取对应空间）
    /// - Returns: 空间list
    static func load(siteId: String, spaceId: String? = nil) -> [SpaceData] {
        
        var predicate: Expression<Bool> = ExpressionKey.siteUUID == siteId
        // 查询指定空间数据
        if spaceId != nil {
            predicate = ExpressionKey.siteUUID == siteId && ExpressionKey.uuid == spaceId!
        }
        
        var spaces: [SpaceData] = []
        let filter = SpaceData.spacesTable.filter(predicate).order(ExpressionKey.createTimestamp.asc)
        if let rows = try? SunSmartDataManager.shared.db?.prepare(filter) {
            for row in rows {
                let space = SpaceData(name: row[ExpressionKey.name], id: row[ExpressionKey.uuid], siteId: row[ExpressionKey.siteUUID], imageId: row[ExpressionKey.imageId], create: "\(row[ExpressionKey.createTimestamp])", lastUpdate: "\(row[ExpressionKey.lastUpdateTimestamp])", isFavourite: row[ExpressionKey.favourite], sourceType: .init(rawValue: row[ExpressionKey.source]) ?? .create, meshUUID: row[ExpressionKey.siteUUID], meshNetworkId: row[ExpressionKey.subNetworkKey])
                space.deviceCount = row[ExpressionKey.deviceNumber]
                space.luminairesCount = row[ExpressionKey.luminaireNumber]
                space.groupCount = row[ExpressionKey.groupNumber]
                space.sceneCount = row[ExpressionKey.sceneNumber]
                space.scheheduleCount = row[ExpressionKey.scheduleNumber]
                space.switchesCount = row[ExpressionKey.switchesNumber]
                spaces.append(space)
            }
        }
        return spaces
    }
 
    /// 删除所有空间数据
    /// - Parameter siteId: 对应场所
    /// - Returns: 是否成功
    static func deleteAll(siteId: String) -> Bool {
        
        let filter = SpaceData.spacesTable.filter(ExpressionKey.siteUUID == siteId)
        do {
            try SunSmartDataManager.shared.db?.run(filter.delete())
        } catch {
            print(error)
            return false
        }
        return true
    }
    
    /// 删除当前空间数据
    @discardableResult func deleteData() -> Bool {
        
        let filter = SpaceData.spacesTable.filter(ExpressionKey.uuid == self.id)
        do {
            try SunSmartDataManager.shared.db?.run(filter.delete())
        } catch {
            print(error)
            return false
        }
        return true
    }
    
    /// 缓存当前空间数据
    @discardableResult func save() -> Bool {

        let createTimestamp = Int64(self.create) ?? Int64(Date().timeIntervalSince1970 * 1000)
        let interOrUpdate = SpaceData.spacesTable.insert(or: .replace, [
            ExpressionKey.uuid <- self.id,
            ExpressionKey.siteUUID <- self.siteId,
            ExpressionKey.subNetworkKey <- self.meshNetworkKey.networkId.hex,
            ExpressionKey.name <- self.name,
            ExpressionKey.imageId <- self.imageId,
            ExpressionKey.source <- self.sourceType.rawValue,
            ExpressionKey.favourite <- self.isFavourite,
            ExpressionKey.deviceSortType <- self.deviceSortType.rawValue,
            ExpressionKey.deviceNumber <- self.deviceCount,
            ExpressionKey.luminaireNumber <- self.luminairesCount,
            ExpressionKey.groupNumber <- self.groupCount,
            ExpressionKey.sceneNumber <- self.sceneCount,
            ExpressionKey.scheduleNumber <- self.scheheduleCount,
            ExpressionKey.switchesNumber <- self.switchesCount,
            ExpressionKey.createTimestamp <- createTimestamp,
            ExpressionKey.lastUpdateTimestamp <- Int64(self.lastUpdate) ?? createTimestamp
        ])
        do {
            try SunSmartDataManager.shared.db?.run(interOrUpdate)
        } catch {
            print(error)
            return false
        }
        return true
    }
    
    /// 获取下一个space名称
    /// - Parameter siteId: 对应场所id
    /// - Parameter defalutName: 查询的space默认名称  ”Space “
    /// - Returns: 默认的space名称
    static func getNextSpaceName(siteId: String, defalutName: String = "space_defalut_name".localizedString) -> String {
        
        var result = "\(defalutName)1"
        // 场所已使用的名称索引
        var spaceIndexs: [Int] = []
        let sql = SpaceData.spacesTable.filter(ExpressionKey.siteUUID == siteId && ExpressionKey.name.like(defalutName + "%"))
        if let rows = try? SunSmartDataManager.shared.db?.prepare(sql) {
            for row in rows {
                
                let spaceName = row[ExpressionKey.name]
                if let index = Int(spaceName.replacingOccurrences(of: defalutName, with: "")) {
                    spaceIndexs.append(index)
                }
            }
        }
        // 获取未被使用的site索引
        for index in 1...1000 {
            if !spaceIndexs.contains(index) {
                result = defalutName + "\(index)"
                break
            }
        }
        return result
    }
    
    /// 克隆当前空间
    func cloneData() -> SpaceData {
        let space = self.copy()
        space.id = UUID().uuidString
        space.name = SpaceData.getNextCloneSpaceName(siteId: space.siteId, spaceName: space.name)
        let time = CLongLong(Date().timeIntervalSince1970 * 1000)
        space.create = "\(time)"
        space.lastUpdate = "\(time)"
        space.sourceType = .clone
        return space
    }
    
    /// 获取下一个克隆space名称
    /// - Parameter spaceName: 克隆的空间名称
    /// - Returns: 默认的site名称
    static func getNextCloneSpaceName(siteId: String, spaceName: String) -> String {
        
        var result = "\(spaceName)(1)"
        // 空间已使用的名称索引
        var spaceIndexs: [Int] = []
        // 匹配名称
        let matching = "\(spaceName)("
        
        let sql = SpaceData.spacesTable.filter(ExpressionKey.siteUUID == siteId && ExpressionKey.name.like(matching + "%"))
        if let rows = try? SunSmartDataManager.shared.db?.prepare(sql) {
            for row in rows {
                let spaceName = row[ExpressionKey.name]
                var cloneName = spaceName.replacingOccurrences(of: "\(matching)", with: "")
                cloneName = cloneName.replacingOccurrences(of: ")", with: "")
                if let index = Int(cloneName) {
                    spaceIndexs.append(index)
                }
            }
        }
        
        // 获取未被使用的space索引
        for index in 1...1000 {
            if !spaceIndexs.contains(index) {
                result = spaceName + "(\(index))"
                break
            }
        }
        return result
    }
    
    /// 判断空间名称是否重名
    /// - Parameter spaceName: 场所名称
    /// - Parameter siteId: 所在场所id
    /// - Returns: 是否重名
    static func isTautonym(spaceName: String, siteId: String) -> Bool {
        
        let filter = SpaceData.spacesTable.filter(ExpressionKey.siteUUID == siteId && ExpressionKey.name == spaceName)
        
        if let result = try? SunSmartDataManager.shared.db?.prepareRowIterator(filter), result.next() != nil {
            return true
        }
        return false
    }
    
}

extension GroupInfo {
    
    private static let groupInfosTable = Table("groupInfos")
    
    struct ExpressionKey {
        static let id = Expression<Int64>("id")
        static let meshUUID = Expression<String>("meshUUID")
        static let subNetworkKey = Expression<String>("subNetworkKey")
        static let groupAddress = Expression<Int>("groupAddress")
        static let imageId = Expression<Int>("imageId")
        static let imageText = Expression<String?>("imageText")
        static let profileId = Expression<String>("profileId")
        static let daylightSensorAddress = Expression<Int?>("daylightSensorAddress")
        static let scenesData = Expression<Data?>("scenesData")
    }
    
    /// 初始化组扩展信息表
    static func initDatabase() {
        
        _ = try? SunSmartDataManager.shared.db?.run(GroupInfo.groupInfosTable.create(temporary: false, ifNotExists: true, withoutRowid: false, block: { builder in
            builder.column(ExpressionKey.id, primaryKey: true)
            builder.column(ExpressionKey.meshUUID)
            builder.column(ExpressionKey.subNetworkKey)
            builder.column(ExpressionKey.groupAddress)
            builder.column(ExpressionKey.imageId)
            builder.column(ExpressionKey.imageText)
            builder.column(ExpressionKey.profileId)
            builder.column(ExpressionKey.daylightSensorAddress)
            builder.column(ExpressionKey.scenesData)
            builder.unique(ExpressionKey.meshUUID, ExpressionKey.groupAddress)
        }))
    }
    
    /// 根据网络id和group地址获取对应配置的组数据
    /// - Parameter meshUUID: 网络id
    /// - Parameter address: 组地址
    /// - Returns: 组数据
    static func load(meshUUID: String, address: UInt16) -> GroupInfo? {
        
        let predicate: Expression<Bool> = ExpressionKey.meshUUID == meshUUID && ExpressionKey.groupAddress == Int(address)
        
        var groupInfo: GroupInfo?
        let filter = GroupInfo.groupInfosTable.filter(predicate)
        if let rows = try? SunSmartDataManager.shared.db?.prepare(filter) {
            for row in rows {
                let info = GroupInfo(address: Address(row[ExpressionKey.groupAddress]), imageId: row[ExpressionKey.imageId], imageText: row[ExpressionKey.imageText])
                if let data = row[ExpressionKey.scenesData] {
                    info.sceneExecuteDatas = (try? jsonDecoder.decode([SceneExecuteData].self, from: data)) ?? []
                }
                // 组绑定的光照传感器
                if let daylightSensorAddress = row[ExpressionKey.daylightSensorAddress] {
                    info.ambientLightSensorNode = Node.load(meshUUID: meshUUID, address: Address(daylightSensorAddress)).first
                }
                // TODO: load Profile、Switches
                // 日程数据
//                let schedules = Schedule.load(meshUUID: meshUUID, meshNetworkKey: meshNetworkKey, address: UInt16(address))
//                groupInfo?.bindSchedules = schedules
//                // 配置数据
                if let profile = Profile.load(meshUUID: meshUUID, profileId: row[ExpressionKey.profileId]) {
                    info.profile = profile
                }
                // 虚拟按键
                info.switchs = GroupSwitch.load(meshUUID: meshUUID, groupAddress: address)
                
                groupInfo = info
                break
            }
        }
        return groupInfo
    }
    
    /// 删除对应子网内所有组扩展数据
    /// - Parameters:
    ///   - meshUUID: 所属网络id
    ///   - address: 组地址
    /// - Returns: 是否成功
    @discardableResult static func delete(meshUUID: String, networkId: String) -> Bool {
        
        let filter = GroupInfo.groupInfosTable.filter(ExpressionKey.meshUUID == meshUUID && ExpressionKey.subNetworkKey == networkId)
        do {
            try SunSmartDataManager.shared.db?.run(filter.delete())
        } catch {
            print(error)
            return false
        }
        return true
    }
    
    /// 删除对应组扩展数据
    /// - Parameters:
    ///   - meshUUID: 所属网络id
    ///   - address: 组地址
    /// - Returns: 是否成功
    @discardableResult func delete(meshUUID: String) -> Bool {
        
        let filter = GroupInfo.groupInfosTable.filter(ExpressionKey.meshUUID == meshUUID && ExpressionKey.groupAddress == Int(address))
        do {
            try SunSmartDataManager.shared.db?.run(filter.delete())
        } catch {
            print(error)
            return false
        }
        return true
    }
    
    /// 缓存对应组扩展数据
    /// - Parameters:
    ///   - meshUUID: 所属网络id
    ///   - groupAddress: 组地址
    /// - Returns: 是否成功
    @discardableResult func save(meshUUID: String? = nil) -> Bool {
        
        guard let uuid = meshUUID ?? MeshNetworkManager.instance.meshNetwork?.uuid.uuidString else { return false }
        let networkKey = MeshNetworkManager.instance.currentNetworkKey
        let scenesData = try? jsonEncoder.encode(self.sceneExecuteDatas)
        let insertOrUpdate = GroupInfo.groupInfosTable.insert(or: .replace, [
            ExpressionKey.meshUUID <- uuid,
            ExpressionKey.subNetworkKey <- networkKey.networkId.hex,
            ExpressionKey.groupAddress <- Int(self.address),
            ExpressionKey.imageId <- self.imageId,
            ExpressionKey.imageText <- self.imageText,
            ExpressionKey.profileId <- self.profile.id,
            ExpressionKey.daylightSensorAddress <- self.ambientLightSensorNode != nil ? Int(self.ambientLightSensorNode!.primaryUnicastAddress) : nil,
            ExpressionKey.scenesData <- scenesData
        ])
        do {
            try SunSmartDataManager.shared.db?.run(insertOrUpdate)
        } catch {
            print(error)
            return false
        }
        return true
    }
    
}

extension SceneInfo {
    
    private static let sceneInfosTable = Table("sceneInfos")
    
    struct ExpressionKey {
        static let id = Expression<Int64>("id")
        static let meshUUID = Expression<String>("meshUUID")
        static let subNetworkKey = Expression<String>("subNetworkKey")
        static let number = Expression<Int>("number")
        static let imageId = Expression<Int>("imageId")
    }
    
    /// 初始化组扩展信息表
    static func initDatabase() {
        
        _ = try? SunSmartDataManager.shared.db?.run(SceneInfo.sceneInfosTable.create(temporary: false, ifNotExists: true, withoutRowid: false, block: { builder in
            builder.column(ExpressionKey.id, primaryKey: true)
            builder.column(ExpressionKey.meshUUID)
            builder.column(ExpressionKey.subNetworkKey)
            builder.column(ExpressionKey.number)
            builder.column(ExpressionKey.imageId)
            builder.unique(ExpressionKey.meshUUID, ExpressionKey.number)
        }))
    }
    
    /// 根据网络id和场景id获取对应场景信息
    /// - Parameter meshUUID: 网络id
    /// - Parameter sceneId: 场景id
    /// - Returns: 场景数据
    static func load(meshUUID: String, sceneId: SceneNumber) -> SceneInfo? {
        
        let filter = SceneInfo.sceneInfosTable.filter(ExpressionKey.meshUUID == meshUUID && ExpressionKey.number == Int(sceneId))
        var sceneInfo: SceneInfo?
        if let rows = try? SunSmartDataManager.shared.db?.prepare(filter) {
            for row in rows {
                sceneInfo = SceneInfo(sceneId: SceneNumber(row[ExpressionKey.number]), imageId: row[ExpressionKey.imageId])
                break
            }
        }
        return sceneInfo
    }
    
    /// 删除对应场景扩展数据
    /// - Parameters:
    ///   - meshUUID: 所属网络id
    ///   - sceneId: 场景id
    /// - Returns: 是否成功
    @discardableResult func delete(meshUUID: String) -> Bool {
        
        let filter = SceneInfo.sceneInfosTable.filter(ExpressionKey.meshUUID == meshUUID && ExpressionKey.number == Int(sceneId))
        do {
            try SunSmartDataManager.shared.db?.run(filter.delete())
        } catch {
            print(error)
            return false
        }
        return true
    }
    
    /// 删除对应场景扩展数据
    /// - Parameters:
    ///   - meshUUID: 所属网络id
    ///   - sceneId: 场景id
    /// - Returns: 是否成功
    @discardableResult static func delete(meshUUID: String, networkId: String) -> Bool {
        
        let filter = SceneInfo.sceneInfosTable.filter(ExpressionKey.meshUUID == meshUUID && ExpressionKey.subNetworkKey == networkId)
        do {
            try SunSmartDataManager.shared.db?.run(filter.delete())
        } catch {
            print(error)
            return false
        }
        return true
    }
    
    /// 缓存对应场景扩展数据
    /// - Parameters:
    ///   - meshUUID: 所属网络id
    /// - Returns: 是否成功
    @discardableResult func save(meshUUID: String? = nil) -> Bool {
        
        guard let uuid = meshUUID ?? MeshNetworkManager.instance.meshNetwork?.uuid.uuidString else { return false }
        let networkKey = MeshNetworkManager.instance.currentNetworkKey
        let insertOrUpdate = SceneInfo.sceneInfosTable.insert(or: .replace, [
            ExpressionKey.meshUUID <- uuid,
            ExpressionKey.subNetworkKey <- networkKey.networkId.hex,
            ExpressionKey.number <- Int(self.sceneId),
            ExpressionKey.imageId <- self.imageId
        ])
        do {
            try SunSmartDataManager.shared.db?.run(insertOrUpdate)
        } catch {
            print(error)
            return false
        }
        return true
    }
    
}

extension Schedule {
    
    private static let schedulesTable = Table("schedules")
    
    struct ExpressionKey {
        static let id = Expression<Int64>("id")
        static let meshUUID = Expression<String>("meshUUID")
        static let subNetworkKey = Expression<String>("subNetworkKey")
        static let scheduleId = Expression<Int>("scheduleIndex")
        static let name = Expression<String>("name")
        static let enabled = Expression<Bool>("enabled")
        static let selectTarget = Expression<Int>("selectTarget")
        static let action = Expression<Int>("action")
        static let fadeTime = Expression<Int>("fadeTime")
        static let weekDays = Expression<Int>("weekDays")
        static let hour = Expression<Int>("hour")
        static let minute = Expression<Int>("minute")
        static let second = Expression<Int>("second")
        static let deviceAddresses = Expression<Data?>("deviceAddresses")
        static let deviceDeleteAddresses = Expression<Data?>("deviceDeleteAddresses")
        static let groupAddresses = Expression<Data?>("groupAddresses")
        static let groupDeleteAddresses = Expression<Data?>("groupDeleteAddresses")
        static let sceneAddress = Expression<Int?>("sceneAddress")
        static let sceneDeleteAddresses = Expression<Data?>("sceneDeleteAddresses")
    }

    /// 初始化组扩展信息表
    static func initDatabase() {
        
        _ = try? SunSmartDataManager.shared.db?.run(Schedule.schedulesTable.create(temporary: false, ifNotExists: true, withoutRowid: false, block: { builder in
            builder.column(ExpressionKey.id, primaryKey: true)
            builder.column(ExpressionKey.meshUUID)
            builder.column(ExpressionKey.subNetworkKey)
            builder.column(ExpressionKey.scheduleId)
            builder.column(ExpressionKey.name)
            builder.column(ExpressionKey.selectTarget)
            builder.column(ExpressionKey.enabled)
            builder.column(ExpressionKey.action)
            builder.column(ExpressionKey.fadeTime)
            builder.column(ExpressionKey.weekDays)
            builder.column(ExpressionKey.hour)
            builder.column(ExpressionKey.minute)
            builder.column(ExpressionKey.second)
            builder.column(ExpressionKey.deviceAddresses)
            builder.column(ExpressionKey.deviceDeleteAddresses)
            builder.column(ExpressionKey.groupAddresses)
            builder.column(ExpressionKey.groupDeleteAddresses)
            builder.column(ExpressionKey.sceneAddress)
            builder.column(ExpressionKey.sceneDeleteAddresses)
            builder.unique(ExpressionKey.meshUUID, ExpressionKey.subNetworkKey, ExpressionKey.scheduleId)
        }))
    }


    /// 根据mesh uuid获取网络下的所有的日程数据
    /// - Parameter meshUUID: 网络id
    /// - Parameter meshNetworkKey: 对应子网网络key
    /// - Parameter scheduleId: 日程id（传入获取指定日程）
    /// - Returns: 日程数据list
    static func load(meshUUID: String? = nil, meshNetworkId: String, scheduleId: Int? = nil) -> [Schedule] {
        
        guard let uuid = meshUUID ?? MeshNetworkManager.instance.meshNetwork?.uuid.uuidString else { return [] }
        
        var predicate: Expression<Bool> = ExpressionKey.meshUUID == uuid && ExpressionKey.subNetworkKey == meshNetworkId
        if scheduleId != nil {
            predicate = ExpressionKey.meshUUID == uuid && ExpressionKey.subNetworkKey == meshNetworkId && ExpressionKey.scheduleId == scheduleId!
        }
        
        var schedules: [Schedule] = []
        let filter = Schedule.schedulesTable.filter(predicate)
        
        if let rows = try? SunSmartDataManager.shared.db?.prepare(filter) {
            for row in rows {
//                let data = SchedulerRegistryEntry.unmarshal(row[ExpressionKey.scheduleData])
                // 定时内设备地址list
                var nodeAddresses: [Address] = []
                if let deviceAddressesData = row[ExpressionKey.deviceAddresses], let addressesStrings = (try? jsonDecoder.decode([String].self, from: deviceAddressesData)) {
                    addressesStrings.forEach {
                        if let address = UInt16($0, radix: 16), address.isUnicast {
                            nodeAddresses.append(address)
                        }
                    }
                }
                // 定时内待删除设备地址list
                var nodeDeleteAddresses: [Address] = []
                if let deviceDeleteAddressesData = row[ExpressionKey.deviceDeleteAddresses], let addressesStrings = (try? jsonDecoder.decode([String].self, from: deviceDeleteAddressesData)) {
                    addressesStrings.forEach {
                        if let address = UInt16($0, radix: 16), address.isUnicast {
                            nodeDeleteAddresses.append(address)
                        }
                    }
                }
                // 定时内组地址list
                var groupAddresses: [Address] = []
                if let groupAddressesData = row[ExpressionKey.groupAddresses], let addressesStrings = (try? jsonDecoder.decode([String].self, from: groupAddressesData)) {
                    addressesStrings.forEach {
                        if let address = UInt16($0, radix: 16), address.isGroup {
                            groupAddresses.append(address)
                        }
                    }
                }
                // 定时内待删除组地址list
                var groupDeleteAddresses: [Address] = []
                if let groupDeleteAddressesData = row[ExpressionKey.groupDeleteAddresses], let addressesStrings = (try? jsonDecoder.decode([String].self, from: groupDeleteAddressesData)) {
                    addressesStrings.forEach {
                        if let address = UInt16($0, radix: 16), address.isGroup {
                            groupDeleteAddresses.append(address)
                        }
                    }
                }
                // 定时内场景id
                let sceneNumber = row[ExpressionKey.sceneAddress] != nil ? SceneNumber(row[ExpressionKey.sceneAddress]!) : nil
                // 定时内需要删除的场景id list
                var sceneDeleteNumbers: [SceneNumber] = []
                if let sceneDeleteAddressesData = row[ExpressionKey.sceneDeleteAddresses], let addressesStrings = (try? jsonDecoder.decode([String].self, from: sceneDeleteAddressesData)) {
                    addressesStrings.forEach {
                        if let number = UInt16($0, radix: 16), number.isValidSceneNumber {
                            sceneDeleteNumbers.append(number)
                        }
                    }
                }
                
                // 计算选中的重复周期
                let allWeekDays: [WeekDay] = [.Monday, .Tuesday, .Wednesday, .Thursday, .Friday, .Saturday, .Sunday]
                var selectWeekDays: [WeekDay] = []
                for (weekInt, weekDay) in allWeekDays.enumerated() {
                    if row[ExpressionKey.weekDays] >> weekInt & 1 == 1 {
                        selectWeekDays.append(weekDay)
                    }
                }
                
                let schedule = Schedule(id: row[ExpressionKey.scheduleId], name: row[ExpressionKey.name], enabled: row[ExpressionKey.enabled], nodeAddresses: nodeAddresses, groupAddresses: groupAddresses, sceneNumber: sceneNumber, selectTargetType: .init(rawValue: row[ExpressionKey.selectTarget]) ?? .groups, action: .init(rawValue: UInt8(row[ExpressionKey.action])) ?? .noAction, fadeTime: row[ExpressionKey.fadeTime], weekDays: selectWeekDays, hour: row[ExpressionKey.hour], minute: row[ExpressionKey.minute])
                schedule.needDeleteNodeAddresses = nodeDeleteAddresses
                schedule.needDeleteGroupAddresses = groupDeleteAddresses
                schedule.needDeleteSceneNumbers = sceneDeleteNumbers
                schedules.append(schedule)
            }
        }
        
        return schedules
    }
    
    /// 删除网络内所有配置的日程数据
    /// - Parameter meshUUID: 对应网络id
    /// - Parameter meshNetworkKey: 子网网络key
    /// - Returns: 是否成功
    @discardableResult static func deleteAll(meshUUID: String, meshNetworkId: String) -> Bool {
        
        let filter = Schedule.schedulesTable.filter(ExpressionKey.meshUUID == meshUUID && ExpressionKey.subNetworkKey == meshNetworkId)
        do {
            try SunSmartDataManager.shared.db?.run(filter.delete())
        } catch {
            print(error)
            return false
        }
        return true
    }
    
    /// 删除网络内对应配置的日程数据
    /// - Parameters:
    ///   - meshUUID: 所属网络id
    ///   - meshNetworkKey: 子网网络key
    ///   - scheduleId: 日程id
    /// - Returns: 是否成功
    @discardableResult func deleteData(meshUUID: String? = nil, meshNetworkId: String? = nil) -> Bool {
        guard let uuid = meshUUID ?? MeshNetworkManager.instance.meshNetwork?.uuid.uuidString else { return false }
        let subNetworkKey = meshNetworkId ?? MeshNetworkManager.instance.currentNetworkKey.networkId.hex
        
        let filter = Schedule.schedulesTable.filter(ExpressionKey.meshUUID == uuid && ExpressionKey.subNetworkKey == subNetworkKey && ExpressionKey.scheduleId == self.id)
        do {
            try SunSmartDataManager.shared.db?.run(filter.delete())
        } catch {
            print(error)
            return false
        }
        return true
    }
    
    /// 缓存对应场景配置数据
    /// - Parameters:
    ///   - meshUUID: 所属网络id
    ///   - meshNetworkKey: 子网网络key
    ///   - groupAddress: 组地址
    ///   - sceneId: 场景id
    ///   - sceneData: 场景数据
    /// - Returns: 是否成功
    @discardableResult func save(meshUUID: String? = nil, meshNetworkId: String? = nil) -> Bool {
        
        guard let uuid = meshUUID ?? MeshNetworkManager.instance.meshNetwork?.uuid.uuidString else { return false }
        let subNetworkKey = meshNetworkId ?? MeshNetworkManager.instance.currentNetworkKey.networkId.hex
        
        let deviceAddressesData = try? jsonEncoder.encode(self.nodeAddresses.map { String(format: "%04X", $0) })
        let deviceDeleteAddressesData = try? jsonEncoder.encode(self.needDeleteNodeAddresses.map { String(format: "%04X", $0) })
        
        let groupAddressesData = try? jsonEncoder.encode(self.groupAddresses.map { String(format: "%04X", $0) })
        let groupDeleteAddressesData = try? jsonEncoder.encode(self.needDeleteGroupAddresses.map { String(format: "%04X", $0) })
        
        let sceneNumber = self.sceneNumber != nil ? Int(self.sceneNumber!) : nil
        let sceneDeleteNumbersData = try? jsonEncoder.encode(self.needDeleteSceneNumbers.map { String(format: "%04X", $0) })
        
        let weekDays = self.weekDays.reduce(0, { (result, day) -> UInt8 in result + day.rawValue})
        
        let insertOrUpdate = Schedule.schedulesTable.insert(or: .replace, [
            ExpressionKey.meshUUID <- uuid,
            ExpressionKey.subNetworkKey <- subNetworkKey,
            ExpressionKey.scheduleId <- self.id,
            ExpressionKey.name <- self.name,
            ExpressionKey.enabled <- self.enabled,
            ExpressionKey.action <- Int(self.action.rawValue),
            ExpressionKey.fadeTime <- self.fadeTime,
            ExpressionKey.weekDays <- Int(weekDays),
            ExpressionKey.hour <- self.hour,
            ExpressionKey.minute <- self.minute,
            ExpressionKey.second <- 0,
            ExpressionKey.selectTarget <- self.selectTargetType.rawValue,
            ExpressionKey.deviceAddresses <- deviceAddressesData,
            ExpressionKey.deviceDeleteAddresses <- deviceDeleteAddressesData,
            ExpressionKey.groupAddresses <- groupAddressesData,
            ExpressionKey.groupDeleteAddresses <- groupDeleteAddressesData,
            ExpressionKey.sceneAddress <- sceneNumber,
            ExpressionKey.sceneDeleteAddresses <- sceneDeleteNumbersData
        ])
        do {
            try SunSmartDataManager.shared.db?.run(insertOrUpdate)
        } catch {
            print(error)
            return false
        }
        
        return true
    }
    
    /// 获取下一个schedule名称
    /// - Parameter defalutName: 默认名称
    /// - Parameter meshNetworkKey: 子网网络key
    /// - Returns: 日程名称
    static func getNextScheduleName(meshUUID: String? = nil, meshNetworkId: String? = nil, defalutName: String = "schedule_defalut_name".localizedString) -> String {
        
        var result = "\(defalutName)1"
        
        guard let uuid = meshUUID ?? MeshNetworkManager.instance.meshNetwork?.uuid.uuidString else { return result }
        let subNetworkey = meshNetworkId ?? MeshNetworkManager.instance.currentNetworkKey.networkId.hex
        
        // 日程已使用的名称索引
        var scheduleIndexs: [Int] = []
        let sql = Schedule.schedulesTable.filter(ExpressionKey.meshUUID == uuid && ExpressionKey.subNetworkKey == subNetworkey && ExpressionKey.name.like(defalutName + "%"))
        if let rows = try? SunSmartDataManager.shared.db?.prepare(sql) {
            for row in rows {
                let spaceName = row[ExpressionKey.name]
                if let index = Int(spaceName.replacingOccurrences(of: defalutName, with: "")) {
                    scheduleIndexs.append(index)
                }
            }
        }
        
        // 获取未被使用的schedule索引
        for index in 1...16 {
            if !scheduleIndexs.contains(index) {
                result = defalutName + "\(index)"
                break
            }
        }
        return result
    }
    
    /// 判断日程名称是否重名
    /// - Parameter ScheduleName: 日程名称
    /// - Parameter meshUUID: 所在网络
    /// - Parameter meshNetworkKey: 子网网络key
    /// - Returns: 是否重名
    static func isTautonym(scheduleName: String, meshUUID: String? = nil, meshNetworkId: String? = nil) -> Bool {
        guard let uuid = meshUUID ?? MeshNetworkManager.instance.meshNetwork?.uuid.uuidString else { return false }
        let subNetworkKey = meshNetworkId ?? MeshNetworkManager.instance.currentNetworkKey.networkId.hex
        
        let filter = Schedule.schedulesTable.filter(ExpressionKey.meshUUID == uuid && ExpressionKey.subNetworkKey == subNetworkKey && ExpressionKey.name == scheduleName)
        let reuslt = try? SunSmartDataManager.shared.db?.prepareRowIterator(filter).next()
        if reuslt != nil {
            return true
        }
        return false
    }
    
}


extension Profile {
    
    private static let profilesTable = Table("profiles")
    
    struct ExpressionKey {
        static let id = Expression<Int64>("id")
        static let uuid = Expression<String>("uuid")
        static let meshUUID = Expression<String>("meshUUID")
        static let subNetworkKey = Expression<String?>("subNetworkKey")
        static let name = Expression<String>("name")
        static let type = Expression<Int>("type")
        static let highEndTrim = Expression<Int>("highEndTrim")
        static let lowEndTrim = Expression<Int>("lowEndTrim")
        static let occupancyLevel = Expression<Int>("occupancyLevel")
        static let vacantLevel = Expression<Int>("vacantLevel")
        static let taskLevel = Expression<Int>("taskLevel")
        static let autoMinLevel = Expression<Int>("autoMinLevel")
        static let timeT1 = Expression<Int>("timeT1")
        static let timeT2 = Expression<Int>("timeT2")
        static let timeT3 = Expression<Int>("timeT3")
        static let timeT4 = Expression<Int>("timeT4")
        static let timeT5 = Expression<Int>("timeT5")
        static let manualOverrideTimeout = Expression<Int64>("manualOverrideTimeout")
        static let powerUpState = Expression<Int>("powerUpState")
        static let adjustSpeed = Expression<Int>("adjustSpeed")
    }
    
    /// 初始化组扩展信息表
    static func initDatabase() {
        
        _ = try? SunSmartDataManager.shared.db?.run(Profile.profilesTable.create(temporary: false, ifNotExists: true, withoutRowid: false, block: { builder in
            builder.column(ExpressionKey.id, primaryKey: true)
            builder.column(ExpressionKey.meshUUID)
            builder.column(ExpressionKey.subNetworkKey)
            builder.column(ExpressionKey.uuid)
            builder.column(ExpressionKey.name)
            builder.column(ExpressionKey.type)
            builder.column(ExpressionKey.highEndTrim)
            builder.column(ExpressionKey.lowEndTrim)
            builder.column(ExpressionKey.occupancyLevel)
            builder.column(ExpressionKey.vacantLevel)
            builder.column(ExpressionKey.taskLevel)
            builder.column(ExpressionKey.autoMinLevel)
            builder.column(ExpressionKey.timeT1)
            builder.column(ExpressionKey.timeT2)
            builder.column(ExpressionKey.timeT3)
            builder.column(ExpressionKey.timeT4)
            builder.column(ExpressionKey.timeT5)
            builder.column(ExpressionKey.manualOverrideTimeout)
            builder.column(ExpressionKey.powerUpState)
            builder.column(ExpressionKey.adjustSpeed)
            builder.unique(ExpressionKey.meshUUID, ExpressionKey.uuid)
        }))
    }

    /// 根据网络id获取网络下的所有的配置数据
    /// - Parameter meshUUID: 网络id
    /// - Parameter networkKey: 子网网络key
    /// - Returns: 日程数据list
    static func loadAll(meshUUID: String, meshNetworkId: String? = nil, profileId: String? = nil) -> [Profile] {
       
        var predicate = ExpressionKey.meshUUID == meshUUID && ExpressionKey.subNetworkKey == meshNetworkId
        if profileId != nil {
            predicate = ExpressionKey.meshUUID == meshUUID && ExpressionKey.subNetworkKey == meshNetworkId && ExpressionKey.uuid == profileId!
        }
        let filter = Profile.profilesTable.filter(predicate)
        
        var profiles: [Profile] = []
        if let rows = try? SunSmartDataManager.shared.db?.prepare(filter) {
            for row in rows {
                let profileType: ProfileType = .init(rawValue: row[ExpressionKey.type]) ?? .occupancy_daylight
                let lightData = LightData(profileType: profileType, highEndTrim: row[ExpressionKey.highEndTrim], lowEndTrim: row[ExpressionKey.lowEndTrim], occupancyLevel: row[ExpressionKey.occupancyLevel], vacantLevel: row[ExpressionKey.vacantLevel], taskLevel: row[ExpressionKey.taskLevel], autoMinLevel: row[ExpressionKey.autoMinLevel], t1: row[ExpressionKey.timeT1], t2: row[ExpressionKey.timeT2], t3: row[ExpressionKey.timeT3], t4: row[ExpressionKey.timeT4], t5: row[ExpressionKey.timeT5])
                
                let powerUpState: PowerUpState = .init(rawValue: UInt8(row[ExpressionKey.powerUpState]))
                let manualOverrideTimeout = UInt32(row[ExpressionKey.manualOverrideTimeout])
                let profile = Profile(name: row[ExpressionKey.name], id: row[ExpressionKey.uuid], type: profileType, lightData: lightData, powerUpState: powerUpState, manualOverrideTimeout: manualOverrideTimeout, adjustSpeed: row[ExpressionKey.adjustSpeed])
                profiles.append(profile)
            }
        }
        return profiles
    }
    
    /// 根据网络id获取网络下的所有的配置数据
    /// - Parameter meshUUID: 网络id
    /// - Parameter networkKey: 子网网络key
    /// - Parameter profileId: 配置id
    /// - Returns: 配置数据
    static func load(meshUUID: String, meshNetworkId: String? = nil, profileId: String) -> Profile? {
        
        return loadAll(meshUUID: meshUUID, meshNetworkId: meshNetworkId, profileId: profileId).first
    }
    
    /// 缓存配置数据
    /// - Parameters:
    ///   - meshUUID: 网络id
    ///   - networkKey: 子网网络key
    /// - Returns: 是否成功
    @discardableResult func save(meshUUID: String? = nil, meshNetworkId: String? = nil) -> Bool {
        
        guard let uuid = meshUUID ?? MeshNetworkManager.instance.meshNetwork?.uuid.uuidString else { return false }
//        let subNetworkey = networkKey
        
        let data = lightData.data
        let insertOrUpdate = Profile.profilesTable.insert(or: .replace, [
            ExpressionKey.meshUUID <- uuid,
            ExpressionKey.subNetworkKey <- meshNetworkId,
            ExpressionKey.uuid <- self.id,
            ExpressionKey.name <- self.name,
            ExpressionKey.type <- self.type.rawValue,
            ExpressionKey.highEndTrim <- data.highEndTrim,
            ExpressionKey.lowEndTrim <- data.lowEndTrim,
            ExpressionKey.occupancyLevel <- data.occupancyLevel,
            ExpressionKey.vacantLevel <- data.vacantLevel,
            ExpressionKey.taskLevel <- data.taskLevel,
            ExpressionKey.autoMinLevel <- data.autoMinLevelEnabled ? data.autoMinLevel : 255,
            ExpressionKey.timeT1 <- data.t1,
            ExpressionKey.timeT2 <- data.t2,
            ExpressionKey.timeT3 <- data.t3,
            ExpressionKey.timeT4 <- data.t4,
            ExpressionKey.timeT5 <- data.t5,
            ExpressionKey.manualOverrideTimeout <- Int64(self.manualOverrideTimeout),
            ExpressionKey.powerUpState <- Int(self.powerUpState.rawValue),
            ExpressionKey.adjustSpeed <- self.adjustSpeed
        ])
        do {
            try SunSmartDataManager.shared.db?.run(insertOrUpdate)
        } catch {
            print(error)
            return false
        }
        
        return true
    }
    
    /// 删除网络全部日程数据
    /// - Parameter spaceId: 空间id
    /// - Parameter networkKey: 子网网络key
    /// - Returns: 是否成功
    @discardableResult static func deleteProfiles(meshUUID: String, meshNetworkId: String) -> Bool {
        
        let filter = Profile.profilesTable.filter(ExpressionKey.meshUUID == meshUUID && ExpressionKey.subNetworkKey == meshNetworkId)
        do {
            try SunSmartDataManager.shared.db?.run(filter.delete())
        } catch {
            print(error)
            return false
        }
        return true
    }
    
    /// 删除日程数据
    /// - Parameter meshUUID: mesh网络id
    /// - Parameter networkKey: 子网网络key
    /// - Returns: 是否成功
    @discardableResult func delete(meshUUID: String? = nil, meshNetworkId: String? = nil) -> Bool {
        
        guard let uuid = meshUUID ?? MeshNetworkManager.instance.meshNetwork?.uuid.uuidString else { return false }
        let subNetworkey = meshNetworkId ?? MeshNetworkManager.instance.currentNetworkKey.networkId.hex
        
        let filter = Profile.profilesTable.filter(ExpressionKey.meshUUID == uuid && ExpressionKey.subNetworkKey == subNetworkey && ExpressionKey.uuid == self.id)
        do {
            try SunSmartDataManager.shared.db?.run(filter.delete())
        } catch {
            print(error)
            return false
        }
        return true
    }
    
}

extension GroupSwitch {
    
    private static let switchsTable = Table("switchs")
    
    struct ExpressionKey {
        static let id = Expression<Int64>("id")
        static let meshUUID = Expression<String>("meshUUID")
        static let subNetworkKey = Expression<String>("subNetworkKey")
        static let switchId = Expression<String>("switchId")
        static let name = Expression<String>("name")
        static let enabled = Expression<Bool>("enabled")
        static let panelType = Expression<Int>("panelType")
        static let groupAddress = Expression<Int>("groupAddress")
        static let sceneA = Expression<Int?>("sceneA")
        static let sceneB = Expression<Int?>("sceneB")
        static let proxyAddresses = Expression<Data?>("proxyAddresses")
        static let enOceanMacAddress = Expression<String?>("enOceanMacAddress")
    }
    
    /// 初始化组扩展信息表
    static func initDatabase() {
        
        _ = try? SunSmartDataManager.shared.db?.run(GroupSwitch.switchsTable.create(temporary: false, ifNotExists: true, withoutRowid: false, block: { builder in
            builder.column(ExpressionKey.id, primaryKey: true)
            builder.column(ExpressionKey.meshUUID)
            builder.column(ExpressionKey.subNetworkKey)
            builder.column(ExpressionKey.switchId)
            builder.column(ExpressionKey.name)
            builder.column(ExpressionKey.enabled)
            builder.column(ExpressionKey.panelType)
            builder.column(ExpressionKey.groupAddress)
            builder.column(ExpressionKey.sceneA)
            builder.column(ExpressionKey.sceneB)
            builder.column(ExpressionKey.proxyAddresses)
            builder.column(ExpressionKey.enOceanMacAddress)
            builder.unique(ExpressionKey.meshUUID, ExpressionKey.subNetworkKey, ExpressionKey.groupAddress, ExpressionKey.switchId)
        }))
    }

    /// 根据网络id、组地址获取组下的所有的虚拟按键数据
    /// - Parameter meshUUID: 网络id
    /// - Parameter networkKey: 子网网络key
    /// - Parameter groupAddress: 组地址
    /// - Parameter id: 按键id（传入获取指定按键）
    /// - Returns: 虚拟按键数据list
    static func load(meshUUID: String? = nil, meshNetworkId: String? = nil, groupAddress: Address, id: String? = nil) -> [GroupSwitch] {
        
        guard let uuid = meshUUID ?? MeshNetworkManager.instance.meshNetwork?.uuid.uuidString else { return [] }
        let subNetworkKey = meshNetworkId ?? MeshNetworkManager.instance.currentNetworkKey.networkId.hex
        
        var predicate = ExpressionKey.meshUUID == uuid && ExpressionKey.subNetworkKey == subNetworkKey && ExpressionKey.groupAddress == Int(groupAddress)
        if let switchId = id {
            predicate = ExpressionKey.meshUUID == uuid && ExpressionKey.subNetworkKey == subNetworkKey && ExpressionKey.groupAddress == Int(groupAddress) && ExpressionKey.switchId == switchId
        }
        let filter = GroupSwitch.switchsTable.filter(predicate)
        
        var switchs: [GroupSwitch] = []
        if let rows = try? SunSmartDataManager.shared.db?.prepare(filter) {
            for row in rows {
                if let group = MeshNetworkManager.instance.groups.first(where: { $0.address.address == row[ExpressionKey.groupAddress] }) {
                    let groupSwitch = GroupSwitch(id: row[ExpressionKey.switchId], group: group, enabled: row[ExpressionKey.enabled], name: row[ExpressionKey.name])
                    let panelType: PanelType = .init(rawValue: UInt8(row[ExpressionKey.panelType])) ?? .default
                    groupSwitch.panelType = panelType
                    if let number = row[ExpressionKey.sceneA], let sceneA = MeshNetworkManager.instance.scenes.first(where: { $0.number == number }) {
                        groupSwitch.sceneA = sceneA
                    }
                    if let number = row[ExpressionKey.sceneB], let sceneB = MeshNetworkManager.instance.scenes.first(where: { $0.number == number }) {
                        groupSwitch.sceneB = sceneB
                    }
                    
                    if let addressesData = row[ExpressionKey.proxyAddresses], let addressesStrings = (try? jsonDecoder.decode([String].self, from: addressesData)) {
                        // 动能开关代理地址list
                        var proxyAddresses: [Address] = []
                        addressesStrings.forEach {
                            if let address = UInt16($0, radix: 16), address.isUnicast {
                                proxyAddresses.append(address)
                            }
                        }
                        if let address = proxyAddresses.first, let proxyNode = MeshNetworkManager.instance.meshNetwork?.node(withAddress: Address(address)) {
                            groupSwitch.proxyNode = proxyNode
                        }
                    }
                    switchs.append(groupSwitch)
                }
            }
        }
        return switchs
    }
    
    /// 根据网络id+动能开关mac获取对应虚拟按键数据
    /// - Parameter meshUUID: 网络id
    /// - Parameter networkKey: 子网网络key
    /// - Parameter enOceanMacAddress: 动能开关按键mac
    /// - Returns: 按键数据
    static func load(meshUUID: String? = nil, networkId: String? = nil, enOceanMacAddress: String) -> GroupSwitch? {
        
        guard let uuid = meshUUID ?? MeshNetworkManager.instance.meshNetwork?.uuid.uuidString else { return nil }
        let subNetworkKey = networkId ?? MeshNetworkManager.instance.currentNetworkKey.networkId.hex
        
        let predicate = ExpressionKey.meshUUID == uuid && ExpressionKey.subNetworkKey == subNetworkKey && ExpressionKey.enOceanMacAddress == enOceanMacAddress
        
        let filter = GroupSwitch.switchsTable.filter(predicate)
        
        var resultSwitch: GroupSwitch?
        if let rows = try? SunSmartDataManager.shared.db?.prepare(filter) {
            for row in rows {
                if let group = MeshNetworkManager.instance.groups.first(where: { $0.address.address == row[ExpressionKey.groupAddress] }) {
                    let groupSwitch = GroupSwitch(id: row[ExpressionKey.switchId], group: group, enabled: row[ExpressionKey.enabled], name: row[ExpressionKey.name])
                    let panelType: PanelType = .init(rawValue: UInt8(row[ExpressionKey.panelType])) ?? .default
                    groupSwitch.panelType = panelType
                    if let number = row[ExpressionKey.sceneA], let sceneA = MeshNetworkManager.instance.scenes.first(where: { $0.number == number }) {
                        groupSwitch.sceneA = sceneA
                    }
                    if let number = row[ExpressionKey.sceneB], let sceneB = MeshNetworkManager.instance.scenes.first(where: { $0.number == number }) {
                        groupSwitch.sceneB = sceneB
                    }
                    
                    if let addressesData = row[ExpressionKey.proxyAddresses], let addressesStrings = (try? jsonDecoder.decode([String].self, from: addressesData)) {
                        // 动能开关代理地址list
                        var proxyAddresses: [Address] = []
                        addressesStrings.forEach {
                            if let address = UInt16($0, radix: 16), address.isUnicast {
                                proxyAddresses.append(address)
                            }
                        }
                        if let address = proxyAddresses.first, let proxyNode = MeshNetworkManager.instance.meshNetwork?.node(withAddress: Address(address)) {
                            groupSwitch.proxyNode = proxyNode
                        }
                    }
                    resultSwitch = groupSwitch
                    break
                }
            }
        }
        return resultSwitch
    }
    
    
    /// 缓存虚拟按键数据
    /// - Parameters:
    ///   - meshUUID: 网络id
    ///   - networkKey: 子网网络key
    /// - Returns: 是否成功
    @discardableResult func save(meshUUID: String? = nil, networkId: String? = nil) -> Bool {
        
        guard let uuid = meshUUID ?? MeshNetworkManager.instance.meshNetwork?.uuid.uuidString else { return false }
        let subNetworkey = networkId ?? MeshNetworkManager.instance.currentNetworkKey.networkId.hex
        
        var proxyAddressesData: Data?
        if let proxyAddress = self.proxyNode?.primaryUnicastAddress {
            proxyAddressesData = try? jsonEncoder.encode([String(format: "%04X", proxyAddress)])
        }
        
        let insertOrUpdate = GroupSwitch.switchsTable.insert(or: .replace, [
            ExpressionKey.meshUUID <- uuid,
            ExpressionKey.subNetworkKey <- subNetworkey,
            ExpressionKey.switchId <- self.id,
            ExpressionKey.name <- self.name,
            ExpressionKey.enabled <- self.enabled,
            ExpressionKey.panelType <- Int(self.panelType.rawValue),
            ExpressionKey.groupAddress <- Int(self.group.address.address),
            ExpressionKey.sceneA <- self.sceneA != nil ? Int(self.sceneA!.number) : nil,
            ExpressionKey.sceneB <- self.sceneB != nil ? Int(self.sceneB!.number) : nil,
            ExpressionKey.proxyAddresses <- proxyAddressesData,
            ExpressionKey.enOceanMacAddress <- self.enOceanMacAddress,
        ])
        do {
            try SunSmartDataManager.shared.db?.run(insertOrUpdate)
        } catch {
            print(error)
            return false
        }
        return true
    }
    
    /// 删除网络内全部虚拟按键数据
    /// - Parameter spaceId: 空间id
    /// - Parameter networkKey: 子网网络key
    /// - Returns: 是否成功
    @discardableResult static func deleteSwitchs(meshUUID: String, networkId: String, groupAddress: Address? = nil) -> Bool {
        
        // 指定子网下所有虚拟按键
        var predicate = ExpressionKey.meshUUID == meshUUID && ExpressionKey.subNetworkKey == networkId
        if let address = groupAddress {
            // 指定组下所有虚拟按键
            predicate =  ExpressionKey.meshUUID == meshUUID && ExpressionKey.subNetworkKey == networkId && ExpressionKey.groupAddress == Int(address)
        }
        
        let filter = GroupSwitch.switchsTable.filter(predicate)
        do {
            try SunSmartDataManager.shared.db?.run(filter.delete())
        } catch {
            print(error)
            return false
        }
        return true
    }
    
    @discardableResult func delete(meshUUID: String, networkId: String) -> Bool {
        
        // 指定虚拟按键
        let predicate = ExpressionKey.meshUUID == meshUUID && ExpressionKey.subNetworkKey == networkId && ExpressionKey.groupAddress == Int(group.address.address) && ExpressionKey.switchId == self.id

        let filter = GroupSwitch.switchsTable.filter(predicate)
        do {
            try SunSmartDataManager.shared.db?.run(filter.delete())
        } catch {
            print(error)
            return false
        }
        return true
    }
    
}
