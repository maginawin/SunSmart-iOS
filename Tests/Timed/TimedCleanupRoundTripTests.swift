import Foundation
import SQLite

extension Run {
    static func timedPayload(_ schedules: [Schedule], node: Node, version: Int = 3) throws -> [String: Any] {
        let nodePayload: [String: Any] = ["uuid": node.uuid.uuidString, "unicastAddress": node.primaryUnicastAddress.hex,
            "deviceKey": node.deviceKey!.hex, "groupState": 0,
            "elements": [["index": 0, "models": [["modelId": "1206", "subscribe": []], ["modelId": "1207", "subscribe": []]]]]]
        return ["nodes": [nodePayload], "groups": [], "scenes": [],
            "spaceData": ["timedSchemaVersion": version],
            "schedules": try JSONSerialization.jsonObject(with: JSONEncoder().encode(schedules))]
    }

    static func timedCleanupRoundTrip(path: String) throws {
        let manager = MeshNetworkManager.instance
        let oldNetwork = manager.meshNetwork
        manager.meshNetwork = MeshNetworkManager.Network()
        defer { manager.meshNetwork = oldNetwork; manager.schedules = []; manager.realNodes = [] }
        let node = Node(1), mesh = manager.meshNetwork!.uuid.uuidString, network = manager.currentNetworkKey.networkId.hex
        let schedule = Schedule(id: 0, name: "Schedule 1", enabled: true, nodeAddresses: [1])
        let route = TimedSchedulerActionAddress(autoOn: "0001", off: "0001", recall: "0001")
        for state: TimedSchedulerNodeSlot.State in [.pendingApply, .synced, .pendingRemoval] {
            schedule.nodeSlots = [.init(identity: node.timedSchedulerIdentity!, slot: 0, state: state, actionAddress: route)]
            let source = try timedPayload([schedule], node: node)
            let wire = TimedSchedulerPayloadPolicy.exportPayload(source)!
            let cleaned = try SpaceSyncCleanupPolicy.normalize(wire)
            precondition(!cleaned.didChange)
            let decoded = try SpaceSyncCleanupCoordinator.cleanupSchedules(cleaned.payload)
            precondition(decoded[0].nodeSlots == schedule.nodeSlots)
            precondition(decoded[0].save(meshUUID: mesh, meshNetworkId: network))
            SunSmartDataManager.shared.db = try Connection(path)
            let reloaded = Schedule.load(meshUUID: mesh, meshNetworkId: network)
            precondition(reloaded.count == 1 && reloaded[0].nodeSlots == schedule.nodeSlots)
            let exported = TimedSchedulerPayloadPolicy.exportPayload(try timedPayload(reloaded, node: node))!
            precondition(TimedSchedulerPayloadPolicy.canonical(exported) == TimedSchedulerPayloadPolicy.canonical(wire))
            let cleanedAgain = try SpaceSyncCleanupCoordinator.cleanupSchedules(SpaceSyncCleanupPolicy.normalize(exported).payload)
            precondition(cleanedAgain[0].nodeSlots == schedule.nodeSlots)
        }
        for version in [1, 2] {
            schedule.nodeSlots = version == 1 ? nil : [.init(identity: node.timedSchedulerIdentity!, slot: 0, state: .assigned)]
            let decoded = try SpaceSyncCleanupCoordinator.cleanupSchedules(timedPayload([schedule], node: node, version: version))
            precondition(decoded[0].nodeSlots == schedule.nodeSlots)
        }
        schedule.nodeAddresses = []; schedule.nodeSlots = []
        let emptyTarget = try SpaceSyncCleanupCoordinator.cleanupSchedules(timedPayload([schedule], node: node))
        precondition(emptyTarget.count == 1)
        schedule.nodeAddresses = [1]
        schedule.nodeSlots = [.init(identity: node.timedSchedulerIdentity!, slot: 0, state: .pendingApply, actionAddress: route)]
        let good = TimedSchedulerPayloadPolicy.exportPayload(try timedPayload([schedule], node: node))!
        func rejects(_ payload: [String: Any]) {
            do { _ = try SpaceSyncCleanupCoordinator.cleanupSchedules(payload); preconditionFailure("invalid shared payload accepted") }
            catch {}
        }
        var bad = good
        bad["schedules"] = (good["schedules"] as! [[String: Any]]) + (good["schedules"] as! [[String: Any]])
        rejects(bad)
        var rows = good["schedules"] as! [[String: Any]], second = rows[0]
        second["id"] = 1; rows.append(second); bad["schedules"] = rows
        rejects(bad) // distinct business IDs still cannot own the same node slot
        rows = good["schedules"] as! [[String: Any]]
        var slots = rows[0]["nodeSlots"] as! [[String: Any]]
        slots[0]["actionAddress"] = ["auto_on": "7FFF", "off": "0001", "recall": "0001"]
        rows[0]["nodeSlots"] = slots; bad["schedules"] = rows
        rejects(bad)
        bad = good
        var nodes = bad["nodes"] as! [[String: Any]]; nodes[0]["uuid"] = "invalid"; bad["nodes"] = nodes
        rejects(bad)
        // Local full ownership may not be exported against a replacement node key.
        bad = try timedPayload([schedule], node: node)
        nodes = bad["nodes"] as! [[String: Any]]; nodes[0]["deviceKey"] = String(repeating: "2", count: 32); bad["nodes"] = nodes
        precondition(TimedSchedulerPayloadPolicy.exportPayload(bad) == nil)
        print("PASS: v3 real export/cleanup/Schedule codec/SQLite/reload roundtrip; all binding states, empty target, v1/v2 and invalid ownership")
    }

