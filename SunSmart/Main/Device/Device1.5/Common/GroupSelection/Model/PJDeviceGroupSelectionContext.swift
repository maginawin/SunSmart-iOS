//
//  PJDeviceGroupSelectionContext.swift
//  SunSmart
//
//  Created by Plato Jobs on 2026/5/7.
//

import Foundation
import NordicSigMeshSDK

enum PJDeviceGroupSelectionSwitchControlPolicy {
    case onlineNodesOnly
    case nonEmptyGroup

    func canControl(_ group: Group) -> Bool {
        switch self {
        case .onlineNodesOnly:
            return group.nodes.contains(where: { $0.state })
        case .nonEmptyGroup:
            return !group.nodes.isEmpty
        }
    }
}

struct PJDeviceGroupSelectionContext {
    let title: String
    let groups: [Group]
    let selectedGroupAddresses: [UInt16]
    let disabledGroupAddresses: Set<UInt16>
    let disabledSelectionTip: String
    let switchControlPolicy: PJDeviceGroupSelectionSwitchControlPolicy

    init(
        title: String,
        groups: [Group],
        selectedGroupAddresses: [UInt16],
        disabledGroupAddresses: Set<UInt16>,
        disabledSelectionTip: String,
        switchControlPolicy: PJDeviceGroupSelectionSwitchControlPolicy = .onlineNodesOnly
    ) {
        self.title = title
        self.groups = groups
        self.selectedGroupAddresses = selectedGroupAddresses
        self.disabledGroupAddresses = disabledGroupAddresses
        self.disabledSelectionTip = disabledSelectionTip
        self.switchControlPolicy = switchControlPolicy
    }
}
