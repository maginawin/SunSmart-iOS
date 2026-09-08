import Foundation

@main
enum SyncSessionCoordinatorTests {
    static func main() {
        let lane = SyncSessionTransportLane()
        let first = SyncSessionCoordinator(lane: lane)
        let second = SyncSessionCoordinator(lane: lane)
        var events: [String] = []
        var oldRun: UUID!
        first.start { oldRun = $0; events.append("start first") }
        var stopFinished: (() -> Void)?
        first.stop { stopFinished = $0; events.append("stop transport and compensate") }
        precondition(!first.lifecycle.isActive(oldRun), "STOP invalidates the old round immediately")
        first.start { _ in events.append("retry first") }
        second.start { _ in events.append("start second") }
        precondition(events == ["start first", "stop transport and compensate"], "nothing starts during compensation")
        first.stop { _ in preconditionFailure("must not stop SDK compensation twice") }
        first.start { _ in events.append("retry first") }
        stopFinished?(); stopFinished?()
        precondition(events == ["start first", "stop transport and compensate", "start second"], "release channel once; preserve waiting session order")
        second.close { $0() }
        precondition(events.last == "retry first", "retry can start only after the channel is released")

        var settled: (() -> Void)?
        var completed = 0
        let run = first.identifier
        first.finish(run, settle: { settled = $0 }, finished: { completed += 1 })
        first.finish(run, settle: { _ in preconditionFailure("duplicate settle") }, finished: { completed += 1 })
        first.start { _ in events.append("queued retry") }
        first.close { _ in preconditionFailure("close must not interrupt active compensation") }
        settled?(); settled?()
        precondition(completed == 0 && !events.contains("queued retry"), "close discards old completion and queued retry")
        precondition(first.closed, "closed sessions never restart")

        let idleClosed = SyncSessionCoordinator(lane: lane)
        idleClosed.close { _ in preconditionFailure("idle must not stop another sender") }
        idleClosed.start { _ in preconditionFailure("closed must not acquire") }
        let running = SyncSessionCoordinator(lane: lane)
        let waiting = SyncSessionCoordinator(lane: lane)
        running.start { _ in }
        waiting.start { _ in preconditionFailure("cancelled waiter must not start") }
        waiting.close { _ in preconditionFailure("waiting session never owns transport") }
        running.close { $0() }

        let automatic = SyncSessionCoordinator(lane: lane)
        var starts = 0
        automatic.start { _ in starts += 1 }
        automatic.finish(automatic.identifier, settle: { $0() }, finished: {
            automatic.start { _ in starts += 1 }
        })
        precondition(starts == 2, "automatic retry requested inside completion starts after release")
        automatic.close { $0() }
        let startup = SyncCommandStopGate()
        let batch = startup.submitted()
        var sdkStops = 0
        var stopCompletions = 0
        var sdkStopFinished: (() -> Void)?
        startup.stop(using: { sdkStops += 1; sdkStopFinished = $0 }, completion: { stopCompletions += 1 })
        precondition(sdkStops == 0, "STOP during SDK startup waits for actual queue installation")
        startup.started(batch)
        precondition(sdkStops == 1 && stopCompletions == 0, "stop only after SDK begins and wait for cleanup")
        sdkStopFinished?(); startup.finished(batch)
        precondition(stopCompletions == 1, "late original finish must not complete stop twice")
        let laterBatch = startup.submitted()
        startup.finished(batch)
        startup.stop(using: { _ in sdkStops += 1 }, completion: { stopCompletions += 1 })
        startup.finished(laterBatch)
        precondition(sdkStops == 1 && stopCompletions == 2, "connect failure before first progress releases stop without stopping another queue")

        let cleanupOwner = SyncSessionCoordinator(lane: lane)
        let following = SyncSessionCoordinator(lane: lane)
        var idleCleanupFinished: (() -> Void)?
        var followingStarted = false
        cleanupOwner.close(idleCleanup: { idleCleanupFinished = $0 }, settle: { _ in preconditionFailure("no active transport to stop") })
        following.start { _ in followingStarted = true }
        precondition(!followingStarted, "idle close compensation still owns the shared channel")
        idleCleanupFinished?()
        precondition(followingStarted, "release only after idle cleanup")
        following.close { $0() }
        let synchronousClose = SyncSessionCoordinator(lane: lane)
        synchronousClose.start { _ in }
        var cleanups = 0
        synchronousClose.close(idleCleanup: { _ in preconditionFailure("running close must not also run idle cleanup") }, settle: { done in cleanups += 1; done() })
        precondition(cleanups == 1, "synchronous stop settles once")
        print("PASS: production session coordinator serializes stop, compensation, retry, close and cross-page channel ownership")
    }
}
