//
//  Database.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/8/24.
//

import Foundation
import NordicSigMeshSDK

/// 缓存场所/空间数据库名称
let sqliteDBName = "sunsmart.sqlite"
/// sqlite缓存对象
let sqliteWrapper = SQLiteWrapper.shared()!

extension SiteData {
    
    static let CREATE_TABLE_SITES = "CREATE TABLE IF NOT EXISTS SITES(SITE_ROW INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,SITE_ID TEXT, SITE_NAME TEXT, SITE_IMAGE_ID INTEGER, SITE_TYPE INTEGER, SITE_CREATE TEXT, SITE_LASTUPDATE TEXT, SITE_SOURCE INTEGER, SITE_FAVOURITE BOOL)"

    static let CREATE_IDX_SITES_SITE = "CREATE UNIQUE INDEX IF NOT EXISTS IDX_SITES_SITE ON SITES(SITE_ID)"

    static let SAVE_SITES = "INSERT OR REPLACE INTO SITES(SITE_ID, SITE_NAME, SITE_IMAGE_ID, SITE_TYPE, SITE_CREATE, SITE_LASTUPDATE, SITE_SOURCE, SITE_FAVOURITE) VALUES(?, ?, ?, ?, ?, ?, ?, ?)"

    static let GET_SITES = "SELECT SITE_ID, SITE_NAME, SITE_IMAGE_ID, SITE_TYPE, SITE_CREATE, SITE_LASTUPDATE, SITE_SOURCE, SITE_FAVOURITE FROM SITES ORDER BY SITE_CREATE"
    
    static let GET_NEXT_SITENAME = "SELECT SITE_NAME FROM SITES WHERE SITE_NAME LIKE ?"
    // 获取重名的场所名称
    static let GET_TAUTONY_SITENAME = "SELECT SITE_NAME FROM SITES WHERE SITE_NAME = ?"

    static let GET_SITE_BY_ID = "SELECT SITE_ID, SITE_NAME, SITE_IMAGE_ID, SITE_TYPE, SITE_CREATE, SITE_LASTUPDATE, SITE_SOURCE, SITE_FAVOURITE FROM SITES WHERE SITE_ID = ?"

    static let DELETE_SITES = "DELETE FROM SITES"
    
    static let DELETE_SITE = "DELETE FROM SITES WHERE SITE_ID = ?"
    
    /// 初始化数据库缓存
    static func createDatabaseIfNotExit() {
        objc_sync_enter(sqliteWrapper)
        if sqliteWrapper.isOpen || sqliteWrapper.openDb(sqliteDBName) {
            sqliteWrapper.execSql(SiteData.CREATE_TABLE_SITES)
            sqliteWrapper.execSql(SiteData.CREATE_IDX_SITES_SITE)
//           sqliteWrapper.closeDb()
        }
        objc_sync_exit(sqliteWrapper)
//        //        sqliteWrapper.closeDb()
        SpaceData.createDatabaseIfNotExit()
    }
    
    /// 获取所有的场所
    /// - Returns: mesh网络list
    static func loadAll() -> [SiteData] {
        
        objc_sync_enter(sqliteWrapper)
        guard sqliteWrapper.isOpen || sqliteWrapper.openDb(sqliteDBName), sqliteWrapper.prepareSql(SiteData.GET_SITES) else {
            objc_sync_exit(sqliteWrapper)
            return []
        }
        var sites: [SiteData] = []
        
        while sqliteWrapper.stepSqlRow() {
            
//            let create = sqliteWrapper.columnText(4) as String
            let site = SiteData(id: sqliteWrapper.columnText(0), name: sqliteWrapper.columnText(1), imageId: Int(sqliteWrapper.columnInt(2)), type: SiteType(rawValue: Int(sqliteWrapper.columnInt(3))) ?? .other, create: sqliteWrapper.columnText(4), lastUpdate: sqliteWrapper.columnText(5), isFavourite: sqliteWrapper.columnBool(7), sourceType: .init(rawValue: Int(sqliteWrapper.columnInt(6))) ?? .create)
            sites.append(site)
        }
        sqliteWrapper.finalizeSql()
  //        sqliteWrapper.closeDb()
        objc_sync_exit(sqliteWrapper)
        
        for site in sites {
            /// 获取场所下空间list 
            site.spaces = SpaceData.loadAll(siteId: site.id)
        }
        
        return sites
    }
    
    /// 根据场所id获取对应场所
    /// - Parameter siteId: 场所id
    /// - Returns: 返回场所对象
    static func load(siteId: String) -> SiteData? {
        
        objc_sync_enter(sqliteWrapper)
        guard sqliteWrapper.isOpen || sqliteWrapper.openDb(sqliteDBName), sqliteWrapper.prepareSql(SiteData.GET_SITE_BY_ID) else {
            objc_sync_exit(sqliteWrapper)
            return nil
        }
        
        sqliteWrapper.bindText(1, text: siteId)
        var site: SiteData?
        
        while sqliteWrapper.stepSqlRow() {
            site = SiteData(id: sqliteWrapper.columnText(0), name: sqliteWrapper.columnText(1), imageId: Int(sqliteWrapper.columnInt(2)), type: SiteType(rawValue: Int(sqliteWrapper.columnInt(3))) ?? .other, create: sqliteWrapper.columnText(4), lastUpdate: sqliteWrapper.columnText(5), isFavourite: sqliteWrapper.columnBool(7), sourceType: .init(rawValue: Int(sqliteWrapper.columnInt(6))) ?? .create)
        }
        sqliteWrapper.finalizeSql()
        //        sqliteWrapper.closeDb()
        objc_sync_exit(sqliteWrapper)
        
        site?.spaces = SpaceData.loadAll(siteId: siteId)
        
        return site
    }
    
    /// 删除当前场所数据
    @discardableResult func delete() -> Bool {
        
        objc_sync_enter(sqliteWrapper)
        guard sqliteWrapper.isOpen || sqliteWrapper.openDb(sqliteDBName), sqliteWrapper.prepareSql(SiteData.DELETE_SITE) else {
            objc_sync_exit(sqliteWrapper)
            return false
        }
        sqliteWrapper.bindText(1, text: self.id)
        sqliteWrapper.stepSqlDone()
        sqliteWrapper.finalizeSql()
        //        sqliteWrapper.closeDb()
        objc_sync_exit(sqliteWrapper)
        
        // 删除场所下缓存的空间
        for space in self.spaces {
            space.delete()
        }
        
        return true
    }
    
    /// 删除所有场所数据
    static func deleteAll() -> Bool {
        
        objc_sync_enter(sqliteWrapper)
        guard sqliteWrapper.isOpen || sqliteWrapper.openDb(sqliteDBName), sqliteWrapper.prepareSql(SiteData.DELETE_SITES) else {
            objc_sync_exit(sqliteWrapper)
            return false
        }
        sqliteWrapper.stepSqlDone()
        sqliteWrapper.finalizeSql()
        //        sqliteWrapper.closeDb()
        objc_sync_exit(sqliteWrapper)
        return true
    }
    
    /// 获取下一个site名称
    /// - Parameter defalutName: 查询的site默认名称  ”Site “
    /// - Returns: 默认的site名称
    static func getNextSiteName(_ defalutName: String = "site_defalut_name".localizedString) -> String {
        
        var result = "\(defalutName)1"
        objc_sync_enter(sqliteWrapper)
        guard sqliteWrapper.isOpen || sqliteWrapper.openDb(sqliteDBName), sqliteWrapper.prepareSql(SiteData.GET_NEXT_SITENAME) else {
            objc_sync_exit(sqliteWrapper)
            return result
        }
        // 场所已使用的名称索引
        var siteIndexs: [Int] = []
        sqliteWrapper.bindText(1, text: "%\(defalutName)%")
        
        while sqliteWrapper.stepSqlRow() {
            
            let siteName = sqliteWrapper.columnText(0) as String
            if let index = Int(siteName.replacingOccurrences(of: defalutName, with: "")) {
                siteIndexs.append(index)
            }
        }
        sqliteWrapper.finalizeSql()
        //        sqliteWrapper.closeDb()
        objc_sync_exit(sqliteWrapper)
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
        objc_sync_enter(sqliteWrapper)
        guard sqliteWrapper.isOpen || sqliteWrapper.openDb(sqliteDBName), sqliteWrapper.prepareSql(SiteData.GET_NEXT_SITENAME) else {
            objc_sync_exit(sqliteWrapper)
            return result
        }
        // 场所已使用的名称索引
        var siteIndexs: [Int] = []
        // 匹配名称
        let matching = "\(siteName)("
        sqliteWrapper.bindText(1, text: "%\(matching)%")
        
        while sqliteWrapper.stepSqlRow() {
            // "Site 1(1)"
            let siteName = sqliteWrapper.columnText(0) as String
            var cloneName = siteName.replacingOccurrences(of: "\(matching)", with: "")
            cloneName = cloneName.replacingOccurrences(of: ")", with: "")
            if let index = Int(cloneName) {
                siteIndexs.append(index)
            }
        }
        sqliteWrapper.finalizeSql()
        //        sqliteWrapper.closeDb()
        objc_sync_exit(sqliteWrapper)
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
        
        objc_sync_enter(sqliteWrapper)
        guard sqliteWrapper.isOpen || sqliteWrapper.openDb(sqliteDBName), sqliteWrapper.prepareSql(SiteData.GET_TAUTONY_SITENAME) else {
            objc_sync_exit(sqliteWrapper)
            return false
        }
        sqliteWrapper.bindText(1, text: siteName)
        // 是否重名
        var tautonym = false
        while sqliteWrapper.stepSqlRow() {
            tautonym = true
            break
        }
        sqliteWrapper.finalizeSql()
        //        sqliteWrapper.closeDb()
        objc_sync_exit(sqliteWrapper)
        return tautonym
    }
    
    /// 缓存当前场所数据
    /// allData：是否保存所有数据（true：场所基本信息+保存spaces数据，false：场所基本信息）
    @discardableResult func save(allData: Bool = false) -> Bool {
        
        objc_sync_enter(sqliteWrapper)
        guard sqliteWrapper.isOpen || sqliteWrapper.openDb(sqliteDBName), sqliteWrapper.prepareSql(SiteData.SAVE_SITES) else {
            objc_sync_exit(sqliteWrapper)
            return false
        }
        
        self.lastUpdate = "\(CLongLong(Date().timeIntervalSince1970 * 1000))"
        
        sqliteWrapper.bindText(1, text: self.id)
        sqliteWrapper.bindText(2, text: self.name)
        sqliteWrapper.bindInt(3, integer: sqlite3_int64(self.imageId))
        sqliteWrapper.bindInt(4, integer: sqlite3_int64(self.type.rawValue))
        sqliteWrapper.bindText(5, text: self.create)
        sqliteWrapper.bindText(6, text: self.lastUpdate)
        sqliteWrapper.bindInt(7, integer: sqlite3_int64(self.sourceType.rawValue))
        sqliteWrapper.bindBool(8, boolean: self.isFavourite)
        sqliteWrapper.stepSqlDone()
        sqliteWrapper.resetSql()
        sqliteWrapper.finalizeSql()
        //        sqliteWrapper.closeDb()
        
        objc_sync_exit(sqliteWrapper)
        if allData {
            self.spaces.forEach({ $0.save() })
        }

        return true
    }
    
    
}

extension SpaceData {
    
    static let CREAT_TABLE_SPACES = "CREATE TABLE IF NOT EXISTS SPACES(SPACE_ROW INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, SPACE_NAME TEXT, SPACE_ID TEXT, SITE_ID TEXT, SPACE_IMAGE_ID INTEGER, SPACE_CREATE TEXT, SPACE_LASTUPDATE TEXT, SPACE_SOURCE INTEGER, SPACE_FAVOURITE BOOL, SPACE_MESHUUID TEXT, SPACE_LUMINAIRES_COUNT INTEGER, SPACE_SWITCHES_COUNT INTEGER, SPACE_DEVICE_COUNT INTEGER, SPACE_GROUP_COUNT INTEGER, SPACE_SCENE_COUNT INTEGER, SPACE_SCHEHEDULE_COUNT INTEGER, SPACE_DEVICES_SORT_TYPE INTEGER, SYNC_DATE_TIMESTAMP INTEGER)"
    
    static let CREATE_IDX_SPACES_SPACE = "CREATE UNIQUE INDEX IF NOT EXISTS IDX_SPACES_SPACE ON SPACES(SPACE_ID, SITE_ID)"
    
    static let SAVE_SPACES = "INSERT OR REPLACE INTO SPACES(SPACE_NAME, SPACE_ID, SITE_ID, SPACE_IMAGE_ID, SPACE_CREATE, SPACE_LASTUPDATE, SPACE_SOURCE, SPACE_FAVOURITE, SPACE_MESHUUID, SPACE_LUMINAIRES_COUNT, SPACE_SWITCHES_COUNT, SPACE_DEVICE_COUNT, SPACE_GROUP_COUNT, SPACE_SCENE_COUNT, SPACE_SCHEHEDULE_COUNT, SPACE_DEVICES_SORT_TYPE, SYNC_DATE_TIMESTAMP) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"

    static let GET_SPACES = "SELECT SPACE_NAME, SPACE_ID, SITE_ID, SPACE_IMAGE_ID, SPACE_CREATE, SPACE_LASTUPDATE, SPACE_SOURCE, SPACE_FAVOURITE, SPACE_MESHUUID, SPACE_LUMINAIRES_COUNT, SPACE_SWITCHES_COUNT, SPACE_DEVICE_COUNT, SPACE_GROUP_COUNT, SPACE_SCENE_COUNT, SPACE_SCHEHEDULE_COUNT, SPACE_DEVICES_SORT_TYPE, SYNC_DATE_TIMESTAMP FROM SPACES WHERE SITE_ID = ? ORDER BY SPACE_CREATE"
    
    static let GET_SPACE_BY_ID = "SELECT SPACE_NAME, SPACE_ID, SITE_ID, SPACE_IMAGE_ID, SPACE_CREATE, SPACE_LASTUPDATE, SPACE_SOURCE, SPACE_FAVOURITE, SPACE_MESHUUID, SPACE_LUMINAIRES_COUNT, SPACE_SWITCHES_COUNT, SPACE_DEVICE_COUNT, SPACE_GROUP_COUNT, SPACE_SCENE_COUNT, SPACE_SCHEHEDULE_COUNT, SPACE_DEVICES_SORT_TYPE, SYNC_DATE_TIMESTAMP FROM SPACES WHERE SPACE_ID = ? AND SITE_ID = ?"
    
    static let GET_NEXT_SPACENAME = "SELECT SPACE_NAME FROM SPACES WHERE SITE_ID = ? AND SPACE_NAME LIKE ?"
    
    static let GET_TAUTONY_SPACENAME = "SELECT SPACE_NAME FROM SPACES WHERE SITE_ID = ? AND SPACE_NAME = ?"

    static let DELETE_SPACES = "DELETE FROM SPACES WHERE SITE_ID = ?"
    
    static let DELETE_SPACE = "DELETE FROM SPACES WHERE SPACE_ID = ? AND SITE_ID = ?"
    
    /// 初始化数据库缓存
    static func createDatabaseIfNotExit() {
        objc_sync_enter(sqliteWrapper)
        if sqliteWrapper.isOpen || sqliteWrapper.openDb(sqliteDBName) {
            sqliteWrapper.execSql(SpaceData.CREAT_TABLE_SPACES)
            sqliteWrapper.execSql(SpaceData.CREATE_IDX_SPACES_SPACE)
            //        sqliteWrapper.closeDb()
        }
        objc_sync_exit(sqliteWrapper)
        
        GroupInfo.createDatabaseIfNotExit()
        SceneInfo.createDatabaseIfNotExit()
        SceneExecuteData.createDatabaseIfNotExit()
        Schedule.createDatabaseIfNotExit()
        Node.createDatabaseIfNotExit()
        Profile.createDatabaseIfNotExit()
        GroupSwitch.createDatabaseIfNotExit()
    }
 
    /// 根据场所id获取场所下的所有空间
    /// - Parameter siteId: 场所id
    /// - Returns: 网络下的房间list
    static func loadAll(siteId: String) -> [SpaceData] {
        objc_sync_enter(sqliteWrapper)
        guard sqliteWrapper.prepareSql(SpaceData.GET_SPACES) else {
            objc_sync_exit(sqliteWrapper)
            return []
        }
        sqliteWrapper.bindText(1, text: siteId)
        
        var spaces: [SpaceData] = []
        while sqliteWrapper.stepSqlRow() {
            
            if let name = sqliteWrapper.columnText(0), let id = sqliteWrapper.columnText(1), let siteId = sqliteWrapper.columnText(2) {
                let space = SpaceData(name: name, id: id, siteId: siteId, imageId: Int(sqliteWrapper.columnInt(3)), create: sqliteWrapper.columnText(4), lastUpdate: sqliteWrapper.columnText(5), isFavourite: sqliteWrapper.columnBool(7), sourceType: .init(rawValue: Int(sqliteWrapper.columnInt(6))) ?? .create, meshUUID: sqliteWrapper.columnText(8))
                space.luminairesCount = Int(sqliteWrapper.columnInt(9))
                space.switchesCount = Int(sqliteWrapper.columnInt(10))
                space.deviceCount = Int(sqliteWrapper.columnInt(11))
                space.groupCount = Int(sqliteWrapper.columnInt(12))
                space.sceneCount = Int(sqliteWrapper.columnInt(13))
                space.scheheduleCount = Int(sqliteWrapper.columnInt(14))
                space.deviceSortType = .init(rawValue: Int(sqliteWrapper.columnInt(15))) ?? .create
                space.lastSyncDateTimestamp = CLongLong(sqliteWrapper.columnInt(16))
                spaces.append(space)
            }
        }
        
        sqliteWrapper.finalizeSql()
        //        sqliteWrapper.closeDb()
        objc_sync_exit(sqliteWrapper)

        return spaces
    }
    
    
    /// 根据空间id和场所id获取对应空间
    /// - Parameter spaceId: 空间id
    /// - Parameter siteId: 场所id
    /// - Returns: 房间
    static func load(spaceId: String, siteId: String) -> SpaceData? {
        objc_sync_enter(sqliteWrapper)
        guard sqliteWrapper.prepareSql(SpaceData.GET_SPACE_BY_ID) else {
            objc_sync_exit(sqliteWrapper)
            return nil
        }
        sqliteWrapper.bindText(1, text: spaceId)
        sqliteWrapper.bindText(2, text: siteId)
        
        var space: SpaceData?
        while sqliteWrapper.stepSqlRow() {
            space = SpaceData(name: sqliteWrapper.columnText(0), id: sqliteWrapper.columnText(1), siteId: sqliteWrapper.columnText(2), imageId: Int(sqliteWrapper.columnInt(3)), create: sqliteWrapper.columnText(4), lastUpdate: sqliteWrapper.columnText(5), isFavourite: sqliteWrapper.columnBool(7), sourceType: .init(rawValue: Int(sqliteWrapper.columnInt(6))) ?? .create, meshUUID: sqliteWrapper.columnText(8))
            space?.luminairesCount = Int(sqliteWrapper.columnInt(9))
            space?.switchesCount = Int(sqliteWrapper.columnInt(10))
            space?.deviceCount = Int(sqliteWrapper.columnInt(11))
            space?.groupCount = Int(sqliteWrapper.columnInt(12))
            space?.sceneCount = Int(sqliteWrapper.columnInt(13))
            space?.scheheduleCount = Int(sqliteWrapper.columnInt(14))
            space?.deviceSortType = .init(rawValue: Int(sqliteWrapper.columnInt(15))) ?? .create
            space?.lastSyncDateTimestamp = CLongLong(sqliteWrapper.columnInt(16))
        }
        sqliteWrapper.finalizeSql()
        //        sqliteWrapper.closeDb()
        objc_sync_exit(sqliteWrapper)
        return space
    }
    
 
    /// 删除所有空间数据
    /// - Parameter siteId: 对应场所
    /// - Returns: 是否成功
    static func deleteAll(siteId: String) -> Bool {
        
        objc_sync_enter(sqliteWrapper)
        guard sqliteWrapper.prepareSql(SpaceData.DELETE_SPACES) else {
            objc_sync_exit(sqliteWrapper)
            return false
        }
        sqliteWrapper.bindText(1, text: siteId)
        sqliteWrapper.stepSqlDone()
        sqliteWrapper.finalizeSql()
        //        sqliteWrapper.closeDb()
        objc_sync_exit(sqliteWrapper)
        return true
    }
    
