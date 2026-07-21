//
//  WiFiFirmwareDFUCancelReducer.swift
//  SunSmart
//
//  Created by One on 2026/7/21.
//

import Foundation

enum WiFiFirmwareDFUCancelPhase: String, Codable, Equatable {
    case notRequested
    case pending
    case recovering
    case unknown
    case resolved
}

struct WiFiFirmwareDFUCancelState: Codable, Equatable {
    var phase: WiFiFirmwareDFUCancelPhase = .notRequested
    var sawVerifyingWhilePending = false
    var recoveryQueryCount = 0

    var hasAttempted: Bool {
        phase != .notRequested
    }

    var blocksNewStart: Bool {
        phase == .pending || phase == .recovering || phase == .unknown
    }
}

enum WiFiFirmwareDFUCancelRET: Equatable {
    case success
    case invalidParameters
    case notCancelled
    case unconfirmed
    case busy
    case reserved
}

enum WiFiFirmwareDFUCancelStatusObservation: Equatable {
    case idle
    case matchedIntermediate(WiFiFirmwareDFUStatusStage)
    case matchedCancelled
    case matchedOtherTerminal
    case invalid
}

enum WiFiFirmwareDFUCancelInput: Equatable {
    case sent
    case response(WiFiFirmwareDFUCancelRET)
    case matchedStatus(WiFiFirmwareDFUStatusStage)
    case pendingTimeout
    case recoveryQuery(WiFiFirmwareDFUCancelStatusObservation)
    case unknownQuery(WiFiFirmwareDFUCancelStatusObservation)
    case resume
}

enum WiFiFirmwareDFUCancelAction: Equatable {
    case none
    case updateOriginalOTA
    case cancellationSucceeded
    case originalOTAFinished
    case continueOriginalOTA(showFailureTip: Bool)
    case requestRecoveryQuery
    case requestUnknownQuery
    case enterUnknown
    case scheduleUnknownQuery(updateOriginalOTA: Bool)
    case clearSession
}

enum WiFiFirmwareDFUCancelTiming {
    static let responseTimeout: TimeInterval = 7
    static let statusTimeout: TimeInterval = 3
    static let maximumRecoveryQueries = 3
    static let unknownQueryInterval: TimeInterval = 30
}

struct WiFiFirmwareDFUCancelReducer {
    private(set) var state: WiFiFirmwareDFUCancelState

    init(state: WiFiFirmwareDFUCancelState = .init()) {
        self.state = state
    }

    mutating func reduce(_ input: WiFiFirmwareDFUCancelInput) -> WiFiFirmwareDFUCancelAction {
        switch (state.phase, input) {
        case (.notRequested, .sent):
            state.phase = .pending
            return .none

        case (.pending, .matchedStatus(.verifying)),
             (.recovering, .matchedStatus(.verifying)):
            state.sawVerifyingWhilePending = true
            return .updateOriginalOTA

        case (.pending, .matchedStatus(.cancelled)),
             (.recovering, .matchedStatus(.cancelled)),
             (.unknown, .matchedStatus(.cancelled)):
            state.phase = .resolved
            return .cancellationSucceeded

        case (.pending, .matchedStatus(.verifyFail)),
             (.pending, .matchedStatus(.success)),
             (.pending, .matchedStatus(.timeout)),
             (.pending, .matchedStatus(.failed)),
             (.recovering, .matchedStatus(.verifyFail)),
             (.recovering, .matchedStatus(.success)),
             (.recovering, .matchedStatus(.timeout)),
             (.recovering, .matchedStatus(.failed)),
             (.unknown, .matchedStatus(.verifyFail)),
             (.unknown, .matchedStatus(.success)),
             (.unknown, .matchedStatus(.timeout)),
             (.unknown, .matchedStatus(.failed)):
            state.phase = .resolved
            return .originalOTAFinished

        case (.pending, .matchedStatus),
             (.recovering, .matchedStatus):
            return .updateOriginalOTA

        case (.unknown, .matchedStatus(let stage)):
            if stage == .verifying {
                state.sawVerifyingWhilePending = true
            }
            return .scheduleUnknownQuery(updateOriginalOTA: stage != .idle)

        case (.pending, .response(.success)),
             (.recovering, .response(.success)),
             (.unknown, .response(.success)):
            state.phase = .resolved
            return .cancellationSucceeded

        case (.pending, .response(.invalidParameters)),
             (.recovering, .response(.invalidParameters)),
             (.unknown, .response(.invalidParameters)):
            state.phase = .resolved
            return .continueOriginalOTA(showFailureTip: true)

        case (.pending, .response(.busy)),
             (.recovering, .response(.busy)):
            state.phase = .recovering
            return .requestRecoveryQuery

        case (.unknown, .response(.busy)):
            return .requestUnknownQuery

        case (_, .response(.notCancelled))
            where state.blocksNewStart && state.sawVerifyingWhilePending:
            state.phase = .resolved
            return .continueOriginalOTA(showFailureTip: true)

        case (.pending, .response(.notCancelled)),
             (.pending, .response(.unconfirmed)),
             (.pending, .response(.reserved)),
             (.recovering, .response(.notCancelled)),
             (.recovering, .response(.unconfirmed)),
             (.recovering, .response(.reserved)):
            state.phase = .recovering
            return .requestRecoveryQuery

        case (.unknown, .response(.notCancelled)),
             (.unknown, .response(.unconfirmed)),
             (.unknown, .response(.reserved)):
            return .requestUnknownQuery

        case (.pending, .pendingTimeout):
            state.phase = .recovering
            state.recoveryQueryCount = 0
            return .requestRecoveryQuery

        case (.recovering, .recoveryQuery(.matchedCancelled)):
            state.phase = .resolved
            return .cancellationSucceeded

        case (.recovering, .recoveryQuery(.matchedOtherTerminal)):
            state.phase = .resolved
            return .originalOTAFinished

        case (.recovering, .recoveryQuery(.matchedIntermediate)):
            state.phase = .resolved
            return .continueOriginalOTA(showFailureTip: true)

        case (.recovering, .recoveryQuery(.idle)),
             (.recovering, .recoveryQuery(.invalid)):
            state.recoveryQueryCount += 1
            guard state.recoveryQueryCount < WiFiFirmwareDFUCancelTiming.maximumRecoveryQueries else {
                state.phase = .unknown
                return .enterUnknown
            }
            return .requestRecoveryQuery

        case (.unknown, .unknownQuery(.matchedCancelled)):
            state.phase = .resolved
            return .cancellationSucceeded

        case (.unknown, .unknownQuery(.matchedOtherTerminal)):
            state.phase = .resolved
            return .originalOTAFinished

        case (.unknown, .unknownQuery(.idle)):
            state.phase = .resolved
            return .clearSession

        case (.unknown, .unknownQuery(.matchedIntermediate)):
            return .scheduleUnknownQuery(updateOriginalOTA: true)

        case (.unknown, .unknownQuery(.invalid)):
            return .scheduleUnknownQuery(updateOriginalOTA: false)

        case (.pending, .resume),
             (.recovering, .resume):
            state.phase = .recovering
            state.recoveryQueryCount = 0
            return .requestRecoveryQuery

        case (.unknown, .resume):
            return .requestUnknownQuery

        case (.notRequested, _),
             (.pending, _),
             (.recovering, _),
             (.unknown, _),
             (.resolved, _):
            return .none
        }
    }
}
