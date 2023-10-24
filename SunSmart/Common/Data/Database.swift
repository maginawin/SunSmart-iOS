//
//  Database.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/8/24.
//

import Foundation

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
        if sqliteWrapper.openDb(sqliteDBName) {
            sqliteWrapper.execSql(SiteData.CREATE_TABLE_SITES)
            sqliteWrapper.execSql(SiteData.CREATE_IDX_SITES_SITE)
            sqliteWrapper.closeDb()
        }
        objc_sync_exit(sqliteWrapper)
        
        SpaceData.createDatabaseIfNotExit()
    }
    
    /// 获取所有的场所
    /// - Returns: mesh网络list
    static func loadAll() -> [SiteData] {
        
        objc_sync_enter(sqliteWrapper)
        guard sqliteWrapper.openDb(sqliteDBName), sqliteWrapper.prepareSql(SiteData.GET_SITES) else {
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
        sqliteWrapper.closeDb()
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
        guard sqliteWrapper.openDb(sqliteDBName), sqliteWrapper.prepareSql(SiteData.GET_SITE_BY_ID) else {
            objc_sync_exit(sqliteWrapper)
            return nil
        }
        
        sqliteWrapper.bindText(1, text: siteId)
        var site: SiteData?
        
        while sqliteWrapper.stepSqlRow() {
            site = SiteData(id: sqliteWrapper.columnText(0), name: sqliteWrapper.columnText(1), imageId: Int(sqliteWrapper.columnInt(2)), type: SiteType(rawValue: Int(sqliteWrapper.columnInt(3))) ?? .other, create: sqliteWrapper.columnText(4), lastUpdate: sqliteWrapper.columnText(5), isFavourite: sqliteWrapper.columnBool(7), sourceType: .init(rawValue: Int(sqliteWrapper.columnInt(6))) ?? .create)
        }
        sqliteWrapper.finalizeSql()
        sqliteWrapper.closeDb()
        objc_sync_exit(sqliteWrapper)
        
        return site
    }
    
    /// 删除当前场所数据
    @discardableResult func delete() -> Bool {
        
        objc_sync_enter(sqliteWrapper)
        guard sqliteWrapper.openDb(sqliteDBName), sqliteWrapper.prepareSql(SiteData.DELETE_SITE) else {
            objc_sync_exit(sqliteWrapper)
            return false
        }
        sqliteWrapper.bindText(1, text: self.id)
        sqliteWrapper.stepSqlDone()
        sqliteWrapper.finalizeSql()
        sqliteWrapper.closeDb()
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
        guard sqliteWrapper.openDb(sqliteDBName), sqliteWrapper.prepareSql(SiteData.DELETE_SITES) else {
            objc_sync_exit(sqliteWrapper)
            return false
        }
        sqliteWrapper.stepSqlDone()
        sqliteWrapper.finalizeSql()
        sqliteWrapper.closeDb()
        objc_sync_exit(sqliteWrapper)
        return true
    }
    
    /// 获取下一个site名称
    /// - Parameter defalutName: 查询的site默认名称  ”Site “
    /// - Returns: 默认的site名称
    static func getNextSiteName(_ defalutName: String = "site_defalut_name".localizedString) -> String {
        
        var result = "\(defalutName)1"
        objc_sync_enter(sqliteWrapper)
        guard sqliteWrapper.openDb(sqliteDBName), sqliteWrapper.prepareSql(SiteData.GET_NEXT_SITENAME) else {
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
        sqliteWrapper.closeDb()
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
        guard sqliteWrapper.openDb(sqliteDBName), sqliteWrapper.prepareSql(SiteData.GET_NEXT_SITENAME) else {
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
        sqliteWrapper.closeDb()
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
        guard sqliteWrapper.openDb(sqliteDBName), sqliteWrapper.prepareSql(SiteData.GET_TAUTONY_SITENAME) else {
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
        sqliteWrapper.closeDb()
        objc_sync_exit(sqliteWrapper)
        return tautonym
    }
    
    /// 缓存当前场所数据
    /// allData：是否保存所有数据（true：场所基本信息+保存spaces数据，false：场所基本信息）
    @discardableResult func save(allData: Bool = false) -> Bool {
        
        objc_sync_enter(sqliteWrapper)
        guard sqliteWrapper.openDb(sqliteDBName), sqliteWrapper.prepareSql(SiteData.SAVE_SITES) else {
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
        sqliteWrapper.closeDb()
        
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
        if sqliteWrapper.openDb(sqliteDBName) {
            sqliteWrapper.execSql(SpaceData.CREAT_TABLE_SPACES)
            sqliteWrapper.execSql(SpaceData.CREATE_IDX_SPACES_SPACE)
            sqliteWrapper.closeDb()
        }
        objc_sync_exit(sqliteWrapper)
    }
 
    /// 根据场所id获取场所下的所有空间
    /// - Parameter siteId: 场所id
    /// - Returns: 网络下的房间list
    static func loadAll(siteId: String) -> [SpaceData] {
        objc_sync_enter(sqliteWrapper)
        guard sqliteWrapper.openDb(sqliteDBName), sqliteWrapper.prepareSql(SpaceData.GET_SPACES) else {
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
        sqliteWrapper.closeDb()
        objc_sync_exit(sqliteWrapper)

        return spaces
    }
    
    
    /// 根据空间id和场所id获取对应空间
    /// - Parameter spaceId: 空间id
    /// - Parameter siteId: 场所id
    /// - Returns: 房间
    static func load(spaceId: String, siteId: String) -> SpaceData? {
        objc_sync_enter(sqliteWrapper)
        guard sqliteWrapper.openDb(sqliteDBName), sqliteWrapper.prepareSql(SpaceData.GET_SPACE_BY_ID) else {
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
        sqliteWrapper.closeDb()
        objc_sync_exit(sqliteWrapper)
        return space
    }
    
 
    /// 删除所有空间数据
    /// - Parameter siteId: 对应场所
    /// - Returns: 是否成功
    static func deleteAll(siteId: String) -> Bool {
        
        objc_sync_enter(sqliteWrapper)
        guard sqliteWrapper.openDb(sqliteDBName), sqliteWrapper.prepareSql(SpaceData.DELETE_SPACES) else {
            objc_sync_exit(sqliteWrapper)
            return false
        }
        sqliteWrapper.bindText(1, text: siteId)
        sqliteWrapper.stepSqlDone()
        sqliteWrapper.finalizeSql()
        sqliteWrapper.closeDb()
        objc_sync_exit(sqliteWrapper)
        return true
    }
    
    /// 删除当前空间数据
    @discardableResult func deleteData() -> Bool {
        
        objc_sync_enter(sqliteWrapper)
        guard sqliteWrapper.openDb(sqliteDBName), sqliteWrapper.prepareSql(SpaceData.DELETE_SPACE) else {
            objc_sync_exit(sqliteWrapper)
            return false
        }
        sqliteWrapper.bindText(1, text: self.id)
        sqliteWrapper.bindText(2, text: self.siteId)
        sqliteWrapper.stepSqlDone()
        sqliteWrapper.finalizeSql()
        sqliteWrapper.closeDb()
        objc_sync_exit(sqliteWrapper)
        return true
    }
    
    /// 缓存当前空间数据
    @discardableResult func save() -> Bool {
        
        objc_sync_enter(sqliteWrapper)
        guard sqliteWrapper.openDb(sqliteDBName), sqliteWrapper.prepareSql(SpaceData.SAVE_SPACES) else {
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
        sqliteWrapper.closeDb()
        
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
        guard sqliteWrapper.openDb(sqliteDBName), sqliteWrapper.prepareSql(SpaceData.GET_NEXT_SPACENAME) else {
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
        sqliteWrapper.closeDb()
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
        guard sqliteWrapper.openDb(sqliteDBName), sqliteWrapper.prepareSql(SpaceData.GET_NEXT_SPACENAME) else {
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
        sqliteWrapper.closeDb()
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
        guard sqliteWrapper.openDb(sqliteDBName), sqliteWrapper.prepareSql(SpaceData.GET_TAUTONY_SPACENAME) else {
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
        sqliteWrapper.closeDb()
        objc_sync_exit(sqliteWrapper)
        return tautonym
    }
    
}


