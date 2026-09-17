import Foundation
import CryptoKit
import NordicSigMeshSDK

/// Site-scoped deletion receipt and local completion. No Space is required.
final class GatewayDeletionContext {
    private enum PersistenceError: Error { case failed }
    private static let lock = NSRecursiveLock()
    private static var active = Set<String>()
    private let account = UserData.currentUserId
    private let region = String(describing: UserData.currentServerRegion)
    private let network: MeshNetwork
    private let store: GatewayDeletionReceiptStore
    private var receipt: GatewayDeletionReceipt
    private var ownsActiveOperation = false

    init?(site: SiteData, gateway: GatewayModel, node: Node) {
        guard let network = node.network,
              network.uuid.uuidString == site.meshUUID,
              node.subNetworkId == site.meshNetworkId,
              gateway.siteId == site.id, gateway.address == node.primaryUnicastAddress,
              MeshNetworkManager.instance.meshNetwork === network,
              MeshNetworkManager.instance.currentNetworkKey.isPrimary else { return nil }
        self.network = network
        store = Self.store(siteId: site.id, mac: gateway.mac)
        receipt = Self.makeReceipt(site: site, gateway: gateway, node: node)
    }

    var isCurrent: Bool {
        account == UserData.currentUserId && region == String(describing: UserData.currentServerRegion)
    }

    var serverAlreadyDeleted: Bool {
        guard isCurrent, let saved = try? store.read(),
              saved.matches(nodeUUID: receipt.nodeUUID, address: receipt.address,
                            createdTimestamp: receipt.createdTimestamp) else { return false }
        return saved.phase != .prepared
    }

    func prepare() -> Bool {
        Self.lock.lock(); defer { Self.lock.unlock() }
        guard isCurrent, !Self.active.contains(Self.activeKey(store.url)) else { return false }
        do {
            if let saved = try store.read(),
               saved.matches(nodeUUID: receipt.nodeUUID, address: receipt.address,
                             createdTimestamp: receipt.createdTimestamp) {
                receipt = saved
            }
            try store.write(receipt)
            Self.active.insert(Self.activeKey(store.url))
            ownsActiveOperation = true
            return true
        } catch { return false }
    }

    func recordServerDeletion() -> Bool {
        Self.lock.lock(); defer { Self.lock.unlock() }
        guard isCurrent else { return false }
        receipt.phase = .serverDeleted
        do { try store.write(receipt); return true } catch { return false }
    }

    func cancelPreparation() {
        Self.lock.lock(); defer { Self.lock.unlock() }
        guard isCurrent else { return }
        try? store.cancelPreparation()
    }

    func finish(resetConfirmed: Bool) -> Bool {
        guard isCurrent, receipt.phase != .prepared else { return false }
        receipt.resetConfirmed = receipt.resetConfirmed || resetConfirmed
        return Self.complete(receipt: receipt, network: network, store: store)
    }

    func release() {
        Self.lock.lock(); defer { Self.lock.unlock() }
        guard ownsActiveOperation else { return }
        Self.active.remove(Self.activeKey(store.url))
        ownsActiveOperation = false
    }

    deinit { release() }

    // Directory enumeration may resolve /var to /private/var. Use the hashed
    // account directory and receipt filename, not URL spelling, as the identity.
    private static func activeKey(_ url: URL) -> String {
        url.deletingLastPathComponent().lastPathComponent + "/" + url.lastPathComponent
    }

    private static var root: URL {
        let scope = "\(UserData.currentUserId)|\(UserData.currentServerRegion)"
        return URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/GatewayDeletion")
            .appendingPathComponent(hash(scope))
    }

    private static func hash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func store(siteId: String, mac: String) -> GatewayDeletionReceiptStore {
        .init(url: root.appendingPathComponent(hash(siteId + "|" + mac.uppercased()) + ".json"))
    }

