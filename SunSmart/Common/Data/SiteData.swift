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

/// 权限类型
enum Permission: Int {
    
    var rawString: String {
        switch self {
        case .owner:
            return "owner".localizedString
        case .editor:
            return "editor".localizedString
        case .visitor:
            return "visitor".localizedString
        }
    }
    
    /// 所有者
    case owner = 1
    /// 管理员
    case editor = 2
    /// 访客
    case visitor = 3
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
    /// 权限
    let permission: Permission

    /// 创建时间（时间戳秒）
//    let create: TimeInterval
    var create: Int64
    /// 最近更新的时间（时间戳秒）
    var lastUpdate: Int64
    /// 是否喜欢（常用）
    var isFavourite: Bool = false
    /// 来源类型
    var sourceType: DataSourceType
    /// 空间数量（site列表使用，当本地没有site下spaces数据，获取服务器site列表site下不会返回spaces数据，这个时候需要一个space数量提供UI显示）
    var spaceCount: Int?
    /// 空间list
    var spaces: [SpaceData] = []
    /// 同步服务器错误信息
    var syncCloudError: NetworkApiError?
    
    /// 展示的同步服务区错误信息
    var showSyncCloudError: NetworkApiError? {
        // 有错误则显示之前上传服务器错误，如没有错误并需要上传服务器并不在同步过程，则说明同步过程退出APP
        return syncCloudError ?? ((needUploadCloud && CloudSynchronizationManager.shared.getSiteCurrentSyncState(self) == nil) ? .unknown : nil)
    }
    
    /// 最近上传到云端的时间
    var lastUploadCloudTimestamp: Int64?
    
    /// 是否提交到云端
    var uploadCloud: Bool {
        return lastUploadCloudTimestamp != nil
    }
    /// 是否需要上传到云端
    var needUploadCloud: Bool {
        return lastUpdate > lastUploadCloudTimestamp ?? 0
    }
    /// 状态
    var state: State = .normal
    
    /// 权限操作list
    var permissionOperates: [SiteOperate] {
        if permission == .owner {
            return [.edit, .delete, .transfer]
        }
        return []
    }
    
    
    /// 初始化场所数据
    /// - Parameters:
    ///   - id: id
    ///   - meshUUID: Mesh UUID
    ///   - name: 名称
    ///   - imageId: 图片id
    ///   - type: 类型
    ///   - create: 创建时间（时间戳秒）
    ///   - lastUpdate: 上次更新时间（时间戳秒）
    ///   - isFavourite: 是否喜欢
    init(id: String, meshUUID: String, name: String, imageId: Int = 0, type: SiteType, permission: Permission, create: Int64, lastUpdate: Int64? = nil, isFavourite: Bool, sourceType: DataSourceType) {
        self.name = name
        self.id = id
        self.meshUUID = meshUUID
        self.imageId = imageId
        self.type = type
        self.permission = permission
        self.create = create
        self.isFavourite = isFavourite
        self.lastUpdate = lastUpdate ?? create
        self.sourceType = sourceType
    }
    
    func copy() -> Self {
        
        let site = SiteData(id: self.id, meshUUID: self.meshUUID, name: self.name, imageId: self.imageId, type: self.type, permission: self.permission, create: self.create, lastUpdate: self.lastUpdate, isFavourite: self.isFavourite, sourceType: self.sourceType)
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
    
    /// Site操作权限
    enum SiteOperate {
        /// 添加
//        case add
        /// 编辑
        case edit
        /// 删除
        case delete
        /// 移交
        case transfer
    }
    
    /// Space状态
    enum State: Int {
        /// 正常
        case normal = 1
        /// 待删除（owner：已转让）
        case waitDeleted = 2
    }
}


