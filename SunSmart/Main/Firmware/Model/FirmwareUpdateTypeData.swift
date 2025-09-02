//
//  FirmwareUpdateTypeData.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/8/30.
//

import Foundation
import NordicSigMeshSDK

class FirmwareUpdateTypeData {
     
    let productId: UInt16
    /// 手机缓存固件版本
    var targetVersion: String?
    /// 手机缓存固件版本hash
    var targetVersionHash: String?
    /// 服务器固件数据
    var serverData: FirmwareServerData?
    
    /// 设备类型下设备list
    var nodes: [Node] = []
    /// 已升级的设备list
    var upgradedNodes: [Node] {
        guard let targetVersion = self.targetVersion else {
            return []
        }
        return nodes.filter({ $0.firmwareVersion != nil && targetVersion.compare($0.firmwareVersion!, options: .numeric) == .orderedSame })
    }
    /// 可升级的设备list
    var canUpgradNodes: [Node] {
        return nodes.filter({ $0.enableUpgrade })
    }
    
    /// 是否展开
    var isShow: Bool = false
    /// 类别名称
    var categoryName: String? {
        return MeshLibManager.manager.supportDeviceInfos.first(where: { $0.productId == self.productId })?.categoryName
    }
    
    init(productId: UInt16, targetVersion: String?, nodes: [Node]) {
        self.productId = productId
        self.targetVersion = targetVersion
        self.nodes = nodes
    }
    
}

struct FirmwareServerData {
    
    /// 设备类型
    let productId: UInt16
    /// 服务器固件版本
    let version: String
    /// 厂商id
    let companyId: UInt16
    /// 客户id
    let customId: UInt16
    /// 文件下载链接
    let url: String
    /// 文件名
    let filename: String
    /// 固件大小
    let size: Int
    /// 发布日期（时间戳）
    let releaseDate: Int64
    /// 更新内容
    let content: String
    
}
