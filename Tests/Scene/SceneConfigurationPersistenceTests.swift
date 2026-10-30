import Foundation
import SQLite

typealias SceneNumber = UInt16
typealias Address = UInt16
extension UInt16 {
    var hex: String { String(format: "%04X", self) }
    var isSpecialScene: Bool { self >= 0xFF00 }
}
final class SunSmartDataManager {
    static let shared = SunSmartDataManager()
    var db: Connection?
}
final class MeshNetworkManager {
    static let instance = MeshNetworkManager()
    struct Network { let uuid = UUID() }
    struct Key { let networkId: UInt16 = 1 }
    var meshNetwork: Network? = Network()
    let currentNetworkKey = Key()
    var groups: [Group] = []
    var schedules: [Schedule] = []
}
final class Group {
    struct Info { var sceneExecuteDatas: [SceneExecuteData] = [] }
    let info = Info()
}
final class SceneExecuteData { let sceneNumber: UInt16 = 1 }
final class Schedule { var scene: Scene? }
final class Scene { let number: UInt16 = 1 }

// ACTUAL_SCENE_INFO
// ACTUAL_SCENE_DATABASE

var storageAssertions = 0
func check(_ value: Bool) { precondition(value); storageAssertions += 1 }

@main struct SceneConfigurationPersistenceTests {
    static func main() throws {
        let path = CommandLine.arguments[1]
        SunSmartDataManager.shared.db = try Connection(path)
        var db: Connection { SunSmartDataManager.shared.db! }
        // A legacy database with a future column demonstrates that metadata saves
        // must preserve the committed configuration, including pending cleanup.
        try db.run("CREATE TABLE sceneInfos (id INTEGER PRIMARY KEY, meshUUID TEXT NOT NULL, subNetworkKey TEXT NOT NULL, number INTEGER NOT NULL, imageId INTEGER NOT NULL, configuration BLOB, UNIQUE(meshUUID, number))")
        let payload = Data(#"{"schemaVersion":1,"kind":"devices","name":"Evening","revision":"00000000-0000-0000-0000-000000000001","deviceMembers":[],"pendingOperations":[],"isDeleting":false}"#.utf8)
        try db.run("INSERT INTO sceneInfos(meshUUID,subNetworkKey,number,imageId,configuration) VALUES ('mesh','net',1,2,?)", Blob(bytes: Array(payload)))
        SceneInfo.initDatabase()
        SceneInfo.initDatabase()
        let info = SceneInfo.load(meshUUID: "mesh", sceneId: 1)!
        info.imageId = 9
        check(info.save(meshUUID: "mesh", subnetworkId: "net"))
        let saved = try db.scalar("SELECT configuration FROM sceneInfos WHERE number = 1") as? Blob
        guard let saved else { print("FAIL: metadataSavePreservesConfiguration: configuration was discarded"); exit(1) }
        let object = try JSONSerialization.jsonObject(with: Data(saved.bytes)) as! [String: Any]
        check(object["name"] as? String == "Evening")
        // Reopen the real database, including records that have no SDK Scene.
        SunSmartDataManager.shared.db = try Connection(path)
        let reopened = try SceneInfo.loadAll(meshUUID: "mesh", subnetworkId: "net")
        check(reopened.count == 1 && reopened[0].configuration?.name == "Evening" && reopened[0].imageId == 9)
        let identity = TimedSchedulerNodeIdentity(nodeUUID: "00000000-0000-0000-0000-00000000000A", unicastAddress: "0001", deviceKeyFingerprint: String(repeating: "A", count: 64))
        let pending = SceneConfiguration(kind: .devices, name: "Cleanup", pendingOperations: [.init(identity: identity, action: .remove)], isDeleting: true)
        let removal = SceneInfo(sceneId: 2); removal.configuration = pending
        check(removal.save(meshUUID: "mesh", subnetworkId: "other-net"))
        check(try SceneInfo.loadAll(meshUUID: "mesh").count == 2)
        check(try SceneInfo.loadAll(meshUUID: "mesh", subnetworkId: "net").count == 1)
        SunSmartDataManager.shared.db = try Connection(path)
        check(SceneInfo.load(meshUUID: "mesh", sceneId: 2)?.configuration == pending)
        try db.run("INSERT INTO sceneInfos(meshUUID,subNetworkKey,number,imageId,configuration) VALUES ('mesh','net',3,0,X'7B7D')")
        let corrupt = SceneInfo.load(meshUUID: "mesh", sceneId: 3)!
        check(corrupt.configurationLoadFailed && corrupt.configuration == nil)
        check(!corrupt.save(meshUUID: "mesh", subnetworkId: "net"))
        check((try db.scalar("SELECT configuration FROM sceneInfos WHERE number = 3") as? Blob)?.bytes == [123, 125])
        check(try SceneInfo.loadAll(meshUUID: "mesh").contains { $0.sceneId == 3 && $0.configurationLoadFailed })
        try db.run("INSERT INTO sceneInfos(meshUUID,subNetworkKey,number,imageId) VALUES ('mesh','net',4,0), ('mesh','net',65280,0), ('other-mesh','net',1,0)")
        let legacy = SceneInfo.load(meshUUID: "mesh", sceneId: 4)!
        check(legacy.configuration == nil && !legacy.configurationLoadFailed)
        check(try SceneInfo.loadAll(meshUUID: "mesh").map(\.sceneId) == [1, 2, 3, 4])
        let special = SceneInfo(sceneId: 0xFF00); special.configuration = pending
        check(!special.save(meshUUID: "mesh", subnetworkId: "net"))
        // A failed write must leave the previously committed record unchanged.
        try db.run("CREATE TRIGGER reject_scene BEFORE INSERT ON sceneInfos BEGIN SELECT RAISE(ABORT, 'injected write failure'); END")
        info.imageId = 20
        check(!info.save(meshUUID: "mesh", subnetworkId: "net"))
        check(SceneInfo.load(meshUUID: "mesh", sceneId: 1)?.imageId == 9)
        try db.run("DROP TRIGGER reject_scene")
        do {
            try db.savepoint {
                try info.saveConfiguration(meshUUID: "mesh", subnetworkId: "net")
                throw NSError(domain: "rollback", code: 1)
            }
        } catch { }
        check(SceneInfo.load(meshUUID: "mesh", sceneId: 1)?.imageId == 9)
        SunSmartDataManager.shared.db = nil
        guard !info.save(meshUUID: "mesh", subnetworkId: "net") else {
            print("FAIL: unavailableDatabaseCannotReportSaveSuccess"); exit(1)
        }
        check(SceneInfo.load(meshUUID: "mesh", sceneId: 1)?.configurationLoadFailed == true)
        do {
            _ = try SceneInfo.loadAll(meshUUID: "mesh")
            print("FAIL: unavailableDatabaseCannotReturnEmptyRows"); exit(1)
        } catch { }
        check(!info.delete(meshUUID: "mesh") && !SceneInfo.delete(meshUUID: "mesh", networkId: "net"))
        // Migration from the actual pre-feature schema; run twice and reopen.
        SunSmartDataManager.shared.db = try Connection(path + ".legacy")
        try db.run("CREATE TABLE sceneInfos (id INTEGER PRIMARY KEY, meshUUID TEXT NOT NULL, subNetworkKey TEXT NOT NULL, number INTEGER NOT NULL, imageId INTEGER NOT NULL, UNIQUE(meshUUID, number))")
        try db.run("INSERT INTO sceneInfos(meshUUID,subNetworkKey,number,imageId) VALUES ('mesh','net',7,3)")
        check(SceneInfo.initDatabase() && SceneInfo.initDatabase())
        SunSmartDataManager.shared.db = try Connection(path + ".legacy")
        let migrated = SceneInfo.load(meshUUID: "mesh", sceneId: 7)!
        check(migrated.configuration == nil && !migrated.configurationLoadFailed && migrated.imageId == 3)
        try db.run("UPDATE sceneInfos SET configuration = 'broken JSON text' WHERE number = 7")
        let wrongType = SceneInfo.load(meshUUID: "mesh", sceneId: 7)!
        guard wrongType.configurationLoadFailed && !wrongType.save(meshUUID: "mesh", subnetworkId: "net") else {
            print("FAIL storage: explicitNonBlobConfigurationMustNotBecomeLegacy"); exit(1)
        }
        storageAssertions += 1
        print("storage: \(storageAssertions) assertions passed, 0 failed (real SQLite)")
    }
}
