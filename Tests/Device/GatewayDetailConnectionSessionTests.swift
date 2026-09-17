import Foundation

@main
struct GatewayDetailConnectionSessionTests {
    static func main() {
        firstConnectionWaitsForReady()
        immediateReentryWaitsOnlyRemainingCooldown()
        failureRetriesAndThenSucceeds()
        retriesStopAfterThreeAttempts()
        missingCallbackUsesItsOwnDeadlineWithoutAnotherRetry()
        readyTimeoutOutlivesRetryAdmissionWindow()
        thirdAttemptCanBecomeReadyAfterAdmissionWindow()
        scanAndGattCanOutliveAdmissionWindow()
        lateAttemptKeepsBothStageDeadlines()
        cooldownCannotAdmitAttemptAfterWindow()
        exitCancelsQueuedAndActiveAttempts()
        oldPageCannotCloseNewPage()
        staleCallbacksCannotReplaceNewAttempt()
        hiddenPageDoesNotRetryAndChildReturnReusesReady()
        bluetoothOffCancelsRecovery()
        contextReplacementProtectsNewConnection()
        staleReadyDuringCooldownIsIgnored()
        deletionKeepsReadyButStopsAutomaticRecovery()
        disconnectRetentionIsBounded()
        print("GatewayDetailConnectionSessionTests passed (19 lifecycle scenarios)")
    }

    private static func firstConnectionWaitsForReady() {
        let h = Harness()
        h.session.resume()
        h.clock.advance(to: 0)
        expect(h.connectTimes == [0], "First entry must have no cooldown")
        h.callbacks[0](true)
        expect(!h.session.state.isReady, "GATT success is not Proxy Ready")
        h.makeReady()
        h.clock.advance(to: 100)
        expect(h.session.state.isReady && h.readyEvents.count == 1, "Ready must cancel all recovery timers")
        expect(h.connectTimes.count == 1 && h.closeTimes.isEmpty, "Successful connection must not be retried")
    }

    private static func immediateReentryWaitsOnlyRemainingCooldown() {
        let clock = Clock()
        let ownership = GatewayDetailConnectionOwnership()
        let first = Harness(clock: clock, ownership: ownership)
        first.session.resume()
        clock.advance(to: 0)
        first.makeReady()
        first.session.finish()
        expect(first.closeTimes == [0], "Explicit exit must close exactly once")
        clock.advance(to: 0.25)
        let second = Harness(clock: clock, ownership: ownership)
        second.session.resume()
        clock.advance(to: 0.99)
        expect(second.connectTimes.isEmpty, "Rapid reentry must respect old close cooldown")
        clock.advance(to: 1)
        expect(second.connectTimes == [1], "Only the remaining cooldown should be waited")
        first.session.finish()
        expect(first.closeTimes.count == 1, "Late deinit fallback must be idempotent")
        second.session.finish()
        clock.advance(to: 3)
        let third = Harness(clock: clock, ownership: ownership)
        third.session.resume()
        clock.advance(to: 3)
        expect(third.connectTimes == [3], "An expired cooldown must not delay reentry")
    }

    private static func failureRetriesAndThenSucceeds() {
        let h = Harness()
        h.session.resume()
        h.clock.advance(to: 0)
        h.callbacks[0](false)
        expect(h.closeTimes == [0], "Failure must clean old attempt before retry")
        expect(h.session.state.activeAttemptID != nil, "Retry wait should retain connecting presentation")
        h.clock.advance(to: 0.99)
        expect(h.connectTimes.count == 1, "Retry must wait one second")
        h.clock.advance(to: 1)
        expect(h.connectTimes == [0, 1], "Failure should trigger another actual transport connect")
        h.makeReady()
        h.callbacks[0](false)
        h.clock.advance(to: 100)
        expect(h.session.state.isReady && h.exhaustions == 0 && h.closeTimes.count == 1,
               "Stale failure must not disconnect successful retry")
    }

    private static func retriesStopAfterThreeAttempts() {
        let h = Harness()
        h.session.resume()
        for i in 0..<3 {
            h.clock.advance(to: Double(i))
            h.callbacks[i](false)
        }
        h.session.resume()
        h.clock.advance(to: 100)
        expect(h.connectTimes == [0, 1, 2], "Must permit only first attempt plus two retries")
        expect(h.closeTimes.count == 3 && h.exhaustions == 1 && h.session.state == .disconnected,
               "Exhaustion must close the last attempt and show failure once")
    }

