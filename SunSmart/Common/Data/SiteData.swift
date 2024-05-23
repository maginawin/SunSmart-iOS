//
//  SiteData.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/8/24.
//

import Foundation

/// 数据来源
enum DataSourceType: Int {
    /// 自己创建
    case create = 1
    /// 克隆
    case clone = 2
    /// 外部分享
    case share = 3
}

protocol Copyable {
    func copy() -> Self
}

class SiteData: Copyable {
    
    /// 场所id
    var id: String
    /// 网络uuid
    var meshUUID: String
    /// 场所名称
    var name: String = ""
    /// 图标id
    var imageId: Int = 0
    /// 类型
    let type: SiteType
    /// 创建时间（时间戳毫秒）
//    let create: TimeInterval
    var create: String
    /// 最近更新的时间（时间戳毫秒）
    var lastUpdate: String
    /// 是否喜欢（常用）
    var isFavourite: Bool = false
    /// 来源类型
    var sourceType: DataSourceType
    
    /// 空间list
    var spaces: [SpaceData] = []
    
    
    /// 初始化场所数据
    /// - Parameters:
    ///   - id: id
    ///   - meshUUID: Mesh UUID
    ///   - name: 名称
    ///   - imageId: 图片id
    ///   - type: 类型
    ///   - create: 创建时间（时间戳毫秒）
    ///   - lastUpdate: 上次更新时间（时间戳毫秒）
    ///   - isFavourite: 是否喜欢
    init(id: String, meshUUID: String, name: String, imageId: Int = 0, type: SiteType, create: String, lastUpdate: String? = nil, isFavourite: Bool, sourceType: DataSourceType) {
        self.name = name
        self.id = id
        self.meshUUID = meshUUID
        self.imageId = imageId
        self.type = type
        self.create = create
        self.isFavourite = isFavourite
        self.lastUpdate = lastUpdate ?? create
        self.sourceType = sourceType
    }
    
    func copy() -> Self {
        
        let site = SiteData(id: self.id, meshUUID: self.meshUUID, name: self.name, imageId: self.imageId, type: self.type, create: self.create, lastUpdate: self.lastUpdate, isFavourite: self.isFavourite, sourceType: self.sourceType)
        let spaces = self.spaces.map({ $0.copy() })
        site.spaces = spaces
        return site as! Self
    }
    
}

extension SiteData {
    /// 场所类型
    enum SiteType: Int {
        /// 办公室
        case office = 1
        /// 仓库
        case warehouse = 2
        /// 学校
        case school = 3
        /// 其它
        case other = 4
    }
}


