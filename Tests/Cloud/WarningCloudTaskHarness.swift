// 由 check_warning_regressions.py 注入生产授权任务；仅替换网络与持久化边界。
import Foundation

struct NetworkApiError: Error, Equatable {}
enum CloudSynchronizationState: Equatable { case wait, successful, cancel, failure(error: NetworkApiError) }
struct AuthorizationError: Error { var networkApiError: NetworkApiError { NetworkApiError() } }
struct Receipt { let submittedGeneration: Int64 }
final class Gateway {
    var lastUpdate: Int64 = 1
    var lastUploadCloudTimestamp: Int64 = 0
    var syncCloudError: NetworkApiError?
    var saves = 0
    func save() { saves += 1 }
}
enum Policy { case always }
actor GatewayServerAuthorizationService {
    static let shared = GatewayServerAuthorizationService()
    private var requests: [Int: CheckedContinuation<Result<Receipt, AuthorizationError>, Never>] = [:]
    private var nextID = 0
    func authorizeWithReceipt(gateway: Gateway, node: Int, policy: Policy, requestedGeneration: Int64) async -> Result<Receipt, AuthorizationError> {
        nextID += 1
        let id = nextID
        return await withCheckedContinuation { requests[id] = $0 }
    }
    func hasRequest(_ id: Int) -> Bool { requests[id] != nil }
    func resolve(_ id: Int, _ result: Result<Receipt, AuthorizationError>) { requests.removeValue(forKey: id)!.resume(returning: result) }
}

final class Handle {
    typealias AsyncTask = _Concurrency.Task
    var gatewayAuthorizationTask: Task<Void, Never>?
    var state = CloudSynchronizationState.wait
    var handleCallback: ((Handle, CloudSynchronizationState) -> Void)?
    func start(_ gateway: Gateway) {
        let node = 0
        // PRODUCTION_GATEWAY_TASK
    }
    func cancel() { gatewayAuthorizationTask?.cancel(); gatewayAuthorizationTask = nil; state = .cancel }
}

@main struct CloudTaskTests {
    static let service = GatewayServerAuthorizationService.shared

    @MainActor static func waitForRequest(_ id: Int) async {
        for _ in 0..<10000 {
            if await service.hasRequest(id) { return }
            await Task.yield()
        }
        preconditionFailure("Missing authorization request")
    }

    @MainActor static func main() async {
        let gateway = Gateway()
        let handle = Handle()
        var states: [CloudSynchronizationState] = []
        handle.handleCallback = { _, state in
            dispatchPrecondition(condition: .onQueue(.main))
            states.append(state)
        }
        // Cancel before the main actor has had a chance to start the task.
        handle.start(gateway)
        let notStarted = handle.gatewayAuthorizationTask!
        handle.cancel()
        await notStarted.value
        precondition(states.isEmpty && handle.state == .cancel)
        handle.start(gateway)
        let replacedBeforeStart = handle.gatewayAuthorizationTask!
        handle.start(gateway)
        let first = handle.gatewayAuthorizationTask!
        await replacedBeforeStart.value
        precondition(handle.gatewayAuthorizationTask != nil && states.isEmpty)
        await waitForRequest(1)
        await service.resolve(1, .success(Receipt(submittedGeneration: 1)))
        await first.value
        precondition(states == [.successful] && gateway.lastUploadCloudTimestamp == 1)
        precondition(handle.gatewayAuthorizationTask == nil)

        handle.start(gateway)
        let cancelled = handle.gatewayAuthorizationTask!
        await waitForRequest(2)
        let savedBeforeCancel = gateway.saves
        handle.cancel()
        await service.resolve(2, .success(Receipt(submittedGeneration: 20)))
        await cancelled.value
        precondition(states.count == 1 && handle.state == .cancel)
        precondition(gateway.saves == savedBeforeCancel)

        handle.start(gateway)
        let stale = handle.gatewayAuthorizationTask!
        await waitForRequest(3)
        handle.start(gateway)
        let replacement = handle.gatewayAuthorizationTask!
        await waitForRequest(4)
        await service.resolve(3, .failure(AuthorizationError()))
        await stale.value
        precondition(handle.gatewayAuthorizationTask != nil && states.count == 1)
        await service.resolve(4, .failure(AuthorizationError()))
        await replacement.value
        precondition(states.count == 2 && gateway.syncCloudError != nil)

        // An edit during authorization requires another generation to be confirmed.
        handle.start(gateway)
        let retry = handle.gatewayAuthorizationTask!
        await waitForRequest(5)
        gateway.lastUpdate = 2
        await service.resolve(5, .success(Receipt(submittedGeneration: 1)))
        await waitForRequest(6)
        precondition(states.count == 2)
        await service.resolve(6, .success(Receipt(submittedGeneration: 2)))
        await retry.value
        precondition(gateway.lastUploadCloudTimestamp == 2 && states.last == .successful)

        // Completion may synchronously enqueue a new operation on the same handle.
        handle.handleCallback = { callbackHandle, _ in callbackHandle.start(gateway) }
        handle.start(gateway)
        let reentrant = handle.gatewayAuthorizationTask!
        await waitForRequest(7)
        await service.resolve(7, .success(Receipt(submittedGeneration: 2)))
        await reentrant.value
        await waitForRequest(8)
        precondition(handle.gatewayAuthorizationTask != nil)
        let cleanup = handle.gatewayAuthorizationTask!
        handle.cancel()
        await service.resolve(8, .success(Receipt(submittedGeneration: 2)))
        await cleanup.value
        print("PASS: Cloud main-queue callback, cancellation, replacement, generation retry and reentrancy")
    }
}
