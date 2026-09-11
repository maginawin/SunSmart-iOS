import Foundation
import SQLite
import struct SQLite.Expression

typealias Address = UInt16
final class MeshNetwork { var deviceUsedAddresses: [UInt16] = [] }
final class MeshDataManager {
    static let shared = MeshDataManager()
    var db: Connection?
}
final class SunSmartDataManager {
    static let shared = SunSmartDataManager()
    var db: Connection?
}
enum UserData { static var currentUserId = "account"; static var currentServerRegion = "region" }
enum Node {
    static let nodesTable = Table("nodes")
    enum ExpressionKey {
        static let meshUUID = Expression<String>("meshUUID")
        static let subnetworkId = Expression<String?>("subnetworkId")
        static let primaryUnicastAddress = Expression<Int>("primaryUnicastAddress")
        static let elementCount = Expression<Int>("elementCount")
    }
}

@main enum SiteEntryPerformanceTests {
    static func require(_ value: @autoclosure () -> Bool, _ message: String) {
        if !value() { fatalError(message) }
    }

    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("mesh.sqlite3").path
        let db = try Connection(path)
        MeshDataManager.shared.db = db
        SunSmartDataManager.shared.db = try Connection(directory.appendingPathComponent("app.sqlite3").path)
        try db.run("CREATE TABLE nodes (meshUUID TEXT, subnetworkId TEXT, primaryUnicastAddress INTEGER, elementCount INTEGER, elements BLOB)")
        let insert = try db.prepare("INSERT INTO nodes VALUES (?, ?, ?, ?, ?)")
        try db.transaction {
            for index in 0..<1064 { try insert.run("site", "space", 1 + index * 3, 3, "INVALID MODEL JSON") }
            try insert.run("site", "other", 4000, 1, "INVALID")
            try insert.run("other-site", "space", 5000, 1, "INVALID")
        }
        var queries: [String] = []
        db.trace { queries.append($0) }
        let addresses = Node.loadAddresses(meshUUID: "site", subnetworkId: "space")
        require(addresses.count == 3192 && addresses.first == 1 && addresses.last == 3192, "element address expansion/scope changed")
        require(!queries.contains { $0.lowercased().contains("select *") || $0.lowercased().contains("select \"elements\"") }, "projection must not select model blobs")
        require(Node.loadAddresses(meshUUID: "site").count == 3193, "site-wide address protection must include peer spaces")

        let network = MeshNetwork()
        network.deviceUsedAddresses = [1, 2, 2, 6]
        let existing: [UInt16] = [2, 3, 3, 4]
        let excluded: [UInt16] = [4, 4, 5, 6]
        let expected = existing.filter { !network.deviceUsedAddresses.contains($0) }
            + excluded.filter { !network.deviceUsedAddresses.contains($0) }
        require(missingAddresses(network: network, existNodeAddresses: existing, exclustionAddresses: excluded) == expected,
                "optimization must preserve original order/duplicates across arrays")
        network.deviceUsedAddresses = Array(1...30000)
        let started = ProcessInfo.processInfo.systemUptime
        let missing = missingAddresses(network: network, existNodeAddresses: Array(1...32000), exclustionAddresses: Array(1...32000))
        require(missing.count == 4000, "large address set result mismatch")
        print("Address membership: 64,000 candidates / 30,000 used, seconds=\(ProcessInfo.processInfo.systemUptime - started)")

