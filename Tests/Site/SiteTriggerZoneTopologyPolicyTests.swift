import Foundation

@main
struct SiteTriggerZoneTopologyPolicyTests {
    typealias Policy = SiteTriggerZoneTopologyPolicy
    typealias Local = ProximityLightingTopologyPolicy

    static func main() {
        testUnrelatedSpaceKeepsSpaceKey()
        testAnyPrimaryDeviceSelectsWholeSpace()
        testSiteZoneAddsCrossSpaceEdgesWithoutDroppingPaths()
        testOverlappingZoneSourcesDoNotCreateExtraWrites()
        testTwoSpaceSubsetOfExistingThreeSpaceZoneIsTopologyNoOp()
        testSourceOnlyProofFailsClosed()
        testRemovingSiteZoneKeepsPrimaryWhenADeviceStillHasIt()
        testInvalidAndAmbiguousInputsFailClosed()
        testPrimaryAddressAndNetKeyEvidence()
        testOnlyConfirmedCloudDataCanBeProjected()
        testSyncTasksStayWithinEachSpaceAndPreserveSharedEdges()
        testDeletedZoneCleanupRemainsAtSiteLevelWhenNodeIsShared()
        testNonSiteMemberStillNeedsPrimaryConfiguration()
        testRecoveryTasksCompareObservedNodesWithServerTarget()
        testDifferencePlanRequiresDeviceObservations()
        testExplicitKeyAndTTLPreflight()
        testPermissionAndBlockerCategories()
        testTargetFingerprintTracksFullDesiredTopology()
        testCloudFingerprintUsesCanonicalContent()
        testPreviousSiteTargetReconstruction()
        testCapacityAfterSiteMerge()
        print("PASS: Site Trigger Zone read-only topology policy tests.")
    }

    private static func testUnrelatedSpaceKeepsSpaceKey() {
        let space = makeSpace("A", addresses: [1, 2], edges: [1: [2], 2: [1]])
        let plan = Policy.makePlan(spaces: [space], zones: [])
        require(plan.isComplete, "A complete single Space must remain plannable")
        require(plan.primarySpaceIDs.isEmpty, "A Space without Primary must not migrate")
        require(plan.targets[space.nodes[0].id]?.forwardKey == .space, "Space key changed without a trigger")
        require(plan.targets[space.nodes[0].id]?.neighborAddresses == [2], "Existing Path edge changed")
    }

    private static func testPermissionAndBlockerCategories() {
        var space = makeSpace("A", addresses: [1, 2], edges: [1: [2]])
        space.canConfigure = false
        let target = Policy.makePlan(spaces: [space], zones: [])
        require(target.issues.contains(.insufficientPermission("A")) && target.canPreviewTasks,
                "Permission loss must block execution without hiding a read-only topology")
        let device = space.nodes[0].id
        let categories = SiteTriggerZoneSyncPlanningPolicy.blockers(for: [
            .topology(.insufficientPermission("A")), .topology(.unknownTargetTTL("A")),
            .topology(.capacity(device, 185)), .unverifiedObservation(device)
        ])
        require(categories == [.permission, .ttl, .capacity, .observations],
                "Distinct permission, TTL, capacity and readback blockers must stay visible")
    }

    private static func testAnyPrimaryDeviceSelectsWholeSpace() {
        let space = makeSpace("A", addresses: [1, 2, 3], edges: [1: [2], 2: [1]],
                              primaryAt: [3], boundAt: [])
        let plan = Policy.makePlan(spaces: [space], zones: [])
        require(plan.isComplete, "Known absent bindings should be actionable")
        require(plan.primarySpaceIDs == ["A"], "A Primary device outside the Path must select Space mode")
        for node in space.nodes.prefix(2) {
            require(plan.targets[node.id]?.forwardKey == .primary, "An entire Space Path must migrate")
            require(plan.targets[node.id]?.primaryPreparation == .installOrBind,
                    "A non-Site member without Primary must need Configuration")
        }
    }

    private static func testSiteZoneAddsCrossSpaceEdgesWithoutDroppingPaths() {
        let a = makeSpace("A", addresses: [1, 2, 3], edges: [1: [2], 2: [1, 3], 3: [2]])
        let b = makeSpace("B", addresses: [4, 5, 6], edges: [4: [5], 5: [4, 6], 6: [5]])
        let zone = makeZone([a.nodes[1], b.nodes[1]])
        let plan = Policy.makePlan(spaces: [a, b], zones: [zone])
        require(plan.isComplete, "A valid two-Space Zone should plan")
        require(plan.primarySpaceIDs == ["A", "B"], "Site participation must select both Spaces")
        require(plan.targets[a.nodes[1].id]?.neighborAddresses == [1, 3, 5],
                "Cross-Space edge must merge with both existing Path edges")
        require(plan.targets[b.nodes[1].id]?.neighborAddresses == [2, 4, 6],
                "Reverse Site edge or existing B Path edge was lost")
        require(plan.targets[a.nodes[0].id]?.forwardKey == .primary,
                "A non-Site Path member must inherit Space Primary mode")
        require(plan.sourcesByDevice[a.nodes[1].id]?.contains(.siteZone(zone.zoneId)) == true,
                "A direct Site Zone member must retain its Zone source")
        require(plan.sourcesByDevice[a.nodes[0].id]?.contains(.spacePrimaryDueToZone(zone.zoneId)) == true
                && plan.sourcesByDevice[a.nodes[0].id]?.contains(.local(.groupPath(0xC000))) == true,
                "A non-Site Path member must show the Zone-caused Primary migration and its Path")
        let previous = Policy.makePlan(spaces: [a, b], zones: [])
        let tasks = SiteTriggerZoneSyncPlanningPolicy.makePlan(
            previous: previous, target: plan, selectedZoneID: zone.zoneId,
            previousZones: [], confirmedZones: [zone], siteSpaceOrder: ["A", "B"])
        let direct = tasks.spaces.flatMap(\.configuration).first { $0.deviceID == a.nodes[1].id }
        let indirect = tasks.spaces.flatMap(\.configuration).first { $0.deviceID == a.nodes[0].id }
        require(direct?.relationshipSources == [.siteZone(zone.zoneId)]
                && indirect?.relationshipSources.isEmpty == true,
                "A new cross-Space edge must be distinguished from a Path member's shared Key migration")
        let attribution = SiteTriggerZoneSyncPlanningPolicy.attributeTasks(
            tasks, liveZoneIDs: [zone.zoneId])
        require(attribution.directByZone[zone.zoneId]?.contains(where: {
            $0.task.deviceID == a.nodes[1].id
        }) == true && attribution.sharedByZone[zone.zoneId]?.contains(where: {
            $0.task.deviceID == a.nodes[0].id
        }) == true,
        "The Zone must distinguish direct edge work from a shared Space Key task")
    }

