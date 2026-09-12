import Foundation

@main
struct DebugCloudJSONFileTests {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let date = Date(timeIntervalSince1970: 0)
        let fileName = DebugCloudJSONFile.fileName(scope: "Site", name: "Office", date: date, timeZone: TimeZone(secondsFromGMT: 28800)!)
        precondition(fileName == "Site_Office_19700101_080000_000+0800.json")
        for name in ["", " \n ", "../a/b\\c\n", String(repeating: "灯光😀", count: 200)] {
            let result = DebugCloudJSONFile.fileName(scope: "Space", name: name, date: date)
            precondition(result.hasPrefix("Space_") && result.hasSuffix(".json"))
            precondition(!result.contains("/") && !result.contains("\\") && !result.contains("\n"))
            precondition(result.utf8.count < 255)
        }
        let payload: [String: Any] = ["siteId": "fixture", "spaces": [[
            "uuid": "a", "spaceName": "灯光😀", "updateTimestamp": Int64(9_007_199_254_740_991),
            "nodes": [["uuid": "b", "value": true], ["uuid": "a", "value": false]],
            "groups": [], "null": NSNull(), "real": 1.25
        ]], "userId": "fixture-user"]
        let first = try DebugCloudJSONFile.write(payload: payload, scope: "Space", name: "A", date: date, directory: directory)
        let second = try DebugCloudJSONFile.write(payload: payload, scope: "Space", name: "A", date: date, directory: directory)
        precondition(first != second && first.lastPathComponent == second.lastPathComponent)
        let raw = try Data(contentsOf: first)
        let decoded = try JSONSerialization.jsonObject(with: raw) as! NSDictionary
        precondition(decoded.isEqual(to: payload))
        precondition(String(decoding: raw, as: UTF8.self).contains("\n"))
        var invalid = payload; invalid["invalid"] = Double.nan
        do {
            _ = try DebugCloudJSONFile.write(payload: invalid, scope: "Site", name: "A", date: date, directory: directory)
            preconditionFailure("Invalid JSON accepted")
        } catch {}
        let blocker = directory.appendingPathComponent("blocker")
        try Data().write(to: blocker)
        do {
            _ = try DebugCloudJSONFile.write(payload: payload, scope: "Site", name: "A", date: date, directory: blocker)
            preconditionFailure("Writing below a regular file succeeded")
        } catch {}
        DebugCloudJSONFile.cleanExpired(now: Date().addingTimeInterval(2 * 86400), directory: directory)
        precondition(!FileManager.default.fileExists(atPath: first.path))
        precondition(FileManager.default.fileExists(atPath: blocker.path))
        let owned = try DebugCloudJSONFile.write(payload: payload, scope: "Site", name: "A", date: date)
        DebugCloudJSONFile.remove(owned)
        precondition(!FileManager.default.fileExists(atPath: owned.path))
        DebugCloudJSONFile.remove(blocker)
        precondition(FileManager.default.fileExists(atPath: blocker.path))
        print("PASS: JSON semantic round-trip, naming, Unicode, isolation, write failures and scoped cleanup")
    }
}
