import Foundation

enum LightTimeInformationPreparation: Equatable {
    case unsupported
    case missingApplicationKey
    case localTimeClientUnavailable
    case ready
    case bindTimeServer
    case configurationNotAllowed
}

enum LightTimeInformationPolicy {
    static func preparation(
        supportsTimeGet: Bool,
        knowsApplicationKey: Bool,
        localTimeClientReady: Bool,
        timeServerBound: Bool,
        canConfigureTimeServer: Bool
    ) -> LightTimeInformationPreparation {
        guard supportsTimeGet else { return .unsupported }
        guard knowsApplicationKey else { return .missingApplicationKey }
        guard localTimeClientReady else { return .localTimeClientUnavailable }
        if timeServerBound {
            return .ready
        }
        return canConfigureTimeServer ? .bindTimeServer : .configurationNotAllowed
    }
}

#if canImport(NordicSigMeshSDK)
import NordicSigMeshSDK

struct LightTimeInformationContext {
    let canConfigureTimeServer: Bool
}

enum LightTimeInformationReadState: Equatable {
    case disconnected
    case reading
    case succeeded(GatewayTimeInformationSnapshot)
    case failed
}

final class LightTimeInformationCoordinator {
    var onReadState: ((LightTimeInformationReadState) -> Void)?

    private struct RuntimeAttempt {
        let id: UUID
        let previousTimestamp: UInt64
        let previousTimeZone: TimeZone?
    }

    private let node: Node
    private let context: LightTimeInformationContext
    private var runtimeAttempt: RuntimeAttempt?
    private var isPageAttached = true

    init(node: Node, context: LightTimeInformationContext) {
        self.node = node
        self.context = context
    }

    @discardableResult
    func read() -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))
        guard isPageAttached, runtimeAttempt == nil else { return false }
        guard let model = node.timeModel else { return false }
        guard MeshLibManager.manager.isMeshNetworkConnected else {
            onReadState?(.disconnected)
            return false
        }

        let manager = MeshNetworkManager.instance
        guard manager.meshNetwork != nil else {
            onReadState?(.failed)
            return false
        }
        let applicationKey = manager.currentApplicationKey
        let knowsApplicationKey = node.applicationKeys.contains {
            $0.index == applicationKey.index
        }
        let localTimeClientReady = knowsApplicationKey
            ? manager.ensureLocalTimeClientModelBinding()
            : false
        let preparation = LightTimeInformationPolicy.preparation(
            supportsTimeGet: node.timeModel != nil,
            knowsApplicationKey: knowsApplicationKey,
            localTimeClientReady: localTimeClientReady,
            timeServerBound: model.isBoundTo(applicationKey),
            canConfigureTimeServer: context.canConfigureTimeServer
        )

        switch preparation {
        case .ready, .bindTimeServer:
            break
        case .unsupported:
            return false
        case .missingApplicationKey, .localTimeClientUnavailable,
             .configurationNotAllowed:
            onReadState?(.failed)
            return false
        }

        let attempt = RuntimeAttempt(
            id: UUID(),
            previousTimestamp: node.timestamp,
            previousTimeZone: node.timezone
        )
        runtimeAttempt = attempt
        onReadState?(.reading)

        if preparation == .bindTimeServer {
            bindTimeServer(
                model: model,
                applicationKey: applicationKey,
                attemptID: attempt.id
            )
        } else {
            sendTimeGet(model: model, attemptID: attempt.id)
        }
        return true
    }

    func finishPage() {
        dispatchPrecondition(condition: .onQueue(.main))
        isPageAttached = false
    }

    private func bindTimeServer(
        model: Model,
        applicationKey: ApplicationKey,
        attemptID: UUID
    ) {
        guard context.canConfigureTimeServer,
              let message = ConfigModelAppBind(
                applicationKey: applicationKey,
                to: model
              ) else {
            fail(attemptID: attemptID)
            return
        }

        do {
            try MeshNetworkManager.instance.send(message, to: node) { [weak self] result in
                DispatchQueue.main.async {
                    guard let self,
                          self.runtimeAttempt?.id == attemptID else { return }
                    guard self.isPageAttached else {
                        self.fail(attemptID: attemptID)
                        return
                    }
                    guard case .success(let response) = result,
                          let status = response as? ConfigModelAppStatus,
                          status.status == .success,
                          status.applicationKeyIndex == applicationKey.index,
                          status.elementAddress == model.parentElement?.unicastAddress,
                          status.modelIdentifier == model.modelIdentifier,
                          status.companyIdentifier == model.companyIdentifier else {
                        self.fail(attemptID: attemptID)
                        return
                    }
                    self.sendTimeGet(model: model, attemptID: attemptID)
                }
            }
        } catch {
            fail(attemptID: attemptID)
        }
    }

    private func sendTimeGet(model: Model, attemptID: UUID) {
        guard runtimeAttempt?.id == attemptID, isPageAttached else {
            fail(attemptID: attemptID)
            return
        }
        MeshAPI.sendMessage(
            message: TimeGet(),
            model: model,
            timeout: 10
        ) { [weak self] response in
            DispatchQueue.main.async {
                self?.settle(attemptID: attemptID, response: response)
            }
        }
    }

    private func settle(attemptID: UUID, response: StaticMeshResponse?) {
        guard let attempt = runtimeAttempt, attempt.id == attemptID else { return }
        guard let status = response as? TimeStatus else {
            fail(attemptID: attemptID)
            return
        }

        let offsetMinutes = status.time.tzOffset.secondsFromGMT() / 60
        guard let snapshot = GatewayTimeInformationFormatter.makeSnapshot(
            seconds: status.time.seconds,
            offsetMinutes: offsetMinutes
        ), isPageAttached else {
            restoreNode(using: attempt)
            runtimeAttempt = nil
            if isPageAttached {
                onReadState?(.failed)
            }
            return
        }

        node.timestamp = status.time.seconds
        node.timezone = status.time.tzOffset
        guard node.savePropertys() else {
            restoreNode(using: attempt)
            runtimeAttempt = nil
            onReadState?(.failed)
            return
        }
        runtimeAttempt = nil
        onReadState?(.succeeded(snapshot))
    }

    private func fail(attemptID: UUID) {
        guard let attempt = runtimeAttempt, attempt.id == attemptID else { return }
        restoreNode(using: attempt)
        runtimeAttempt = nil
        if isPageAttached {
            onReadState?(.failed)
        }
    }

    private func restoreNode(using attempt: RuntimeAttempt) {
        node.timestamp = attempt.previousTimestamp
        node.timezone = attempt.previousTimeZone
        _ = node.savePropertys()
    }
}
#endif
