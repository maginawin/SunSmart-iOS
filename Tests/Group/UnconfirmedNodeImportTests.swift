import Foundation

extension SpaceRecoveryReceiptTests {
    @MainActor static func testUnconfirmedNodeImports() async throws {
        typealias S = SpaceConfigurationSafety
        typealias P = ProximityLightingImportPreflight
        defer { P.storedSpace = nil; P.onExport = nil }

        for mode in ["http500", "timeout", "noReceipt", "receiptRetired", "reopened", "partial", "replacement", "keyChanged", "knownNodes", "legacyReceipt", "legacyBaseline"] {
            for readback in [false, true] {
                var space = SpaceData()
                space.lastUpdate = 40
                space.nodes = mode == "knownNodes" ? try [membershipNode(1), membershipNode(2)] : []
                P.storedSpace = space
                let baseline = S.prepareSubmission(space, payload: space.payload)!
                precondition(S.markSubmissionAccepted(baseline, space: space))
                precondition(S.finishAcceptedSubmission(baseline, space: space))
                space.nodes = try [membershipNode(1), membershipNode(2)]
                space.lastUpdate = 50
                if mode != "noReceipt" && mode != "legacyBaseline" {
                    let receipt = S.prepareSubmission(space, payload: space.payload)!
                    let error: NetworkApiError = mode == "timeout" ? .requestTimeout
                        : .init(code: 9999, message: "unknown error", httpStatusCode: 500,
                                responseBody: "{\"code\":\"9999\",\"message\":\"unknown error\"}")
                    S.rejectSubmission(receipt, space: space, error: error)
                    space.syncCloudError = error
                }
                if mode == "legacyReceipt" || mode == "legacyBaseline" {
                    var legacy = try S.recoveryState(space)
                    if mode == "legacyReceipt" { legacy.submission?.nodeIdentities = nil }
                    if mode == "legacyBaseline" {
                        legacy.nodeIdentitiesBaseline = nil
                        space.nodes[0]["createdTimestamp"] = 45
                        space.nodes[1]["createdTimestamp"] = 46
                    }
                    try S.testSaveState(legacy, space: space)
                }
                if mode == "receiptRetired" {
                    guard case .success = S.resumeLocalUpload(space) else { preconditionFailure("existing retry preparation") }
                    precondition(!S.hasPendingUpload(space))
                }
                if mode == "reopened" {
                    // New Space object, same on-disk recovery receipt and confirmed baseline.
                    let reopened = SpaceData(space.id)
                    reopened.nodes = space.nodes; reopened.lastUpdate = 50; reopened.lastUploadCloudTimestamp = 40
                    space = reopened; P.storedSpace = space
                }
                let before = try S.recoveryState(space)
                let originalNodes = space.nodes
                var remote = space.payload
                remote["role"] = "owner"
                remote["nodes"] = mode == "partial" ? [try membershipNode(1)]
                    : mode == "replacement" ? [try membershipNode(3), try membershipNode(4)] : []
                remote["deviceCount"] = mode == "partial" ? 1 : 0 // Protection cannot depend on a stale summary.
                if mode == "keyChanged" {
                    var replaced = originalNodes
                    replaced[1]["deviceKey"] = String(repeating: "C3", count: 16)
                    remote["nodes"] = replaced; remote["deviceCount"] = 2
                }
                if readback {
                    NetworkRequest.shared.result = .success(["data": remote])
                    guard case .failure = await S.resumeUpload(space, readbackAttempts: 1) else {
                        preconditionFailure("missing unconfirmed nodes must not complete readback: \(mode)")
                    }
                } else {
                    let outcome = await space.update(spaceJsonData: remote)
                    precondition(outcome == .preserved("unconfirmedLocalNodes"),
                                 "equal cloud must stop before import preparation: \(mode), \(outcome)")
                }
                precondition(NSDictionary(dictionary: ["nodes": space.nodes]).isEqual(to: ["nodes": originalNodes]))
                precondition(space.lastUpdate == 50 && space.lastUploadCloudTimestamp == 40 && space.needUploadCloud)
                precondition(try! S.recoveryState(space) == before, "receipt and generation must survive on disk")
                precondition(!S.hasPendingImport(space))
                precondition(space.syncCloudError != nil)

                // A later complete equal-version read remains eligible; this exception
                // must not become a persistent block or modify retry scheduling.
                remote["nodes"] = originalNodes
                NetworkRequest.shared.result = .success(["data": remote])
                guard case .success = await S.resumeUpload(space, readbackAttempts: 1) else {
                    preconditionFailure("complete readback must still finish: \(mode)")
                }
                precondition(space.nodes.count == 2 && !S.hasPendingUpload(space) && !space.needUploadCloud)
            }
        }

        for mode in ["clean", "metadataOnly", "accepted", "newerCloud", "localDeletion", "visitor", "firstUpload"] {
            let space = SpaceData()
            space.nodes = try [membershipNode(1), membershipNode(2)]
            space.lastUpdate = 40; P.storedSpace = space
            if mode != "firstUpload" {
                let baseline = S.prepareSubmission(space, payload: space.payload)!
                precondition(S.markSubmissionAccepted(baseline, space: space))
                precondition(S.finishAcceptedSubmission(baseline, space: space))
            }
            if mode != "clean" { space.lastUpdate = 50 }
            if mode == "accepted" {
                let receipt = S.prepareSubmission(space, payload: space.payload)!
                precondition(S.markSubmissionAccepted(receipt, space: space))
            }
            if mode == "newerCloud" || mode == "visitor" {
                _ = S.prepareSubmission(space, payload: space.payload)!
            }
            if mode == "localDeletion" { space.nodes.removeAll() }
            var remote = space.payload
            remote["nodes"] = [[String: Any]]()
            remote["role"] = mode == "visitor" ? "visitor" : "owner"
            if mode == "newerCloud" { remote["updateTimestamp"] = 60 }
            let outcome = await space.update(spaceJsonData: remote)
            if mode == "firstUpload" {
                precondition(outcome == .preserved("unconfirmedLocalNodes") && space.nodes.count == 2)
            } else {
                precondition(outcome == .prepared, "existing cloud authority must remain reachable: \(mode), \(outcome)")
            }
        }
        for mode in ["cancelled", "localEdit", "receiptConfirmed", "account", "missingRow", "password"] {
            let space = SpaceData()
            space.nodes = try [membershipNode(1), membershipNode(2)]
            space.lastUploadCloudTimestamp = 40; P.storedSpace = space
            let receipt = S.prepareSubmission(space, payload: space.payload)!
            var remote = space.payload; remote["nodes"] = [[String: Any]](); remote["role"] = "editor"
            if mode == "password" { remote["userEvents"] = ["EditorPasswdChanged"] }
            P.onExport = {
                P.onExport = nil
                if mode == "localEdit" { space.lastUpdate = 51 }
                if mode == "receiptConfirmed" { precondition(S.markSubmissionAccepted(receipt, space: space)) }
                if mode == "account" { UserData.currentUserId = "other-account" }
                if mode == "missingRow" { P.storedSpace = nil }
            }
            let outcome: SpaceImportOutcome
            if mode == "cancelled" {
                let payload = remote
                let task = Task { @MainActor in await space.update(spaceJsonData: payload) }
                task.cancel(); outcome = await task.value
            } else { outcome = await space.update(spaceJsonData: remote) }
            UserData.currentUserId = "test-account"; P.onExport = nil
            if mode == "password" {
                precondition(outcome == .preserved("unconfirmedLocalNodes") && space.requiresPasswordVerification)
            } else {
                precondition(outcome == .rejected("staleImportPreparation"), "stale inspection cannot authorize import: \(mode)")
            }
            precondition(space.nodes.count == 2 && !S.hasPendingImport(space))
            precondition(try! S.recoveryState(space).generation == receipt.generation)
        }
        print("PASS: equal cloud preserves unknown submissions and unconfirmed additions across entry/readback/reopen; complete, accepted, clean, newer and authority paths remain reachable")
    }
}
