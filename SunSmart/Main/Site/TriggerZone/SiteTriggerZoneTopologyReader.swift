import Foundation
import CryptoKit
import NordicSigMeshSDK

/// Builds a read-only, all-Space snapshot for Site Zone preflight. This never changes
/// the active Mesh context, installs a Key, or sends a device command.
enum SiteTriggerZoneTopologyReader {
    private typealias Observation = SiteTriggerZoneSyncPlanningPolicy.Observation

    private struct Snapshot {
        let topology: SiteTriggerZoneTopologyPolicy.Plan
        let observations: [Observation]
        let spaces: [SiteTriggerZoneTopologyPolicy.SpaceSnapshot]
        let zones: [SiteTriggerZone]
    }
    enum ReadError: Error, Equatable {
        case unconfirmedCloud
        case unsupportedSchema
        case invalidCurrentMembers(UUID)
        case missingSiteMesh
        case ambiguousPrimaryKey
        case ambiguousSpaceKey(String)
        case keyRefreshInProgress(String)
        case inconsistentPrimaryKey(String)
        case insufficientSpacePermission(String)
        case unavailableSpace(String)
        case staleDeviceChange(UUID)
        case invalidPreviousMembers(UUID)

        var blocker: SiteTriggerZoneSyncPlanningPolicy.Blocker {
            switch self {
            case .unconfirmedCloud: return .cloud
            case .unsupportedSchema: return .schema
            case .invalidCurrentMembers: return .members
            case .insufficientSpacePermission: return .permission
            case .missingSiteMesh, .unavailableSpace: return .mesh
            case .ambiguousPrimaryKey, .ambiguousSpaceKey,
                 .keyRefreshInProgress, .inconsistentPrimaryKey: return .keys
            case .staleDeviceChange, .invalidPreviousMembers: return .previousTarget
            }
        }
    }

    /// Legacy triggerElementAddress identifies the source element, not the
    /// normalized Vendor Model address. Resolve it against the current Node
    /// before allowing an edit; the original server fields remain untouched.
    static func resolvedMembers(of zone: SiteTriggerZone, site: SiteData) -> [SiteTriggerZoneMember]? {
        if let members = zone.members { return members }
        guard case .array(let values) = zone.fields["members"],
              zone.hasCompleteDisplayMembers else { return nil }
        var members: [SiteTriggerZoneMember] = []
        for value in values {
            guard case .object(var fields) = value,
                  fields["deviceAddress"] == nil,
                  case .integer(let trigger) = fields["triggerElementAddress"],
                  let triggerAddress = UInt16(exactly: trigger),
                  let display = SiteTriggerZoneDisplayMember(value: value),
                  let primaryAddress = display.primaryAddress,
                  case .integer(let group) = fields["groupAddress"],
                  let groupAddress = UInt16(exactly: group),
                  let space = site.spaces.first(where: { $0.id == display.identity.spaceID }),
                  space.siteId == site.id, space.meshUUID == site.meshUUID,
                  let network = ProximityLightingTopologyContext.network(for: space) else { return nil }
            let address = withExtendedLifetime(network) { () -> UInt16? in
                let matches = ProximityLightingTopologyContext.realNodes(in: network)
                    .filter { $0.uuid == display.identity.nodeUUID }
                guard matches.count == 1, let node = matches.first,
                      node.primaryUnicastAddress == primaryAddress,
                      node.group?.address.address == groupAddress,
                      !node.elements.isEmpty,
                      Int(triggerAddress) >= Int(primaryAddress),
                      Int(triggerAddress) < Int(primaryAddress) + node.elements.count,
                      node.sunricherVendorModel != nil else { return nil }
                return ProximityLightingTopologyPlanner.normalizedAddress(for: node)
            }
            guard let address else { return nil }
            fields["deviceAddress"] = .integer(Int64(address))
            guard let member = SiteTriggerZoneMember(value: .object(fields)) else { return nil }
            members.append(member)
        }
        return Set(members.map(\.identity)).count == members.count ? members : nil
    }

