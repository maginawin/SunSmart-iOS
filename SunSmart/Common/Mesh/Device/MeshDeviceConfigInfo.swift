//
//  MeshDeviceConfigInfo.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/9/27.
//

import Foundation
import NordicSigMeshSDK

struct MeshDeviceConfigInfo {
    
    /// 厂商id
    let companyId: UInt16
    /// 产品id
    let productId: UInt16
    /// 产品名称
    let categoryName: String
    /// element数量
    let elementCount: Int
    /// 图标类别
    let iconCategory: String
    /// 设备类型
    let deviceCategory: String
    /// 型号名称
    let modelName: String?
    /// 灵敏度范围（传感器）
    let sensitivityRange: ClosedRange<UInt16>?

    var iconName: String {
        return "device_\(iconCategory)"
    }

    var offlineIconName: String {
        return "device_offline_\(iconCategory)"
    }

    var unsyncIconName: String {
        return "device_unsync_\(iconCategory)"
    }
    
    /// 默认设备配置信息
    static var defaultConfigInfos: [MeshDeviceConfigInfo] {
        
        var configInfos: [MeshDeviceConfigInfo] = []
        
        if let filePath = Bundle.main.path(forResource: "devices_config", ofType: "json") {
            let fileURL = URL(fileURLWithPath: filePath)
            if let fileData = try? Data(contentsOf: fileURL), let configDicts = try? JSONSerialization.jsonObject(with: fileData) as? [[String: Any]] {
                configInfos = configDicts.compactMap({ dict in
                    if let companyIdHex = dict["companyId"] as? String, let companyId = UInt16(hex: companyIdHex),
                       let productIdHex = dict["productId"] as? String,  let productId = UInt16(hex: productIdHex),
                       let categoryName = dict["categoryName"] as? String, let elementCount = dict["elementCount"] as? Int,
                       let iconCategory = dict["iconCategory"] as? String,
                       let deviceCategory = dict["deviceCategory"] as? String {
                        
                        var sensitivityRange: ClosedRange<UInt16>?
                        if let sensitivityRangeMin = dict["sensitivityRangeMin"] as? UInt16, let sensitivityRangeMax = dict["sensitivityRangeMax"] as? UInt16 {
                            sensitivityRange = sensitivityRangeMin...sensitivityRangeMax
                        }
                        
                        return .init(companyId: companyId, productId: productId, categoryName: categoryName, elementCount: elementCount, iconCategory: iconCategory, deviceCategory: deviceCategory, modelName: dict["modelName"] as? String, sensitivityRange: sensitivityRange)
                    }
                    return nil
                })
            }
        }
        return configInfos
    }
    
}
