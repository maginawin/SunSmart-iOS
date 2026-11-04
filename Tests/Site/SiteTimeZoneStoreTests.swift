import Foundation

@main
struct SiteTimeZoneStoreTests {
    static func check(_ value: @autoclosure () -> Bool, _ message: String) { if !value() { fatalError(message) } }
    static func pump(_ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(5)
        while !condition() && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        check(condition(), "Asynchronous cache boundary timed out")
    }
    static func response(next: Any = "2026-11-01T01:00:00-06:00", offset: String = "UTC-05:00", dst: Bool = true, to: Any = "UTC-06:00") -> [String: Any] {
        ["code": 200, "data": ["is_dst": dst, "current_offset": offset, "next_switch": next, "switches_to": to]]
    }
    static func main() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let files = SiteTimeZoneCache(directory: dir)
        var now = SiteTimeZoneSnapshot.parseDate("2026-10-28T12:00:00Z")!
        var callbacks: [(Result<[String: Any], Error>) -> Void] = []
        var dates: [Date] = []
        let store = SiteTimeZoneStore(now: { now }, read: files.read, write: files.write) { _, date, callback in
            dates.append(date); callbacks.append(callback)
        }
        var done = 0
        store.refresh(identifier: "America/Chicago") { value in check(value?.offsetMinutes == -300, "Successful response published"); done += 1 }
        store.refresh(identifier: "America/Chicago") { _ in done += 1 }
        pump { callbacks.count == 1 }
        callbacks.removeFirst()(.success(response()))
        pump { done == 2 }
        check(store.snapshot(for: "America/Chicago")?.offsetMinutes == -300, "Memory snapshot retained")
        store.refresh(identifier: "America/Chicago") { _ in done += 1 }
        pump { done == 3 }; check(dates.count == 1, "Same natural day must reuse success")
        var restartedRequests = 0
        let restarted = SiteTimeZoneStore(now: { now }, read: files.read, write: files.write) { _, _, _ in restartedRequests += 1 }
        var restored = false
        restarted.refresh(identifier: "America/Chicago") { value in restored = value?.offsetMinutes == -300 }
        pump { restored }; check(restartedRequests == 0, "Restart must reuse durable daily success")
        now = SiteTimeZoneSnapshot.parseDate("2026-10-29T05:00:00Z")!
        store.refresh(identifier: "America/Chicago") { value in check(value?.offsetMinutes == -300, "Pre-transition stale cache survives refresh failure"); done += 1 }
        pump { callbacks.count == 1 }
        callbacks.removeFirst()(.failure(NSError(domain: "offline", code: 1)))
        pump { done == 4 }
        store.refresh(identifier: "America/Chicago") { _ in done += 1 }
        pump { callbacks.count == 1 }; callbacks.removeFirst()(.success(response()))
        pump { done == 5 }; check(dates.count == 3, "Failure does not consume today's success")
        now = SiteTimeZoneSnapshot.parseDate("2026-11-01T06:59:59Z")!
        store.refresh(identifier: "America/Chicago") { value in check(value == nil, "Late pre-transition response is not a usable current offset"); done += 1 }
        pump { callbacks.count == 1 }
        now = now.addingTimeInterval(1)
        callbacks.removeFirst()(.success(response()))
        pump { done == 6 }
        store.refresh(identifier: "America/Chicago") { value in check(value?.offsetMinutes == -360, "Transition allows an additional same-day success"); done += 1 }
        pump { callbacks.count == 1 }
        callbacks.removeFirst()(.success(response(next: "2027-03-14T03:00:00-05:00", offset: "UTC-06:00", dst: false, to: "UTC-05:00")))
        pump { done == 7 }
        store.refresh(identifier: "America/Chicago") { _ in done += 1 }
        pump { done == 8 }; check(dates.count == 5, "Transition refresh must not repeat after success")
        now = now.addingTimeInterval(-120)
        check(store.usableSnapshot(for: "America/Chicago") == nil, "Clock rollback cannot use a future server sample")
        // Persist failure preserves this process's success; a new process has to fetch again.
        var writes = 0, faultRequests = 0, faultDone = false
        let fault = SiteTimeZoneStore(now: { now }, read: { _ in Data("corrupt cache".utf8) }, write: { _, _ in
            writes += 1; throw NSError(domain: "disk", code: 1)
        }, fetch: { _, _, complete in
            faultRequests += 1
            complete(.success(response(next: NSNull(), offset: "UTC+05:45", dst: false, to: NSNull())))
        })
        fault.refresh(identifier: "Asia/Kathmandu") { value in faultDone = value?.offsetMinutes == 345 }
        pump { faultDone }
        fault.refresh(identifier: "Asia/Kathmandu") { _ in }
        check(writes == 1 && faultRequests == 1, "Corrupt cache is replaced and disk failure does not repeat same-process success")
        var started: [String] = [], releases: [(Result<[String: Any], Error>) -> Void] = [], queueDone = 0
        let limited = SiteTimeZoneStore(now: { now }, read: { _ in nil }, write: { _, _ in }) { id, _, callback in
            started.append(id); releases.append(callback)
        }
        for id in ["Test/One", "Test/Two", "Test/Three", "Test/Four"] {
            limited.refresh(identifier: id) { _ in queueDone += 1 }
        }
        pump { started.count == 3 }
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        check(started.count == 3, "Visible timezone requests have bounded concurrency")
        releases.removeFirst()(.failure(NSError(domain: "offline", code: 1)))
        pump { started.count == 4 && queueDone == 1 }
        for callback in releases { callback(.success(response(next: NSNull(), offset: "UTC+00:00", dst: false, to: NSNull()))) }
        pump { queueDone == 4 }
        print("SiteTimeZoneStoreTests passed")
    }
}
