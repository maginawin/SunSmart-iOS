//
//  Database.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/8/24.
//

import Foundation
import NordicSigMeshSDK
import SQLite
import struct SQLite.Expression

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
        // 1. 创建用户专属目录
        let userDir = docPath + "/\(UserData.currentUserId)"
        // 确保目录存在
        try? FileManager.default.createDirectory(
            atPath: userDir,
            withIntermediateDirectories: true,
            attributes: nil
        )
        
        db = try? Connection("\(userDir)/sunsmart.sqlite3")
        db?.busyTimeout = 1.5
    }
    
    public func initDatabase() {
        SiteData.initDatabase()
        
        FirmwareData.initDatabase()
        // 初始化网络数据库
        MeshDataManager.customDatabasePath = "\(docPath)/\(UserData.currentUserId)/mesh.sqlite3"
        MeshDataManager.shared.initDatabase()
        
        // 初始化设备配置信息数据库
        MeshDeviceConfigInfo.initDatabase()
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
        static let permission = Expression<Int>("permission")
        static let source = Expression<Int>("source")
        static let favourite = Expression<Bool>("favourite")
        static let createTimestamp = Expression<Int64>("createTimestamp")
        static let lastUpdateTimestamp = Expression<Int64>("lastUpdateTimestamp")
        static let lastUploadCloudTimestamp = Expression<Int64?>("lastUploadCloudTimestamp")
        static let regionType = Expression<Int>("regionType")
        static let syncCloudError = Expression<Int?>("syncCloudError")
        static let state = Expression<Int>("state")
        static let spaceCount = Expression<Int?>("spaceCount")
        static let transferCode = Expression<String?>("transferCode")
        static let transferPassword = Expression<String?>("transferPassword")
        static let localAddress = Expression<Int?>("localAddress")
        static let recycleAddressData = Expression<Data?>("recycleAddressData")
    }
    
    /// 初始化场所表
    static func initDatabase() {
        
        _ = try? SunSmartDataManager.shared.db?.run(SiteData.sitesTable.create(temporary: false, ifNotExists: true, withoutRowid: false, block: { builder in
            builder.column(ExpressionKey.id, primaryKey: true)
            builder.column(ExpressionKey.uuid, unique: true)
            builder.column(ExpressionKey.name)
            builder.column(ExpressionKey.imageId)
            builder.column(ExpressionKey.type)
            builder.column(ExpressionKey.permission)
            builder.column(ExpressionKey.source)
            builder.column(ExpressionKey.favourite)
            builder.column(ExpressionKey.createTimestamp)
            builder.column(ExpressionKey.lastUpdateTimestamp)
            builder.column(ExpressionKey.lastUploadCloudTimestamp)
            builder.column(ExpressionKey.regionType)
            builder.column(ExpressionKey.syncCloudError)
            builder.column(ExpressionKey.state)
            builder.column(ExpressionKey.spaceCount)
            builder.column(ExpressionKey.transferCode)
            builder.column(ExpressionKey.transferPassword)
            builder.column(ExpressionKey.localAddress)
            builder.column(ExpressionKey.recycleAddressData)
        }))
        
//        _ = try? SunSmartDataManager.shared.db?.run(SiteData.sitesTable.addColumn(ExpressionKey.localAddress))
        
        SpaceData.initDatabase()
    }
    
    /// 获取所有的场所
    /// - Returns: mesh网络list
    static func loadAll() -> [SiteData] {
        
        var sites: [SiteData] = []
        
        let filter = SiteData.sitesTable.filter(ExpressionKey.regionType == UserData.currentServerRegion.rawValue)
        
        if let rows = try? SunSmartDataManager.shared.db?.prepare(filter.order(ExpressionKey.createTimestamp.asc)) {
            for row in rows {
                let site = SiteData(region: ServerRegion(rawValue: row[ExpressionKey.regionType]) ?? UserData.currentServerRegion,id: row[ExpressionKey.uuid], meshUUID: row[ExpressionKey.uuid], name: row[ExpressionKey.name], imageId: row[ExpressionKey.imageId], type: .init(rawValue: row[ExpressionKey.type]) ?? .office, permission: .init(rawValue: row[ExpressionKey.permission]) ?? .owner, create: row[ExpressionKey.createTimestamp], lastUpdate: row[ExpressionKey.lastUpdateTimestamp], isFavourite: row[ExpressionKey.favourite], sourceType: .init(rawValue: row[ExpressionKey.source]) ?? .create)
                site.lastUploadCloudTimestamp = row[ExpressionKey.lastUploadCloudTimestamp]
                if let errorCode = row[ExpressionKey.syncCloudError] {
                    site.syncCloudError = .init(code: errorCode)
                }
                site.state = .init(rawValue: row[ExpressionKey.state]) ?? .normal
                site.spaceCount = row[ExpressionKey.spaceCount]
                site.transferCode = row[ExpressionKey.transferCode]
                site.transferPassword = row[ExpressionKey.transferPassword]
                // 手机正在使用的地址
                if let address = row[ExpressionKey.localAddress] {
                    site.localAddress = Address(address)
                }
                // site未回收的地址
                if let data = row[ExpressionKey.recycleAddressData], let recycleAddressData = try? jsonDecoder.decode(RecycleAddressData.self, from: data) {
                    site.recycleAddressData = recycleAddressData
                }
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
        
        let filter = SiteData.sitesTable.filter(ExpressionKey.uuid == siteId && ExpressionKey.regionType == UserData.currentServerRegion.rawValue)
        
        var site: SiteData?
        if let rows = try? SunSmartDataManager.shared.db?.prepare(filter) {
            for row in rows {
                site = SiteData(region: ServerRegion(rawValue: row[ExpressionKey.regionType]) ?? UserData.currentServerRegion, id: row[ExpressionKey.uuid], meshUUID: row[ExpressionKey.uuid], name: row[ExpressionKey.name], imageId: row[ExpressionKey.imageId], type: .init(rawValue: row[ExpressionKey.type]) ?? .office, permission: .init(rawValue: row[ExpressionKey.permission]) ?? .owner, create: row[ExpressionKey.createTimestamp], lastUpdate: row[ExpressionKey.lastUpdateTimestamp], isFavourite: row[ExpressionKey.favourite], sourceType: .init(rawValue: row[ExpressionKey.source]) ?? .create)
                site?.lastUploadCloudTimestamp = row[ExpressionKey.lastUploadCloudTimestamp]
                if let errorCode = row[ExpressionKey.syncCloudError] {
                    site?.syncCloudError = .init(code: errorCode)
                }
                site?.state = .init(rawValue: row[ExpressionKey.state]) ?? .normal
                site?.spaceCount = row[ExpressionKey.spaceCount]
                site?.transferCode = row[ExpressionKey.transferCode]
                site?.transferPassword = row[ExpressionKey.transferPassword]
                // 手机正在使用的地址
                if let address = row[ExpressionKey.localAddress] {
                    site?.localAddress = Address(address)
                }
                // site未回收的地址
                if let data = row[ExpressionKey.recycleAddressData], let recycleAddressData = try? jsonDecoder.decode(RecycleAddressData.self, from: data) {
                    site?.recycleAddressData = recycleAddressData
                }
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
    /// - Parameter defaultName: 查询的site默认名称  ”Site “
    /// - Returns: 默认的site名称
    static func getNextSiteName(_ defaultName: String = "site_defalut_name".localizedString) -> String {
        
        var result = "\(defaultName)1"
        // 场所已使用的名称索引
        var siteIndexs: [Int] = []
        let sql = SiteData.sitesTable.filter(ExpressionKey.regionType == UserData.currentServerRegion.rawValue && ExpressionKey.name.like(defaultName + "%"))
        if let rows = try? SunSmartDataManager.shared.db?.prepare(sql) {
            for row in rows {
                let siteName = row[ExpressionKey.name]
                if let index = Int(siteName.replacingOccurrences(of: defaultName, with: "")) {
                    siteIndexs.append(index)
                }
            }
        }
        // 获取未被使用的site索引
        for index in 1...1000 {
            if !siteIndexs.contains(index) {
                result = defaultName + "\(index)"
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
        let time = Int64(Date().timeIntervalSince1970)
        site.create = time
        site.lastUpdate = time
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
        
        let sql = SiteData.sitesTable.filter(ExpressionKey.regionType == UserData.currentServerRegion.rawValue && ExpressionKey.name.like(matching + "%"))
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
        
        let filter = SiteData.sitesTable.filter(ExpressionKey.regionType == UserData.currentServerRegion.rawValue && ExpressionKey.name == siteName)
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
        var recycleAddressData: Data?
        if self.recycleAddressData != nil {
            recycleAddressData = try? jsonEncoder.encode(self.recycleAddressData!)
        }
        
        let insetOrUpdate = table.insert(or: .replace, [
            ExpressionKey.uuid <- self.id,
            ExpressionKey.name <- self.name,
            ExpressionKey.imageId <- self.imageId,
            ExpressionKey.type <- self.type.rawValue,
            ExpressionKey.permission <- self.permission.rawValue,
            ExpressionKey.source <- self.sourceType.rawValue,
            ExpressionKey.favourite <- self.isFavourite,
            ExpressionKey.createTimestamp <- self.create,
            ExpressionKey.lastUpdateTimestamp <- self.lastUpdate,
            ExpressionKey.lastUploadCloudTimestamp <- self.lastUploadCloudTimestamp,
            ExpressionKey.regionType <- self.region.rawValue,
            ExpressionKey.syncCloudError <- self.syncCloudError?.code,
            ExpressionKey.state <- self.state.rawValue,
            ExpressionKey.spaceCount <- self.spaceCount,
            ExpressionKey.transferCode <- self.transferCode,
            ExpressionKey.transferPassword <- self.transferPassword,
            ExpressionKey.localAddress <- self.localAddress != nil ? Int(self.localAddress!) : nil,
            ExpressionKey.recycleAddressData <- recycleAddressData
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
    
    private static let spacesTableName = "spaces"
    private static let spacesTable = Table(spacesTableName)
    
    struct ExpressionKey {
        static let id = Expression<Int64>("id")
        static let uuid = Expression<String>("uuid")
        static let siteUUID = Expression<String>("siteUUID")
        static let subNetworkKey = Expression<String>("subNetworkKey")
        static let name = Expression<String>("name")
        static let imageId = Expression<Int>("imageId")
        static let permission = Expression<Int>("permission")
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
        static let lastUploadCloudTimestamp = Expression<Int64?>("lastUploadCloudTimestamp")
        static let syncCloudError = Expression<Int?>("syncCloudError")
        static let state = Expression<Int>("state")
        static let editorPassword = Expression<String?>("editorPassword")
        static let vistorPassword = Expression<String?>("vistorPassword")
        static let authorizationPassword = Expression<String?>("authorizationPassword")
        static let requiresPasswordVerification = Expression<Bool>("requiresPasswordVerification")
        static let vistorPasswordEnable = Expression<Bool>("vistorPasswordEnable")
        static let shareCode = Expression<String?>("shareCode")
        static let applyDeviceAddressCount = Expression<Int?>("applyDeviceAddressCount")
        static let applyGroupAddressCount = Expression<Int?>("applyGroupAddressCount")
        static let isReleaseAddress = Expression<Bool?>("isReleaseAddress")
        static let editor = Expression<Data?>("editor")
        static let vistors = Expression<Data?>("vistors")
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
            builder.column(ExpressionKey.permission)
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
            builder.column(ExpressionKey.lastUploadCloudTimestamp)
            builder.column(ExpressionKey.syncCloudError)
            builder.column(ExpressionKey.state)
            builder.column(ExpressionKey.editorPassword)
            builder.column(ExpressionKey.vistorPassword)
            builder.column(ExpressionKey.authorizationPassword)
            builder.column(ExpressionKey.requiresPasswordVerification)
            builder.column(ExpressionKey.vistorPasswordEnable)
            builder.column(ExpressionKey.shareCode)
            builder.column(ExpressionKey.applyDeviceAddressCount)
            builder.column(ExpressionKey.applyGroupAddressCount)
            builder.column(ExpressionKey.isReleaseAddress)
            builder.column(ExpressionKey.editor)
            builder.column(ExpressionKey.vistors)
        }))
        
        // 获取表内存在的属性
        if let columns = try? SunSmartDataManager.shared.db?.schema.columnDefinitions(table: spacesTableName) {
            // 插入字段
            // 是否存在”applyGroupAddressCount“属性
            if !columns.contains(where: { $0.name == "applyGroupAddressCount" }) {
                _ = try? SunSmartDataManager.shared.db?.run(SpaceData.spacesTable.addColumn(ExpressionKey.applyGroupAddressCount))
            }
            
            // 是否存在”editor“属性
            if !columns.contains(where: { $0.name == "editor" }) {
                _ = try? SunSmartDataManager.shared.db?.run(SpaceData.spacesTable.addColumn(ExpressionKey.editor))
            }
            // 是否存在”vistors“属性
            if !columns.contains(where: { $0.name == "vistors" }) {
                _ = try? SunSmartDataManager.shared.db?.run(SpaceData.spacesTable.addColumn(ExpressionKey.vistors))
            }
        }
        
        GroupInfo.initDatabase()
        Profile.initDatabase()
        SceneInfo.initDatabase()
        Schedule.initDatabase()
//        GroupSwitch.initDatabase()
        DeviceSwitchData.initDatabase()
        MeshDistributionData.initDatabase()
        DeviceDongleData.initDatabase()
        EnergyStatisticsStaticData.initDatabase()
        GatewayModel.initDatabase()
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
                let space = SpaceData(name: row[ExpressionKey.name], id: row[ExpressionKey.uuid], siteId: row[ExpressionKey.siteUUID], imageId: row[ExpressionKey.imageId], create: row[ExpressionKey.createTimestamp], lastUpdate: row[ExpressionKey.lastUpdateTimestamp], isFavourite: row[ExpressionKey.favourite], permission: .init(rawValue: row[ExpressionKey.permission]) ?? .owner, sourceType: .init(rawValue: row[ExpressionKey.source]) ?? .create, meshUUID: row[ExpressionKey.siteUUID], meshNetworkId: row[ExpressionKey.subNetworkKey])
                space.deviceCount = row[ExpressionKey.deviceNumber]
                space.luminairesCount = row[ExpressionKey.luminaireNumber]
                space.groupCount = row[ExpressionKey.groupNumber]
                space.sceneCount = row[ExpressionKey.sceneNumber]
                space.scheheduleCount = row[ExpressionKey.scheduleNumber]
                space.switchesCount = row[ExpressionKey.switchesNumber]
                space.lastUploadCloudTimestamp = row[ExpressionKey.lastUploadCloudTimestamp]
                if let errorCode = row[ExpressionKey.syncCloudError] {
                    space.syncCloudError = .init(code: errorCode)
                }
                space.state = .init(rawValue: row[ExpressionKey.state]) ?? .normal
                space.editorPassword = row[ExpressionKey.editorPassword]
                space.vistorPassword = row[ExpressionKey.vistorPassword]
                space.authorizationPassword = row[ExpressionKey.authorizationPassword]
                space.requiresPasswordVerification = row[ExpressionKey.requiresPasswordVerification]
                space.vistorPasswordEnable = row[ExpressionKey.vistorPasswordEnable]
                space.shareCode = row[ExpressionKey.shareCode]
                space.applyDeviceAddressCount = row[ExpressionKey.applyDeviceAddressCount]
                space.applyGroupAddressCount = row[ExpressionKey.applyGroupAddressCount]
                space.releaseAddress = row[ExpressionKey.isReleaseAddress] ?? false
                
                if let editorData = row[ExpressionKey.editor] {
                    space.editor = try? jsonDecoder.decode(UserData.self, from: editorData)
                }
                if let vistorsData = row[ExpressionKey.vistors] {
                    space.visitors = (try? jsonDecoder.decode([UserData].self, from: vistorsData)) ?? []
                }
//                space.editor = UserData.load(spaceId: space.id, permisson: .editor).first
//                space.visitors = UserData.load(spaceId: space.id, permisson: .visitor)
                
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

        var editorData: Data?
        if self.editor != nil {
            editorData = try? jsonEncoder.encode(self.editor!)
        }
        
        var vistorsData: Data?
        if self.visitors.count > 0 {
            vistorsData = try? jsonEncoder.encode(self.visitors)
        }
        
        let interOrUpdate = SpaceData.spacesTable.insert(or: .replace, [
            ExpressionKey.uuid <- self.id,
            ExpressionKey.siteUUID <- self.siteId,
            ExpressionKey.subNetworkKey <- self.meshNetworkId,
            ExpressionKey.name <- self.name,
            ExpressionKey.imageId <- self.imageId,
            ExpressionKey.permission <- self.permission.rawValue,
            ExpressionKey.source <- self.sourceType.rawValue,
            ExpressionKey.favourite <- self.isFavourite,
            ExpressionKey.deviceSortType <- self.deviceSortType.rawValue,
            ExpressionKey.deviceNumber <- self.deviceCount,
            ExpressionKey.luminaireNumber <- self.luminairesCount,
            ExpressionKey.groupNumber <- self.groupCount,
            ExpressionKey.sceneNumber <- self.sceneCount,
            ExpressionKey.scheduleNumber <- self.scheheduleCount,
            ExpressionKey.switchesNumber <- self.switchesCount,
            ExpressionKey.createTimestamp <- self.create,
            ExpressionKey.lastUpdateTimestamp <- self.lastUpdate,
            ExpressionKey.lastUploadCloudTimestamp <- self.lastUploadCloudTimestamp,
            ExpressionKey.syncCloudError <- self.syncCloudError?.code,
            ExpressionKey.state <- self.state.rawValue,
            ExpressionKey.editorPassword <- self.editorPassword,
            ExpressionKey.vistorPassword <- self.vistorPassword,
            ExpressionKey.authorizationPassword <- self.authorizationPassword,
            ExpressionKey.requiresPasswordVerification <- self.requiresPasswordVerification,
            ExpressionKey.vistorPasswordEnable <- self.vistorPasswordEnable,
            ExpressionKey.shareCode <- self.shareCode,
            ExpressionKey.applyDeviceAddressCount <- self.applyDeviceAddressCount,
            ExpressionKey.applyGroupAddressCount <- self.applyGroupAddressCount,
            ExpressionKey.isReleaseAddress <- self.releaseAddress,
            ExpressionKey.editor <- editorData,
            ExpressionKey.vistors <- vistorsData
        ])
        do {
            try SunSmartDataManager.shared.db?.run(interOrUpdate)
            
            // 更新editor、visitor用户数据
//            UserData.delete(spaceId: self.id)
//            if let editorUser = self.editor {
//                editorUser.save(spaceId: self.id, permisson: .editor)
//            }
//            self.visitors.forEach({
//                $0.save(spaceId: self.id, permisson: .visitor)
//            })
            
        } catch {
            print(error)
            return false
        }
        return true
    }
    
    /// 获取下一个space名称
    /// - Parameter siteId: 对应场所id
    /// - Parameter defaultName: 查询的space默认名称  ”Space “
    /// - Returns: 默认的space名称
    static func getNextSpaceName(siteId: String, defaultName: String = "space_defalut_name".localizedString) -> String {
        
        var result = "\(defaultName)1"
        // 场所已使用的名称索引
        var spaceIndexs: [Int] = []
        let sql = SpaceData.spacesTable.filter(ExpressionKey.siteUUID == siteId && ExpressionKey.name.like(defaultName + "%"))
        if let rows = try? SunSmartDataManager.shared.db?.prepare(sql) {
            for row in rows {
                
                let spaceName = row[ExpressionKey.name]
                if let index = Int(spaceName.replacingOccurrences(of: defaultName, with: "")) {
                    spaceIndexs.append(index)
                }
            }
        }
        // 获取未被使用的site索引
        for index in 1...1000 {
            if !spaceIndexs.contains(index) {
                result = defaultName + "\(index)"
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
        let time = Int64(Date().timeIntervalSince1970)
        space.create = time
        space.lastUpdate = time
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
    
    private static let groupInfosTableName = "groupInfos"
    private static let groupInfosTable = Table(groupInfosTableName)
    
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
        static let pwmPeriod = Expression<Int?>("pwmPeriod")
        static let proximityLightingPath = Expression<Data?>("proximityLightingPath")
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
            builder.column(ExpressionKey.pwmPeriod)
            builder.column(ExpressionKey.proximityLightingPath)
            builder.unique(ExpressionKey.meshUUID, ExpressionKey.groupAddress)
        }))
        
        // 获取表内存在的属性
        if let columns = try? SunSmartDataManager.shared.db?.schema.columnDefinitions(table: groupInfosTableName) {
            // 插入字段
            // 是否存在”pwmPeriod“属性
            if !columns.contains(where: { $0.name == "pwmPeriod" }) {
                _ = try? SunSmartDataManager.shared.db?.run(GroupInfo.groupInfosTable.addColumn(ExpressionKey.pwmPeriod))
            }
            
            if !columns.contains(where: { $0.name == "proximityLightingPath" }) {
                _ = try? SunSmartDataManager.shared.db?.run(GroupInfo.groupInfosTable.addColumn(ExpressionKey.proximityLightingPath))
            }
        }
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
                    info.ambientLightSensorNodeAddress = Address(daylightSensorAddress)
//                    info.ambientLightSensorNode = Node.load(meshUUID: meshUUID, address: Address(daylightSensorAddress)).first
                }
                // TODO: load Profile、Switches
                // 日程数据
//                let schedules = Schedule.load(meshUUID: meshUUID, meshNetworkKey: meshNetworkKey, address: UInt16(address))
//                groupInfo?.bindSchedules = schedules
//                // 配置数据
                if let profile = Profile.load(meshUUID: meshUUID, meshNetworkId: row[ExpressionKey.subNetworkKey], profileId: row[ExpressionKey.profileId]) {
                    info.profile = profile
                }
                if let pwmPeriod = row[ExpressionKey.pwmPeriod] {
                    info.pwmPeriod = UInt16(pwmPeriod)
                }
                
                // 邻近照明路径
                if let proximityLightingPathData = row[ExpressionKey.proximityLightingPath],
                    let proximityLightingPath = try? jsonDecoder.decode(GroupProximityLightingPathData.self, from: proximityLightingPathData) {
                    info.proximityLightingPath = proximityLightingPath
                }
                // 虚拟按键
//                info.switchs = GroupSwitch.load(meshUUID: meshUUID, meshNetworkId: row[ExpressionKey.subNetworkKey], groupAddress: address)
                
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
    @discardableResult func save(meshUUID: String? = nil, subnetworkId: String? = nil) -> Bool {
        
        guard let uuid = meshUUID ?? MeshNetworkManager.instance.meshNetwork?.uuid.uuidString else { return false }
        let networkId = subnetworkId ?? MeshNetworkManager.instance.currentNetworkKey.networkId.hex
       
        let scenesData = try? jsonEncoder.encode(self.sceneExecuteDatas)
        
        var proximityLightingPathData: Data?
        if let proximityLightingPath = self.proximityLightingPath {
            proximityLightingPathData = try? jsonEncoder.encode(proximityLightingPath)
        }
        
        let insertOrUpdate = GroupInfo.groupInfosTable.insert(or: .replace, [
            ExpressionKey.meshUUID <- uuid,
            ExpressionKey.subNetworkKey <- networkId,
            ExpressionKey.groupAddress <- Int(self.address),
            ExpressionKey.imageId <- self.imageId,
            ExpressionKey.imageText <- self.imageText,
            ExpressionKey.profileId <- self.profile.id,
            ExpressionKey.daylightSensorAddress <- self.ambientLightSensorNodeAddress != nil ? Int(self.ambientLightSensorNodeAddress!) : nil,
            ExpressionKey.scenesData <- scenesData,
            ExpressionKey.pwmPeriod <- self.pwmPeriod != nil ? Int(self.pwmPeriod!) : nil,
            ExpressionKey.proximityLightingPath <- proximityLightingPathData
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
    @discardableResult func save(meshUUID: String? = nil, subnetworkId: String? = nil) -> Bool {
        
        guard let uuid = meshUUID ?? MeshNetworkManager.instance.meshNetwork?.uuid.uuidString else { return false }
        let networkId = subnetworkId ?? MeshNetworkManager.instance.currentNetworkKey.networkId.hex
        let insertOrUpdate = SceneInfo.sceneInfosTable.insert(or: .replace, [
            ExpressionKey.meshUUID <- uuid,
            ExpressionKey.subNetworkKey <- networkId,
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
    /// - Parameter defaultName: 默认名称
    /// - Parameter meshNetworkKey: 子网网络key
    /// - Returns: 日程名称
    static func getNextScheduleName(meshUUID: String? = nil, meshNetworkId: String? = nil, defaultName: String = "schedule_defalut_name".localizedString) -> String {
        
        var result = "\(defaultName)1"
        
        guard let uuid = meshUUID ?? MeshNetworkManager.instance.meshNetwork?.uuid.uuidString else { return result }
        let subNetworkey = meshNetworkId ?? MeshNetworkManager.instance.currentNetworkKey.networkId.hex
        
        // 日程已使用的名称索引
        var scheduleIndexs: [Int] = []
        let sql = Schedule.schedulesTable.filter(ExpressionKey.meshUUID == uuid && ExpressionKey.subNetworkKey == subNetworkey && ExpressionKey.name.like(defaultName + "%"))
        if let rows = try? SunSmartDataManager.shared.db?.prepare(sql) {
            for row in rows {
                let spaceName = row[ExpressionKey.name]
                if let index = Int(spaceName.replacingOccurrences(of: defaultName, with: "")) {
                    scheduleIndexs.append(index)
                }
            }
        }
        
        // 获取未被使用的schedule索引
        for index in 1...16 {
            if !scheduleIndexs.contains(index) {
                result = defaultName + "\(index)"
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
    
    private static let profilesTableName = "profiles"
    private static let profilesTable = Table(profilesTableName)
    
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
        static let powerUpCct = Expression<Int>("powerUpCct")
        static let adjustSpeed = Expression<Int>("adjustSpeed")
        static let sensitivity = Expression<Int>("sensitivity")
        static let proximityLightingNumber = Expression<Int>("proximityLightingNumber")
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
            builder.column(ExpressionKey.powerUpCct)
            builder.column(ExpressionKey.sensitivity)
            builder.column(ExpressionKey.proximityLightingNumber)
            builder.unique(ExpressionKey.meshUUID, ExpressionKey.uuid)
        }))
        
        // 获取表内存在的属性
        if let columns = try? SunSmartDataManager.shared.db?.schema.columnDefinitions(table: profilesTableName) {
            // 插入字段
            // 是否存在”powerUpCct“属性
            if !columns.contains(where: { $0.name == "powerUpCct" }) {
                _ = try? SunSmartDataManager.shared.db?.run(Profile.profilesTable.addColumn(ExpressionKey.powerUpCct, defaultValue: 4500))
            }
            
            // 是否存在”sensitivity“属性
            if !columns.contains(where: { $0.name == "sensitivity" }) {
                _ = try? SunSmartDataManager.shared.db?.run(Profile.profilesTable.addColumn(ExpressionKey.sensitivity, defaultValue: 100))
            }
            
            // 是否存在”proximityLightingNumber“属性
            if !columns.contains(where: { $0.name == "proximityLightingNumber" }) {
                _ = try? SunSmartDataManager.shared.db?.run(Profile.profilesTable.addColumn(ExpressionKey.proximityLightingNumber, defaultValue: 2))
            }
            
        }
    }

    /// 根据网络id获取网络下的所有的配置数据
    /// - Parameter meshUUID: 网络id
    /// - Parameter networkKey: 子网网络key
    /// - Returns: 日程数据list
    static func loadAll(meshUUID: String, meshNetworkId: String? = nil, profileId: String? = nil) -> [Profile] {
       
        let subNetworkey = meshNetworkId ?? MeshNetworkManager.instance.currentNetworkKey.networkId.hex
        
        var predicate = ExpressionKey.meshUUID == meshUUID && ExpressionKey.subNetworkKey == subNetworkey
        if profileId != nil {
            predicate = ExpressionKey.meshUUID == meshUUID && ExpressionKey.subNetworkKey == subNetworkey && ExpressionKey.uuid == profileId!
        }
        let filter = Profile.profilesTable.filter(predicate)
        
        var profiles: [Profile] = []
        if let rows = try? SunSmartDataManager.shared.db?.prepare(filter) {
            for row in rows {
                let profileType: ProfileType = .init(rawValue: row[ExpressionKey.type]) ?? .occupancy_daylight
                let lightData = LightData(profileType: profileType, highEndTrim: row[ExpressionKey.highEndTrim], lowEndTrim: row[ExpressionKey.lowEndTrim], occupancyLevel: row[ExpressionKey.occupancyLevel], vacantLevel: row[ExpressionKey.vacantLevel], taskLevel: row[ExpressionKey.taskLevel], autoMinLevel: row[ExpressionKey.autoMinLevel], t1: row[ExpressionKey.timeT1], t2: row[ExpressionKey.timeT2], t3: row[ExpressionKey.timeT3], t4: row[ExpressionKey.timeT4], t5: row[ExpressionKey.timeT5])
                
                let powerUpState: PowerUpState = .init(rawValue: UInt8(row[ExpressionKey.powerUpState]))
                let powerUpCct = UInt16(row[ExpressionKey.powerUpCct])
             
                let manualOverrideTimeout = UInt32(row[ExpressionKey.manualOverrideTimeout])
                
                let profile = Profile(name: row[ExpressionKey.name], id: row[ExpressionKey.uuid], type: profileType, lightData: lightData, powerUpState: powerUpState, powerUpCct: powerUpCct, manualOverrideTimeout: manualOverrideTimeout, adjustSpeed: row[ExpressionKey.adjustSpeed], sensitivity: UInt8(row[ExpressionKey.sensitivity]), proximityLightingNumber: UInt8(row[ExpressionKey.proximityLightingNumber]))
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
        let subNetworkey = meshNetworkId ?? MeshNetworkManager.instance.currentNetworkKey.networkId.hex
        
        let data = lightData.data
        let insertOrUpdate = Profile.profilesTable.insert(or: .replace, [
            ExpressionKey.meshUUID <- uuid,
            ExpressionKey.subNetworkKey <- subNetworkey,
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
            ExpressionKey.powerUpCct <- Int(self.powerUpCct),
            ExpressionKey.adjustSpeed <- self.adjustSpeed,
            ExpressionKey.sensitivity <- Int(self.sensitivity),
            ExpressionKey.proximityLightingNumber <- Int(self.proximityLightingNumber)
        ])
        do {
            try SunSmartDataManager.shared.db?.run(insertOrUpdate)
        } catch {
            print(error)
            return false
        }
        
        return true
    }
    
    /// 删除网络全部组配置
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
    
    /// 删除组配置数据
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
        let filter = GroupSwitch.switchsTable.filter(predicate).order(ExpressionKey.id.asc)
        
        var switchs: [GroupSwitch] = []
        if let rows = try? SunSmartDataManager.shared.db?.prepare(filter) {
            for row in rows {
//                if let group = MeshNetworkManager.instance.groups.first(where: { $0.address.address == row[ExpressionKey.groupAddress] }) {
                let groupSwitch = GroupSwitch(id: row[ExpressionKey.switchId], groupAddress: Address(row[ExpressionKey.groupAddress]), enabled: row[ExpressionKey.enabled], name: row[ExpressionKey.name])
                    let panelType: PanelType = .init(rawValue: UInt8(row[ExpressionKey.panelType])) ?? .default
                    groupSwitch.panelType = panelType
                    if let number = row[ExpressionKey.sceneA] { //  let sceneA = MeshNetworkManager.instance.scenes.first(where: { $0.number == number })
                        groupSwitch.sceneANumber = SceneNumber(number)
                    }
                    if let number = row[ExpressionKey.sceneB] { //  let sceneB = MeshNetworkManager.instance.scenes.first(where: { $0.number == number })
                        groupSwitch.sceneBNumber = SceneNumber(number)
                    }
                    
                    if let addressesData = row[ExpressionKey.proxyAddresses], let addressesStrings = (try? jsonDecoder.decode([String].self, from: addressesData)) {
                        // 动能开关代理地址list
                        var proxyAddresses: [Address] = []
                        addressesStrings.forEach {
                            if let address = UInt16($0, radix: 16), address.isUnicast {
                                proxyAddresses.append(address)
                            }
                        }
                        if let address = proxyAddresses.first { // let proxyNode = MeshNetworkManager.instance.meshNetwork?.node(withAddress: Address(address))
                            groupSwitch.proxyNodeAddress = Address(address)
                        }
                    }
                    switchs.append(groupSwitch)
//                }
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
//                if let group = MeshNetworkManager.instance.groups.first(where: { $0.address.address == row[ExpressionKey.groupAddress] }) {
                    let groupSwitch = GroupSwitch(id: row[ExpressionKey.switchId], groupAddress: Address(row[ExpressionKey.groupAddress]), enabled: row[ExpressionKey.enabled], name: row[ExpressionKey.name])
                    let panelType: PanelType = .init(rawValue: UInt8(row[ExpressionKey.panelType])) ?? .default
                    groupSwitch.panelType = panelType
                    if let number = row[ExpressionKey.sceneA] {
                        groupSwitch.sceneANumber = SceneNumber(number)
                    }
                    if let number = row[ExpressionKey.sceneB] {
                        groupSwitch.sceneBNumber = SceneNumber(number)
                    }
                    
                    if let addressesData = row[ExpressionKey.proxyAddresses], let addressesStrings = (try? jsonDecoder.decode([String].self, from: addressesData)) {
                        // 动能开关代理地址list
                        var proxyAddresses: [Address] = []
                        addressesStrings.forEach {
                            if let address = UInt16($0, radix: 16), address.isUnicast {
                                proxyAddresses.append(address)
                            }
                        }
                        if let address = proxyAddresses.first {
                            groupSwitch.proxyNodeAddress = Address(address)
                        }
                    }
                    resultSwitch = groupSwitch
                    break
//                }
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
        if let proxyAddress = self.proxyNodeAddress {
            proxyAddressesData = try? jsonEncoder.encode([String(format: "%04X", proxyAddress)])
        }
        
        let insertOrUpdate = GroupSwitch.switchsTable.insert(or: .replace, [
            ExpressionKey.meshUUID <- uuid,
            ExpressionKey.subNetworkKey <- subNetworkey,
            ExpressionKey.switchId <- self.id,
            ExpressionKey.name <- self.name,
            ExpressionKey.enabled <- self.enabled,
            ExpressionKey.panelType <- Int(self.panelType.rawValue),
            ExpressionKey.groupAddress <- Int(self.groupAddress),
            ExpressionKey.sceneA <- self.sceneANumber != nil ? Int(self.sceneANumber!) : nil,
            ExpressionKey.sceneB <- self.sceneBNumber != nil ? Int(self.sceneBNumber!) : nil,
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
        let predicate = ExpressionKey.meshUUID == meshUUID && ExpressionKey.subNetworkKey == networkId && ExpressionKey.groupAddress == Int(groupAddress) && ExpressionKey.switchId == self.id

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

extension FirmwareData {
    
    private static let firmwaresTable = Table("firmwares")
    
    struct ExpressionKey {
        static let id = Expression<Int64>("id")
        static let name = Expression<String>("name")
        static let version = Expression<String>("version")
        static let firmwareData = Expression<Data>("data")
        static let firmwareId = Expression<Data>("firmwareId")
        static let updateFirmwareImageIndex = Expression<Int>("updateFirmwareImageIndex")
        static let incomingFirmwareMetadata = Expression<Data>("incomingFirmwareMetadata")
        static let deviceType = Expression<Int>("deviceType")
        static let vendorId = Expression<Int>("vendorId")
        static let customId = Expression<Int?>("customId")
        static let releaseDateTimestamp = Expression<Int64>("releaseDate")
        static let content = Expression<String>("content")
        static let compositionHash = Expression<String>("compositionHash")
    }
    
    /// 初始化固件数据扩展信息表
    static func initDatabase() {
        
        _ = try? SunSmartDataManager.shared.db?.run(FirmwareData.firmwaresTable.create(temporary: false, ifNotExists: true, withoutRowid: false, block: { builder in
            builder.column(ExpressionKey.id, primaryKey: true)
            builder.column(ExpressionKey.name)
            builder.column(ExpressionKey.version)
            builder.column(ExpressionKey.firmwareData)
            builder.column(ExpressionKey.firmwareId)
            builder.column(ExpressionKey.updateFirmwareImageIndex)
            builder.column(ExpressionKey.incomingFirmwareMetadata)
            builder.column(ExpressionKey.deviceType)
            builder.column(ExpressionKey.vendorId)
            builder.column(ExpressionKey.customId)
            builder.column(ExpressionKey.releaseDateTimestamp)
            builder.column(ExpressionKey.content)
            builder.column(ExpressionKey.compositionHash)
            builder.unique(ExpressionKey.deviceType, ExpressionKey.vendorId, ExpressionKey.customId)
        }))
    }
    
    
    /// 读取固件缓存数据
    /// - Parameters:
    ///   - productId: 产品id
    ///   - vendorId: 厂商id（非必须）
    ///   - customId: 自定义id（非必须）
    /// - Returns: 固件包list
    static func load(productId: UInt16, vendorId: UInt16? = nil, customId: UInt16? = nil) -> [FirmwareData] {
        
        var query = FirmwareData.firmwaresTable.filter(ExpressionKey.deviceType == Int(productId))
        
        if let vendorId = vendorId {
            query = query.filter(ExpressionKey.vendorId == Int(vendorId))
        }
        if let customId = customId {
            query = query.filter(ExpressionKey.customId == Int(customId))
        }
        
        var list: [FirmwareData] = []
        if let rows = try? SunSmartDataManager.shared.db?.prepare(query) {
            for row in rows {
                let customId = row[ExpressionKey.customId]
                let data = FirmwareData(name: row[ExpressionKey.name], version: row[ExpressionKey.version], firmwareID: row[ExpressionKey.firmwareId], data: row[ExpressionKey.firmwareData], updateFirmwareImageIndex: row[ExpressionKey.updateFirmwareImageIndex], incomingFirmwareMetadata: row[ExpressionKey.incomingFirmwareMetadata], productId: UInt16(row[ExpressionKey.deviceType]), vendorId: UInt16(row[ExpressionKey.vendorId]), customId: customId != nil ? UInt16(customId!) : nil, releaseDate: row[ExpressionKey.releaseDateTimestamp], content: row[ExpressionKey.content], compositionHash: row[ExpressionKey.compositionHash])
                list.append(data)
            }
        }
        return list
    }
    
    /// 保存数据
    @discardableResult func save() -> Bool {
     
        let insertOrUpdate = FirmwareData.firmwaresTable.insert(or: .replace, [
            ExpressionKey.name <- self.name,
            ExpressionKey.version <- self.version,
            ExpressionKey.firmwareData <- self.data,
            ExpressionKey.firmwareId <- self.firmwareID,
            ExpressionKey.updateFirmwareImageIndex <- self.updateFirmwareImageIndex,
            ExpressionKey.incomingFirmwareMetadata <- self.incomingFirmwareMetadata,
            ExpressionKey.deviceType <- Int(self.productId),
            ExpressionKey.vendorId <- Int(self.vendorId),
            ExpressionKey.customId <- self.customId != nil ? Int(self.customId!) : nil,
            ExpressionKey.releaseDateTimestamp <- self.releaseDate,
            ExpressionKey.content <- self.content,
            ExpressionKey.compositionHash <- self.compositionHash
        ])
       
        do {
            try SunSmartDataManager.shared.db?.run(insertOrUpdate)
        } catch {
            print(error)
            return false
        }
        return true
    }
    
    @discardableResult func delete() -> Bool {
        
        var filter = FirmwareData.firmwaresTable.filter(ExpressionKey.deviceType == Int(self.productId) && ExpressionKey.vendorId == Int(self.vendorId))
        if self.customId != nil {
//            let customIdQuery = FirmwareData.firmwaresTable.filter(ExpressionKey.customId == Int(self.customId!))
            filter = filter.filter(ExpressionKey.customId == Int(self.customId!))
        }
        
        do {
            try SunSmartDataManager.shared.db?.run(filter.delete())
        } catch {
            print(error)
            return false
        }
        return true
    }
    
}

extension MeshDistributionData {
    
    private static let distributionDatasTableName = "distributionDatas"
    private static let distributionDatasTable = Table(distributionDatasTableName)
    
    struct ExpressionKey {
        static let id = Expression<Int64>("id")
        static let meshUUID = Expression<String>("meshUUID")
        static let subNetworkId = Expression<String>("subNetworkId")
        static let vendorId = Expression<Int>("vendorId")
        static let deviceType = Expression<Int>("deviceType")
        static let distributionAddress = Expression<Int>("distributionAddress")
        static let targetAddresses = Expression<Data>("targetAddresses")
        static let distributionState = Expression<Data?>("distributionState")
//        static let updateFirmwareImageIndex = Expression<Int>("updateFirmwareImageIndex")
//        static let incomingFirmwareMetadata = Expression<Data>("incomingFirmwareMetadata")
//        static let firmwareDataSize = Expression<Int>("firmwareDataSize")
    }
    
    /// 初始化固件数据扩展信息表
    static func initDatabase() {
        
        _ = try? SunSmartDataManager.shared.db?.run(MeshDistributionData.distributionDatasTable.create(temporary: false, ifNotExists: true, withoutRowid: false, block: { builder in
            builder.column(ExpressionKey.id, primaryKey: true)
            builder.column(ExpressionKey.meshUUID)
            builder.column(ExpressionKey.subNetworkId)
            builder.column(ExpressionKey.vendorId)
            builder.column(ExpressionKey.deviceType)
            builder.column(ExpressionKey.distributionAddress)
            builder.column(ExpressionKey.targetAddresses)
            builder.column(ExpressionKey.distributionState)
//            builder.column(ExpressionKey.updateFirmwareImageIndex)
//            builder.column(ExpressionKey.incomingFirmwareMetadata)
//            builder.column(ExpressionKey.firmwareDataSize)
            builder.unique(ExpressionKey.meshUUID, ExpressionKey.subNetworkId, ExpressionKey.vendorId, ExpressionKey.deviceType)
        }))
        
        // 获取表内存在的属性
        if let columns = try? SunSmartDataManager.shared.db?.schema.columnDefinitions(table: distributionDatasTableName) {
            // 插入字段
            // 是否存在”distributionState“属性
            if !columns.contains(where: { $0.name == "distributionState" }) {
                _ = try? SunSmartDataManager.shared.db?.run(MeshDistributionData.distributionDatasTable.addColumn(ExpressionKey.distributionState))
            }
        }
        
    }
    
    
    /// 获取网络内所有分发记录
    /// - Parameters:
    ///   - meshUUID: 网络uuid
    ///   - meshNetworkId: 子网id
    /// - Returns: 分发记录list
    static func loadAll(meshUUID: String? = nil, meshNetworkId: String? = nil) -> [MeshDistributionData] {
        
        guard let uuid = meshUUID ?? MeshNetworkManager.instance.meshNetwork?.uuid.uuidString else { return [] }
        let subNetworkKey = meshNetworkId ?? MeshNetworkManager.instance.currentNetworkKey.networkId.hex
        
        let predicate = ExpressionKey.meshUUID == uuid && ExpressionKey.subNetworkId == subNetworkKey
        
        let filter = MeshDistributionData.distributionDatasTable.filter(predicate)
        
        var distributionDatas: [MeshDistributionData] = []
        if let rows = try? SunSmartDataManager.shared.db?.prepare(filter) {
            for row in rows {
                
                // 升级设备地址data
                let targetAddressesData = row[ExpressionKey.targetAddresses]
                var targetAddresses: [Address] = []
                if let addressesStrings = (try? jsonDecoder.decode([String].self, from: targetAddressesData)) {
                    addressesStrings.forEach {
                        if let address = UInt16($0, radix: 16) {
                            targetAddresses.append(address)
                        }
                    }
                }
                // 分发状态
                var state: FirmwareDistributionUpdateState = .none
                if let data = row[ExpressionKey.distributionState], let updateState = FirmwareDistributionUpdateState(parameters: data) {
                    state = updateState
                }
                let distributionData = MeshDistributionData(distributionAddress: Address(row[ExpressionKey.distributionAddress]), targetAddresses: targetAddresses, distributionState: state)
                distributionDatas.append(distributionData)
            }
        }
        return distributionDatas
    }
    
    /// 获取固件分发数据
    /// - Parameters:
    ///   - meshUUID: 网络uuid
    ///   - meshNetworkId: 子网id
    ///   - productId: 设备类型
    ///   - vendorId: 场所id
    /// - Returns: 固件分发数据
    static func load(meshUUID: String? = nil, meshNetworkId: String? = nil, productId: UInt16, vendorId: UInt16 = 0x0A78) -> MeshDistributionData? {
        
        guard let uuid = meshUUID ?? MeshNetworkManager.instance.meshNetwork?.uuid.uuidString else { return nil }
        let subNetworkKey = meshNetworkId ?? MeshNetworkManager.instance.currentNetworkKey.networkId.hex
        
        let predicate = ExpressionKey.meshUUID == uuid && ExpressionKey.subNetworkId == subNetworkKey && ExpressionKey.deviceType == Int(productId) && ExpressionKey.vendorId == Int(vendorId)
        
        let filter = MeshDistributionData.distributionDatasTable.filter(predicate)
        
        var distributionData: MeshDistributionData?
        if let rows = try? SunSmartDataManager.shared.db?.prepare(filter) {
            for row in rows {
                // 升级设备地址data
                let targetAddressesData = row[ExpressionKey.targetAddresses]
                var targetAddresses: [Address] = []
                if let addressesStrings = (try? jsonDecoder.decode([String].self, from: targetAddressesData)) {
                    addressesStrings.forEach {
                        if let address = UInt16($0, radix: 16) {
                            targetAddresses.append(address)
                        }
                    }
                }
                // 分发状态
                var state: FirmwareDistributionUpdateState = .none
                if let data = row[ExpressionKey.distributionState], let updateState = FirmwareDistributionUpdateState(parameters: data) {
                    state = updateState
                }
                distributionData = MeshDistributionData(distributionAddress: Address(row[ExpressionKey.distributionAddress]), targetAddresses: targetAddresses, distributionState: state)
            }
        }
        return distributionData
    }
    
    /// 保存数据
    @discardableResult func save(meshUUID: String? = nil, networkId: String? = nil, productId: UInt16, vendorId: UInt16 = 0x0A78) -> Bool {
        
        guard let uuid = meshUUID ?? MeshNetworkManager.instance.meshNetwork?.uuid.uuidString else { return false }
        let subNetworkey = networkId ?? MeshNetworkManager.instance.currentNetworkKey.networkId.hex
        
        let targetAddressesData = try? jsonEncoder.encode(targetAddresses.map({ $0.hex }))
        
        let insertOrUpdate = MeshDistributionData.distributionDatasTable.insert(or: .replace, [
            ExpressionKey.meshUUID <- uuid,
            ExpressionKey.subNetworkId <- subNetworkey,
            ExpressionKey.vendorId <- Int(vendorId),
            ExpressionKey.deviceType <- Int(productId),
            ExpressionKey.distributionAddress <- Int(self.distributionAddress),
            ExpressionKey.targetAddresses <- targetAddressesData ?? Data(),
            ExpressionKey.distributionState <- self.distributionState.parmaters
        ])
       
        do {
            try SunSmartDataManager.shared.db?.run(insertOrUpdate)
        } catch {
            print(error)
            return false
        }
        return true
    }
    
    /// 删除分发数据
    @discardableResult func delete(meshUUID: String? = nil, networkId: String? = nil, productId: UInt16, vendorId: UInt16 = 0x0A78) -> Bool {
        
        guard let uuid = meshUUID ?? MeshNetworkManager.instance.meshNetwork?.uuid.uuidString else { return false }
        let subNetworkey = networkId ?? MeshNetworkManager.instance.currentNetworkKey.networkId.hex
        
        let filter = MeshDistributionData.distributionDatasTable.filter(ExpressionKey.meshUUID == uuid && ExpressionKey.subNetworkId == subNetworkey && ExpressionKey.deviceType == Int(productId) && ExpressionKey.vendorId == Int(vendorId))
        
        do {
            try SunSmartDataManager.shared.db?.run(filter.delete())
        } catch {
            print(error)
            return false
        }
        return true
    }
    
}

extension DeviceSwitchData {
    
    private static let switchsTableName = "switchs"
    private static let switchsTable = Table(switchsTableName)
    
    struct ExpressionKey {
        static let id = Expression<Int64>("id")
        static let meshUUID = Expression<String>("meshUUID")
        static let subNetworkKey = Expression<String>("subNetworkKey")
        static let switchId = Expression<String>("switchId")
        static let name = Expression<String>("name")
        static let enabled = Expression<Bool>("enabled")
        static let panelType = Expression<Int>("panelType")
        static let linkGroupAddress = Expression<Int?>("linkGroupAddress")
        static let subLinkGroupAddress = Expression<Int?>("subLinkGroupAddress")
        static let bindGroupAddresses = Expression<Data?>("bindGroupAddresses")
        static let unbindGroupAddresses = Expression<Data?>("unbindGroupAddresses")
        static let sceneA = Expression<Int?>("sceneA")
        static let sceneB = Expression<Int?>("sceneB")
        static let sceneC = Expression<Int?>("sceneC")
        static let sceneD = Expression<Int?>("sceneD")
        static let proxyAddresses = Expression<Data?>("proxyAddresses")
        static let enOceanMacAddress = Expression<String?>("enOceanMacAddress")
        static let enOceanSecurityKey = Expression<String?>("enOceanSecurityKey")
        static let deleteProxyAddress = Expression<Int?>("deleteProxyAddress")
    }
    
    /// 初始化组扩展信息表
    static func initDatabase() {
        
        _ = try? SunSmartDataManager.shared.db?.run(DeviceSwitchData.switchsTable.create(temporary: false, ifNotExists: true, withoutRowid: false, block: { builder in
            builder.column(ExpressionKey.id, primaryKey: true)
            builder.column(ExpressionKey.meshUUID)
            builder.column(ExpressionKey.subNetworkKey)
            builder.column(ExpressionKey.switchId)
            builder.column(ExpressionKey.name)
            builder.column(ExpressionKey.enabled)
            builder.column(ExpressionKey.panelType)
            builder.column(ExpressionKey.linkGroupAddress)
            builder.column(ExpressionKey.bindGroupAddresses)
            builder.column(ExpressionKey.unbindGroupAddresses)
            builder.column(ExpressionKey.sceneA)
            builder.column(ExpressionKey.sceneB)
            builder.column(ExpressionKey.proxyAddresses)
            builder.column(ExpressionKey.enOceanMacAddress)
            builder.column(ExpressionKey.enOceanSecurityKey)
            builder.column(ExpressionKey.deleteProxyAddress)
            builder.column(ExpressionKey.subLinkGroupAddress)
            builder.column(ExpressionKey.sceneC)
            builder.column(ExpressionKey.sceneD)
            builder.unique(ExpressionKey.meshUUID, ExpressionKey.subNetworkKey, ExpressionKey.switchId)
        }))
        
        // 获取表内存在的属性
        if let columns = try? SunSmartDataManager.shared.db?.schema.columnDefinitions(table: switchsTableName) {
            // 插入字段
            // 是否存在”subLinkGroupAddress“属性
            if !columns.contains(where: { $0.name == "subLinkGroupAddress" }) {
                _ = try? SunSmartDataManager.shared.db?.run(DeviceSwitchData.switchsTable.addColumn(ExpressionKey.subLinkGroupAddress))
            }
            // 是否存在”sceneC“属性
            if !columns.contains(where: { $0.name == "sceneC" }) {
                _ = try? SunSmartDataManager.shared.db?.run(DeviceSwitchData.switchsTable.addColumn(ExpressionKey.sceneC))
            }
            // 是否存在”sceneD“属性
            if !columns.contains(where: { $0.name == "sceneD" }) {
                _ = try? SunSmartDataManager.shared.db?.run(DeviceSwitchData.switchsTable.addColumn(ExpressionKey.sceneD))
            }
        }
        
    }

    /// 根据网络id获取所有的虚拟按键数据
    /// - Parameter meshUUID: 网络id
    /// - Parameter networkKey: 子网网络key
    /// - Parameter id: 按键id（传入获取指定按键）
    /// - Parameter macAddress: 动能开关mac
    /// - Returns: 虚拟按键数据list
    static func load(meshUUID: String, meshNetworkId: String? = nil, id: String? = nil, macAddress: String? = nil) -> [DeviceSwitchData] {
        
        let subNetworkKey = meshNetworkId ?? MeshNetworkManager.instance.currentNetworkKey.networkId.hex
        
        var predicate = ExpressionKey.meshUUID == meshUUID && ExpressionKey.subNetworkKey == subNetworkKey
        if let switchId = id {
            predicate = ExpressionKey.meshUUID == meshUUID && ExpressionKey.subNetworkKey == subNetworkKey && ExpressionKey.switchId == switchId
        }else if let mac = macAddress {
            predicate = ExpressionKey.meshUUID == meshUUID && ExpressionKey.subNetworkKey == subNetworkKey && (ExpressionKey.enOceanMacAddress ?? "") == mac
        }
        
        let filter = DeviceSwitchData.switchsTable.filter(predicate).order(ExpressionKey.id.asc)
        
        var switchs: [DeviceSwitchData] = []
        if let rows = try? SunSmartDataManager.shared.db?.prepare(filter) {
            for row in rows {
                
                // 动能开关关联的组地址（publish）
                let linkGroupAddress = row[ExpressionKey.linkGroupAddress]
                // 动能开关关联的子组地址（cct publish）
                let subLinkGroupAddress = row[ExpressionKey.subLinkGroupAddress]
                
                // 动能开关绑定组地址list（subscribe）
                var bindAddresses: [Address] = []
                if let bindAddressesData = row[ExpressionKey.bindGroupAddresses], let addressesStrings = (try? jsonDecoder.decode([String].self, from: bindAddressesData)) {
                    addressesStrings.forEach {
                        if let address = UInt16($0, radix: 16), address.isGroup {
                            bindAddresses.append(address)
                        }
                    }
                }
                
                // 解除绑定的组地址list（unsubscribe）
                var unbindAddresses: [Address] = []
                if let unbindAddressesData = row[ExpressionKey.unbindGroupAddresses], let addressesStrings = (try? jsonDecoder.decode([String].self, from: unbindAddressesData)) {
                    addressesStrings.forEach {
                        if let address = UInt16($0, radix: 16), address.isGroup {
                            unbindAddresses.append(address)
                        }
                    }
                }
                
                let switchData = DeviceSwitchData(id: row[ExpressionKey.switchId], enabled: row[ExpressionKey.enabled], name: row[ExpressionKey.name], linkGroupAddress: linkGroupAddress != nil ? Address(linkGroupAddress!) : nil, subLinkGroupAddress: subLinkGroupAddress != nil ? Address(subLinkGroupAddress!) : nil, bindGroupAddresses: bindAddresses)
                let panelType: PanelType = .init(rawValue: UInt8(row[ExpressionKey.panelType])) ?? .default
                switchData.panelType = panelType
                if let number = row[ExpressionKey.sceneA] { //  let sceneA = MeshNetworkManager.instance.scenes.first(where: { $0.number == number })
                    switchData.sceneANumber = SceneNumber(number)
                }
                if let number = row[ExpressionKey.sceneB] { //  let sceneB = MeshNetworkManager.instance.scenes.first(where: { $0.number == number })
                    switchData.sceneBNumber = SceneNumber(number)
                }
                
                if let number = row[ExpressionKey.sceneC] { //  let sceneA = MeshNetworkManager.instance.scenes.first(where: { $0.number == number })
                    switchData.sceneCNumber = SceneNumber(number)
                }
                if let number = row[ExpressionKey.sceneD] { //  let sceneB = MeshNetworkManager.instance.scenes.first(where: { $0.number == number })
                    switchData.sceneDNumber = SceneNumber(number)
                }
                
                switchData.unbindGroupAddresses = unbindAddresses
                
                if let addressesData = row[ExpressionKey.proxyAddresses], let addressesStrings = (try? jsonDecoder.decode([String].self, from: addressesData)) {
                    // 动能开关代理地址list
                    var proxyAddresses: [Address] = []
                    addressesStrings.forEach {
                        if let address = UInt16($0, radix: 16), address.isUnicast {
                            proxyAddresses.append(address)
                        }
                    }
                    if let address = proxyAddresses.first { // let proxyNode = MeshNetworkManager.instance.meshNetwork?.node(withAddress: Address(address))
                        switchData.proxyNodeAddress = Address(address)
                    }
                }
                switchData.enOceanMacAddress = row[ExpressionKey.enOceanMacAddress]
                switchData.enOceanSecurityKey = row[ExpressionKey.enOceanSecurityKey]
                if let address = row[ExpressionKey.deleteProxyAddress] {
                    switchData.deleteProxyNodeAddress = Address(address)
                }
                
                switchs.append(switchData)
            }
        }
        return switchs
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
        if let proxyAddress = self.proxyNodeAddress {
            proxyAddressesData = try? jsonEncoder.encode([String(format: "%04X", proxyAddress)])
        }
        var bindGroupAddressesData: Data?
        if self.bindGroupAddresses.count > 0 {
            bindGroupAddressesData = try? jsonEncoder.encode(bindGroupAddresses.map({ $0.hex }))
        }
        var unbindGroupAddressesData: Data?
        if self.unbindGroupAddresses.count > 0 {
            unbindGroupAddressesData = try? jsonEncoder.encode(unbindGroupAddresses.map({ $0.hex }))
        }
        
        let insertOrUpdate = DeviceSwitchData.switchsTable.insert(or: .replace, [
            ExpressionKey.meshUUID <- uuid,
            ExpressionKey.subNetworkKey <- subNetworkey,
            ExpressionKey.switchId <- self.id,
            ExpressionKey.name <- self.name,
            ExpressionKey.enabled <- self.enabled,
            ExpressionKey.panelType <- Int(self.panelType.rawValue),
            ExpressionKey.linkGroupAddress <- self.linkGroupAddress != nil ? Int(self.linkGroupAddress!) : nil,
            ExpressionKey.subLinkGroupAddress <- self.subLinkGroupAddress != nil ? Int(self.subLinkGroupAddress!) : nil,
            ExpressionKey.bindGroupAddresses <- bindGroupAddressesData,
            ExpressionKey.unbindGroupAddresses <- unbindGroupAddressesData,
            ExpressionKey.sceneA <- self.sceneANumber != nil ? Int(self.sceneANumber!) : nil,
            ExpressionKey.sceneB <- self.sceneBNumber != nil ? Int(self.sceneBNumber!) : nil,
            ExpressionKey.sceneC <- self.sceneCNumber != nil ? Int(self.sceneCNumber!) : nil,
            ExpressionKey.sceneD <- self.sceneDNumber != nil ? Int(self.sceneDNumber!) : nil,
            ExpressionKey.proxyAddresses <- proxyAddressesData,
            ExpressionKey.enOceanMacAddress <- self.enOceanMacAddress,
            ExpressionKey.enOceanSecurityKey <- self.enOceanSecurityKey,
            ExpressionKey.deleteProxyAddress <- self.deleteProxyNodeAddress != nil ? Int(self.deleteProxyNodeAddress!) : nil
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
    @discardableResult static func deleteSwitchs(meshUUID: String, networkId: String) -> Bool {
        
        // 指定子网下所有虚拟按键
        let predicate = ExpressionKey.meshUUID == meshUUID && ExpressionKey.subNetworkKey == networkId
 
        let filter = DeviceSwitchData.switchsTable.filter(predicate)
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
        let predicate = ExpressionKey.meshUUID == meshUUID && ExpressionKey.subNetworkKey == networkId && ExpressionKey.switchId == self.id

        let filter = DeviceSwitchData.switchsTable.filter(predicate)
        do {
            try SunSmartDataManager.shared.db?.run(filter.delete())
        } catch {
            print(error)
            return false
        }
        return true
    }
    
}

extension DeviceDongleData {
    
    private static let donglesTableName = "dongles"
    private static let donglesTable = Table(donglesTableName)
    
    struct ExpressionKey {
        static let id = Expression<Int64>("id")
        static let meshUUID = Expression<String>("meshUUID")
        static let subNetworkKey = Expression<String>("subNetworkKey")
        static let dongleId = Expression<String>("dongleId")
        static let name = Expression<String>("name")
        static let bindNodeAddress = Expression<Int?>("bindNodeAddress")
        static let timeAuthority = Expression<Bool>("timeAuthority")
        static let collectionEnable = Expression<Bool>("collectionEnable")
        static let schedules = Expression<Data?>("schedules")
        static let firstCollectionTimestamp = Expression<Int64?>("firstCollectionTimestamp")
    }
    
    /// 初始化组扩展信息表
    static func initDatabase() {
        
        _ = try? SunSmartDataManager.shared.db?.run(DeviceDongleData.donglesTable.create(temporary: false, ifNotExists: true, withoutRowid: false, block: { builder in
            builder.column(ExpressionKey.id, primaryKey: true)
            builder.column(ExpressionKey.meshUUID)
            builder.column(ExpressionKey.subNetworkKey)
            builder.column(ExpressionKey.dongleId)
            builder.column(ExpressionKey.name)
            builder.column(ExpressionKey.bindNodeAddress)
            builder.column(ExpressionKey.timeAuthority)
            builder.column(ExpressionKey.collectionEnable)
            builder.column(ExpressionKey.schedules)
            builder.column(ExpressionKey.firstCollectionTimestamp)
            builder.unique(ExpressionKey.meshUUID, ExpressionKey.subNetworkKey, ExpressionKey.dongleId)
        }))
    }
    
    /// 根据网络id获取所有的dongle数据
    /// - Parameter meshUUID: 网络id
    /// - Parameter networkKey: 子网网络key
    /// - Parameter id: dongle id（传入获取指定dongle）
    /// - Parameter bindNodeAddress: 绑定的节点地址
    /// - Returns: dongle数据list
    static func load(meshUUID: String, meshNetworkId: String? = nil, id: String? = nil, bindNodeAddress: Address? = nil) -> [DeviceDongleData] {
        
        let subNetworkKey = meshNetworkId ?? MeshNetworkManager.instance.currentNetworkKey.networkId.hex
        
        var predicate = DeviceDongleData.donglesTable.filter(ExpressionKey.meshUUID == meshUUID && ExpressionKey.subNetworkKey == subNetworkKey)
        if let dongleId = id {
            predicate = predicate.filter(ExpressionKey.dongleId == dongleId)
        }else if let address = bindNodeAddress {
            predicate = predicate.filter(ExpressionKey.bindNodeAddress == Int(address))
        }
        
        let filter = predicate.order(ExpressionKey.id.asc)
        
        var dongles: [DeviceDongleData] = []
        if let rows = try? SunSmartDataManager.shared.db?.prepare(filter) {
            for row in rows {
                
                let bindNodeAddress = row[ExpressionKey.bindNodeAddress]
                var collectionSchedules: [CollectionSchedule] = []
                if let data = row[ExpressionKey.schedules],
                   let schedules = try? jsonDecoder.decode([CollectionSchedule].self, from: data) {
                    collectionSchedules = schedules
                }
                
               let dongleData = DeviceDongleData(id: row[ExpressionKey.dongleId], name: row[ExpressionKey.name], bindNodeAddress: bindNodeAddress != nil ? Address(bindNodeAddress!) : nil, timeAuthority: row[ExpressionKey.timeAuthority], collectionEnable: row[ExpressionKey.collectionEnable], schedules: collectionSchedules)
                
                dongleData.firstCollectionTimestamp = row[ExpressionKey.firstCollectionTimestamp]
                
                dongles.append(dongleData)
            }
        }
        return dongles
    }
    
    /// 缓存dongle数据
    /// - Parameters:
    ///   - meshUUID: 网络id
    ///   - networkKey: 子网网络key
    /// - Returns: 是否成功
    @discardableResult func save(meshUUID: String? = nil, networkId: String? = nil) -> Bool {
        
        guard let uuid = meshUUID ?? MeshNetworkManager.instance.meshNetwork?.uuid.uuidString else { return false }
        let subNetworkey = networkId ?? MeshNetworkManager.instance.currentNetworkKey.networkId.hex
        
        var schedulesData: Data?
        if schedules.count > 0 {
            schedulesData = try? jsonEncoder.encode(schedules)
        }
        
        let insertOrUpdate = DeviceDongleData.donglesTable.insert(or: .replace, [
            ExpressionKey.meshUUID <- uuid,
            ExpressionKey.subNetworkKey <- subNetworkey,
            ExpressionKey.dongleId <- self.id,
            ExpressionKey.name <- self.name,
            ExpressionKey.bindNodeAddress <- self.bindNodeAddress != nil ? Int(self.bindNodeAddress!) : nil,
            ExpressionKey.timeAuthority <- self.timeAuthority,
            ExpressionKey.collectionEnable <- self.collectionEnable,
            ExpressionKey.schedules <- schedulesData,
            ExpressionKey.firstCollectionTimestamp <- self.firstCollectionTimestamp
        ])
        do {
            try SunSmartDataManager.shared.db?.run(insertOrUpdate)
        } catch {
            print(error)
            return false
        }
        return true
    }
    
    /// 删除网络内全部dongle数据
    /// - Parameter meshUUID: 网络id
    /// - Parameter networkKey: 子网网络key
    /// - Returns: 是否成功
    @discardableResult static func deleteDongles(meshUUID: String, networkId: String) -> Bool {
        
        // 指定子网下所有虚拟按键
        let predicate = ExpressionKey.meshUUID == meshUUID && ExpressionKey.subNetworkKey == networkId
 
        let filter = DeviceDongleData.donglesTable.filter(predicate)
        do {
            try SunSmartDataManager.shared.db?.run(filter.delete())
        } catch {
            print(error)
            return false
        }
        return true
    }
    
    @discardableResult func delete(meshUUID: String, networkId: String) -> Bool {
        
        // 指定删除dongle
        let predicate = ExpressionKey.meshUUID == meshUUID && ExpressionKey.subNetworkKey == networkId && ExpressionKey.dongleId == self.id

        let filter = DeviceDongleData.donglesTable.filter(predicate)
        do {
            try SunSmartDataManager.shared.db?.run(filter.delete())
        } catch {
            print(error)
            return false
        }
        return true
    }
    
}

extension MeshDeviceConfigInfo {
    
    private static let deviceConfigInfosTableName = "deviceConfigInfos"
    private static let deviceConfigInfosTable = Table(deviceConfigInfosTableName)
    
    struct ExpressionKey {
        static let id = Expression<Int64>("id")
        static let companyId = Expression<Int>("companyId")
        static let productId = Expression<Int>("productId")
        static let categoryName = Expression<String>("categoryName")
        static let elementCount = Expression<Int>("elementCount")
        static let iconCategory = Expression<String>("iconCategory")
        static let deviceCategory = Expression<String>("deviceCategory")
        static let modelName = Expression<String?>("modelName")
        static let sensitivityRangeMin = Expression<Int?>("sensitivityRangeMin")
        static let sensitivityRangeMax = Expression<Int?>("sensitivityRangeMax")
    }
    
    /// 初始化设备配置信息表
    static func initDatabase() {
        
        _ = try? SunSmartDataManager.shared.db?.run(MeshDeviceConfigInfo.deviceConfigInfosTable.create(temporary: false, ifNotExists: true, withoutRowid: false, block: { builder in
            builder.column(ExpressionKey.id, primaryKey: true)
            builder.column(ExpressionKey.companyId)
            builder.column(ExpressionKey.productId)
            builder.column(ExpressionKey.categoryName)
            builder.column(ExpressionKey.elementCount)
            builder.column(ExpressionKey.iconCategory)
            builder.column(ExpressionKey.deviceCategory)
            builder.column(ExpressionKey.modelName)
            builder.column(ExpressionKey.sensitivityRangeMin)
            builder.column(ExpressionKey.sensitivityRangeMax)
            builder.unique(ExpressionKey.companyId, ExpressionKey.productId)
        }))
        // 获取表内存在的属性
        if let columns = try? SunSmartDataManager.shared.db?.schema.columnDefinitions(table: deviceConfigInfosTableName) {
            // 插入字段
            // 是否存在”iconCategory“属性
            if !columns.contains(where: { $0.name == "iconCategory" }) {
                _ = try? SunSmartDataManager.shared.db?.run(MeshDeviceConfigInfo.deviceConfigInfosTable.addColumn(ExpressionKey.iconCategory, defaultValue: "Lighting"))
            }
            // 是否存在”iconCategory“属性
            if !columns.contains(where: { $0.name == "deviceCategory" }) {
                _ = try? SunSmartDataManager.shared.db?.run(MeshDeviceConfigInfo.deviceConfigInfosTable.addColumn(ExpressionKey.deviceCategory, defaultValue: "Lighting"))
            }
            // 是否存在”modelName“属性
            if !columns.contains(where: { $0.name == "modelName" }) {
                _ = try? SunSmartDataManager.shared.db?.run(MeshDeviceConfigInfo.deviceConfigInfosTable.addColumn(ExpressionKey.modelName))
            }
            // 是否存在”sensitivityRangeMin“属性
            if !columns.contains(where: { $0.name == "sensitivityRangeMin" }) {
                _ = try? SunSmartDataManager.shared.db?.run(MeshDeviceConfigInfo.deviceConfigInfosTable.addColumn(ExpressionKey.sensitivityRangeMin))
            }
            // 是否存在”sensitivityRangeMax“属性
            if !columns.contains(where: { $0.name == "sensitivityRangeMax" }) {
                _ = try? SunSmartDataManager.shared.db?.run(MeshDeviceConfigInfo.deviceConfigInfosTable.addColumn(ExpressionKey.sensitivityRangeMax))
            }
        }
    }
    
    /// 加载设备配置信息list
    /// - Parameters:
    ///   - companyId: 厂商id（非必须）
    ///   - productId: 产品id（非必须）
    /// - Returns: 设备配置信息list
    static func load(companyId: UInt16? = nil, productId: UInt16? = nil) -> [MeshDeviceConfigInfo] {
        
        var query = MeshDeviceConfigInfo.deviceConfigInfosTable
        
        if let companyId = companyId {
//            let vendorQuery = MeshDeviceConfigInfo.deviceConfigInfosTable.filter(ExpressionKey.companyId == Int(companyId))
            query = query.filter(ExpressionKey.companyId == Int(companyId))
        }
        if let productId = productId {
//            let productIdQuery = MeshDeviceConfigInfo.deviceConfigInfosTable.filter(ExpressionKey.productId == Int(productId))
            query = query.filter(ExpressionKey.productId == Int(productId))
        }
        
        var infos: [MeshDeviceConfigInfo] = []
        if let rows = try? SunSmartDataManager.shared.db?.prepare(query) {
            for row in rows {
                
                var sensitivityRange: ClosedRange<UInt16>?
                if let min = row[ExpressionKey.sensitivityRangeMin], let max = row[ExpressionKey.sensitivityRangeMax] {
                    sensitivityRange = UInt16(min)...UInt16(max)
                }
                
                let info = MeshDeviceConfigInfo(companyId: UInt16(row[ExpressionKey.companyId]), productId: UInt16(row[ExpressionKey.productId]), categoryName: row[ExpressionKey.categoryName], elementCount: row[ExpressionKey.elementCount], iconCategory: row[ExpressionKey.iconCategory], deviceCategory: row[ExpressionKey.deviceCategory], modelName: row[ExpressionKey.modelName], sensitivityRange: sensitivityRange)
                infos.append(info)
            }
        }
        return infos
    }
    
    
    /// 删除设备配置信息
    /// - Parameters:
    ///   - companyId: 厂商id（非必须）
    ///   - productId: 产品id（非必须）
    /// - Returns: 是否成功
    @discardableResult static func delete(companyId: UInt16? = nil, productId: UInt16? = nil) -> Bool {
        
        var predicate = MeshDeviceConfigInfo.deviceConfigInfosTable
        
        if let companyId = companyId {
//            let vendorQuery = MeshDeviceConfigInfo.deviceConfigInfosTable.filter(ExpressionKey.companyId == Int(companyId))
            predicate = predicate.filter(ExpressionKey.companyId == Int(companyId))
        }
        if let productId = productId {
//            let productIdQuery = MeshDeviceConfigInfo.deviceConfigInfosTable.filter(ExpressionKey.productId == Int(productId))
            predicate = predicate.filter(ExpressionKey.productId == Int(productId))
        }

        do {
            try SunSmartDataManager.shared.db?.run(predicate.delete())
        } catch {
            print(error)
            return false
        }
        return true
    }
    
    
    /// 重新缓存所有设备配置信息数据
    /// - Parameter list: 缓存的list数据
    /// - Returns: 是否成功
    @discardableResult static func saveAll(list: [MeshDeviceConfigInfo]) -> Bool {
        guard delete() else {
            return false
        }
        list.forEach({
            $0.save()
        })
        return true
    }
    
    @discardableResult func save() -> Bool {
        
        let insertOrUpdate = MeshDeviceConfigInfo.deviceConfigInfosTable.insert(or: .replace, [
            ExpressionKey.companyId <- Int(self.companyId),
            ExpressionKey.productId <- Int(self.productId),
            ExpressionKey.categoryName <- self.categoryName,
            ExpressionKey.elementCount <- self.elementCount,
            ExpressionKey.iconCategory <- self.iconCategory,
            ExpressionKey.deviceCategory <- self.deviceCategory,
            ExpressionKey.modelName <- self.modelName,
            ExpressionKey.sensitivityRangeMin <- self.sensitivityRange != nil ? Int(self.sensitivityRange!.lowerBound) : nil,
            ExpressionKey.sensitivityRangeMax <- self.sensitivityRange != nil ? Int(self.sensitivityRange!.upperBound) : nil
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

extension EnergyStatisticsStaticData {
    
    private static let energyStaticDatasTableName = "energyStaticDatas"
    private static let energyStaticDatasTable = Table(energyStaticDatasTableName)
    
    struct ExpressionKey {
        static let id = Expression<Int64>("id")
        static let spaceId = Expression<String>("spaceId")
        static let timestamp = Expression<Int64>("timestamp")
        static let incomplete = Expression<Bool>("incomplete")
        static let deviceEnergys = Expression<Data>("deviceEnergys")
        static let groups = Expression<Data>("groups")
    }
    
    /// 初始化能耗静态统计数据信息表
    static func initDatabase() {
        
        _ = try? SunSmartDataManager.shared.db?.run(EnergyStatisticsStaticData.energyStaticDatasTable.create(temporary: false, ifNotExists: true, withoutRowid: false, block: { builder in
            builder.column(ExpressionKey.id, primaryKey: true)
            builder.column(ExpressionKey.spaceId)
            builder.column(ExpressionKey.timestamp)
            builder.column(ExpressionKey.incomplete)
            builder.column(ExpressionKey.deviceEnergys)
            builder.column(ExpressionKey.groups)
            builder.unique(ExpressionKey.timestamp, ExpressionKey.spaceId)
        }))
    }
    
    /// 加载能耗静态统计数据list（Static Data）最新数据在前面
    /// - Parameters:
    ///   - spaceId: 空间id
    /// - Returns: 能耗静态统计数据list
    static func load(spaceId: String) -> [EnergyStatisticsStaticData] {
        
        let filter = EnergyStatisticsStaticData.energyStaticDatasTable.filter(ExpressionKey.spaceId == spaceId).order(ExpressionKey.timestamp.desc)

        var datas: [EnergyStatisticsStaticData] = []
        if let rows = try? SunSmartDataManager.shared.db?.prepare(filter) {
            for row in rows {
                if let deviceEnergyDatas = try? jsonDecoder.decode([DeviceTotalEnergyData].self, from: row[ExpressionKey.deviceEnergys]) {
                    
                    let groups = try? jsonDecoder.decode([Group].self, from: row[ExpressionKey.groups])
                    
                    let data = EnergyStatisticsStaticData(timestamp: Int64(row[ExpressionKey.timestamp]), incomplete: row[ExpressionKey.incomplete], deviceEnergyDatas: deviceEnergyDatas, groups: groups ?? [])
                    datas.append(data)
                }
            }
        }
        return datas
    }
    
    /// 保存能耗静态数据到数据库
    /// - Parameter spaceId: 对应spaceId
    /// - Returns: 是否成功
    @discardableResult func save(spaceId: String) -> Bool {
        
        guard let deviceEnergysData = try? jsonEncoder.encode(self.deviceEnergyDatas), let groupsData = try? jsonEncoder.encode(self.groups) else {
            return false
        }
        let insertOrUpdate = EnergyStatisticsStaticData.energyStaticDatasTable.insert(or: .replace, [
            ExpressionKey.spaceId <- spaceId,
            ExpressionKey.timestamp <- self.timestamp,
            ExpressionKey.incomplete <- self.incomplete,
            ExpressionKey.deviceEnergys <- deviceEnergysData,
            ExpressionKey.groups <- groupsData
        ])
        do {
            try SunSmartDataManager.shared.db?.run(insertOrUpdate)
        } catch {
            print(error)
            return false
        }
        return true
        
    }
    
    /// 删除对应能耗静态统计数据数据（Static Data）
    /// - Parameters:
    ///   - spaceId: 空间id
    /// - Returns: 是否成功
    @discardableResult func delete(spaceId: String) -> Bool {
        
        let predicate = EnergyStatisticsStaticData.energyStaticDatasTable.filter(ExpressionKey.spaceId == spaceId && ExpressionKey.timestamp == self.timestamp)

        do {
            try SunSmartDataManager.shared.db?.run(predicate.delete())
        } catch {
            print(error)
            return false
        }
        return true
    }
    
}

extension GatewayModel {
    
    private static let gatewaysTableName = "gateways"
    private static let gatewaysTable = Table(gatewaysTableName)
    
    struct ExpressionKey {
        static let id = Expression<Int64>("id")
        static let siteUUID = Expression<String>("siteUUID")
        static let macAddress = Expression<String>("macAddress")
        static let address = Expression<Int>("address")
        static let activate = Expression<Bool>("activate")
        static let associatedSpaces = Expression<Data>("associatedSpaces")
        static let apn = Expression<String?>("apn")
        static let mqttServerInfo = Expression<Data?>("mqttServerInfo")
    }
    
    /// 初始化能耗静态统计数据信息表
    static func initDatabase() {
        
        _ = try? SunSmartDataManager.shared.db?.run(GatewayModel.gatewaysTable.create(temporary: false, ifNotExists: true, withoutRowid: false, block: { builder in
            builder.column(ExpressionKey.id, primaryKey: true)
            builder.column(ExpressionKey.siteUUID)
            builder.column(ExpressionKey.macAddress)
            builder.column(ExpressionKey.address)
            builder.column(ExpressionKey.activate)
            builder.column(ExpressionKey.associatedSpaces)
            builder.column(ExpressionKey.apn)
            builder.column(ExpressionKey.mqttServerInfo)
            builder.unique(ExpressionKey.siteUUID, ExpressionKey.macAddress)
        }))
    }
    
    /// 加载site内所有网关list
    /// - Parameters:
    ///   - siteId: site id
    /// - Returns: 网关list
    static func load(siteId: String, macAddress: String? = nil, address: Address? = nil) -> [GatewayModel] {
        
        var query = GatewayModel.gatewaysTable.filter(ExpressionKey.siteUUID == siteId)
        if let macAddress = macAddress {
            query = query.filter(ExpressionKey.macAddress == macAddress)
//            query = GatewayModel.gatewaysTable.filter(ExpressionKey.siteUUID == siteId && ExpressionKey.macAddress == macAddress)
        }else if let address = address {
            query = query.filter(ExpressionKey.address == Int(address))
        }
        
        var gateways: [GatewayModel] = []
        if let rows = try? SunSmartDataManager.shared.db?.prepare(query) {
            for row in rows {
                var spaceDatas: [SpaceData] = []
                if let spaceIds = try? jsonDecoder.decode([String].self, from: row[ExpressionKey.associatedSpaces]) {
                    spaceDatas = spaceIds.compactMap({
                        return SpaceData.load(siteId: siteId, spaceId: $0).first
                    })
                }
                
                let gateway = GatewayModel(siteId: siteId,address: Address(row[ExpressionKey.address]), mac: row[ExpressionKey.macAddress], activate: row[ExpressionKey.activate], associatedSpaces: spaceDatas, apn: row[ExpressionKey.apn], mqttServerInfo: nil)
                
                if let data = row[ExpressionKey.mqttServerInfo],
                   let serverInformation = try? jsonDecoder.decode(GatewayInformation.MQTTConnectInformation.self, from: data) {
                    gateway.mqttServerInfo = serverInformation
                }
                gateways.append(gateway)
            }
        }
        return gateways
    }
    
    /// 保存网关model数据
    @discardableResult func save() -> Bool {
        
        let spacesData = (try? jsonEncoder.encode(associatedSpaces.map({ $0.id }))) ?? Data()
        
        var mqttServerInfoData: Data?
        if let mqttServerInfo = self.mqttServerInfo {
            mqttServerInfoData = try? jsonEncoder.encode(mqttServerInfo)
        }
        
        let insertOrUpdate = GatewayModel.gatewaysTable.insert(or: .replace, [
            ExpressionKey.siteUUID <- self.siteId,
            ExpressionKey.macAddress <- self.mac,
            ExpressionKey.address <- Int(self.address),
            ExpressionKey.activate <- self.activate,
            ExpressionKey.apn <- self.apn,
            ExpressionKey.associatedSpaces <- spacesData,
            ExpressionKey.mqttServerInfo <- mqttServerInfoData
        ])
        do {
            try SunSmartDataManager.shared.db?.run(insertOrUpdate)
        } catch {
            print(error)
            return false
        }
        return true
        
    }
    
    /// 删除对应网关
    /// - Parameters:
    ///   - siteId: siteid
    ///   - macAddress: 网关mac地址
    /// - Returns: 是否成功
    @discardableResult static func delete(siteId: String, macAddress: String) -> Bool {
        
        let predicate = GatewayModel.gatewaysTable.filter(ExpressionKey.siteUUID == siteId && ExpressionKey.macAddress == macAddress)
        do {
            try SunSmartDataManager.shared.db?.run(predicate.delete())
        } catch {
            print(error)
            return false
        }
        return true
    }
    
    /// 删除对应网关
    /// - Parameters:
    ///   - siteId: siteid
    ///   - macAddress: 网关mac地址
    /// - Returns: 是否成功
    @discardableResult func delete() -> Bool {
        
        let predicate = GatewayModel.gatewaysTable.filter(ExpressionKey.siteUUID == self.siteId && ExpressionKey.macAddress == mac)
        do {
            try SunSmartDataManager.shared.db?.run(predicate.delete())
        } catch {
            print(error)
            return false
        }
        return true
    }
    
    
}