    /// The inventory is scoped to a readable, authorized Space. Offline nodes
    /// remain present; unavailable Spaces never become empty inventories.
    static func cleanupClassifier(site: SiteData) -> (SiteJSONValue) -> SiteTriggerZoneReferenceCleanup.Classification {
        struct Inventory {
            let network: MeshNetwork
            let nodes: [Node]
            let plan: ProximityLightingTopologyPlanner.Plan
        }
        var inventories: [String: Inventory] = [:]
        var inspectedSpaces = Set<String>()
        // Empty Zones need no Mesh load. Resolve only referenced Spaces, once per
        // classifier, including failed reads so they remain conservatively unknown.
        func inventory(for spaceID: String) -> Inventory? {
            if let cached = inventories[spaceID] { return cached }
            guard inspectedSpaces.insert(spaceID).inserted,
                  let space = site.spaces.first(where: { $0.id == spaceID }),
                  space.canEditing, !SpaceConfigurationSafety.isBlocked(space),
                  space.siteId == site.id, space.meshUUID == site.meshUUID,
                  let network = ProximityLightingTopologyContext.network(for: space) else { return nil }
            ProximityLightingTopologyContext.loadGroupInfo(network: network, space: space)
            let preparation = ProximityLightingLifecycleCoordinator.begin(space: space,
                groups: network.groups.filter { !$0.isVirtual },
                nodes: ProximityLightingTopologyContext.realNodes(in: network), network: network).prepare()
            guard preparation.isValid, !preparation.normalized.hasDestructiveRepairs,
                  let preview = ProximityLightingLifecycleCoordinator.preview(preparation) else { return nil }
            let loaded = Inventory(network: network,
                nodes: ProximityLightingTopologyContext.realNodes(in: network), plan: preview.plan)
            inventories[spaceID] = loaded
            return loaded
        }
        return { value in
            guard let display = SiteTriggerZoneDisplayMember(value: value),
                  let primary = display.primaryAddress, case .object(let fields) = value,
                  case .integer(let rawGroup) = fields["groupAddress"],
                  let groupAddress = UInt16(exactly: rawGroup),
                  case .integer(let rawDevice) = fields["deviceAddress"] ?? fields["triggerElementAddress"],
                  let address = UInt16(exactly: rawDevice), address > 0, address < 0x8000,
                  let inventory = inventory(for: display.identity.spaceID) else { return .unknown }
            let matches = inventory.nodes.filter { $0.uuid == display.identity.nodeUUID }
            guard matches.count <= 1 else { return .unknown }
            guard let node = matches.first, node.primaryUnicastAddress == primary else { return .obsolete }
            guard node.groupState != .exitFailure, node.group?.address.address == groupAddress,
                  let group = inventory.network.groups.first(where: { !$0.isVirtual && $0.address.address == groupAddress }),
                  ProximityLightingLifecycleCoordinator.isEligible(group.info.profile.type) else { return .obsolete }
            let normalized = ProximityLightingTopologyPlanner.normalizedAddress(for: node)
            if fields["deviceAddress"] != nil, address != normalized { return .obsolete }
            if fields["deviceAddress"] == nil,
               !(Int(primary)..<(Int(primary) + node.elements.count)).contains(Int(address)) { return .obsolete }
            guard inventory.plan.target(for: normalized).enabled == true else { return .obsolete }
            return .valid
        }
    }

    static func mergedLocalTarget(for node: Node, local: ProximityLightingTopologyPolicy.Target)
        -> ProximityLightingTopologyPolicy.Target? {
        guard let network = node.network,
              let site = SiteData.load(siteId: network.uuid.uuidString) else { return local }
        guard let state = try? SiteTriggerZoneStore.load(site) else { return nil }
        let allMembers = (state.data.zones ?? []).flatMap(\.displayMembers)
        let previousMembers = (state.deviceSyncChanges ?? []).flatMap { change -> [SiteTriggerZoneDisplayMember] in
            guard case .array(let values) = change.previousMembers else { return [] }
            return values.compactMap(SiteTriggerZoneDisplayMember.init(value:))
        }
        // A Site Zone can change forwarding for every node in a participating Space.
        guard let space = site.spaces.first(where: { $0.meshNetworkId == node.subNetworkId }),
              (allMembers + previousMembers).contains(where: { $0.identity.spaceID == space.id }) else { return local }
        guard case .success(let plan) = makePlan(site: site, state: state), plan.canPreviewTasks,
              let target = plan.targets[.init(spaceID: space.id, nodeUUID: node.uuid)] else { return nil }
        return .init(enabled: target.enabled, relayNumber: target.relayNumber,
                     neighborAddresses: target.neighborAddresses)
    }

