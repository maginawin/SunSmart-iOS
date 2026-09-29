import Foundation

let jsonDecoder = JSONDecoder()
extension String { var localizedString: String { self } }

// Only optional identifier decoding comes from the production SDK. Other Node
// fields and persistence are explicit boundaries, not a full Mesh importer.
final class Node: Decodable {
    var companyIdentifier: UInt16?, productIdentifier: UInt16?, versionIdentifier: UInt16?
    var minimumNumberOfReplayProtectionList: UInt16?
    enum CodingKeys: String, CodingKey {
        case companyIdentifier = "cid", productIdentifier = "pid", versionIdentifier = "vid"
        case minimumNumberOfReplayProtectionList = "crpl"
    }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // SDK_OPTIONAL_FIELDS
    }
    func restoreSchedulerModelSnapshot(nodeData: [String: Any]) -> Bool {
        nodeData["testSchedulerValid"] as? Bool != false
    }
}
enum Outcome: Equatable { case applied, rejected(String) }
struct Cleanup { var didChange: Bool }
enum SpaceConfigurationSafety {
    static var preserves = true, stages = true
    static var stageCount = 0
    static func preserveRemoteReferenceCleanup(_ space: ImportHarness, payload: [String: Any], candidate: [String: Any]) -> Bool { preserves }
    static func beginImport(_ space: ImportHarness, payload: [String: Any]) -> Bool { stageCount += 1; return stages }
}
final class ImportHarness {
    let id = "fixture-space"
    func stage(_ nodeDicts: [[String: Any]], groups: [Int] = [1], groupDicts: [Int] = [1],
               referenceCleanup: Cleanup? = nil) async -> Outcome {
        let originalSpaceJsonData: [String: Any] = ["nodes": nodeDicts]
        let spaceJsonData = originalSpaceJsonData
        return await withCheckedContinuation { continuation in
            // IMPORT_STAGING_GATE
            continuation.resume(returning: .applied)
        }
    }
}
enum RecoveryMessage {
    // RECOVERY_MESSAGE
}

@main struct CloudNodeImportTests {
    static func require(_ value: Bool, _ message: String) { precondition(value, message) }
    static func rejected(_ dictionary: [String: Any]) -> Bool { (try? CloudNodeImport.decode(dictionary)) == nil }
    static func main() async throws {
        let original: [String: Any] = ["uuid": "00000000-0000-0000-0000-000000000001", "vid": "",
            "cid": "0A78", "pid": "2503", "crpl": NSNull(), "unicastAddress": "3E27",
            "deviceKey": "synthetic-secret", "elements": [["index": 0, "models": []]], "appKeys": []]
        let raw = try JSONSerialization.data(withJSONObject: original)
        require((try? jsonDecoder.decode(Node.self, from: raw)) == nil, "unadapted SDK must reproduce empty VID failure")
        let decoded = try CloudNodeImport.decode(original)
        require(decoded.versionIdentifier == nil && decoded.productIdentifier == 0x2503, "unknown VID retains known product")
        let prepared = CloudNodeImport.decodingDictionary(original)
        require(prepared["vid"] == nil && original["vid"] as? String == "", "only the decoding copy is normalized")
        require(prepared["UUID"] as? String == original["uuid"] as? String, "UUID alias preserved")
        require(prepared["deviceKey"] as? String == "synthetic-secret", "identity key unchanged")
        require((prepared["elements"] as? [[String: Any]])?.count == 1, "placeholder element retained")
        for value: Any? in [nil, NSNull(), "", "0003"] {
            var payload = original; payload["vid"] = value
            require(!rejected(payload), "valid optional VID forms remain importable")
        }
        for value: Any in ["ZZZZ", "003", "  ", 3, false] {
            var payload = original; payload["vid"] = value
            require(rejected(payload), "nonempty malformed VID is not repaired")
        }
        for key in ["cid", "pid", "crpl"] {
            var payload = original; payload[key] = ""
            require(rejected(payload), "unrelated optional fields keep their SDK contract")
        }
        let harness = ImportHarness()
        let accepted = await harness.stage([original])
        require(accepted == .applied && SpaceConfigurationSafety.stageCount == 1, "empty VID reaches staging without dropping the node")
        SpaceConfigurationSafety.stageCount = 0
        var corrupt = original; corrupt["vid"] = "ZZZZ"
        let invalidNode = await harness.stage([original, corrupt])
        require(invalidNode == .rejected("configurationNodeDecodeFailed") && SpaceConfigurationSafety.stageCount == 0,
            "decode failure neither stages nor replaces configuration")
        let invalidGroups = await harness.stage([original], groups: [])
        require(invalidGroups == .rejected("configurationGroupDecodeFailed"), "group decode classified separately")
        var scheduler = original; scheduler["testSchedulerValid"] = false
        let invalidScheduler = await harness.stage([scheduler])
        require(invalidScheduler == .rejected("configurationSchedulerRestoreFailed"), "scheduler restore classified separately")
        SpaceConfigurationSafety.preserves = false
        let cleanup = await harness.stage([original], referenceCleanup: .init(didChange: true))
        require(cleanup == .rejected("configurationReferenceStagingFailed") && SpaceConfigurationSafety.stageCount == 0,
            "failed evidence save stops staging")
        SpaceConfigurationSafety.preserves = true; SpaceConfigurationSafety.stages = false
        let storage = await harness.stage([original])
        require(storage == .rejected("configurationStagingFailed"), "actual staging failure remains storage failure")
        SpaceConfigurationSafety.stages = true
        let retried = await harness.stage([original])
        require(retried == .applied, "unchanged original payload can retry after storage recovery")
        for reason in ["configurationNodeDecodeFailed", "configurationGroupDecodeFailed", "configurationSchedulerRestoreFailed"] {
            require(RecoveryMessage.message(reason) == "space_recovery_data_failed", "decode errors cannot become disk failures")
        }
        require(RecoveryMessage.message("configurationPersistenceFailed") == "space_recovery_storage_failed", "database message retained")
        require(RecoveryMessage.message("configurationFinalizationFailed") == "space_recovery_finalize_failed", "post-commit failure does not claim old data is active")
        if CommandLine.arguments.count > 1 {
            let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
            let response = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            let payload = response["data"] as! [String: Any]
            let nodes = payload["nodes"] as! [[String: Any]]
            let decodedNodes = try nodes.map(CloudNodeImport.decode)
            require(decodedNodes.count == nodes.count, "snapshot retains every node at the SDK identifier boundary")
            let staged = await harness.stage(nodes)
            require(staged == .applied, "snapshot passes production node staging gate with explicit storage doubles")
            print("Private snapshot optional-field/staging probe passed: nodes=\(nodes.count)")
        }
        print("Cloud Node import compatibility, error classification and retry tests passed")
    }
}
