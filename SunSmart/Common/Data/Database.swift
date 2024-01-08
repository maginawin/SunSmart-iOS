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
    
    static let CREAT_TABLE_SPACES = "CREATE TABLE IF NOT EXISTS SPACES(SPACE_ROW INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, SPACE_NAME TEXT, SPACE_ID TEXT, SITE_ID TEXT, SPACE_IMAGE_ID INTEGER, SPACE_CREATE TEXT, SPACE_LASTUPDATE TEXT, SPACE_SOURCE INTEGER, SPACE_FAVOURITE BOOL, SPACE_MESHUUID TEXT, SPACE_LUMINAIRES_COUNT INTEGER, SPACE_SWITCHES_COUNT INTEGER, SPACE_DEVICE_COUNT INTEGER, SPACE_GROUP_COUNT INTEGER, SPACE_SCENE_COUNT INTEGER, SPACE_SCHEHEDULE_COUNT INTEGER, SPACE_DEVICES_SORT_TYPE INTEGER)"
    
    static let CREATE_IDX_SPACES_SPACE = "CREATE UNIQUE INDEX IF NOT EXISTS IDX_SPACES_SPACE ON SPACES(SPACE_ID, SITE_ID)"
    
    static let SAVE_SPACES = "INSERT OR REPLACE INTO SPACES(SPACE_NAME, SPACE_ID, SITE_ID, SPACE_IMAGE_ID, SPACE_CREATE, SPACE_LASTUPDATE, SPACE_SOURCE, SPACE_FAVOURITE, SPACE_MESHUUID, SPACE_LUMINAIRES_COUNT, SPACE_SWITCHES_COUNT, SPACE_DEVICE_COUNT, SPACE_GROUP_COUNT, SPACE_SCENE_COUNT, SPACE_SCHEHEDULE_COUNT, SPACE_DEVICES_SORT_TYPE) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"

    static let GET_SPACES = "SELECT SPACE_NAME, SPACE_ID, SITE_ID, SPACE_IMAGE_ID, SPACE_CREATE, SPACE_LASTUPDATE, SPACE_SOURCE, SPACE_FAVOURITE, SPACE_MESHUUID, SPACE_LUMINAIRES_COUNT, SPACE_SWITCHES_COUNT, SPACE_DEVICE_COUNT, SPACE_GROUP_COUNT, SPACE_SCENE_COUNT, SPACE_SCHEHEDULE_COUNT, SPACE_DEVICES_SORT_TYPE FROM SPACES WHERE SITE_ID = ? ORDER BY SPACE_CREATE"
    
    static let GET_SPACE_BY_ID = "SELECT SPACE_NAME, SPACE_ID, SITE_ID, SPACE_IMAGE_ID, SPACE_CREATE, SPACE_LASTUPDATE, SPACE_SOURCE, SPACE_FAVOURITE, SPACE_MESHUUID, SPACE_LUMINAIRES_COUNT, SPACE_SWITCHES_COUNT, SPACE_DEVICE_COUNT, SPACE_GROUP_COUNT, SPACE_SCENE_COUNT, SPACE_SCHEHEDULE_COUNT, SPACE_DEVICES_SORT_TYPE FROM SPACES WHERE SPACE_ID = ? AND SITE_ID = ?"
    
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
                space.deviceSortType = .init(rawValue: Int(sqliteWrapper.columnInt(15))) ?? .addDate
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
            space?.deviceSortType = .init(rawValue: Int(sqliteWrapper.columnInt(15))) ?? .addDate
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
    
    private static let CREAT_TABLE_GROUPS_INFO = "CREATE TABLE IF NOT EXISTS GROUPS_INFO(GROUPS_INFO_ROW INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, GROUP_NAME TEXT, GROUP_ADDRESS INTEGER, MESH_UUID TEXT, GROUP_IMAGE_ID INTEGER, GROUP_IMAGE_TEXT TEXT)"
    
    private static let CREATE_IDX_GROUPS_INFO = "CREATE UNIQUE INDEX IF NOT EXISTS IDX_GROUPS_INFO ON GROUPS_INFO(MESH_UUID, GROUP_ADDRESS)"
    
    private static let SAVE_GROUPS_INFO = "INSERT OR REPLACE INTO GROUPS_INFO(GROUP_NAME, GROUP_ADDRESS, MESH_UUID, GROUP_IMAGE_ID, GROUP_IMAGE_TEXT) VALUES(?, ?, ?, ?, ?)"

    private static let GET_GROUPS_INFO = "SELECT GROUP_NAME, GROUP_ADDRESS, MESH_UUID, GROUP_IMAGE_ID, GROUP_IMAGE_TEXT FROM GROUPS_INFO WHERE MESH_UUID = ?"
    
    private static let GET_GROUP_INFO_BY_ID = "SELECT GROUP_NAME, GROUP_ADDRESS, MESH_UUID, GROUP_IMAGE_ID, GROUP_IMAGE_TEXT FROM GROUPS_INFO WHERE MESH_UUID = ? AND GROUP_ADDRESS = ?"
    
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
        while sqliteWrapper.stepSqlRow() {
            
            let address = sqliteWrapper.columnInt(1)
            let imageId = sqliteWrapper.columnInt(3)
            let imageText = sqliteWrapper.columnText(4)
            
            groupInfo = GroupInfo(address: UInt16(address), imageId: Int(imageId))
            if let name = sqliteWrapper.columnText(0) {
                groupInfo!.name = name
            }
            groupInfo!.imageText = imageText
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
        
        return groupInfo
    }
    
    /// 删除所有组扩展数据
    /// - Parameter meshUUID: 对应网络id
    /// - Returns: 是否成功
    static func deleteAll(meshUUID: String) -> Bool {
        
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
        
        let groups = targetAddresss.compactMap({ MeshNetworkManager.instance.meshNetwork?.group(withAddress: MeshAddress($0)) })
        sceneInfo?.groups = groups
        
        return sceneInfo
    }
    
    /// 删除所有场景扩展数据
    /// - Parameter meshUUID: 对应网络id
    /// - Returns: 是否成功
    static func deleteAll(meshUUID: String) -> Bool {
        
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
    static func deleteAll(meshUUID: String) -> Bool {
        
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
    
    static let CREAT_TABLE_SCHEDULES = "CREATE TABLE IF NOT EXISTS SCHEDULES(SCHEDULE_ROW INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, SCHEDULE_NAME TEXT, SCHEDULE_ID TEXT, MESH_UUID TEXT, SCHEDULE_CREATE TEXT, SCHEDULE_LASTUPDATE TEXT, SCHEDULE_ENABLED BOOL, DEVICE_ADDRESS TEXT, GROUP_ADDRESS TEXT, DELETE_DEVICE_ADDRESS TEXT, DELETE_GROUP_ADDRESS TEXT, SCENE_ID INTEGER, SELECT_TYPE INTEGER, ACTION_TYPE INTEGER, FADETIME INTEGER, WEEKDAYS INTEGER, HOUR INTEGER, MINUTE INTEGER, SECOND INTEGER)"
    
    static let CREATE_IDX_SCHEDULES_SCHEDULE = "CREATE UNIQUE INDEX IF NOT EXISTS IDX_SCHEDULES_SCHEDULE ON SCHEDULES(SCHEDULE_ID, MESH_UUID)"
    
    static let SAVE_SCHEDULES = "INSERT OR REPLACE INTO SCHEDULES(SCHEDULE_NAME, SCHEDULE_ID, MESH_UUID, SCHEDULE_CREATE, SCHEDULE_LASTUPDATE, SCHEDULE_ENABLED, DEVICE_ADDRESS, GROUP_ADDRESS, DELETE_NODE_ADDRESS, DELETE_GROUP_ADDRESS, SCENE_ID, SELECT_TYPE, ACTION_TYPE, FADETIME, WEEKDAYS, HOUR, MINUTE, SECOND) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"

    static let GET_SCHEDULES = "SELECT SCHEDULE_NAME, SCHEDULE_ID, MESH_UUID, SCHEDULE_CREATE, SCHEDULE_LASTUPDATE, SCHEDULE_ENABLED, DEVICE_ADDRESS, GROUP_ADDRESS, DELETE_NODE_ADDRESS, DELETE_GROUP_ADDRESS, SCENE_ID, SELECT_TYPE, ACTION_TYPE, FADETIME, WEEKDAYS, HOUR, MINUTE, SECOND FROM SCHEDULES WHERE MESH_UUID = ? ORDER BY SCHEDULE_CREATE"
    
    static let GET_SCHEDULE_BY_ID = "SELECT SCHEDULE_NAME, SCHEDULE_ID, MESH_UUID, SCHEDULE_CREATE, SCHEDULE_LASTUPDATE, SCHEDULE_ENABLED, DEVICE_ADDRESS, GROUP_ADDRESS, DELETE_NODE_ADDRESS, DELETE_GROUP_ADDRESS, SCENE_ID, SELECT_TYPE, ACTION_TYPE, FADETIME, WEEKDAYS, HOUR, MINUTE, SECOND FROM SCHEDULES WHERE MESH_UUID = ? AND SCHEDULE_ID = ?"
    
    static let GET_NEXT_SCHEDULE_NAME = "SELECT SPACE_NAME FROM SPACES WHERE MESH_UUID = ? AND SCHEDULE_NAME LIKE ?"
    
    static let GET_TAUTONY_SCHEDULE_NAME = "SELECT SPACE_NAME FROM SPACES WHERE MESH_UUID = ? AND SCHEDULE_NAME = ?"

    static let DELETE_SCHEDULES = "DELETE FROM SPACES WHERE MESH_UUID = ?"
    
    static let DELETE_SCHEDULE = "DELETE FROM SPACES WHERE MESH_UUID = ? AND SCHEDULE_ID = ?"
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
            let scheduleId = UInt16(sqliteWrapper.columnInt(10))
            let selectTargetType = Int(sqliteWrapper.columnInt(11))
            let actionType = UInt8(sqliteWrapper.columnInt(12))
            let fadeTime = Int(sqliteWrapper.columnInt(13))
            let weekDaysValue = Int(sqliteWrapper.columnInt(14))
            let hour = Int(sqliteWrapper.columnInt(15))
            let minute = Int(sqliteWrapper.columnInt(16))
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
            if meshUUID == MeshNetworkManager.instance.meshNetwork?.uuid.uuidString {
                // 获取对应的组 "组地址0,组地址1..."
                groups = groupAddressStr?.components(separatedBy: ",").compactMap({ MeshNetworkManager.instance.meshNetwork?.group(withAddress: UInt16($0) ?? 0) }) ?? []
                deleteGroups = deleteGroupAddressStr?.components(separatedBy: ",").compactMap({ MeshNetworkManager.instance.meshNetwork?.group(withAddress: UInt16($0) ?? 0) }) ?? []
                
                // 获取对应的设备 "设备地址0,设备地址1..."
                nodes = deviceAddressStr?.components(separatedBy: ",").compactMap({ MeshNetworkManager.instance.meshNetwork?.node(withAddress: UInt16($0) ?? 0) }) ?? []
                deleteNodes = deleteDeviceAddressStr?.components(separatedBy: ",").compactMap({ MeshNetworkManager.instance.meshNetwork?.node(withAddress: UInt16($0) ?? 0) }) ?? []
            }
           
            let schedule = Schedule(id: Int(sqliteWrapper.columnInt(1)), name: sqliteWrapper.columnText(0), enabled: sqliteWrapper.columnBool(5), nodes: nodes, groups: groups, actionSceneId: scheduleId, action: SchedulerAction(rawValue: actionType) ?? .noAction, fadeTime: fadeTime, weekDays: selectWeekDays, hour: hour, minute: minute, create: sqliteWrapper.columnText(3), lastUpdate: sqliteWrapper.columnText(4))
            schedule.selectTargetType = .init(rawValue: selectTargetType) ?? .groups
            schedule.needDeleteGroups = deleteGroups
            schedule.needDeleteNodes = deleteNodes
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
            let scheduleId = UInt16(sqliteWrapper.columnInt(10))
            let selectTargetType = Int(sqliteWrapper.columnInt(11))
            let actionType = UInt8(sqliteWrapper.columnInt(12))
            let fadeTime = Int(sqliteWrapper.columnInt(13))
            let weekDaysValue = Int(sqliteWrapper.columnInt(14))
            let hour = Int(sqliteWrapper.columnInt(15))
            let minute = Int(sqliteWrapper.columnInt(16))
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
            if meshUUID == MeshNetworkManager.instance.meshNetwork?.uuid.uuidString {
                // 获取对应的组 "组地址0,组地址1..."
                groups = groupAddressStr?.components(separatedBy: ",").compactMap({ MeshNetworkManager.instance.meshNetwork?.group(withAddress: UInt16($0) ?? 0) }) ?? []
                deleteGroups = deleteGroupAddressStr?.components(separatedBy: ",").compactMap({ MeshNetworkManager.instance.meshNetwork?.group(withAddress: UInt16($0) ?? 0) }) ?? []
                
                // 获取对应的设备 "设备地址0,设备地址1..."
                nodes = deviceAddressStr?.components(separatedBy: ",").compactMap({ MeshNetworkManager.instance.meshNetwork?.node(withAddress: UInt16($0) ?? 0) }) ?? []
                deleteNodes = deleteDeviceAddressStr?.components(separatedBy: ",").compactMap({ MeshNetworkManager.instance.meshNetwork?.node(withAddress: UInt16($0) ?? 0) }) ?? []
            }
           
            sceneData = Schedule(id: Int(sqliteWrapper.columnInt(1)), name: sqliteWrapper.columnText(0), enabled: sqliteWrapper.columnBool(5), nodes: nodes, groups: groups, actionSceneId: scheduleId, action: SchedulerAction(rawValue: actionType) ?? .noAction, fadeTime: fadeTime, weekDays: selectWeekDays, hour: hour, minute: minute, create: sqliteWrapper.columnText(3), lastUpdate: sqliteWrapper.columnText(4))
            sceneData?.needDeleteNodes = deleteNodes
            sceneData?.needDeleteGroups = deleteGroups
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
            $0.groups.contains(where: { $0.address.address == address }) || $0.nodes.contains(where: { $0.primaryUnicastAddress == address })
        })
        return bindSchedules
    }
 
    /// 删除网络内所有配置的日程数据
    /// - Parameter meshUUID: 对应网络id
    /// - Returns: 是否成功
    static func deleteAll(meshUUID: String) -> Bool {
        
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
    @discardableResult func deleteData(meshUUID: String, scheduleId: Int) -> Bool {
        
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
        needDeleteGroups.forEach({ groupAddressStr += "\(groupAddressStr.isEmpty ? "" : ",")\($0.address.address)" })
        var nodeAddressStr = ""
        var deleteNodeAddressStr = ""
        nodes.forEach({ nodeAddressStr += "\(nodeAddressStr.isEmpty ? "" : ",")\($0.primaryUnicastAddress)" })
        needDeleteNodes.forEach({ deleteNodeAddressStr += "\(deleteNodeAddressStr.isEmpty ? "" : ",")\($0.primaryUnicastAddress)" })
        sqliteWrapper.bindText(7, text: nodeAddressStr)
        sqliteWrapper.bindText(8, text: groupAddressStr)
        sqliteWrapper.bindText(9, text: deleteNodeAddressStr)
        sqliteWrapper.bindText(10, text: deleteGroupAddressStr)
        
        sqliteWrapper.bindInt(11, integer: sqlite3_int64(actionSceneId))
        sqliteWrapper.bindInt(12, integer: sqlite3_int64(selectTargetType.rawValue))
        sqliteWrapper.bindInt(13, integer: sqlite3_int64(action.rawValue))
        sqliteWrapper.bindInt(14, integer: sqlite3_int64(fadeTime))
        var weekdayValue = 0
        weekDays.forEach({ weekdayValue += Int($0.rawValue) })
        sqliteWrapper.bindInt(15, integer: sqlite3_int64(weekdayValue))
        sqliteWrapper.bindInt(16, integer: sqlite3_int64(hour))
        sqliteWrapper.bindInt(17, integer: sqlite3_int64(minute))
        
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
    
    private static let CREAT_TABLE_NODE_INFOS = "CREATE TABLE IF NOT EXISTS NODE_INFOS(NODE_ROW INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, ADDRESS INTEGER, MAC_ADDRESS TEXT, MESH_UUID TEXT, CCT_RANGE_MIN INTEGER, CCT_RANGE_MAX INTEGER, RSSI INTEGER, GROUP_STATE INTEGER)"
    
    private static let CREATE_IDX_NODE_INFO = "CREATE UNIQUE INDEX IF NOT EXISTS IDX_NODE_INFO ON NODE_INFOS(ADDRESS, MESH_UUID)"
    
    private static let SAVE_NODE_INFO = "INSERT OR REPLACE INTO NODE_INFOS(ADDRESS, MAC_ADDRESS, MESH_UUID, CCT_RANGE_MIN, CCT_RANGE_MAX, RSSI, GROUP_STATE) VALUES(?, ?, ?, ?, ?, ?, ?)"
    
    private static let GET_NODE_INFOS = "SELECT ADDRESS, MAC_ADDRESS, MESH_UUID, CCT_RANGE_MIN, CCT_RANGE_MAX, RSSI, GROUP_STATE FROM NODE_INFOS WHERE MESH_UUID = ?"
    
    private static let GET_NODE_INFO_BY_ID = "SELECT ADDRESS, MAC_ADDRESS, MESH_UUID, CCT_RANGE_MIN, CCT_RANGE_MAX, RSSI, GROUP_STATE FROM NODE_INFOS WHERE MESH_UUID = ? AND ADDRESS = ?"
    
    private static let DELETE_NODE_INFOS = "DELETE FROM NODE_INFOS WHERE MESH_UUID = ?"
    
    private static let DELETE_NODE_INFO = "DELETE FROM NODE_INFOS WHERE MESH_UUID = ? AND ADDRESS = ?"
    
    /// node-schedule
    private static let CREAT_TABLE_NODE_SCHEDULES = "CREATE TABLE IF NOT EXISTS NODE_SCHEDULES(NODE_SCHEDULES_ROW INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, ADDRESS INTEGER, MESH_UUID TEXT, SCHEDULE_ID INTEGER, SCHEDULE_DATA BLOB)"
    
    private static let CREATE_IDX_NODE_SCHEDULES = "CREATE UNIQUE INDEX IF NOT EXISTS IDX_NODE_SCHEDULES ON NODE_SCHEDULES(ADDRESS, MESH_UUID, SCHEDULE_ID)"
    
    private static let SAVE_NODE_SCHEDULE = "INSERT OR REPLACE INTO NODE_SCHEDULES(ADDRESS, MESH_UUID, SCHEDULE_ID, SCHEDULE_DATA) VALUES(?, ?, ?, ?)"
    
    private static let GET_NODE_SCHEDULES = "SELECT ADDRESS, MESH_UUID, SCHEDULE_ID, SCHEDULE_DATA FROM NODE_SCHEDULES WHERE MESH_UUID = ? AND ADDRESS = ?"
    
    private static let GET_NODE_SCHEDULE = "SELECT ADDRESS, MESH_UUID, SCHEDULE_ID, SCHEDULE_DATA FROM NODE_SCHEDULES WHERE MESH_UUID = ? AND ADDRESS = ? AND SCHEDULE_ID = ?"
    
    private static let DELETE_NETWORK_SCHEDULES = "DELETE FROM NODE_INFOS WHERE MESH_UUID = ?"
    
    private static let DELETE_NODE_SCHEDULES = "DELETE FROM NODE_INFOS WHERE MESH_UUID = ? AND ADDRESS = ?"
    
    private static let DELETE_NODE_SCHEDULE = "DELETE FROM NODE_INFOS WHERE MESH_UUID = ? AND ADDRESS = ? AND SCHEDULE_ID = ?"
    
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
            let groupState: GroupState = .init(rawValue: Int(sqliteWrapper.columnInt(5))) ?? .none
            let schedules = loadAllSchedule(meshUUID: meshUUID, address: address)
            var scheduleDatas: [Int: SchedulerRegistryEntry] = [:]
            schedules.forEach({
                scheduleDatas.updateValue($0.entry, forKey: $0.scheduleId)
            })
            
            let scenes = SceneExecuteData.loadAll(meshUUID: meshUUID, address: address)
            var sceneDatas: [Int: SceneExecuteData] = [:]
            scenes.forEach({
                sceneDatas.updateValue($0.data, forKey: $0.sceneId)
            })
            
            nodeInfos.append(NodeInfo(address: address, mac: mac, cctRange: cctRange, rssi: rssi, groupState: groupState, schedules: scheduleDatas, sceneDatas: sceneDatas))
        }
      
        sqliteWrapper.finalizeSql()
        //        sqliteWrapper.closeDb()
        objc_sync_exit(sqliteWrapper)

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
            let groupState: GroupState = .init(rawValue: Int(sqliteWrapper.columnInt(5))) ?? .none
            
//            loadAllSchedule(meshUUID: meshUUID, address: address)
            let schedules = loadAllSchedule(meshUUID: meshUUID, address: address)
            var scheduleDatas: [Int: SchedulerRegistryEntry] = [:]
            schedules.forEach({
                scheduleDatas.updateValue($0.entry, forKey: $0.scheduleId)
            })
            
            let scenes = SceneExecuteData.loadAll(meshUUID: meshUUID, address: address)
            var sceneDatas: [Int: SceneExecuteData] = [:]
            scenes.forEach({
                sceneDatas.updateValue($0.data, forKey: $0.sceneId)
            })
            
            nodeInfo = NodeInfo(address: address, mac: mac, cctRange: cctRange, rssi: rssi, groupState: groupState, schedules: scheduleDatas, sceneDatas: sceneDatas)
        }
      
        sqliteWrapper.finalizeSql()
        //        sqliteWrapper.closeDb()
        objc_sync_exit(sqliteWrapper)

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
        sqliteWrapper.bindInt(5, integer: sqlite3_int64((lightCTLTemperatureRange ?? defalutLightCTLTemperatureRange).lowerBound))
        sqliteWrapper.bindInt(6, integer: sqlite3_int64(rssi ?? -99))
        sqliteWrapper.bindInt(7, integer: sqlite3_int64(groupState.rawValue))
        sqliteWrapper.stepSqlDone()
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
                schedules.append(SchedulerRegistryEntry.unmarshal(scheduleData) as! (Int, SchedulerRegistryEntry))
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
    static func loadSchedule(meshUUID: String, address: UInt16, scheduleId: Int) -> (scheduleId: Int, entry: SchedulerRegistryEntry)? {
        objc_sync_enter(sqliteWrapper)
        guard sqliteWrapper.isOpen || sqliteWrapper.openDb(sqliteDBName), sqliteWrapper.prepareSql(GET_NODE_SCHEDULE) else {
            objc_sync_exit(sqliteWrapper)
            return nil
        }
        sqliteWrapper.bindText(1, text: meshUUID)
        sqliteWrapper.bindInt(2, integer: sqlite3_int64(address))
        sqliteWrapper.bindInt(3, integer: sqlite3_int64(scheduleId))
        
        var schedule: (Int, SchedulerRegistryEntry)?
        while sqliteWrapper.stepSqlRow() {
            
//            let groupAddress = UInt16(sqliteWrapper.columnInt(0))
//            let scheduleId = Int(sqliteWrapper.columnInt(2))
            if let scheduleData = sqliteWrapper.columnBlob(3), scheduleData.count == 10 {
                schedule = SchedulerRegistryEntry.unmarshal(scheduleData) as? (Int, SchedulerRegistryEntry)
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
        guard sqliteWrapper.isOpen || sqliteWrapper.openDb(sqliteDBName), sqliteWrapper.prepareSql(Node.SAVE_NODE_SCHEDULE), data == nil && entry == nil else {
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
    

    struct NodeInfo {
        let address: UInt16
        let mac: String?
        let cctRange: ClosedRange<UInt16>
        let rssi: Int
        let groupState: Node.GroupState
        let schedules: [Int: SchedulerRegistryEntry]
        let sceneDatas: [Int: SceneExecuteData]
    }
    
}

