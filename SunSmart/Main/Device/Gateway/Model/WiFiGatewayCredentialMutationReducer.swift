import Foundation

struct WiFiGatewayCredentialSnapshot: Equatable {
    let ssid: Data
    let password: Data
}

enum WiFiGatewayCredentialMutationOperation: Equatable {
    case set(target: WiFiGatewayCredentialSnapshot)
    case clear(previous: WiFiGatewayCredentialSnapshot)
}

enum WiFiGatewayCredentialMutationResponse: Equatable {
    case confirmed
    case invalidParameters
    case unconfirmed
}

enum WiFiGatewayCredentialReadObservation: Equatable {
    case credentials(WiFiGatewayCredentialSnapshot)
    case notConfigured
    case unconfirmed
}

enum WiFiGatewayCredentialMutationInput: Equatable {
    case start(WiFiGatewayCredentialMutationOperation)
    case mutationResponse(WiFiGatewayCredentialMutationResponse)
    case recoveryResponse(WiFiGatewayCredentialReadObservation)
}

enum WiFiGatewayCredentialMutationAction: Equatable {
    case none
    case sendSet(WiFiGatewayCredentialSnapshot)
    case sendClear
    case requestCredentials
    case setTargetReached
    case setTargetNotReached
    case setTargetUnknown
    case clearTargetReached
    case clearTargetNotReached(WiFiGatewayCredentialSnapshot)
    case clearTargetUnknown
}

struct WiFiGatewayCredentialMutationReducer {
    private enum Phase: Equatable {
        case idle
        case waitingMutation(WiFiGatewayCredentialMutationOperation)
        case waitingRecovery(WiFiGatewayCredentialMutationOperation)
        case finished
    }

    private var phase: Phase = .idle

    mutating func reduce(
        _ input: WiFiGatewayCredentialMutationInput
    ) -> WiFiGatewayCredentialMutationAction {
        switch (phase, input) {
        case (.idle, .start(let operation)):
            phase = .waitingMutation(operation)
            switch operation {
            case .set(let target): return .sendSet(target)
            case .clear: return .sendClear
            }

        case (.waitingMutation(let operation), .mutationResponse(.confirmed)):
            phase = .finished
            switch operation {
            case .set: return .setTargetReached
            case .clear: return .clearTargetReached
            }

        case (.waitingMutation(let operation), .mutationResponse(.invalidParameters)):
            phase = .finished
            switch operation {
            case .set: return .setTargetNotReached
            case .clear(let previous): return .clearTargetNotReached(previous)
            }

        case (.waitingMutation(let operation), .mutationResponse(.unconfirmed)):
            phase = .waitingRecovery(operation)
            return .requestCredentials

        case (.waitingRecovery(.set(let target)), .recoveryResponse(.credentials(let value))):
            phase = .finished
            return value == target ? .setTargetReached : .setTargetNotReached

        case (.waitingRecovery(.set), .recoveryResponse(.notConfigured)):
            phase = .finished
            return .setTargetNotReached

        case (.waitingRecovery(.set), .recoveryResponse(.unconfirmed)):
            phase = .finished
            return .setTargetUnknown

        case (.waitingRecovery(.clear), .recoveryResponse(.notConfigured)):
            phase = .finished
            return .clearTargetReached

        case (.waitingRecovery(.clear), .recoveryResponse(.credentials(let value))):
            phase = .finished
            return .clearTargetNotReached(value)

        case (.waitingRecovery(.clear), .recoveryResponse(.unconfirmed)):
            phase = .finished
            return .clearTargetUnknown

        default:
            return .none
        }
    }
}
