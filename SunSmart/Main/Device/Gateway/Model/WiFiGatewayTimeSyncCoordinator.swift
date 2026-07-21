//
//  WiFiGatewayTimeSyncCoordinator.swift
//  SunSmart
//

import Foundation

struct WiFiGatewayTimeSyncSessionGate {
    enum Result: Equatable {
        case success
        case skipped
        case failed
    }

    enum BeginDecision: Equatable {
        case start
        case join
        case finished(Result)
    }

    private var syncingSessions: Set<UUID> = []
    private var finishedSessions: [UUID: Result] = [:]

    mutating func begin(sessionID: UUID) -> BeginDecision {
        if let result = finishedSessions[sessionID] {
            return .finished(result)
        }
        if syncingSessions.contains(sessionID) {
            return .join
        }
        syncingSessions.insert(sessionID)
        return .start
    }

    mutating func finish(sessionID: UUID, result: Result) {
        syncingSessions.remove(sessionID)
        finishedSessions[sessionID] = result
        if finishedSessions.count > 16,
           let evictedSessionID = finishedSessions.keys.first(where: { $0 != sessionID }) {
            finishedSessions.removeValue(forKey: evictedSessionID)
        }
    }
}

struct WiFiGatewayAutomaticLoadGate {
    enum Intent: Equatable {
        case resume
        case reload
    }

    private var readySessionID: UUID?
    private var pendingIntent: Intent?

    mutating func request(forceReload: Bool) {
        let requestedIntent: Intent = forceReload ? .reload : .resume
        if pendingIntent != .reload {
            pendingIntent = requestedIntent
        }
    }

    mutating func markReady(sessionID: UUID) {
        readySessionID = sessionID
    }

    mutating func takeIfReady(currentSessionID: UUID?) -> Intent? {
        guard let currentSessionID,
              currentSessionID == readySessionID,
              let intent = pendingIntent else {
            return nil
        }
        pendingIntent = nil
        return intent
    }

    mutating func invalidate() {
        readySessionID = nil
        pendingIntent = nil
    }
}

#if canImport(NordicSigMeshSDK)
import NordicSigMeshSDK

final class WiFiGatewayTimeSyncCoordinator {
    enum Outcome {
        case completed
        case skipped
        case failed
        case ignored
    }

    typealias TimeSender = (
        _ message: TimeSet,
        _ model: Model,
        _ completion: @escaping (Bool) -> Void
    ) -> Void

    static let shared = WiFiGatewayTimeSyncCoordinator()

    private var gate = WiFiGatewayTimeSyncSessionGate()
    private var waiters: [UUID: [(Outcome) -> Void]] = [:]
    private let timeSender: TimeSender

    init(timeSender: @escaping TimeSender = WiFiGatewayTimeSyncCoordinator.sendTime) {
        self.timeSender = timeSender
    }

    func synchronize(
        context: ProxyReadyContext,
        node: Node,
        completion: @escaping (Outcome) -> Void
    ) {
        dispatchPrecondition(condition: .onQueue(.main))
        let manager = MeshLibManager.manager
        guard Node.isWiFiGateway(
            companyIdentifier: node.companyIdentifier,
            productIdentifier: node.productIdentifier
        ),
        context.nodeAddress == node.primaryUnicastAddress,
        manager.currentProxyReadyContext == context,
        manager.currentProxy?.nodeAddress == context.nodeAddress else {
            completion(.ignored)
            return
        }

        switch gate.begin(sessionID: context.sessionID) {
        case .join:
            waiters[context.sessionID, default: []].append(completion)
        case .finished(let result):
            completion(outcome(for: result))
        case .start:
            waiters[context.sessionID] = [completion]
            guard node.isKeybindComplete, let model = node.timeSetupModel else {
                finish(context: context, result: .skipped, outcome: .skipped)
                return
            }

            let timeZone = TimeZone.current
            let message = Node.setLocalTimeMessage()
            let address = String(format: "0x%04X", context.nodeAddress)
            print(
                "WiFiGateway TimeSet start address=\(address) "
                + "session=\(context.sessionID) timezone=\(timeZone.identifier) "
                + "offset=\(timeZone.secondsFromGMT())"
            )
            timeSender(message, model) { [weak self] success in
                DispatchQueue.main.async {
                    self?.finish(
                        context: context,
                        result: success ? .success : .failed,
                        outcome: success ? .completed : .failed
                    )
                }
            }
        }
    }

    private func finish(
        context: ProxyReadyContext,
        result: WiFiGatewayTimeSyncSessionGate.Result,
        outcome: Outcome
    ) {
        gate.finish(sessionID: context.sessionID, result: result)
        let callbacks = waiters.removeValue(forKey: context.sessionID) ?? []
        let address = String(format: "0x%04X", context.nodeAddress)
        print(
            "WiFiGateway TimeSet finish address=\(address) "
            + "session=\(context.sessionID) result=\(result)"
        )
        callbacks.forEach { $0(outcome) }
    }

    private func outcome(for result: WiFiGatewayTimeSyncSessionGate.Result) -> Outcome {
        switch result {
        case .success:
            return .completed
        case .skipped:
            return .skipped
        case .failed:
            return .failed
        }
    }

    private static func sendTime(
        message: TimeSet,
        model: Model,
        completion: @escaping (Bool) -> Void
    ) {
        MeshAPI.sendMessage(message: message, model: model, timeout: 10) { response in
            completion(response is TimeStatus)
        }
    }
}
#endif
