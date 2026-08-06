//
//  GatewayFirmwareScanNetworkKeyScopePolicy.swift
//  SunSmart
//
//  Created by One on 2026/8/6.
//

import Foundation

struct GatewayFirmwareScanNetworkKeyScopeInput {
    let address: UInt16
    let associatedApplicationKeyIndexes: [UInt16]
}

struct GatewayFirmwareScanNetworkKeyScopeResolution {
    let allowedNetworkKeyIndexesByAddress: [UInt16: Set<UInt16>]
    let unresolvedApplicationKeyIndexesByAddress: [UInt16: Set<UInt16>]
}

enum GatewayFirmwareScanNetworkKeyScopePolicy {
    static func resolve(
        primaryNetworkKeyIndex: UInt16?,
        availableNetworkKeyIndexes: Set<UInt16>,
        boundNetworkKeyIndexByApplicationKeyIndex: [UInt16: UInt16],
        gateways: [GatewayFirmwareScanNetworkKeyScopeInput]
    ) -> GatewayFirmwareScanNetworkKeyScopeResolution {
        var allowedByAddress: [UInt16: Set<UInt16>] = [:]
        var unresolvedByAddress: [UInt16: Set<UInt16>] = [:]

        gateways.forEach { gateway in
            var allowed: Set<UInt16> = []
            var unresolved: Set<UInt16> = []

            if let primaryNetworkKeyIndex,
               availableNetworkKeyIndexes.contains(primaryNetworkKeyIndex) {
                allowed.insert(primaryNetworkKeyIndex)
            }

            Set(gateway.associatedApplicationKeyIndexes).forEach { appKeyIndex in
                if let boundNetworkKeyIndex =
                    boundNetworkKeyIndexByApplicationKeyIndex[appKeyIndex] {
                    if availableNetworkKeyIndexes.contains(boundNetworkKeyIndex) {
                        allowed.insert(boundNetworkKeyIndex)
                    } else {
                        unresolved.insert(appKeyIndex)
                    }
                } else if availableNetworkKeyIndexes.contains(appKeyIndex) {
                    allowed.insert(appKeyIndex)
                } else {
                    unresolved.insert(appKeyIndex)
                }
            }

            allowedByAddress[gateway.address] = allowed
            unresolvedByAddress[gateway.address] = unresolved
        }

        return GatewayFirmwareScanNetworkKeyScopeResolution(
            allowedNetworkKeyIndexesByAddress: allowedByAddress,
            unresolvedApplicationKeyIndexesByAddress: unresolvedByAddress
        )
    }
}
