import Foundation

private final class FakeClockTransport: InformationClockTransport {
    var isCurrent = true
    var canRecover = true
    var bound: Set<InformationClockModel> = [.server, .setup]
    var offset: Int? = 345
    var persistenceSucceeds = true
    var calls: [String] = []
    var readCallbacks: [(InformationClockResponse) -> Void] = []
    var setCallbacks: [(InformationClockResponse) -> Void] = []
    var bindCallbacks: [(Bool) -> Void] = []
    var sentDate: Date?
    var saved: [InformationClockSample] = []

    func isBound(_ model: InformationClockModel) -> Bool { bound.contains(model) }
    func bind(_ model: InformationClockModel, completion: @escaping (Bool) -> Void) {
        calls.append(model == .server ? "bind-server" : "bind-setup")
        bindCallbacks.append { [self] success in
            if success { bound.insert(model) }
            completion(success)
        }
    }
    func targetOffset(at date: Date) -> Int? { offset }
    func setTime(date: Date, offset: Int, completion: @escaping (InformationClockResponse) -> Void) {
        calls.append("set")
        sentDate = date
        setCallbacks.append(completion)
    }
    func getTime(completion: @escaping (InformationClockResponse) -> Void) {
        calls.append("get")
        readCallbacks.append(completion)
    }
    func persist(_ sample: InformationClockSample) -> Bool {
        calls.append("persist")
        if persistenceSucceeds { saved.append(sample) }
        return persistenceSucceeds
    }
    func finish() { calls.append("finish") }
}

@main
struct InformationClockRecoveryTests {
    static let date = Date(timeIntervalSince1970: 1_788_800_000)
    static let sample = InformationClockSample(seconds: 842_115_200, offsetMinutes: 345, taiDelta: 0)

    static func main() {
        normalReadAndDeduplication()
        bindingCombinations()
        terminalFailures()
        environmentAndDetach()
        readbackVerification()
        readbackUsesReportedDelta()
        bindingUsesFreshTime()
        leaseOwnership()
        cacheOwnership()
        print("InformationClockRecoveryTests passed")
    }

    private static func make(_ transport: FakeClockTransport) -> InformationClockRecovery {
        InformationClockRecovery(transport: transport, now: { date })
    }

    private static func normalReadAndDeduplication() {
        let t = FakeClockTransport()
        let operation = make(t)
        var finishes = 0
        operation.onFinish = { require($0 == sample, "Display the actual read sample"); finishes += 1 }
        require(operation.start(), "Start initial read")
        require(!operation.start(), "Merge repeated taps")
        // Read succeeds even when target timezone differs; do not auto-correct it.
        t.offset = -480
        t.readCallbacks[0](.sample(sample))
        t.readCallbacks[0](.noResponse)
        require(t.calls == ["get", "persist", "finish"], "Normal read never sets time")
        require(finishes == 1, "Ignore duplicate terminal callback")
    }

    private static func bindingCombinations() {
        for serverBound in [false, true] {
            for setupBound in [false, true] {
                let t = FakeClockTransport()
                t.bound = []
                if serverBound { t.bound.insert(.server) }
                if setupBound { t.bound.insert(.setup) }
                let operation = make(t)
                operation.start()
                if serverBound { t.readCallbacks[0](.sample(.init(seconds: 0, offsetMinutes: 480, taiDelta: 0))) }
                while !t.bindCallbacks.isEmpty { t.bindCallbacks.removeFirst()(true) }
                require(t.setCallbacks.count == 1, "Exactly one recovery write")
                t.setCallbacks[0](.sample(sample))
                t.readCallbacks.last?(.sample(sample))
                var expected = serverBound ? ["get"] : []
                if !serverBound { expected.append("bind-server") }
                if !setupBound { expected.append("bind-setup") }
                expected += ["set", "get", "persist", "finish"]
                require(t.calls == expected, "Bind only missing Models, then set and read back")
            }
        }
    }

    private static func terminalFailures() {
        for response in [InformationClockResponse.invalid, .sample(.init(seconds: 10, offsetMinutes: 1, taiDelta: 0))] {
            let t = FakeClockTransport(); let operation = make(t); operation.start()
            t.readCallbacks[0](response)
            require(t.calls == ["get", "finish"], "Unrelated invalid responses do not cause writes")
        }
        for bound in [false, true] {
            let t = FakeClockTransport(); t.canRecover = false
            t.bound = bound ? [.server, .setup] : []
            let operation = make(t); operation.start()
            if bound { t.readCallbacks[0](.noResponse) }
            require(!t.calls.contains("set") && t.bindCallbacks.isEmpty, "Read-only or unsupported recovery never mutates")
        }
        let t = FakeClockTransport(); t.bound = []
        let operation = make(t); operation.start(); t.bindCallbacks[0](false)
        require(t.calls == ["bind-server", "finish"], "Binding failure stops immediately")

        for response in [InformationClockResponse.noResponse, .invalid, .sample(.init(seconds: 0, offsetMinutes: 345, taiDelta: 0)), .sample(.init(seconds: sample.seconds, offsetMinutes: 480, taiDelta: 0))] {
            let t = FakeClockTransport(); let operation = make(t); operation.start()
            t.readCallbacks[0](.noResponse); t.setCallbacks[0](response)
            require(t.calls == ["get", "set", "finish"], "Set failure never reads or writes again")
        }
        let p = FakeClockTransport(); p.persistenceSucceeds = false
        let saveOperation = make(p); saveOperation.start(); p.readCallbacks[0](.sample(sample))
        require(p.calls == ["get", "persist", "finish"] && p.saved.isEmpty, "Local save failure does not write device")

        for offset in [nil, 1] as [Int?] {
            let t = FakeClockTransport(); t.offset = offset
            let operation = make(t); operation.start(); t.readCallbacks[0](.noResponse)
            require(t.calls == ["get", "finish"], "Unencodable fallback stops silently")
        }
    }

