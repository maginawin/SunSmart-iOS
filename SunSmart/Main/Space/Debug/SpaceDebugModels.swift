//
//  SpaceDebugModels.swift
//  SunSmart
//
//  Created on 2026/5/16.
//

import CoreBluetooth
import Foundation
import NordicSigMeshSDK

enum SpaceDebugDeviceCategory: Int, CaseIterable {
    case lights
    case switches
    case sensors
    case others

    init(node: Node) {
        switch node.deviceType {
        case .light:
            self = .lights
        case .switches:
            self = .switches
        case .sensor:
            self = .sensors
        case .dongle, .gateway, .emergencyController, .unknown:
            self = .others
        }
    }

    var title: String {
        switch self {
        case .lights:
            return "lights".localizedString
        case .switches:
            return "switches".localizedString
        case .sensors:
            return "sensors".localizedString
        case .others:
            return "others".localizedString
        }
    }
}

enum SpaceDebugScanState: Equatable {
    case idle
    case preparing
    case scanning
    case stopped
    case connecting(Address)

    var title: String {
        switch self {
        case .idle, .stopped:
            return "debug_stopped".localizedString
        case .preparing:
            return "debug_preparing".localizedString
        case .scanning:
            return "debug_scanning".localizedString
        case .connecting:
            return "connecting".localizedString
        }
    }
}

enum SpaceDebugConnectionState {
    case connecting
    case connected
    case reconnecting
    case disconnected

    var title: String {
        switch self {
        case .connecting:
            return "connecting".localizedString
        case .connected:
            return "debug_connected".localizedString
        case .reconnecting:
            return "debug_reconnecting".localizedString
        case .disconnected:
            return "debug_disconnected".localizedString
        }
    }
}

enum SpaceDebugUARTSupportViewState: Equatable {
    case checking
    case supported
    case unsupported
    case disconnected
    case failed(String)
}

struct SpaceDebugUARTMessage: Equatable {
    let text: String
    let timestamp: Date
}

struct SpaceDebugNodeItem {
    let node: Node
    let displayOrder: Int
    var peripheral: CBPeripheral?
    var rssi: Int?
    var lastSeen: Date?
    var isConnecting: Bool = false

    var address: Address {
        node.primaryUnicastAddress
    }

    var category: SpaceDebugDeviceCategory {
        SpaceDebugDeviceCategory(node: node)
    }

    var isFound: Bool {
        peripheral != nil && rssi != nil
    }

    var groupName: String? {
        node.group?.name
    }

    var nodeName: String {
        node.name ?? "\(node.primaryUnicastAddress)"
    }

    var displayTitle: String {
        if let groupName = groupName, !groupName.isEmpty {
            return "\(groupName) - \(nodeName)"
        }
        return nodeName
    }
}

struct SpaceDebugSection {
    let category: SpaceDebugDeviceCategory
    var items: [SpaceDebugNodeItem]
}

struct SpaceDebugUARTLogExportContext {
    let siteName: String
    let spaceName: String
    let groupName: String?
    let deviceName: String
    let macAddress: String
    let companyID: String
    let productID: String
    let address: String
    let versionIdentifier: String
    let model: String
    let deviceType: String
    let firmwareVersion: String
    let droppedMessageCount: Int
    let generatedAt: Date
}
