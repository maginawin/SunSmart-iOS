import Foundation
import NordicSigMeshSDK

extension Node {
    func needsSceneRemoval(_ number: SceneNumber) -> Bool {
        guard let model = sceneSetupModel else { return false }
        return SceneDeleteCapability.needsRemoval(observed: model.parentElement?.observedSceneRegister,
            number: number, hasCachedData: sceneExecuteDatas.contains { $0.sceneNumber == number })
    }
}

/// One policy for scene editing, group membership and device restoration.
/// Observations belong to the live Element instance, never to imported data.
enum SceneCapacity {
    static func validSceneAllocation(_ data: [String: Any]) -> Bool {
        func decode(_ raw: Any?, bounds: ClosedRange<Int>, sceneKeys: Bool = false) -> Set<UInt16>? {
            if let values = raw as? [Int] {
                guard values.allSatisfy(bounds.contains), Set(values).count == values.count else { return nil }
                return Set(values.map(UInt16.init))
            }
            guard let ranges = raw as? [[String: Any]] else { return nil }
            var numbers = Set<UInt16>()
            for range in ranges {
                guard let lowText = (range["lowAddress"] ?? (sceneKeys ? range["firstScene"] : nil)) as? String,
                      let highText = (range["highAddress"] ?? (sceneKeys ? range["lastScene"] : nil)) as? String,
                      let low = UInt16(lowText, radix: 16), let high = UInt16(highText, radix: 16),
                      low <= high, bounds.contains(Int(low)), bounds.contains(Int(high)) else { return nil }
                for number in low...high where !numbers.insert(number).inserted { return nil }
            }
            return numbers
        }
        // Mirror the established full Provisioner response, including legacy
        // scene dictionaries and subsequent allocations encoded as integer lists.
        guard decode(data["allocatedUnicastRange"], bounds: 1...0x7FFF) != nil,
              decode(data["allocatedGroupRange"], bounds: 0xC000...0xFEFF) != nil,
              let scenes = decode(data["allocatedSceneRange"], bounds: 1...0xFEFF, sceneKeys: true),
              !scenes.isEmpty else { return false }
        if let extra = data["allocatedUnicastAddress"], decode(extra, bounds: 1...0x7FFF) == nil { return false }
        return true
    }

    struct Failure: Error {
        let devices: [String]
        let unknown: Bool
    }

    static func intendedScenes(on node: Node, group editedGroup: Group? = nil,
                               members: [Node] = [], addingMembers: [Node] = [],
                               scene: Scene? = nil, sceneGroups: [Group] = [],
                               sceneSnapshot: SceneTargetSnapshot? = nil) -> Set<SceneNumber> {
        let manager = MeshNetworkManager.instance
        var result = Set<SceneNumber>()
        for group in manager.groups {
            let nodes = group == editedGroup ? members : group.nodes
            guard nodes.contains(node) else { continue }
            let active = node.groupState != .exitFailure || (group == editedGroup && addingMembers.contains(node))
            for data in group.info.sceneExecuteDatas {
                if data.state == .waitDelete || (active && data.state == .normal && data.sceneNumber != scene?.number) {
                    result.insert(data.sceneNumber)
                }
            }
            if active, let scene, sceneGroups.contains(group) { result.insert(scene.number) }
        }
        // Fixed device membership and cleanup reservations do not follow Group.nodes.
        for stored in manager.scenes where stored.info.configuration != nil {
            if let snapshot = try? SceneTargetResolver.resolve(scene: stored),
               snapshot.reservesScene(on: node) { result.insert(stored.number) }
        }
        if let sceneSnapshot, sceneSnapshot.reservesScene(on: node) {
            // Zero is only a preflight placeholder before T04 allocates a legal ID.
            result.insert(sceneSnapshot.number ?? 0)
        }
        return result
    }

    static func validateTopology(group: Group? = nil, members: [Node] = [], addingMembers: [Node] = [],
                                 scene: Scene? = nil, sceneGroups: [Group] = [],
                                 sceneSnapshot: SceneTargetSnapshot? = nil) throws {
        try validateConfigurations(sceneSnapshot: sceneSnapshot)
        let nodes = MeshNetworkManager.instance.realNodes + members
        var visited = Set<UUID>()
        var full: [String] = [], unknown: [String] = []
        for node in nodes where visited.insert(node.uuid).inserted && node.sceneSetupModel != nil {
            let previous = intendedScenes(on: node)
            let desired = intendedScenes(on: node, group: group, members: members, addingMembers: addingMembers,
                                         scene: scene, sceneGroups: sceneGroups, sceneSnapshot: sceneSnapshot)
            do {
                try SceneCapacityPolicy.validate(previous: previous, desired: desired,
                    observed: node.sceneSetupModel?.parentElement?.observedSceneRegister)
            } catch SceneCapacityPolicy.Failure.unknown { unknown.append(label(node)) }
            catch { full.append(label(node)) }
        }
        if !full.isEmpty { throw Failure(devices: full, unknown: false) }
        if !unknown.isEmpty { throw Failure(devices: unknown, unknown: true) }
    }

    static func label(_ node: Node) -> String { "\(node.name ?? "") (\(node.primaryUnicastAddress.hex))" }

