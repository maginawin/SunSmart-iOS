import Foundation

// Only Node/Element identity and the database transport are test boundaries.
// The snapshot adapter, SDK wire codec and SDK property save/load blocks are
// compiled from production sources by check_scheduler_cloud_roundtrip.py.
public typealias SceneNumber = UInt16
extension UInt16 {
    static let schedulerSetupServerModelId: UInt16 = 0x1207
    var hex: String { String(format: "%04X", self) }
}
final class Model: Hashable {
    weak var parentElement: Element?
    static func == (lhs: Model, rhs: Model) -> Bool { lhs === rhs }
    func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}
final class Element {
    let unicastAddress: UInt16
    let model = Model()
    init(_ address: UInt16) { unicastAddress = address; model.parentElement = self }
    func model(withSigModelId: UInt16) -> Model? { withSigModelId == 0x1207 ? model : nil }
}
final class Node {
    let uuid: UUID
    let primaryUnicastAddress: UInt16
    let elements: [Element]
    var schedulerSetupModels: [Model] { elements.map(\.model) }
    var allSchedulerModelEntrys: [Model: [Int: SchedulerRegistryEntry]] = [:]
    var schedulerActions: [Int: SchedulerRegistryEntry] = [:]
    var scheduleIds: [Int] = []
    var corruptedSchedulerModelActionsData: Data?
    var schedulerModelCacheDecodeError: String?
    init(_ data: [String: Any]) {
        uuid = UUID(uuidString: data["uuid"] as! String)!
        let address = UInt16(data["unicastAddress"] as! String, radix: 16)!
        primaryUnicastAddress = address
        elements = (data["elements"] as! [[String: Any]]).map {
            Element(address + UInt16($0["index"] as! Int))
        }
    }
    func element(withAddress address: UInt16) -> Element? { elements.first { $0.unicastAddress == address } }
    // SDK_PERSISTENCE_METHODS
}

@main struct SchedulerModelSnapshotTests {
    static func legacy(_ index: Int, _ e: SchedulerRegistryEntry) -> [String: Any] {
        ["id": index, "year": e.year.value, "month": e.month.value, "day": e.day.value,
         "hour": e.hour.value, "minute": e.minute.value, "second": e.second.value,
         "dayOfWeek": e.dayOfWeek.value, "action": e.action.rawValue,
         "transitionTime": Int(e.transitionTime.interval ?? 0), "sceneNumber": e.sceneNumber]
    }
    static func entry(_ index: Int, variant: Bool = false) -> SchedulerRegistryEntry {
        .init(year: .init(value: 0x64), month: .init(value: 0x0811), day: .init(value: 0),
              hour: .init(value: 0x19), minute: .init(value: 0x3F), second: .init(value: 0x3E),
              dayOfWeek: .init(value: 0x55), action: variant ? .sceneRecall : .turnOn,
              transitionTime: .init(rawValue: [0x07, 0xC7, 0x88, 0xFF][index % 4]),
              sceneNumber: variant ? 42 : 6)
    }
    static func fixture(_ index: Int) throws -> [String: Any] {
        let address = UInt16(10 + index * 2)
        var json: [String: Any] = [
            "uuid": String(format: "00000000-0000-0000-0000-%012d", index + 1),
            "unicastAddress": address.hex, "deviceKey": String(repeating: "A1", count: 16),
            "netKeys": [], "appKeys": [], "versionSEQ": 0, "scenesDatas": [], "lightLCPropertys": [:],
            "elements": (0..<2).map { ["index": $0, "location": "0001", "models": [["modelId": "1207", "bind": [6], "subscribe": []]]] }
        ]
        let node = Node(json)
        node.schedulerActions = index < 2 ? [:] : [0: entry(0), 1: entry(1)]
        node.allSchedulerModelEntrys[node.schedulerSetupModels[0]] = node.schedulerActions
        node.allSchedulerModelEntrys[node.schedulerSetupModels[1]] = index < 30 ? [:] : [0: entry(0, variant: true), 1: entry(1)]
        json["schedules"] = node.schedulerActions.map { legacy($0.key, $0.value) }
        json["custProps"] = ["schedulerModelStates": try node.schedulerModelSnapshot(nodeData: json)!.dictionary()]
        return json
    }

