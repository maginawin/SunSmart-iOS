import Foundation
import SQLite

// Environment seams only; the test runner extracts the real Profile, GroupInfo,
// database extension and cloud field mappings. Mesh transport/UI are not run.
protocol Copyable { func copy() -> Self }
typealias Address = UInt16
typealias SceneNumber = UInt16
extension UInt16 {
    static let generalLightControlScene: UInt16 = 0xFF00
    static let minLightControlScene: UInt16 = 0xFF00
    static let maxLightControlScene: UInt16 = 0xFFEF
    var hex: String { String(format: "%04X", self) }
    init?(hex: String) { self.init(hex, radix: 16) }
}
extension String { var localizedString: String { self } }
extension Data { var hex: String { map { String(format: "%02X", $0) }.joined() } }
struct SceneExecuteData: Codable {}
struct GroupProximityLightingPathData: Codable { var paths: [String] = [] }
class Schedule {}
class DeviceSwitchData { var bindGroupAddresses: [Address] = []; var unbindGroupAddresses: [Address] = [] }
class Node {
    var primaryUnicastAddress: Address = 1
    var sensorCalibrated = false
    func contains(elementWithAddress address: Address) -> Bool { address == primaryUnicastAddress }
}
struct HarnessNetwork { let uuid = UUID() }
struct HarnessKey { let networkId = Data([1]) }
class MeshNetworkManager {
    static let instance = MeshNetworkManager()
    var meshNetwork: HarnessNetwork? = HarnessNetwork()
    var currentNetworkKey = HarnessKey()
    var realNodes: [Node] = []
    var switchs: [DeviceSwitchData] = []
}
class ProfileLightSensorTemplate {
    static func initDatabase() {}
    static func load(profileId: String) -> [ProfileLightSensorTemplate] { [] }
}
struct HarnessGroup { var info: GroupInfo }
enum SpaceConfigurationSafety {
    enum SafetyError: Error { case persistenceFailed }
}

