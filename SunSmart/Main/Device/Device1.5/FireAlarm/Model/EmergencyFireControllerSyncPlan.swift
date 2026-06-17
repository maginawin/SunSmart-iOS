//
//  EmergencyFireControllerSyncPlan.swift
//  SunSmart
//
//  Created by Plato Jobs on 2026/5/7.
//

import Foundation
import NordicSigMeshSDK

enum EmergencyFireControllerSyncTaskKind: String {
    case publication = "Publication"
    case enabled = "Enable"
    case resend = "Resend"
    case restoreDelay = "Restore Delay"
    case actionConfig = "Action Config"
    case lightnessSubscription = "Lightness Group"
    case lightLCSubscription = "LC Group"
    case associationCleanup = "Group Cleanup"
    case deleteCleanup = "Delete Cleanup"
    case deleteConfiguration = "Delete Configuration"
}

final class EmergencyFireControllerSyncTask {
    let title: String
    let kind: EmergencyFireControllerSyncTaskKind
    let address: Address
    let messageHandles: [MeshMessageHandle]
    let isUnsupported: Bool
    let pendingFunctions: [EmergencyFireControllerFunction]
    let pendingGroupAddress: Address?
    let clearsUnassociatePending: Bool
    let changedOnly: Bool
    var state: SyncDevicesState = .none
    var isSelected = false

    init(
        title: String,
        kind: EmergencyFireControllerSyncTaskKind,
        address: Address,
        messageHandles: [MeshMessageHandle],
        isUnsupported: Bool = false,
        pendingFunctions: [EmergencyFireControllerFunction] = [],
        pendingGroupAddress: Address? = nil,
        clearsUnassociatePending: Bool = false,
        changedOnly: Bool = false
    ) {
        self.title = title
        self.kind = kind
        self.address = address
        self.messageHandles = messageHandles
        self.isUnsupported = isUnsupported
        self.pendingFunctions = pendingFunctions
        self.pendingGroupAddress = pendingGroupAddress
        self.clearsUnassociatePending = clearsUnassociatePending
        self.changedOnly = changedOnly
        if isUnsupported {
            state = .failed
        }
    }
}

final class EmergencyFireControllerSyncItem {
    let name: String
    let iconName: String
    let address: Address
    let controller: DeviceEmerFireData?
    var tasks: [EmergencyFireControllerSyncTask]
    var isExpanded = false

    init(name: String, iconName: String, address: Address, tasks: [EmergencyFireControllerSyncTask], controller: DeviceEmerFireData? = nil) {
        self.name = name
        self.iconName = iconName
        self.address = address
        self.tasks = tasks
        self.controller = controller
    }
}

enum EmergencyFireControllerPublishGroupError: LocalizedError {
    case groupAddressInsufficient
    case createGroupFailed
    case missingBoundNode
    case nodeNotReady
    case missingSceneClientModel

    var errorDescription: String? {
        switch self {
        case .groupAddressInsufficient:
            return "group_address_insufficient_message".localizedString
        case .createGroupFailed:
            return "failed".localizedString + " !"
        case .missingBoundNode, .nodeNotReady, .missingSceneClientModel:
            return "The device needs to be repaired."
        }
    }
}