    private static func testOverlappingZoneSourcesDoNotCreateExtraWrites() {
        let space = makeSpace("A", addresses: [1, 2], edges: [:],
                              primaryAt: [1, 2], boundAt: [1, 2])
        let first = makeZone(space.nodes)
        let second = makeZone(space.nodes)
        let before = Policy.makePlan(spaces: [space], zones: [first])
        let after = Policy.makePlan(spaces: [space], zones: [first, second])
        require(after.sourcesByDevice[space.nodes[0].id]?.contains(.siteZone(second.zoneId)) == true,
                "An overlapping Zone must remain attributable")
        let tasks = SiteTriggerZoneSyncPlanningPolicy.makePlan(
            previous: before, target: after, selectedZoneID: second.zoneId,
            previousZones: [first], confirmedZones: [first, second], siteSpaceOrder: ["A"])
        require(tasks.isComplete && tasks.taskCount == 0,
                "A source-only overlap must not create a redundant device command")
    }

    private static func testTwoSpaceSubsetOfExistingThreeSpaceZoneIsTopologyNoOp() {
        let a = makeSpace("A", addresses: [1, 2], edges: [:],
                          primaryAt: [1, 2], boundAt: [1, 2])
        let b = makeSpace("B", addresses: [3, 4], edges: [:],
                          primaryAt: [3, 4], boundAt: [3, 4])
        let c = makeSpace("C", addresses: [5, 6], edges: [:],
                          primaryAt: [5, 6], boundAt: [5, 6])
        let existing = makeZone(a.nodes + b.nodes + c.nodes)
        let proposed = makeZone([a.nodes[0], b.nodes[0]])
        let before = Policy.makePlan(spaces: [a, b, c], zones: [existing])
        let after = Policy.makePlan(spaces: [a, b, c], zones: [existing, proposed])
        require(before.targets == after.targets,
                "A two-Space subset must not change any target under an existing three-Space clique")
        require(SiteTriggerZoneSyncPlanningPolicy.targetFingerprint(siteID: "site", topology: before)
                == SiteTriggerZoneSyncPlanningPolicy.targetFingerprint(siteID: "site", topology: after),
                "Adding only a Zone source must not change the executable target identity")
        let tasks = SiteTriggerZoneSyncPlanningPolicy.makePlan(
            previous: before, target: after, selectedZoneID: proposed.zoneId,
            previousZones: [existing], confirmedZones: [existing, proposed],
            siteSpaceOrder: ["A", "B", "C"])
        require(tasks.isComplete && tasks.taskCount == 0,
                "A new Zone source without a changed target must not create device tasks")
        let change = SiteTriggerZoneDeviceSyncChange(zoneID: proposed.zoneId,
            previousMembers: .array([]), targetMembers: proposed.fields["members"]!)
        require(SiteTriggerZoneSyncPlanningPolicy.allRetainedChangesAreSourceOnly(
            confirmedZones: [existing, proposed], changes: [change]),
            "A subset of an unchanged three-Space Zone must not show new target work")
        let another = makeZone([a.nodes[1], b.nodes[1]])
        let anotherChange = SiteTriggerZoneDeviceSyncChange(zoneID: another.zoneId,
            previousMembers: .array([]), targetMembers: another.fields["members"]!)
        require(SiteTriggerZoneSyncPlanningPolicy.allRetainedChangesAreSourceOnly(
            confirmedZones: [existing, proposed, another], changes: [change, anotherChange]),
            "Several newly added subsets must still be source-only under one unchanged Zone")
    }