@main
enum ProfilePersistenceTests {
    static let mesh = "test-mesh"
    static let subnet = "test-subnet"

    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("profiles.sqlite3")
        SunSmartDataManager.shared.db = try Connection(url.path)
        GroupInfo.initDatabase()
        Profile.initDatabase()
        try testDefaultsAndCloudRoundtrip(url)
        let captured = try Connection(url.path, readonly: true)
        SunSmartDataManager.shared.db = try Connection(.inMemory)
        let scoped = GroupInfo.load(meshUUID: mesh, address: 0xC006, subnetworkId: subnet,
                                    database: captured, includeTemplates: false)
        precondition(scoped != nil && scoped?.profileLoadFailed == false)
        precondition(scoped?.profile.type == .proximityLighting)
        SunSmartDataManager.shared.db = try Connection(url.path)
        try testProximityAllImport(url)
        try testLegacySchemaAndReload()
        try testInvalidWritesAndRollback()
        testLevelBoundaries()
        try testSceneValidationAndLegacyAutoMin()
        print("PASS: production Profile + GroupInfo SQLite save/load, defaults, cloud field roundtrip, legacy rows, rollback and level boundaries")
    }

    static func save(_ info: GroupInfo) -> Bool { info.save(meshUUID: mesh, subnetworkId: subnet) }
    static func load(_ address: Address) -> GroupInfo? { GroupInfo.load(meshUUID: mesh, address: address, subnetworkId: subnet) }
    static func db() -> Connection { SunSmartDataManager.shared.db! }
    static func payload(_ info: GroupInfo) -> [String: Any] { exportProfile(HarnessGroup(info: info)) }
    static func count(_ table: String) throws -> Int64 { try db().scalar("SELECT count(*) FROM \(table)") as! Int64 }
    static func check(_ condition: @autoclosure () throws -> Bool) rethrows {
        let passed = try condition()
        precondition(passed)
    }

    static func testDefaultsAndCloudRoundtrip(_ url: URL) throws {
        let defaults = Profile.defaultGroupProfiles()
        precondition(defaults.count == 8 && defaults[0].lightControlData.occupancyLevel == 500)
        for (index, profile) in defaults.enumerated() {
            let info = GroupInfo(address: Address(0xC000 + index), imageId: 3, imageText: "test", profile: profile)
            // Match create-group's copy into a new GroupInfo profile, preserving its ID.
            let created = GroupInfo(address: info.address)
            let id = created.profile.id
            created.profile.updateData(profile: profile)
            created.imageId = info.imageId
            created.imageText = info.imageText
            precondition(created.profile.id == id && save(created))
            // Reopen the SQLite connection, so reload cannot use model references.
            SunSmartDataManager.shared.db = try Connection(url.path)
            let restored = load(info.address)!
            precondition(!restored.profileLoadFailed && restored.profile.id == id)
            precondition(restored.profile == created.profile)
            if let expectedNight = created.profile.nightData {
                precondition(restored.profile.nightData != nil && restored.profile.nightData! == expectedNight)
            } else {
                precondition(restored.profile.nightData == nil)
            }
            precondition(restored.imageId == 3 && restored.imageText == "test")
            let exported = payload(restored)
            precondition(SpaceConfigurationIntegrityPolicy.profileIssue(exported) == nil)
            let wire = try JSONSerialization.data(withJSONObject: exported)
            let decoded = try JSONSerialization.jsonObject(with: wire) as! [String: Any]
            let imported = importProfile(decoded)!
            let remote = GroupInfo(address: Address(0xC100 + index), profile: imported)
            precondition(save(remote))
            let roundtrip = payload(load(remote.address)!)
            precondition(NSDictionary(dictionary: exported).isEqual(to: roundtrip))
            // Default lux survives both database and cloud conversion unchanged.
            precondition(imported.lightControlData == profile.lightControlData)
        }
        print("PASS: eight real defaults and create-style copies -> SQLite reopen -> cloud export/import -> SQLite -> export")
    }

    static func testProximityAllImport(_ url: URL) throws {
        for (index, type) in [Profile.ProfileType.proximityLighting, .proximityLightingWithPhotocell].enumerated() {
            let profile = Profile.defaultGroupProfile(type: type)
            profile.proximityLightingNumber = 255
            profile.lightControlData.t2 = 5
            profile.lightControlData.t4 = 0
            profile.manualOverrideTimeout = 5
            let info = GroupInfo(address: Address(0xC700 + index), profile: profile)
            let canonical = payload(info)
            let allValues: [Any] = Array(21...255).map { $0 as Any }
                + [256, 65535, Int64.max, UInt64.max]
            for value in allValues {
                var cloud = canonical
                cloud["proximityLightingNumber"] = value
                let wire = try JSONSerialization.data(withJSONObject: cloud)
                let decoded = try JSONSerialization.jsonObject(with: wire) as! [String: Any]
                precondition(SpaceConfigurationIntegrityPolicy.profileIssue(decoded) == nil)
                let imported = importProfile(decoded)!
                precondition(imported.proximityLightingNumber == 255)
                info.profile = imported
                precondition(NSDictionary(dictionary: canonical).isEqual(to: payload(info)),
                             "Cloud import must normalize before narrowing while preserving every other Profile field")
            }
            precondition(save(info))
            SunSmartDataManager.shared.db = try Connection(url.path)
            let reloaded = load(info.address)!
            precondition(!reloaded.profileLoadFailed && reloaded.profile.proximityLightingNumber == 255)
            precondition(NSDictionary(dictionary: canonical).isEqual(to: payload(reloaded)),
                         "Import, SQLite readback and export preserve the full Profile while canonicalizing ALL")
            for number in [21, 22, 254, 255, 256, 65535, Int.max] {
                try db().run("UPDATE profiles SET proximityLightingNumber = ? WHERE uuid = ?", number, info.profile.id)
                SunSmartDataManager.shared.db = try Connection(url.path)
                let legacyLocal = load(info.address)!
                precondition(!legacyLocal.profileLoadFailed && legacyLocal.profile.proximityLightingNumber == 255,
                             "Existing SQL integers above 20 must normalize before narrowing and topology validation")
                try check(try db().scalar("SELECT proximityLightingNumber FROM profiles WHERE uuid = ?", info.profile.id) as? Int64 == Int64(number))
                precondition(NSDictionary(dictionary: canonical).isEqual(to: payload(legacyLocal)),
                             "Loading a normalized Profile must preserve its raw stored value and all other fields")
                precondition(save(legacyLocal))
                try check(try db().scalar("SELECT proximityLightingNumber FROM profiles WHERE uuid = ?", info.profile.id) as? Int64 == 255)
            }
            for number in 0...255 {
                info.profile.proximityLightingNumber = UInt8(number)
                precondition(info.profile.proximityLightingNumber == (number > 20 ? 255 : UInt8(number)))
            }
            precondition(save(info))
            precondition(NSDictionary(dictionary: canonical).isEqual(to: payload(load(info.address)!)))
            for invalid: Any in [-1, Int64.min, 1.5, 21.5, 256.5, "21", "255", true, false, NSNull()] {
                var malformed = canonical
                malformed["proximityLightingNumber"] = invalid
                precondition(SpaceConfigurationIntegrityPolicy.profileIssue(malformed) == "invalidProfileRelay")
            }
        }
        print("PASS: Profile 7/8 integer >20 import, SQL wide-integer reload, model updates and canonical export retain all other fields")
    }

    static func testLegacySchemaAndReload() throws {
        // Reproduce the accuracy build's NOT NULL/no-default column on a full schema.
        let columns = try db().schema.columnDefinitions(table: "profiles").map { $0.name }
        var schema = try db().scalar("SELECT sql FROM sqlite_master WHERE name = 'profiles'") as! String
        schema.insert(contentsOf: "regulatorAccuracy INTEGER NOT NULL, ", at: schema.index(after: schema.firstIndex(of: "(")!))
        try db().execute("ALTER TABLE profiles RENAME TO profiles_previous")
        try db().execute(schema)
        let names = columns.map { "\"\($0)\"" }.joined(separator: ",")
        try db().execute("INSERT INTO profiles (\(names),regulatorAccuracy) SELECT \(names),33 FROM profiles_previous")
        let existing = load(0xC000)!
        let id = existing.profile.id
        precondition(!existing.profileLoadFailed && existing.profile.lightControlData.occupancyLevel == 500)
        precondition(save(existing))
        try check(try db().scalar("SELECT regulatorAccuracy FROM profiles WHERE uuid = ?", id) as? Int64 == 33)
        let new = GroupInfo(address: 0xC200, profile: Profile.defaultGroupProfile(type: .daylight))
        precondition(save(new))
        try check(try db().scalar("SELECT regulatorAccuracy FROM profiles WHERE uuid = ?", new.profile.id) as? Int64 == 0x14)
        // Old rows without a scenes blob reconstruct the general scene from SQL.
        try db().run("UPDATE profiles SET scenes = NULL WHERE uuid = ?", id)
        let old = load(0xC000)!
        precondition(!old.profileLoadFailed && old.profile.id == id && old.profile.lightControlData.occupancyLevel == 500)
        precondition(GroupInfo.load(meshUUID: mesh, address: 0xC000, subnetworkId: "other") == nil)
        for type: Profile.ProfileType in [.proximityLighting, .proximityLightingWithPhotocell] {
            let changed = GroupInfo(address: 0xC201, profile: Profile.defaultGroupProfile(type: type))
            precondition(save(changed))
            let originalID = changed.profile.id
            changed.profile.updateData(profile: Profile.defaultGroupProfile(type: .occupancy_daylight))
            precondition(save(changed))
            let restored = load(changed.address)!
            precondition(restored.profile.id == originalID && restored.profile.lightControlData.occupancyLevel == 500)
            precondition(SpaceConfigurationIntegrityPolicy.profileIssue(payload(restored)) == nil)
        }
        print("PASS: full legacy NOT NULL schema preserves values and IDs; old 500 lux row reload; 7/8 -> 1")
    }

    static func testInvalidWritesAndRollback() throws {
        let beforeProfiles = try count("profiles")
        let beforeGroups = try count("groupInfos")
        let invalid = GroupInfo(address: 0xC300, profile: Profile.defaultGroupProfile(type: .occupancy))
        invalid.profile.lightControlData.occupancyLevel = 101
        precondition(!save(invalid))
        try check(try count("profiles") == beforeProfiles && count("groupInfos") == beforeGroups)
        let candidate = GroupInfo(address: 0xC301)
        try db().execute("CREATE TRIGGER reject_group BEFORE INSERT ON groupInfos BEGIN SELECT RAISE(ABORT, 'injected'); END")
        precondition(!save(candidate))
        try db().execute("DROP TRIGGER reject_group")
        try check(try count("profiles") == beforeProfiles && count("groupInfos") == beforeGroups)
        // SQL write succeeds, but readback is deliberately made invalid.
        try db().execute("CREATE TRIGGER corrupt_profile AFTER INSERT ON profiles BEGIN UPDATE profiles SET occupancyLevel = 65536 WHERE uuid = NEW.uuid; END")
        precondition(!save(candidate))
        let existing = load(0xC000)!
        let before = payload(existing)
        existing.profile.lightControlData.occupancyLevel = 900
        precondition(!save(existing))
        try db().execute("DROP TRIGGER corrupt_profile")
        try check(try count("profiles") == beforeProfiles && count("groupInfos") == beforeGroups)
        precondition(NSDictionary(dictionary: before).isEqual(to: payload(load(0xC000)!)))
        precondition(load(candidate.address) == nil)
        let damaged = load(0xC001)!
        try db().run("UPDATE profiles SET scenes = X'62726f6b656e' WHERE uuid = ?", damaged.profile.id)
        precondition(load(damaged.address)!.profileLoadFailed)
        precondition(!save(load(damaged.address)!))
        precondition(save(candidate))
        print("PASS: invalid writes, group-row failure and readback corruption roll back both tables; corrupt scenes stay protected")
    }

    static func testLevelBoundaries() {
        for type in Profile.ProfileType.defaultGroupProfileTypes {
            let maximum = type.daylightType ? 65535 : 100
            for keyPath in [\Profile.LightControlData.occupancyLevel, \.vacantLevel, \.standbyLevel, \.taskLevel] {
                for value in [-1, 0, 100, 101, 500, 1500, 65535, 65536] {
                    let info = GroupInfo(address: 0xC400, profile: Profile.defaultGroupProfile(type: type))
                    info.profile.lightControlData[keyPath: keyPath] = value
                    let expected = (0...maximum).contains(value)
                    precondition((SpaceConfigurationIntegrityPolicy.profileIssue(payload(info)) == nil) == expected)
                    precondition(save(info) == expected)
                    if expected { precondition(load(info.address)!.profile.lightControlData[keyPath: keyPath] == value) }
                }
            }
            let trimmed = GroupInfo(address: 0xC401, profile: Profile.defaultGroupProfile(type: type))
            trimmed.profile.lightControlData.highEndTrim = 101
            precondition(!save(trimmed) && SpaceConfigurationIntegrityPolicy.profileIssue(payload(trimmed)) != nil)
        }
        let profile = payload(GroupInfo(address: 0xC500))
        for bad: Any in [true, "500", 1.5, NSNull()] {
            var malformed = profile
            malformed["occupancyLevel"] = bad
            precondition(SpaceConfigurationIntegrityPolicy.profileIssue(malformed) != nil)
        }
        var missing = profile
        missing.removeValue(forKey: "occupancyLevel")
        precondition(SpaceConfigurationIntegrityPolicy.profileIssue(missing) != nil)
        missing = profile
        missing.removeValue(forKey: "standbyLevel")
        missing.removeValue(forKey: "scenes")
        precondition(SpaceConfigurationIntegrityPolicy.profileIssue(missing) == nil)
        precondition(importProfile(missing)!.lightControlData.standbyLevel == 0)
    }

    static func testSceneValidationAndLegacyAutoMin() throws {
        for type in Profile.ProfileType.defaultGroupProfileTypes {
            let info = GroupInfo(address: 0xC600, profile: Profile.defaultGroupProfile(type: type))
            let extra = Profile.LightControlScene(sceneNumber: 0xFF03, name: "test-scene",
                lightControlData: .init(occupancyLevel: 500))
            info.profile.scenes.append(extra)
            precondition((SpaceConfigurationIntegrityPolicy.profileIssue(payload(info)) == nil) == type.daylightType)
            precondition(save(info) == type.daylightType)
            extra.lightControlData.occupancyLevel = 100
            precondition(save(info))
            // A valid SQL header must not hide an invalid secondary scene blob.
            extra.lightControlData.occupancyLevel = 65536
            let badScenes = try JSONEncoder().encode(info.profile.scenes)
            let filter = Table("profiles").filter(Profile.ExpressionKey.uuid == info.profile.id)
            try db().run(filter.update(Profile.ExpressionKey.scenes <- badScenes))
            precondition(load(info.address)!.profileLoadFailed)
            precondition(SpaceConfigurationIntegrityPolicy.profileIssue(payload(info)) != nil)
        }
        for value in [0, 30, 255, 100] {
            let info = GroupInfo(address: 0xC601)
            info.profile.lightControlData.autoMinLevel = value
            precondition(save(info))
            let expected = value <= 30 ? value : 255
            precondition(load(info.address)!.profile.lightControlData.autoMinLevel == expected)
            let imported = importProfile(payload(info))!
            precondition(imported.lightControlData.autoMinLevel == expected)
        }
        print("PASS: secondary scene units/invalid blob protection and legacy Auto min 0/30/255/100 normalization")
    }
}
