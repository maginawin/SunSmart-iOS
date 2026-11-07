import Foundation
import SQLite

extension Run {
    static func schedulerResultPersistence(path: String) throws {
        let manager = MeshNetworkManager.instance
        for scenario in ["oneModel", "twoModels", "partial", "unknown", "nodeSaveFailure", "scheduleSaveFailure", "cancelled", "replacement", "wrongIdentity", "missingReceipt", "duplicateReceipt"] {
            TimedSchedulerTaskCoordinator.invalidateAll()
            let node = Node(0x49F9), otherNode = Node(0x49FC)
            manager.realNodes = [node, otherNode]
            let group = Group(); node.group = group; node.groupState = .exitFailure
            let schedule = Schedule(id: 4000, name: "Group cleanup", enabled: true, groupAddresses: [group.address.address], selectTargetType: .groups)
            schedule.groups = [group]
            schedule.nodeSlots = [.init(identity: node.timedSchedulerIdentity!, slot: 0, state: .pendingRemoval, actionAddress: node.timedActionAddress())]
            let retained = Schedule(id: 4001, name: "Direct target", enabled: true, nodeAddresses: [node.primaryUnicastAddress])
            retained.nodeSlots = [.init(identity: node.timedSchedulerIdentity!, slot: 1, state: .synced, actionAddress: node.timedActionAddress())]
            manager.schedules = [schedule, retained]
            precondition(schedule.save() && retained.save())
            let retainedSlots = retained.nodeSlots
            let primary = node.schedulerSetupModels[0], secondary = node.schedulerSetupModels[1]
            node.allSchedulerModelEntrys = [primary: [0: .init(isValid: true), 1: retained.schedulerEntry], secondary: [0: .init(isValid: true)]]
            if scenario == "oneModel" { node.allSchedulerModelEntrys[secondary] = [:] }
            if scenario == "unknown" { node.allSchedulerModelEntrys.removeValue(forKey: secondary) }
            node.rebuildTimedSchedulerActions()
            let handles = schedule.getMessageHandles(node: node, delete: true)
            precondition(handles.count == (scenario == "oneModel" ? 1 : 2))
            handles.forEach { $0.schedulerAdmission?() }
            for (index, handle) in handles.enumerated() where scenario != "partial" || index == 0 {
                handle.respondAddresss = handle.allAddresss
                // The transport has already observed the accepted Status before App completion.
                if node.allSchedulerModelEntrys[handle.model!] != nil {
                    node.allSchedulerModelEntrys[handle.model!]!.removeValue(forKey: 0)
                }
            }
            node.rebuildTimedSchedulerActions()
            if scenario == "nodeSaveFailure" { node.propertiesSaveSucceeds = false }
            if scenario == "scheduleSaveFailure" {
                try SunSmartDataManager.shared.db!.execute("CREATE TRIGGER fail_result_binding BEFORE INSERT ON schedules WHEN NEW.scheduleIndex = 4000 BEGIN SELECT RAISE(ABORT, 'result failure'); END")
            }
            if scenario == "cancelled" { handles[0].schedulerTask!.cancel() }
            if scenario == "replacement" { schedule.enabled = false; precondition(schedule.save()) }
            if scenario == "wrongIdentity" { node.deviceKey = Data(repeating: 2, count: 16) }
            let results = scenario == "missingReceipt" ? Array(handles.prefix(1))
                : scenario == "duplicateReceipt" ? [handles[0], handles[0]] : handles
            let applied = schedule.applySchedulerResults(results, expected: handles, on: node)
            let success = scenario == "oneModel" || scenario == "twoModels"
            precondition(applied == success, "batch result: \(scenario)")
            precondition(schedule.nodeSlots!.isEmpty == success, "binding lifecycle: \(scenario)")
            if success {
                precondition(node.appliedMessages == handles.count, "all Models apply before binding release")
                precondition(handles.allSatisfy { !$0.isSuccessful && $0.schedulerTask?.isCancelled == false }, "accepted receipts must survive their send intent ending")
            }
            precondition(retained.nodeSlots == retainedSlots && node.allSchedulerModelEntrys[primary]?[1] == retained.schedulerEntry)
            precondition(otherNode.allSchedulerModelEntrys.values.allSatisfy(\.isEmpty))
            // Independent connection: production Schedule codec and SQLite save/load.
            SunSmartDataManager.shared.db = try Connection(path)
            let reloaded = Schedule.load(meshUUID: manager.meshNetwork!.uuid.uuidString,
                meshNetworkId: manager.currentNetworkKey.networkId.hex, scheduleId: 4000).first!
            precondition(reloaded.nodeSlots == schedule.nodeSlots, "durable binding: \(scenario)")
            if scenario == "scheduleSaveFailure" { try SunSmartDataManager.shared.db!.execute("DROP TRIGGER fail_result_binding") }
            if success || scenario == "partial" || scenario == "nodeSaveFailure" || scenario == "scheduleSaveFailure" {
                node.propertiesSaveSucceeds = true
                manager.schedules = [reloaded, retained]
                let retry = reloaded.getMessageHandles(node: node, delete: true)
                precondition(retry.count == (scenario == "partial" ? 1 : 0), "retry sends only unfinished Model: \(scenario)")
                retry.forEach { $0.schedulerAdmission?(); $0.respondAddresss = $0.allAddresss }
                precondition(reloaded.applySchedulerResults(retry, expected: retry, on: node), "durable retry: \(scenario)")
                precondition(reloaded.nodeSlots!.isEmpty && reloaded.deletionIsSynchronized(on: node))
                precondition(Schedule.load(meshUUID: manager.meshNetwork!.uuid.uuidString,
                    meshNetworkId: manager.currentNetworkKey.networkId.hex, scheduleId: 4000).first!.nodeSlots!.isEmpty)
            }
        }
        TimedSchedulerTaskCoordinator.invalidateAll()
        print("PASS: real Scheduler result/ownership + SQLite round trip; one/two Models, partial retry, unknown, save failures, cancellation, replacement, identity and receipt membership")
    }
}
