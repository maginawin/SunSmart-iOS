import Foundation

#if canImport(NordicSigMeshSDK)
import NordicSigMeshSDK

struct LightTimeInformationContext {
    let canConfigureTimeServer: () -> Bool
}

enum LightTimeInformationReadState: Equatable {
    case disconnected
    case reading
    case succeeded(GatewayTimeInformationSnapshot)
    case failed
}

final class LightTimeInformationCoordinator {
    var onReadState: ((LightTimeInformationReadState) -> Void)?
    private let node: Node
    private let context: LightTimeInformationContext
    private var recovery: InformationClockRecovery?
    private var isPageAttached = true

    init(node: Node, context: LightTimeInformationContext) {
        self.node = node
        self.context = context
    }

    deinit { recovery?.detach() }

    @discardableResult
    func read() -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))
        guard isPageAttached, recovery == nil, node.timeModel != nil else { return false }
        guard MeshLibManager.manager.isMeshNetworkConnected else {
            onReadState?(.disconnected)
            return false
        }
        guard let transport = InformationClockMeshTransport(
            node: node,
            requiresDirectProxy: false,
            canConfigure: context.canConfigureTimeServer
        ) else {
            onReadState?(.failed)
            return false
        }
        let operation = InformationClockRecovery(transport: transport)
        recovery = operation
        operation.onFinish = { [weak self] sample in
            guard let self, self.isPageAttached else { return }
            self.recovery = nil
            guard let sample,
                  let snapshot = GatewayTimeInformationFormatter.makeSnapshot(
                    seconds: sample.seconds, offsetMinutes: sample.offsetMinutes
                  ) else {
                self.onReadState?(.failed)
                return
            }
            self.onReadState?(.succeeded(snapshot))
        }
        onReadState?(.reading)
        return operation.start()
    }

    func finishPage() {
        dispatchPrecondition(condition: .onQueue(.main))
        isPageAttached = false
        recovery?.detach()
        recovery = nil
    }
}
#endif