    /// 删除当前空间数据
    @discardableResult func deleteData() -> Bool {
        
        objc_sync_enter(sqliteWrapper)
        guard sqliteWrapper.prepareSql(SpaceData.DELETE_SPACE) else {
            objc_sync_exit(sqliteWrapper)
            return false
        }
        sqliteWrapper.bindText(1, text: self.id)
        sqliteWrapper.bindText(2, text: self.siteId)
        sqliteWrapper.stepSqlDone()
        sqliteWrapper.finalizeSql()
        //        sqliteWrapper.closeDb()
        objc_sync_exit(sqliteWrapper)
        return true
    }
    
    /// 缓存当前空间数据
    @discardableResult func save() -> Bool {
        
        objc_sync_enter(sqliteWrapper)
        guard sqliteWrapper.prepareSql(SpaceData.SAVE_SPACES) else {
            objc_sync_exit(sqliteWrapper)
            return false
        }
        
        sqliteWrapper.bindText(1, text: self.name)
        sqliteWrapper.bindText(2, text: self.id)
        sqliteWrapper.bindText(3, text: self.siteId)
        sqliteWrapper.bindInt(4, integer: sqlite3_int64(self.imageId))
        sqliteWrapper.bindText(5, text: self.create)
        sqliteWrapper.bindText(6, text: self.lastUpdate)
        sqliteWrapper.bindInt(7, integer: sqlite3_int64(self.sourceType.rawValue))
        sqliteWrapper.bindBool(8, boolean: self.isFavourite)
        sqliteWrapper.bindText(9, text: self.meshUUID)
        sqliteWrapper.bindInt(10, integer: sqlite3_int64(self.luminairesCount))
        sqliteWrapper.bindInt(11, integer: sqlite3_int64(self.switchesCount))
        sqliteWrapper.bindInt(12, integer: sqlite3_int64(self.deviceCount))
        sqliteWrapper.bindInt(13, integer: sqlite3_int64(self.groupCount))
        sqliteWrapper.bindInt(14, integer: sqlite3_int64(self.sceneCount))
        sqliteWrapper.bindInt(15, integer: sqlite3_int64(self.scheheduleCount))
        sqliteWrapper.bindInt(16, integer: sqlite3_int64(self.deviceSortType.rawValue))
        sqliteWrapper.bindInt(17, integer: sqlite3_int64(self.lastSyncDateTimestamp))
        sqliteWrapper.stepSqlDone()
        sqliteWrapper.resetSql()
        sqliteWrapper.finalizeSql()
        //        sqliteWrapper.closeDb()
        
        objc_sync_exit(sqliteWrapper)
        
        return true
    }
    