    private static func testSourceOnlyProofFailsClosed() {
        typealias Tasks = SiteTriggerZoneSyncPlanningPolicy
        let space = makeSpace("A", addresses: [1, 2, 3], edges: [:])
        let covering = makeZone(space.nodes)
        let subset = makeZone([space.nodes[0], space.nodes[1]])
        let addition = SiteTriggerZoneDeviceSyncChange(zoneID: subset.zoneId,
            previousMembers: .array([]), targetMembers: subset.fields["members"]!)
        require(Tasks.allRetainedChangesAreSourceOnly(
            confirmedZones: [covering, subset], changes: [addition]),
            "An unchanged covering Zone must prove a source-only addition")
        let removal = SiteTriggerZoneDeviceSyncChange(zoneID: subset.zoneId,
            previousMembers: subset.fields["members"]!, targetMembers: .array([]))
        require(Tasks.allRetainedChangesAreSourceOnly(
            confirmedZones: [covering], changes: [removal]),
            "An unchanged covering Zone must prove a source-only deletion")
        let coveringChange = SiteTriggerZoneDeviceSyncChange(zoneID: covering.zoneId,
            previousMembers: .array([]), targetMembers: covering.fields["members"]!)
        require(!Tasks.allRetainedChangesAreSourceOnly(
            confirmedZones: [covering, subset], changes: [addition, coveringChange]),
            "A changed covering Zone cannot prove prior target coverage")
        let incompleteCover = makeZone([space.nodes[0]])
        require(!Tasks.allRetainedChangesAreSourceOnly(
            confirmedZones: [incompleteCover, subset], changes: [addition]),
            "A covering Zone missing one affected member cannot prove no target work")
        var differentAddress = subset
        var changed = subset.members!
        changed[0].fields["deviceAddress"] = .integer(4)
        differentAddress.replaceMembers(changed)
        let changedAddress = SiteTriggerZoneDeviceSyncChange(zoneID: subset.zoneId,
            previousMembers: .array([]), targetMembers: differentAddress.fields["members"]!)
        require(!Tasks.allRetainedChangesAreSourceOnly(
            confirmedZones: [covering, differentAddress], changes: [changedAddress]),
            "Matching UUIDs with different device addresses cannot prove source-only work")
        var legacy = subset.members![0].fields
        legacy.removeValue(forKey: "deviceAddress")
        let unresolvedOld = SiteTriggerZoneDeviceSyncChange(zoneID: subset.zoneId,
            previousMembers: .array([.object(legacy)]), targetMembers: subset.fields["members"]!)
        require(!Tasks.allRetainedChangesAreSourceOnly(
            confirmedZones: [covering, subset], changes: [unresolvedOld]),
            "Legacy unresolved addresses must remain pending until full topology resolution")
    }

    private static func testRemovingSiteZoneKeepsPrimaryWhenADeviceStillHasIt() {
        let space = makeSpace("A", addresses: [1, 2], edges: [1: [2], 2: [1]],
                              primaryAt: [1], boundAt: [1])
        let plan = Policy.makePlan(spaces: [space], zones: [])
        require(plan.primarySpaceIDs == ["A"], "Deleting Site Zone must not switch a Primary Space back")
        require(plan.targets[space.nodes[1].id]?.primaryPreparation == .installOrBind,
                "A newly unsynced Path member still needs Primary after Site deletion")
    }

    private static func testInvalidAndAmbiguousInputsFailClosed() {
        let a = makeSpace("A", addresses: [1, 2], edges: [1: [2], 2: [1]])
        let b = makeSpace("B", addresses: [2, 3], edges: [2: [3], 3: [2]])
        let collision = Policy.makePlan(spaces: [a, b], zones: [])
        require(!collision.isComplete && collision.issues.contains(.duplicateAddress(2)),
                "Reused Mesh address across Spaces must block cross-Space planning")
        var zone = makeZone([a.nodes[0]])
        var stale = zone.members!
        stale[0].fields["groupAddress"] = .integer(0xC001)
        zone.replaceMembers(stale)
        let invalid = Policy.makePlan(spaces: [a], zones: [zone])
        require(!invalid.isComplete && invalid.issues.contains(.invalidMember(zone.zoneId, a.nodes[0].id)),
                "A stale Group must not silently join the Site graph")
        let uncertain = makeSpace("C", addresses: [7], edges: [:], unknownKeyAt: [7])
        require(Policy.makePlan(spaces: [uncertain], zones: []).issues.contains(.unknownPrimaryEvidence("C")),
                "Unknown Key inventory cannot be treated as no Primary")
    }

    private static func testCapacityAfterSiteMerge() {
        let addresses = Array(UInt16(1)...UInt16(186))
        let space = makeSpace("A", addresses: addresses, edges: [:])
        let zone = makeZone(space.nodes)
        let plan = Policy.makePlan(spaces: [space], zones: [zone])
        require(!plan.isComplete && plan.issues.contains(.capacity(space.nodes[0].id, 185)),
                "Site edges beyond the 184-neighbor limit must block execution")
    }

    private static func testPrimaryAddressAndNetKeyEvidence() {
        let space = makeSpace("A", addresses: [10], edges: [:], primaryAt: [10], boundAt: [10],
                              missingNetKeyAt: [10])
        let plan = Policy.makePlan(spaces: [space], zones: [])
        require(plan.targets[space.nodes[0].id]?.primaryPreparation == .installOrBind,
                "A Primary AppKey without its NetKey still needs Configuration")
        var zone = makeZone(space.nodes)
        var stale = zone.members!
        stale[0].fields["primaryAddress"] = .integer(11)
        stale[0].fields["deviceAddress"] = .integer(11)
        zone.replaceMembers(stale)
        let invalid = Policy.makePlan(spaces: [space], zones: [zone])
        require(invalid.issues.contains(.invalidMember(zone.zoneId, space.nodes[0].id)),
                "A reused node address must not match a stale primary address")
    }

    private static func testOnlyConfirmedCloudDataCanBeProjected() {
        var state = SiteTriggerZoneState()
        state.serverData = state.data
        require(Policy.confirmedZones(from: state)?.isEmpty == true,
                "Confirmed empty cloud state should be readable")
        state.commit(state.data.replacingZone(SiteTriggerZone())!, now: 10, siteTimestamp: 0)
        require(Policy.confirmedZones(from: state) == nil,
                "A local Save before GET confirmation cannot plan device work")
        state.pending = nil
        state.conflict = true
        require(Policy.confirmedZones(from: state) == nil,
                "A conflict cannot plan device work")
    }

