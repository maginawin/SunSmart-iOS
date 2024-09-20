//
//  FirmwareUpdateTypeData.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/8/30.
//

import Foundation
import NordicSigMeshSDK

class FirmwareUpdateTypeData {
     
    let deviceType: DeviceType
    /// 手机缓存固件版本
    var targetVersion: String?
    /// 服务器固件数据
    var serverData: FirmwareServerData?
    
    /// 设备类型下设备list
    var nodes: [Node] = []
    /// 可升级的设备list
    var upgradedNodes: [Node] = []
    /// 是否展开
    var isShow: Bool = false
    
    
    init(deviceType: DeviceType, targetVersion: String?, nodes: [Node], upgradedNodes: [Node] = []) {
        self.deviceType = deviceType
        self.targetVersion = targetVersion
        self.nodes = nodes
        self.upgradedNodes = upgradedNodes
    }
    
}

struct FirmwareServerData {
    
    /// 设备类型
    let deviceType: DeviceType
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
