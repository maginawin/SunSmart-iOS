import Foundation
import CryptoKit
import NordicSigMeshSDK
import SQLite
import struct SQLite.Expression

/// Scoped, read-only storage for status preparation. It does not call the legacy
/// Space/Mesh loaders, which may repair storage or migrate passwords while reading.
enum NodeSyncTopologyStorage {
    struct NodeEvidence {
        let networkKeys: Set<UInt16>
        let applicationKeys: Set<UInt16>
        let vendorBindings: Set<UInt16>?
    }
    struct KeyEvidence {
        let primary: SiteTriggerZoneTopologyPolicy.KeyReference?
        let space: SiteTriggerZoneTopologyPolicy.KeyReference?
    }
    struct Request {
        let appPath: String?
        let meshPath: String
        let region: Int
        let protection: SpaceProtectionReadRequest

        init(protection: SpaceProtectionReadRequest) {
            precondition(Thread.isMainThread)
            appPath = SunSmartDataManager.shared.db?.description
            meshPath = MeshDataManager.customDatabasePath ?? NSHomeDirectory() + "/Documents/db.sqlite3"
            region = UserData.currentServerRegion.rawValue
            self.protection = protection
        }

        func read(_ live: NodeSyncTopologySnapshot, isCancelled: () -> Bool = { false }) -> NodeSyncPreparedTopology {
            precondition(!Thread.isMainThread)
            let interval = AppPerformance.begin("SyncTopologyPrepare")
            defer { interval.end() }
            do {
                guard !isCancelled(), live.isAvailable, let appPath, !appPath.isEmpty else { return .unavailable }
                let app = try Connection(appPath, readonly: true)
                app.busyTimeout = 0.05
                let version = try app.scalar("PRAGMA data_version") as? Int64
                let spaces = try Self.spaces(app: app, meshUUID: live.meshUUID)
                guard let current = spaces.first(where: { $0.networkID == live.networkID }) else { return .unavailable }
                let groups = live.groupSnapshots()
                let zones = ProximityLightingTopologyPlanner.makeSpaceZoneSnapshots(try current.decodeZones())
                let computation = AppPerformance.begin("SyncTopologyPlan")
                let plan = ProximityLightingTopologyPolicy.makePlan(groups: groups, spaceZones: zones)
                computation.end()
                let site = try readSite(app: app, spaces: spaces, current: current, live: live, localPlan: plan, isCancelled: isCancelled)
                guard version != nil, version == (try app.scalar("PRAGMA data_version") as? Int64),
                      protection.scope.meshUUID == live.meshUUID,
                      protection.scope.networkID == live.networkID else { return .unavailable }
                let available: Bool
                if case .unavailable = site { available = false } else { available = plan.isComplete }
                return .init(groups: groups, spaceZones: zones, plan: plan, site: site, isAvailable: available)
            } catch { return .unavailable }
        }

        private struct Space {
            let id: String
            let networkID: String
            let canEdit: Bool
            let zonesData: Data?

            func decodeZones() throws -> [SpaceTriggerZone] {
                guard let zonesData else { return [] }
                let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
                return try decoder.decode([SpaceTriggerZone].self, from: zonesData)
            }
        }
        private static func spaces(app: Connection, meshUUID: String) throws -> [Space] {
            let key = SpaceData.ExpressionKey.self
            let rows = try app.prepare(Table("spaces").filter(key.siteUUID == meshUUID).order(key.createTimestamp.asc))
            // Keep other Spaces' payloads opaque until Site participation is known.
            return rows.map { row in
                let permission = Permission(rawValue: row[key.permission]) ?? .owner
                let state = SpaceData.State(rawValue: row[key.state]) ?? .normal
                return Space(id: row[key.uuid], networkID: row[key.subNetworkKey],
                             canEdit: (permission == .owner || permission == .editor)
                                && state != .waitDeleted && !row[key.requiresPasswordVerification],
                             zonesData: row[key.triggerZones])
            }
        }

