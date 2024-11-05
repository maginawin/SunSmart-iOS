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
    
    /// 默认设备配置信息
    static var defaultConfigInfos: [MeshDeviceConfigInfo] {
        
        var configInfos: [MeshDeviceConfigInfo] = [
            .init(companyId: CompanyId, productId: 0x0001, categoryName: "PIR Sensor Lighting", elementCount: 2),
            .init(companyId: CompanyId, productId: 0x0011, categoryName: "PIR Sensor Lighting", elementCount: 2),
            .init(companyId: CompanyId, productId: 0x0211, categoryName: "Standalone Sensor", elementCount: 2),
            .init(companyId: CompanyId, productId: 0x0301, categoryName: "Driver Lighting", elementCount: 2),
            .init(companyId: CompanyId, productId: 0x0401, categoryName: "Controler Lighting", elementCount: 2)
        ]
        
        if let filePath = Bundle.main.path(forResource: "devices_config", ofType: "json") {
            let fileURL = URL(fileURLWithPath: filePath)
            if let fileData = try? Data(contentsOf: fileURL), let configDicts = try? JSONSerialization.jsonObject(with: fileData) as? [[String: Any]] {
                configInfos = configDicts.compactMap({ dict in
                    if let companyIdHex = dict["companyId"] as? String, let companyId = UInt16(hex: companyIdHex),
                       let productIdHex = dict["productId"] as? String,  let productId = UInt16(hex: productIdHex),
                       let categoryName = dict["categoryName"] as? String, let elementCount = dict["elementCount"] as? Int {
                        return .init(companyId: companyId, productId: productId, categoryName: categoryName, elementCount: elementCount)
                    }
                    return nil
                })
            }
        }
        return configInfos
    }
    
}
