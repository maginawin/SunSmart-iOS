//
//  GatewayTimeSyncCoordinator.swift
//  SunSmart
//
//  Created by One on 2026/8/13.
//

import Foundation

enum GatewayTimeSyncAttemptPhase: Equatable {
    case connecting
    case sent
    case detachedAfterSend
    case finished
}

struct GatewayTimeStatusSnapshot: Equatable {
    let seconds: UInt64
    let offsetMinutes: Int
}

enum GatewayTimeSyncDecision: Equatable {
    case success(renderUI: Bool)
    case failure(renderUI: Bool)
    case cancelledBeforeSend
    case ignored
}

struct GatewayTimeSyncAttemptCore {
    private struct Attempt {
        let id: UUID
        let gatewayID: String
        var phase: GatewayTimeSyncAttemptPhase
    }

    let pageSessionID: UUID
    private var attempt: Attempt?
    private var isPageAttached = true

    init(pageSessionID: UUID) {
        self.pageSessionID = pageSessionID
    }

    var phase: GatewayTimeSyncAttemptPhase {
        attempt?.phase ?? .finished
    }

    mutating func begin(gatewayID: String) -> UUID? {
        guard isPageAttached, attempt == nil else { return nil }
        let attemptID = UUID()
        attempt = Attempt(
            id: attemptID,
            gatewayID: gatewayID,
            phase: .connecting
        )
        return attemptID
    }

    mutating func markSent(attemptID: UUID) -> Bool {
        guard var attempt,
              attempt.id == attemptID,
              attempt.phase == .connecting else {
            return false
        }
        attempt.phase = .sent
        self.attempt = attempt
        return true
    }

    mutating func detachPage() -> GatewayTimeSyncDecision {
        isPageAttached = false
        guard var attempt else { return .ignored }
        switch attempt.phase {
        case .connecting:
            self.attempt = nil
            return .cancelledBeforeSend
        case .sent:
            attempt.phase = .detachedAfterSend
            self.attempt = attempt
            return .ignored
        case .detachedAfterSend, .finished:
            return .ignored
        }
    }

    mutating func cancelBeforeSendForBackground() -> GatewayTimeSyncDecision {
        guard let attempt else { return .ignored }
        guard attempt.phase == .connecting else { return .ignored }
        self.attempt = nil
        return .failure(renderUI: isPageAttached)
    }

    mutating func receive(
        attemptID: UUID,
        status: GatewayTimeStatusSnapshot,
        targetOffsetMinutes: Int
    ) -> GatewayTimeSyncDecision {
        guard let attempt,
              attempt.id == attemptID,
              attempt.phase == .sent || attempt.phase == .detachedAfterSend else {
            return .ignored
        }
        let renderUI = isPageAttached && attempt.phase == .sent
        self.attempt = nil
        guard status.seconds > 0,
              status.offsetMinutes == targetOffsetMinutes else {
            return .failure(renderUI: renderUI)
        }
        return .success(renderUI: renderUI)
    }

    mutating func timeout(attemptID: UUID) -> GatewayTimeSyncDecision {
        guard let attempt, attempt.id == attemptID else { return .ignored }
        let renderUI = isPageAttached && attempt.phase != .detachedAfterSend
        self.attempt = nil
        return .failure(renderUI: renderUI)
    }
}

#if canImport(CoreBluetooth) && canImport(NordicSigMeshSDK)
import CoreBluetooth
import NordicSigMeshSDK

enum GatewayTimeSyncError: Error {
    case missingLocalBinding
    case connectionFailed
    case missingTimeSetupModel
    case invalidOrMissingTimeStatus
    case localPersistenceFailed
}

final class GatewayTimeSyncCoordinator {
    var onPersistedSuccess: ((SyncGatewayRuntimeTarget) -> Void)?
    var onUISettlement: ((String, UUID, Result<Void, GatewayTimeSyncError>) -> Void)?
    var onAttemptEnded: (() -> Void)?

    private struct RuntimeAttempt {
        let id: UUID
        let target: SyncGatewayRuntimeTarget
    }

    private var core: GatewayTimeSyncAttemptCore
    private var runtimeAttempt: RuntimeAttempt?

    init(pageSessionID: UUID) {
        core = GatewayTimeSyncAttemptCore(pageSessionID: pageSessionID)
    }

