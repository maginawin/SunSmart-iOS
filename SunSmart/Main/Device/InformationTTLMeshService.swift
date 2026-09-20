import Foundation
import NordicSigMeshSDK

/// The explicit owning scope avoids borrowing whichever Space happens to be
/// visible when a delayed callback arrives.
enum InformationTTLContext {
    case device(SpaceData)
    case gateway(GatewayInformationContext)

    var isVisible: Bool {
        switch self {
        case .device(let space):
            return space.permission == .owner || space.permission == .editor
        case .gateway(let context):
            if context.site.permission == .owner { return true }
            return context.site.spaces.contains { space in
                (space.permission == .owner || space.permission == .editor)
                    && (context.gatewayModel.associatedSpaces.isEmpty
                        || context.gatewayModel.associatedSpaces.contains { $0.spaceId == space.id })
            }
        }
    }

    var canEdit: Bool {
        switch self {
        case .device(let space): return space.canEditing && space.deviceOperates.contains(.edit)
        case .gateway(let context):
            return context.site.canConfigureGateway(context.gatewayModel)
                && !context.gatewayModel.isServerDeletionInProgress
                && !context.gatewayModel.serverDeletionPendingLocalReset
        }
    }
}

final class InformationTTLMeshService: InformationTTLService {
    let context: InformationTTLContext
    private let node: Node
    private let network: MeshNetwork
    private let networkID: String
    private var pendingRequest: UUID?
    private var generation: Int64?

    init?(node: Node, context: InformationTTLContext) {
        guard let network = node.network,
              network.nodes.contains(where: { $0 === node }),
              node.primaryUnicastAddress.isUnicast else { return nil }
        switch context {
        case .device(let space):
            guard space.meshUUID.caseInsensitiveCompare(network.uuid.uuidString) == .orderedSame,
                  node.subNetworkId == space.meshNetworkId else { return nil }
        case .gateway(let gateway):
            guard gateway.node === node else { return nil }
        }
        self.node = node
        self.network = network
        self.networkID = MeshNetworkManager.instance.currentNetworkKey.networkId.hex
        self.context = context
    }

    var isCurrent: Bool {
        node.network === network && MeshNetworkManager.instance.meshNetwork === network
            && network.nodes.contains(where: { $0 === node })
            && MeshNetworkManager.instance.currentNetworkKey.networkId.hex == networkID
    }

    var readBlocker: InformationTTLFailure? {
        guard context.isVisible else { return .permission }
        guard isCurrent, node.deviceKey != nil, !node.networkKeys.isEmpty else { return .unavailable }
        let manager = MeshLibManager.manager
        guard manager.isMeshNetworkConnected, let proxy = manager.currentProxyReadyContext else { return .disconnected }
        if case .gateway = context,
           proxy.nodeAddress != node.primaryUnicastAddress || manager.currentProxy?.nodeAddress != node.primaryUnicastAddress {
            return .disconnected
        }
        return nil
    }

    var writeBlocker: InformationTTLFailure? { context.canEdit ? readBlocker : .permission }
    var canSynchronize: Bool { context.canEdit }
    var cachedTTL: UInt8? { node.defaultTTL }
    var needsCloudSync: Bool {
        switch context {
        case .device(let space): return space.needUploadCloud
        case .gateway(let context):
            return context.gatewayModel.lastUpdate > (context.gatewayModel.lastUploadCloudTimestamp ?? 0)
        }
    }

    func getTTL(completion: @escaping (UInt8?) -> Void) {
        guard readBlocker == nil else { completion(nil); return }
        send(ConfigDefaultTtlGet(), completion: completion)
    }

    func setTTL(_ value: UInt8, completion: @escaping (UInt8?) -> Void) {
        guard writeBlocker == nil, InformationTTLValue.isEditable(value) else { completion(nil); return }
        send(ConfigDefaultTtlSet(ttl: value), completion: completion)
    }

    private func send(_ message: AcknowledgedConfigMessage, completion: @escaping (UInt8?) -> Void) {
        guard pendingRequest == nil, readBlocker == nil else { completion(nil); return }
        let id = UUID()
        let proxy = MeshLibManager.manager.currentProxyReadyContext
        let deviceKey = node.deviceKey
        let keys = node.networkKeys.map { $0.key }
        pendingRequest = id
        let finish: (UInt8?) -> Void = { [self] value in
            guard pendingRequest == id else { return }
            pendingRequest = nil
            let validContext = isCurrent && context.isVisible
                && MeshLibManager.manager.currentProxyReadyContext == proxy
                && node.deviceKey == deviceKey && node.networkKeys.map({ $0.key }) == keys
            completion(validContext ? value : nil)
        }
        // MessageHandle.cancel() in this SDK clears *all* callbacks for the
        // destination, including Information TimeGet. Let the reliable request
        // expire normally; our fallback follows its timeout, never precedes it.
        let timeout = MeshNetworkManager.instance.networkParameters.acknowledgmentMessageTimeout + 3
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { finish(nil) }
        attempt(message, until: Date().addingTimeInterval(2), request: id, finish: finish)
    }