    private static func testSyncTasksStayWithinEachSpaceAndPreserveSharedEdges() {
        typealias Tasks = SiteTriggerZoneSyncPlanningPolicy
        let a = makeSpace("A", addresses: [1, 2], edges: [1: [2], 2: [1]],
                          primaryAt: [1], boundAt: [1])
        let b = makeSpace("B", addresses: [3, 4], edges: [3: [4], 4: [3]],
                          primaryAt: [4], boundAt: [4])
        let zone = makeZone([a.nodes[1], b.nodes[0]])
        let before = Policy.makePlan(spaces: [a, b], zones: [zone])
        let after = Policy.makePlan(spaces: [a, b], zones: [])
        let tasks = Tasks.makePlan(previous: before, target: after,
                                   selectedZoneID: zone.zoneId, previousZones: [zone],
                                   confirmedZones: [], siteSpaceOrder: ["B", "A"])
        require(tasks.isComplete && tasks.spaces.map(\.spaceID) == ["A", "B"],
                "Old Site member order should drive per-Space execution")
        require(tasks.spaces[0].remove.count == 1 && tasks.spaces[0].configuration.count == 1,
                "A Space must remove obsolete Site edges and configure its missing Primary bind")
        require(tasks.spaces[0].remove[0].removedNeighbors == [3],
                "Remove must contain only the obsolete Site edge")
        require(tasks.spaces[0].remove[0].target?.neighborAddresses == [1],
                "The existing Group Path edge must remain in the final target")
        require(tasks.spaces[0].remove[0].sources.contains(.siteZone(zone.zoneId)),
                "Deleted Zone cleanup must retain its old Zone attribution")
        require(tasks.spaces[0].remove[0].relationshipSources == [.siteZone(zone.zoneId)],
                "Only the deleted Zone should own its removed cross-Space edge")
        require(tasks.spaces[1].remove.count == 1 && tasks.spaces[1].configuration.count == 1,
                "B Space should retain its own Remove then Configuration tasks")
    }

    private static func testNonSiteMemberStillNeedsPrimaryConfiguration() {
        let space = makeSpace("A", addresses: [21, 22], edges: [21: [22], 22: [21]],
                              primaryAt: [21], boundAt: [21])
        let stable = Policy.makePlan(spaces: [space], zones: [])
        let tasks = SiteTriggerZoneSyncPlanningPolicy.makePlan(
            previous: stable, target: stable, selectedZoneID: UUID(),
            previousZones: [], confirmedZones: [], siteSpaceOrder: ["A"])
        require(tasks.isComplete && tasks.taskCount == 1,
                "A non-Site Path member missing Primary needs a task even without a topology diff")
        require(tasks.spaces[0].configuration[0].deviceID == space.nodes[1].id,
                "The missing binding task belongs to the non-Site Path member")
    }

    private static func testDeletedZoneCleanupRemainsAtSiteLevelWhenNodeIsShared() {
        typealias Tasks = SiteTriggerZoneSyncPlanningPolicy
        let a = makeSpace("A", addresses: [1, 2], edges: [:],
                          primaryAt: [1, 2], boundAt: [1, 2])
        let b = makeSpace("B", addresses: [3], edges: [:],
                          primaryAt: [3], boundAt: [3])
        let deleted = makeZone([a.nodes[0], b.nodes[0]])
        let surviving = makeZone(a.nodes)
        let before = Policy.makePlan(spaces: [a, b], zones: [deleted, surviving])
        let after = Policy.makePlan(spaces: [a, b], zones: [surviving])
        let tasks = Tasks.makePlan(previous: before, target: after,
            selectedZoneID: deleted.zoneId, previousZones: [deleted, surviving],
            confirmedZones: [surviving], siteSpaceOrder: ["A", "B"])
        let removed = tasks.spaces.flatMap(\.remove).first { $0.deviceID == a.nodes[0].id }
        require(removed?.relationshipSources == [.siteZone(deleted.zoneId)]
                && removed?.sources.contains(.siteZone(surviving.zoneId)) == true,
                "Removed cross-Space edge and surviving same-Node Zone need distinct attribution")
        let attribution = Tasks.attributeTasks(tasks, liveZoneIDs: [surviving.zoneId])
        require(attribution.siteLevel.contains(where: {
            $0.task.deviceID == a.nodes[0].id && $0.task.kind == .remove
        }) && attribution.sharedByZone[surviving.zoneId]?.contains(where: {
            $0.task.deviceID == a.nodes[0].id && $0.task.kind == .remove
        }) == true,
        "Deleted Zone cleanup must remain reachable at Site level despite a shared live Node")
    }