        private func readSite(app: Connection, spaces: [Space], current: Space,
                              live: NodeSyncTopologySnapshot, localPlan: ProximityLightingTopologyPolicy.Plan, isCancelled: () -> Bool)
            throws -> SiteTriggerZoneTopologyReader.LocalTargetSnapshot {
            let interval = AppPerformance.begin("SyncSiteTopologyPlan")
            defer { interval.end() }
            let key = SiteData.ExpressionKey.self
            guard let site = try app.pluck(Table("sites").filter(key.uuid == live.meshUUID && key.regionType == region)) else {
                return .localOnly
            }
            guard let row = try app.pluck(Table("site_extensions").filter(
                Expression<String>("siteId") == live.meshUUID && Expression<Int>("region") == region)) else { return .localOnly }
            let state = try JSONDecoder().decode(SiteTriggerZoneState.self, from: row[Expression<Data>("payload")])
            let members = (state.data.zones ?? []).flatMap(\.displayMembers)
            let previous = (state.deviceSyncChanges ?? []).flatMap { change -> [SiteTriggerZoneDisplayMember] in
                guard case .array(let values) = change.previousMembers else { return [] }
                return values.compactMap(SiteTriggerZoneDisplayMember.init(value:))
            }
            guard (members + previous).contains(where: { $0.identity.spaceID == current.id }) else { return .localOnly }
            guard state.pending == nil, !state.conflict, !state.hasAmbiguousRemote,
                  state.rejectedRemote == nil, let confirmed = state.serverData, confirmed == state.data,
                  let serverZones = confirmed.zones,
                  confirmed.fields["schemaVersion"] == .integer(2)
                    || (confirmed.fields["schemaVersion"] == .integer(1) && serverZones.allSatisfy(\.isEmpty)),
                  let uuid = UUID(uuidString: live.meshUUID) else { return .unavailable }
            let mesh = try Connection(meshPath, readonly: true)
            mesh.busyTimeout = 0.05
            let meshVersion = try mesh.scalar("PRAGMA data_version") as? Int64
            guard let network = try mesh.pluck(Table("meshNetwork").filter(Expression<String>("meshUUID") == live.meshUUID)) else {
                return .unavailable
            }
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            guard let netData = network[Expression<Data?>("netKeys")], let appData = network[Expression<Data?>("appKeys")] else {
                return .unavailable
            }
            let netKeys = try decoder.decode([NetworkKey].self, from: netData)
            let appKeys = try decoder.decode([ApplicationKey].self, from: appData)
            let persistedKeys = Self.keys(networkKeys: netKeys, applicationKeys: appKeys, networkID: current.networkID)
            guard let primary = persistedKeys.primary else { return .unavailable }
            let provisioners = try network[Expression<Data?>("provisioners")].map {
                Set(try decoder.decode([Provisioner].self, from: $0).map(\.uuid))
            } ?? []
            var inputs: [String: NodeSyncTopologySnapshot] = [:]
            var snapshots: [SiteTriggerZoneTopologyPolicy.SpaceSnapshot] = []
            for space in spaces {
                guard !isCancelled() else { return .unavailable }
                let scope = SpaceProtectionReadRequest.Scope(account: protection.scope.account, region: protection.scope.region,
                                                            meshUUID: live.meshUUID, networkID: space.networkID)
                let safety = SpaceProtectionReadRequest(scope: scope, root: protection.root, defaults: protection.defaults).read()
                guard safety.isCurrent, !safety.isBlocked else { return .unavailable }
                let input: NodeSyncTopologySnapshot
                let plan: ProximityLightingTopologyPolicy.Plan
                if space.id == current.id {
                    input = live; plan = localPlan
                } else {
                    input = try Self.persistedSnapshot(app: app, mesh: mesh, meshUUID: live.meshUUID,
                        space: space, keys: Self.keys(networkKeys: netKeys, applicationKeys: appKeys, networkID: space.networkID),
                        provisioners: provisioners)
                    plan = ProximityLightingTopologyPolicy.makePlan(groups: input.groupSnapshots(),
                        spaceZones: ProximityLightingTopologyPlanner.makeSpaceZoneSnapshots(try space.decodeZones()))
                }
                guard input.isAvailable, input.keys.primary == primary, input.keys.space != nil else { return .unavailable }
                inputs[space.id] = input
                let devices = input.devices.map { device in
                    SiteTriggerZoneTopologyPolicy.NodeSnapshot(id: .init(spaceID: space.id, nodeUUID: device.id),
                        primaryAddress: device.primaryAddress, address: device.address, groupAddress: device.groupAddress,
                        primaryNetKey: device.evidence.networkKeys.contains(primary.networkIndex) ? .present : .absent,
                        primaryAppKey: device.evidence.applicationKeys.contains(primary.applicationIndex) ? .present : .absent,
                        primaryModelBind: device.evidence.vendorBindings.map { $0.contains(primary.applicationIndex) ? .present : .absent } ?? .unknown)
                }
                snapshots.append(.init(id: space.id, meshUUID: uuid, nodes: devices,
                    canConfigure: (SiteData.State(rawValue: site[key.state]) ?? .normal) == .normal && space.canEdit,
                    spaceKey: input.keys.space, primaryKey: primary, targetTTL: nil, localPlan: plan))
            }
            let zones = try serverZones.map { zone -> SiteTriggerZone in
                guard !isCancelled() else { throw ReadFailure.invalid }
                if zone.members != nil { return zone }
                guard case .array(let values) = zone.fields["members"], zone.hasCompleteDisplayMembers else { throw ReadFailure.invalid }
                let resolved = try values.map { value -> SiteTriggerZoneMember in
                    guard case .object(var fields) = value, fields["deviceAddress"] == nil,
                          case .integer(let trigger) = fields["triggerElementAddress"], let address = UInt16(exactly: trigger),
                          let display = SiteTriggerZoneDisplayMember(value: value), let primary = display.primaryAddress,
                          case .integer(let rawGroup) = fields["groupAddress"], let group = UInt16(exactly: rawGroup),
                          let input = inputs[display.identity.spaceID] else { throw ReadFailure.invalid }
                    let matches = input.devices.filter { $0.id == display.identity.nodeUUID }
                    guard matches.count == 1, let node = matches.first, node.primaryAddress == primary,
                          node.groupAddress == group, node.evidence.vendorBindings != nil, node.elementCount > 0,
                          Int(address) >= Int(primary), Int(address) < Int(primary) + node.elementCount else { throw ReadFailure.invalid }
                    fields["deviceAddress"] = .integer(Int64(node.address))
                    guard let member = SiteTriggerZoneMember(value: .object(fields)) else { throw ReadFailure.invalid }
                    return member
                }
                guard Set(resolved.map(\.identity)).count == resolved.count else { throw ReadFailure.invalid }
                var result = zone; result.replaceMembers(resolved); return result
            }
            guard meshVersion != nil, meshVersion == (try mesh.scalar("PRAGMA data_version") as? Int64) else { return .unavailable }
            let plan = SiteTriggerZoneTopologyPolicy.makePlan(spaces: snapshots, zones: zones)
            return plan.canPreviewTasks ? .site(spaceID: current.id, plan: plan) : .unavailable
        }

