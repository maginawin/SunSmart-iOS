//
//  WiFiFirmwareDFUState.swift
//  SunSmart
//
//  Created by Codex on 2026/7/15.
//

import Foundation

enum WiFiFirmwareUpdatingKind: String, Codable {
    case connFailedTimeout
    case connFailedServerUnable
    case downloading
    case downloadFailed
    case updating
    case upgradeFailed
    case upgradeComplete
    case cancelled
    case communicationUnknown
}

struct WiFiFirmwareUpdatingState: Equatable, Codable {
    let kind: WiFiFirmwareUpdatingKind
    let percent: Int
}

enum WiFiFirmwarePrimaryAction: Equatable {
    case upgrade
    case retry
    case cancelDisabled
    case done
}

struct WiFiFirmwarePrimaryActionPresentation: Equatable {
    let titleKey: String
    let isEnabled: Bool
    let action: WiFiFirmwarePrimaryAction
}

enum WiFiFirmwareDFUStateMapper {
    static func map(status: WiFiFirmwareDFUStatusSnapshot) -> WiFiFirmwareUpdatingState? {
        let percent = min(100, max(0, status.percent))
        let kind: WiFiFirmwareUpdatingKind

        switch status.stage {
        case .preparing, .downloading:
            kind = .downloading
        case .verifying, .verifyOK, .rebooting, .recovering, .versionCheck:
            kind = .updating
        case .verifyFail:
            kind = .downloadFailed
        case .failed where status.failureCategory == .download:
            kind = .downloadFailed
        case .failed, .timeout:
            kind = .upgradeFailed
        case .success:
            kind = .upgradeComplete
        case .cancelled:
            kind = .cancelled
        case .idle:
            return nil
        }

        return .init(kind: kind, percent: status.stage == .success ? 100 : percent)
    }
}

struct WiFiFirmwareDFUSession: Codable, Equatable {
    let targetFirmwareID: String
    var otaID: UInt64?
    var lastStatus: WiFiFirmwareDFUStatusSnapshot?
    var lastState: WiFiFirmwareUpdatingState?
    var terminalConsumed: Bool
    var requiresAuthoritativeQuery: Bool
}

struct WiFiFirmwareDFUSessionStore {
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load(networkUUID: UUID, nodeAddress: UInt16) -> WiFiFirmwareDFUSession? {
        defaults.removeObject(forKey: legacyStorageKey(
            networkUUID: networkUUID,
            nodeAddress: nodeAddress
        ))
        let key = storageKey(networkUUID: networkUUID, nodeAddress: nodeAddress)
        guard let data = defaults.data(forKey: key) else { return nil }
        do {
            return try JSONDecoder().decode(WiFiFirmwareDFUSession.self, from: data)
        } catch {
            defaults.removeObject(forKey: key)
            return nil
        }
    }

    func save(
        _ session: WiFiFirmwareDFUSession,
        networkUUID: UUID,
        nodeAddress: UInt16
    ) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        defaults.set(data, forKey: storageKey(
            networkUUID: networkUUID,
            nodeAddress: nodeAddress
        ))
    }

    func remove(networkUUID: UUID, nodeAddress: UInt16) {
        defaults.removeObject(forKey: storageKey(
            networkUUID: networkUUID,
            nodeAddress: nodeAddress
        ))
        defaults.removeObject(forKey: legacyStorageKey(
            networkUUID: networkUUID,
            nodeAddress: nodeAddress
        ))
    }

    private func storageKey(networkUUID: UUID, nodeAddress: UInt16) -> String {
        "wifi_firmware_dfu_session.v19.\(networkUUID.uuidString).\(nodeAddress)"
    }

    private func legacyStorageKey(networkUUID: UUID, nodeAddress: UInt16) -> String {
        "wifi_firmware_dfu_session.\(networkUUID.uuidString).\(nodeAddress)"
    }
}
