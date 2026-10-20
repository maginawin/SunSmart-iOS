import Foundation
import SQLite

typealias Address = UInt16
let jsonEncoder = JSONEncoder(), jsonDecoder = JSONDecoder()
enum Profile { struct LightControlData: Codable {} }
final class SunSmartDataManager { static let shared = SunSmartDataManager(); var db: Connection? }

@main enum HDBInitializationPersistenceTests {
    static func main() throws {
        let file = CommandLine.arguments[1]
        SunSmartDataManager.shared.db = try Connection(file)
        Node.PreConfiguration.initDatabase()
        precondition(Node.PreConfiguration.load(meshUUID: "mesh", nodeAddress: 1) == nil)
        let config = Node.PreConfiguration()
        config.hdbInitializationSignature = "initialization-signature"
        config.upRatio = 65; config.displayLux = true
        precondition(config.save(meshUUID: "mesh", nodeAddress: 1))
        // Reopen actual SQLite and use production loading, not the in-memory node cache.
        SunSmartDataManager.shared.db = try Connection(file)
        let saved = Node.PreConfiguration.load(meshUUID: "mesh", nodeAddress: 1)!
        precondition(saved.hdbInitializationSignature == config.hdbInitializationSignature && saved.upRatio == 65 && saved.displayLux)
        precondition(Node.PreConfiguration.load(meshUUID: "other", nodeAddress: 1) == nil)
        precondition(Node.PreConfiguration.load(meshUUID: "mesh", nodeAddress: 2) == nil)
        let imported = try jsonDecoder.decode(Node.PreConfiguration.self, from: jsonEncoder.encode(saved))
        precondition(imported.hdbInitializationSignature == config.hdbInitializationSignature)
        precondition(imported.save(meshUUID: "mesh", nodeAddress: 2))
        precondition(Node.PreConfiguration.load(meshUUID: "mesh", nodeAddress: 2)?.hdbInitializationSignature == config.hdbInitializationSignature)
        precondition(Node.PreConfiguration.delete(meshUUID: "mesh", nodeAddress: 1))
        precondition(Node.PreConfiguration.load(meshUUID: "mesh", nodeAddress: 1) == nil)
        SunSmartDataManager.shared.db = nil
        precondition(Node.PreConfiguration.load(meshUUID: "mesh", nodeAddress: 2) == nil, "No durable completion without the database readback")
        print("PASS: production HDB initialization receipt SQLite save/reopen/load/delete and Codable export/import")
    }
}