    static func showFailure(_ error: Error) {
        guard let failure = error as? Failure else {
            XWHUDManager.showErrorTipHUD("save_failure".localizedString)
            return
        }
        let key = failure.unknown ? "scene_capacity_unknown" : "scene_capacity_exceeded"
        SRAlertView(message: String(format: key.localizedString, failure.devices.joined(separator: "\n")),
                    actions: [SRAlertAction(title: "ok".localizedString, actionHandler: nil)]).show()
    }

    static func unknownNodes(_ nodes: [Node]) -> [Node] {
        var seen = Set<UUID>()
        return nodes.filter {
            seen.insert($0.uuid).inserted && $0.sceneSetupModel != nil &&
                $0.sceneSetupModel?.parentElement?.observedSceneRegister == nil
        }
    }

    static func nodesRequiringRead(group: Group? = nil, members: [Node] = [], addingMembers: [Node] = [],
                                   scene: Scene? = nil, sceneGroups: [Group] = [],
                                   sceneSnapshot: SceneTargetSnapshot? = nil) -> [Node] {
        unknownNodes(MeshNetworkManager.instance.realNodes + members).filter { node in
            let desired = intendedScenes(on: node, group: group, members: members, addingMembers: addingMembers,
                                         scene: scene, sceneGroups: sceneGroups, sceneSnapshot: sceneSnapshot)
            return !desired.subtracting(intendedScenes(on: node)).isEmpty
        }
    }

    /// Read only the ordinary target Register. It does not synthesize Scenes.
    static func readUnknownState(nodes: [Node], completion: @escaping (Bool) -> Void) {
        let unknown = unknownNodes(nodes)
        guard !unknown.isEmpty else { completion(true); return }
        let manager = MeshNetworkManager.instance
        guard let network = manager.meshNetwork, !MeshProxyMessageCommand.shared.isBusy,
              MeshLibManager.manager.isMeshNetworkConnected else { completion(false); return }
        let networkID = manager.currentNetworkKey.networkId.hex
        let models = unknown.compactMap { $0.sceneSetupModel }
        let handles = models.map { model -> MeshMessageHandle in
            let handle = MeshMessageHandle(message: SceneRegisterGet(), model: model)
            handle.continuous = false
            return handle
        }
        MeshProxyMessageCommand.shared.addMessage(messageHandles: handles, progressBack: nil,
            successfulBack: { _, _ in }, failedBack: { _ in }) { results in
                DispatchQueue.main.async {
                    let current = manager.meshNetwork === network && manager.currentNetworkKey.networkId.hex == networkID
                        && unknown.allSatisfy { network.node(withAddress: $0.primaryUnicastAddress) === $0 }
                    completion(current && results.count == handles.count && results.allSatisfy(\.isSuccessful)
                        && unknownNodes(unknown).isEmpty)
                }
            }
    }

    static func canAddDevice(to group: Group, node: Node) -> Bool {
        guard node.sceneSetupModel != nil else { return true }
        let desired = Set(group.info.sceneExecuteDatas.filter { $0.state == .normal }.map(\.sceneNumber))
        // Provisioning can reveal capabilities only after joining the network.
        // Unknown physical state is read again at the configuration boundary.
        let observed = node.sceneSetupModel?.parentElement?.observedSceneRegister
        guard desired.count <= 16, observed.map({ $0.union(desired).count <= 16 }) ?? true else {
            showFailure(Failure(devices: [label(node)], unknown: false)); return false
        }
        return true
    }

    static func validateStore(node: Node, number: SceneNumber) throws {
        try validateConfigurations()
        guard let element = node.sceneSetupModel?.parentElement else { return }
        if element.observedSceneRegister?.contains(number) == true { return }
        let desired = intendedScenes(on: node).union([number])
        do {
            // At execution time an already persisted intent is not proof that it
            // fits physically. Use the live Register as the previous set.
            try SceneCapacityPolicy.validate(previous: element.observedSceneRegister ?? [], desired: desired,
                                             observed: element.observedSceneRegister)
        } catch {
            #if DEBUG
            print("[SceneSync] stage=capacityRejected scene=\(number) address=\(node.primaryUnicastAddress) unknown=\(error as? SceneCapacityPolicy.Failure == .unknown)")
            #endif
            throw Failure(devices: [label(node)], unknown: error as? SceneCapacityPolicy.Failure == .unknown)
        }
    }

    static func validateConfigurations(sceneSnapshot: SceneTargetSnapshot? = nil) throws {
        let manager = MeshNetworkManager.instance
        for scene in manager.scenes where scene.info.configuration != nil || scene.info.configurationLoadFailed {
            _ = try SceneTargetResolver.resolve(scene: scene)
        }
        if let snapshot = sceneSnapshot {
            guard snapshot.scope.meshUUID == manager.meshNetwork?.uuid.uuidString,
                  snapshot.scope.networkID == manager.currentNetworkKey.networkId.hex,
                  !snapshot.unresolved.contains(where: { $0.action == .write }),
                  snapshot.targets.allSatisfy({ target in
                      manager.realNodes.contains { $0 === target.node }
                          && target.node.timedSchedulerIdentity.flatMap { try? SceneConfiguration.identity($0) } == target.identity
                  }) else { throw SceneTargetResolver.Failure.invalidConfiguration }
        }
    }
}