    private static func testRecoveryTasksCompareObservedNodesWithServerTarget() {
        typealias Tasks = SiteTriggerZoneSyncPlanningPolicy
        let space = makeSpace("A", addresses: [1, 2], edges: [1: [2], 2: [1]],
                              primaryAt: [1, 2], boundAt: [1, 2])
        let target = Policy.makePlan(spaces: [space], zones: [])
        let first = space.nodes[0].id
        let second = space.nodes[1].id
        let primaryKey = target.targets[first]!.forwardKeyReference!
        let observations: [Tasks.Observation] = [
            .init(deviceID: first, address: 1, enabled: true, relayNumber: 2,
                  neighborAddresses: [2, 3], forwardKey: .primary, ttl: 0, evidence: .verified,
                  forwardKeyReference: primaryKey),
            .init(deviceID: second, address: 2, enabled: true, relayNumber: 2,
                  neighborAddresses: [1], forwardKey: .primary, ttl: 0, evidence: .verified,
                  forwardKeyReference: primaryKey)
        ]
        let plan = Tasks.makeRecoveryPlan(target: target, observations: observations,
                                          siteSpaceOrder: ["A"])
        require(plan.isComplete && plan.spaces.count == 1 && plan.taskCount == 2,
                "A stale observed Site edge should produce Remove and final Configuration")
        require(plan.spaces[0].remove[0].removedNeighbors == [3]
                && plan.spaces[0].configuration[0].target?.neighborAddresses == [2]
                && plan.spaces[0].configuration[0].configurationChange == .update,
                "Recovery must remove only the obsolete edge and retain the Group Path neighbor")
        var newEdge = observations
        newEdge[0] = .init(deviceID: first, address: 1, enabled: true, relayNumber: 2,
                           neighborAddresses: [], forwardKey: .primary, ttl: 0, evidence: .verified,
                           forwardKeyReference: primaryKey)
        let addition = Tasks.makeRecoveryPlan(target: target, observations: newEdge,
                                              siteSpaceOrder: ["A"])
        require(addition.spaces[0].configuration[0].configurationChange == .add,
                "A new desired neighbor must be identified as an Add task")
        var cached = observations
        cached[0] = .init(deviceID: first, address: 1, enabled: true, relayNumber: 2,
                          neighborAddresses: [2, 3], forwardKey: nil, ttl: nil, evidence: .cache)
        let blocked = Tasks.makeRecoveryPlan(target: target, observations: cached,
                                             siteSpaceOrder: ["A"])
        require(blocked.taskCount == 2 && blocked.issues.contains(.unverifiedObservation(first))
                && blocked.issues.contains(.missingObservedState(first)),
                "Cache-only differences remain visible tasks but cannot authorize execution")
        let missing = Tasks.makeRecoveryPlan(target: target, observations: [observations[0]],
                                             siteSpaceOrder: ["A"])
        require(missing.issues.contains(.missingObservation(second)),
                "A missing Node must not be silently treated as already synchronized")
    }

    private static func testDifferencePlanRequiresDeviceObservations() {
        typealias Tasks = SiteTriggerZoneSyncPlanningPolicy
        let space = makeSpace("A", addresses: [1], edges: [:])
        let zone = makeZone(space.nodes)
        let desired = Policy.makePlan(spaces: [space], zones: [zone])
        let candidate = Tasks.makePlan(
            previous: Policy.makePlan(spaces: [space], zones: []), target: desired,
            selectedZoneID: zone.zoneId, previousZones: [], confirmedZones: [zone],
            siteSpaceOrder: ["A"])
        let id = space.nodes[0].id
        let target = desired.targets[id]!
        require(candidate.isComplete && candidate.taskCount == 1,
                "A complete cloud difference is only a candidate without device evidence")
        let cached = Tasks.Observation(
            deviceID: id, address: target.address, enabled: target.enabled,
            relayNumber: target.relayNumber, neighborAddresses: target.neighborAddresses,
            forwardKey: target.forwardKey, ttl: target.ttl, evidence: .cache,
            forwardKeyReference: target.forwardKeyReference)
        let blocked = Tasks.requiringDeviceObservations(candidate, observations: [cached])
        require(blocked.issues == [.unverifiedObservation(id), .requiresDeviceReconciliation(id)]
                && blocked.blockers == [.observations, .reconciliation]
                && blocked.taskCount == 1,
                "An exact cache echo must keep the candidate task but block execution")
        let verified = Tasks.Observation(
            deviceID: id, address: target.address, enabled: target.enabled,
            relayNumber: target.relayNumber, neighborAddresses: target.neighborAddresses,
            forwardKey: target.forwardKey, ttl: target.ttl, evidence: .verified,
            forwardKeyReference: target.forwardKeyReference)
        let observed = Tasks.requiringDeviceObservations(candidate, observations: [verified])
        require(observed.issues == [.requiresDeviceReconciliation(id)],
                "A verified observation still needs an actual-state recovery plan")
        require(Tasks.requiringDeviceObservations(candidate, observations: [])
                    .issues.contains(.missingObservation(id)),
                "A missing device readback must be visible")
        require(Tasks.requiringDeviceObservations(candidate, observations: [verified, verified])
                    .issues.contains(.duplicateObservation(id)),
                "Ambiguous device readbacks must block execution")
        let wrongAddress = Tasks.Observation(
            deviceID: id, address: 2, enabled: target.enabled,
            relayNumber: target.relayNumber, neighborAddresses: target.neighborAddresses,
            forwardKey: target.forwardKey, ttl: target.ttl, evidence: .verified,
            forwardKeyReference: target.forwardKeyReference)
        require(Tasks.requiringDeviceObservations(candidate, observations: [wrongAddress])
                    .issues.contains(.addressMismatch(id)),
                "A verified reply from a stale address cannot satisfy the target")
    }