    private static func makeReceipt(site: SiteData, gateway: GatewayModel, node: Node?) -> GatewayDeletionReceipt {
        .init(siteId: site.id, meshUUID: site.meshUUID, networkId: site.meshNetworkId, mac: gateway.mac,
              nodeUUID: node?.uuid.uuidString ?? "", address: gateway.address,
              elementAddresses: Array(Set((node?.elements.compactMap { $0.unicastAddress } ?? []) + [gateway.address])),
              productId: node?.productIdentifier, createdTimestamp: node?.createdTimestamp ?? 0,
              phase: gateway.serverDeletionPendingLocalReset ? .serverDeleted : .prepared)
    }

    static func hasPendingDeletion(siteId: String, mac: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        do { return try store(siteId: siteId, mac: mac).read().map { $0.phase != .completed } ?? false }
        catch { return true }
    }

    // Site import must keep its receipt check and subsequent Node/Gateway writes
    // atomic with deletion. Call only around synchronous work, after awaits.
    static func lockImport() { lock.lock() }
    static func unlockImport() { lock.unlock() }

    static func blocksImport(siteId: String, mac: String, node: Node, createdTimestamp: Int64?) -> Bool {
        lock.lock(); defer { lock.unlock() }
        do {
            return try store(siteId: siteId, mac: mac).read()?.blocksImport(
                nodeUUID: node.uuid.uuidString, address: node.primaryUnicastAddress,
                createdTimestamp: createdTimestamp) ?? false
        } catch { return true }
    }

    static func blocksRegistration(gateway: GatewayModel, node: Node) -> Bool {
        blocksImport(siteId: gateway.siteId, mac: gateway.mac, node: node, createdTimestamp: node.createdTimestamp)
    }

    static func blocksSave(_ gateway: GatewayModel) -> Bool {
        lock.lock(); defer { lock.unlock() }
        do {
            guard let receipt = try store(siteId: gateway.siteId, mac: gateway.mac).read() else { return false }
            if receipt.phase != .completed {
                return !gateway.serverDeletionPendingLocalReset && !gateway.isServerDeletionInProgress
            }
            guard receipt.address == gateway.address else { return false }
            guard !gateway.serverDeletionPendingLocalReset,
                  let node = Node.load(meshUUID: receipt.meshUUID, address: gateway.address).first else { return true }
            return receipt.matches(nodeUUID: node.uuid.uuidString, address: node.primaryUnicastAddress,
                                   createdTimestamp: node.createdTimestamp)
        } catch { return true }
    }

    static func serverDeletionConfirmed(siteId: String, mac: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard let receipt = try? store(siteId: siteId, mac: mac).read() else { return false }
        if let gateway = GatewayModel.load(siteId: siteId, macAddress: mac).first,
           let node = Node.load(meshUUID: receipt.meshUUID, address: gateway.address).first,
           !receipt.matches(nodeUUID: node.uuid.uuidString, address: node.primaryUnicastAddress,
                            createdTimestamp: node.createdTimestamp) { return false }
        return receipt.phase != .prepared
    }

