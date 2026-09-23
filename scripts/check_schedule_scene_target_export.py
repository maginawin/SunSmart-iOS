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

fixture = """
import Foundation

struct Address { let hex: String }
struct SceneNumber { let hex: String }
struct Scene { let number: SceneNumber }

final class Schedule: Encodable {
    enum TargetType: Int { case groups = 0, devices, scene, profile }
    enum Action: Int { case off = 0 }
    enum CodingKeys: String, CodingKey {
        case id, name, enabled, action, fadeTime, hour, minute, profiles, groupAddresses
        case target = "selectTarget", dayOfWeek, nodeAddresses = "deviceAddresses"
        case sceneNumber = "sceneAddress"
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
    // Simulates exporting another Space while its scenes are not globally active.
    var scene: Scene? { nil }
    static func getWeekValue(weekDays: [Int]) -> Int { 127 }

ENCODER
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
        print("PASS: Schedule Codable preserves stored scene target outside the active Space")
    }
}
""".replace("ENCODER", encoder)

with tempfile.TemporaryDirectory(prefix="schedule-target-export-") as directory:
    source = Path(directory) / "ScheduleEncoder.swift"
    binary = Path(directory) / "ScheduleEncoderTests"
    source.write_text(fixture)
    subprocess.run(["swiftc", "-parse-as-library", str(source), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