    private func attempt(_ message: AcknowledgedConfigMessage, until deadline: Date, request id: UUID,
                         finish: @escaping (UInt8?) -> Void) {
        guard pendingRequest == id, readBlocker == nil,
              !(message is ConfigDefaultTtlSet) || writeBlocker == nil else { finish(nil); return }
        do {
            try MeshNetworkManager.instance.send(message, to: node.primaryUnicastAddress) { [self] result in
                DispatchQueue.main.async { [self] in
                    guard pendingRequest == id else { return }
                    if case .failure(let error) = result, let accessError = error as? AccessError,
                       case .busy = accessError, Date() < deadline {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [self] in
                            attempt(message, until: deadline, request: id, finish: finish)
                        }
                        return
                    }
                    // SDK reliable requests match the response opcode and source.
                    // Its ConfigurationClientHandler updates and saves the Node
                    // before this callback; never assign the remote public setter.
                    let status = (try? result.get()) as? ConfigDefaultTtlStatus
                    finish(status.flatMap { InformationTTLValue.isValid($0.ttl) ? $0.ttl : nil })
                }
            }
        } catch { finish(nil) }
    }

    func persist(_ value: UInt8, markCloudDirty: Bool) -> Bool {
        guard isCurrent, InformationTTLValue.isValid(value), node.defaultTTL == value,
              node.save(),
              Node.load(meshUUID: network.uuid.uuidString, subnetworkId: node.subNetworkId,
                        address: node.primaryUnicastAddress, nodeUUID: node.uuid.uuidString)
                .first?.defaultTTL == value else { return false }
        // Read-only availability can outlive edit authorization. Keep the actual
        // device cache, but never start an unauthorized cloud mutation.
        guard markCloudDirty else { return true }
        switch context {
        case .device(let space):
            if let stored = SpaceData.load(siteId: space.siteId, spaceId: space.id).first {
                space.lastUpdate = max(space.lastUpdate, stored.lastUpdate, stored.lastUploadCloudTimestamp ?? 0)
            }
            space.markLocalChangePendingCloudSync()
            generation = space.lastUpdate
            return space.save()
        case .gateway(let context):
            let gateway = context.gatewayModel
            let stored = GatewayModel.load(siteId: gateway.siteId, macAddress: gateway.mac).first
            gateway.lastUpdate = GatewayCloudSyncGenerationPolicy.next(
                now: Int64(Date().timeIntervalSince1970), current: max(gateway.lastUpdate, stored?.lastUpdate ?? 0),
                uploaded: max(gateway.lastUploadCloudTimestamp ?? 0, stored?.lastUploadCloudTimestamp ?? 0)
            )
            gateway.syncCloudError = nil
            generation = gateway.lastUpdate
            return gateway.save()
        }
    }

    func synchronize(completion: @escaping (Bool) -> Void) {
        guard isCurrent, canSynchronize else { completion(false); return }
        let target: Int64
        switch context {
        case .device(let space):
            target = generation ?? space.lastUpdate
            guard let site = SiteData.load(siteId: space.siteId) else { completion(false); return }
            site.spaces = SpaceData.load(siteId: site.id)
            if let index = site.spaces.firstIndex(where: { $0.id == space.id }) { site.spaces[index] = space }
            space.enqueueSpaceSync(site: site, level: .promptly)
        case .gateway(let context):
            target = generation ?? context.gatewayModel.lastUpdate
            CloudSynchronizationManager.shared.addSynchronizationHandle(
                operation: .syncGateway(gateway: context.gatewayModel, node: node), level: .promptly
            )
        }
        guard NetworkRequest.shared.networkable else { completion(false); return }
        // Observe the persisted generation rather than a replaceable handle's
        // callback. Another upload can supersede this one without losing success.
        pollCloud(target: target, deadline: Date().addingTimeInterval(30), completion: completion)
    }

    private func pollCloud(target: Int64, deadline: Date, completion: @escaping (Bool) -> Void) {
        guard isCurrent, canSynchronize else { completion(false); return }
        let uploaded: Int64
        let state: CloudSynchronizationState?
        switch context {
        case .device(let space):
            uploaded = max(space.lastUploadCloudTimestamp ?? 0,
                           SpaceData.load(siteId: space.siteId, spaceId: space.id).first?.lastUploadCloudTimestamp ?? 0)
            state = CloudSynchronizationManager.shared.getSpaceCurrentSyncState(space)?.state
        case .gateway(let context):
            let gateway = context.gatewayModel
            uploaded = max(gateway.lastUploadCloudTimestamp ?? 0,
                           GatewayModel.load(siteId: gateway.siteId, macAddress: gateway.mac).first?.lastUploadCloudTimestamp ?? 0)
            state = CloudSynchronizationManager.shared.getGatewayCurrentSyncState(context.gatewayModel)?.state
        }
        let failed: Bool
        if case .failure = state { failed = true } else { failed = false }
        if let result = InformationTTLCloudConfirmation.result(
            target: target, uploaded: uploaded, failed: failed, expired: Date() >= deadline
        ) {
            completion(result)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
            pollCloud(target: target, deadline: deadline, completion: completion)
        }
    }
}