        private struct StoredNodeKey: Decodable { let index: UInt16 }
        private static func persistedSnapshot(app: Connection, mesh: Connection, meshUUID: String,
                                              space: Space, keys: KeyEvidence, provisioners: Set<UUID>) throws -> NodeSyncTopologySnapshot {
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            var sdkGroups: [Group] = []
            var groups: [NodeSyncTopologySnapshot.GroupValue] = []
            for row in try mesh.prepare(Table("groups").filter(Expression<String>("meshUUID") == meshUUID
                && Expression<String?>("subnetworkId") == space.networkID)) {
                guard let address = UInt16(exactly: row[Expression<Int>("groupAddress")]) else { throw ReadFailure.invalid }
                let group = try Group(name: row[Expression<String>("name")], address: MeshAddress(address))
                group.isVirtual = row[Expression<Bool>("isVirtual")]
                sdkGroups.append(group)
                guard !group.isVirtual else { continue }
                guard let info = GroupInfo.load(meshUUID: meshUUID, address: address, subnetworkId: space.networkID,
                    database: app, includeTemplates: false), !info.profileLoadFailed, !info.topologyLoadFailed else { throw ReadFailure.invalid }
                groups.append(.init(address: address,
                    eligible: info.profile.type == .proximityLighting || info.profile.type == .proximityLightingWithPhotocell,
                    relay: info.profile.proximityLightingNumber,
                    paths: info.proximityLightingPath?.paths.map { $0.items.map(\.address) } ?? [],
                    zones: info.proximityLightingPath?.zones.map(\.addresses) ?? []))
            }
            var devices: [NodeSyncTopologySnapshot.Device] = []
            for row in try mesh.prepare(Table("nodes").filter(Expression<String>("meshUUID") == meshUUID
                && Expression<String?>("subnetworkId") == space.networkID)) {
                guard let uuid = UUID(uuidString: row[Expression<String>("UUID")]) else { throw ReadFailure.invalid }
                guard !provisioners.contains(uuid), !row[Expression<Bool>("configComplete")] else { continue }
                guard let primary = UInt16(exactly: row[Expression<Int>("unicastAddress")]),
                      let data = row[Expression<Data?>("elements")] else { throw ReadFailure.invalid }
                let elements = try decoder.decode([Element].self, from: data)
                var subscriptions = Set<Address>(), membership: Address?, vendorAddress: Address?, vendorBindings: Set<UInt16>?
                for (offset, element) in elements.enumerated() {
                    for model in element.models {
                        for group in sdkGroups where model.isSubscribed(to: group.address) {
                            subscriptions.insert(group.address.address)
                            if membership == nil && NodeSyncTopologyCapture.isMembershipGroup(group) { membership = group.address.address }
                        }
                        if vendorAddress == nil, model.modelId == .vensorServerModelId {
                            guard let address = UInt16(exactly: Int(primary) + offset) else { throw ReadFailure.invalid }
                            vendorAddress = address
                            // Model has no network here. Decode the persisted bindings
                            // via Codable, rather than the network-dependent key getter.
                            struct Binding: Decodable { let bind: [UInt16] }
                            vendorBindings = Set(try decoder.decode(Binding.self, from: JSONEncoder().encode(model)).bind)
                        }
                    }
                }
                let net = try decoder.decode([StoredNodeKey].self, from: row[Expression<Data>("netKeys")])
                let apps = try decoder.decode([StoredNodeKey].self, from: row[Expression<Data>("appKeys")])
                devices.append(.init(id: uuid, primaryAddress: primary, address: vendorAddress ?? primary,
                    elementCount: elements.count, groupAddress: membership, subscriptions: subscriptions,
                    exited: row[Expression<Int>("groupState")] == Node.GroupState.exitFailure.rawValue,
                    evidence: .init(networkKeys: Set(net.map(\.index)), applicationKeys: Set(apps.map(\.index)), vendorBindings: vendorBindings)))
            }
            return .init(meshUUID: meshUUID, networkID: space.networkID, groups: groups, devices: devices, isAvailable: true, keys: keys)
        }
        private enum ReadFailure: Error { case invalid }

