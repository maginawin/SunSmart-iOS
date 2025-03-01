//
//  SpaceData.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/8/24.
//

import Foundation
import NordicSigMeshSDK

class SpaceData: Copyable {
    
    /// 空间名称
    var name: String = ""
    /// 空间id
    var id: String
    /// 对应场所id
    var siteId: String
    /// 图标
    var imageId: Int = 0
    /// 创建时间（时间戳秒）
    var create: Int64
    /// 最近更新的时间（时间戳秒）
    var lastUpdate: Int64
    /// 是否喜欢（常用）
    var isFavourite: Bool = false
    /// 权限
    var permission: Permission
    /// 来源类型
    var sourceType: DataSourceType
    /// mesh网络uuid
    var meshUUID: String
    /// 子网网络key
//    var meshNetworkKey: NetworkKey {
//        return meshManager?.meshNetwork?.networkKeys.first(where: { $0.networkId.hex == meshNetworkId }) ?? MeshNetworkManager.instance.currentNetworkKey
//    }
    /// 所有者（editor/visitor权限查看）
    var owner: UserData?
    /// 子管理员（owner权限查看）
    var editor: UserData?
    /// 访客list（owner/editor权限查看）
    var visitors: [UserData] = []
    
    /// 子网网络id
    var meshNetworkId: String
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
    
    /// 是否提交到云端
//    var uploadCloud: Bool = false
    /// 最近上传到云端的时间
    var lastUploadCloudTimestamp: Int64?
    
    /// 是否提交到云端
    var uploadCloud: Bool {
        guard permission == .owner else {
            return true
        }
        return lastUploadCloudTimestamp != nil
    }
    /// 是否需要上传到云端
    var needUploadCloud: Bool {
        return lastUpdate > lastUploadCloudTimestamp ?? 0 && permission != .visitor
    }
    /// 展示的同步服务区错误信息
    var showSyncCloudError: NetworkApiError? {
        
        guard needUploadCloud else {
            return nil
        }
        // 同步过程中不显示错误
//        if let handle = CloudSynchronizationManager.shared.getSpaceCurrentSyncState(self), handle.state.rawValue == CloudSynchronizationHandle.State.wait.rawValue || handle.state.rawValue == CloudSynchronizationHandle.State.inProgress.rawValue {
//            return nil
//        }
        // 有错误则显示之前上传服务器错误，如没有错误并需要上传服务器并不在同步过程，则说明同步过程退出APP
        return syncCloudError ?? (CloudSynchronizationManager.shared.getSpaceCurrentSyncState(self) == nil ? .unknown : nil)
    }
    
    /// 同步服务器错误信息
    var syncCloudError: NetworkApiError?
    /// 上一次同步节点时间戳
    var lastSyncDateTimestamp: Int64 = 0
    /// 是否需要同步节点时间
    var needSyncDate: Bool {
        /// 计算上次同步时间后的时间差值
        let distance = CLongLong(Date().timeIntervalSince1970) - lastSyncDateTimestamp
        // 超过一天主动同步时间
        return distance > 3600 * 24
    }
    /// space状态
    var state: State = .normal
    
    /// Password
    /// 访客密码（权限owner/editor）
    var vistorPassword: String?
    /// 子管理员密码（权限owner）
    var editorPassword: String?
    /// 授权密码（editor、visitor进入space需要）
    var authorizationPassword: String?
    /// 是否需要访客密码
    var vistorPasswordEnable: Bool = false
    /// 是否需要验证密码（密码被修改后需要验证）
    var requiresPasswordVerification: Bool = false
    
    /// 分享邀请码
    var shareCode: String?
    
    /// 是否数据空的空间
    var isEmpty: Bool {
        return deviceCount == 0 && luminairesCount == 0 && groupCount == 0 && sceneCount == 0 && scheheduleCount == 0 && switchesCount == 0
    }
    /// 是否引导配置中
    var isConfiguring: Bool = false
    // 需要申请的设备地址数量
    var applyDeviceAddressCount: Int?
    /// 是否已释放地址
    var releaseAddress: Bool = false
    