    private static func environmentAndDetach() {
        for detach in [false, true] {
            for stage in ["read", "bind", "set", "readback"] {
                let t = FakeClockTransport()
                if stage == "bind" { t.bound = [] }
                let operation = make(t); var notified = false
                operation.onFinish = { _ in notified = true }
                operation.start()
                if stage == "set" || stage == "readback" { t.readCallbacks[0](.noResponse) }
                if stage == "readback" { t.setCallbacks[0](.sample(sample)) }
                let calls = t.calls
                if detach { operation.detach() } else { t.isCurrent = false }
                switch stage {
                case "bind": t.bindCallbacks[0](true)
                case "set": t.setCallbacks[0](.sample(sample))
                default: t.readCallbacks.last?(.sample(sample))
                }
                require(t.calls == calls + ["finish"], "Changed Site/key/session or detached page stops every stage")
                require(t.saved.isEmpty && (!detach || !notified), "No stale persistence or detached UI notification")
            }
        }
        let t = FakeClockTransport(); t.bound = []
        let operation = make(t); operation.start(); t.canRecover = false; t.bindCallbacks[0](true)
        require(t.calls == ["bind-server", "finish"], "Recheck write permission after binding")
    }

    private static func readbackVerification() {
        let responses: [InformationClockResponse] = [
            .noResponse, .invalid, .sample(.init(seconds: 0, offsetMinutes: 345, taiDelta: 0)),
            .sample(.init(seconds: sample.seconds, offsetMinutes: 480, taiDelta: 0)),
            .sample(.init(seconds: sample.seconds + 31, offsetMinutes: 345, taiDelta: 0))
        ]
        for response in responses {
            let t = FakeClockTransport(); let operation = make(t); operation.start()
            t.readCallbacks[0](.noResponse); t.setCallbacks[0](.sample(sample))
            t.readCallbacks[1](response)
            require(t.calls == ["get", "set", "get", "finish"], "Readback failure cannot re-enter recovery")
            require(t.saved.isEmpty, "Set ACK alone never publishes success")
        }
        let t = FakeClockTransport(); let operation = make(t); operation.start()
        t.readCallbacks[0](.noResponse)
        t.readCallbacks[0](.sample(sample))
        require(t.calls == ["get", "set"], "Late initial response cannot finish the Set stage")
        t.setCallbacks[0](.sample(sample)); t.readCallbacks[1](.sample(sample))
    }

    private static func bindingUsesFreshTime() {
        let t = FakeClockTransport(); t.bound = []
        var now = date
        let operation = InformationClockRecovery(transport: t, now: { now })
        operation.start(); t.bindCallbacks.removeFirst()(true)
        now = date.addingTimeInterval(20)
        t.bindCallbacks.removeFirst()(true)
        require(t.sentDate == now, "Construct time after binding, not at page entry")
        t.setCallbacks[0](.noResponse)
    }

    private static func readbackUsesReportedDelta() {
        for delta: Int16 in [0, 36, 37] {
            let t = FakeClockTransport(); let operation = make(t)
            let actual = InformationClockSample(
                seconds: sample.seconds + UInt64(delta), offsetMinutes: 345,
                taiDelta: delta, subSecond: 128
            )
            operation.start()
            t.readCallbacks[0](.sample(.init(seconds: 0, offsetMinutes: 345, taiDelta: 0)))
            t.setCallbacks[0](.sample(actual))
            t.readCallbacks[1](.sample(actual))
            require(t.calls == ["get", "set", "get", "persist", "finish"], "Standard TAI readback must not fail the 30-second gate")
            require(t.saved == [actual], "Persist raw seconds only after the converted readback is verified")
        }
        let t = FakeClockTransport(); let operation = make(t); operation.start()
        t.readCallbacks[0](.noResponse); t.setCallbacks[0](.sample(sample))
        t.readCallbacks[1](.sample(.init(seconds: sample.seconds + 37, offsetMinutes: 345, taiDelta: 0)))
        require(t.saved.isEmpty, "Do not hide an actual 37-second error behind a guessed delta")
    }

    private static func leaseOwnership() {
        let first = InformationClockLease.acquire(key: "site/node")!
        require(InformationClockLease.acquire(key: "site/node") == nil, "Detail and Information must not overlap")
        let other = InformationClockLease.acquire(key: "other-site/node")!
        first.release()
        let next = InformationClockLease.acquire(key: "site/node")!
        first.release()
        require(next.isOwner, "Stale release cannot release a newer operation")
        next.release(); other.release()
    }

    private static func cacheOwnership() {
        require(!InformationClockCachePolicy.mayAcceptResponse(
            currentSeconds: 300, currentOffset: 480,
            confirmedSeconds: 100, confirmedOffset: 345,
            responseSeconds: 200, responseOffset: 345
        ), "An old operation must not replace a different newer Node update")
        require(InformationClockCachePolicy.mayAcceptResponse(
            currentSeconds: 200, currentOffset: 345,
            confirmedSeconds: 100, confirmedOffset: 345,
            responseSeconds: 200, responseOffset: 345
        ), "SDK-applied response may be restored and then validated")
        require(InformationClockCachePolicy.mayAcceptResponse(
            currentSeconds: 100, currentOffset: nil,
            confirmedSeconds: 100, confirmedOffset: nil,
            responseSeconds: 0, responseOffset: 480
        ), "Unknown response may recover without treating default timezone as real data")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
    }
}