    static func localIntentRevision(path: String) throws {
        let manager = MeshNetworkManager.instance, oldNetwork = MeshNetworkManager.instance.meshNetwork
        manager.meshNetwork = MeshNetworkManager.Network()
        defer { manager.meshNetwork = oldNetwork; manager.schedules = []; manager.realNodes = [] }
        let node = Node(1), mesh = manager.meshNetwork!.uuid.uuidString, network = manager.currentNetworkKey.networkId.hex
        manager.realNodes = [node]
        let schedule = Schedule(id: 0, name: "Intent", enabled: true, nodeAddresses: [1])
        let binding = TimedSchedulerNodeSlot(identity: node.timedSchedulerIdentity!, slot: 0, state: .pendingApply,
            actionAddress: .init(autoOn: "0001", off: "0001", recall: "0001"))
        let plan = TimedSchedulerBindings.Plan(meshUUID: mesh, networkID: network, schedules: [schedule], bindings: [0: [binding]])
        let space = SpaceData.load(subNetworkId: network)!
        precondition(space.save())
        // Fail only the revision write, after the Schedule/schema writes succeeded.
        try SunSmartDataManager.shared.db!.execute("CREATE TRIGGER reject_timed_revision BEFORE INSERT ON timed_test_spaces WHEN NEW.revision > 10 BEGIN SELECT RAISE(ABORT, 'fixture revision failure'); END")
        do { try TimedSchedulerBindings.commit(plan, markCloudChange: true); preconditionFailure("revision failure must roll back intent") }
        catch {}
        precondition(Schedule.load(meshUUID: mesh, meshNetworkId: network).isEmpty && schedule.nodeSlots == nil)
        precondition(SpaceData.load(subNetworkId: network)!.lastUpdate == 10)
        try SunSmartDataManager.shared.db!.execute("DROP TRIGGER reject_timed_revision")
        try TimedSchedulerBindings.commit(plan, markCloudChange: true)
        let revision = SpaceData.load(subNetworkId: network)!.lastUpdate
        precondition(revision > 10)
        // No transport callback occurs: preparation failure/cancel cannot be
        // required for persistence. Reopen the actual SQLite connection.
        SunSmartDataManager.shared.db = try Connection(path)
        let reopenedSpace = SpaceData.load(subNetworkId: network)!
        precondition(reopenedSpace.needUploadCloud, "reopened revision=\(reopenedSpace.lastUpdate) confirmed=\(String(describing: reopenedSpace.lastUploadCloudTimestamp)) expected=\(revision)")
        precondition(Schedule.load(meshUUID: mesh, meshNetworkId: network)[0].nodeSlots == [binding])
        try TimedSchedulerBindings.commit(plan, markCloudChange: true)
        precondition(SpaceData.load(subNetworkId: network)!.lastUpdate == revision, "unchanged retry must not advance revision")
        schedule.hour += 1
        try TimedSchedulerBindings.commit(plan, markCloudChange: true)
        precondition(SpaceData.load(subNetworkId: network)!.lastUpdate > revision)
        print("PASS: user intent and upload revision commit atomically; failed revision rolls back, restart retains pending intent, unchanged retry stays clean")
    }
}