    /// 获取下一个space名称
    /// - Parameter siteId: 对应场所id
    /// - Parameter defalutName: 查询的space默认名称  ”Space “
    /// - Returns: 默认的space名称
    static func getNextSpaceName(siteId: String, defalutName: String = "space_defalut_name".localizedString) -> String {
        
        var result = "\(defalutName)1"
        objc_sync_enter(sqliteWrapper)
        guard sqliteWrapper.isOpen || sqliteWrapper.openDb(sqliteDBName), sqliteWrapper.prepareSql(SpaceData.GET_NEXT_SPACENAME) else {
            objc_sync_exit(sqliteWrapper)
            return result
        }
        // 空间已使用的名称索引
        var siteIndexs: [Int] = []
        sqliteWrapper.bindText(1, text: siteId)
        sqliteWrapper.bindText(2, text: "%\(defalutName)%")
        
        while sqliteWrapper.stepSqlRow() {
            
            let siteName = sqliteWrapper.columnText(0) as String
            if let index = Int(siteName.replacingOccurrences(of: defalutName, with: "")) {
                siteIndexs.append(index)
            }
//            let create = sqliteWrapper.columnText(4) as String
//            siteNames.append(sqliteWrapper.columnText(0) as String)
        }
        sqliteWrapper.finalizeSql()
        //        sqliteWrapper.closeDb()
        objc_sync_exit(sqliteWrapper)
        // 获取未被使用的space索引
        for index in 1...1000 {
            if !siteIndexs.contains(index) {
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
        
        var result = spaceName
        objc_sync_enter(sqliteWrapper)
        guard sqliteWrapper.prepareSql(SpaceData.GET_NEXT_SPACENAME) else {
            objc_sync_exit(sqliteWrapper)
            return result
        }
        // 空间已使用的名称索引
        var spaceIndexs: [Int] = []
        sqliteWrapper.bindText(1, text: siteId)
        let matching = spaceName
//        "\(spaceName)("
        sqliteWrapper.bindText(2, text: "%\(matching)%")
        // Space名称不存在则直接用Space名称，存在则Space名称(1)、Space名称(2)...
        // 是否找到相同名称
        var isEqual = false
        while sqliteWrapper.stepSqlRow() {
            // "Site 1(1)"
            let spaceName = sqliteWrapper.columnText(0) as String
            var cloneName = spaceName.replacingOccurrences(of: "\(matching)(", with: "")
            cloneName = cloneName.replacingOccurrences(of: ")", with: "")
            if let index = Int(cloneName) {
                spaceIndexs.append(index)
            }else if spaceName == matching {
                isEqual = true
            }
        }
        
        sqliteWrapper.finalizeSql()
        //        sqliteWrapper.closeDb()
        objc_sync_exit(sqliteWrapper)
        if isEqual {
            // 获取未被使用的space索引
            for index in 1...1000 {
                if !spaceIndexs.contains(index) {
                    result = spaceName + "(\(index))"
                    break
                }
            }
        }
        return result
    }
    
    /// 判断空间名称是否重名
    /// - Parameter spaceName: 场所名称
    /// - Parameter siteId: 所在场所id
    /// - Returns: 是否重名
    static func isTautonym(spaceName: String, siteId: String) -> Bool {
        
        objc_sync_enter(sqliteWrapper)
        guard sqliteWrapper.prepareSql(SpaceData.GET_TAUTONY_SPACENAME) else {
            objc_sync_exit(sqliteWrapper)
            return false
        }
        sqliteWrapper.bindText(1, text: siteId)
        sqliteWrapper.bindText(2, text: spaceName)
        var tautonym = false
        while sqliteWrapper.stepSqlRow() {
            tautonym = true
            break
        }
        sqliteWrapper.finalizeSql()
        //        sqliteWrapper.closeDb()
        objc_sync_exit(sqliteWrapper)
        return tautonym
    }
    
}

extension GroupInfo {
    
    private static let CREAT_TABLE_GROUPS_INFO = "CREATE TABLE IF NOT EXISTS GROUPS_INFO(GROUPS_INFO_ROW INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, GROUP_NAME TEXT, GROUP_ADDRESS INTEGER, MESH_UUID TEXT, GROUP_IMAGE_ID INTEGER, GROUP_IMAGE_TEXT TEXT, PROFILE_ID TEXT, AMBIENT_LIGHT_NODE_ADDRESS INTEGER)"
    
    private static let CREATE_IDX_GROUPS_INFO = "CREATE UNIQUE INDEX IF NOT EXISTS IDX_GROUPS_INFO ON GROUPS_INFO(MESH_UUID, GROUP_ADDRESS)"
    
    private static let SAVE_GROUPS_INFO = "INSERT OR REPLACE INTO GROUPS_INFO(GROUP_NAME, GROUP_ADDRESS, MESH_UUID, GROUP_IMAGE_ID, GROUP_IMAGE_TEXT, PROFILE_ID, AMBIENT_LIGHT_NODE_ADDRESS) VALUES(?, ?, ?, ?, ?, ?, ?)"

    private static let GET_GROUPS_INFO = "SELECT GROUP_NAME, GROUP_ADDRESS, MESH_UUID, GROUP_IMAGE_ID, GROUP_IMAGE_TEXT, PROFILE_ID, AMBIENT_LIGHT_NODE_ADDRESS FROM GROUPS_INFO WHERE MESH_UUID = ?"
    
    private static let GET_GROUP_INFO_BY_ID = "SELECT GROUP_NAME, GROUP_ADDRESS, MESH_UUID, GROUP_IMAGE_ID, GROUP_IMAGE_TEXT, PROFILE_ID, AMBIENT_LIGHT_NODE_ADDRESS FROM GROUPS_INFO WHERE MESH_UUID = ? AND GROUP_ADDRESS = ?"
    
    private static let DELETE_GROUPS_INFO = "DELETE FROM GROUPS_INFO WHERE MESH_UUID = ?"
    
    private static let DELETE_GROUP_INFO = "DELETE FROM GROUPS_INFO WHERE MESH_UUID = ? AND GROUP_ADDRESS = ?"
    
    /// 初始化数据库缓存
    static func createDatabaseIfNotExit() {
        objc_sync_enter(sqliteWrapper)
        if sqliteWrapper.isOpen || sqliteWrapper.openDb(sqliteDBName) {
            sqliteWrapper.execSql(GroupInfo.CREAT_TABLE_GROUPS_INFO)
            sqliteWrapper.execSql(GroupInfo.CREATE_IDX_GROUPS_INFO)
            //        sqliteWrapper.closeDb()
        }
        objc_sync_exit(sqliteWrapper)
    }
 
    /// 根据mesh uuid获取网络下的所有组扩展信息
    /// - Parameter siteId: 场所id
    /// - Returns: 网络下的房间list
    static func loadAll(meshUUID: String) -> [GroupInfo] {
        objc_sync_enter(sqliteWrapper)
        guard sqliteWrapper.isOpen || sqliteWrapper.openDb(sqliteDBName), sqliteWrapper.prepareSql(GET_GROUPS_INFO) else {
            objc_sync_exit(sqliteWrapper)
            return []
        }
        sqliteWrapper.bindText(1, text: meshUUID)
        
        var groupInfos: [GroupInfo] = []
        var profileIds: [(address: Address, profileId: String)] = []
        
        while sqliteWrapper.stepSqlRow() {
            
            let address = sqliteWrapper.columnInt(1)
            let imageId = sqliteWrapper.columnInt(3)
            let imageText = sqliteWrapper.columnText(4)
            
            let groupInfo = GroupInfo(address: UInt16(address), imageId: Int(imageId))
            if let name = sqliteWrapper.columnText(0) {
                groupInfo.name = name
            }
            groupInfo.imageText = imageText
            groupInfos.append(groupInfo)
            if let profileId = sqliteWrapper.columnText(5) {
                profileIds.append((address: Address(address), profileId: profileId))
            }
            // 组绑定的光照传感器
            let ambientLightNodeAddress = sqliteWrapper.columnInt(6)
            if ambientLightNodeAddress > 0 {
                if let node = MeshNetworkManager.instance.meshNetwork?.node(withAddress: Address(ambientLightNodeAddress)) {
                    groupInfo.ambientLightSensorNode = node
                }
            }
        }
        
        sqliteWrapper.finalizeSql()
        //        sqliteWrapper.closeDb()
        objc_sync_exit(sqliteWrapper)
        
        groupInfos.forEach({
            // 场景数据
            let sceneDatas = SceneExecuteData.loadAll(meshUUID: meshUUID, address: $0.address)
            var bindSceneDatas: [SceneNumber: SceneExecuteData] = [:]
            sceneDatas.forEach({
                bindSceneDatas.updateValue($0.data, forKey: SceneNumber($0.sceneId))
            })
            
            $0.bindSceneDatas = bindSceneDatas
            // 日程数据
            let schedules = Schedule.loadAll(meshUUID: meshUUID, address: $0.address)
            $0.bindSchedules = schedules
            // 组配置数据
            if let profileid = profileIds.first(where: { $0.address == $0.address })?.profileId, let profile = Profile.load(meshUUID: meshUUID, profileId: profileid) {
                $0.profile = profile
            }
            
        })

        return groupInfos
    }
    
    /// 根据网络id和group地址获取对应配置的组数据
    /// - Parameter meshUUID: 网络id
    /// - Parameter address: 组地址地址
    /// - Returns: 组数据
    static func load(meshUUID: String, address: UInt16) -> GroupInfo? {
        objc_sync_enter(sqliteWrapper)
        guard sqliteWrapper.isOpen || sqliteWrapper.openDb(sqliteDBName), sqliteWrapper.prepareSql(GET_GROUP_INFO_BY_ID) else {
            objc_sync_exit(sqliteWrapper)
            return nil
        }
        sqliteWrapper.bindText(1, text: meshUUID)
        sqliteWrapper.bindInt(2, integer: sqlite3_int64(address))
        
        var groupInfo: GroupInfo?
        var profileId: String?
        while sqliteWrapper.stepSqlRow() {
            
            let address = sqliteWrapper.columnInt(1)
            let imageId = sqliteWrapper.columnInt(3)
            let imageText = sqliteWrapper.columnText(4)
            
            groupInfo = GroupInfo(address: UInt16(address), imageId: Int(imageId))
            if let name = sqliteWrapper.columnText(0) {
                groupInfo!.name = name
            }
            groupInfo!.imageText = imageText
            profileId = sqliteWrapper.columnText(5)
            // 组绑定的光照传感器
            let ambientLightNodeAddress = sqliteWrapper.columnInt(6)
            if ambientLightNodeAddress > 0 {
                if let node = MeshNetworkManager.instance.meshNetwork?.node(withAddress: Address(ambientLightNodeAddress)) {
                    groupInfo!.ambientLightSensorNode = node
                }
            }
        }
        sqliteWrapper.finalizeSql()
        //        sqliteWrapper.closeDb()
        objc_sync_exit(sqliteWrapper)
        
        // 场景数据
        let sceneDatas = SceneExecuteData.loadAll(meshUUID: meshUUID, address: UInt16(address))
        
        var bindSceneDatas: [SceneNumber: SceneExecuteData] = [:]
        sceneDatas.forEach({
            bindSceneDatas.updateValue($0.data, forKey: SceneNumber($0.sceneId))
        })
        groupInfo?.bindSceneDatas = bindSceneDatas
        
        // 日程数据
        let schedules = Schedule.loadAll(meshUUID: meshUUID, address: UInt16(address))
        groupInfo?.bindSchedules = schedules
        // 配置数据
        if let profileId = profileId, let profile = Profile.load(meshUUID: meshUUID, profileId: profileId) {
            groupInfo?.profile = profile
        }
        // 虚拟按键
        groupInfo?.switchs = GroupSwitch.loadAll(meshUUID: meshUUID, groupAddress: address)
        
        return groupInfo
    }
    
    /// 删除所有组扩展数据
    /// - Parameter meshUUID: 对应网络id
    /// - Returns: 是否成功
    @discardableResult static func deleteAll(meshUUID: String) -> Bool {
        
        objc_sync_enter(sqliteWrapper)
        guard sqliteWrapper.isOpen || sqliteWrapper.openDb(sqliteDBName), sqliteWrapper.prepareSql(DELETE_GROUPS_INFO) else {
            objc_sync_exit(sqliteWrapper)
            return false
        }
        sqliteWrapper.bindText(1, text: meshUUID)
        sqliteWrapper.stepSqlDone()
        sqliteWrapper.finalizeSql()
        //        sqliteWrapper.closeDb()
        objc_sync_exit(sqliteWrapper)
        return true
    }
    
    /// 删除对应组扩展数据
    /// - Parameters:
    ///   - meshUUID: 所属网络id
    ///   - address: 组地址
    /// - Returns: 是否成功
    @discardableResult static func delete(meshUUID: String, address: UInt16) -> Bool {
        
        objc_sync_enter(sqliteWrapper)
        guard sqliteWrapper.isOpen || sqliteWrapper.openDb(sqliteDBName), sqliteWrapper.prepareSql(DELETE_GROUP_INFO) else {
            objc_sync_exit(sqliteWrapper)
            return false
        }
        
        sqliteWrapper.bindText(1, text: meshUUID)
        sqliteWrapper.bindInt(2, integer: sqlite3_int64(address))
        
        sqliteWrapper.stepSqlDone()
        sqliteWrapper.finalizeSql()
        //        sqliteWrapper.closeDb()
        objc_sync_exit(sqliteWrapper)
        return true
    }
    
    /// 缓存对应组扩展数据
    /// - Parameters:
    ///   - meshUUID: 所属网络id
    ///   - groupAddress: 组地址
    /// - Returns: 是否成功
    @discardableResult func save(meshUUID: String) -> Bool {
        
        objc_sync_enter(sqliteWrapper)
        guard sqliteWrapper.isOpen || sqliteWrapper.openDb(sqliteDBName), sqliteWrapper.prepareSql(GroupInfo.SAVE_GROUPS_INFO) else {
            objc_sync_exit(sqliteWrapper)
            return false
        }
        
        sqliteWrapper.bindText(1, text: name)
        sqliteWrapper.bindInt(2, integer: sqlite3_int64(address))
        sqliteWrapper.bindText(3, text: meshUUID)
        sqliteWrapper.bindInt(4, integer: sqlite3_int64(imageId))
//        if imageText != nil {
            sqliteWrapper.bindText(5, text: imageText)
        sqliteWrapper.bindText(6, text: profile.id)
        if let node = ambientLightSensorNode {
            sqliteWrapper.bindInt(7, integer: sqlite3_int64(node.primaryUnicastAddress))
        }else {
            sqliteWrapper.bindInt(7, integer: sqlite3_int64(-1))
        }
        
//        }
        sqliteWrapper.stepSqlDone()
        sqliteWrapper.resetSql()
        sqliteWrapper.finalizeSql()
        //        sqliteWrapper.closeDb()
        
        objc_sync_exit(sqliteWrapper)
        
        return true
    }
    
}

extension SceneInfo {
    
    private static let CREAT_TABLE_SCENES_INFO = "CREATE TABLE IF NOT EXISTS SCENES_INFO(SCENES_INFO_ROW INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, SCENE_NAME TEXT, SCENE_ID INTEGER, MESH_UUID TEXT, SCENE_IMAGE_ID INTEGER)"
    
    private static let CREATE_IDX_SCENES_INFO = "CREATE UNIQUE INDEX IF NOT EXISTS IDX_SCENES_INFO ON SCENES_INFO(MESH_UUID, SCENE_ID)"
    
    private static let SAVE_SCENES_INFO = "INSERT OR REPLACE INTO SCENES_INFO(SCENE_NAME, SCENE_ID, MESH_UUID, SCENE_IMAGE_ID) VALUES(?, ?, ?, ?)"

    private static let GET_SCENES_INFO = "SELECT SCENE_NAME, SCENE_ID, MESH_UUID, SCENE_IMAGE_ID FROM SCENES_INFO WHERE MESH_UUID = ?"
    
    private static let GET_SCENE_INFO_BY_ID = "SELECT SCENE_NAME, SCENE_ID, MESH_UUID, SCENE_IMAGE_ID FROM SCENES_INFO WHERE MESH_UUID = ? AND SCENE_ID = ?"
    
    private static let DELETE_SCENES_INFO = "DELETE FROM SCENES_INFO WHERE MESH_UUID = ?"
    
    private static let DELETE_SCENE_INFO = "DELETE FROM SCENES_INFO WHERE MESH_UUID = ? AND SCENE_ID = ?"
    
    
    /// 初始化数据库缓存
    static func createDatabaseIfNotExit() {
        objc_sync_enter(sqliteWrapper)
        if sqliteWrapper.isOpen || sqliteWrapper.openDb(sqliteDBName) {
            sqliteWrapper.execSql(CREAT_TABLE_SCENES_INFO)
            sqliteWrapper.execSql(CREATE_IDX_SCENES_INFO)
            //        sqliteWrapper.closeDb()
        }
        objc_sync_exit(sqliteWrapper)
    }
    
    /// 根据网络id和场景id获取对应场景信息
    /// - Parameter meshUUID: 网络id
    /// - Parameter sceneId: 场景id
    /// - Returns: 场景数据
    static func load(meshUUID: String, sceneId: Int) -> SceneInfo? {
        objc_sync_enter(sqliteWrapper)
        guard sqliteWrapper.isOpen || sqliteWrapper.openDb(sqliteDBName), sqliteWrapper.prepareSql(GET_SCENE_INFO_BY_ID) else {
            objc_sync_exit(sqliteWrapper)
            return nil
        }
        sqliteWrapper.bindText(1, text: meshUUID)
        sqliteWrapper.bindInt(2, integer: sqlite3_int64(sceneId))
        
        var sceneInfo: SceneInfo?
        while sqliteWrapper.stepSqlRow() {
            
            let sceneId = sqliteWrapper.columnInt(1)
            let imageId = sqliteWrapper.columnInt(3)
            
            sceneInfo = SceneInfo(sceneId: UInt16(sceneId), imageId: Int(imageId))
            if let name = sqliteWrapper.columnText(0) {
                sceneInfo!.name = name
            }
        }
        sqliteWrapper.finalizeSql()
        //        sqliteWrapper.closeDb()
        objc_sync_exit(sqliteWrapper)
        
        // 获取场景下面的组
        let targetAddresss = SceneExecuteData.loadAll(meshUUID: meshUUID, sceneId: Int(sceneId)).map({ $0.address })
        
        var groups = targetAddresss.compactMap({ MeshNetworkManager.instance.meshNetwork?.group(withAddress: MeshAddress($0)) })
        groups.sort(by: { $0.address.address < $1.address.address })
        sceneInfo?.groups = groups
        return sceneInfo
    }
    
    /// 删除所有场景扩展数据
    /// - Parameter meshUUID: 对应网络id
    /// - Returns: 是否成功
    @discardableResult static func deleteAll(meshUUID: String) -> Bool {
        
        objc_sync_enter(sqliteWrapper)
        guard sqliteWrapper.isOpen || sqliteWrapper.openDb(sqliteDBName), sqliteWrapper.prepareSql(DELETE_SCENES_INFO) else {
            objc_sync_exit(sqliteWrapper)
            return false
        }
        sqliteWrapper.bindText(1, text: meshUUID)
        sqliteWrapper.stepSqlDone()
        sqliteWrapper.finalizeSql()
        //        sqliteWrapper.closeDb()
        objc_sync_exit(sqliteWrapper)
        return true
    }
    
    /// 删除对应场景扩展数据
    /// - Parameters:
    ///   - meshUUID: 所属网络id
    ///   - sceneId: 场景id
    /// - Returns: 是否成功
    @discardableResult static func delete(meshUUID: String, sceneId: UInt16) -> Bool {
        
        objc_sync_enter(sqliteWrapper)
        guard sqliteWrapper.isOpen || sqliteWrapper.openDb(sqliteDBName), sqliteWrapper.prepareSql(DELETE_SCENE_INFO) else {
            objc_sync_exit(sqliteWrapper)
            return false
        }
        
        sqliteWrapper.bindText(1, text: meshUUID)
        sqliteWrapper.bindInt(2, integer: sqlite3_int64(sceneId))
        
        sqliteWrapper.stepSqlDone()
        sqliteWrapper.finalizeSql()
        //        sqliteWrapper.closeDb()
        objc_sync_exit(sqliteWrapper)
        return true
    }
    
    /// 缓存对应场景扩展数据
    /// - Parameters:
    ///   - meshUUID: 所属网络id
    ///   - sceneId: 场景id
    /// - Returns: 是否成功
    @discardableResult func save(meshUUID: String) -> Bool {
        
        objc_sync_enter(sqliteWrapper)
        guard sqliteWrapper.isOpen || sqliteWrapper.openDb(sqliteDBName), sqliteWrapper.prepareSql(SceneInfo.SAVE_SCENES_INFO) else {
            objc_sync_exit(sqliteWrapper)
            return false
        }
        
        sqliteWrapper.bindText(1, text: name)
        sqliteWrapper.bindInt(2, integer: sqlite3_int64(sceneId))
        sqliteWrapper.bindText(3, text: meshUUID)
        sqliteWrapper.bindInt(4, integer: sqlite3_int64(imageId))

        sqliteWrapper.stepSqlDone()
        sqliteWrapper.resetSql()
        sqliteWrapper.finalizeSql()
        //        sqliteWrapper.closeDb()
        
        objc_sync_exit(sqliteWrapper)
        
        return true
    }
    
    
    
    
}

extension SceneExecuteData {
    
    private static let CREAT_TABLE_SCENE_DATA = "CREATE TABLE IF NOT EXISTS SCENE_DATA(SCENE_DATA_ROW INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, TARGET_ADDRESS INTEGER, SCENE_ID INTEGER, MESH_UUID TEXT, SCENE_LIGHTNESS INTEGER, SCENE_CCT INTEGER, SCENE_STATE INTEGER)"
    
    private static let CREATE_IDX_SCENE_DATA = "CREATE UNIQUE INDEX IF NOT EXISTS IDX_SCENE_DATA ON SCENE_DATA(TARGET_ADDRESS, SCENE_ID, MESH_UUID)"
    
    private static let SAVE_SCENE_DATA = "INSERT OR REPLACE INTO SCENE_DATA(TARGET_ADDRESS, SCENE_ID, MESH_UUID, SCENE_LIGHTNESS, SCENE_CCT, SCENE_STATE) VALUES(?, ?, ?, ?, ?, ?)"

    private static let GET_SCENES_DATA = "SELECT TARGET_ADDRESS, SCENE_ID, MESH_UUID, SCENE_LIGHTNESS, SCENE_CCT, SCENE_STATE FROM SCENE_DATA WHERE MESH_UUID = ? AND TARGET_ADDRESS = ?"
    
    static let GET_TARGETS_SCENES_DATA = "SELECT TARGET_ADDRESS, SCENE_ID, MESH_UUID, SCENE_LIGHTNESS, SCENE_CCT, SCENE_STATE FROM SCENE_DATA WHERE MESH_UUID = ? AND SCENE_ID = ?"
    
    private static let GET_SCENE_DATA_BY_ID = "SELECT TARGET_ADDRESS, SCENE_ID, MESH_UUID, SCENE_LIGHTNESS, SCENE_CCT, SCENE_STATE FROM SCENE_DATA WHERE MESH_UUID = ? AND TARGET_ADDRESS = ? AND SCENE_ID = ?"
    
    private static let DELETE_SCENES_DATA = "DELETE FROM SCENE_DATA WHERE MESH_UUID = ?"
    
    private static let DELETE_SCENES_DATA_BY_ID = "DELETE FROM SCENE_DATA WHERE MESH_UUID = ? AND TARGET_ADDRESS = ?"
    
    private static let DELETE_SCENE_DATA = "DELETE FROM SCENE_DATA WHERE MESH_UUID = ? AND TARGET_ADDRESS = ? AND SCENE_ID = ?"
    
    
    /// 初始化数据库缓存
    static func createDatabaseIfNotExit() {
        objc_sync_enter(sqliteWrapper)
        if sqliteWrapper.isOpen || sqliteWrapper.openDb(sqliteDBName) {
            sqliteWrapper.execSql(SceneExecuteData.CREAT_TABLE_SCENE_DATA)
            sqliteWrapper.execSql(SceneExecuteData.CREATE_IDX_SCENE_DATA)
            //        sqliteWrapper.closeDb()
        }
        objc_sync_exit(sqliteWrapper)
    }
 
    /// 根据mesh uuid及sceneId获取场景下关联目标地址及执行数据
    /// - Parameter meshUUID: 网络id
    /// - Parameter sceneId: 对应场景
    /// - Returns: 目标地址，执行数据
    static func loadAll(meshUUID: String, sceneId: Int) -> [(address: UInt16, data: SceneExecuteData)] {
        
        objc_sync_enter(sqliteWrapper)
        guard sqliteWrapper.isOpen || sqliteWrapper.openDb(sqliteDBName), sqliteWrapper.prepareSql(GET_TARGETS_SCENES_DATA) else {
            objc_sync_exit(sqliteWrapper)
            return []
        }
        sqliteWrapper.bindText(1, text: meshUUID)
        sqliteWrapper.bindInt(2, integer: sqlite3_int64(sceneId))
        
        var sceneDatas: [(address: UInt16, data: SceneExecuteData)] = []
        while sqliteWrapper.stepSqlRow() {
            
            let targetAddress = UInt16(sqliteWrapper.columnInt(0))
//            let sceneId = Int(sqliteWrapper.columnInt(1))
            let lightness = Int(sqliteWrapper.columnInt(2))
            let cct = Int(sqliteWrapper.columnInt(3))
            let state = Int(sqliteWrapper.columnInt(4))
            let sceneData = SceneExecuteData(lightness: lightness, cct: cct, state: .init(rawValue: state) ?? .normal)
            sceneDatas.append((targetAddress, sceneData))
        }
      
        sqliteWrapper.finalizeSql()
        //        sqliteWrapper.closeDb()
        objc_sync_exit(sqliteWrapper)

        return sceneDatas
        
    }
    
    /// 根据mesh uuid及groupAddress /  deviceAddress获取网络下的所有配置的场景数据
    /// - Parameter meshUUID: 网络id
    /// - Parameter address: 对应地址（组地址/设备地址）
    /// - Returns: 场景id，场景数据
    static func loadAll(meshUUID: String, address: UInt16) -> [(sceneId: Int, data: SceneExecuteData)] {
        objc_sync_enter(sqliteWrapper)
        guard sqliteWrapper.isOpen || sqliteWrapper.openDb(sqliteDBName), sqliteWrapper.prepareSql(GET_SCENES_DATA) else {
            objc_sync_exit(sqliteWrapper)
            return []
        }
        sqliteWrapper.bindText(1, text: meshUUID)
        sqliteWrapper.bindInt(2, integer: sqlite3_int64(address))
        
        var sceneDatas: [(sceneId: Int, data: SceneExecuteData)] = []
        while sqliteWrapper.stepSqlRow() {
            
//            let groupAddress = UInt16(sqliteWrapper.columnInt(0))
            let sceneId = Int(sqliteWrapper.columnInt(1))
            let lightness = Int(sqliteWrapper.columnInt(3))
            let cct = Int(sqliteWrapper.columnInt(4))
            let state = Int(sqliteWrapper.columnInt(5))
            let sceneData = SceneExecuteData(lightness: lightness, cct: cct, state: .init(rawValue: Int(state)) ?? .normal)
            sceneDatas.append((sceneId, sceneData))
        }
      
        sqliteWrapper.finalizeSql()
        //        sqliteWrapper.closeDb()
        objc_sync_exit(sqliteWrapper)

        return sceneDatas
    }
    
    /// 根据网络id获取对应配置的场景数据
    /// - Parameter meshUUID: 网络id
    /// - Parameter address: 对应地址（组地址/设备地址）
    /// - Parameter sceneId: 场景id
    /// - Returns: 场景数据
    static func load(meshUUID: String, address: UInt16, sceneId: Int) -> SceneExecuteData? {
        objc_sync_enter(sqliteWrapper)
        guard sqliteWrapper.isOpen || sqliteWrapper.openDb(sqliteDBName), sqliteWrapper.prepareSql(GET_SCENE_DATA_BY_ID) else {
            objc_sync_exit(sqliteWrapper)
            return nil
        }
        sqliteWrapper.bindText(1, text: meshUUID)
        sqliteWrapper.bindInt(2, integer: sqlite3_int64(address))
        sqliteWrapper.bindInt(3, integer: sqlite3_int64(sceneId))
        
        var sceneData: SceneExecuteData?
        while sqliteWrapper.stepSqlRow() {
            let lightness = sqliteWrapper.columnInt(3)
            let cct = sqliteWrapper.columnInt(4)
            let state = sqliteWrapper.columnInt(5)
            
            sceneData = SceneExecuteData(lightness: Int(lightness), cct: Int(cct), state: .init(rawValue: Int(state)) ?? .normal)
        }
        sqliteWrapper.finalizeSql()
        //        sqliteWrapper.closeDb()
        objc_sync_exit(sqliteWrapper)
        return sceneData
    }
    
 
    /// 删除所有配置的场景数据
    /// - Parameter meshUUID: 对应网络id
    /// - Returns: 是否成功
    @discardableResult static func deleteAll(meshUUID: String) -> Bool {
        
        objc_sync_enter(sqliteWrapper)
        guard sqliteWrapper.isOpen || sqliteWrapper.openDb(sqliteDBName), sqliteWrapper.prepareSql(DELETE_SCENES_DATA) else {
            objc_sync_exit(sqliteWrapper)
            return false
        }
        sqliteWrapper.bindText(1, text: meshUUID)
        sqliteWrapper.stepSqlDone()
        sqliteWrapper.finalizeSql()
        //        sqliteWrapper.closeDb()
        objc_sync_exit(sqliteWrapper)
        return true
    }
    
    /// 删除对应组配置的场景数据
    /// - Parameters:
    ///   - meshUUID: 所属网络id
    ///   - address: 对应地址（组地址/设备地址）
    ///   - sceneId: 删除对应场景数据，否则删除改地址下所有配置的场景数据
    /// - Returns: 是否成功
    @discardableResult static func deleteData(meshUUID: String, address: UInt16, sceneId: Int? = nil) -> Bool {
        
        objc_sync_enter(sqliteWrapper)
        guard sqliteWrapper.isOpen || sqliteWrapper.openDb(sqliteDBName) else {
            objc_sync_exit(sqliteWrapper)
            return false
        }
        
        if let sceneId = sceneId {
            guard sqliteWrapper.prepareSql(DELETE_SCENE_DATA) else {
                objc_sync_exit(sqliteWrapper)
                return false
            }
            sqliteWrapper.bindInt(3, integer: sqlite3_int64(sceneId))
        }else {
            guard sqliteWrapper.prepareSql(DELETE_SCENES_DATA_BY_ID) else {
                objc_sync_exit(sqliteWrapper)
                return false
            }
        }
        sqliteWrapper.bindText(1, text: meshUUID)
        sqliteWrapper.bindInt(2, integer: sqlite3_int64(address))
        
        sqliteWrapper.stepSqlDone()
        sqliteWrapper.finalizeSql()
        //        sqliteWrapper.closeDb()
        objc_sync_exit(sqliteWrapper)
        return true
    }
    
    /// 缓存对应场景配置数据
    /// - Parameters:
    ///   - meshUUID: 所属网络id
    ///   - groupAddress: 组地址
    ///   - sceneId: 场景id
    ///   - sceneData: 场景数据
    /// - Returns: 是否成功
    @discardableResult static func save(meshUUID: String, address: UInt16, sceneId: Int, sceneData: SceneExecuteData) -> Bool {
        
        objc_sync_enter(sqliteWrapper)
        guard sqliteWrapper.isOpen || sqliteWrapper.openDb(sqliteDBName), sqliteWrapper.prepareSql(SAVE_SCENE_DATA) else {
            objc_sync_exit(sqliteWrapper)
            return false
        }
        
        sqliteWrapper.bindInt(1, integer: sqlite3_int64(address))
        sqliteWrapper.bindInt(2, integer: sqlite3_int64(sceneId))
        sqliteWrapper.bindText(3, text: meshUUID)
        sqliteWrapper.bindInt(4, integer: sqlite3_int64(sceneData.lightness))
        sqliteWrapper.bindInt(5, integer: sqlite3_int64(sceneData.cct))
        sqliteWrapper.bindInt(6, integer: sqlite3_int64(sceneData.state.rawValue))
        
        sqliteWrapper.stepSqlDone()
        sqliteWrapper.resetSql()
        sqliteWrapper.finalizeSql()
        //        sqliteWrapper.closeDb()
        
        objc_sync_exit(sqliteWrapper)
        
        return true
    }
    
}

extension Schedule {
    
    private static let CREAT_TABLE_SCHEDULES = "CREATE TABLE IF NOT EXISTS SCHEDULES(SCHEDULE_ROW INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, SCHEDULE_NAME TEXT, SCHEDULE_ID TEXT, MESH_UUID TEXT, SCHEDULE_CREATE TEXT, SCHEDULE_LASTUPDATE TEXT, SCHEDULE_ENABLED BOOL, DEVICE_ADDRESS TEXT, GROUP_ADDRESS TEXT, DELETE_DEVICE_ADDRESS TEXT, DELETE_GROUP_ADDRESS TEXT, SCENE_ID INTEGER, DELETE_SCENES TEXT, SELECT_TYPE INTEGER, ACTION_TYPE INTEGER, FADETIME INTEGER, WEEKDAYS INTEGER, HOUR INTEGER, MINUTE INTEGER, SECOND INTEGER)"
    
    private static let CREATE_IDX_SCHEDULES_SCHEDULE = "CREATE UNIQUE INDEX IF NOT EXISTS IDX_SCHEDULES_SCHEDULE ON SCHEDULES(SCHEDULE_ID, MESH_UUID)"
    
    private static let SAVE_SCHEDULES = "INSERT OR REPLACE INTO SCHEDULES(SCHEDULE_NAME, SCHEDULE_ID, MESH_UUID, SCHEDULE_CREATE, SCHEDULE_LASTUPDATE, SCHEDULE_ENABLED, DEVICE_ADDRESS, GROUP_ADDRESS, DELETE_DEVICE_ADDRESS, DELETE_GROUP_ADDRESS, SCENE_ID, DELETE_SCENES, SELECT_TYPE, ACTION_TYPE, FADETIME, WEEKDAYS, HOUR, MINUTE, SECOND) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"

    private static let GET_SCHEDULES = "SELECT SCHEDULE_NAME, SCHEDULE_ID, MESH_UUID, SCHEDULE_CREATE, SCHEDULE_LASTUPDATE, SCHEDULE_ENABLED, DEVICE_ADDRESS, GROUP_ADDRESS, DELETE_DEVICE_ADDRESS, DELETE_GROUP_ADDRESS, SCENE_ID, DELETE_SCENES, SELECT_TYPE, ACTION_TYPE, FADETIME, WEEKDAYS, HOUR, MINUTE, SECOND FROM SCHEDULES WHERE MESH_UUID = ?"
    
    private static let GET_SCHEDULE_BY_ID = "SELECT SCHEDULE_NAME, SCHEDULE_ID, MESH_UUID, SCHEDULE_CREATE, SCHEDULE_LASTUPDATE, SCHEDULE_ENABLED, DEVICE_ADDRESS, GROUP_ADDRESS, DELETE_DEVICE_ADDRESS, DELETE_GROUP_ADDRESS, SCENE_ID, DELETE_SCENES, SELECT_TYPE, ACTION_TYPE, FADETIME, WEEKDAYS, HOUR, MINUTE, SECOND FROM SCHEDULES WHERE MESH_UUID = ? AND SCHEDULE_ID = ?"
    
    private static let GET_NEXT_SCHEDULE_NAME = "SELECT SPACE_NAME FROM SCHEDULES WHERE MESH_UUID = ? AND SCHEDULE_NAME LIKE ?"
    
    private static let GET_TAUTONY_SCHEDULE_NAME = "SELECT SPACE_NAME FROM SCHEDULES WHERE MESH_UUID = ? AND SCHEDULE_NAME = ?"

    private static let DELETE_SCHEDULES = "DELETE FROM SCHEDULES WHERE MESH_UUID = ?"
    
    private static let DELETE_SCHEDULE = "DELETE FROM SCHEDULES WHERE MESH_UUID = ? AND SCHEDULE_ID = ?"
//    needDelete
    
    /// 初始化数据库缓存
    static func createDatabaseIfNotExit() {
        objc_sync_enter(sqliteWrapper)
        if sqliteWrapper.isOpen || sqliteWrapper.openDb(sqliteDBName) {
            sqliteWrapper.execSql(CREAT_TABLE_SCHEDULES)
            sqliteWrapper.execSql(CREATE_IDX_SCHEDULES_SCHEDULE)
            //        sqliteWrapper.closeDb()
        }
        objc_sync_exit(sqliteWrapper)
    }
 
    /// 根据mesh uuid获取网络下的所有的日程数据
    /// - Parameter meshUUID: 网络id
    /// - Returns: 日程数据list
    static func loadAll(meshUUID: String) -> [Schedule] {
        objc_sync_enter(sqliteWrapper)
        guard sqliteWrapper.isOpen || sqliteWrapper.openDb(sqliteDBName), sqliteWrapper.prepareSql(GET_SCHEDULES) else {
            objc_sync_exit(sqliteWrapper)
            return []
        }
        sqliteWrapper.bindText(1, text: meshUUID)
        
        var schedules: [Schedule] = []
        while sqliteWrapper.stepSqlRow() {
            
            let deviceAddressStr = sqliteWrapper.columnText(6)
            let groupAddressStr = sqliteWrapper.columnText(7)
            let deleteDeviceAddressStr = sqliteWrapper.columnText(8)
            let deleteGroupAddressStr = sqliteWrapper.columnText(9)
            let sceneId = UInt16(sqliteWrapper.columnInt(10))
            let deleteSceneStr = sqliteWrapper.columnText(11)
            let selectTargetType = Int(sqliteWrapper.columnInt(12))
            let actionType = UInt8(sqliteWrapper.columnInt(13))
            let fadeTime = Int(sqliteWrapper.columnInt(14))
            let weekDaysValue = Int(sqliteWrapper.columnInt(15))
            let hour = Int(sqliteWrapper.columnInt(16))
            let minute = Int(sqliteWrapper.columnInt(17))
            // 计算选中的重复周期
            let allWeekDays: [WeekDay] = [.Monday, .Tuesday, .Wednesday, .Thursday, .Friday, .Saturday, .Sunday]
            var selectWeekDays: [WeekDay] = []
            for (weekInt, weekDay) in allWeekDays.enumerated() {
                if weekDaysValue >> weekInt & 1 == 1 {
                    selectWeekDays.append(weekDay)
                }
            }
            
            var groups: [Group] = []
            var deleteGroups: [Group] = []
            var nodes: [Node] = []
            var deleteNodes: [Node] = []
            var scene: Scene?
            var deleteScenes: [Scene] = []
            if meshUUID == MeshNetworkManager.instance.meshNetwork?.uuid.uuidString {
                // 获取对应的组 "组地址0,组地址1..."
                groups = groupAddressStr?.components(separatedBy: ",").compactMap({ MeshNetworkManager.instance.meshNetwork?.group(withAddress: UInt16($0) ?? 0) }) ?? []
                deleteGroups = deleteGroupAddressStr?.components(separatedBy: ",").compactMap({ MeshNetworkManager.instance.meshNetwork?.group(withAddress: UInt16($0) ?? 0) }) ?? []
                
                // 获取对应的设备 "设备地址0,设备地址1..."
                nodes = deviceAddressStr?.components(separatedBy: ",").compactMap({ MeshNetworkManager.instance.meshNetwork?.node(withAddress: UInt16($0) ?? 0) }) ?? []
                deleteNodes = deleteDeviceAddressStr?.components(separatedBy: ",").compactMap({ MeshNetworkManager.instance.meshNetwork?.node(withAddress: UInt16($0) ?? 0) }) ?? []
                
                // 获取对应的场景
                scene = MeshNetworkManager.instance.scenes.first(where: { $0.number == sceneId })
                // 获取对应待删除的场景"场景地址0,场景地址1..."
                deleteScenes = deleteSceneStr?.components(separatedBy: ",").compactMap({ sceneId in
                    MeshNetworkManager.instance.scenes.first(where: { $0.number == SceneNumber(UInt16(sceneId) ?? 0) })
                }) ?? []
                
            }
           
            let schedule = Schedule(id: Int(sqliteWrapper.columnInt(1)), name: sqliteWrapper.columnText(0), enabled: sqliteWrapper.columnBool(5), nodes: nodes, groups: groups, scene: scene, action: SchedulerAction(rawValue: actionType) ?? .noAction, fadeTime: fadeTime, weekDays: selectWeekDays, hour: hour, minute: minute, create: sqliteWrapper.columnText(3), lastUpdate: sqliteWrapper.columnText(4))
            schedule.selectTargetType = .init(rawValue: selectTargetType) ?? .groups
            schedule.needDeleteGroups = deleteGroups
            schedule.needDeleteNodes = deleteNodes
            schedule.needDeleteScenes = deleteScenes
            schedules.append(schedule)
        }
      
        sqliteWrapper.finalizeSql()
        //        sqliteWrapper.closeDb()
        objc_sync_exit(sqliteWrapper)

        return schedules
    }
    
    /// 根据网络id及获取对应配置的场景数据
    /// - Parameter meshUUID: 网络id
    /// - Parameter scheduleId: 日程id
    /// - Returns: 日程数据
    static func load(meshUUID: String, scheduleId: Int) -> Schedule? {
        objc_sync_enter(sqliteWrapper)
        guard sqliteWrapper.isOpen || sqliteWrapper.openDb(sqliteDBName), sqliteWrapper.prepareSql(GET_SCHEDULE_BY_ID) else {
            objc_sync_exit(sqliteWrapper)
            return nil
        }
        sqliteWrapper.bindText(1, text: meshUUID)
        sqliteWrapper.bindInt(2, integer: sqlite3_int64(scheduleId))
        
        var sceneData: Schedule?
        while sqliteWrapper.stepSqlRow() {
            let deviceAddressStr = sqliteWrapper.columnText(6)
            let groupAddressStr = sqliteWrapper.columnText(7)
            let deleteDeviceAddressStr = sqliteWrapper.columnText(8)
            let deleteGroupAddressStr = sqliteWrapper.columnText(9)
            let sceneId = UInt16(sqliteWrapper.columnInt(10))
            let deleteSceneStr = sqliteWrapper.columnText(11)
            let selectTargetType = Int(sqliteWrapper.columnInt(12))
            let actionType = UInt8(sqliteWrapper.columnInt(13))
            let fadeTime = Int(sqliteWrapper.columnInt(14))
            let weekDaysValue = Int(sqliteWrapper.columnInt(15))
            let hour = Int(sqliteWrapper.columnInt(16))
            let minute = Int(sqliteWrapper.columnInt(17))
            // 计算选中的重复周期
            let allWeekDays: [WeekDay] = [.Monday, .Tuesday, .Wednesday, .Thursday, .Friday, .Saturday, .Sunday]
            var selectWeekDays: [WeekDay] = []
            for (weekInt, weekDay) in allWeekDays.enumerated() {
                if weekDaysValue >> weekInt & 1 == 1 {
                    selectWeekDays.append(weekDay)
                }
            }
            
            var groups: [Group] = []
            var deleteGroups: [Group] = []
            var nodes: [Node] = []
            var deleteNodes: [Node] = []
            var scene: Scene?
            var deleteScenes: [Scene] = []
            if meshUUID == MeshNetworkManager.instance.meshNetwork?.uuid.uuidString {
                // 获取对应的组 "组地址0,组地址1..."
                groups = groupAddressStr?.components(separatedBy: ",").compactMap({ MeshNetworkManager.instance.meshNetwork?.group(withAddress: UInt16($0) ?? 0) }) ?? []
                deleteGroups = deleteGroupAddressStr?.components(separatedBy: ",").compactMap({ MeshNetworkManager.instance.meshNetwork?.group(withAddress: UInt16($0) ?? 0) }) ?? []
                
                // 获取对应的设备 "设备地址0,设备地址1..."
                nodes = deviceAddressStr?.components(separatedBy: ",").compactMap({ MeshNetworkManager.instance.meshNetwork?.node(withAddress: UInt16($0) ?? 0) }) ?? []
                deleteNodes = deleteDeviceAddressStr?.components(separatedBy: ",").compactMap({ MeshNetworkManager.instance.meshNetwork?.node(withAddress: UInt16($0) ?? 0) }) ?? []
                // 获取对应的场景
                scene = MeshNetworkManager.instance.scenes.first(where: { $0.number == sceneId })
                // 获取对应待删除的场景"场景地址0,场景地址1..."
                deleteScenes = deleteSceneStr?.components(separatedBy: ",").compactMap({ sceneId in
                    MeshNetworkManager.instance.scenes.first(where: { $0.number == SceneNumber(UInt16(sceneId) ?? 0) })
                }) ?? []
            }
           
            sceneData = Schedule(id: Int(sqliteWrapper.columnInt(1)), name: sqliteWrapper.columnText(0), enabled: sqliteWrapper.columnBool(5), nodes: nodes, groups: groups, scene: scene, action: SchedulerAction(rawValue: actionType) ?? .noAction, fadeTime: fadeTime, weekDays: selectWeekDays, hour: hour, minute: minute, create: sqliteWrapper.columnText(3), lastUpdate: sqliteWrapper.columnText(4))
            sceneData?.needDeleteNodes = deleteNodes
            sceneData?.needDeleteGroups = deleteGroups
            sceneData?.needDeleteScenes = deleteScenes
            sceneData?.selectTargetType = .init(rawValue: selectTargetType) ?? .groups
        }
        sqliteWrapper.finalizeSql()
        //        sqliteWrapper.closeDb()
        objc_sync_exit(sqliteWrapper)
        return sceneData
    }
    
    /// 根据组地址/设备地址获取关联的日程list
    static func loadAll(meshUUID: String, address: UInt16) -> [Schedule] {
        
        let schedules = loadAll(meshUUID: meshUUID)
        let bindSchedules = schedules.filter({
            $0.groups.contains(where: { $0.address.address == address }) ||
            $0.needDeleteGroups.contains(where: { $0.address.address == address }) ||
            $0.nodes.contains(where: { $0.primaryUnicastAddress == address }) ||
            $0.needDeleteNodes.contains(where: { $0.primaryUnicastAddress == address })
        })
        return bindSchedules
    }
    
    static func loadAll(meshUUID: String, sceneNumber: SceneNumber) -> [Schedule] {
        let schedules = loadAll(meshUUID: meshUUID)
        let bindSchedules = schedules.filter({
            $0.scene?.number == sceneNumber
//            $0.needDeleteGroups.contains(where: { $0.address.address == address }) ||
        })
        return bindSchedules
    }
 
    /// 删除网络内所有配置的日程数据
    /// - Parameter meshUUID: 对应网络id
    /// - Returns: 是否成功
    @discardableResult static func deleteAll(meshUUID: String) -> Bool {
        
        objc_sync_enter(sqliteWrapper)
        guard sqliteWrapper.isOpen || sqliteWrapper.openDb(sqliteDBName), sqliteWrapper.prepareSql(DELETE_SCHEDULES) else {
            objc_sync_exit(sqliteWrapper)
            return false
        }
        sqliteWrapper.bindText(1, text: meshUUID)
        sqliteWrapper.stepSqlDone()
        sqliteWrapper.finalizeSql()
        //        sqliteWrapper.closeDb()
        objc_sync_exit(sqliteWrapper)
        return true
    }
    
    /// 删除网络内对应配置的日程数据
    /// - Parameters:
    ///   - meshUUID: 所属网络id
    ///   - scheduleId: 日程id
    /// - Returns: 是否成功
    @discardableResult static func deleteData(meshUUID: String, scheduleId: Int) -> Bool {
        
        objc_sync_enter(sqliteWrapper)
        guard sqliteWrapper.isOpen || sqliteWrapper.openDb(sqliteDBName), sqliteWrapper.prepareSql(Schedule.DELETE_SCHEDULE) else {
            objc_sync_exit(sqliteWrapper)
            return false
        }
        
        sqliteWrapper.bindText(1, text: meshUUID)
        sqliteWrapper.bindInt(2, integer: sqlite3_int64(scheduleId))
        sqliteWrapper.stepSqlDone()
        sqliteWrapper.finalizeSql()
        //        sqliteWrapper.closeDb()
        objc_sync_exit(sqliteWrapper)
        return true
    }
    
    /// 缓存对应场景配置数据
    /// - Parameters:
    ///   - meshUUID: 所属网络id
    ///   - groupAddress: 组地址
    ///   - sceneId: 场景id
    ///   - sceneData: 场景数据
    /// - Returns: 是否成功
    @discardableResult func save(meshUUID: String) -> Bool {
        
        objc_sync_enter(sqliteWrapper)
        guard sqliteWrapper.isOpen || sqliteWrapper.openDb(sqliteDBName), sqliteWrapper.prepareSql(Schedule.SAVE_SCHEDULES) else {
            objc_sync_exit(sqliteWrapper)
            return false
        }
        
        sqliteWrapper.bindText(1, text: name)
        sqliteWrapper.bindInt(2, integer: sqlite3_int64(id))
        sqliteWrapper.bindText(3, text: meshUUID)
        sqliteWrapper.bindText(4, text: create)
        sqliteWrapper.bindText(5, text: lastUpdate)
        sqliteWrapper.bindBool(6, boolean: enabled)
        var groupAddressStr = ""
        var deleteGroupAddressStr = ""
        groups.forEach({ groupAddressStr += "\(groupAddressStr.isEmpty ? "" : ",")\($0.address.address)" })
        needDeleteGroups.forEach({ deleteGroupAddressStr += "\(deleteGroupAddressStr.isEmpty ? "" : ",")\($0.address.address)" })
        var nodeAddressStr = ""
        var deleteNodeAddressStr = ""
        nodes.forEach({ nodeAddressStr += "\(nodeAddressStr.isEmpty ? "" : ",")\($0.primaryUnicastAddress)" })
        needDeleteNodes.forEach({ deleteNodeAddressStr += "\(deleteNodeAddressStr.isEmpty ? "" : ",")\($0.primaryUnicastAddress)" })
        var deleteSceneIdStr = ""
        needDeleteScenes.forEach({ deleteSceneIdStr += "\(deleteSceneIdStr.isEmpty ? "" : ",")\($0.number)" })
        
        sqliteWrapper.bindText(7, text: nodeAddressStr)
        sqliteWrapper.bindText(8, text: groupAddressStr)
        sqliteWrapper.bindText(9, text: deleteNodeAddressStr)
        sqliteWrapper.bindText(10, text: deleteGroupAddressStr)
        sqliteWrapper.bindInt(11, integer: sqlite3_int64(scene?.number ?? 0))
        sqliteWrapper.bindText(12, text: deleteSceneIdStr)
        sqliteWrapper.bindInt(13, integer: sqlite3_int64(selectTargetType.rawValue))
        sqliteWrapper.bindInt(14, integer: sqlite3_int64(action.rawValue))
        sqliteWrapper.bindInt(15, integer: sqlite3_int64(fadeTime))
        var weekdayValue = 0
        weekDays.forEach({ weekdayValue += Int($0.rawValue) })
        sqliteWrapper.bindInt(16, integer: sqlite3_int64(weekdayValue))
        sqliteWrapper.bindInt(17, integer: sqlite3_int64(hour))
        sqliteWrapper.bindInt(18, integer: sqlite3_int64(minute))
        
        sqliteWrapper.stepSqlDone()
        sqliteWrapper.resetSql()
        sqliteWrapper.finalizeSql()
        //        sqliteWrapper.closeDb()
        
        objc_sync_exit(sqliteWrapper)
        
        return true
    }
    
    /// 获取下一个schedule名称
    /// - Parameter defalutName: 默认名称
    /// - Returns: 日程名称
    static func getNextScheduleName(meshUUID: String, defalutName: String = "schedule_defalut_name".localizedString) -> String {
        
        var result = "\(defalutName)1"
        objc_sync_enter(sqliteWrapper)
        guard sqliteWrapper.isOpen || sqliteWrapper.openDb(sqliteDBName), sqliteWrapper.prepareSql(Schedule.GET_NEXT_SCHEDULE_NAME) else {
            objc_sync_exit(sqliteWrapper)
            return result
        }
        // 日程已使用的名称索引
        var scheduleIndexs: [Int] = []
        sqliteWrapper.bindText(1, text: meshUUID)
        sqliteWrapper.bindText(2, text: "%\(defalutName)%")
        
        while sqliteWrapper.stepSqlRow() {
            
            let scheduleName = sqliteWrapper.columnText(0) as String
            if let index = Int(scheduleName.replacingOccurrences(of: defalutName, with: "")) {
                scheduleIndexs.append(index)
            }
        }
        sqliteWrapper.finalizeSql()
        //        sqliteWrapper.closeDb()
        objc_sync_exit(sqliteWrapper)
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
    /// - Returns: 是否重名
    static func isTautonym(scheduleName: String, meshUUID: String) -> Bool {
        
        objc_sync_enter(sqliteWrapper)
        guard sqliteWrapper.isOpen || sqliteWrapper.openDb(sqliteDBName), sqliteWrapper.prepareSql(Schedule.GET_TAUTONY_SCHEDULE_NAME) else {
            objc_sync_exit(sqliteWrapper)
            return false
        }
        sqliteWrapper.bindText(1, text: meshUUID)
        sqliteWrapper.bindText(2, text: scheduleName)
        var tautonym = false
        while sqliteWrapper.stepSqlRow() {
            tautonym = true
            break
        }
        sqliteWrapper.finalizeSql()
        //        sqliteWrapper.closeDb()
        objc_sync_exit(sqliteWrapper)
        return tautonym
    }
    
}

extension Node {
    
    private static let CREAT_TABLE_NODE_INFOS = "CREATE TABLE IF NOT EXISTS NODE_INFOS(NODE_ROW INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, ADDRESS INTEGER, MAC_ADDRESS TEXT, MESH_UUID TEXT, CCT_RANGE_MIN INTEGER, CCT_RANGE_MAX INTEGER, RSSI INTEGER, GROUP_STATE INTEGER, SENSOR_TYPE_DATA BLOB, SENSOR_CALIBRATIONVALUE INTEGER,  ENOCEAN_MACADDRESS TEXT, ENOCEAN_KEY_SCENES BLOB, POWER_UPSTATE INTEGER, DEFALUT_LIGHTNESS INTEGER, LIGHTNESS_RANGE_MIN INTEGER, LIGHTNESS_RANGE_MAX INTEGER)"

    private static let CREATE_IDX_NODE_INFO = "CREATE UNIQUE INDEX IF NOT EXISTS IDX_NODE_INFO ON NODE_INFOS(ADDRESS, MESH_UUID)"
    
    private static let SAVE_NODE_INFO = "INSERT OR REPLACE INTO NODE_INFOS(ADDRESS, MAC_ADDRESS, MESH_UUID, CCT_RANGE_MIN, CCT_RANGE_MAX, RSSI, GROUP_STATE, SENSOR_TYPE_DATA, SENSOR_CALIBRATIONVALUE, ENOCEAN_MACADDRESS, ENOCEAN_KEY_SCENES, POWER_UPSTATE, DEFALUT_LIGHTNESS, LIGHTNESS_RANGE_MIN, LIGHTNESS_RANGE_MAX) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
    
    private static let GET_NODE_INFOS = "SELECT ADDRESS, MAC_ADDRESS, MESH_UUID, CCT_RANGE_MIN, CCT_RANGE_MAX, RSSI, GROUP_STATE, SENSOR_TYPE_DATA, SENSOR_CALIBRATIONVALUE, ENOCEAN_MACADDRESS, ENOCEAN_KEY_SCENES, POWER_UPSTATE, DEFALUT_LIGHTNESS, LIGHTNESS_RANGE_MIN, LIGHTNESS_RANGE_MAX FROM NODE_INFOS WHERE MESH_UUID = ?"
    
    private static let GET_NODE_INFO_BY_ID = "SELECT ADDRESS, MAC_ADDRESS, MESH_UUID, CCT_RANGE_MIN, CCT_RANGE_MAX, RSSI, GROUP_STATE, SENSOR_TYPE_DATA, SENSOR_CALIBRATIONVALUE, ENOCEAN_MACADDRESS, ENOCEAN_KEY_SCENES, POWER_UPSTATE, DEFALUT_LIGHTNESS, LIGHTNESS_RANGE_MIN, LIGHTNESS_RANGE_MAX FROM NODE_INFOS  WHERE MESH_UUID = ? AND ADDRESS = ?"
    
    private static let DELETE_NODE_INFOS = "DELETE FROM NODE_INFOS WHERE MESH_UUID = ?"
    
    private static let DELETE_NODE_INFO = "DELETE FROM NODE_INFOS WHERE MESH_UUID = ? AND ADDRESS = ?"
    
    /// node-schedule
    private static let CREAT_TABLE_NODE_SCHEDULES = "CREATE TABLE IF NOT EXISTS NODE_SCHEDULES(NODE_SCHEDULES_ROW INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, ADDRESS INTEGER, MESH_UUID TEXT, SCHEDULE_ID INTEGER, SCHEDULE_DATA BLOB)"
    
    private static let CREATE_IDX_NODE_SCHEDULES = "CREATE UNIQUE INDEX IF NOT EXISTS IDX_NODE_SCHEDULES ON NODE_SCHEDULES(ADDRESS, MESH_UUID, SCHEDULE_ID)"
    
    private static let SAVE_NODE_SCHEDULE = "INSERT OR REPLACE INTO NODE_SCHEDULES(ADDRESS, MESH_UUID, SCHEDULE_ID, SCHEDULE_DATA) VALUES(?, ?, ?, ?)"
    
    private static let GET_NODE_SCHEDULES = "SELECT ADDRESS, MESH_UUID, SCHEDULE_ID, SCHEDULE_DATA FROM NODE_SCHEDULES WHERE MESH_UUID = ? AND ADDRESS = ?"
    
    private static let GET_NODE_SCHEDULE = "SELECT ADDRESS, MESH_UUID, SCHEDULE_ID, SCHEDULE_DATA FROM NODE_SCHEDULES WHERE MESH_UUID = ? AND ADDRESS = ? AND SCHEDULE_ID = ?"
    
    private static let DELETE_NETWORK_SCHEDULES = "DELETE FROM NODE_SCHEDULES WHERE MESH_UUID = ?"
    
    private static let DELETE_NODE_SCHEDULES = "DELETE FROM NODE_SCHEDULES WHERE MESH_UUID = ? AND ADDRESS = ?"
    
    private static let DELETE_NODE_SCHEDULE = "DELETE FROM NODE_SCHEDULES WHERE MESH_UUID = ? AND ADDRESS = ? AND SCHEDULE_ID = ?"
    
    /// node-profile
    private static let CREAT_TABLE_NODE_PROFILES = "CREATE TABLE IF NOT EXISTS NODE_PROFILES(NODE_PROFILES_ROW INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, address integer, mesh_uuid text, mode integer, occupancy_mode integer, lightness_range_high integer, lightness_range_low integer, lightness_on integer, lux_level_on integer, lightness_prolong integer, lux_level_prolong integer, regulator_kid text, regulator_kiu text, regulator_kpd text, regulator_kpu text, regulator_accuracy integer, time_fade_on integer, time_run_on integer, time_fade integer, time_prolong integer, time_standby_auto integer, manual_override_timeout bigint, manual_override_enabled integer, power_up_state integer, power_up_lightness integer, light_auto_adjust_enabled integer)"
    
    private static let CREATE_IDX_NODE_PROFILES = "CREATE UNIQUE INDEX IF NOT EXISTS IDX_NODE_PROFILES ON NODE_PROFILES(mesh_uuid, address)"
    
    private static let SAVE_NODE_PROFILE = "INSERT OR REPLACE INTO NODE_PROFILES(address, mesh_uuid, mode, occupancy_mode, lightness_range_high, lightness_range_low, lightness_on, lux_level_on, lightness_prolong, lux_level_prolong, regulator_kid, regulator_kiu, regulator_kpd, regulator_kpu, regulator_accuracy, time_fade_on, time_run_on, time_fade, time_prolong, time_standby_auto, manual_override_timeout, manual_override_enabled, power_up_state, power_up_lightness, light_auto_adjust_enabled) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
    
    private static let GET_NODE_PROFILE = "SELECT address, mesh_uuid, mode, occupancy_mode, lightness_range_high, lightness_range_low, lightness_on, lux_level_on, lightness_prolong, lux_level_prolong, regulator_kid, regulator_kiu, regulator_kpd, regulator_kpu, regulator_accuracy, time_fade_on, time_run_on, time_fade, time_prolong, time_standby_auto, manual_override_timeout, manual_override_enabled, power_up_state, power_up_lightness, light_auto_adjust_enabled FROM NODE_PROFILES WHERE mesh_uuid = ? AND address = ?"
    
    private static let DELETE_NODE_PROFILES = "DELETE FROM NODE_PROFILES WHERE mesh_uuid = ?"
    private static let DELETE_NODE_PROFILE = "DELETE FROM NODE_PROFILES WHERE mesh_uuid = ? AND address = ?"
    
    /// 初始化数据库缓存
    static func createDatabaseIfNotExit() {
        objc_sync_enter(sqliteWrapper)
        if sqliteWrapper.isOpen || sqliteWrapper.openDb(sqliteDBName) {
            sqliteWrapper.execSql(CREAT_TABLE_NODE_INFOS)
            sqliteWrapper.execSql(CREATE_IDX_NODE_INFO)
            //        sqliteWrapper.closeDb()
        }
        objc_sync_exit(sqliteWrapper)
        
        createScheduleDatabaseIfNotExit()
        
        createProfileDatabaseIfNotExit()
    }
    
    /// 获取网络下所有的设备扩展数据
    /// - Parameter meshUUID: 网络id
    /// - Returns: 扩展数据list
    static func loadAll(meshUUID: String) -> [NodeInfo] {
        objc_sync_enter(sqliteWrapper)
        guard sqliteWrapper.isOpen || sqliteWrapper.openDb(sqliteDBName), sqliteWrapper.prepareSql(GET_NODE_INFOS) else {
            objc_sync_exit(sqliteWrapper)
            return []
        }
        sqliteWrapper.bindText(1, text: meshUUID)
//        sqliteWrapper.bindInt(2, integer: sqlite3_int64(address))
        
        var nodeInfos: [NodeInfo] = []
        while sqliteWrapper.stepSqlRow() {
        
            let address = UInt16(sqliteWrapper.columnInt(0))
            let mac = sqliteWrapper.columnText(1)
            let cctRange: ClosedRange<UInt16> = UInt16(sqliteWrapper.columnInt(3))...UInt16(sqliteWrapper.columnInt(4))
            let rssi = Int(sqliteWrapper.columnInt(5))
            let groupState: GroupState = .init(rawValue: Int(sqliteWrapper.columnInt(6))) ?? .none
            
            // 传感器类型data
            var sensorTypes: [Int: DeviceProperty] = [:]
            if let sensorTypeData = sqliteWrapper.columnBlob(7) {
                var offset = 0
                let length = 2
                while offset + length <= sensorTypeData.count {
                    let type: UInt16 = sensorTypeData.read(fromOffset: offset)
                    sensorTypes.updateValue(DeviceProperty(type), forKey: Int(offset / length))
                    offset += length
                }
            }
            // 光照传感器校准值
            let sensorCalibrationValue = UInt16(sqliteWrapper.columnInt(8))
            // EnOcean设备mac
            var enOceanMacAddress: String?
            if sqliteWrapper.columnText(9).count > 0 {
                enOceanMacAddress = sqliteWrapper.columnText(9)
            }
            // EnOcean按键对应场景
            var enOceanSwitchKeyScenes: [SceneNumber] = []
            if let switchKeySceneData = sqliteWrapper.columnBlob(10), switchKeySceneData.count == 8 {
                let sceneNumber1: UInt16 = switchKeySceneData.read(fromOffset: 0)
                let sceneNumber2: UInt16 = switchKeySceneData.read(fromOffset: 1)
                let sceneNumber3: UInt16 = switchKeySceneData.read(fromOffset: 2)
                let sceneNumber4: UInt16 = switchKeySceneData.read(fromOffset: 3)
                enOceanSwitchKeyScenes.append(contentsOf: [sceneNumber1, sceneNumber2, sceneNumber3, sceneNumber4])
            }
            
            // 上电状态
            let powerUpState: OnPowerUp = .init(rawValue: UInt8(sqliteWrapper.columnInt(8))) ?? .restore
            
            // 上电亮度
            var defalutLightness: UInt16?
            if sqliteWrapper.columnInt(9) >= 0 {
                defalutLightness = UInt16(sqliteWrapper.columnInt(9))
            }
            
            // 亮度范围
            let lightnessMin = UInt16(sqliteWrapper.columnInt(13))
            let lightnessMax = UInt16(sqliteWrapper.columnInt(14))
            
            nodeInfos.append(NodeInfo(address: address, mac: mac, cctRange: cctRange, rssi: rssi, groupState: groupState, schedules: [:], sceneDatas: [:], sensorTypes: sensorTypes, sensorCalibrationValue: sensorCalibrationValue, enOceanMacAddress: enOceanMacAddress, enOceanSwitchKeyScenes: enOceanSwitchKeyScenes, powerUpState: powerUpState, defalutLightness: defalutLightness, lightnessRange: lightnessMin...lightnessMax))
        }
      
        sqliteWrapper.finalizeSql()
        //        sqliteWrapper.closeDb()
        objc_sync_exit(sqliteWrapper)
        
        nodeInfos.forEach({ info in
            
            let schedules = loadAllSchedule(meshUUID: meshUUID, address: info.address)
            var scheduleDatas: [Int: SchedulerRegistryEntry] = [:]
            schedules.forEach({
                scheduleDatas.updateValue($0.entry, forKey: $0.scheduleId)
            })
            
            let scenes = SceneExecuteData.loadAll(meshUUID: meshUUID, address: info.address)
            var sceneDatas: [SceneNumber: SceneExecuteData] = [:]
            scenes.forEach({
                sceneDatas.updateValue($0.data, forKey: SceneNumber($0.sceneId))
            })
        })
        
        return nodeInfos
    }
    
    /// 获取网络下所有的设备扩展数据
    /// - Parameter meshUUID: 网络id
    /// - Returns: 扩展数据list
    static func loadNodeInfo(meshUUID: String, address: UInt16) -> NodeInfo? {
        objc_sync_enter(sqliteWrapper)
        guard sqliteWrapper.isOpen || sqliteWrapper.openDb(sqliteDBName), sqliteWrapper.prepareSql(GET_NODE_INFO_BY_ID) else {
            objc_sync_exit(sqliteWrapper)
            return nil
        }
        sqliteWrapper.bindText(1, text: meshUUID)
        sqliteWrapper.bindInt(2, integer: sqlite3_int64(address))

        var nodeInfo: NodeInfo?
        while sqliteWrapper.stepSqlRow() {
            
//            let groupAddress = UInt16(sqliteWrapper.columnInt(0))
            let address = UInt16(sqliteWrapper.columnInt(0))
            let mac = sqliteWrapper.columnText(1)
            let cctRange: ClosedRange<UInt16> = UInt16(sqliteWrapper.columnInt(3))...UInt16(sqliteWrapper.columnInt(4))
            let rssi = Int(sqliteWrapper.columnInt(5))
            let groupState: GroupState = .init(rawValue: Int(sqliteWrapper.columnInt(6))) ?? .none
            // 传感器类型data
            var sensorTypes: [Int: DeviceProperty] = [:]
            if let sensorTypeData = sqliteWrapper.columnBlob(7) {
                var offset = 0
                let length = 2
                
                while offset + length <= sensorTypeData.count {
                    let type: UInt16 = sensorTypeData.read(fromOffset: offset)
                    sensorTypes.updateValue(DeviceProperty(type), forKey: Int(offset / length))
                    offset += length
                }
            }
            // 光照传感器校准值
            let sensorCalibrationValue = UInt16(sqliteWrapper.columnInt(8))
            // EnOcean设备mac
            var enOceanMacAddress: String?
            if sqliteWrapper.columnText(9).count > 0 {
                enOceanMacAddress = sqliteWrapper.columnText(9)
            }
            // EnOcean按键对应场景
            var enOceanSwitchKeyScenes: [SceneNumber] = []
            if let switchKeySceneData = sqliteWrapper.columnBlob(10), switchKeySceneData.count == 8 {
                let sceneNumber1: UInt16 = switchKeySceneData.read(fromOffset: 0)
                let sceneNumber2: UInt16 = switchKeySceneData.read(fromOffset: 2)
                let sceneNumber3: UInt16 = switchKeySceneData.read(fromOffset: 4)
                let sceneNumber4: UInt16 = switchKeySceneData.read(fromOffset: 6)
                enOceanSwitchKeyScenes.append(contentsOf: [sceneNumber1, sceneNumber2, sceneNumber3, sceneNumber4])
            }
            
            // 上电状态
            var powerUpState: OnPowerUp?
            if sqliteWrapper.columnInt(11) > 0 {
                powerUpState = .init(rawValue: UInt8(sqliteWrapper.columnInt(11)))
            }
         
            // 上电亮度
            var defalutLightness: UInt16?
            if sqliteWrapper.columnInt(12) >= 0 {
                defalutLightness = UInt16(sqliteWrapper.columnInt(12))
            }
            // 亮度范围
            let lightnessMin = UInt16(sqliteWrapper.columnInt(13))
            let lightnessMax = UInt16(sqliteWrapper.columnInt(14))
            
            nodeInfo = NodeInfo(address: address, mac: mac, cctRange: cctRange, rssi: rssi, groupState: groupState, schedules: [:], sceneDatas: [:], sensorTypes: sensorTypes, sensorCalibrationValue: sensorCalibrationValue, enOceanMacAddress: enOceanMacAddress, enOceanSwitchKeyScenes: enOceanSwitchKeyScenes, powerUpState: powerUpState, defalutLightness: defalutLightness, lightnessRange: lightnessMin...lightnessMax)
        }
      
        sqliteWrapper.finalizeSql()
        objc_sync_exit(sqliteWrapper)
        
        if nodeInfo != nil {
            let schedules = loadAllSchedule(meshUUID: meshUUID, address: address)
            var scheduleDatas: [Int: SchedulerRegistryEntry] = [:]
            schedules.forEach({
                scheduleDatas.updateValue($0.entry, forKey: $0.scheduleId)
            })
            
            let scenes = SceneExecuteData.loadAll(meshUUID: meshUUID, address: address)
            var sceneDatas: [SceneNumber: SceneExecuteData] = [:]
            scenes.forEach({
                sceneDatas.updateValue($0.data, forKey: SceneNumber($0.sceneId))
            })
            nodeInfo?.sceneDatas = sceneDatas
            nodeInfo?.schedules = scheduleDatas
        }
        //        sqliteWrapper.closeDb()

        return nodeInfo
    }
    
    @discardableResult func saveNodeInfo(meshUUID: String) -> Bool {
        
        objc_sync_enter(sqliteWrapper)
        guard sqliteWrapper.isOpen || sqliteWrapper.openDb(sqliteDBName), sqliteWrapper.prepareSql(Node.SAVE_NODE_INFO) else {
            objc_sync_exit(sqliteWrapper)
            return false
        }
        sqliteWrapper.bindInt(1, integer: sqlite3_int64(primaryUnicastAddress))
        sqliteWrapper.bindText(2, text: macAddress ?? "")
        sqliteWrapper.bindText(3, text: meshUUID)
        sqliteWrapper.bindInt(4, integer: sqlite3_int64((lightCTLTemperatureRange ?? defalutLightCTLTemperatureRange).lowerBound))
        sqliteWrapper.bindInt(5, integer: sqlite3_int64((lightCTLTemperatureRange ?? defalutLightCTLTemperatureRange).upperBound))
        sqliteWrapper.bindInt(6, integer: sqlite3_int64(rssi ?? -99))
        sqliteWrapper.bindInt(7, integer: sqlite3_int64(groupState.rawValue))
        
        var sensorTypeData = Data()
        let propertys: [DeviceProperty] = sensorModelTypes.sorted(by: { $0.key.parentElement?.index ?? 0 < $1.key.parentElement?.index ?? 0 }).map({ $0.value })
        propertys.forEach { property in
            sensorTypeData.append(Data([UInt8(property.id & 0xff), UInt8(property.id << 8 & 0xff)]))
        }
        sqliteWrapper.bindBlob(8, blob: sensorTypeData)
        
        sqliteWrapper.bindInt(9, integer: sqlite3_int64(self.daylightCalibrationValue ?? 0xFFFF))
        sqliteWrapper.bindText(10, text: self.enOceanMacAddress ?? "")
        
        var enOceanKeySceneData = Data()
        self.enOceanKeySceneNumbers.forEach({
            enOceanKeySceneData += Data([UInt8($0 & 0xff), UInt8($0 >> 8 & 0xff)])
        })
        sqliteWrapper.bindBlob(11, blob: enOceanKeySceneData)
        
        if let state = powerUpState {
            sqliteWrapper.bindInt(12, integer: sqlite3_int64(state.rawValue))
        }else {
            sqliteWrapper.bindInt(12, integer: -1)
        }
        
        if let lightness = defalutLightness {
            sqliteWrapper.bindInt(13, integer: sqlite3_int64(lightness))
        }else {
            sqliteWrapper.bindInt(13, integer: -1)
        }
        
        sqliteWrapper.bindInt(14, integer: sqlite3_int64(lightnessRange.lowerBound))
        sqliteWrapper.bindInt(15, integer: sqlite3_int64(lightnessRange.upperBound))
        
        // 占用传感器model地址
//        if let address = presenceDetectedSensorModel?.parentElement?.unicastAddress {
//            sqliteWrapper.bindInt(8, integer: sqlite3_int64(address))
//        }else {
//            sqliteWrapper.bindInt(8, integer: sqlite3_int64(-1))
//        }
//        // 光照传感器model地址
//        if let address = ambientLightSensorModel?.parentElement?.unicastAddress {
//            sqliteWrapper.bindInt(9, integer: sqlite3_int64(address))
//        }else {
//            sqliteWrapper.bindInt(9, integer: sqlite3_int64(-1))
//        }
        
        sqliteWrapper.stepSqlDone()
        sqliteWrapper.resetSql()
        sqliteWrapper.finalizeSql()
        objc_sync_exit(sqliteWrapper)
        
        return true
    }
    
    /// 删除所属网络设备扩展信息
    /// - Parameter meshUUID: mesh网络id
    /// - Returns: 是否成功
    @discardableResult static func deleteAllInfo(meshUUID: String) -> Bool {
        
        objc_sync_enter(sqliteWrapper)
        guard sqliteWrapper.isOpen || sqliteWrapper.openDb(sqliteDBName), sqliteWrapper.prepareSql(Node.DELETE_NODE_INFOS) else {
            objc_sync_exit(sqliteWrapper)
            return false
        }
        
        sqliteWrapper.bindText(1, text: meshUUID)
        sqliteWrapper.stepSqlDone()
        sqliteWrapper.finalizeSql()
        //        sqliteWrapper.closeDb()
        objc_sync_exit(sqliteWrapper)
        return true
    }
    
    /// 删除设备扩展信息
    /// - Parameter meshUUID: mesh网络id
    /// - Returns: 是否成功
    @discardableResult static func deleteInfo(meshUUID: String, address: UInt16) -> Bool {
        
        objc_sync_enter(sqliteWrapper)
        guard sqliteWrapper.isOpen || sqliteWrapper.openDb(sqliteDBName), sqliteWrapper.prepareSql(Node.DELETE_NODE_INFO) else {
            objc_sync_exit(sqliteWrapper)
            return false
        }
        
        sqliteWrapper.bindText(1, text: meshUUID)
        sqliteWrapper.bindInt(2, integer: sqlite3_int64(address))
        sqliteWrapper.stepSqlDone()
        sqliteWrapper.finalizeSql()
        //        sqliteWrapper.closeDb()
        objc_sync_exit(sqliteWrapper)
        return true
        
    }
    
    //********* SCHEDULE **********/
    
    /// 初始化数据库缓存
    static func createScheduleDatabaseIfNotExit() {
        objc_sync_enter(sqliteWrapper)
        if sqliteWrapper.isOpen || sqliteWrapper.openDb(sqliteDBName) {
            sqliteWrapper.execSql(CREAT_TABLE_NODE_SCHEDULES)
            sqliteWrapper.execSql(CREATE_IDX_NODE_SCHEDULES)
            //        sqliteWrapper.closeDb()
        }
        objc_sync_exit(sqliteWrapper)
    }
    
    /// 获取网络下对应设备的所有日程数据
    /// - Parameter meshUUID: 网络id
    /// - Parameter address: 设备地址
    /// - Returns: 日程id，日程数据
    static func loadAllSchedule(meshUUID: String, address: UInt16) -> [(scheduleId: Int, entry: SchedulerRegistryEntry)] {
        objc_sync_enter(sqliteWrapper)
        guard sqliteWrapper.isOpen || sqliteWrapper.openDb(sqliteDBName), sqliteWrapper.prepareSql(GET_NODE_SCHEDULES) else {
            objc_sync_exit(sqliteWrapper)
            return []
        }
        sqliteWrapper.bindText(1, text: meshUUID)
        sqliteWrapper.bindInt(2, integer: sqlite3_int64(address))
        
        var schedules: [(Int, SchedulerRegistryEntry)] = []
        while sqliteWrapper.stepSqlRow() {
            
            if let scheduleData = sqliteWrapper.columnBlob(3), scheduleData.count == 10 {
                let data = SchedulerRegistryEntry.unmarshal(scheduleData)
                
                schedules.append((Int(data.index), data.entry))
            }
        }
      
        sqliteWrapper.finalizeSql()
        //        sqliteWrapper.closeDb()
        objc_sync_exit(sqliteWrapper)

        return schedules
    }
    
    /// 获取网络下对应设备指定日程数据
    /// - Parameter meshUUID: 网络id
    /// - Parameter address: 设备地址
    ///- Parameter scheduleId: 设备地址
    /// - Returns: 日程id，日程数据
    static func loadSchedule(meshUUID: String, address: UInt16, scheduleId: Int) -> SchedulerRegistryEntry? {
        objc_sync_enter(sqliteWrapper)
        guard sqliteWrapper.isOpen || sqliteWrapper.openDb(sqliteDBName), sqliteWrapper.prepareSql(GET_NODE_SCHEDULE) else {
            objc_sync_exit(sqliteWrapper)
            return nil
        }
        sqliteWrapper.bindText(1, text: meshUUID)
        sqliteWrapper.bindInt(2, integer: sqlite3_int64(address))
        sqliteWrapper.bindInt(3, integer: sqlite3_int64(scheduleId))
        
        var schedule: SchedulerRegistryEntry?
        while sqliteWrapper.stepSqlRow() {
            
//            let groupAddress = UInt16(sqliteWrapper.columnInt(0))
//            let scheduleId = Int(sqliteWrapper.columnInt(2))
            if let scheduleData = sqliteWrapper.columnBlob(3), scheduleData.count == 10 {
                schedule = SchedulerRegistryEntry.unmarshal(scheduleData).entry
//                schedule = (Int(data.index), data.entry)
            }
        }
      
        sqliteWrapper.finalizeSql()
        //        sqliteWrapper.closeDb()
        objc_sync_exit(sqliteWrapper)

        return schedule
    }
    
    /// 缓存设备日程数据
    /// - Parameters:
    ///   - meshUUID: 网络id
    ///   - address: 设备地址
    ///   - scheduleId: 日程id
    ///   - entry: 日程对象（二选一）
    ///   - data: 日程数据（二选一）
    /// - Returns: 是否成功
    @discardableResult static func saveSchedule(meshUUID: String, address: UInt16, scheduleId: Int, entry: SchedulerRegistryEntry? = nil, data: Data? = nil) -> Bool {
        
        objc_sync_enter(sqliteWrapper)
        guard sqliteWrapper.isOpen || sqliteWrapper.openDb(sqliteDBName), sqliteWrapper.prepareSql(Node.SAVE_NODE_SCHEDULE), data != nil || entry != nil else {
            objc_sync_exit(sqliteWrapper)
            return false
        }
        
        sqliteWrapper.bindInt(1, integer: sqlite3_int64(address))
        sqliteWrapper.bindText(2, text: meshUUID)
        sqliteWrapper.bindInt(3, integer: sqlite3_int64(scheduleId))
        let scheduleData = data ?? SchedulerRegistryEntry.marshal(index: UInt8(scheduleId), entry: entry!)
        sqliteWrapper.bindBlob(4, blob: scheduleData)
        sqliteWrapper.stepSqlDone()
        sqliteWrapper.finalizeSql()
        objc_sync_exit(sqliteWrapper)
        return true
    }
    
    /// 删除网络全部日程数据
    /// - Parameter meshUUID: mesh网络id
    /// - Returns: 是否成功
    @discardableResult static func deleteAllSchedule(meshUUID: String) -> Bool {
        
        objc_sync_enter(sqliteWrapper)
        guard sqliteWrapper.isOpen || sqliteWrapper.openDb(sqliteDBName), sqliteWrapper.prepareSql(Node.DELETE_NETWORK_SCHEDULES) else {
            objc_sync_exit(sqliteWrapper)
            return false
        }
        
        sqliteWrapper.bindText(1, text: meshUUID)
        sqliteWrapper.stepSqlDone()
        sqliteWrapper.finalizeSql()
        //        sqliteWrapper.closeDb()
        objc_sync_exit(sqliteWrapper)
        return true
        
    }
    
    /// 删除设备全部日程数据
    /// - Parameter meshUUID: mesh网络id
    /// - Parameter address: 设备地址
    /// - Returns: 是否成功
    @discardableResult static func deleteSchedules(meshUUID: String, address: UInt16) -> Bool {
        
        objc_sync_enter(sqliteWrapper)
        guard sqliteWrapper.isOpen || sqliteWrapper.openDb(sqliteDBName), sqliteWrapper.prepareSql(Node.DELETE_NODE_SCHEDULES) else {
            objc_sync_exit(sqliteWrapper)
            return false
        }
        
        sqliteWrapper.bindText(1, text: meshUUID)
        sqliteWrapper.bindInt(2, integer: sqlite3_int64(address))
        sqliteWrapper.stepSqlDone()
        sqliteWrapper.finalizeSql()
        //        sqliteWrapper.closeDb()
        objc_sync_exit(sqliteWrapper)
        return true
        
    }
    
    /// 删除设备对应的日程数据
    /// - Parameter meshUUID: mesh网络id
    /// - Parameter address: 设备地址
    /// - Parameter scheduleId: 日程id
    /// - Returns: 是否成功
    @discardableResult static func deleteSchedule(meshUUID: String, address: UInt16, scheduleId: Int) -> Bool {
        
        objc_sync_enter(sqliteWrapper)
        guard sqliteWrapper.isOpen || sqliteWrapper.openDb(sqliteDBName), sqliteWrapper.prepareSql(Node.DELETE_NODE_SCHEDULE) else {
            objc_sync_exit(sqliteWrapper)
            return false
        }
        
        sqliteWrapper.bindText(1, text: meshUUID)
        sqliteWrapper.bindInt(2, integer: sqlite3_int64(address))
        sqliteWrapper.bindInt(3, integer: sqlite3_int64(scheduleId))
        sqliteWrapper.stepSqlDone()
        sqliteWrapper.finalizeSql()
        //        sqliteWrapper.closeDb()
        objc_sync_exit(sqliteWrapper)
        return true
    }
    
    //********* Profile **********/
    
    /// 初始化数据库缓存
    static func createProfileDatabaseIfNotExit() {
        objc_sync_enter(sqliteWrapper)
        if sqliteWrapper.isOpen || sqliteWrapper.openDb(sqliteDBName) {
            sqliteWrapper.execSql(CREAT_TABLE_NODE_PROFILES)
            sqliteWrapper.execSql(CREATE_IDX_NODE_PROFILES)
            //        sqliteWrapper.closeDb()
        }
        objc_sync_exit(sqliteWrapper)
    }
    
    /// 获取网络下对应设备的配置数据
    /// - Parameter meshUUID: 网络id
    /// - Parameter address: 设备地址
    /// - Returns: 配置数据
    static func loadProfile(meshUUID: String, address: UInt16) -> (propertys: LightLCProperty, lightnessRange: ClosedRange<UInt16>, powerUpState: Profile.PowerUpState)? {
        objc_sync_enter(sqliteWrapper)
        guard sqliteWrapper.isOpen || sqliteWrapper.openDb(sqliteDBName), sqliteWrapper.prepareSql(GET_NODE_PROFILE) else {
            objc_sync_exit(sqliteWrapper)
            return nil
        }
        sqliteWrapper.bindText(1, text: meshUUID)
        sqliteWrapper.bindInt(2, integer: sqlite3_int64(address))
        
        var data: (propertys: LightLCProperty, lightnessRange: ClosedRange<UInt16>, powerUpState: Profile.PowerUpState)?
        while sqliteWrapper.stepSqlRow() {
            
            let property = LightLCProperty()
            
            let mode = sqliteWrapper.columnInt(2)
            if mode == 0 || mode == 1 {
                property.mode = mode == 1
            }
            
            let occupancyMode = sqliteWrapper.columnInt(3)
            if occupancyMode == 0 || occupancyMode == 1 {
                property.occupancyMode = occupancyMode == 1
            }
            
            let lightnessRangeHigh = UInt16(sqliteWrapper.columnInt(4))
            
            let lightnessRangeLow = UInt16(sqliteWrapper.columnInt(5))
            
            let lightnessOn = sqliteWrapper.columnInt(6)
            if lightnessOn >= 0 {
                property.lightnessOn = UInt16(lightnessOn)
            }
            let luxLevelOn = sqliteWrapper.columnInt(7)
            if luxLevelOn >= 0 {
                property.luxLevelOn = UInt16(luxLevelOn)
            }
            
            let lightnessProlong = sqliteWrapper.columnInt(8)
            if lightnessProlong >= 0 {
                property.lightnessProlong = UInt16(lightnessProlong)
            }
            let luxLevelProlong = sqliteWrapper.columnInt(9)
            if luxLevelProlong >= 0 {
                property.luxLevelProlong = UInt16(luxLevelProlong)
            }
            
//            let lightAutoMinLevel = UInt16(sqliteWrapper.columnInt(10))
//            property.lightAutoMinLevel = lightAutoMinLevel
            
            if let regulatorKidStr = sqliteWrapper.columnText(10), let regulatorKid = Float(regulatorKidStr) {
                property.regulatorKid = regulatorKid
            }
            
            if let regulatorKiuStr = sqliteWrapper.columnText(11), let regulatorKiu = Float(regulatorKiuStr) {
                property.regulatorKiu = regulatorKiu
            }
            
            if let regulatorKpdStr = sqliteWrapper.columnText(12), let regulatorKpd = Float(regulatorKpdStr) {
                property.regulatorKpd = regulatorKpd
            }
            
            if let regulatorKpuStr = sqliteWrapper.columnText(13), let regulatorKpu = Float(regulatorKpuStr) {
                property.regulatorKpu = regulatorKpu
            }
            
            let regulatorAccuracy = sqliteWrapper.columnInt(14)
            if regulatorAccuracy >= 0 {
                property.regulatorAccuracy = UInt8(regulatorAccuracy)
            }
            let timeFadeOn = sqliteWrapper.columnInt(15)
            if timeFadeOn >= 0 {
                property.timeFadeOn = UInt32(timeFadeOn)
            }
            let timeRunOn = sqliteWrapper.columnInt(16)
            if timeRunOn >= 0 {
                property.timeRunOn = UInt32(timeRunOn)
            }
            let timeFade = sqliteWrapper.columnInt(17)
            if timeFade >= 0 {
                property.timeFade = UInt32(timeFade)
            }
            let timeProlong = sqliteWrapper.columnInt(18)
            if timeProlong >= 0 {
                property.timeProlong = UInt32(timeProlong)
            }
            let timeFadeStandbyAuto = sqliteWrapper.columnInt(19)
            if timeFadeStandbyAuto >= 0 {
                property.timeFadeStandbyAuto = UInt32(timeFadeStandbyAuto)
            }
            let manualOverrideTimeout = sqliteWrapper.columnInt64(20)
            if manualOverrideTimeout >= 0 {
                property.manualOverrideTimeout = UInt32(manualOverrideTimeout)
            }
            
            let manualOverrideEnabled = sqliteWrapper.columnInt(21)
            if manualOverrideEnabled == 0 || manualOverrideEnabled == 1 {
                property.manualOverrideEnabled = manualOverrideEnabled == 1
            }
            
            var powerUpState: OnPowerUp?
            if sqliteWrapper.columnInt(22) >= 0 {
                powerUpState = .init(rawValue: UInt8(sqliteWrapper.columnInt(22)))
            }
            
            let powerUpLightness = sqliteWrapper.columnInt(23)
            
            let autoAdjustEnabled = sqliteWrapper.columnInt(24)
            if autoAdjustEnabled == 0 || autoAdjustEnabled == 1 {
                property.lightAutoAdjustEnabled = autoAdjustEnabled == 1
            }
            
            if powerUpState == .default, powerUpLightness > 0 {
                let level = Node.getLightness100(lightness: UInt16(powerUpLightness))
                data = (property, lightnessRangeLow...lightnessRangeHigh, .definedLightLevel(level))
            }else {
                data = (property, lightnessRangeLow...lightnessRangeHigh, .restore)
            }
            
        }
      
        sqliteWrapper.finalizeSql()
        //        sqliteWrapper.closeDb()
        objc_sync_exit(sqliteWrapper)

        return data
    }
    
    
    /// 保存节点配置数据
    /// - Parameter meshUUID: 网络id
    /// - Returns: 是否成功
    @discardableResult func saveNodeProfile(meshUUID: String) -> Bool {
        
        objc_sync_enter(sqliteWrapper)
        guard sqliteWrapper.isOpen || sqliteWrapper.openDb(sqliteDBName), sqliteWrapper.prepareSql(Node.SAVE_NODE_PROFILE) else {
            objc_sync_exit(sqliteWrapper)
            return false
        }

        sqliteWrapper.bindInt(1, integer: sqlite3_int64(primaryUnicastAddress))
        sqliteWrapper.bindText(2, text: meshUUID)
        if let mode = lightLCProperty.mode {
            sqliteWrapper.bindInt(3, integer: sqlite3_int64(mode ? 1 : 0))
        }else {
            sqliteWrapper.bindInt(3, integer: sqlite3_int64(-1))
        }
        if let occupancyMode = lightLCProperty.occupancyMode {
            sqliteWrapper.bindInt(4, integer: sqlite3_int64(occupancyMode ? 1 : 0))
        }else {
            sqliteWrapper.bindInt(4, integer: sqlite3_int64(-1))
        }
        sqliteWrapper.bindInt(5, integer: sqlite3_int64(lightnessRange.upperBound))
        sqliteWrapper.bindInt(6, integer: sqlite3_int64(lightnessRange.lowerBound))
        if let lightnessOn = lightLCProperty.lightnessOn {
            sqliteWrapper.bindInt(7, integer: sqlite3_int64(lightnessOn))
        }else {
            sqliteWrapper.bindInt(7, integer: sqlite3_int64(-1))
        }
        if let luxLevelOn = lightLCProperty.luxLevelOn {
            sqliteWrapper.bindInt(8, integer: sqlite3_int64(luxLevelOn))
        }else {
            sqliteWrapper.bindInt(8, integer: sqlite3_int64(-1))
        }
        if let lightnessProlong = lightLCProperty.lightnessProlong {
            sqliteWrapper.bindInt(9, integer: sqlite3_int64(lightnessProlong))
        }else {
            sqliteWrapper.bindInt(9, integer: sqlite3_int64(-1))
        }
        if let luxLevelProlong = lightLCProperty.luxLevelProlong {
            sqliteWrapper.bindInt(10, integer: sqlite3_int64(luxLevelProlong))
        }else {
            sqliteWrapper.bindInt(10, integer: sqlite3_int64(-1))
        }
//        sqliteWrapper.bindInt(11, integer: sqlite3_int64(lightLCProperty.lightAutoMinLevel))
        
        if let regulatorKid = lightLCProperty.regulatorKid {
            sqliteWrapper.bindText(11, text: "\(regulatorKid)")
        }else {
            sqliteWrapper.bindText(11, text: "")
        }
        if let regulatorKiu = lightLCProperty.regulatorKiu {
            sqliteWrapper.bindText(12, text: "\(regulatorKiu)")
        }else {
            sqliteWrapper.bindText(12, text: "")
        }
        if let regulatorKpd = lightLCProperty.regulatorKpd {
            sqliteWrapper.bindText(13, text: "\(regulatorKpd)")
        }else {
            sqliteWrapper.bindText(13, text: "")
        }
        if let regulatorKpu = lightLCProperty.regulatorKpu {
            sqliteWrapper.bindText(14, text: "\(regulatorKpu)")
        }else {
            sqliteWrapper.bindText(14, text: "")
        }
        if let regulatorAccuracy = lightLCProperty.regulatorAccuracy {
            sqliteWrapper.bindInt(15, integer: sqlite3_int64(regulatorAccuracy))
        }else {
            sqliteWrapper.bindInt(15, integer: sqlite3_int64(-1))
        }
        if let timeFadeOn = lightLCProperty.timeFadeOn {
            sqliteWrapper.bindInt(16, integer: sqlite3_int64(timeFadeOn))
        }else {
            sqliteWrapper.bindInt(16, integer: sqlite3_int64(-1))
        }
        if let timeRunOn = lightLCProperty.timeRunOn {
            sqliteWrapper.bindInt(17, integer: sqlite3_int64(timeRunOn))
        }else {
            sqliteWrapper.bindInt(17, integer: sqlite3_int64(-1))
        }
        if let timeFade = lightLCProperty.timeFade {
            sqliteWrapper.bindInt(18, integer: sqlite3_int64(timeFade))
        }else {
            sqliteWrapper.bindInt(18, integer: sqlite3_int64(-1))
        }
        if let timeProlong = lightLCProperty.timeProlong {
            sqliteWrapper.bindInt(19, integer: sqlite3_int64(timeProlong))
        }else {
            sqliteWrapper.bindInt(19, integer: sqlite3_int64(-1))
        }
        if let timeFadeStandbyAuto = lightLCProperty.timeFadeStandbyAuto {
            sqliteWrapper.bindInt(20, integer: sqlite3_int64(timeFadeStandbyAuto))
        }else {
            sqliteWrapper.bindInt(20, integer: sqlite3_int64(-1))
        }
        sqliteWrapper.bindInt(21, integer: sqlite3_int64(lightLCProperty.manualOverrideTimeout))
        if let manualOverrideEnabled = lightLCProperty.manualOverrideEnabled {
            sqliteWrapper.bindInt(22, integer: sqlite3_int64(manualOverrideEnabled ? 1 : 0))
        }else {
            sqliteWrapper.bindInt(22, integer: sqlite3_int64(-1))
        }
        
        if let state = powerUpState {
            sqliteWrapper.bindInt(23, integer: sqlite3_int64(state.rawValue))
        }else {
            sqliteWrapper.bindInt(23, integer: sqlite3_int64(-1))
        }
        
        if let defalutLightness = self.defalutLightness {
            sqliteWrapper.bindInt(24, integer: sqlite3_int64(defalutLightness))
        }else {
            sqliteWrapper.bindInt(24, integer: sqlite3_int64(-1))
        }
        
        if let lightAutoAdjustEnabled = lightLCProperty.lightAutoAdjustEnabled {
            sqliteWrapper.bindInt(25, integer: sqlite3_int64(lightAutoAdjustEnabled ? 1 : 0))
        }else {
            sqliteWrapper.bindInt(25, integer: sqlite3_int64(-1))
        }
        
        sqliteWrapper.stepSqlDone()
        sqliteWrapper.resetSql()
        sqliteWrapper.finalizeSql()
        objc_sync_exit(sqliteWrapper)
        
        return true
    }
    
    /// 删除配置数据
    /// - Parameter meshUUID: mesh网络id
    /// - Parameter address: 设备地址（传入删除单个设备，不传删除网络内设备配置数据）
    /// - Returns: 是否成功
    @discardableResult static func deleteProfile(meshUUID: String, address: UInt16? = nil) -> Bool {
        
        objc_sync_enter(sqliteWrapper)
        guard sqliteWrapper.isOpen || sqliteWrapper.openDb(sqliteDBName) else {
            objc_sync_exit(sqliteWrapper)
            return false
        }
        if address != nil {
            sqliteWrapper.prepareSql(Node.DELETE_NODE_PROFILE)
            sqliteWrapper.bindText(1, text: meshUUID)
            sqliteWrapper.bindInt(2, integer: sqlite3_int64(address!))
        }else {
            sqliteWrapper.prepareSql(Node.DELETE_NODE_PROFILES)
            sqliteWrapper.bindText(1, text: meshUUID)
        }
     
        sqliteWrapper.stepSqlDone()
        sqliteWrapper.finalizeSql()
        //        sqliteWrapper.closeDb()
        objc_sync_exit(sqliteWrapper)
        return true
    }
    

    struct NodeInfo {
        let address: UInt16
        let mac: String?
        let cctRange: ClosedRange<UInt16>
        let rssi: Int
        let groupState: Node.GroupState
        var schedules: [Int: SchedulerRegistryEntry]
        var sceneDatas: [SceneNumber: SceneExecuteData]
        /// 传感器类型 key：element count  value：类型
        var sensorTypes: [Int: DeviceProperty]
        /// 传感器校准值（光照）
        var sensorCalibrationValue: UInt16?
        /// 动能开关mac
        var enOceanMacAddress: String?
        /// 动能开关按键绑定的场景
        var enOceanSwitchKeyScenes: [SceneNumber]
        /// 上电状态
        var powerUpState: OnPowerUp?
        /// 上电亮度（powerUpState：defalut）
        var defalutLightness: UInt16?
        /// 亮度范围
        var lightnessRange: ClosedRange<UInt16>
    }
}

extension Profile {
    
    
    private static let CREAT_TABLE_PROFILES = "CREATE TABLE IF NOT EXISTS PROFILES(PROFILE_ROW INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, profile_name text, profile_id text, mesh_uuid text, profile_type integer, high_end_trim integer, low_end_trim integer, occupancy_level integer, vacant_level integer, task_level integer, auto_min_level integer, time_t1 integer, time_t2 integer, time_t3 integer, time_t4 integer, time_t5 integer, manual_override_timeout bigint, power_up_state integer, adjust_speed integer)"
    
    private static let CREATE_IDX_PROFILES_PROFILE = "CREATE UNIQUE INDEX IF NOT EXISTS IDX_PROFILES_PROFILE ON PROFILES(mesh_uuid, profile_id)"
    
    private static let SAVE_PROFILE = "INSERT OR REPLACE INTO PROFILES(profile_name, profile_id, mesh_uuid, profile_type, high_end_trim, low_end_trim, occupancy_level, vacant_level, task_level, auto_min_level, time_t1, time_t2, time_t3, time_t4, time_t5, manual_override_timeout, power_up_state, adjust_speed) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"

    private static let GET_PROFILES = "SELECT profile_name, profile_id, mesh_uuid, profile_type, high_end_trim, low_end_trim, occupancy_level, vacant_level, task_level, auto_min_level, time_t1, time_t2, time_t3, time_t4, time_t5, manual_override_timeout, power_up_state, adjust_speed FROM PROFILES WHERE mesh_uuid = ?"
    
    private static let GET_PROFILE_BY_ID = "SELECT profile_name, profile_id, mesh_uuid, profile_type, high_end_trim, low_end_trim, occupancy_level, vacant_level, task_level, auto_min_level, time_t1, time_t2, time_t3, time_t4, time_t5, manual_override_timeout, power_up_state, adjust_speed FROM PROFILES WHERE mesh_uuid = ? AND profile_id = ?"
    
    private static let DELETE_PROFILES = "DELETE FROM PROFILES WHERE mesh_uuid = ?"
    
    private static let DELETE_PROFILE = "DELETE FROM PROFILES WHERE mesh_uuid = ? AND profile_id = ?"
    
    
    /// 初始化数据库缓存
    static func createDatabaseIfNotExit() {
        objc_sync_enter(sqliteWrapper)
        if sqliteWrapper.isOpen || sqliteWrapper.openDb(sqliteDBName) {
            sqliteWrapper.execSql(CREAT_TABLE_PROFILES)
            sqliteWrapper.execSql(CREATE_IDX_PROFILES_PROFILE)
            //        sqliteWrapper.closeDb()
        }
        objc_sync_exit(sqliteWrapper)
    }
    
    /// 根据网络id获取网络下的所有的配置数据
    /// - Parameter meshUUID: 网络id
    /// - Returns: 日程数据list
    static func loadAll(meshUUID: String) -> [Profile] {
        objc_sync_enter(sqliteWrapper)
        guard sqliteWrapper.isOpen || sqliteWrapper.openDb(sqliteDBName), sqliteWrapper.prepareSql(GET_PROFILES) else {
            objc_sync_exit(sqliteWrapper)
            return []
        }
        sqliteWrapper.bindText(1, text: meshUUID)
        
        var profiles: [Profile] = []
        while sqliteWrapper.stepSqlRow() {
            
            let name = sqliteWrapper.columnText(0)
            let id = sqliteWrapper.columnText(1) ?? ""
            let type = Int(sqliteWrapper.columnInt(3))
            let highEndTrim = Int(sqliteWrapper.columnInt(4))
            let lowEndTrim = Int(sqliteWrapper.columnInt(5))
            let occupancyLevel = Int(sqliteWrapper.columnInt(6))
            let vacantLevel = Int(sqliteWrapper.columnInt(7))
            let taskLevel = Int(sqliteWrapper.columnInt(8))
            let autoMinLevel = Int(sqliteWrapper.columnInt(9))
            let t1 = Int(sqliteWrapper.columnInt(10))
            let t2 = Int(sqliteWrapper.columnInt(11))
            let t3 = Int(sqliteWrapper.columnInt(12))
            let t4 = Int(sqliteWrapper.columnInt(13))
            let t5 = Int(sqliteWrapper.columnInt(14))
            let manualOverrideTimeout: UInt32 = UInt32(sqliteWrapper.columnInt64(15))
            let powerUpState = Int(sqliteWrapper.columnInt(16))
            let adjustSpeed = Int(sqliteWrapper.columnInt(17))
            
            let profileType: ProfileType = .init(rawValue: type) ?? .occupancy_daylight
            
            let lightData = LightData(profileType: profileType, highEndTrim: highEndTrim, lowEndTrim: lowEndTrim, occupancyLevel: occupancyLevel, vacantLevel: vacantLevel, taskLevel: taskLevel, autoMinLevel: autoMinLevel, t1: t1, t2: t2, t3: t3, t4: t4, t5: t5)
            
            let profile = Profile(name: name ?? "", id: id, type: profileType, lightData: lightData, powerUpState: .init(rawValue: powerUpState), manualOverrideTimeout: manualOverrideTimeout, adjustSpeed: adjustSpeed)
            profiles.append(profile)
        }
        
        sqliteWrapper.finalizeSql()
        objc_sync_exit(sqliteWrapper)
        
        return profiles
    }
    
    /// 根据网络id获取网络下的所有的配置数据
    /// - Parameter meshUUID: 网络id
    /// - Parameter profileId: 配置id
    /// - Returns: 配置数据
    static func load(meshUUID: String, profileId: String) -> Profile? {
        objc_sync_enter(sqliteWrapper)
        guard sqliteWrapper.isOpen || sqliteWrapper.openDb(sqliteDBName), sqliteWrapper.prepareSql(GET_PROFILE_BY_ID) else {
            objc_sync_exit(sqliteWrapper)
            return nil
        }
        sqliteWrapper.bindText(1, text: meshUUID)
        sqliteWrapper.bindText(2, text: profileId)
        
        var profile: Profile?
        while sqliteWrapper.stepSqlRow() {
            
            let name = sqliteWrapper.columnText(0)
            let id = sqliteWrapper.columnText(1) ?? ""
            let type = Int(sqliteWrapper.columnInt(3))
            let highEndTrim = Int(sqliteWrapper.columnInt(4))
            let lowEndTrim = Int(sqliteWrapper.columnInt(5))
            let occupancyLevel = Int(sqliteWrapper.columnInt(6))
            let vacantLevel = Int(sqliteWrapper.columnInt(7))
            let taskLevel = Int(sqliteWrapper.columnInt(8))
            let autoMinLevel = Int(sqliteWrapper.columnInt(9))
            let t1 = Int(sqliteWrapper.columnInt(10))
            let t2 = Int(sqliteWrapper.columnInt(11))
            let t3 = Int(sqliteWrapper.columnInt(12))
            let t4 = Int(sqliteWrapper.columnInt(13))
            let t5 = Int(sqliteWrapper.columnInt(14))
            let manualOverrideTimeout: UInt32 = UInt32(sqliteWrapper.columnInt64(15))
            let powerUpState = Int(sqliteWrapper.columnInt(16))
            let adjustSpeed = Int(sqliteWrapper.columnInt(17))
            
            let profileType: ProfileType = .init(rawValue: type) ?? .occupancy_daylight
            
            let lightData = LightData(profileType: profileType, highEndTrim: highEndTrim, lowEndTrim: lowEndTrim, occupancyLevel: occupancyLevel, vacantLevel: vacantLevel, taskLevel: taskLevel, autoMinLevel: autoMinLevel, t1: t1, t2: t2, t3: t3, t4: t4, t5: t5)
            
            profile = Profile(name: name ?? "", id: id, type: profileType, lightData: lightData, powerUpState: .init(rawValue: powerUpState), manualOverrideTimeout: manualOverrideTimeout, adjustSpeed: adjustSpeed)
        }
        
        sqliteWrapper.finalizeSql()
        objc_sync_exit(sqliteWrapper)
        
        return profile
    }
    
    /// 缓存配置数据
    /// - Parameters:
    ///   - meshUUID: 网络id
    /// - Returns: 是否成功
    @discardableResult func save(meshUUID: String) -> Bool {
        
        objc_sync_enter(sqliteWrapper)
        guard sqliteWrapper.isOpen || sqliteWrapper.openDb(sqliteDBName), sqliteWrapper.prepareSql(Profile.SAVE_PROFILE) else {
            objc_sync_exit(sqliteWrapper)
            return false
        }
        
        let data = lightData.data
        sqliteWrapper.bindText(1, text: name)
        sqliteWrapper.bindText(2, text: id)
        sqliteWrapper.bindText(3, text: meshUUID)
        sqliteWrapper.bindInt(4, integer: sqlite3_int64(type.rawValue))
        sqliteWrapper.bindInt(5, integer: sqlite3_int64(data.highEndTrim))
        sqliteWrapper.bindInt(6, integer: sqlite3_int64(data.lowEndTrim))
        sqliteWrapper.bindInt(7, integer: sqlite3_int64(data.occupancyLevel))
        sqliteWrapper.bindInt(8, integer: sqlite3_int64(data.vacantLevel))
        sqliteWrapper.bindInt(9, integer: sqlite3_int64(data.taskLevel))
        sqliteWrapper.bindInt(10, integer: sqlite3_int64(data.autoMinLevelEnabled ? data.autoMinLevel : 255))
        sqliteWrapper.bindInt(11, integer: sqlite3_int64(data.t1))
        sqliteWrapper.bindInt(12, integer: sqlite3_int64(data.t2))
        sqliteWrapper.bindInt(13, integer: sqlite3_int64(data.t3))
        sqliteWrapper.bindInt(14, integer: sqlite3_int64(data.t4))
        sqliteWrapper.bindInt(15, integer: sqlite3_int64(data.t5))
        sqliteWrapper.bindInt(16, integer: sqlite3_int64(manualOverrideTimeout))
        sqliteWrapper.bindInt(17, integer: sqlite3_int64(powerUpState.rawValue))
        sqliteWrapper.bindInt(18, integer: sqlite3_int64(adjustSpeed))
        
        sqliteWrapper.stepSqlDone()
        sqliteWrapper.finalizeSql()
        objc_sync_exit(sqliteWrapper)
        return true
    }
    
    /// 删除网络全部日程数据
    /// - Parameter spaceId: 空间id
    /// - Returns: 是否成功
    @discardableResult static func deleteProfiles(meshUUID: String) -> Bool {
        
        objc_sync_enter(sqliteWrapper)
        guard sqliteWrapper.isOpen || sqliteWrapper.openDb(sqliteDBName), sqliteWrapper.prepareSql(DELETE_PROFILES) else {
            objc_sync_exit(sqliteWrapper)
            return false
        }
        
        sqliteWrapper.bindText(1, text: meshUUID)
        sqliteWrapper.stepSqlDone()
        sqliteWrapper.finalizeSql()
        //        sqliteWrapper.closeDb()
        objc_sync_exit(sqliteWrapper)
        return true
    }
    
    /// 删除网络全部日程数据
    /// - Parameter meshUUID: mesh网络id
    /// - Returns: 是否成功
    @discardableResult static func deleteProfile(meshUUID: String, profileId: String) -> Bool {
        
        objc_sync_enter(sqliteWrapper)
        guard sqliteWrapper.isOpen || sqliteWrapper.openDb(sqliteDBName), sqliteWrapper.prepareSql(DELETE_PROFILE) else {
            objc_sync_exit(sqliteWrapper)
            return false
        }
        
        sqliteWrapper.bindText(1, text: meshUUID)
        sqliteWrapper.bindText(2, text: profileId)
        sqliteWrapper.stepSqlDone()
        sqliteWrapper.finalizeSql()
        //        sqliteWrapper.closeDb()
        objc_sync_exit(sqliteWrapper)
        return true
    }
    
}

extension GroupSwitch {
    
    private static let CREAT_TABLE_ENOCEAN_SWITCHS = "CREATE TABLE IF NOT EXISTS ENOCEAN_SWITCHS(SWITCHS_ROW INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, id integer, mesh_uuid text, name text, enable bool, panel_type integer, group_address integer, sceneA_id integer, sceneB_id integer, proxy_address integer)"
    
    private static let CREATE_IDX_ENOCEAN_SWITCH = "CREATE UNIQUE INDEX IF NOT EXISTS IDX_ENOCEAN_SWITCH ON ENOCEAN_SWITCHS(mesh_uuid, group_address, id)"
    
    private static let SAVE_ENOCEAN_SWITCH = "INSERT OR REPLACE INTO ENOCEAN_SWITCHS(id, mesh_uuid, name, enable, panel_type, group_address, sceneA_id, sceneB_id, proxy_address) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?)"

    
    private static let GET_ENOCEAN_SWITCHS = "SELECT id, mesh_uuid, name, enable, panel_type, group_address, sceneA_id, sceneB_id, proxy_address FROM ENOCEAN_SWITCHS WHERE mesh_uuid = ? And group_address = ?"
    
    private static let GET_ENOCEAN_SWITCH_BY_ID = "SELECT id, mesh_uuid, name, enable, panel_type, group_address, sceneA_id, sceneB_id, proxy_address FROM ENOCEAN_SWITCHS WHERE mesh_uuid = ? AND group_address = ? AND id = ?"
    
    private static let GET_ENOCEAN_SWITCH_BY_PROXY = "SELECT id, mesh_uuid, name, enable, panel_type, group_address, sceneA_id, sceneB_id, proxy_address FROM ENOCEAN_SWITCHS WHERE mesh_uuid = ? AND proxy_address = ?"
    

    private static let DELETE_ALL_ENOCEAN_SWITCHS = "DELETE FROM ENOCEAN_SWITCHS WHERE mesh_uuid = ?"
    
    private static let DELETE_ENOCEAN_SWITCHS = "DELETE FROM ENOCEAN_SWITCHS WHERE mesh_uuid = ? AND group_address = ?"
    
    private static let DELETE_ENOCEAN_SWITCH = "DELETE FROM ENOCEAN_SWITCHS WHERE mesh_uuid = ? AND group_address = ? AND id = ?"
    
    
    /// 初始化数据库缓存
    static func createDatabaseIfNotExit() {
        objc_sync_enter(sqliteWrapper)
        if sqliteWrapper.isOpen || sqliteWrapper.openDb(sqliteDBName) {
            sqliteWrapper.execSql(CREAT_TABLE_ENOCEAN_SWITCHS)
            sqliteWrapper.execSql(CREATE_IDX_ENOCEAN_SWITCH)
            //        sqliteWrapper.closeDb()
        }
        objc_sync_exit(sqliteWrapper)
    }
    
    /// 根据网络id、组地址获取组下的所有的虚拟按键数据
    /// - Parameter meshUUID: 网络id
    /// - Parameter groupAddress: 组地址
    /// - Returns: 虚拟按键数据list
    static func loadAll(meshUUID: String, groupAddress: Address) -> [GroupSwitch] {
        objc_sync_enter(sqliteWrapper)
        
        guard sqliteWrapper.isOpen || sqliteWrapper.openDb(sqliteDBName), sqliteWrapper.prepareSql(GET_ENOCEAN_SWITCHS),
              MeshNetworkManager.instance.meshNetwork?.uuid.uuidString == meshUUID,
              let group = MeshNetworkManager.instance.meshNetwork?.group(withAddress: MeshAddress(groupAddress)) else {
            objc_sync_exit(sqliteWrapper)
            return []
        }
        sqliteWrapper.bindText(1, text: meshUUID)
        sqliteWrapper.bindInt(2, integer: sqlite3_int64(groupAddress))
        
        var switchs: [GroupSwitch] = []
        while sqliteWrapper.stepSqlRow() {
            
            let id = Int(sqliteWrapper.columnInt(0))
            let name = sqliteWrapper.columnText(2)
            let enabled = sqliteWrapper.columnBool(3)
            let panelType: PanelType = .init(rawValue: UInt8(sqliteWrapper.columnInt(4))) ?? .default
            let sceneANumber = UInt16(sqliteWrapper.columnInt(6))
            let sceneBNumber = UInt16(sqliteWrapper.columnInt(7))
            let proxyAddress = sqliteWrapper.columnInt(8)

            let groupSwitch = GroupSwitch(id: id, group: group, enabled: enabled, name: name ?? "")
            groupSwitch.panelType = panelType
            if sceneANumber > 0, let sceneA = MeshNetworkManager.instance.scenes.first(where: { $0.number == sceneANumber }) {
                groupSwitch.sceneA = sceneA
            }
            if sceneBNumber > 0, let sceneB = MeshNetworkManager.instance.scenes.first(where: { $0.number == sceneBNumber }) {
                groupSwitch.sceneB = sceneB
            }
            if proxyAddress > 0, let proxyNode = MeshNetworkManager.instance.meshNetwork?.node(withAddress: Address(proxyAddress)) {
                groupSwitch.proxyNode = proxyNode
            }
            switchs.append(groupSwitch)
        }
        
        sqliteWrapper.finalizeSql()
        objc_sync_exit(sqliteWrapper)
        
        return switchs
    }
    
    /// 根据网络id和组地址、id获取网络下的指定的虚拟按键数据
    /// - Parameter meshUUID: 网络id
    /// - Parameter groupAddress: 组地址
    /// - Parameter id: 虚拟按键id
    /// - Returns: 按键数据
    static func load(meshUUID: String, groupAddress: Address, id: Int) -> GroupSwitch? {
        objc_sync_enter(sqliteWrapper)
        guard sqliteWrapper.isOpen || sqliteWrapper.openDb(sqliteDBName), sqliteWrapper.prepareSql(GET_ENOCEAN_SWITCH_BY_ID),
              MeshNetworkManager.instance.meshNetwork?.uuid.uuidString == meshUUID,
              let group = MeshNetworkManager.instance.meshNetwork?.group(withAddress: MeshAddress(groupAddress))else {
            objc_sync_exit(sqliteWrapper)
            return nil
        }
        sqliteWrapper.bindText(1, text: meshUUID)
        sqliteWrapper.bindInt(2, integer: sqlite3_int64(groupAddress))
        sqliteWrapper.bindInt(3, integer: sqlite3_int64(id))
        
        var groupSwitch: GroupSwitch?
        while sqliteWrapper.stepSqlRow() {
            
            let id = Int(sqliteWrapper.columnInt(0))
            let name = sqliteWrapper.columnText(2)
            let enabled = sqliteWrapper.columnBool(3)
            let panelType: PanelType = .init(rawValue: UInt8(sqliteWrapper.columnInt(4))) ?? .default
            let sceneANumber = UInt16(sqliteWrapper.columnInt(6))
            let sceneBNumber = UInt16(sqliteWrapper.columnInt(7))
            let proxyAddress = sqliteWrapper.columnInt(8)

            groupSwitch = GroupSwitch(id: id, group: group, enabled: enabled, name: name ?? "")
            groupSwitch?.panelType = panelType
            if sceneANumber > 0, let sceneA = MeshNetworkManager.instance.scenes.first(where: { $0.number == sceneANumber }) {
                groupSwitch?.sceneA = sceneA
            }
            if sceneBNumber > 0, let sceneB = MeshNetworkManager.instance.scenes.first(where: { $0.number == sceneBNumber }) {
                groupSwitch?.sceneB = sceneB
            }
            if proxyAddress > 0, let proxyNode = MeshNetworkManager.instance.meshNetwork?.node(withAddress: Address(proxyAddress)) {
                groupSwitch?.proxyNode = proxyNode
            }
        }
        
        sqliteWrapper.finalizeSql()
        objc_sync_exit(sqliteWrapper)
        
        return groupSwitch
    }
    
    /// 根据网络id获取网络下的所有的虚拟按键数据
    /// - Parameter meshUUID: 网络id
    /// - Parameter switchMac: 虚拟按键mac
    /// - Returns: 按键数据
    static func load(meshUUID: String, proxyAddress: UInt16) -> GroupSwitch? {
        objc_sync_enter(sqliteWrapper)
        guard sqliteWrapper.isOpen || sqliteWrapper.openDb(sqliteDBName), sqliteWrapper.prepareSql(GET_ENOCEAN_SWITCH_BY_PROXY),
              MeshNetworkManager.instance.meshNetwork?.uuid.uuidString == meshUUID else {
            objc_sync_exit(sqliteWrapper)
            return nil
        }
        sqliteWrapper.bindText(1, text: meshUUID)
        sqliteWrapper.bindInt(2, integer: sqlite3_int64(proxyAddress))
        
        var groupSwitch: GroupSwitch?
        while sqliteWrapper.stepSqlRow() {
            
            let id = Int(sqliteWrapper.columnInt(0))
            let name = sqliteWrapper.columnText(2)
            let enabled = sqliteWrapper.columnBool(3)
            let panelType: PanelType = .init(rawValue: UInt8(sqliteWrapper.columnInt(4))) ?? .default
            let groupAddress = UInt16(sqliteWrapper.columnInt(5))
            let sceneANumber = UInt16(sqliteWrapper.columnInt(6))
            let sceneBNumber = UInt16(sqliteWrapper.columnInt(7))
            let proxyAddress = sqliteWrapper.columnInt(8)
            
            if let group = MeshNetworkManager.instance.meshNetwork?.group(withAddress: MeshAddress(groupAddress)) {
                groupSwitch = GroupSwitch(id: id, group: group, enabled: enabled, name: name ?? "")
                groupSwitch?.panelType = panelType
                if sceneANumber > 0, let sceneA = MeshNetworkManager.instance.scenes.first(where: { $0.number == sceneANumber }) {
                    groupSwitch?.sceneA = sceneA
                }
                if sceneBNumber > 0, let sceneB = MeshNetworkManager.instance.scenes.first(where: { $0.number == sceneBNumber }) {
                    groupSwitch?.sceneB = sceneB
                }
                if proxyAddress > 0, let proxyNode = MeshNetworkManager.instance.meshNetwork?.node(withAddress: Address(proxyAddress)) {
                    groupSwitch?.proxyNode = proxyNode
                }
            }
            
        }
        
        sqliteWrapper.finalizeSql()
        objc_sync_exit(sqliteWrapper)
        
        return groupSwitch
    }
    
    
    /// 缓存虚拟按键数据
    /// - Parameters:
    ///   - meshUUID: 网络id
    /// - Returns: 是否成功
    @discardableResult func save(meshUUID: String) -> Bool {
        
        objc_sync_enter(sqliteWrapper)
        guard sqliteWrapper.isOpen || sqliteWrapper.openDb(sqliteDBName), sqliteWrapper.prepareSql(GroupSwitch.SAVE_ENOCEAN_SWITCH) else {
            objc_sync_exit(sqliteWrapper)
            return false
        }

        sqliteWrapper.bindInt(1, integer: sqlite3_int64(id))
        sqliteWrapper.bindText(2, text: meshUUID)
        sqliteWrapper.bindText(3, text: name)
        sqliteWrapper.bindBool(4, boolean: enabled)
        sqliteWrapper.bindInt(5, integer: sqlite3_int64(panelType.rawValue))
        sqliteWrapper.bindInt(6, integer: sqlite3_int64(group.address.address))
        sqliteWrapper.bindInt(7, integer: sqlite3_int64(sceneA?.number ?? 0))
        sqliteWrapper.bindInt(8, integer: sqlite3_int64(sceneB?.number ?? 0))
        sqliteWrapper.bindInt(9, integer: sqlite3_int64(proxyNode?.primaryUnicastAddress ?? 0))
        
        sqliteWrapper.stepSqlDone()
        sqliteWrapper.finalizeSql()
        objc_sync_exit(sqliteWrapper)
        return true
    }
    
    /// 删除网络内全部虚拟按键数据
    /// - Parameter spaceId: 空间id
    /// - Returns: 是否成功
    @discardableResult static func deleteSwitchs(meshUUID: String) -> Bool {
        
        objc_sync_enter(sqliteWrapper)
        guard sqliteWrapper.isOpen || sqliteWrapper.openDb(sqliteDBName), sqliteWrapper.prepareSql(DELETE_ALL_ENOCEAN_SWITCHS) else {
            objc_sync_exit(sqliteWrapper)
            return false
        }
        
        sqliteWrapper.bindText(1, text: meshUUID)
        sqliteWrapper.stepSqlDone()
        sqliteWrapper.finalizeSql()
        //        sqliteWrapper.closeDb()
        objc_sync_exit(sqliteWrapper)
        return true
    }
    
    /// 删除网络内组全部虚拟按键数据
    /// - Parameter spaceId: 空间id
    /// - Returns: 是否成功
    @discardableResult static func deleteSwitchs(meshUUID: String, groupAddress: Address) -> Bool {
        
        objc_sync_enter(sqliteWrapper)
        guard sqliteWrapper.isOpen || sqliteWrapper.openDb(sqliteDBName), sqliteWrapper.prepareSql(DELETE_ENOCEAN_SWITCHS) else {
            objc_sync_exit(sqliteWrapper)
            return false
        }
        
        sqliteWrapper.bindText(1, text: meshUUID)
        sqliteWrapper.bindInt(2, integer: sqlite3_int64(groupAddress))
        sqliteWrapper.stepSqlDone()
        sqliteWrapper.finalizeSql()
        //        sqliteWrapper.closeDb()
        objc_sync_exit(sqliteWrapper)
        return true
    }
    
    /// 删除网络内组的虚拟按键数据
    /// - Parameter meshUUID: mesh网络id
    /// - Parameter groupAddress: 组地址
    /// - Parameter id: id
    /// - Returns: 是否成功
    @discardableResult static func deleteProfile(meshUUID: String, groupAddress: Address, switchId: Int) -> Bool {
        
        objc_sync_enter(sqliteWrapper)
        guard sqliteWrapper.isOpen || sqliteWrapper.openDb(sqliteDBName), sqliteWrapper.prepareSql(DELETE_ENOCEAN_SWITCH) else {
            objc_sync_exit(sqliteWrapper)
            return false
        }
        
        sqliteWrapper.bindText(1, text: meshUUID)
        sqliteWrapper.bindInt(2, integer: sqlite3_int64(groupAddress))
        sqliteWrapper.bindInt(3, integer: sqlite3_int64(switchId))
        sqliteWrapper.stepSqlDone()
        sqliteWrapper.finalizeSql()
        //        sqliteWrapper.closeDb()
        objc_sync_exit(sqliteWrapper)
        return true
    }
    
}