        fileprivate static func keys(networkKeys: [NetworkKey], applicationKeys: [ApplicationKey], networkID: String) -> KeyEvidence {
            func pair(_ candidates: [NetworkKey]) -> SiteTriggerZoneTopologyPolicy.KeyReference? {
                guard candidates.count == 1, let key = candidates.first,
                      key.phase == .normalOperation, key.oldKey == nil else { return nil }
                let apps = applicationKeys.filter { $0.boundNetworkKeyIndex == key.index }
                guard apps.count == 1, let app = apps.first, app.oldKey == nil else { return nil }
                var data = Data("SiteZoneKeyPairV1".utf8); data.append(key.key); data.append(app.key)
                return .init(networkIndex: key.index, applicationIndex: app.index,
                             materialIdentity: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
            }
            return .init(primary: pair(networkKeys.filter(\.isPrimary)),
                         space: pair(networkKeys.filter { $0.networkId.hex.caseInsensitiveCompare(networkID) == .orderedSame }))
        }
    }

    static func nodeEvidence(_ node: Node) -> NodeEvidence {
        .init(networkKeys: Set(node.networkKeys.map(\.index)), applicationKeys: Set(node.applicationKeys.map(\.index)),
              vendorBindings: node.sunricherVendorModel.map { Set($0.boundApplicationKeys.map(\.index)) })
    }
    static func keyEvidence(network: MeshNetwork, networkID: String) -> KeyEvidence {
        Request.keys(networkKeys: network.networkKeys, applicationKeys: network.applicationKeys, networkID: networkID)
    }
}
