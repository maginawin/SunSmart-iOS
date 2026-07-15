//
//  WiFiFirmwareDFUState.swift
//  SunSmart
//
//  Created by Codex on 2026/7/15.
//

import Foundation
import NordicSigMeshSDK

enum WiFiFirmwareUpdatingKind: String, Codable {
    case connFailedTimeout
    case connFailedServerUnable
    case downloading
    case downloadFailed
    case updating
    case upgradeFailed
    case upgradeComplete
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
    static func map(
        status: WiFiGatewayDFUStatus,
        targetFirmwareID: String
    ) -> WiFiFirmwareUpdatingState? {
        guard status.firmwareID == targetFirmwareID else { return nil }
        let percent = min(100, max(0, Int(status.percent)))
        switch status.stage {
        case .downloading:
            return .init(kind: .downloading, percent: percent)
        case .verifying, .verifyOK, .rebooting, .recovering, .versionCheck:
            return .init(kind: .updating, percent: percent)
        case .verifyFail:
            return .init(kind: .downloadFailed, percent: percent)
        case .success:
            return .init(kind: .upgradeComplete, percent: 100)
        case .failed:
            switch status.code {
            case .noNetwork, .http, .sizeMismatch:
                return .init(kind: .downloadFailed, percent: percent)
            default:
                return .init(kind: .upgradeFailed, percent: percent)
            }
        case .timeout, .reserved:
            return .init(kind: .upgradeFailed, percent: percent)
        case .idle:
            return nil
        }
    }

    static func stageIdentifier(_ stage: WiFiGatewayDFUStage) -> String {
        switch stage {
        case .idle: return "idle"
        case .downloading: return "downloading"
        case .verifying: return "verifying"
        case .verifyOK: return "verifyOK"
        case .verifyFail: return "verifyFail"
        case .rebooting: return "rebooting"
        case .recovering: return "recovering"
        case .versionCheck: return "versionCheck"
        case .success: return "success"
        case .timeout: return "timeout"
        case .failed: return "failed"
        case .reserved(let rawValue): return "reserved:\(rawValue)"
        }
    }

    static func codeIdentifier(_ code: WiFiGatewayDFUCode) -> String {
        switch code {
        case .none: return "none"
        case .noNetwork: return "noNetwork"
        case .http: return "http"
        case .sizeMismatch: return "sizeMismatch"
        case .verify: return "verify"
        case .versionRejected: return "versionRejected"
        case .noPartition: return "noPartition"
        case .noMemory: return "noMemory"
        case .otaBegin: return "otaBegin"
        case .otaWrite: return "otaWrite"
        case .otaEnd: return "otaEnd"
        case .setBoot: return "setBoot"
        case .internalError: return "internalError"
        case .triggerError: return "triggerError"
        case .triggerTimeout: return "triggerTimeout"
        case .triggerBusyTimeout: return "triggerBusyTimeout"
        case .otaTimeout: return "otaTimeout"
        case .protocolError: return "protocolError"
        case .versionProtocol: return "versionProtocol"
        case .versionMissing: return "versionMissing"
        case .versionQueryError: return "versionQueryError"
        case .versionQueryTimeout: return "versionQueryTimeout"
        case .versionMismatch: return "versionMismatch"
        case .recoveryTimeout: return "recoveryTimeout"
        case .reserved(let rawValue): return "reserved:\(rawValue)"
        }
    }
}

struct WiFiFirmwareDFUSession: Codable, Equatable {
    let targetFirmwareID: String
    var accepted: Bool
    var lastState: WiFiFirmwareUpdatingState?
    var stageIdentifier: String?
    var codeIdentifier: String?
    var moduleVersion: String?
    var terminalConsumed: Bool
}

struct WiFiFirmwareDFUSessionStore {
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load(networkUUID: UUID, nodeAddress: UInt16) -> WiFiFirmwareDFUSession? {
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
        defaults.set(data, forKey: storageKey(networkUUID: networkUUID, nodeAddress: nodeAddress))
    }

    func remove(networkUUID: UUID, nodeAddress: UInt16) {
        defaults.removeObject(forKey: storageKey(networkUUID: networkUUID, nodeAddress: nodeAddress))
    }

    private func storageKey(networkUUID: UUID, nodeAddress: UInt16) -> String {
        return "wifi_firmware_dfu_session.\(networkUUID.uuidString).\(nodeAddress)"
    }
}
