import Foundation
import NordicSigMeshSDK

/// SDK 回调在同一状态所有者上执行；完成异步交付，允许 SDK 先清空上一批队列。
final class SyncExecutionEnvironment {
    var configurationIsCurrent: () -> Bool = { true }
    var configurationAvailable: () -> Bool = { SpaceConfigurationSafety.currentConfigurationAvailable }
    var bluetoothAvailable: () -> Bool = { MeshLibManager.manager.isOpenBluetooth }
    var delay: (TimeInterval, @escaping () -> Void) -> Void = { interval, action in
        DispatchQueue.main.asyncAfter(deadline: .now() + interval, execute: action)
    }
    var authorize: (GatewayModel, Node, @escaping (String?) -> Void) -> (() -> Void) = { gateway, node, completion in
        let task = Task { @MainActor in
            let result = await GatewayServerAuthorizationService.shared.authorize(gateway: gateway, node: node, policy: .ifMissing)
            guard !Task.isCancelled else { return }
            switch result {
            case .success: completion(nil)
            case .failure(let error): completion(error.localizedDescription)
            }
        }
        return { task.cancel() }
    }
    var send: ([MeshMessageHandle], TimeInterval, MessageCommandSuccessfulCallback?, MessageCommandFailedCallback?, MessageCommandFinishedCallback?) -> Void
    var stop: (@escaping () -> Void) -> Void

    init() {
        let gate = SyncCommandStopGate()
        send = { handles, timeout, success, failure, finished in
            let batch = !handles.isEmpty && finished != nil ? gate.submitted() : nil
            MeshProxyMessageCommand.shared.addMessage(messageHandles: handles, ackMessageTimeout: timeout,
                progressBack: batch.map { identifier in { _, _ in onStateQueue { gate.started(identifier) } } },
                successfulBack: success.map { callback in
                    { handle, status in onStateQueue { if let batch { gate.started(batch) }; callback(handle, status) } }
                }, failedBack: failure.map { callback in
                    { handle in onStateQueue { if let batch { gate.started(batch) }; callback(handle) } }
                }, finishedBack: finished.map { callback in
                    { handles in DispatchQueue.main.async { if let batch { gate.finished(batch) }; callback(handles) } }
                })
        }
        stop = { completion in
            gate.stop(using: { finished in
                MeshProxyMessageCommand.shared.stopSendMessage { _ in DispatchQueue.main.async(execute: finished) }
            }, completion: completion)
        }
    }

    func addMessage(messageHandles: [MeshMessageHandle], ackMessageTimeout: TimeInterval = 5,
                    successfulBack: MessageCommandSuccessfulCallback? = nil,
                    failedBack: MessageCommandFailedCallback? = nil,
                    finishedBack: MessageCommandFinishedCallback?) {
        precondition(Thread.isMainThread)
        send(messageHandles, ackMessageTimeout, successfulBack, failedBack, finishedBack)
    }
}

private func onStateQueue(_ action: () -> Void) {
    if Thread.isMainThread { action() } else { DispatchQueue.main.sync(execute: action) }
}