    func synchronize(
        target: SyncGatewayRuntimeTarget,
        peripheral: CBPeripheral,
        targetTimeZone: SiteTimeZoneValue
    ) -> UUID? {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let node = target.node,
              target.gateway != nil,
              let attemptID = core.begin(gatewayID: target.descriptor.id) else {
            return nil
        }
        runtimeAttempt = RuntimeAttempt(id: attemptID, target: target)

        MeshLibManager.manager.connectProxy(
            node: node,
            peripheral: peripheral
        ) { [self] connected in
            DispatchQueue.main.async { [self] in
                guard runtimeAttempt?.id == attemptID else { return }
                guard connected else {
                    settleTransportFailure(
                        attemptID: attemptID,
                        error: .connectionFailed
                    )
                    return
                }
                guard let model = node.timeSetupModel else {
                    settleTransportFailure(
                        attemptID: attemptID,
                        error: .missingTimeSetupModel
                    )
                    return
                }
                guard let resolution = SiteTimeSetMessageFactory.resolve(
                    storageValue: targetTimeZone.storageValue
                ), core.markSent(attemptID: attemptID) else {
                    settleTransportFailure(
                        attemptID: attemptID,
                        error: .invalidOrMissingTimeStatus
                    )
                    return
                }

                let message = Node.setLocalTimeMessage(
                    date: Date(),
                    timeZone: resolution.timeZone
                )
                MeshAPI.sendMessage(
                    message: message,
                    model: model,
                    timeout: 10
                ) { [self] response in
                    DispatchQueue.main.async { [self] in
                        guard runtimeAttempt?.id == attemptID else { return }
                        guard let timeStatus = response as? TimeStatus else {
                            settleTransportFailure(
                                attemptID: attemptID,
                                error: .invalidOrMissingTimeStatus
                            )
                            return
                        }
                        settle(
                            attemptID: attemptID,
                            status: timeStatus,
                            targetOffsetMinutes: resolution.offsetMinutes
                        )
                    }
                }
            }
        }
        return attemptID
    }

    func finishPage() {
        dispatchPrecondition(condition: .onQueue(.main))
        let decision = core.detachPage()
        if decision == .cancelledBeforeSend,
           let node = runtimeAttempt?.target.node {
            MeshLibManager.manager.disconnectProxy(node: node)
            runtimeAttempt = nil
        }
        onUISettlement = nil
        onAttemptEnded = nil
    }

    func handleAppDidEnterBackground() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard core.cancelBeforeSendForBackground() == .failure(renderUI: true),
              let runtimeAttempt else {
            return
        }
        if let node = runtimeAttempt.target.node {
            MeshLibManager.manager.disconnectProxy(node: node)
        }
        self.runtimeAttempt = nil
        onUISettlement?(
            runtimeAttempt.target.descriptor.id,
            runtimeAttempt.id,
            .failure(.connectionFailed)
        )
        onAttemptEnded?()
    }

    private func settle(
        attemptID: UUID,
        status: TimeStatus,
        targetOffsetMinutes: Int
    ) {
        let snapshot = GatewayTimeStatusSnapshot(
            seconds: status.time.seconds,
            offsetMinutes: status.time.tzOffset.secondsFromGMT() / 60
        )
        let decision = core.receive(
            attemptID: attemptID,
            status: snapshot,
            targetOffsetMinutes: targetOffsetMinutes
        )
        guard case .success(let renderUI) = decision,
              let runtimeAttempt,
              runtimeAttempt.id == attemptID,
              let node = runtimeAttempt.target.node else {
            if case .failure(let renderUI) = decision {
                finishRuntimeAttempt(
                    attemptID: attemptID,
                    renderUI: renderUI,
                    result: .failure(.invalidOrMissingTimeStatus)
                )
            }
            return
        }

        node.timestamp = snapshot.seconds
        node.timezone = status.time.tzOffset
        guard node.savePropertys() else {
            finishRuntimeAttempt(
                attemptID: attemptID,
                renderUI: renderUI,
                result: .failure(.localPersistenceFailed)
            )
            return
        }

        onPersistedSuccess?(runtimeAttempt.target)
        finishRuntimeAttempt(
            attemptID: attemptID,
            renderUI: renderUI,
            result: .success(())
        )
    }

    private func settleTransportFailure(
        attemptID: UUID,
        error: GatewayTimeSyncError
    ) {
        let decision = core.timeout(attemptID: attemptID)
        guard case .failure(let renderUI) = decision else { return }
        finishRuntimeAttempt(
            attemptID: attemptID,
            renderUI: renderUI,
            result: .failure(error)
        )
    }

    private func finishRuntimeAttempt(
        attemptID: UUID,
        renderUI: Bool,
        result: Result<Void, GatewayTimeSyncError>
    ) {
        guard let runtimeAttempt, runtimeAttempt.id == attemptID else { return }
        if let node = runtimeAttempt.target.node {
            MeshLibManager.manager.disconnectProxy(node: node)
        }
        self.runtimeAttempt = nil
        if renderUI {
            onUISettlement?(
                runtimeAttempt.target.descriptor.id,
                attemptID,
                result
            )
            onAttemptEnded?()
        }
    }
}
#endif
