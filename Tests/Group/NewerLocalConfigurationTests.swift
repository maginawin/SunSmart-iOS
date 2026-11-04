import Foundation

extension SpaceRecoveryReceiptTests {
    @MainActor static func newerLocalFixture() throws -> (SpaceData, [String: Any]) {
        typealias S = SpaceConfigurationSafety
        let space = SpaceData()
        space.nodes = try (1...2).map(membershipNode)
        space.groups = [["address": "C000", "name": "G1", "parentAddress": "0000",
                         "profile": ["id": "profile", "type": 1]]]
        let members = try space.nodes.map { node -> [String: Any] in
            ["identity": ["nodeUUID": node["uuid"]!, "unicastAddress": node["unicastAddress"]!,
                          "deviceKeyFingerprint": try SchedulerModelSnapshot.keyFingerprint(node)],
             "parameters": ["isOn": true, "lightness": 65535, "cct": 4500]]
        }
        let scene: [String: Any] = ["number": "0004", "name": "Scene 4", "kind": "devices",
            "schemaVersion": 1, "revision": UUID().uuidString, "isDeleting": false,
            "deviceMembers": members, "pendingOperations": []]
        space.exportValues = ["scenes": [["number": "0004", "name": "Scene 4", "imageId": 0]],
                              "spaceData": ["timedSchemaVersion": 1, "sceneConfigurations": [scene]]]
        space.lastUpdate = 90; space.lastUploadCloudTimestamp = 90
        let baseline = space.payload
        S.verifyUpgradeBaseline(space, local: baseline, remote: baseline)
        try SpaceMembershipCoordinator.confirmConfiguration(space)
        var remote = baseline
        remote["updateTimestamp"] = 80
        var oldScene = scene
        oldScene["revision"] = UUID().uuidString
        oldScene["deviceMembers"] = []
        remote["spaceData"] = ["timedSchemaVersion": 1, "sceneConfigurations": [oldScene]]
        space.nodes = space.nodes.map { $0.merging(["groupAddress": "C000", "groupState": 1]) { _, value in value } }
        space.lastUpdate = 100
        ProximityLightingImportPreflight.storedSpace = space
        return (space, remote)
    }