    private static func testExplicitKeyAndTTLPreflight() {
        typealias Tasks = SiteTriggerZoneSyncPlanningPolicy
        let readySpace = makeSpace("A", addresses: [1], edges: [:])
        let ready = Policy.makePlan(spaces: [readySpace], zones: [])
        let target = ready.targets[readySpace.nodes[0].id]!
        require(target.forwardKeyReference == readySpace.spaceKey && target.ttl == 0,
                "A Space target must retain the resolved Key identity and explicit TTL")
        let missingTTL = Policy.makePlan(spaces: [makeSpace("A", addresses: [1], edges: [:],
                                                           targetTTL: nil)], zones: [])
        require(missingTTL.issues.contains(.unknownTargetTTL("A"))
                && Tasks.makeRecoveryPlan(target: missingTTL, observations: [],
                                          siteSpaceOrder: ["A"]).issues.contains(.topology(.unknownTargetTTL("A"))),
                "Unknown forwarding TTL must block recovery with a specific reason")
        let pendingSpace = makeSpace("B", addresses: [2, 3], edges: [:], targetTTL: nil)
        let pendingZone = makeZone(pendingSpace.nodes)
        let old = Policy.makePlan(spaces: [pendingSpace], zones: [])
        let new = Policy.makePlan(spaces: [pendingSpace], zones: [pendingZone])
        let tentative = Tasks.makePlan(previous: old, target: new,
            selectedZoneID: pendingZone.zoneId, previousZones: [],
            confirmedZones: [pendingZone], siteSpaceOrder: ["B"])
        require(tentative.taskCount == 2 && !tentative.isComplete
                && tentative.issues.contains(.topology(.unknownTargetTTL("B"))),
                "An unknown TTL may show candidate work but must never authorize execution")
        let withTransport = Tasks.withTransportCandidates(tentative, spaces: [pendingSpace])
        require(withTransport.spaces[0].transportKeyCandidate == pendingSpace.spaceKey
                && withTransport.spaces[0].transportKeyCandidate
                    != new.targets[pendingSpace.nodes[0].id]?.forwardKeyReference,
                "A Space transport candidate must remain distinct from Primary forwarding Key")
        require(withTransport.taskCount == tentative.taskCount
                && withTransport.targetFingerprint == tentative.targetFingerprint,
                "Transport selection cannot change the desired device target")
        let missingTransport = Tasks.withTransportCandidates(tentative, spaces: [])
        require(missingTransport.spaces[0].transportKeyCandidate == nil
                && missingTransport.issues.contains(.topology(.missingSpaceKey("B"))),
                "A missing transport candidate must block rather than fall back to current AppKey")
        let emptyTransportSpace = Policy.SpaceSnapshot(
            id: pendingSpace.id, meshUUID: pendingSpace.meshUUID, nodes: pendingSpace.nodes,
            spaceKey: .init(networkIndex: pendingSpace.spaceKey!.networkIndex,
                            applicationIndex: pendingSpace.spaceKey!.applicationIndex,
                            materialIdentity: ""),
            primaryKey: pendingSpace.primaryKey, targetTTL: pendingSpace.targetTTL,
            localPlan: pendingSpace.localPlan)
        require(Tasks.withTransportCandidates(tentative, spaces: [emptyTransportSpace])
                    .issues.contains(.topology(.missingSpaceKey("B"))),
                "An empty Key identity is not a resolved transport candidate")
        require(Policy.makePlan(spaces: [emptyTransportSpace], zones: [])
                    .issues.contains(.missingSpaceKey("B")),
                "An empty Key identity must also block the Site target")
        let missingKey = Policy.makePlan(spaces: [makeSpace("A", addresses: [1], edges: [:],
                                                           missingSpaceKey: true)], zones: [])
        require(missingKey.issues.contains(.missingSpaceKey("A")),
                "An unresolved Space AppKey must block the complete target")
        let unresolvedIdentity = Policy.SpaceSnapshot(
            id: readySpace.id, meshUUID: readySpace.meshUUID, nodes: readySpace.nodes,
            spaceKey: .init(networkIndex: readySpace.spaceKey!.networkIndex,
                            applicationIndex: readySpace.spaceKey!.applicationIndex),
            primaryKey: readySpace.primaryKey, targetTTL: readySpace.targetTTL,
            localPlan: readySpace.localPlan)
        let missingIdentity = Policy.makePlan(spaces: [unresolvedIdentity], zones: [])
        require(missingIdentity.issues.contains(.missingSpaceKey("A"))
                && Tasks.targetFingerprint(siteID: "site", topology: missingIdentity) == nil,
                "Key indices without a resolved Key material identity cannot authorize a target")
        let observedWithoutKey = Tasks.Observation(deviceID: readySpace.nodes[0].id,
            address: 1, enabled: true, relayNumber: 2, neighborAddresses: [],
            forwardKey: .space, ttl: 0, evidence: .verified)
        let recovery = Tasks.makeRecoveryPlan(target: ready, observations: [observedWithoutKey],
                                               siteSpaceOrder: ["A"])
        require(recovery.issues.contains(.missingObservedState(readySpace.nodes[0].id)),
                "Matching Key role without a verified Key index is insufficient evidence")
    }