    /// 是否被关闭了编辑权限
    var disableEditorPermission: Bool = false
    /// Mesh OTA分发中
    var meshOTADistribution: Bool = false
    
    /// space操作权限list
    var spaceOperates: [SpaceOperate] {
        switch permission {
        case .owner:
            return [.add, .edit, .delete, .editorOperate, .visitorsOperate, .shareEditor, .shareVisitor]
        case .editor:
            return [.exit, .visitorsOperate, .shareVisitor]
        case .visitor:
            return [.exit]
        }
    }
    /// 设备操作权限
    var deviceOperates: [MeshOperate] {
        if permission == .visitor || disableEditorPermission || meshOTADistribution {
            return [.control]
        }
        return [.add, .edit, .delete, .control]
    }
    
    /// 组操作权限
    var groupOperates: [MeshOperate] {
        if permission == .visitor || disableEditorPermission || meshOTADistribution {
            return [.control]
        }
        return [.add, .edit, .delete, .control]
    }
    
    /// 场景操作权限
    var sceneOperates: [MeshOperate] {
        if permission == .visitor || disableEditorPermission || meshOTADistribution {
            return [.control]
        }
        return [.add, .edit, .delete, .control]
    }
    
    /// 日程操作权限
    var scheduleOperates: [MeshOperate] {
        if permission == .visitor || disableEditorPermission || meshOTADistribution {
            return []
        }
        return [.add, .edit, .delete]
    }
    
    /// ble固件升级操作权限
    var bleOTAOperates: [MeshOperate] {
        if permission == .visitor || disableEditorPermission || meshOTADistribution {
            return []
        }
        return [.add, .edit, .delete]
    }
    
    /// mesh固件升级操作权限
    var meshOTAOperates: [MeshOperate] {
        if permission == .visitor || (disableEditorPermission && !meshOTADistribution) {
            return []
        }
        return [.add, .edit, .delete]
    }
    
    /// 初始化空间
    /// - Parameters:
    ///   - name: 空间名称
    ///   - id: 空间id
    ///   - siteId: 对应场所id
    ///   - image: 空间图片
    ///   - create: 创建时间（时间戳秒）
    ///   - lastUpdate: 最新修改时间（时间戳秒）
    ///   - isFavourite: 是否喜欢
    ///   - sourceType: 来源
    ///   - meshUUID: mesh网络uuid
    init(name: String, id: String, siteId: String, imageId: Int = 0, create: Int64, lastUpdate: Int64? = nil, isFavourite: Bool, permission: Permission, sourceType: DataSourceType, meshUUID: String, meshNetworkId: String) {
        self.name = name
        self.id = id
        self.siteId = siteId
        self.imageId = imageId
        self.create = create
        self.lastUpdate = lastUpdate ?? create
        self.permission = permission
        self.sourceType = sourceType
        self.isFavourite = isFavourite
        self.meshUUID = meshUUID
        self.meshNetworkId = meshNetworkId
    }
    
    func copy() -> Self {
        let space = SpaceData(name: self.name, id: self.id, siteId: self.siteId, imageId: self.imageId, create: self.create, lastUpdate: self.lastUpdate, isFavourite: self.isFavourite, permission: self.permission, sourceType: self.sourceType, meshUUID: self.meshUUID, meshNetworkId: self.meshNetworkId)
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
    
    /// Space操作权限
    enum SpaceOperate {
        /// 添加
        case add
        /// 编辑
        case edit
        /// 删除
        case delete
        /// 退出
        case exit
        /// 操作编辑者/子管理员
        case editorOperate
        /// 操作访客
        case visitorsOperate
        /// 分享编辑者权限
        case shareEditor
        /// 分享访客权限
        case shareVisitor
    }
    
    /// Mesh网络操作权限
    enum MeshOperate {
        /// 添加
        case add
        /// 删除
        case delete
        /// 编辑/修改配置
        case edit
        /// 控制（设备、组、场景）
        case control
//        case view
    }
    
    /// Space状态
    enum State: Int {
        /// 正常
        case normal = 1
        /// 待删除
        case waitDeleted = 2
    }
}