    @MainActor static func testNewerLocalConfiguration() async throws {
        typealias S = SpaceConfigurationSafety
        let request = NetworkRequest.shared
        defer {
            ProximityLightingImportPreflight.storedSpace = nil
            ProximityLightingImportPreflight.onExport = nil
            S.failStateWrite = false
            request.responses = []
        }
        for mode in ["plain", "baselineBlocked", "readbackBlocked", "membershipBlocked", "import", "cleanLocal", "emptyLocal", "betweenVersions"] {
            let (space, original) = try newerLocalFixture()
            var remote = original
            if mode == "betweenVersions" { remote["updateTimestamp"] = 95 }
            if mode == "baselineBlocked" { S.block(space, reason: "cloudBaselineNeedsReview") }
            if mode == "readbackBlocked" { S.block(space, reason: "uploadReadbackConflict") }
            if mode == "membershipBlocked" { S.block(space, reason: "cloudConfigurationConflict") }
            if mode == "cleanLocal" { space.lastUploadCloudTimestamp = space.lastUpdate }
            if mode == "emptyLocal" {
                space.nodes = []; space.groups = []; space.exportValues = [:]
            }
            let localNodes = space.nodes
            let localConfiguration = SpaceConfigurationIntegrityPolicy.configurationData(space.payload)
            let confirmed = space.lastUploadCloudTimestamp
            let uploads = request.uploads
            request.result = .success(["data": remote])
            precondition(!S.prefersNewerCloud(space, remote: remote), "older cloud must not replace newer local data: " + mode)
            if mode == "import" || mode == "cleanLocal" {
                let result = await space.update(spaceJsonData: remote)
                precondition(result == .preserved("newerLocalConfiguration"), "entry import must preserve the newer local snapshot")
            } else {
                guard case .success = await S.resumeUpload(space) else {
                    preconditionFailure("newer local Scene and Group must be uploadable: " + mode + " diagnostics=\(S.debugSnapshotStatus(space)["lastReadbackDiagnostic"] ?? "none")")
                }
            }
            precondition(!S.isBlocked(space) && space.needUploadCloud && !S.hasPendingUpload(space), mode)
            precondition(space.lastUploadCloudTimestamp == confirmed && request.uploads == uploads)
            precondition(NSArray(array: space.nodes).isEqual(to: localNodes), "selection must not merge old cloud nodes")
            precondition(SpaceConfigurationIntegrityPolicy.configurationsMatch(localConfiguration,
                SpaceConfigurationIntegrityPolicy.configurationData(space.payload)))
            request.responses = [.success(["data": remote]), .success([:]), .success(["data": space.payload])]
            guard case .success = await S.uploadBeforeUnbind(space) else { preconditionFailure("local replacement must complete: " + mode) }
            precondition(!space.needUploadCloud && !S.hasPendingUpload(space) && request.uploads == uploads + 1)
            precondition(SpaceConfigurationIntegrityPolicy.configurationsMatch(localConfiguration,
                SpaceConfigurationIntegrityPolicy.configurationData(request.lastSpaceUpload!)))
        }
        print("PASS: newer local full configuration wins over old cloud Scene, members, saved conflicts and empty/clean local state")
        for accepted in [false, true] {
            let (space, remote) = try newerLocalFixture()
            let receipt = S.prepareSubmission(space, payload: space.payload)!
            if accepted { precondition(S.markSubmissionAccepted(receipt, space: space)) }
            let uploads = request.uploads
            request.responses = [.success(["data": remote]), .success([:]), .success(["data": space.payload])]
            guard case .success = await S.uploadBeforeUnbind(space) else {
                preconditionFailure("retry must replace the older cloud with the current local version")
            }
            precondition(request.uploads == uploads + 1 && !S.hasPendingUpload(space) && !space.needUploadCloud)
            precondition(!S.markSubmissionAccepted(receipt, space: space), "late receipt must not acknowledge the replacement")
        }
        let (space, remote) = try newerLocalFixture()
        request.responses = [.success(["data": remote]), .success([:])]
        request.result = .success(["data": remote])
        guard case .failure = await S.uploadBeforeUnbind(space) else {
            preconditionFailure("POST success followed by old GET must not report success")
        }
        precondition(S.hasPendingUpload(space) && space.lastUploadCloudTimestamp == 90 && space.needUploadCloud)
        precondition(space.lastUpdate == 100 && space.nodes.count == 2)
        request.responses = [.success(["data": remote]), .success([:]), .success(["data": space.payload])]
        guard case .success = await S.uploadBeforeUnbind(space) else { preconditionFailure("old readback must remain retryable") }
        precondition(!S.hasPendingUpload(space) && !space.needUploadCloud && space.lastUploadCloudTimestamp == 100)
        print("PASS: pending/accepted retries replace older cloud while stale readback stays unconfirmed until a matching GET")
        for mode in ["role", "key", "invalidLocal", "stateWrite", "spaceWrite", "cancelled", "localChanged",
                     "membershipChanged", "cleanupDuringExport", "unrelatedBlock", "offline"] {
            let (space, original) = try newerLocalFixture()
            var remote = original
            if mode == "role" { remote["role"] = "visitor" }
            if mode == "key" { remote["netKey"] = ["key": "wrong"] }
            if mode == "invalidLocal" { space.exportValues["spaceData"] = ["sceneConfigurations": "broken"] }
            if mode == "stateWrite" { S.failStateWrite = true }
            if mode == "spaceWrite" { space.savesSucceed = false }
            if mode == "unrelatedBlock" { S.block(space, reason: "invalidStoredGroupConfiguration") }
            if mode == "localChanged" { ProximityLightingImportPreflight.onExport = { space.lastUpdate += 1 } }
            if mode == "membershipChanged" { ProximityLightingImportPreflight.onExport = { SpaceMembershipResponseContext.invalidate() } }
            if mode == "cleanupDuringExport" {
                ProximityLightingImportPreflight.onExport = {
                    precondition(S.updateDeletionJournal(space) {
                        $0.entries.append(.init(id: UUID(), nodeUUID: UUID().uuidString, primaryAddress: 3,
                            elementAddresses: [3], macAddress: nil, productId: nil, stage: .removed))
                    })
                }
            }
            request.result = mode == "offline" ? .failure(.noNetwork) : .success(["data": remote])
            let result: Swift.Result<Void, NetworkApiError>
            if mode == "cancelled" {
                let task = Task { @MainActor in await S.resumeUpload(space) }
                task.cancel(); result = await task.value
            } else { result = await S.resumeUpload(space) }
            ProximityLightingImportPreflight.onExport = nil; S.failStateWrite = false; space.savesSucceed = true
            guard case .failure = result else { preconditionFailure("invalid authority, data or late state change must not authorize upload: " + mode) }
            precondition(space.lastUploadCloudTimestamp == 90 && space.nodes.count == 2)
            if mode == "stateWrite" || mode == "spaceWrite" {
                guard case .success = await S.resumeUpload(space) else { preconditionFailure("persistence retry: " + mode) }
                precondition(space.needUploadCloud && !S.hasPendingUpload(space))
            }
        }
        print("PASS: newer local selection respects network identity, authority, invalid data, persistence retry, cancellation and state changes during export")
    }
}