    static func makePlan(site: SiteData, state: SiteTriggerZoneState)
        -> Result<SiteTriggerZoneTopologyPolicy.Plan, ReadError> {
        read(site: site, state: state).map(\.topology)
    }

    static func makeRecoveryPlan(site: SiteData, state: SiteTriggerZoneState)
        -> Result<SiteTriggerZoneSyncPlanningPolicy.Plan, ReadError> {
        read(site: site, state: state).map { snapshot in
            let plan = SiteTriggerZoneSyncPlanningPolicy.makeRecoveryPlan(
                target: snapshot.topology, observations: snapshot.observations,
                siteSpaceOrder: site.spaces.map(\.id)
            )
            let candidate = SiteTriggerZoneSyncPlanningPolicy.Plan(
                spaces: plan.spaces, issues: plan.issues,
                targetFingerprint: SiteTriggerZoneSyncPlanningPolicy.targetFingerprint(
                    siteID: site.id, topology: snapshot.topology))
            return SiteTriggerZoneSyncPlanningPolicy.withTransportCandidates(
                candidate, spaces: snapshot.spaces)
        }
    }

    /// Tentative old/new Site diff. It retains every Space and relationship;
    /// device evidence, explicit TTL and execution receipts remain separate.
    static func makeDifferencePlan(site: SiteData, state: SiteTriggerZoneState,
                                   selectedZoneID: UUID)
        -> Result<SiteTriggerZoneSyncPlanningPolicy.Plan, ReadError> {
        read(site: site, state: state).flatMap { snapshot in
            let changes = state.deviceSyncChanges ?? []
            guard let rawZones = state.serverData?.zones else { return .failure(.unconfirmedCloud) }
            let result = SiteTriggerZoneSyncPlanningPolicy.reconstructPreviousZones(
                confirmedZones: rawZones, changes: changes,
                resolve: { resolvedMembers(of: $0, site: site) })
            let historicalZones: [SiteTriggerZone]
            switch result {
            case .failure(.staleTarget(let id)):
                return .failure(.staleDeviceChange(id))
            case .failure(.duplicateChange(let id)), .failure(.invalidPreviousMembers(let id)):
                return .failure(.invalidPreviousMembers(id))
            case .success(let zones):
                historicalZones = zones
            }
            let classify = cleanupClassifier(site: site)
            if historicalZones.contains(where: { SiteTriggerZoneReferenceCleanup.clean($0, classify: classify) != $0 }) {
                // Old members may no longer have Nodes or an eligible Profile.
                // Reconcile every surviving device from its observed state to
                // the complete current Site target, preserving peer removals.
                return makeRecoveryPlan(site: site, state: state)
            }
            var previousZones: [SiteTriggerZone] = []
            for zone in historicalZones {
                guard let members = resolvedMembers(of: zone, site: site) else {
                    return .failure(.invalidPreviousMembers(zone.zoneId))
                }
                var resolved = zone
                resolved.replaceMembers(members)
                previousZones.append(resolved)
            }
            let previous = SiteTriggerZoneTopologyPolicy.makePlan(
                spaces: snapshot.spaces, zones: previousZones)
            let plan = SiteTriggerZoneSyncPlanningPolicy.makePlan(
                previous: previous, target: snapshot.topology,
                selectedZoneID: selectedZoneID, previousZones: previousZones,
                confirmedZones: snapshot.zones, siteSpaceOrder: site.spaces.map(\.id)
            )
            let candidate = SiteTriggerZoneSyncPlanningPolicy.Plan(
                spaces: plan.spaces, issues: plan.issues,
                targetFingerprint: SiteTriggerZoneSyncPlanningPolicy.targetFingerprint(
                    siteID: site.id, topology: snapshot.topology))
            let scoped = SiteTriggerZoneSyncPlanningPolicy.withTransportCandidates(
                candidate, spaces: snapshot.spaces)
            return .success(SiteTriggerZoneSyncPlanningPolicy.requiringDeviceObservations(
                scoped, observations: snapshot.observations))
        }
    }

