//
//  EnergyStatisticsStaticData.swift
//  SunSmart
//
//  Created by yuankehong on 2025/5/10.
//

import Foundation
import NordicSigMeshSDK

struct DeviceTotalEnergyData {
    
    /// 设备名称
    let name: String
    /// 设备地址
    let address: Address
    /// 时间戳
    let timestamp: Int64
    /// 最大输出功率(W)
    let maxRatedPower: UInt16
    /// 满功率使用的总能耗（W/h）
    let maxTotalEnergyUse: UInt32
    /// 实际使用的总能耗（W/h）
    let preciseTotalEnergyUse: UInt32
    
    
    func toJSON() -> [String: Any] {
        return ["name": name, "address": address, "timestamp": timestamp, "maxRatedPower": maxRatedPower, "maxTotalEnergyUse": maxTotalEnergyUse, "preciseTotalEnergyUse": preciseTotalEnergyUse]
    }
}