    private static func missingCallbackUsesItsOwnDeadlineWithoutAnotherRetry() {
        let h = Harness()
        h.session.resume()
        h.clock.advance(to: 59.99)
        expect(h.connectTimes == [0] && h.closeTimes.isEmpty && h.exhaustions == 0,
               "The callback watchdog must allow the full scan, BLE and GATT stages")
        h.clock.advance(to: 60)
        expect(h.closeTimes == [60] && h.exhaustions == 1,
               "A missing callback must stop at its deadline without retrying outside the admission window")
        h.callbacks.forEach { $0(true) }
        h.clock.advance(to: 100)
        expect(h.connectTimes.count == 1 && h.exhaustions == 1, "Late callbacks must not restart exhausted recovery")
    }

    private static func readyTimeoutOutlivesRetryAdmissionWindow() {
        let h = Harness()
        h.session.resume()
        h.clock.advance(to: 0)
        h.callbacks[0](true)
        h.clock.advance(to: 19.99)
        expect(h.closeTimes.isEmpty, "GATT success should allow 20 seconds for Ready")
        h.clock.advance(to: 21)
        h.callbacks[1](true)
        h.clock.advance(to: 42)
        h.callbacks[2](true)
        h.clock.advance(to: 50)
        expect(h.closeTimes == [20, 41] && h.exhaustions == 0,
               "The admission window must not cancel the third attempt's Ready wait")
        h.clock.advance(to: 62)
        expect(h.closeTimes == [20, 41, 62] && h.exhaustions == 1,
               "Ready must still have a bounded deadline after the admission window")
    }

    private static func thirdAttemptCanBecomeReadyAfterAdmissionWindow() {
        let h = Harness()
        h.session.resume()
        h.clock.advance(to: 15)
        h.callbacks[0](false)
        h.clock.advance(to: 31)
        h.callbacks[1](false)
        h.clock.advance(to: 47)
        h.callbacks[2](true)
        h.clock.advance(to: 50)
        expect(h.connectTimes == [0, 16, 32] && h.closeTimes == [15, 31],
               "The third attempt's GATT success near 50 seconds must not be interrupted")
        h.clock.advance(to: 53)
        h.makeReady()
        h.clock.advance(to: 150)
        expect(h.session.state.isReady && h.readyEvents.count == 1 && h.exhaustions == 0,
               "Ready after 50 seconds must complete the issued attempt")
        expect(h.closeTimes == [15, 31], "Successful late Ready must cancel its deadline")
    }

    private static func scanAndGattCanOutliveAdmissionWindow() {
        let h = Harness()
        h.session.resume()
        // A single SDK attempt may spend 15 seconds scanning, 30 connecting,
        // and another 12 discovering services and enabling notifications.
        h.clock.advance(to: 57)
        expect(h.connectTimes == [0] && h.closeTimes.isEmpty,
               "Scanning time must not shorten the BLE/GATT allowance")
        h.callbacks[0](true)
        h.clock.advance(to: 70)
        h.makeReady()
        h.clock.advance(to: 100)
        expect(h.session.state.isReady && h.exhaustions == 0 && h.closeTimes.isEmpty,
               "A slow first connection must retain its independent Ready allowance")
    }

    private static func lateAttemptKeepsBothStageDeadlines() {
        let h = Harness()
        h.session.resume()
        h.clock.advance(to: 24)
        h.callbacks[0](false)
        h.clock.advance(to: 48)
        h.callbacks[1](false)
        h.clock.advance(to: 108)
        expect(h.connectTimes == [0, 25, 49] && h.closeTimes == [24, 48],
               "An attempt admitted at 49 seconds must keep its full callback deadline")
        h.callbacks[2](true)
        h.clock.advance(to: 127.99)
        expect(h.closeTimes == [24, 48], "The late GATT callback must start a full 20-second Ready deadline")
        h.clock.advance(to: 128)
        expect(h.closeTimes == [24, 48, 128] && h.exhaustions == 1,
               "A late admitted attempt must terminate without starting a fourth attempt")
    }

    private static func cooldownCannotAdmitAttemptAfterWindow() {
        let h = Harness()
        h.session.resume()
        h.clock.advance(to: 49.5)
        h.callbacks[0](false)
        h.clock.advance(to: 50)
        expect(h.connectTimes == [0] && h.closeTimes == [49.5] && h.exhaustions == 1,
               "Admission expiry during cooldown must cancel the queued retry without closing twice")
        h.clock.advance(to: 100)
        expect(h.connectTimes == [0], "A queued attempt must not start outside the admission window")
    }

