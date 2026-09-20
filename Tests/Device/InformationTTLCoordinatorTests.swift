import Foundation

private final class TTLService: InformationTTLService {
    var isCurrent = true
    var readBlocker: InformationTTLFailure?
    var writeBlocker: InformationTTLFailure?
    var canSynchronize = true
    var cachedTTL: UInt8? = 5
    var needsCloudSync = false
    var saves = true
    var calls: [String] = []
    var reads: [(UInt8?) -> Void] = []
    var writes: [(UInt8?) -> Void] = []
    var uploads: [(Bool) -> Void] = []
    var persisted: [UInt8] = []

    func getTTL(completion: @escaping (UInt8?) -> Void) { calls.append("get"); reads.append(completion) }
    func setTTL(_ value: UInt8, completion: @escaping (UInt8?) -> Void) { calls.append("set:\(value)"); writes.append(completion) }
    func persist(_ value: UInt8, markCloudDirty: Bool) -> Bool {
        calls.append(markCloudDirty ? "save-dirty" : "save")
        guard saves else { return false }
        persisted.append(value)
        cachedTTL = value
        if markCloudDirty { needsCloudSync = true }
        return true
    }
    func synchronize(completion: @escaping (Bool) -> Void) { calls.append("upload"); uploads.append(completion) }
}

@main
struct InformationTTLCoordinatorTests {
    static func require(_ value: @autoclosure () -> Bool, _ message: String) {
        if !value() { fatalError(message) }
    }

    private static func ready(_ service: TTLService) -> InformationTTLCoordinator {
        let coordinator = InformationTTLCoordinator(service: service)
        require(coordinator.read(), "Initial read starts")
        service.reads[0](5)
        return coordinator
    }

    static func main() {
        for input in ["2", "127", "005"] { require(InformationTTLValue.parse(input) != nil, "Legal decimal input") }
        for input in ["", "0", "00", "000", "1", "128", "255", "256", "-1", "2.0", " 5", "+5", "0x05", "１２", "999999999999"] {
            require(InformationTTLValue.parse(input) == nil, "Reject invalid input without clamping: \(input)")
        }
        readAndWrite()
        existingZeroCanBeReadAndCorrected()
        verifyAfterUncertainWrite()
        failureAndRetry()
        ownershipAndDetach()
        cloudGenerations()
        print("InformationTTLCoordinatorTests passed")
    }

    static func readAndWrite() {
        let service = TTLService()
        let c = InformationTTLCoordinator(service: service)
        var results: [InformationTTLResult] = []
        c.onResult = { results.append($0) }
        c.read()
        require(c.value == nil && c.phase == .reading, "Cached value is not presented as live")
        require(!c.read() && !c.update(9), "Deduplicate during reading")
        service.reads[0](5)
        require(c.value == 5 && service.calls == ["get", "save"], "Unchanged read does not dirty or upload")
        c.update(5)
        require(results.last == .unchanged && service.writes.isEmpty, "Same value sends no Set")
        require(!c.update(0) && service.writes.isEmpty, "Even a direct coordinator call cannot send TTL zero")
        c.update(2)
        require(c.value == 5, "Do not optimistically replace confirmed value")
        require(!c.update(7), "Duplicate Set is rejected")
        service.writes[0](2)
        require(c.value == 2 && c.phase == .synchronizing, "Confirmed minimum editable TTL is saved and uploaded")
        require(results.last == .unchanged, "No complete success before cloud receipt")
        service.uploads[0](true)
        service.uploads[0](false)
        require(results.last == .updated && !c.needsRetry, "Single terminal outcome")

        let changed = TTLService(); changed.cachedTTL = nil
        let reader = InformationTTLCoordinator(service: changed)
        reader.read(); changed.reads[0](127)
        require(changed.persisted == [127] && changed.uploads.count == 1, "Old nil cache accepts real TTL and syncs")
        changed.uploads[0](true)
        require(reader.phase == .idle && reader.value == 127, "Read finishes")
    }

    static func existingZeroCanBeReadAndCorrected() {
        let service = TTLService(); service.cachedTTL = 0
        let c = InformationTTLCoordinator(service: service)
        c.read(); service.reads[0](0)
        require(c.value == 0 && service.persisted == [0], "Display and preserve an existing device TTL of zero")
        require(!c.update(0) && service.writes.isEmpty, "Existing zero does not allow submitting zero")
        require(c.update(127), "An existing zero can be corrected to an editable TTL")
        service.writes[0](127); service.uploads[0](true)
        require(c.value == 127 && !c.needsRetry, "Corrected TTL completes normally")

        var result: InformationTTLResult?
        c.onResult = { result = $0 }
        c.update(2); service.writes[1](nil); service.reads[1](0); service.uploads[1](true)
        require(c.value == 0 && result == .failed(.mismatch),
                "Zero reported during verification remains device truth, not an invalid packet")
    }

