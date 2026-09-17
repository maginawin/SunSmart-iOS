import Foundation

/// A Gateway belongs to the Site primary network, not to one of its associated Spaces.
/// Keep this operation independent of Space deletion checkpoints and topology cleanup.
@MainActor
final class GatewayDeletionCoordinator {
    enum Permission { case allowed, denied, unavailable }
    enum Failure: Equatable { case offline, permission, server, local, changedContext, busy }
    enum Result: Equatable {
        case deleted(resetConfirmed: Bool)
        case failed(Failure)
    }

    struct Steps {
        var isOnline: () -> Bool
        var isCurrent: () -> Bool
        var serverAlreadyDeleted: () -> Bool
        var permission: () async -> Permission
        var prepare: () -> Bool
        var deleteServer: () async -> Bool
        var recordServerDeletion: () -> Bool
        var canReset: () -> Bool
        var reset: () async -> Bool
        var finishLocal: (Bool) -> Bool
        var cancelPreparation: () -> Void
    }

    private(set) var isRunning = false

    func delete(using steps: Steps) async -> Result {
        guard !isRunning else { return .failed(.busy) }
        guard steps.isOnline() else { return .failed(.offline) }
        guard steps.isCurrent() else { return .failed(.changedContext) }
        isRunning = true
        defer { isRunning = false }

        if !steps.serverAlreadyDeleted() {
            switch await steps.permission() {
            case .allowed: break
            case .denied: return .failed(.permission)
            case .unavailable: return .failed(.server)
            }
        }
        guard steps.isCurrent() else { return .failed(.changedContext) }
        guard steps.prepare() else { return .failed(.local) }
        if !steps.serverAlreadyDeleted() {
            guard await steps.deleteServer() else {
                if steps.isCurrent() { steps.cancelPreparation() }
                return .failed(.server)
            }
            guard steps.isCurrent() else { return .failed(.changedContext) }
            guard steps.recordServerDeletion() else { return .failed(.local) }
        }
        guard steps.isCurrent() else { return .failed(.changedContext) }
        // Internet can disappear after server confirmation. Bluetooth and local
        // completion no longer require a network request or a second confirmation.
        let resetConfirmed = steps.canReset() ? await steps.reset() : false
        guard steps.isCurrent() else { return .failed(.changedContext) }
        return steps.finishLocal(resetConfirmed)
            ? .deleted(resetConfirmed: resetConfirmed) : .failed(.local)
    }
}

struct GatewayDeletionReceipt: Codable, Equatable {
    enum Phase: String, Codable { case prepared, serverDeleted, completed }
    let siteId: String
    let meshUUID: String
    let networkId: String
    let mac: String
    let nodeUUID: String
    let address: UInt16
    let elementAddresses: [UInt16]
    let productId: UInt16?
    let createdTimestamp: Int64
    var phase: Phase
    var resetConfirmed = false

    func matches(nodeUUID: String, address: UInt16, createdTimestamp: Int64? = nil) -> Bool {
        self.nodeUUID.caseInsensitiveCompare(nodeUUID) == .orderedSame
            && self.address == address
            && (createdTimestamp == nil || createdTimestamp! <= self.createdTimestamp)
    }

    func blocksImport(nodeUUID: String, address: UInt16, createdTimestamp: Int64?) -> Bool {
        phase != .completed || matches(nodeUUID: nodeUUID, address: address, createdTimestamp: createdTimestamp)
    }
}

/// One small durable receipt per Gateway. Completed receipts reject stale cloud
/// snapshots of the deleted provisioning instance, without retaining credentials.
struct GatewayDeletionReceiptStore {
    let url: URL

    func read() throws -> GatewayDeletionReceipt? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(GatewayDeletionReceipt.self, from: Data(contentsOf: url))
    }

    func write(_ receipt: GatewayDeletionReceipt) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(receipt).write(to: url, options: .atomic)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                                              ofItemAtPath: url.path)
        #endif
        var excludedDirectory = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try excludedDirectory.setResourceValues(values)
    }

    func cancelPreparation() throws {
        guard try read()?.phase == .prepared else { return }
        try FileManager.default.removeItem(at: url)
    }
}
