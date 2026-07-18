import Foundation

enum WiFiFirmwareDFUStatusStage: String, Codable, Equatable {
    case idle
    case preparing
    case downloading
    case verifying
    case verifyOK
    case verifyFail
    case rebooting
    case recovering
    case versionCheck
    case success
    case timeout
    case failed
    case cancelled

    var forwardRank: Int? {
        switch self {
        case .preparing: return 0
        case .downloading: return 1
        case .verifying: return 2
        case .verifyOK: return 3
        case .rebooting: return 4
        case .recovering: return 5
        case .versionCheck: return 6
        case .idle, .verifyFail, .success, .timeout, .failed, .cancelled: return nil
        }
    }

    var isTerminal: Bool {
        switch self {
        case .verifyFail, .success, .timeout, .failed, .cancelled:
            return true
        case .idle, .preparing, .downloading, .verifying, .verifyOK,
                .rebooting, .recovering, .versionCheck:
            return false
        }
    }
}

enum WiFiFirmwareDFUFailureCategory: String, Codable, Equatable {
    case none
    case download
    case timeout
    case other
}

struct WiFiFirmwareDFUStatusSnapshot: Codable, Equatable {
    let otaID: UInt64
    let stage: WiFiFirmwareDFUStatusStage
    let percent: Int
    let failureCategory: WiFiFirmwareDFUFailureCategory
    let codeIdentifier: String
    let firmwareID: String?
    let moduleVersion: String?
}

enum WiFiFirmwareDFUStatusSource: Equatable {
    case event
    case query
}

enum WiFiFirmwareDFUIgnoreReason: Equatable {
    case invalidIdle
    case identityMismatch
    case stageRegressed
    case downloadProgressRegressed
    case duplicate
    case terminalLocked
    case cancelledRequiresQuery
}

enum WiFiFirmwareDFUReduction: Equatable {
    case accepted
    case ignored(WiFiFirmwareDFUIgnoreReason)
}

enum WiFiFirmwareDFUQueryTiming {
    static let statusTimeout: TimeInterval = 3
    static let quietQueryInterval: TimeInterval = 10
    static let unknownThreshold: TimeInterval = 30
    static let unknownQueryInterval: TimeInterval = 30
}

struct WiFiFirmwareDFUStatusReducer {
    let targetFirmwareID: String
    private(set) var boundOTAID: UInt64?
    private(set) var lastAcceptedStatus: WiFiFirmwareDFUStatusSnapshot?

    init(
        targetFirmwareID: String,
        boundOTAID: UInt64? = nil,
        lastAcceptedStatus: WiFiFirmwareDFUStatusSnapshot? = nil
    ) {
        self.targetFirmwareID = targetFirmwareID
        self.boundOTAID = boundOTAID
        self.lastAcceptedStatus = lastAcceptedStatus
    }

    mutating func reduce(
        _ candidate: WiFiFirmwareDFUStatusSnapshot,
        source: WiFiFirmwareDFUStatusSource
    ) -> WiFiFirmwareDFUReduction {
        guard candidate.stage != .idle else {
            return .ignored(.invalidIdle)
        }
        guard candidate.otaID != 0,
              candidate.firmwareID == targetFirmwareID else {
            return .ignored(.identityMismatch)
        }
        guard lastAcceptedStatus?.stage.isTerminal != true else {
            return .ignored(.terminalLocked)
        }

        if let boundOTAID {
            guard candidate.otaID == boundOTAID else {
                return .ignored(.identityMismatch)
            }
        } else {
            boundOTAID = candidate.otaID
        }

        if candidate == lastAcceptedStatus {
            return .ignored(.duplicate)
        }

        if source == .event,
           candidate.stage == .cancelled,
           lastAcceptedStatus?.stage == .verifying {
            return .ignored(.cancelledRequiresQuery)
        }

        if candidate.stage.isTerminal {
            lastAcceptedStatus = candidate
            return .accepted
        }

        if let previous = lastAcceptedStatus,
           let previousRank = previous.stage.forwardRank,
           let candidateRank = candidate.stage.forwardRank,
           candidateRank < previousRank {
            return .ignored(.stageRegressed)
        }

        if candidate.stage == .downloading,
           lastAcceptedStatus?.stage == .downloading,
           candidate.percent < (lastAcceptedStatus?.percent ?? 0) {
            return .ignored(.downloadProgressRegressed)
        }

        lastAcceptedStatus = candidate
        return .accepted
    }
}

enum WiFiFirmwareDFUStartRecoveryDecision: Equatable {
    case established(WiFiFirmwareDFUStatusSnapshot)
    case queryOnce
    case unknown
}

struct WiFiFirmwareDFUStartRecovery {
    private(set) var reducer: WiFiFirmwareDFUStatusReducer
    private(set) var didIssueStatusQuery = false

    init(otaID: UInt64, firmwareID: String) {
        reducer = WiFiFirmwareDFUStatusReducer(
            targetFirmwareID: firmwareID,
            boundOTAID: otaID
        )
    }

    mutating func record(
        _ status: WiFiFirmwareDFUStatusSnapshot,
        source: WiFiFirmwareDFUStatusSource
    ) -> Bool {
        switch reducer.reduce(status, source: source) {
        case .accepted, .ignored(.duplicate):
            return true
        case .ignored:
            return false
        }
    }

    mutating func nextAfterMissingRET() -> WiFiFirmwareDFUStartRecoveryDecision {
        if let status = reducer.lastAcceptedStatus {
            return .established(status)
        }
        guard !didIssueStatusQuery else {
            return .unknown
        }
        didIssueStatusQuery = true
        return .queryOnce
    }
}