    static func main() throws {
        if CommandLine.arguments[1] == "export" {
            let fixture = try (0..<70).map(Self.fixture)
            try JSONSerialization.data(withJSONObject: ["nodes": fixture]).write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
            return
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
        let payload = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let nodes = payload["nodes"] as! [[String: Any]]
        let original = try (0..<70).map(Self.fixture)
        precondition(SchedulerModelSnapshot.spaceData(payload) == SchedulerModelSnapshot.spaceData(["nodes": original]))
        var knownEmpty = 0, populated = 0
        for json in nodes {
            let visitor = Node(json)
            precondition(visitor.restoreSchedulerModelSnapshot(nodeData: json))
            let persisted = visitor.saveSnapshotProperty()
            let reloaded = Node(json)
            reloaded.loadSnapshotProperty(persisted)
            // Legacy bytes are a separate SDK column; retain the actual wire bytes.
            for bytes in try SchedulerModelSnapshot.entries(try SchedulerModelSnapshot.decode(node: json)!.legacyEntriesData) {
                let entry = SchedulerRegistryEntry.unmarshal(bytes)
                reloaded.schedulerActions[Int(entry.index)] = entry.entry
            }
            precondition(reloaded.matchesSchedulerModelSnapshot(nodeData: json))
            precondition(Set(visitor.allSchedulerModelEntrys.keys).isDisjoint(with: reloaded.allSchedulerModelEntrys.keys))
            knownEmpty += reloaded.allSchedulerModelEntrys.values.filter(\.isEmpty).count
            populated += reloaded.allSchedulerModelEntrys.values.filter { !$0.isEmpty }.count
        }
        precondition(knownEmpty == 32 && populated == 108)

        var json = original[2]
        let node = Node(json)
        node.schedulerActions = Dictionary(uniqueKeysWithValues: (0..<16).map { ($0, entry($0)) })
        node.allSchedulerModelEntrys[node.schedulerSetupModels[0]] = node.schedulerActions
        node.allSchedulerModelEntrys[node.schedulerSetupModels[1]] = Dictionary(uniqueKeysWithValues: (0..<16).map { ($0, entry($0, variant: true)) })
        json["schedules"] = node.schedulerActions.map { legacy($0.key, $0.value) }
        let snapshot = try node.schedulerModelSnapshot(nodeData: json)!
        json["custProps"] = ["schedulerModelStates": try snapshot.dictionary()]
        let imported = Node(json)
        precondition(imported.restoreSchedulerModelSnapshot(nodeData: json))
        precondition(imported.allSchedulerModelEntrys.values.allSatisfy { $0.count == 16 })
        precondition(imported.schedulerActions[0]!.month.value == 0x0811)
        precondition(imported.schedulerActions[0]!.transitionTime.rawValue == 0x07)
        precondition(imported.matchesSchedulerModelSnapshot(nodeData: json))
        let baseline = SchedulerModelSnapshot.spaceData(["nodes": [json]])!
        precondition(SchedulerModelSnapshot.remoteChanged(baseline, since: nil))
        precondition(!SchedulerModelSnapshot.remoteChanged(baseline, since: baseline))
        // Local live observations changing must not make the same cloud value new.
        imported.allSchedulerModelEntrys = [:]
        precondition(!SchedulerModelSnapshot.remoteChanged(baseline, since: baseline))
        var reversed = try snapshot.dictionary()
        reversed["models"] = snapshot.models.reversed().map { model -> [String: Any] in
            let bytes = try! SchedulerModelSnapshot.entries(model.entriesData).reversed().reduce(into: Data()) { $0.append($1) }
            return ["elementAddress": model.elementAddress.lowercased(), "modelId": "1207", "entriesData": bytes.base64EncodedString()]
        }
        var reordered = json
        reordered["custProps"] = ["schedulerModelStates": reversed]
        precondition(SchedulerModelSnapshot.spaceData(["nodes": [reordered]]) == baseline)

        var legacyPayload = json
        legacyPayload.removeValue(forKey: "custProps")
        let unknown = Node(legacyPayload)
        precondition(unknown.restoreSchedulerModelSnapshot(nodeData: legacyPayload) && unknown.allSchedulerModelEntrys.isEmpty)
        precondition(SchedulerModelSnapshot.spaceData(["nodes": [legacyPayload]]) == Data("[]".utf8))
        for properties in [NSNull(), ["unrelated": [1, 2]], [1, 2], [String: Any]()] as [Any] {
            legacyPayload["custProps"] = properties
            let decoded = try SchedulerModelSnapshot.decode(node: legacyPayload)
            precondition(decoded == nil)
            precondition(SchedulerModelSnapshot.spaceData(["nodes": [legacyPayload]]) == Data("[]".utf8))
        }
        var partial = try snapshot.dictionary()
        partial["models"] = [["elementAddress": node.primaryUnicastAddress.hex, "modelId": "1207", "entriesData": ""]]
        var partiallyKnown = json
        partiallyKnown["custProps"] = ["schedulerModelStates": partial]
        let partialNode = Node(partiallyKnown)
        precondition(partialNode.restoreSchedulerModelSnapshot(nodeData: partiallyKnown))
        precondition(partialNode.allSchedulerModelEntrys.count == 1)
        precondition(partialNode.allSchedulerModelEntrys[partialNode.schedulerSetupModels[0]]?.isEmpty == true)
        precondition(partialNode.allSchedulerModelEntrys[partialNode.schedulerSetupModels[1]] == nil)

        let preserved = Node(json)
        precondition(preserved.restoreSchedulerModelSnapshot(nodeData: json))
        let preservedSnapshot = try preserved.schedulerModelSnapshot(nodeData: json)
        let preservedIDs = preserved.scheduleIds
        for raw in ["null", "\"invalid\"", "0", "1.5", "true", "[]", "[{}]", "{}", "{\"schemaVersion\":1}"] {
            var bad = json
            // Parse a cloud-shaped envelope so null/numbers use Foundation's real JSON types.
            bad["custProps"] = try JSONSerialization.jsonObject(with: Data("{\"schedulerModelStates\":\(raw)}".utf8))
            do {
                _ = try SchedulerModelSnapshot.decode(node: bad)
                preconditionFailure("Declared invalid snapshot must throw: \(raw)")
            } catch {}
            precondition(SchedulerModelSnapshot.spaceData(["nodes": [bad]]) == nil)
            precondition(!preserved.restoreSchedulerModelSnapshot(nodeData: bad))
            precondition(!preserved.matchesSchedulerModelSnapshot(nodeData: bad))
            let after = try preserved.schedulerModelSnapshot(nodeData: json)
            precondition(after == preservedSnapshot && preserved.scheduleIds == preservedIDs,
                         "Rejected snapshot must preserve existing Model and legacy schedules")
        }

        func rejects(_ change: (inout [String: Any]) -> Void) throws {
            var invalid = try snapshot.dictionary()
            change(&invalid)
            var bad = json
            bad["custProps"] = ["schedulerModelStates": invalid]
            precondition(SchedulerModelSnapshot.spaceData(["nodes": [bad]]) == nil)
            precondition(!Node(bad).restoreSchedulerModelSnapshot(nodeData: bad))
        }
        try rejects { $0["schemaVersion"] = 2 }
        try rejects { $0["nodeUUID"] = UUID().uuidString }
        try rejects { $0["deviceKeyFingerprint"] = "different" }
        try rejects { $0["unicastAddress"] = "7000" }
        try rejects { $0["models"] = (partial["models"] as! [[String: Any]]) + (partial["models"] as! [[String: Any]]) }
        for (address, bytes) in [("7000", Data()), (node.primaryUnicastAddress.hex, Data([1])),
                                 (node.primaryUnicastAddress.hex, Data([0,0,0,0,0,0,0x30,0,0,0])),
                                 (node.primaryUnicastAddress.hex, Data(repeating: 0, count: 20))] {
            try rejects { $0["models"] = [["elementAddress": address, "modelId": "1207", "entriesData": bytes.base64EncodedString()]] }
        }
        try rejects { $0["legacyEntriesData"] = "" }
        node.corruptedSchedulerModelActionsData = Data([1])
        precondition((try? node.schedulerModelSnapshot(nodeData: json)) == nil)
        print("PASS: 70 nodes / 140 Model containers round-trip; SDK reload preserves 32 empty + 108 populated containers")
        print("PASS: all 16 slots, independent Models, raw month/time, legacy/partial unknown, canonical order, identity/topology/malformed rejection")
        print("PASS: invalid snapshot root types and incomplete objects reject without changing existing schedules; missing legacy fields remain compatible")
    }
}
