//
//  DeviceParameterRatedPowerPhaseData.swift
//  SunSmart
//
//  Created by yuankehong on 2025/5/8.
//

import Foundation
import NordicSigMeshSDK

class DeviceParameterRatedPowerPhaseData: NSObject {
    
    /// 亮度百分比
    var lightLevel: UInt8?
    /// 功率
    var power: UInt16?
    /// 是否必要的数据
    var necessary: Bool = false
    
    init(lightLevel: UInt8? = nil, power: UInt16? = nil, necessary: Bool) {
        self.lightLevel = lightLevel
        self.power = power
        self.necessary = necessary
    }
    
    /// 默认的数据
    static func `default`() -> [DeviceParameterRatedPowerPhaseData] {
        return [
            DeviceParameterRatedPowerPhaseData(lightLevel: 0, power: 0, necessary: true),
            DeviceParameterRatedPowerPhaseData(lightLevel: 100, power: nil, necessary: true)
        ]
    }
    
    /// 转换节点阶段能耗数据
    func toNodePhaseEnergyConsumption() -> NodePhaseEnergyConsumption? {
        
        guard let level = lightLevel, let power = power else {
            return nil
        }
        return NodePhaseEnergyConsumption(percent: UInt8(Float(level) * 2.55), power: power)
    }
    
}
