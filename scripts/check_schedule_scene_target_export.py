#!/usr/bin/env python3
"""Execute Schedule's production Codable encoder with no active scene lookup."""

from pathlib import Path
import subprocess
import tempfile
import sys

root = Path(__file__).resolve().parents[1]
schedule = (root / "SunSmart/Main/Timed/Model/Scheduler.swift").read_text()
start = schedule.index("    public func encode(to encoder: Encoder) throws {")
end = schedule.index("\n    }", start) + len("\n    }")
encoder = schedule[start:end]
start = schedule.index("    public required init(from decoder: Decoder) throws {")
end = schedule.index("\n    }", start) + len("\n    }")
decoder = schedule[start:end]

profile_start = schedule.index("    struct ScheduleProfile:")
profile_end = schedule.index("\n    }", profile_start) + len("\n    }")
profile = schedule[profile_start:profile_end]

fixture = """
import Foundation

typealias Address = UInt16
typealias SceneNumber = UInt16
extension UInt16 {
    var isGroup: Bool { self >= 0xC000 && self < 0xFF00 }
    var isVirtual: Bool { self >= 0x8000 && self < 0xC000 }
    var isSpecialGroup: Bool { self >= 0xFF00 }
    var hex: String { String(format: "%04X", self) }
    init?(hex: String) { self.init(hex, radix: 16) }
}
struct Scene { let number: SceneNumber }

final class Schedule: Codable {
    init() {}
PROFILE_CODEC
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
    var sceneNumber: SceneNumber?
    var profiles: [ScheduleProfile] = []
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
        schedule.sceneNumber = 6
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
        var profileRow = payload
        profileRow["selectTarget"] = 3
        profileRow["sceneAddress"] = ""
        profileRow["profiles"] = [["groupAddress": "C000", "profileSceneNumber": "FF00", "groupName": "Group 1", "type": 3]]
        var remote: [String: Any] = ["nodes": [], "schedules": [profileRow], "spaceData": ["timedSchemaVersion": 1]]
        let baseline = TimedSchedulerPayloadPolicy.canonical(remote)!
        let profileSchedule = try JSONDecoder().decode(Schedule.self, from: JSONSerialization.data(withJSONObject: profileRow))
        precondition(profileSchedule.sceneNumber == nil && profileSchedule.profiles.count == 1)
        remote["schedules"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode([profileSchedule]))
        precondition(TimedSchedulerPayloadPolicy.canonical(remote) == baseline, "Profile metadata survives production Codable")
        profileRow["profiles"] = [["groupAddress": "C000", "profileSceneNumber": "FF00"]]
        let oldProfile = try JSONDecoder().decode(Schedule.self, from: JSONSerialization.data(withJSONObject: profileRow))
        precondition(oldProfile.profiles.first?.groupName == nil && oldProfile.profiles.first?.type == nil)
        let oldProfileData = try JSONSerialization.jsonObject(with: JSONEncoder().encode(oldProfile)) as! [String: Any]
        var oldEnvelope: [String: Any] = ["nodes": [], "schedules": [oldProfileData], "spaceData": ["timedSchemaVersion": 1]]
        let oldCanonical = TimedSchedulerPayloadPolicy.canonical(oldEnvelope)!
        profileRow["profiles"] = [["groupAddress": "C000", "profileSceneNumber": "FF00", "groupName": NSNull(), "type": NSNull()]]
        oldEnvelope["schedules"] = [profileRow]
        precondition(TimedSchedulerPayloadPolicy.canonical(oldEnvelope) == oldCanonical)
        let nullProfile = try JSONDecoder().decode(Schedule.self, from: JSONSerialization.data(withJSONObject: profileRow))
        oldEnvelope["schedules"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode([nullProfile]))
        precondition(TimedSchedulerPayloadPolicy.canonical(oldEnvelope) == oldCanonical)
        profileRow["profiles"] = [["groupAddress": "C000", "profileSceneNumber": "FF00", "type": 3]]
        oldEnvelope["schedules"] = [profileRow]
        precondition(TimedSchedulerPayloadPolicy.canonical(oldEnvelope) != oldCanonical)
        if CommandLine.arguments.count == 2 {
            let document = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))) as! [String: Any]
            let input = document["data"] as! [String: Any]
            let inputSchedules = try JSONDecoder().decode([Schedule].self, from: JSONSerialization.data(withJSONObject: input["schedules"]!))
            var result = input
            result["schedules"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(inputSchedules))
            let expected = TimedSchedulerPayloadPolicy.canonical(input)
            precondition(expected != nil && expected == TimedSchedulerPayloadPolicy.canonical(result))
            print("PASS: private server sample production Codable and canonical round trip; schedules=", inputSchedules.count)
        }
        print("PASS: production Schedule Codable preserves scene targets, logical IDs, slots and pending cleanup; corrupt arrays reject")
    }
}
""".replace("PROFILE_CODEC", profile).replace("ENCODER", encoder).replace("DECODER", decoder)

with tempfile.TemporaryDirectory(prefix="schedule-target-export-") as directory:
    source = Path(directory) / "ScheduleEncoder.swift"
    binary = Path(directory) / "ScheduleEncoderTests"
    source.write_text(fixture)
    subprocess.run(["swiftc", "-parse-as-library",
                    str(root / "SunSmart/Main/Timed/Model/TimedSchedulerSlotPolicy.swift"),
                    str(source), "-o", str(binary)], check=True)
    subprocess.run([str(binary), *sys.argv[1:]], check=True)
