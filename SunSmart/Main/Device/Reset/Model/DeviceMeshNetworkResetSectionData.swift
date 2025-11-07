//
//  DeviceMeshNetworkResetSectionData.swift
//  SunSmart
//
//  Created by yuankehong on 2025/10/21.
//

import Foundation
import NordicSigMeshSDK

class DeviceMeshNetworkResetSectionData {
    
    /// 网络名称
    let name: String?
    /// 网络id
    let networkId: String
    /// 网络内设备list
    var devices: [ProvisioningDevice] = []
    /// 是否展开
    var unfold: Bool = false
    
    /// 重置状态
    var resetState: ProvisioningDevice.DeviceResetState = .none
    
//    {
//       guard devices.count > 0 else {
//           return .none
//       }
//       var state: ProvisioningDevice.DeviceResetState = .none
//       if devices.contains(where: { $0.resetState == .reseting }) {
//           state = .reseting
//       }else if devices.contains(where: { $0.resetState == .wait }) {
//           state = .wait
//       }else if devices.contains(where: { $0.resetState == .identifying }) {
//           state = .identifying
//       }else if devices.contains(where: { $0.resetState == .identifyWait }) {
//           state = .identifyWait
//       }else if devices.contains(where: { $0.resetState == .scanning }) {
//           state = .scanning
//       }
//       return state
//   }
    
    init(name: String?, networkId: String, devices: [ProvisioningDevice]) {
        self.name = name
        self.networkId = networkId
        self.devices = devices
    }
    
}
