import Foundation

@main
struct TimedSchedulerSingleOwnerContractTests {
    static func main() throws {
        guard CommandLine.arguments.count == 12 else {
            fatalError(
                "Expected Node+SupportModels, Node+Messages, MeshScheduleServer, "
                + "Node+MessageHandles, MeshNetwork+SunSmart, ScheduleServer, "
                + "GroupServer, Scheduler, DeviceGroupDeferredSyncPlanner, "
                + "MeshDatabase and TimedViewController paths"
            )
        }

        let supportModels = try source(at: 1)
        let nodeMessages = try source(at: 2)
        let meshScheduleServer = try source(at: 3)
        let messageHandles = try source(at: 4)
        let meshNetwork = try source(at: 5)
        let scheduleServer = try source(at: 6)
        let groupServer = try source(at: 7)
        let scheduler = try source(at: 8)
        let groupSyncPlanner = try source(at: 9)
        let meshDatabase = try source(at: 10)
        let timedViewController = try source(at: 11)

        testOwnerPolicy(in: supportModels)
        testSetAndDeleteRouting(
            messageHandles: messageHandles,
            scheduler: scheduler
        )
        testModelAwareSync(in: meshNetwork)
        testDeleteTargets(in: scheduleServer)
        testEnabledStateUsesTargetEntry(in: scheduleServer)
        testHistoricalEntryPoints(
            scheduleServer: scheduleServer,
            meshNetwork: meshNetwork,
            groupServer: groupServer,
            groupSyncPlanner: groupSyncPlanner
        )
        testMultiModelRead(
            meshScheduleServer: meshScheduleServer,
            nodeMessages: nodeMessages
        )
        testSchedulerModelPersistence(in: meshDatabase)
        testUnknownSchedulerModelRepair(in: timedViewController)

        print("TimedSchedulerSingleOwnerContractTests passed")
    }

    private static func testOwnerPolicy(in source: String) {
        require(
            source.contains("var schedulerSetupModels: [Model]"),
            "Node must expose all Scheduler Setup models"
        )
        require(
            source.contains("var ordinarySchedulerSetupModel: Model?"),
            "Node must identify the ordinary Scheduler Setup model"
        )
        let ownerPolicy = section(
            in: source,
            from: "var ordinarySchedulerSetupModel: Model?",
            to: "/// 时间model"
        )
        require(
            source.contains("enum SchedulerSetupModelOwner"),
            "SDK must expose a neutral Scheduler owner type"
        )
        require(
            ownerPolicy.contains(
                "func schedulerSetupModel(for owner: SchedulerSetupModelOwner)"
            ),
            "SDK Scheduler model selection must receive an owner, not an App action"
        )
        require(
            ownerPolicy.contains("case .lightLC"),
            "SDK must support selecting the Light LC Scheduler"
        )
        require(
            ownerPolicy.contains("case .ordinary"),
            "SDK must support selecting the ordinary Scheduler"
        )
        require(
            ownerPolicy.contains(
                "func schedulerCleanupModels(for owner: SchedulerSetupModelOwner)"
            ),
            "SDK cleanup must use the already-resolved owner"
        )
    }

    private static func testSetAndDeleteRouting(
        messageHandles source: String,
        scheduler: String
    ) {
        let scheduleMessages = section(
            in: source,
            from: "extension Schedule {",
            to: "extension ProfileType {"
        )
        require(
            scheduleMessages.contains(
                "schedulerModelOwner(on: node, contextGroup: contextGroup)"
            ),
            "Schedule Set must resolve its owner from the App Group/Profile policy"
        )
        require(
            scheduleMessages.contains("node.schedulerSetupModel(for: owner)"),
            "Schedule Set must pass the resolved owner to the SDK"
        )
        require(
            scheduleMessages.contains("node.schedulerCleanupModels(for: owner)"),
            "Schedule Set must clear every non-owner Scheduler for the resolved owner"
        )
        require(
            scheduleMessages.contains("contextGroup: Group? = nil"),
            "Schedule Set must accept an explicit target Group for add/restore flows"
        )

        let deleteMessages = section(
            in: scheduleMessages,
            from: "if delete {",
            to: "}else {"
        )
        require(
            deleteMessages.contains("node.schedulerSetupModels"),
            "Delete must clear every Scheduler model regardless of Action"
        )

        let cleanupPosition = scheduleMessages.range(
            of: "node.schedulerCleanupModels(for: owner)"
        )?.lowerBound
        let ownerPosition = scheduleMessages.range(
            of: "model: schedulerSetupModel"
        )?.lowerBound
        require(
            cleanupPosition != nil
                && ownerPosition != nil
                && cleanupPosition! < ownerPosition!,
            "Set must clear non-owner models before writing the owner"
        )

        let appOwnerPolicy = section(
            in: scheduler,
            from: "static func schedulerModelOwner(",
            to: "class Schedule:"
        )
        require(
            appOwnerPolicy.contains("node.groupState != .exitFailure"),
            "A Group being exited must not be treated as an active automatic Group"
        )
        require(
            appOwnerPolicy.contains(
                "contextGroup ?? node.restoreData?.addGroup ?? node.group"
            ),
            "The App policy must prefer an explicit target or restore Group before current membership"
        )
        require(
            appOwnerPolicy.contains(".manualControl"),
            "The App policy must distinguish Manual control Profiles"
        )
        require(
            appOwnerPolicy.contains("TimedSchedulerOwnerPolicy.resolve"),
            "The App adapter must reuse the tested Timed owner policy"
        )
    }

