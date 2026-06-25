//
//  Node+Capability.swift
//  SunSmart
//
//  Created by yuankehong on 2026/1/7.
//

import Foundation
import NordicSigMeshSDK

extension Node {
    
    /// 节点支持的功能类型
    enum DeviceCapability {
        /// 设备所有功能
        static let all: [DeviceCapability] = [.lightSensorConditionSegmentSet, .lightSensorConditionRecall, .setupBehavior, .pirEnabled]
        
        // 每个功能支持的最低版本id
        var supportedVersionId: Int {
            switch self {
            case .lightSensorConditionSegmentSet: return 1
            case .lightSensorConditionRecall: return 2
            case .setupBehavior: return 3
            case .pirEnabled: return 3
            }
        }
        
        /// 光照传感器执行条件分段设置
        case lightSensorConditionSegmentSet
        /// 光照传感器执行事件激活
        case lightSensorConditionRecall
        /// 设备功能配置行为
        case setupBehavior
        /// pir传感器启用/禁用
        case pirEnabled
    }
    
    /// 设备所支持的功能/能力
    var capabilities: [DeviceCapability] {
        guard let vid = self.versionIdentifier else { return [] }
        return DeviceCapability.all.filter { capability in
            capability.supportedVersionId <= vid
        }
    }

    var supportsUpDownRatioControl: Bool {
        companyIdentifier == 0x0A78 && productIdentifier == 0x2491
    }

    var supportsLightDetailRelayControl: Bool {
        if !isEmergencySignController {
            return true
        }
        return companyIdentifier == 0x0A78 && productIdentifier == 0x24C1
    }
    
}