    private static func read(site: SiteData, state: SiteTriggerZoneState)
        -> Result<Snapshot, ReadError> {
        guard state.pending == nil, !state.conflict, !state.hasAmbiguousRemote,
              state.rejectedRemote == nil,
              let serverData = state.serverData, serverData == state.data else {
            return .failure(.unconfirmedCloud)
        }
        guard let serverZones = serverData.zones else { return .failure(.unsupportedSchema) }
        guard serverData.fields["schemaVersion"] == .integer(2)
            || (serverData.fields["schemaVersion"] == .integer(1)
                && serverZones.allSatisfy(\.isEmpty)) else {
            return .failure(.unsupportedSchema)
        }
        var zones: [SiteTriggerZone] = []
        for zone in serverZones {
            guard let members = resolvedMembers(of: zone, site: site) else {
                return .failure(.invalidCurrentMembers(zone.zoneId))
            }
            var resolved = zone
            resolved.replaceMembers(members)
            zones.append(resolved)
        }
        guard let meshUUID = UUID(uuidString: site.meshUUID) else { return .failure(.missingSiteMesh) }
        guard let primaryNetwork = MeshNetwork.load(meshUUID: site.meshUUID,
                                                    subnetworkId: site.meshNetworkId),
              primaryNetwork.uuid == meshUUID else { return .failure(.missingSiteMesh) }
        let primaryNetworkKeys = primaryNetwork.networkKeys.filter(\.isPrimary)
        guard primaryNetworkKeys.count == 1 else { return .failure(.ambiguousPrimaryKey) }
        let primaryAppKeys = primaryNetwork.applicationKeys.filter {
            $0.boundNetworkKeyIndex == primaryNetworkKeys[0].index
        }
        guard primaryAppKeys.count == 1 else { return .failure(.ambiguousPrimaryKey) }
        let primaryNetKey = primaryNetworkKeys[0]
        let primaryAppKey = primaryAppKeys[0]
        guard primaryNetKey.phase == .normalOperation,
              primaryNetKey.oldKey == nil, primaryAppKey.oldKey == nil else {
            return .failure(.keyRefreshInProgress("primary"))
        }
        let primaryKeyReference = keyReference(networkKey: primaryNetKey,
                                               applicationKey: primaryAppKey)

        var snapshots: [SiteTriggerZoneTopologyPolicy.SpaceSnapshot] = []
        var observations: [Observation] = []
        for space in site.spaces {
            guard space.siteId == site.id, space.meshUUID == site.meshUUID else {
                return .failure(.unavailableSpace(space.id))
            }
            guard let network = ProximityLightingTopologyContext.network(for: space),
                  network.uuid == meshUUID else {
                return .failure(space.canEditing ? .unavailableSpace(space.id)
                                                 : .insufficientSpacePermission(space.id))
            }
            let spacePrimaryNetKeys = network.networkKeys.filter {
                $0.index == primaryNetKey.index
            }
            let spacePrimaryAppKeys = network.applicationKeys.filter {
                $0.index == primaryAppKey.index
            }
            guard spacePrimaryNetKeys.count == 1, spacePrimaryAppKeys.count == 1,
                  spacePrimaryAppKeys[0].boundNetworkKeyIndex == primaryNetKey.index,
                  spacePrimaryNetKeys[0].phase == .normalOperation,
                  spacePrimaryNetKeys[0].oldKey == nil,
                  spacePrimaryAppKeys[0].oldKey == nil,
                  keyReference(networkKey: spacePrimaryNetKeys[0],
                               applicationKey: spacePrimaryAppKeys[0]) == primaryKeyReference else {
                return .failure(.inconsistentPrimaryKey(space.id))
            }
            let spaceNetKeys = network.networkKeys.filter {
                $0.networkId.hex.caseInsensitiveCompare(space.meshNetworkId) == .orderedSame
            }
            guard spaceNetKeys.count == 1 else { return .failure(.ambiguousSpaceKey(space.id)) }
            let spaceAppKeys = network.applicationKeys.filter {
                $0.boundNetworkKeyIndex == spaceNetKeys[0].index
            }
            guard spaceAppKeys.count == 1 else { return .failure(.ambiguousSpaceKey(space.id)) }
            guard spaceNetKeys[0].phase == .normalOperation,
                  spaceNetKeys[0].oldKey == nil, spaceAppKeys[0].oldKey == nil else {
                return .failure(.keyRefreshInProgress(space.id))
            }
            let spaceKeyReference = keyReference(networkKey: spaceNetKeys[0],
                                                 applicationKey: spaceAppKeys[0])
            let snapshot = withExtendedLifetime(network) { () -> SiteTriggerZoneTopologyPolicy.SpaceSnapshot? in
                let groups = network.groups.filter { !$0.isVirtual && $0.subNetworkId == space.meshNetworkId }
                let nodes = ProximityLightingTopologyContext.realNodes(in: network)
                guard ProximityLightingTopologyContext.isAvailable(space: space, network: network,
                                                                    groups: groups, nodes: nodes) else { return nil }
                let localPlan = ProximityLightingTopologyPlanner.makePlan(
                    groups: groups, nodes: nodes, spaceTriggerZones: space.triggerZones)
                let deviceSnapshots = nodes.map { node in
                    let vendorModel = node.sunricherVendorModel
                    return SiteTriggerZoneTopologyPolicy.NodeSnapshot(
                        id: .init(spaceID: space.id, nodeUUID: node.uuid),
                        primaryAddress: node.primaryUnicastAddress,
                        address: ProximityLightingTopologyPlanner.normalizedAddress(for: node),
                        groupAddress: node.group?.address.address,
                        primaryNetKey: node.networkKeys.contains(where: { $0.index == primaryNetKey.index }) ? .present : .absent,
                        primaryAppKey: node.applicationKeys.contains(where: { $0.index == primaryAppKey.index }) ? .present : .absent,
                        primaryModelBind: vendorModel.map { $0.isBoundTo(primaryAppKey) ? .present : .absent } ?? .unknown
                    )
                }
                #if DEBUG
                for (node, primary) in zip(nodes, deviceSnapshots) {
                    let address = ProximityLightingTopologyPlanner.normalizedAddress(for: node)
                    print("[SiteZoneSync][cache-observation] space=\(space.id) node=\(node.uuid) address=\(address) enabled=\(String(describing: node.proximityLightingEnabled)) relay=\(String(describing: node.proximityLightingRelayCount)) neighbors=\(String(describing: node.proximityLightingNeighborAddresses)) primaryNetKey=\(primary.primaryNetKey) primaryAppKey=\(primary.primaryAppKey) primaryModelBind=\(primary.primaryModelBind) evidence=cache ttl=unknown")
                }
                #endif
                observations.append(contentsOf: nodes.map { node in
                    .init(deviceID: .init(spaceID: space.id, nodeUUID: node.uuid),
                          address: ProximityLightingTopologyPlanner.normalizedAddress(for: node),
                          enabled: node.proximityLightingEnabled,
                          relayNumber: node.proximityLightingRelayCount,
                          neighborAddresses: node.proximityLightingNeighborAddresses,
                          forwardKey: nil, ttl: nil, evidence: .cache,
                          forwardKeyReference: nil)
                })
                var snapshot = SiteTriggerZoneTopologyPolicy.SpaceSnapshot(
                    id: space.id, meshUUID: network.uuid,
                    nodes: deviceSnapshots, spaceKey: spaceKeyReference,
                    primaryKey: primaryKeyReference, targetTTL: nil,
                    localPlan: localPlan)
                snapshot.canConfigure = site.state == .normal && space.canEditing
                return snapshot
            }
            guard let snapshot else { return .failure(.unavailableSpace(space.id)) }
            snapshots.append(snapshot)
        }
        return .success(.init(
            topology: SiteTriggerZoneTopologyPolicy.makePlan(spaces: snapshots, zones: zones),
            observations: observations, spaces: snapshots, zones: zones
        ))
    }

    private static func keyReference(networkKey: NetworkKey, applicationKey: ApplicationKey)
        -> SiteTriggerZoneTopologyPolicy.KeyReference {
        var pair = Data("SiteZoneKeyPairV1".utf8)
        pair.append(networkKey.key)
        pair.append(applicationKey.key)
        let identity = SHA256.hash(data: pair).map { String(format: "%02x", $0) }.joined()
        return .init(networkIndex: networkKey.index, applicationIndex: applicationKey.index,
                     materialIdentity: identity)
    }
}