        let readSnapshot = ConfigurationMeshReadSnapshot()
        readSnapshot.network = network
        readSnapshot.revision = ConfigurationSnapshotRevision.current()
        require(readSnapshot.currentNetwork === network, "unchanged snapshot should reuse network")
        try insert.run("site", "space", 6000, 1, "INVALID")
        require(readSnapshot.currentNetwork == nil, "same-connection write must invalidate snapshot")
        readSnapshot.revision = ConfigurationSnapshotRevision.current()
        let other = try Connection(path)
        try other.run("UPDATE nodes SET elementCount = 2 WHERE primaryUnicastAddress = 6000")
        require(readSnapshot.currentNetwork == nil, "external-connection write must invalidate snapshot")
        readSnapshot.revision = ConfigurationSnapshotRevision.current()
        UserData.currentServerRegion = "changed"
        require(readSnapshot.currentNetwork == nil, "region switch must invalidate snapshot")
        readSnapshot.revision = ConfigurationSnapshotRevision.current()
        UserData.currentUserId = "other"
        require(readSnapshot.currentNetwork == nil, "account switch must invalidate snapshot")

        let uploads = ["/sitespace/sync/siteprops", "/sitespace/sync/spaceprops"]
        let paths = ["/sitespace/get/siteprops", "/sitespace/get/spaceprops"] + uploads
        let hosts = ["www.mericher.com", "sunsmart-ap.mericher.com", "sunsmart-us.mericher.com", "sunsmart-eu.mericher.com"]
        let samples: [[String: Any]] = [
            ["site": ["siteName": "测试 Site", "spaces": []], "user": ["userId": "test"]],
            ["site": ["siteName": "New Site"], "user": ["userId": "test"], "devicesInSetle": 100],
            ["siteId": "test", "spaceId": "space", "userId": "test", "spaces": []],
            ["payload": String(repeating: "中英文 test ", count: 1000)]
        ]
        for host in hosts {
            for path in paths {
                for sample in samples {
                    var request = URLRequest(url: URL(string: "https://" + host + "/srv2" + path)!)
                    request.httpMethod = "POST"
                    request.httpBody = try JSONSerialization.data(withJSONObject: sample)
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("gzip", forHTTPHeaderField: "Content-Encoding")
                    request.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")
                    request.setValue("1", forHTTPHeaderField: "Content-Length")
                    let prepared = try HTTPBodyEncoding.prepare(request)
                    let shouldCompress = uploads.contains(path)
                    if shouldCompress {
                        require(prepared.httpBody!.isGzipped, "upload must contain actual gzip bytes")
                        let decoded = try prepared.httpBody!.gunzipped()
                        require(decoded == request.httpBody, "gzip must preserve every JSON byte including UTF-8")
                        require(prepared.value(forHTTPHeaderField: "Content-Encoding") == "gzip", "gzip body must have matching header")
                    } else {
                        require(prepared.httpBody == request.httpBody, "queries must retain JSON in every region")
                        require(prepared.value(forHTTPHeaderField: "Content-Encoding") == nil, "identity body must not declare gzip")
                    }
                    if uploads.contains(path) {
                        require(prepared.value(forHTTPHeaderField: "Content-Length") == nil, "upload length must be calculated from final bytes")
                    }
                    require(prepared.value(forHTTPHeaderField: "Content-Type") == "application/json", "media type remains JSON")
                    require(prepared.value(forHTTPHeaderField: "Accept-Encoding") == "gzip", "response negotiation must remain")
                    let repeated = try HTTPBodyEncoding.prepare(prepared)
                    require(repeated.httpBody == prepared.httpBody && repeated.allHTTPHeaderFields == prepared.allHTTPHeaderFields,
                            "repeated preparation must preserve body and headers")
                }
            }
        }
        for method in ["GET", "POST"] {
            var request = URLRequest(url: URL(string: "https://www.mericher.com/srv2/sitespace/sync/siteprops")!)
            request.httpMethod = method
            for body in [nil, Data(), Data("{}".utf8)] as [Data?] {
                if method == "POST", body?.isEmpty == false { continue }
                request.httpBody = body
                let prepared = try HTTPBodyEncoding.prepare(request)
                require(prepared.httpBody == body && prepared.value(forHTTPHeaderField: "Content-Encoding") == nil,
                        "absent/empty bodies and non-POST requests must not be compressed")
            }
        }
        print("PASS: SDK address semantics, SQLite snapshot invalidation and gzip request encoding in all regions")
    }
}