    static func verifyAfterUncertainWrite() {
        for reply in [UInt8?.none, UInt8?(5), UInt8?(255)] {
            let service = TTLService(); let c = ready(service)
            var result: InformationTTLResult?
            c.onResult = { result = $0 }
            c.update(7); service.writes[0](reply)
            require(c.phase == .verifying && service.reads.count == 2, "Uncertain Set gets one verification")
            service.writes[0](7)
            require(service.uploads.isEmpty, "Late Set callback cannot finish verification")
            service.reads[1](7); service.uploads[0](true)
            require(result == .updated && c.value == 7, "Readback can confirm a timed-out write")
        }
        let service = TTLService(); let c = ready(service)
        var result: InformationTTLResult?
        c.onResult = { result = $0 }
        c.update(9); service.writes[0](5); service.reads[1](6); service.uploads[0](true)
        require(result == .failed(.mismatch) && c.value == 6 && service.persisted.last == 6,
                "Persist reported value, never the rejected user input")

        for bad in [UInt8?.none, UInt8?(1), UInt8?(128)] {
            let service = TTLService(); let c = ready(service)
            c.onResult = { result = $0 }
            c.update(7); service.writes[0](nil); service.reads[1](bad)
            require(result == .failed(.unconfirmed) && c.value == nil && service.uploads.isEmpty,
                    "Unknown write result does not claim rollback or upload desired value")
        }
    }

    static func failureAndRetry() {
        let service = TTLService(); let c = ready(service)
        var result: InformationTTLResult?
        c.onResult = { result = $0 }
        c.update(8); service.writes[0](8); service.uploads[0](false)
        require(c.value == 8 && c.needsRetry && result == .failed(.cloudSync), "Cloud failure retains device truth")
        c.retry()
        require(service.writes.count == 1 && service.reads.count == 1 && service.uploads.count == 2,
                "Retry cloud without repeating Mesh")
        service.uploads[1](true)
        require(result == .updated && !c.needsRetry, "Retry completes")

        c.update(9); service.writes[1](9); service.uploads[2](false)
        require(c.update(10), "Pending cloud sync must not block another offline Mesh edit")
        service.uploads[2](true)
        require(c.phase == .writing, "Old upload callback cannot confirm a newer edit")
        service.writes[2](10); service.uploads[3](false)
        require(c.value == 10 && c.needsRetry, "Latest offline device value remains retryable")

        let local = TTLService(); let writer = ready(local)
        writer.onResult = { result = $0 }
        local.saves = false
        writer.update(8); local.writes[0](8)
        require(writer.value == 8 && result == .failed(.localSave) && local.uploads.isEmpty,
                "Local failure never sends unpersisted state to cloud")
        local.saves = true; writer.retry(); local.uploads[0](true)
        require(local.writes.count == 1 && local.persisted.last == 8 && result == .updated, "Retry local save then upload")

        let offline = TTLService(); offline.readBlocker = .disconnected
        let reader = InformationTTLCoordinator(service: offline)
        require(!reader.read() && offline.calls.isEmpty, "No request when disconnected")
        offline.readBlocker = nil; reader.read(); offline.reads[0](nil)
        require(reader.value == nil && reader.phase == .idle, "Read failure can be retried")
    }

    static func ownershipAndDetach() {
        let service = TTLService(); let c = ready(service)
        service.writeBlocker = .permission
        require(!c.update(7) && service.writes.isEmpty, "Permission rechecked at Confirm")
        service.writeBlocker = nil
        c.update(7); service.isCurrent = false; service.writes[0](7)
        require(service.persisted == [5] && service.uploads.isEmpty && c.value == nil,
                "Switched network cannot persist a stale response")

        let detached = TTLService(); let writer = ready(detached)
        var called = false
        writer.onResult = { _ in called = true }
        writer.update(9); writer.detach(); detached.writes[0](9); detached.uploads[0](true)
        require(detached.persisted.last == 9 && !called, "Page exit preserves confirmed write but silences UI")

        let reading = TTLService(); let reader = InformationTTLCoordinator(service: reading)
        reader.read(); reader.detach(); reading.reads[0](6)
        require(reading.persisted.isEmpty, "Detached read does not start a new cloud mutation")
    }

    static func cloudGenerations() {
        require(InformationTTLCloudConfirmation.result(target: 20, uploaded: 19, failed: false, expired: false) == nil,
                "Older successful upload does not acknowledge current TTL")
        require(InformationTTLCloudConfirmation.result(target: 20, uploaded: 0, failed: false, expired: false) == nil,
                "Replacement/cancel without a receipt keeps waiting")
        require(InformationTTLCloudConfirmation.result(target: 20, uploaded: 21, failed: false, expired: false) == true,
                "A newer confirmed snapshot covers this edit")
        require(InformationTTLCloudConfirmation.result(target: 20, uploaded: 19, failed: true, expired: false) == false,
                "Current upload failure ends foreground waiting")
        require(InformationTTLCloudConfirmation.result(target: 20, uploaded: 19, failed: false, expired: true) == false,
                "Unconfirmed cancellation cannot hold the HUD forever")
    }
}