    /// Called on Site entry after an interrupted operation, never while its
    /// controller is still trying Reset. Old persisted pending flags are adopted.
    @discardableResult
    static func resume(site: SiteData) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let manager = MeshNetworkManager.instance
        let network: MeshNetwork?
        if manager.meshNetwork?.uuid.uuidString == site.meshUUID, manager.currentNetworkKey.isPrimary {
            network = manager.meshNetwork
        } else {
            network = MeshNetwork.load(meshUUID: site.meshUUID, subnetworkId: site.meshNetworkId)
        }
        guard let network else { return false }
        for gateway in GatewayModel.load(siteId: site.id) where gateway.serverDeletionPendingLocalReset {
            let store = store(siteId: site.id, mac: gateway.mac)
            guard !active.contains(activeKey(store.url)) else { continue }
            do {
                if try store.read() == nil {
                    let node = network.nodes.first { $0.primaryUnicastAddress == gateway.address }
                    try store.write(makeReceipt(site: site, gateway: gateway, node: node))
                }
            } catch { continue }
        }
        var needsManualReset = false
        for url in (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] where url.pathExtension == "json" {
            guard !active.contains(activeKey(url)), let receipt = try? GatewayDeletionReceiptStore(url: url).read(),
                  receipt.siteId == site.id, receipt.networkId == site.meshNetworkId else { continue }
            if receipt.phase == .prepared {
                // A terminated request has no confirmed server result. Release its
                // preflight lock; do not infer success or remove any local data.
                try? GatewayDeletionReceiptStore(url: url).cancelPreparation()
                continue
            }
            guard receipt.phase == .serverDeleted else { continue }
            if complete(receipt: receipt, network: network, store: .init(url: url)) {
                needsManualReset = needsManualReset || !receipt.resetConfirmed
            }
        }
        return needsManualReset
    }

    private static func complete(receipt: GatewayDeletionReceipt, network: MeshNetwork,
                                 store: GatewayDeletionReceiptStore) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard receipt.phase != .prepared, network.uuid.uuidString == receipt.meshUUID,
              let db = SunSmartDataManager.shared.db else { return false }
        let persistedNodes = Node.load(meshUUID: receipt.meshUUID, address: receipt.address)
        // Never erase a new provisioning instance that reused an address.
        guard persistedNodes.allSatisfy({ receipt.matches(nodeUUID: $0.uuid.uuidString,
            address: $0.primaryUnicastAddress, createdTimestamp: $0.createdTimestamp) }) else { return false }
        if let current = network.nodes.first(where: { $0.primaryUnicastAddress == receipt.address }),
           !receipt.matches(nodeUUID: current.uuid.uuidString, address: current.primaryUnicastAddress,
                            createdTimestamp: current.createdTimestamp) { return false }
        do {
            // Keep the receipt until both databases have completed their work.
            try store.write(receipt)
            if let node = network.nodes.first(where: { $0.primaryUnicastAddress == receipt.address }) {
                network.remove(node: node)
            }
            guard Node.delete(meshUUID: receipt.meshUUID, address: receipt.address), network.save(),
                  Node.load(meshUUID: receipt.meshUUID, address: receipt.address).isEmpty else { return false }
            let addresses = Set(receipt.elementAddresses)
            for scene in network.scenes where !addresses.isDisjoint(with: scene.addresses) {
                addresses.forEach { address in while scene.addresses.contains(address) { scene.remove(address: address) } }
                guard scene.save() else { return false }
            }
            try db.transaction {
                func require(_ success: Bool) throws {
                    if !success { throw PersistenceError.failed }
                }
                for schedule in Schedule.load(meshUUID: receipt.meshUUID, meshNetworkId: receipt.networkId) {
                    let active = schedule.nodeAddresses.filter { !addresses.contains($0) }
                    let pending = schedule.needDeleteNodeAddresses.filter { !addresses.contains($0) }
                    if active != schedule.nodeAddresses || pending != schedule.needDeleteNodeAddresses {
                        schedule.nodeAddresses = active; schedule.needDeleteNodeAddresses = pending
                        try require(schedule.save(meshUUID: receipt.meshUUID, meshNetworkId: receipt.networkId))
                    }
                }
                try require(Node.PreConfiguration.delete(meshUUID: receipt.meshUUID, nodeAddress: receipt.address))
                if let product = receipt.productId,
                   let distribution = MeshDistributionData.load(meshUUID: receipt.meshUUID, meshNetworkId: receipt.networkId, productId: product),
                   distribution.distributionAddress == receipt.address {
                    try require(distribution.delete(meshUUID: receipt.meshUUID, networkId: receipt.networkId, productId: product))
                }
                for space in SpaceData.load(siteId: receipt.siteId) where space.relevanceGatewayId?.uppercased() == receipt.mac.uppercased() {
                    space.relevanceGatewayId = nil; space.gatewayStatus = .notBound; space.gatewayLastOnline = nil
                    try require(space.save())
                }
                if let gateway = GatewayModel.load(siteId: receipt.siteId, macAddress: receipt.mac).first {
                    guard gateway.address == receipt.address else { throw PersistenceError.failed }
                    try require(gateway.delete())
                }
            }
            var completed = receipt
            completed.phase = .completed
            try store.write(completed)
            return true
        } catch {
            #if DEBUG
            print("[GatewayDeletion] local completion failed site=\(receipt.siteId) address=\(receipt.address) error=\(error)")
            #endif
            return false
        }
    }
}