    private static func testTargetFingerprintTracksFullDesiredTopology() {
        typealias Tasks = SiteTriggerZoneSyncPlanningPolicy
        let a = makeSpace("A", addresses: [1, 2], edges: [1: [2], 2: [1]])
        let b = makeSpace("B", addresses: [3], edges: [:])
        let normal = Policy.makePlan(spaces: [a, b], zones: [])
        let reordered = Policy.makePlan(spaces: [b, a], zones: [])
        let fingerprint = Tasks.targetFingerprint(siteID: "site", topology: normal)
        require(fingerprint?.count == 64 && fingerprint == Tasks.targetFingerprint(
            siteID: "site", topology: reordered),
            "A complete Site target needs a stable digest independent of Space iteration order")
        require(fingerprint != Tasks.targetFingerprint(siteID: "other-site", topology: normal),
                "The same device graph in another Site must not reuse a target fingerprint")
        let changedTTL = Policy.SpaceSnapshot(
            id: a.id, meshUUID: a.meshUUID, nodes: a.nodes,
            spaceKey: a.spaceKey, primaryKey: a.primaryKey, targetTTL: 1,
            localPlan: a.localPlan)
        require(fingerprint != Tasks.targetFingerprint(siteID: "site", topology:
            Policy.makePlan(spaces: [changedTTL, b], zones: [])),
            "Forwarding TTL must be part of the device target identity")
        let changedKey = Policy.SpaceSnapshot(
            id: a.id, meshUUID: a.meshUUID, nodes: a.nodes,
            spaceKey: .init(networkIndex: 9, applicationIndex: 9,
                            materialIdentity: "A-rotated-pair"),
            primaryKey: a.primaryKey, targetTTL: a.targetTTL,
            localPlan: a.localPlan)
        require(fingerprint != Tasks.targetFingerprint(siteID: "site", topology:
            Policy.makePlan(spaces: [changedKey, b], zones: [])),
            "Forwarding Key indices must be part of the device target identity")
        let rotatedMaterial = Policy.SpaceSnapshot(
            id: a.id, meshUUID: a.meshUUID, nodes: a.nodes,
            spaceKey: .init(networkIndex: a.spaceKey!.networkIndex,
                            applicationIndex: a.spaceKey!.applicationIndex,
                            materialIdentity: "A-new-material"),
            primaryKey: a.primaryKey, targetTTL: a.targetTTL,
            localPlan: a.localPlan)
        require(fingerprint != Tasks.targetFingerprint(siteID: "site", topology:
            Policy.makePlan(spaces: [rotatedMaterial, b], zones: [])),
            "Rotating Key material at the same indices must change the target identity")
        require(fingerprint != Tasks.targetFingerprint(siteID: "site", topology:
            Policy.makePlan(spaces: [a, b], zones: [makeZone([a.nodes[0], b.nodes[0]])])),
            "Cross-Space neighbor and Primary target changes must change the digest")
        let unknownTTL = Policy.SpaceSnapshot(
            id: a.id, meshUUID: a.meshUUID, nodes: a.nodes,
            spaceKey: a.spaceKey, primaryKey: a.primaryKey, targetTTL: nil,
            localPlan: a.localPlan)
        require(Tasks.targetFingerprint(siteID: "site", topology:
            Policy.makePlan(spaces: [unknownTTL, b], zones: [])) == nil,
            "An unresolved TTL must not be assigned an executable fingerprint")

        let single = makeSpace("C", addresses: [4], edges: [:])
        let zone = makeZone(single.nodes)
        let needsPreparation = Policy.makePlan(spaces: [single], zones: [zone])
        let node = single.nodes[0]
        let readyNode = Policy.NodeSnapshot(
            id: node.id, primaryAddress: node.primaryAddress, address: node.address,
            groupAddress: node.groupAddress, primaryNetKey: .present,
            primaryAppKey: .present, primaryModelBind: .present)
        let readySpace = Policy.SpaceSnapshot(
            id: single.id, meshUUID: single.meshUUID, nodes: [readyNode],
            spaceKey: single.spaceKey, primaryKey: single.primaryKey,
            targetTTL: single.targetTTL, localPlan: single.localPlan)
        let prepared = Policy.makePlan(spaces: [readySpace], zones: [zone])
        require(Tasks.targetFingerprint(siteID: "site", topology: needsPreparation)
                == Tasks.targetFingerprint(siteID: "site", topology: prepared),
                "Key/Bind progress must not change the desired target fingerprint")
    }

    private static func testCloudFingerprintUsesCanonicalContent() {
        typealias Tasks = SiteTriggerZoneSyncPlanningPolicy
        var first = SiteExtensionData()
        first.fields = [
            "schemaVersion": .integer(2),
            "triggerZones": .array([]),
            "future": .object(["z": .integer(3), "a": .string("value")])
        ]
        var reordered = SiteExtensionData()
        reordered.fields = [
            "future": .object(["a": .string("value"), "z": .integer(3)]),
            "triggerZones": .array([]),
            "schemaVersion": .integer(2)
        ]
        let fingerprint = Tasks.cloudFingerprint(siteID: "site", data: first)
        require(fingerprint?.count == 64
                && fingerprint == Tasks.cloudFingerprint(siteID: "site", data: reordered),
                "Cloud content identity must not depend on JSON dictionary insertion order")
        reordered.fields["future"] = .object(["a": .string("changed"), "z": .integer(3)])
        require(fingerprint != Tasks.cloudFingerprint(siteID: "site", data: reordered),
                "An extensionData change must be visible in the cloud fingerprint")
    }

