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
    case cancellationUnknown
}

struct WiFiFirmwareUpdatingState: Equatable, Codable {
    let kind: WiFiFirmwareUpdatingKind
    let percent: Int
}

enum WiFiFirmwarePrimaryAction: Equatable {
    case upgrade
    case retry
    case cancel
    case cancelDisabled
    case done
}

struct WiFiFirmwarePrimaryActionPresentation: Equatable {
    let titleKey: String
    let isEnabled: Bool
    let action: WiFiFirmwarePrimaryAction
}

enum WiFiFirmwareInitialLoadRequirement: Hashable {
    case currentVersion
    case cloudFirmware
}

struct WiFiFirmwareInitialLoadGate {
    private var nextGeneration = 0
    private var activeGeneration: Int?
    private var completedRequirements: Set<WiFiFirmwareInitialLoadRequirement> = []
    private var otaStatusStarted = false

    mutating func begin() -> Int {
        nextGeneration += 1
        activeGeneration = nextGeneration
        completedRequirements.removeAll()
        otaStatusStarted = false
        return nextGeneration
    }

    mutating func complete(
        _ requirement: WiFiFirmwareInitialLoadRequirement,
        generation: Int
    ) -> Bool {
        guard activeGeneration == generation, !otaStatusStarted else {
            return false
        }
        completedRequirements.insert(requirement)
        guard completedRequirements.count == 2 else { return false }
        otaStatusStarted = true
        return true
    }

    mutating func cancel() {
        activeGeneration = nil
        completedRequirements.removeAll()
        otaStatusStarted = false
    }
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
    var cancelState: WiFiFirmwareDFUCancelState
    var transactionGate: WiFiFirmwareDFUTransactionGate

    init(
        targetFirmwareID: String,
        otaID: UInt64?,
        lastStatus: WiFiFirmwareDFUStatusSnapshot?,
        lastState: WiFiFirmwareUpdatingState?,
        terminalConsumed: Bool,
        requiresAuthoritativeQuery: Bool,
        cancelState: WiFiFirmwareDFUCancelState = .init(),
        transactionGate: WiFiFirmwareDFUTransactionGate = .init()
    ) {
        self.targetFirmwareID = targetFirmwareID
        self.otaID = otaID
        self.lastStatus = lastStatus
        self.lastState = lastState
        self.terminalConsumed = terminalConsumed
        self.requiresAuthoritativeQuery = requiresAuthoritativeQuery
        self.cancelState = cancelState
        self.transactionGate = transactionGate
    }

    private enum CodingKeys: String, CodingKey {
        case targetFirmwareID
        case otaID
        case lastStatus
        case lastState
        case terminalConsumed
        case requiresAuthoritativeQuery
        case cancelState
        case transactionGate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        targetFirmwareID = try container.decode(String.self, forKey: .targetFirmwareID)
        otaID = try container.decodeIfPresent(UInt64.self, forKey: .otaID)
        lastStatus = try container.decodeIfPresent(
            WiFiFirmwareDFUStatusSnapshot.self,
            forKey: .lastStatus
        )
        lastState = try container.decodeIfPresent(
            WiFiFirmwareUpdatingState.self,
            forKey: .lastState
        )
        terminalConsumed = try container.decode(Bool.self, forKey: .terminalConsumed)
        requiresAuthoritativeQuery = try container.decode(
            Bool.self,
            forKey: .requiresAuthoritativeQuery
        )
        cancelState = try container.decodeIfPresent(
            WiFiFirmwareDFUCancelState.self,
            forKey: .cancelState
        ) ?? .init()
        transactionGate = try container.decodeIfPresent(
            WiFiFirmwareDFUTransactionGate.self,
            forKey: .transactionGate
        ) ?? .init()
    }

    mutating func prepareForPageRecovery() {
        guard !terminalConsumed else { return }
        requiresAuthoritativeQuery = true
    }

    var isStatusQueryEligible: Bool {
        !terminalConsumed && (
            cancelState.blocksNewStart ||
                requiresAuthoritativeQuery ||
                lastStatus?.stage.isTerminal != true
        )
    }
}

enum WiFiFirmwareDFUAuthoritativeRecoveryDecision: Equatable {
    case acceptStatus
    case clearStaleTerminal
    case retainSession
}

enum WiFiFirmwareDFUAuthoritativeRecoveryPolicy {
    static func decision(
        session: WiFiFirmwareDFUSession,
        candidate: WiFiFirmwareDFUStatusSnapshot
    ) -> WiFiFirmwareDFUAuthoritativeRecoveryDecision {
        guard !session.terminalConsumed,
              session.requiresAuthoritativeQuery else {
            return .retainSession
        }

        let identityMatches = candidate.stage != .idle &&
            candidate.otaID != 0 &&
            candidate.firmwareID == session.targetFirmwareID &&
            (session.otaID == nil || candidate.otaID == session.otaID)
        if identityMatches {
            return .acceptStatus
        }

        if session.cancelState.blocksNewStart {
            return session.cancelState.phase == .unknown && candidate.stage == .idle
                ? .clearStaleTerminal
                : .retainSession
        }

        return session.lastStatus?.stage.isTerminal == true
            ? .clearStaleTerminal
            : .retainSession
    }
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
