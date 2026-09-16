import Foundation
import CryptoKit

/// Membership survives missing Mesh identity and is isolated from configuration journals.
struct SpaceMembershipRecord: Codable, Equatable {
    struct Scope: Codable, Hashable {
        let account: String
        let region: String
        let siteID: String
        let spaceID: String
    }
    enum Phase: String, Codable { case joined, queued, requesting, unknown, confirmed, left }
    let scope: Scope
    var generation = UUID()
    var phase: Phase = .joined
    var networkID: String?
    var initialized = false
    var savedCopy: String?
    var recyclePayload: Data?
    var isLeaving: Bool { phase != .joined }
}

final class SpaceMembershipStore {
    let root: URL
    private let lock = NSRecursiveLock()
    init(root: URL) { self.root = root }

    private func url(_ scope: SpaceMembershipRecord.Scope) throws -> URL {
        let data = try JSONEncoder().encode(scope)
        // Stable key order is essential across launches.
        let object = try JSONSerialization.jsonObject(with: data)
        let canonical = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        let name = SHA256.hash(data: canonical).map { String(format: "%02x", $0) }.joined()
        return root.appendingPathComponent(name + ".json")
    }

    func read(_ scope: SpaceMembershipRecord.Scope) throws -> SpaceMembershipRecord? {
        lock.lock(); defer { lock.unlock() }
        let path = try url(scope)
        let data: Data
        do { data = try Data(contentsOf: path) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError { return nil }
        let record = try JSONDecoder().decode(SpaceMembershipRecord.self, from: data)
        guard record.scope == scope else { throw CocoaError(.fileReadCorruptFile) }
        return record
    }

    func write(_ record: SpaceMembershipRecord) throws {
        lock.lock(); defer { lock.unlock() }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let path = try url(record.scope)
        try JSONEncoder().encode(record).write(to: path, options: .atomic)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: path.path)
        #endif
        var folder = root
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
    }

    /// Compare-and-write also rejects callbacks from a previous join generation.
    func replace(_ record: SpaceMembershipRecord, expected: SpaceMembershipRecord) throws {
        lock.lock(); defer { lock.unlock() }
        guard try read(expected.scope) == expected, record.scope == expected.scope else {
            throw CocoaError(.userCancelled)
        }
        try write(record)
    }

    func records(account: String, region: String) throws -> [SpaceMembershipRecord] {
        lock.lock(); defer { lock.unlock() }
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .compactMap { path in
                let value = try JSONDecoder().decode(SpaceMembershipRecord.self, from: Data(contentsOf: path))
                return value.scope.account == account && value.scope.region == region ? value : nil
            }
    }
}

/// A response belongs to the account and membership epoch at request start.
/// Local provenance is removed before staging and is never part of uploaded JSON.
enum SpaceMembershipResponseContext {
    static let payloadKey = "_localSpaceMembershipContext"
    private static let lock = NSLock()
    private static var epoch = UUID().uuidString
    static func invalidate() { lock.lock(); defer { lock.unlock() }; epoch = UUID().uuidString }
    static func capture(account: String, region: String) -> [String: String] {
        lock.lock(); defer { lock.unlock() }
        return ["account": account, "region": region, "epoch": epoch]
    }
    static func matches(_ context: [String: String], account: String, region: String) -> Bool {
        context == capture(account: account, region: region)
    }
    static func annotate(_ response: [String: Any], context: [String: String]) -> [String: Any] {
        var result = response
        guard var data = result["data"] as? [String: Any] else { return result }
        data[payloadKey] = context
        if let spaces = data["spaces"] as? [[String: Any]] {
            data["spaces"] = spaces.map { item in
                var value = item; value[payloadKey] = context; return value
            }
        }
        result["data"] = data
        return result
    }
}
