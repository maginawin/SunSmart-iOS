import Foundation

/// Owns only this operation's scheduling/ACK state. No global cancellation and no
/// reliable-message retransmission. Radio submission and local persistence are
/// injected so timing and failure paths can be exercised without a Mesh network.
@MainActor
final class LightsBatchDeletionExecutor {
    enum Evidence: String, Codable { case acknowledged, submitted }
    struct Result {
        let succeeded: Set<String>
        let failed: Set<String>
    }
    private struct Pending {
        let members: Set<String>
        var deadline: TimeInterval
        var submitted = false
        var accepted: Bool?
        var recorded = false
    }
    private let now: () -> TimeInterval
    private let sleep: (TimeInterval) async -> Void
    private var pending: [UInt16: Pending] = [:]
    private var running = false
    private var cancelRequested = false

    init(now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         sleep: @escaping (TimeInterval) async -> Void = { interval in
             try? await Task.sleep(nanoseconds: UInt64(max(0, interval) * 1_000_000_000))
         }) {
        self.now = now
        self.sleep = sleep
    }

    func cancel() { cancelRequested = true }

    func receive(source: UInt16, parameters: Data) {
        guard running, parameters.count == 3, parameters[0] == 0x48, parameters[1] == 0x02,
              var item = pending[source], item.accepted == nil, now() <= item.deadline else { return }
        item.accepted = parameters[2] == 0
        pending[source] = item
    }

    func run(plan: LightsBatchDeletionPlan, isCurrent: () -> Bool,
             send: (LightsBatchDeletionPlan.Task) async -> Bool,
             record: (Set<String>, Evidence) -> Set<String>) async -> Result {
        guard !running else { return .init(succeeded: [], failed: plan.selected) }
        running = true; cancelRequested = false; pending = [:]
        defer { running = false; pending = [:] }
        var succeeded = Set<String>()
        var lastSubmission: TimeInterval?
        func collect() {
            for address in Array(pending.keys) {
                guard var item = pending[address], item.submitted, item.accepted == true, !item.recorded else { continue }
                succeeded.formUnion(record(item.members, .acknowledged))
                item.recorded = true
                pending[address] = item
            }
        }
        var nextAllowed: TimeInterval = now()
        sending: for task in plan.tasks {
            if nextAllowed > now() { await sleep(nextAllowed - now()) }
            collect()
            guard !cancelRequested, isCurrent() else { break }
            if task.isUnicast {
                // Registered before send: a fast ACK may precede write completion.
                pending[task.destination] = .init(members: task.members, deadline: .infinity)
            }
            var completed = 0
            for repetition in 0..<task.repetitions {
                guard !cancelRequested, isCurrent() else { break sending }
                if repetition > 0 { await sleep(max(0, (lastSubmission ?? now()) + 1 - now())) }
                guard !cancelRequested, isCurrent() else { break sending }
                guard await send(task) else {
                    if task.isUnicast { pending.removeValue(forKey: task.destination) }
                    break sending
                }
                completed += 1
                lastSubmission = now()
                if task.isUnicast {
                    pending[task.destination]?.submitted = true
                    pending[task.destination]?.deadline = now() + 10
                }
                collect()
            }
            if !task.isUnicast && completed == task.repetitions {
                succeeded.formUnion(record(task.members, .submitted))
            }
            nextAllowed = (lastSubmission ?? now()) + task.followingGap
        }
        // Expected Proxy departure after the last write does not invalidate
        // already submitted multicast tasks or accepted ACKs.
        while true {
            collect()
            let remainingACK = pending.values.filter { $0.submitted && $0.accepted == nil && $0.deadline > now() }
            let barrier = lastSubmission.map { $0 + 3 } ?? now()
            guard now() < barrier || !remainingACK.isEmpty else { break }
            await sleep(min(0.05, max(0.001, max(barrier, remainingACK.map(\.deadline).max() ?? now()) - now())))
        }
        collect()
        return .init(succeeded: succeeded, failed: plan.selected.subtracting(succeeded))
    }
}