    private static func testModelAwareSync(in source: String) {
        let needsSync = section(
            in: source,
            from: "func needsSync(on node: Node",
            to: "func needsDelete(from node: Node"
        )
        require(
            needsSync.contains(
                "schedulerModelOwner(on: node, contextGroup: contextGroup)"
            ),
            "needsSync must use the same App Group/Profile owner as writes"
        )
        require(
            needsSync.contains("schedulerSetupModel(for: owner)"),
            "needsSync must inspect the model selected from the resolved owner"
        )
        require(
            needsSync.contains("allSchedulerModelEntrys"),
            "needsSync must compare entries with their Model dimension"
        )
        require(
            needsSync.contains("schedulerCleanupModels(for: owner)"),
            "needsSync must detect stale non-owner entries"
        )
        require(
            needsSync.contains("allSchedulerModelEntrys[model]"),
            "needsSync must require known state for every non-owner Scheduler"
        )
        require(
            needsSync.contains("guard let cleanupEntrys"),
            "A failed cleanup with unknown cache state must remain pending"
        )
        require(
            needsSync.contains("TimedSchedulerSyncPolicy.evaluate"),
            "needsSync must use the tested per-Model difference policy"
        )
        require(
            needsSync.contains("schedulerSyncDifference"),
            "Timed diagnostics and needsSync must share one difference calculation"
        )

        let needsDelete = section(
            in: source,
            from: "func needsDelete(from node: Node",
            to: "func getNeedSyncDatas()"
        )
        require(
            needsDelete.contains("schedulerSetupModels"),
            "needsDelete must inspect every Scheduler model"
        )
        require(
            needsDelete.contains("allSchedulerModelEntrys"),
            "needsDelete must use Model-aware entries"
        )
        require(
            needsDelete.contains("allSchedulerModelEntrys[model] == nil"),
            "Delete must retry Scheduler models whose state is still unknown"
        )

        let updateData = section(
            in: source,
            from: "func updateData(message: MeshMessage",
            to: "case is LightLCLightOnOffSet"
        )
        require(
            updateData.contains("model: Model? = nil"),
            "Node cache updates must receive the source Scheduler model"
        )
        require(
            updateData.contains("allSchedulerModelEntrys"),
            "Scheduler Set cache updates must preserve the Model dimension"
        )
        require(
            updateData.contains("rebuildTimedSchedulerActions()"),
            "The flattened compatibility cache must be rebuilt from Action owners"
        )
        require(
            updateData.contains("shouldFinalizeScheduleDeletion"),
            "Schedule target cleanup must wait for all Scheduler models"
        )
        require(
            updateData.contains("allSchedulerModelEntrys[model] != nil"),
            "Unknown or failed Scheduler cleanup must block deletion finalization"
        )
    }

    private static func testDeleteTargets(in source: String) {
        let deleteSchedule = section(
            in: source,
            from: "static func deleteSchedule(",
            to: "static func saveSchedule("
        )
        require(
            deleteSchedule.contains(
                "schedule.needDeleteNodeAddresses.append(contentsOf:"
            ),
            "Direct device targets must be retained for deletion"
        )
        require(
            !deleteSchedule.contains(
                "schedule.needDeleteNodeAddresses.removeAll()"
            ),
            "Delete must not immediately erase direct device targets"
        )
    }

    private static func testEnabledStateUsesTargetEntry(in source: String) {
        let setEnabled = section(
            in: source,
            from: "static func setEnabledState(",
            to: "static func deleteSchedule("
        )
        let enabledPosition = setEnabled.range(
            of: "schedule.enabled = enabled"
        )?.lowerBound
        let filterPosition = setEnabled.range(
            of: "setNodes = setNodes.filter"
        )?.lowerBound
        require(
            enabledPosition != nil
                && filterPosition != nil
                && enabledPosition! < filterPosition!,
            "Enable/disable must build sync decisions from the requested entry"
        )
        require(
            setEnabled.contains("schedule.needsSync(on:"),
            "Enable/disable must use Model-aware synchronization"
        )
    }

