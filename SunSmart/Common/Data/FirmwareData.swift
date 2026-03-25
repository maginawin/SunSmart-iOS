//
//  FirmwareData.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/9/3.
//

import Foundation
import NordicSigMeshSDK
///// 设备类型
//enum DeviceType {
//    /// 产品id
//    var pid: UInt16 {
//        switch self {
//        case .pirSensorLightingMushroom:
//            return 0x0001
//        case .pirSensorLightingLinear:
//            return 0x0011
//        case .converter:
//            return 0x0101
//        }
//    }
//    
//    var name: String {
//        switch self {
//        case .pirSensorLightingMushroom:
//            return "PIR Sensor Lighting".localizedString
//        case .pirSensorLightingLinear:
//            return "PIR Sensor Lighting".localizedString
//        case .converter:
//            return "BLE to 0-10V converter".localizedString
//        }
//    }
//    
//    init?(pid: UInt16) {
//        switch pid {
//        case DeviceType.pirSensorLightingMushroom.pid:
//            self = .pirSensorLightingMushroom
//        case DeviceType.pirSensorLightingLinear.pid:
//            self = .pirSensorLightingLinear
//        case DeviceType.converter.pid:
//            self = .converter
//        default:
//            return nil
//        }
//    }
//    
//    /// PIR+Dayling+Light 蘑菇头传感器
//    case pirSensorLightingMushroom
////        case fixtureIntegratedMushroomSensor
//    /// PIR+Dayling+Light 条形传感器
//    case pirSensorLightingLinear
////        case fixtureIntegratedLinearSensor
//    /// 0~10V转换器
//    case converter
//}

struct FirmwareData {
    
    /// 名称
    let name: String
    /// 版本
    let version: String
    /// 固件ID
    let firmwareID: Data
    /// 固件数据
    let data: Data
    /// 更新的镜像索引
    let updateFirmwareImageIndex: Int
    /// 升级check数据
    let incomingFirmwareMetadata: Data
    /// 产品id
    let productId: UInt16
    /// 厂商id
    let vendorId: UInt16
    /// 客户id
    let customId: UInt16?
    /// 发布日期（时间戳）
    let releaseDate: Int64
    /// 更新内容
    let content: String
    /// 固件hash
    let compositionHash: String
    /// 设备版本vid
    let versionIdentifier: UInt16?
}
