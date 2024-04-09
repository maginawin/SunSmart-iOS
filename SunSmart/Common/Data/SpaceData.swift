//
//  SpaceData.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/8/24.
//

import Foundation

class SpaceData: Copyable {
    
    /// 空间名称
    var name: String = ""
    /// 空间id
    var id: String
    /// 对应场所id
    var siteId: String
    /// 图标
    var imageId: Int = 0
    /// 创建时间（时间戳毫秒）
    var create: String
    /// 最近更新的时间（时间戳毫秒）
    var lastUpdate: String
    /// 是否喜欢（常用）
    var isFavourite: Bool = false
    
    /// 来源类型
    var sourceType: DataSourceType
    /// mesh网络uuid
    var meshUUID: String
//    var meshInfo: MeshNetworkInfo
    
    /// 灯数量
    var luminairesCount: Int = 0
    /// 开关数量
    var switchesCount: Int = 0
    /// 设备数量
    var deviceCount: Int = 0
    /// 组数量
    var groupCount: Int = 0
    /// 场景数量
    var sceneCount: Int = 0
    /// 计划数量
    var scheheduleCount: Int = 0
    /// 设备排序类型
    var deviceSortType: DeviceSortType = .create
    /// 上一次同步节点时间戳
    var lastSyncDateTimestamp: CLongLong = 0
    /// 是否需要同步节点时间
    var needSyncDate: Bool {
        /// 计算上次同步时间后的时间差值
        let distance = CLongLong(Date().timeIntervalSince1970) - lastSyncDateTimestamp
        // 超过一天主动同步时间
        return distance > 3600 * 24
    }
    
    
    /// 初始化空间
    /// - Parameters:
    ///   - name: 空间名称
    ///   - id: 空间id
    ///   - siteId: 对应场所id
    ///   - image: 空间图片
    ///   - create: 创建时间（时间戳毫秒）
    ///   - lastUpdate: 最新修改时间（时间戳毫秒）
    ///   - isFavourite: 是否喜欢
    ///   - sourceType: 来源
    ///   - meshUUID: mesh网络uuid
    init(name: String, id: String, siteId: String, imageId: Int = 0, create: String, lastUpdate: String? = nil, isFavourite: Bool, sourceType: DataSourceType, meshUUID: String) {
        self.name = name
        self.id = id
        self.siteId = siteId
        self.imageId = imageId
        self.create = create
        self.lastUpdate = lastUpdate ?? create
        self.sourceType = sourceType
        self.isFavourite = isFavourite
        self.meshUUID = meshUUID
    }
    
    func copy() -> Self {
        let space = SpaceData(name: self.name, id: self.id, siteId: self.siteId, imageId: self.imageId, create: self.create, lastUpdate: self.lastUpdate, isFavourite: self.isFavourite, sourceType: self.sourceType, meshUUID: self.meshUUID)
        space.deviceCount = self.deviceCount
        space.switchesCount = self.switchesCount
        space.luminairesCount = self.luminairesCount
        space.groupCount = self.groupCount
        space.sceneCount = self.sceneCount
        space.scheheduleCount = self.scheheduleCount
        return space as! Self
    }
    
}

extension SpaceData {
    /// 设备排序类型
    enum DeviceSortType: Int {
        /// 添加时间（默认）
        case create = 0
        /// id递增排序（小到大）
        case id = 1
        /// 信号强度排序（强到弱）
        case rssi = 2
    }
}
