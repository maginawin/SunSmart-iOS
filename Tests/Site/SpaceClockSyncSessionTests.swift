import Foundation

@main struct SpaceClockSyncSessionTests {
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fatalError(message) }
    }
    static func main() {
        let now = Date()
        SiteTimeZoneValue.snapshotProvider = { _, _ in nil }
        let resolution = SiteTimeSetMessageFactory.resolve(storageValue: nil, phoneTimeZone: TimeZone(secondsFromGMT: 28800)!, at: now)!
        var pending: [(SiteTimeSetTimeZoneResolution?) -> Void] = []
        var timers: [() -> Void] = []
        var sends = 0
        var wireValid: (() -> Bool)?
        var reject: (() -> Void)?
        var allowed = true
        let session = SpaceClockSyncSession(prepare: { _, done in pending.append(done) },
            schedule: { _, block in timers.append(block) }, isAllowed: { allowed },
            send: { _, valid, rejected in sends += 1; wireValid = valid; reject = rejected })
        session.activate(connected: true)
        check(timers.count == 1 && pending.isEmpty, "Already-connected entry still schedules after the connection delay")
        timers.removeFirst()(); check(pending.count == 1, "One prepare per burst")
        pending.removeFirst()(nil)
        session.connectionChanged(false); session.connectionChanged(true)
        timers.removeFirst()(); pending.removeFirst()(resolution)
        check(sends == 1 && wireValid?() == true, "Failed first attempt must recover on reconnect")
        session.refresh(retry: false); pending.removeFirst()(resolution)
        check(sends == 1, "Unchanged snapshot notifications must not broadcast again")
        session.refresh(retry: true)
        let late = pending.removeFirst()
        session.stop(); late(resolution)
        check(sends == 1 && wireValid?() == false, "Leaving invalidates queued wire work and late preparation")
        session.activate(connected: true); timers.removeFirst()(); pending.removeFirst()(resolution)
        check(sends == 2, "Re-entry has a new delivery opportunity")
        reject?(); session.refresh(retry: true); pending.removeFirst()(resolution)
        check(sends == 3, "Rejected sends remain retryable without immediate retry loops")
        allowed = false
        check(wireValid?() == false, "Permission loss rejects queued packets")
        session.refresh(retry: true)
        check(pending.isEmpty, "Visitors cannot prepare or send")
        testTargetChangesAndCancellation()
        testStoreFailureAndTransition()
        print("SpaceClockSyncSessionTests passed")
    }
    static func testTargetChangesAndCancellation() {
        let now = Date()
        var next = now.addingTimeInterval(3600)
        var requested = now.addingTimeInterval(-10)
        SiteTimeZoneValue.snapshotProvider = { id, _ in
            try? SiteTimeZoneSnapshot(identifier: id, response: ["code": 200, "data": ["is_dst": false,
                "current_offset": "UTC-06:00", "next_switch": SiteTimeZoneSnapshot.requestDateString(next),
                "switches_to": "UTC-05:00"]], requestedAt: requested)
        }
        var pending: [(SiteTimeSetTimeZoneResolution?) -> Void] = [], timers: [() -> Void] = []
        var sends = 0, validations: [() -> Bool] = []
        let session = SpaceClockSyncSession(prepare: { _, done in pending.append(done) },
            schedule: { _, block in timers.append(block) }, isAllowed: { true },
            send: { _, valid, _ in sends += 1; validations.append(valid) })
        session.activate(connected: true); session.stop(); timers.removeFirst()()
        check(pending.isEmpty, "Leaving during the connection delay must cancel preparation")
        session.activate(connected: true); timers.removeFirst()()
        session.refresh(retry: false)
        pending.removeFirst()(SiteTimeSetMessageFactory.resolve(storageValue: "America/Chicago", at: now))
        check(pending.count == 1, "A notification during preparation coalesces into one follow-up")
        requested = requested.addingTimeInterval(1)
        pending.removeFirst()(SiteTimeSetMessageFactory.resolve(storageValue: "America/Chicago", at: now))
        check(sends == 1, "Changing only requestedAt must not resend the same target")
        next = next.addingTimeInterval(3600)
        session.refresh(retry: false)
        pending.removeFirst()(SiteTimeSetMessageFactory.resolve(storageValue: "America/Chicago", at: now))
        check(sends == 2 && !validations[0]() && validations[1](),
              "Changing only the future transition must send a new target and revoke the old queued work")
        session.refresh(retry: true, force: true)
        pending.removeFirst()(SiteTimeSetMessageFactory.resolve(storageValue: "America/Chicago", at: now))
        check(sends == 3, "Newly added devices need another delivery opportunity for the same target")
        session.stop()
    }

    static func testStoreFailureAndTransition() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = SiteTimeZoneCache(directory: directory)
        var now = SiteTimeZoneSnapshot.parseDate("2026-11-01T06:59:59Z")!
        var responses: [(Result<[String: Any], Error>) -> Void] = []
        var requests = 0, sends: [Int] = []
        let store = SiteTimeZoneStore(now: { now }, read: cache.read, write: cache.write) { _, _, reply in
            requests += 1; responses.append(reply)
        }
        SiteTimeZoneValue.snapshotProvider = { id, _ in store.snapshot(for: id) }
        var delays: [() -> Void] = []
        let session = SpaceClockSyncSession(prepare: { retry, done in
            store.refresh(identifier: "America/Chicago", retry: retry) { _ in
                done(SiteTimeSetMessageFactory.resolve(storageValue: "America/Chicago", at: now))
            }
        }, schedule: { _, block in delays.append(block) }, isAllowed: { true },
           send: { resolution, _, _ in sends.append(resolution.offsetMinutes) })
        let observation = store.observe(identifier: "America/Chicago") { session.refresh(retry: false) }
        defer { store.removeObserver(observation); session.stop() }
        session.activate(connected: true); delays.removeFirst()()
        pumpUntil { responses.count == 1 }
        responses.removeFirst()(.failure(NSError(domain: "offline", code: 1)))
        pumpUntil { requests == 1 && responses.isEmpty }
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        check(requests == 1 && sends.isEmpty, "Failure notification must not recursively retry or send without a Site snapshot")
        session.refresh(retry: true)
        pumpUntil { responses.count == 1 }
        responses.removeFirst()(.success(["code":200, "data":["is_dst":true,"current_offset":"UTC-05:00",
            "next_switch":"2026-11-01T01:00:00-06:00", "switches_to":"UTC-06:00"]]))
        pumpUntil { sends == [-300] }
        session.refresh(retry: false)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        check(requests == 2 && sends == [-300], "Cached success and its notifications must coalesce")
        now = now.addingTimeInterval(1)
        store.refreshObserved()
        pumpUntil { responses.count == 1 }
        responses.removeFirst()(.success(["code":200, "data":["is_dst":false,"current_offset":"UTC-06:00",
            "next_switch":"2027-03-14T03:00:00-05:00", "switches_to":"UTC-05:00"]]))
        pumpUntil { sends == [-300, -360] }
        check(requests == 3, "A long-lived Space must refresh and send the new target at the transition")
        check((try? cache.read("America/Chicago")) != nil, "Snapshot crossed the real durable cache boundary")
    }
    static func pumpUntil(_ predicate: () -> Bool) {
        let deadline = Date().addingTimeInterval(3)
        while !predicate() && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        check(predicate(), "Asynchronous Store/session boundary did not settle")
    }

}
