#!/usr/bin/env python3
"""Execute Schedule's production Codable encoder with no active scene lookup."""

from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
schedule = (root / "SunSmart/Main/Timed/Model/Scheduler.swift").read_text()
start = schedule.index("    public func encode(to encoder: Encoder) throws {")
end = schedule.index("\n    }", start) + len("\n    }")
encoder = schedule[start:end]
start = schedule.index("    public required init(from decoder: Decoder) throws {")
end = schedule.index("\n    }", start) + len("\n    }")
decoder = schedule[start:end]

fixture = """
import Foundation

typealias Address = UInt16
typealias SceneNumber = UInt16
extension UInt16 {
    var hex: String { String(format: "%04X", self) }
    init?(hex: String) { self.init(hex, radix: 16) }
}
struct Scene { let number: SceneNumber }

final class Schedule: Codable {
    init() {}
    typealias ScheduleProfile = Int
    enum TargetType: Int { case groups = 0, devices, scene, profile }
    enum Action: UInt8 { case off = 0, on = 1, scene = 2, noAction = 15 }
    enum CodingKeys: String, CodingKey {
        case id, name, enabled, action, fadeTime, hour, minute, profiles, groupAddresses
        case target = "selectTarget", dayOfWeek, nodeAddresses = "deviceAddresses"
        case sceneNumber = "sceneAddress"
        case nodeSlots, needDeleteNodeAddresses, needDeleteGroupAddresses, needDeleteSceneNumbers
    }
    var id = 0
    var name = "Lunch"
    var enabled = true
    var selectTargetType = TargetType.scene
    var action = Action.off
    var fadeTime = 10
    var hour = 12
    var minute = 30
    var weekDays: [Int] = []
    var nodeAddresses: [Address] = []
    var groupAddresses: [Address] = []
    var sceneNumber: SceneNumber? = .init(hex: "0006")
    var profiles: [Int] = []
    var nodeSlots: [TimedSchedulerNodeSlot]?
    var nodeSlotsLoadFailed = false
    var needDeleteNodeAddresses: [Address] = []
    var needDeleteGroupAddresses: [Address] = []
    var needDeleteSceneNumbers: [SceneNumber] = []
    // Simulates exporting another Space while its scenes are not globally active.
    var scene: Scene? { nil }
    static func getWeekValue(weekDays: [Int]) -> Int { weekDays.reduce(0, |) }
    static func getWeekDays(weekValue: Int) -> [Int] { (0..<7).map { 1 << $0 }.filter { weekValue & $0 != 0 } }

ENCODER
DECODER
}

@main struct Run {
    static func main() throws {
        let schedule = Schedule()
        let encoded = try JSONEncoder().encode(schedule)
        let payload = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        precondition(payload["sceneAddress"] as? String == "0006",
                     "A stored scene must survive export without an active scene lookup")
        schedule.sceneNumber = nil
        let missing = try JSONEncoder().encode(schedule)
        let missingPayload = try JSONSerialization.jsonObject(with: missing) as! [String: Any]
        precondition(missingPayload["sceneAddress"] is NSNull,
                     "Missing legacy scene targets remain explicit for upload validation")
        schedule.nodeSlots = [.init(identity: .init(
            nodeUUID: "11111111-1111-1111-1111-111111111111", unicastAddress: "0001",
            deviceKeyFingerprint: String(repeating: "a", count: 64)), slot: 7, state: .pendingRemoval)]
        schedule.needDeleteNodeAddresses = [1]
        let reserved = try JSONSerialization.jsonObject(with: JSONEncoder().encode(schedule)) as! [String: Any]
        guard (reserved["nodeSlots"] as? [[String: Any]])?.first?["slot"] as? Int == 7,
              reserved["needDeleteNodeAddresses"] as? [String] == ["0001"] else {
            print("FAIL: cloud export must preserve a pending slot reservation")
            exit(1)
        }
        schedule.id = 300
        schedule.weekDays = [1, 8, 32]
        schedule.needDeleteGroupAddresses = [0xC001]
        schedule.needDeleteSceneNumbers = [6]
        let exported = try JSONEncoder().encode(schedule)
        let imported = try JSONDecoder().decode(Schedule.self, from: exported)
        precondition(imported.id == 300 && imported.nodeSlots == schedule.nodeSlots)
        precondition(imported.weekDays == schedule.weekDays && imported.needDeleteNodeAddresses == [1])
        precondition(imported.needDeleteGroupAddresses == [0xC001] && imported.needDeleteSceneNumbers == [6])
        var legacy = payload
        legacy["sceneAddress"] = 6
        let old = try JSONDecoder().decode(Schedule.self, from: JSONSerialization.data(withJSONObject: legacy))
        precondition(old.nodeSlots == nil && old.id == 0 && old.sceneNumber == 6)
        var corrupt = try JSONSerialization.jsonObject(with: exported) as! [String: Any]
        corrupt["nodeSlots"] = NSNull()
        do {
            _ = try JSONDecoder().decode([Schedule].self, from: JSONSerialization.data(withJSONObject: [payload, corrupt]))
            preconditionFailure("one corrupt record must reject the entire decoded schedule array")
        } catch {}
        print("PASS: production Schedule Codable preserves scene targets, logical IDs, slots and pending cleanup; corrupt arrays reject")
    }
}
""".replace("ENCODER", encoder).replace("DECODER", decoder)

with tempfile.TemporaryDirectory(prefix="schedule-target-export-") as directory:
    source = Path(directory) / "ScheduleEncoder.swift"
    binary = Path(directory) / "ScheduleEncoderTests"
    source.write_text(fixture)
    subprocess.run(["swiftc", "-parse-as-library",
                    str(root / "SunSmart/Main/Timed/Model/TimedSchedulerSlotPolicy.swift"),
                    str(source), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