    private static func exitCancelsQueuedAndActiveAttempts() {
        let queued = Harness()
        queued.session.resume()
        queued.session.finish()
        queued.clock.advance(to: 100)
        expect(queued.connectTimes.isEmpty && queued.closeTimes.isEmpty,
               "Exit before queued start must not touch the transport")
        let active = Harness()
        active.session.resume()
        active.clock.advance(to: 0)
        active.session.finish()
        active.callbacks[0](true)
        active.makeReady()
        active.clock.advance(to: 100)
        expect(active.closeTimes == [0] && active.readyEvents.isEmpty && active.exhaustions == 0,
               "Exit during connect must suppress callbacks and retries")
        let retry = Harness()
        retry.session.resume()
        retry.clock.advance(to: 0)
        retry.callbacks[0](false)
        retry.session.finish()
        retry.clock.advance(to: 100)
        expect(retry.connectTimes.count == 1 && retry.closeTimes.count == 1,
               "Exit during retry wait must not reconnect or close twice")
    }

    private static func oldPageCannotCloseNewPage() {
        let clock = Clock()
        let owner = GatewayDetailConnectionOwnership()
        let old = Harness(clock: clock, ownership: owner)
        let new = Harness(clock: clock, ownership: owner)
        old.session.resume()
        clock.advance(to: 0)
        new.session.resume()
        expect(old.session.isFinished && old.closeTimes == [0], "New page must finish previous owner before connecting")
        clock.advance(to: 1)
        new.makeReady()
        old.callbacks[0](false)
        old.session.resume()
        old.session.finish()
        clock.advance(to: 100)
        expect(new.session.state.isReady && new.closeTimes.isEmpty && old.closeTimes.count == 1,
               "Old callbacks, reappearance or destruction cannot close new owner")
    }

    private static func staleCallbacksCannotReplaceNewAttempt() {
        let h = Harness()
        h.session.resume()
        h.clock.advance(to: 0)
        h.callbacks[0](false)
        h.clock.advance(to: 1)
        let secondAttempt = h.session.state.activeAttemptID
        h.callbacks[0](true)
        h.callbacks[0](false)
        expect(h.session.state.activeAttemptID == secondAttempt && h.closeTimes.count == 1,
               "Stale GATT callbacks must not complete the next attempt")
        h.callbacks[1](true)
        h.makeReady()
        h.clock.advance(to: 100)
        expect(h.session.state.isReady && h.connectTimes.count == 2, "Current attempt must still complete normally")
    }

    private static func hiddenPageDoesNotRetryAndChildReturnReusesReady() {
        let h = Harness()
        h.session.resume()
        h.clock.advance(to: 0)
        h.makeReady()
        let readyID = h.readyID
        h.session.pause()
        h.clock.advance(to: 2)
        h.session.resume()
        expect(h.readyID == readyID && h.closeTimes.isEmpty && h.connectTimes.count == 1,
               "Child page return/cancelled dismiss must reuse established connection")
        let hidden = Harness()
        hidden.session.resume()
        hidden.clock.advance(to: 0)
        hidden.session.pause()
        hidden.callbacks[0](false)
        hidden.clock.advance(to: 30)
        expect(hidden.connectTimes.count == 1 && hidden.exhaustions == 0, "Hidden page must not retry or show failure")
        hidden.session.resume()
        hidden.clock.advance(to: 30)
        expect(hidden.connectTimes.count == 2, "Return should resume a failed hidden connection")
    }

    private static func bluetoothOffCancelsRecovery() {
        let h = Harness()
        h.session.resume()
        h.clock.advance(to: 0)
        h.available = false
        h.session.availabilityChanged()
        h.callbacks[0](false)
        h.clock.advance(to: 20)
        expect(h.connectTimes.count == 1 && h.closeTimes.count == 1 && h.exhaustions == 0,
               "Bluetooth unavailable must stop recovery")
        h.available = true
        h.session.availabilityChanged()
        h.clock.advance(to: 20)
        expect(h.connectTimes.count == 2, "Bluetooth restoration can reconnect the visible page")
    }

    private static func contextReplacementProtectsNewConnection() {
        let h = Harness()
        h.session.resume()
        h.clock.advance(to: 0)
        h.contextCurrent = false
        h.callbacks[0](false)
        h.clock.advance(to: 100)
        expect(h.session.isFinished && h.closeTimes.isEmpty && h.connectTimes.count == 1,
               "A replaced Mesh manager must not be closed by the old page")
    }

