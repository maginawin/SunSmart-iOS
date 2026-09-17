import Foundation
import Darwin

#if os(macOS)
@main
#endif
struct SpaceProtectionReadSnapshotTests {
    static var report = ""
    static func require(_ condition: @autoclosure () -> Bool, _ text: String) {
        if !condition() {
            #if DEBUG
            print("FAIL: " + text)
            #endif
            exit(1)
        }
    }
    static func mutation(_ action: () throws -> Void) rethrows {
        SpaceProtectionReadGeneration.beginMutation()
        defer { SpaceProtectionReadGeneration.endMutation() }
        try action()
    }
    static func cpu() -> Double {
        var value = rusage()
        getrusage(RUSAGE_SELF, &value)
        return Double(value.ru_utime.tv_sec + value.ru_stime.tv_sec)
            + Double(value.ru_utime.tv_usec + value.ru_stime.tv_usec) / 1_000_000
    }
    static func main() throws {
        try run()
        #if DEBUG
        print(report)
        #endif
    }
    static func run() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("protection-test-" + UUID().uuidString)
        let suite = "protection-test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { try? FileManager.default.removeItem(at: root); defaults.removePersistentDomain(forName: suite) }
        let scope = SpaceProtectionReadRequest.Scope(account: "fixture", region: "fixture", meshUUID: "mesh", networkID: "net")
        let request = SpaceProtectionReadRequest(scope: scope, root: root, defaults: defaults)
        require(!request.read().isBlocked, "missing recovery directory must remain readable as absent")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let key = scope.storageKey
        let stateURL = root.appendingPathComponent(key + ".json")
        let directory = root.appendingPathComponent(key)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let identity = SpaceRecoveryState.Identity(account: scope.account, region: scope.region,
            space: .init(siteId: "site", spaceId: "space", meshUUID: scope.meshUUID, networkId: scope.networkID))
        var state = SpaceRecoveryState(identity: identity)
        // A real encoded baseline is decoded by the original reader on every check.
        state.authorizationBaseline = Data(repeating: 65, count: 16_384)
        var journal = SpaceDeletionJournal(scope: identity.space)
        let journalURL = directory.appendingPathComponent("device-deletions.json")
        try mutation { try state.write(to: stateURL); try journal.write(to: journalURL) }
        let clean = request.read()
        require(!clean.isBlocked && clean.phase == .active && clean.authority == .writable, "clean state not preserved")
        require(clean.recoveryGeneration == state.generation, "recovery generation not retained")
        for marker in ["pending-import.json", "pending-reference-cleanup.json"] {
            let file = directory.appendingPathComponent(marker)
            try mutation { try Data("pending".utf8).write(to: file, options: .atomic) }
            require(!clean.isCurrent && request.read().isBlocked, "marker change reused permitted snapshot")
            try mutation { try FileManager.default.removeItem(at: file) }
        }
        try mutation { try Data("broken".utf8).write(to: stateURL, options: .atomic) }
        require(request.read().isBlocked && request.read().failure == .unreadable, "corrupt recovery state allowed")
        try mutation { try state.write(to: stateURL) }
        state.phase = .removing
        try mutation { try state.write(to: stateURL) }
        require(request.read().isBlocked, "removing phase allowed")
        state.phase = .active
        try mutation { try state.write(to: stateURL) }
        journal.entries = [.init(id: UUID(), nodeUUID: "node", primaryAddress: 1, elementAddresses: [1], macAddress: nil, productId: nil)]
        try mutation { try journal.write(to: journalURL) }
        require(request.read().pendingDeletion && request.read().isBlocked, "pending deletion allowed")
        journal.entries = []
        try mutation { try journal.write(to: journalURL) }
        try mutation { try Data("broken".utf8).write(to: journalURL) }
        require(request.read().failure == .unreadable && request.read().isBlocked, "corrupt journal allowed")
        try mutation { try journal.write(to: journalURL) }
        var replacedDuringRead = false
        AppPerformance.observe { sample in
            if sample.name == "ProtectionFileProbe" && !replacedDuringRead {
                replacedDuringRead = true
                mutation { try! journal.write(to: journalURL) }
            }
        }
        let mixed = request.read()
        AppPerformance.observe(nil)
        require(replacedDuringRead && mixed.failure == .mutation && mixed.isBlocked, "atomic replacement during read accepted")
        mutation { defaults.set("blocked", forKey: "spaceConfigurationBlocked." + key) }
        require(request.read().blockedReason == "blocked" && request.read().isBlocked, "blocked reason lost")
        mutation { defaults.removeObject(forKey: "spaceConfigurationBlocked." + key) }
        let beforeFailedWrite = request.read()
        do {
            try mutation { throw CocoaError(.fileWriteNoPermission) }
        } catch {}
        require(!beforeFailedWrite.isCurrent, "failed write retained previous generation")
        var committed = false
        require(!beforeFailedWrite.commit { committed = true } && !committed, "invalidated snapshot committed cached result")
        SpaceProtectionReadGeneration.beginMutation()
        require(request.read().failure == .mutation && request.read().isBlocked, "read during mutation allowed")
        SpaceProtectionReadGeneration.endMutation()
        let backgroundSnapshot = request.read()
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            mutation { defaults.set("changed", forKey: "spaceConfigurationBlocked." + key) }
            done.signal()
        }
        done.wait()
        require(!backgroundSnapshot.isCurrent, "background writer did not invalidate snapshot")
        mutation { defaults.removeObject(forKey: "spaceConfigurationBlocked." + key) }
        let other = SpaceProtectionReadRequest(scope: .init(account: "other", region: scope.region, meshUUID: "mesh", networkID: "net"), root: root, defaults: defaults)
        try mutation { try state.write(to: root.appendingPathComponent(other.scope.storageKey + ".json")) }
        require(other.read().isBlocked, "identity mismatch allowed")
        state.directoryName = "../outside"
        try mutation { try state.write(to: stateURL) }
        require(request.read().isBlocked, "corrupt directory accepted")
        state.directoryName = nil
        try mutation { try state.write(to: stateURL) }
        // An existing but unreadable file is different from an absent file.
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: stateURL.path)
        let permissionResult = request.read()
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stateURL.path)
        require(permissionResult.isBlocked, "permission denied treated as absent")

        let lock = NSLock()
        var reads = 0, probes = 0, mainReads = 0
        AppPerformance.observe { sample in
            lock.lock(); defer { lock.unlock() }
            if sample.name == "ProtectionFileRead" { reads += sample.value; if sample.main { mainReads += sample.value } }
            if sample.name == "ProtectionFileProbe" { probes += sample.value }
        }
        let worker = DispatchQueue(label: "protection-test-reader")
        func readOnWorker() -> SpaceProtectionReadSnapshot {
            let done = DispatchSemaphore(value: 0)
            var value: SpaceProtectionReadSnapshot!
            worker.async { value = request.read(); done.signal() }
            done.wait()
            return value
        }
        let snapshot = readOnWorker()
        for _ in 0..<5_000 { require(!snapshot.isBlocked && snapshot.isCurrent, "stable snapshot changed") }
        require(reads == 2 && probes == 2 && mainReads == 0,
                "5000 checks must use one worker read (2 files, 2 probes), no main file I/O")
        AppPerformance.observe(nil)
        var oldWall: [Double] = [], newWall: [Double] = [], oldCPU: [Double] = [], newCPU: [Double] = []
        // 15 fresh snapshots, with OS file cache warm. This does not represent
        // process cold starts or the complete live Node pipeline.
        for _ in 0..<15 {
            var start = ProcessInfo.processInfo.systemUptime; var cpuStart = cpu()
            for _ in 0..<2_000 { require(!LegacyProtectionReader.isBlocked(request), "legacy fixture invalid") }
            oldWall.append(ProcessInfo.processInfo.systemUptime - start); oldCPU.append(cpu() - cpuStart)
            start = ProcessInfo.processInfo.systemUptime; cpuStart = cpu()
            let captured = readOnWorker()
            for _ in 0..<2_000 { require(!captured.isBlocked, "snapshot fixture invalid") }
            newWall.append(ProcessInfo.processInfo.systemUptime - start); newCPU.append(cpu() - cpuStart)
        }
        func median(_ values: [Double]) -> Double { values.sorted()[values.count / 2] }
        report = String(format: "PASS: real protection files, corruption/permissions/identity/pending/mutation; 5000 checks = 2 reads + 2 probes, main reads=0; 15 x 2000 checks median wall %.4f -> %.4f s, CPU %.4f -> %.4f s", median(oldWall), median(newWall), median(oldCPU), median(newCPU))
    }
}