    private static func testHistoricalEntryPoints(
        scheduleServer: String,
        meshNetwork: String,
        groupServer: String,
        groupSyncPlanner: String
    ) {
        let restore = section(
            in: meshNetwork,
            from: "// 日程\n",
            to: "if let pwmFrequency"
        )
        require(
            restore.contains("schedule.getMessageHandles(node: self)"),
            "Device restore must reuse the single-owner Schedule message builder"
        )
        require(
            !restore.contains(
                "SchedulerActionSet(index: UInt8(schedule.id)"
            ),
            "Device restore must not bypass the owner policy"
        )

        let groupSchedules = section(
            in: groupServer,
            from: "// 设备需要新增/更新的日程",
            to: "return messages"
        )
        require(
            groupSchedules.contains(
                "schedule.getMessageHandles(node: node, contextGroup: self)"
            ),
            "Group synchronization must pass its Group Profile to the Schedule message builder"
        )
        require(
            groupSchedules.contains("schedule.needsSync(on: node"),
            "Group synchronization must detect non-owner Scheduler residue"
        )
        require(
            !groupSchedules.contains(
                "SchedulerActionSet(index: UInt8(schedule.id)"
            ),
            "Group synchronization must not bypass the owner policy"
        )

        let saveSchedule = section(
            in: scheduleServer,
            from: "static func saveSchedule(",
            to: "MeshProxyMessageCommand.shared.addMessage"
        )
        require(
            saveSchedule.contains("contextGroup: group"),
            "Group-targeted Timed saves must pass the target Group to owner resolution"
        )

        let deferredSchedules = section(
            in: groupSyncPlanner,
            from: "static func makeDeferredTasks(",
            to: "static func makeTaskCheckpointBatch("
        )
        require(
            deferredSchedules.contains("contextGroup: group"),
            "Deferred add-to-Group Schedule messages must use the target Group Profile"
        )
    }

    private static func testMultiModelRead(
        meshScheduleServer: String,
        nodeMessages: String
    ) {
        let setSchedule = section(
            in: meshScheduleServer,
            from: "static func setSchedule(",
            to: "static func getSchedule("
        )
        require(
            setSchedule.contains("schedulerCleanupModels(for: .ordinary)"),
            "The SDK API without App Profile context must clear non-ordinary models"
        )
        require(
            setSchedule.contains("schedulerSetupModel(for: .ordinary)"),
            "The SDK API without App Profile context must conservatively use the ordinary Scheduler"
        )
        require(
            !setSchedule.contains("node.schedulerSetupModel {"),
            "The public SDK Schedule Set API must not write only the first Scheduler"
        )

        let getSchedule = section(
            in: meshScheduleServer,
            from: "static func getSchedule(",
            to: "public extension SchedulerRegistryEntry"
        )
        require(
            getSchedule.contains("schedulerSetupModels"),
            "Schedule reads must traverse all Scheduler models"
        )
        require(
            getSchedule.contains("messageHandle.model"),
            "Scheduler Status follow-up reads must keep the source Model"
        )
        require(
            !getSchedule.contains("node.schedulerSetupModel!"),
            "Scheduler Action Get must not jump back to the first Scheduler"
        )
        require(
            getSchedule.contains("SchedulerModelReadCompletionEvaluator.evaluate"),
            "Schedule read completion must classify every requested Node from all Register and Action handles"
        )
        require(
            getSchedule.contains(".parentNode?")
                && getSchedule.contains(".primaryUnicastAddress"),
            "Schedule read completion must aggregate Element handles by primary Node"
        )
        require(
            getSchedule.contains("if index == nil"),
            "Only authoritative full reads may invalidate partial Scheduler Model cache"
        )
        require(
            getSchedule.contains("modelEntrys.removeValue(forKey: model)"),
            "A failed authoritative read must keep the affected Node state unknown for retry"
        )
        require(
            getSchedule.contains("schedulerActionSnapshots")
                && getSchedule.contains("node.schedulerActions = snapshot")
                && getSchedule.contains("node.scheduleIds = snapshot.keys.sorted()")
                && getSchedule.contains("node.savePropertys()"),
            "A failed authoritative read must restore the legacy projection while persisting unknown per-Model state"
        )

        let schedulerStatus = section(
            in: nodeMessages,
            from: "case is SchedulerStatus:",
            to: "case is TimeStatus:"
        )
        require(
            schedulerStatus.contains("allSchedulerModelEntrys"),
            "Incoming Scheduler data must maintain per-Model state"
        )
        require(
            schedulerStatus.contains("rebuildSchedulerActions()"),
            "Incoming Scheduler data must rebuild the neutral compatibility projection"
        )
        require(
            schedulerStatus.contains("removeValue(forKey:"),
            "Invalid Scheduler entries must be removed from per-Model state"
        )

        let rebuildSchedulerActions = section(
            in: nodeMessages,
            from: "func rebuildSchedulerActions()",
            to: "/// 更新设备节点数据"
        )
        require(
            !rebuildSchedulerActions.contains("schedulerSetupModel(for:"),
            "The SDK cache must not guess an App Group/Profile owner from Action"
        )
    }