    private static func staleReadyDuringCooldownIsIgnored() {
        let h = Harness()
        h.session.resume()
        h.clock.advance(to: 0)
        h.callbacks[0](false)
        h.makeReady()
        expect(!h.session.state.isReady && h.readyEvents.isEmpty, "A Ready event during cleanup/cooldown cannot revive an old attempt")
        h.readyID = nil
        h.clock.advance(to: 1)
        h.makeReady()
        expect(h.session.state.isReady, "New actual connection should still accept Ready")
    }

    private static func deletionKeepsReadyButStopsAutomaticRecovery() {
        let h = Harness()
        h.session.resume()
        h.clock.advance(to: 0)
        h.makeReady()
        h.session.setAutomaticConnectionEnabled(false)
        expect(h.session.state.isReady && h.closeTimes.isEmpty, "Deletion must retain Ready for Node Reset")
        h.readyID = nil
        h.session.connectionLost()
        h.clock.advance(to: 5)
        expect(h.connectTimes.count == 1, "Node Reset disconnect must not cause reconnection")
        h.session.setAutomaticConnectionEnabled(true)
        h.clock.advance(to: 5)
        expect(h.connectTimes.count == 2, "Failed deletion can restore automatic recovery")
    }

    private static func disconnectRetentionIsBounded() {
        let clock = Clock()
        var bearer: NSObject? = NSObject()
        weak var retainedBearer = bearer
        GatewayDetailConnectionSession.retainDuringDisconnect(bearer!) { delay, action in
            clock.schedule(delay, action)
        }
        bearer = nil
        clock.advance(to: 1.99)
        expect(retainedBearer != nil, "Closing bearer must survive SDK removing its last reference")
        clock.advance(to: 2)
        expect(retainedBearer == nil, "Retention must release the old bearer after two seconds")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String,
                               file: StaticString = #file, line: UInt = #line) {
        if !condition() { fatalError(message, file: file, line: line) }
    }

    private final class Clock {
        private final class Job {
            let at: TimeInterval
            let action: () -> Void
            var cancelled = false
            init(at: TimeInterval, action: @escaping () -> Void) { self.at = at; self.action = action }
        }
        var now: TimeInterval = 0
        private var jobs: [Job] = []
        func schedule(_ delay: TimeInterval, _ action: @escaping () -> Void) -> () -> Void {
            let job = Job(at: now + delay, action: action)
            jobs.append(job)
            return { job.cancelled = true }
        }
        func advance(to end: TimeInterval) {
            precondition(end >= now)
            while let next = jobs.filter({ !$0.cancelled && $0.at <= end }).min(by: { $0.at < $1.at }) {
                jobs.removeAll { $0 === next }
                now = next.at
                next.action()
            }
            now = end
        }
    }

    private final class Harness {
        let clock: Clock
        let ownership: GatewayDetailConnectionOwnership
        var contextCurrent = true
        var available = true
        var readyID: UUID?
        var callbacks: [(Bool) -> Void] = []
        var connectTimes: [TimeInterval] = []
        var closeTimes: [TimeInterval] = []
        var readyEvents: [UUID] = []
        var exhaustions = 0
        lazy var session: GatewayDetailConnectionSession = {
            let session = GatewayDetailConnectionSession(
                target: "same-site-gateway", address: 10, ownership: ownership,
                environment: .init(
                    contextIsCurrent: { [unowned self] in contextCurrent },
                    canConnect: { [unowned self] in available },
                    readySession: { [unowned self] in readyID },
                    connect: { [unowned self] callback in
                        connectTimes.append(clock.now)
                        callbacks.append(callback)
                    },
                    disconnect: { [unowned self] in
                        closeTimes.append(clock.now)
                        readyID = nil
                        // Match the SDK's synchronous offline notification.
                        self.session.connectionLost()
                    }
                ),
                callbackTimeout: 60,
                readyTimeout: 20,
                now: { [clock] in clock.now },
                schedule: { [clock] delay, action in clock.schedule(delay, action) }
            )
            session.onReady = { [unowned self] in readyEvents.append($0) }
            session.onExhausted = { [unowned self] in exhaustions += 1 }
            return session
        }()
        init(clock: Clock = Clock(), ownership: GatewayDetailConnectionOwnership = GatewayDetailConnectionOwnership()) {
            self.clock = clock
            self.ownership = ownership
        }
        func makeReady() {
            let id = UUID()
            readyID = id
            session.receiveReady(sessionID: id)
        }
    }
}
