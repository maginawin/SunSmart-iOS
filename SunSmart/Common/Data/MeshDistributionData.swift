//
//  MeshDistributionData.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/11/18.
//

import Foundation
import NordicSigMeshSDK

extension FirmwareDistributionUpdateState {
    
    var rawValue: UInt8 {
        switch self {
        case .none:
            return 0
        case .await:
            return 1
        case .updating:
            return 2
        case .complete:
            return 3
        case .failure:
            return 4
        case .waitingInstall:
            return 5
        }
    }
    
    var parmaters: Data {
        var data = Data()
        switch self {
        case .none:
            return data + self.rawValue
        case .await:
            return data + self.rawValue
        case .updating(let updatePhase):
            return data + self.rawValue + updatePhase.parmaters
        case .waitingInstall(let currentDistributionNode):
            if let address = currentDistributionNode?.primaryUnicastAddress {
                return data + self.rawValue + address
            }
            return data + self.rawValue
        case .complete:
            return data + self.rawValue
        case .failure(let updatePhase, let failedNodes):
            let phaseLength = UInt16(updatePhase.parmaters.count)
            data = data + self.rawValue + phaseLength + updatePhase.parmaters
            let failedAddresses = failedNodes.map({ $0.primaryUnicastAddress })
            if let deviceAddressesData = try? JSONEncoder().encode(failedAddresses) {
                return data + deviceAddressesData
            }
            return data
        }
    }
    
    init?(parameters: Data) {
        guard parameters.count >= 1 else {
            return nil
        }
        let code: UInt8 = parameters.read(fromOffset: 0)
        switch code {
        case 0:
            self = .none
        case 1:
            self = .await
        case 2:
            if parameters.count >= 2, let updatePhase = UpdatePhase(parameters: parameters.subdata(in: 1..<parameters.count)) {
                self = .updating(updatePhase: updatePhase)
            }else {
                self = .updating(updatePhase: .verifying)
            }
        case 3:
            self = .complete
        case 4:
            var updatePhase: UpdatePhase = .verifying
            var failedNodes: [Node] = []
            if parameters.count >= 4 {
                // phase 数据长度
                let phaseLength: UInt16 = parameters.read(fromOffset: 1)
                // 失败设备数据起始位置
                let failedNodesLocation = 3+Int(phaseLength)
                if let phase = UpdatePhase(parameters: parameters.subdata(in: 3..<failedNodesLocation)) {
                    updatePhase = phase
                    // 查看失败设备
                    if parameters.count > failedNodesLocation {
                       let failedAddressesData = parameters.subdata(in: failedNodesLocation..<parameters.count)
                        if let addresses = try? JSONDecoder().decode([UInt16].self, from: failedAddressesData) {
                            failedNodes = addresses.compactMap({ address in MeshNetworkManager.instance.realNodes.first(where: { $0.primaryUnicastAddress == address }) })
                        }
                    }
                }
            }
            self = .failure(updatePhase: updatePhase, failedNodes: failedNodes)
        case 5:
            var currentDistributionNode: Node?
            if parameters.count == 3 {
                let address: UInt16 = parameters.read(fromOffset: 1)
                currentDistributionNode = MeshNetworkManager.instance.realNodes.first(where: { $0.primaryUnicastAddress == address })
            }
            self = .waitingInstall(currentDistributionNode: currentDistributionNode)
        default:
            return nil
        }
    }
    
}

extension FirmwareDistributionUpdateState.UpdatePhase {
    
    var rawValue: UInt8 {
        switch self {
        case .verifying:
            return 0
        case .blob:
            return 1
        case .apply:
            return 2
        }
    }
    
    var parmaters: Data {
        var data = Data() + rawValue
        switch self {
        case .verifying:
            break
        case .blob(let progress, let estimateTime):
            if estimateTime >= 0 {
                data = data + progress + UInt16(estimateTime)
            }else {
                data = data + progress
            }
        case .apply(let successNodes):
            let addresses = successNodes.map({ $0.primaryUnicastAddress })
            if let deviceAddressesData = try? JSONEncoder().encode(addresses) {
                data = data + deviceAddressesData
            }
        }
        return data
    }
    
    init?(parameters: Data) {
        guard parameters.count >= 1 else {
            return nil
        }
        let code: UInt8 = parameters.read(fromOffset: 0)
        switch code {
        case 0: // 验证
            self = .verifying
        case 1: // 传输blob
            var progress: UInt8 = 0
            var estimateTime: UInt16?
            if parameters.count >= 2 {
                progress = parameters.read(fromOffset: 1)
            }
            if parameters.count >= 3 {
                estimateTime = parameters.read(fromOffset: 2)
            }
            self = .blob(progress: progress, estimateTime: estimateTime != nil ? Int(estimateTime!) : -1)
        case 2: // 更新
            var successNodes: [Node] = []
            if parameters.count >= 2 {
                let addressData = parameters.subdata(in: 1..<parameters.count)
                if let addresses = try? JSONDecoder().decode([UInt16].self, from: addressData) {
                    successNodes = addresses.compactMap({ address in MeshNetworkManager.instance.realNodes.first(where: { $0.primaryUnicastAddress == address }) })
                }
            }
            self = .apply(successNodes: successNodes)
        default:
            return nil
        }
        
    }
}

struct MeshDistributionData {
    
    /// 分发者地址
    let distributionAddress: Address
    /// 升级目标设备地址list
    let targetAddresses: [Address]
    /// 分发状态
    var distributionState: FirmwareDistributionUpdateState
//    /// 更新的模块
//    let updateFirmwareImageIndex: UInt16
//    /// 固件校验数据
//    let incomingFirmwareMetadata: Data
//    /// 固件包大小
//    let firmwareDataSize: UInt32
    
    /// 分发设备
    var distributionNode: Node? {
        return MeshNetworkManager.instance.meshNetwork?.node(withAddress: distributionAddress)
    }
    /// 升级的目标设备
    var targetNodes: [Node] {
        return targetAddresses.compactMap({ MeshNetworkManager.instance.meshNetwork?.node(withAddress: $0) })
    }
    
    /// 更新分发状态
    mutating func updateDistributionState(state: FirmwareDistributionUpdateState) {
        self.distributionState = state
    }
    
}