    private static func testPreviousSiteTargetReconstruction() {
        typealias Tasks = SiteTriggerZoneSyncPlanningPolicy
        let space = makeSpace("A", addresses: [1], edges: [:])
        let zone = makeZone(space.nodes)
        let memberValues = zone.fields["members"]!
        let added = SiteTriggerZoneDeviceSyncChange(zoneID: zone.zoneId,
            previousMembers: .array([]), targetMembers: memberValues)
        let prior = try? Tasks.reconstructPreviousZones(
            confirmedZones: [zone], changes: [added], resolve: { $0.members }).get()
        require(prior?.first?.isEmpty == true,
                "A newly populated Zone must be absent from the previous relationship target")
        let deleted = SiteTriggerZoneDeviceSyncChange(zoneID: zone.zoneId,
            previousMembers: memberValues, targetMembers: .array([]))
        let restored = try? Tasks.reconstructPreviousZones(
            confirmedZones: [], changes: [deleted], resolve: { $0.members }).get()
        require(restored?.first?.members == zone.members,
                "Deleted Zone members must remain available for device cleanup")
        require(Tasks.hasDeletedZoneCleanup(confirmedZones: [], changes: [deleted])
                && !Tasks.hasDeletedZoneCleanup(confirmedZones: [zone], changes: [added]),
                "Only retained changes for a missing Zone need the Site-level cleanup entry")
        var legacyFields = zone.members![0].fields
        legacyFields.removeValue(forKey: "deviceAddress")
        let legacy = SiteTriggerZoneDeviceSyncChange(zoneID: zone.zoneId,
            previousMembers: .array([.object(legacyFields)]), targetMembers: .array([]))
        let restoredLegacy = try? Tasks.reconstructPreviousZones(
            confirmedZones: [], changes: [legacy], resolve: { candidate in
                if let members = candidate.members { return members }
                guard case .array(let values) = candidate.fields["members"],
                      values.count == 1,
                      case .object(var fields) = values[0] else { return nil }
                fields["deviceAddress"] = .integer(1)
                return SiteTriggerZoneMember(value: .object(fields)).map { [$0] }
            }).get()
        require(restoredLegacy?.first?.members == zone.members,
                "Legacy trigger-only members must be normalized before old target planning")
        let legacyTasks = Tasks.makePlan(
            previous: Policy.makePlan(spaces: [space], zones: restoredLegacy!),
            target: Policy.makePlan(spaces: [space], zones: []),
            selectedZoneID: zone.zoneId, previousZones: restoredLegacy!,
            confirmedZones: [], siteSpaceOrder: ["A"])
        require(!legacyTasks.issues.contains(.invalidPreviousMembers(zone.zoneId)),
                "Normalized legacy members must drive old-Space ordering without a false blocker")
        let stale = SiteTriggerZoneDeviceSyncChange(zoneID: zone.zoneId,
            previousMembers: .array([]), targetMembers: .array([]))
        switch Tasks.reconstructPreviousZones(confirmedZones: [zone], changes: [stale],
                                               resolve: { $0.members }) {
        case .failure(.staleTarget(zone.zoneId)): break
        default: preconditionFailure("A stale change must not be projected onto a newer cloud target")
        }
        switch Tasks.reconstructPreviousZones(confirmedZones: [zone], changes: [added, added],
                                               resolve: { $0.members }) {
        case .failure(.duplicateChange(zone.zoneId)): break
        default: preconditionFailure("Duplicate historical changes must block attribution")
        }
    }

    private static func makeSpace(_ id: String, addresses: [UInt16], edges: [UInt16: [UInt16]],
                                  primaryAt: Set<UInt16> = [], boundAt: Set<UInt16> = [],
                                  unknownKeyAt: Set<UInt16> = [],
                                  missingNetKeyAt: Set<UInt16> = [], targetTTL: UInt8? = 0,
                                  missingSpaceKey: Bool = false) -> Policy.SpaceSnapshot {
        let nodes = addresses.map { address in
            Policy.NodeSnapshot(
                id: .init(spaceID: id, nodeUUID: UUID()),
                primaryAddress: address,
                address: address,
                groupAddress: 0xC000,
                primaryNetKey: missingNetKeyAt.contains(address) ? .absent : .present,
                primaryAppKey: unknownKeyAt.contains(address) ? .unknown
                    : primaryAt.contains(address) ? .present : .absent,
                primaryModelBind: boundAt.contains(address) ? .present : .absent
            )
        }
        let targets = Dictionary(uniqueKeysWithValues: addresses.map { address in
            (address, Local.Target(enabled: true, relayNumber: 2,
                                   neighborAddresses: edges[address] ?? []))
        })
        let sources = Dictionary(uniqueKeysWithValues: addresses.map { address in
            (address, Set<Local.Source>([.groupProfile(0xC000)]).union(
                (edges[address] ?? []).isEmpty ? [] : [.groupPath(0xC000)]))
        })
        let neighborSources = Dictionary(uniqueKeysWithValues: addresses.map { address in
            (address, Dictionary(uniqueKeysWithValues: (edges[address] ?? []).map { neighbor in
                (neighbor, Set<Local.Source>([.groupPath(0xC000)]))
            }))
        })
        let spaceIndex = UInt16(id.utf8.first ?? 1)
        return .init(id: id, meshUUID: meshUUID, nodes: nodes,
                     spaceKey: missingSpaceKey ? nil : .init(networkIndex: spaceIndex,
                                                             applicationIndex: spaceIndex,
                                                             materialIdentity: "\(id)-space-key"),
                     primaryKey: .init(networkIndex: 0, applicationIndex: 0,
                                       materialIdentity: "site-primary-key"),
                     targetTTL: targetTTL,
                     localPlan: .init(targets: targets, capacityViolations: [],
                                      sourcesByAddress: sources,
                                      neighborSourcesByAddress: neighborSources))
    }

    private static func makeZone(_ nodes: [Policy.NodeSnapshot]) -> SiteTriggerZone {
        var zone = SiteTriggerZone()
        zone.replaceMembers(nodes.map {
            SiteTriggerZoneMember(identity: $0.id, groupAddress: $0.groupAddress!,
                                  primaryAddress: $0.primaryAddress, deviceAddress: $0.address)
        })
        return zone
    }

    private static let meshUUID = UUID()

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
    }
}
