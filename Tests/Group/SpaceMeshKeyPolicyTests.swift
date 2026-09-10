import Foundation

@main struct SpaceMeshKeyPolicyTests {
    static func main() throws {
        typealias P = SpaceMeshKeyPolicy
        let net: [String: Any] = ["index": 1, "key": String(repeating: "11", count: 16), "phase": 0]
        let app: [String: Any] = ["index": 1, "boundNetKey": 1, "key": String(repeating: "22", count: 16)]
        let valid: [String: Any] = ["netKey": net, "appKey": app, "appKeyIndex": 1,
            "nodes": [["netKeys": [["index": 1]], "appKeys": [["index": 1]]]]]
        precondition(P.issue(in: valid) == nil)
        let pair = try P.pair(valid).get()
        precondition((try? P.additions(for: pair, networks: [], applications: []).get()) == .init(network: true, application: true))
        precondition((try? P.additions(for: pair, networks: [net], applications: []).get()) == .init(network: false, application: true))
        precondition((try? P.additions(for: pair, networks: [net], applications: [app]).get()) == .init(network: false, application: false))
        for (field, expected) in [("netKey", P.Issue.missingNetKey), ("appKey", .missingAppKey)] {
            var missing = valid; missing.removeValue(forKey: field)
            precondition(P.issue(in: missing) == expected && P.fingerprint(missing) == nil)
        }
        var otherNet = net; otherNet["key"] = String(repeating: "33", count: 16)
        if case .failure(.netKeyIndexConflict) = P.additions(for: pair, networks: [otherNet], applications: [app]) {} else { fatalError("same index must not reuse another Space's key") }
        var otherApp = app; otherApp["key"] = String(repeating: "44", count: 16)
        if case .failure(.appKeyIndexConflict) = P.additions(for: pair, networks: [net], applications: [otherApp]) {} else { fatalError("AppKey collision") }
        if case .failure(.ambiguousKeys) = P.additions(for: pair, networks: [net, net], applications: [app]) {} else { fatalError("duplicate slots") }
        var aliasedNet = net; aliasedNet["index"] = 2
        if case .failure(.networkIdentityMismatch) = P.additions(for: pair, networks: [aliasedNet], applications: []) {} else { fatalError("do not duplicate Network ID in another slot") }
        var secondApp = app; secondApp["index"] = 2
        if case .failure(.ambiguousKeys) = P.additions(for: pair, networks: [net], applications: [secondApp]) {} else { fatalError("do not add an ambiguous application key") }
        for invalid in [true as Any, -1, 4096, "1", 1.5] {
            var badNet = net; badNet["index"] = invalid
            var bad = valid; bad["netKey"] = badNet
            precondition(P.issue(in: bad) == .invalidNetKey)
        }
        var badApp = app; badApp["boundNetKey"] = 2
        var bad = valid; bad["appKey"] = badApp
        precondition(P.issue(in: bad) == .invalidBinding)
        bad = valid; bad["appKeyIndex"] = 2
        precondition(P.issue(in: bad) == .invalidAppKeyIndex)
        bad = valid; bad["nodes"] = [["netKeys": [["index": 2]]]]
        precondition(P.issue(in: bad) == .invalidNodeKeyReference)
        var refreshed = otherNet; refreshed["phase"] = 1; refreshed["oldKey"] = net["key"]
        var refreshPayload = valid; refreshPayload["netKey"] = refreshed
        let refreshPair = try P.pair(refreshPayload).get()
        if case .failure(.keyRefreshNeedsReview) = P.additions(for: refreshPair, networks: [net], applications: [app]) {} else { fatalError("refresh must not silently overwrite") }
        precondition((try? P.additions(for: refreshPair, networks: [refreshed], applications: [app]).get()) == .init(network: false, application: false))
        var renamedNet = net; renamedNet["name"] = "Another display name"
        var renamed = valid; renamed["netKey"] = renamedNet
        precondition(P.fingerprint(renamed) == P.fingerprint(valid))
        var changed = valid; changed["appKey"] = otherApp
        precondition(P.fingerprint(changed) != P.fingerprint(valid))
        // Site upload must inspect every nested Space, not just root keys.
        let spaces = [valid, ["groups": []]]
        precondition(!spaces.allSatisfy { P.issue(in: $0) == nil })
        print("PASS: key presence, index collisions, missing AppKey repair, binding, refresh and private receipts")
    }
}