    private static func testSchedulerModelPersistence(in source: String) {
        let loadProperties = section(
            in: source,
            from: "// 解析设备所有日程数据 [model: 16个日程]",
            to: "if let data = row[PropertyExpressionKey.lightLCPropertys]"
        )
        require(
            loadProperties.contains("SchedulerModelCachePersistence.decode"),
            "Scheduler Model persistence must use the backward-compatible codec"
        )
        require(
            loadProperties.contains("case .corrupted"),
            "Corrupted Scheduler Model persistence must be handled explicitly"
        )
        require(
            loadProperties.contains("corruptedSchedulerModelActionsData"),
            "Corrupted Scheduler Model persistence must retain the original blob"
        )
        require(
            !loadProperties.contains(
                "try? jsonDecoder.decode([ScheduleModelDataContainer].self"
            ),
            "Scheduler Model persistence decode failures must not be swallowed"
        )

        let saveProperties = section(
            in: source,
            from: "// 所有model日程数据 [model: 16个日程]",
            to: "let lightLCPropertysData"
        )
        require(
            saveProperties.contains("SchedulerModelCachePersistence.dataForSaving"),
            "Scheduler Model saves must preserve corrupted data until authoritative state exists"
        )
        require(
            saveProperties.contains("corruptedSchedulerModelActionsData"),
            "Scheduler Model saves must pass the retained corrupted blob to the codec"
        )
    }

    private static func testUnknownSchedulerModelRepair(in source: String) {
        let repair = section(
            in: source,
            from: "private func repairUnknownSchedulerModelCachesIfNeeded()",
            to: "private func debugPrintScheduleDiagnostics()"
        )
        require(
            repair.contains(
                "TimedSchedulerCacheRepairPolicy.needsAuthoritativeRead"
            ),
            "Timed must repair nodes whose per-Model Scheduler state is unknown"
        )
        require(
            repair.contains("MeshAPI.getSchedule(")
                && repair.contains("index: nil"),
            "Timed repair must read authoritative Scheduler Registers before comparing"
        )
        require(
            repair.contains("MeshProxyMessageCommand.shared.isBusy"),
            "Timed repair must not replace callbacks of an existing Mesh command"
        )
        require(
            repair.contains("node.deviceType != .dongle"),
            "Ordinary Timed migration must not consume Dongle collection Scheduler state"
        )
        require(
            repair.contains("self.updateUI()"),
            "Timed must recalculate sync markers after authoritative reads finish"
        )

        let diagnostics = section(
            in: source,
            from: "private func debugPrintScheduleDiagnostics()",
            to: "#endif"
        )
        require(
            diagnostics.contains("schedulerSyncDifference"),
            "Timed diagnostics must print the same difference used by needsSync"
        )
        require(
            diagnostics.contains("allSchedulerModelEntrys[model]"),
            "Timed diagnostics must print per-Model Scheduler state"
        )
        require(
            diagnostics.contains("schedulerModelCacheDecodeError"),
            "Timed diagnostics must expose persistence decode failures"
        )
    }

    private static func source(at index: Int) throws -> String {
        try String(
            contentsOfFile: CommandLine.arguments[index],
            encoding: .utf8
        )
    }

    private static func section(
        in source: String,
        from startMarker: String,
        to endMarker: String
    ) -> String {
        guard let startRange = source.range(of: startMarker) else {
            fatalError("Missing source marker: \(startMarker)")
        }
        let remainder = source[startRange.lowerBound...]
        guard let endRange = remainder.range(of: endMarker) else {
            fatalError("Missing source marker: \(endMarker)")
        }
        return String(remainder[..<endRange.lowerBound])
    }

    private static func require(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) {
        precondition(condition(), message)
    }
}
