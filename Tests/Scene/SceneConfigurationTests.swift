import Foundation

@main struct SceneConfigurationTests {
    static func main() throws {
        var passed = 0
        var failed = 0
        func test(_ name: String, _ body: () throws -> Bool) {
            do {
                if try body() { passed += 1 } else { failed += 1; print("FAIL model: \(name)") }
            } catch { failed += 1; print("FAIL model: \(name): \(error)") }
        }
        func rejects(_ body: () throws -> Void) -> Bool {
            do { try body(); return false } catch { return true }
        }
        let a = TimedSchedulerNodeIdentity(nodeUUID: "00000000-0000-0000-0000-00000000000A", unicastAddress: "0001", deviceKeyFingerprint: String(repeating: "A", count: 64))
        let b = TimedSchedulerNodeIdentity(nodeUUID: "00000000-0000-0000-0000-00000000000B", unicastAddress: "0002", deviceKeyFingerprint: String(repeating: "B", count: 64))
        let on = SceneParameters(isOn: true, lightness: 19660, cct: 4500)
        let off = SceneParameters(isOn: false, lightness: 50000, cct: 3000)
        let members = [SceneDeviceMember(identity: a, parameters: on), .init(identity: b, parameters: off)]
        let config = SceneConfiguration(kind: .devices, name: "Evening", deviceMembers: members,
            pendingOperations: [.init(identity: a, action: .write)])
        test("memberParametersAndPendingIntentRoundTrip") {
            let loaded = try SceneConfiguration.decode(config.encoded())
            return loaded == config && loaded.deviceMembers[1].parameters.isOn == false
        }
        test("duplicateIdentityIsRejected") {
            var bad = config; bad.deviceMembers.append(members[0])
            return rejects { _ = try bad.encoded() }
        }
        test("caseVariantsCannotDuplicateIdentity") {
            var bad = config
            bad.deviceMembers.append(.init(identity: .init(nodeUUID: a.nodeUUID.lowercased(), unicastAddress: a.unicastAddress,
                deviceKeyFingerprint: a.deviceKeyFingerprint.lowercased()), parameters: off))
            return rejects { _ = try bad.encoded() }
        }
        test("groupModeRejectsDeviceMembers") {
            var bad = config; bad.kind = .groups
            return rejects { _ = try bad.encoded() }
        }
        test("corruptBlockDoesNotBecomeEmpty") {
            rejects { _ = try SceneConfiguration.decode(Data("{}".utf8)) }
                && rejects { _ = try SceneConfiguration.decode(Data("null".utf8)) }
        }
        test("unknownVersionIsRejected") {
            var bad = config; bad.schemaVersion = 3
            return rejects { _ = try bad.encoded() }
        }
        test("versionOneDeletionWithoutReferenceBlockRemainsReadable") {
            var legacy = config
            legacy.isDeleting = true
            legacy.pendingOperations = [.init(identity: a, action: .remove)]
            let encoded = try legacy.encoded()
            let object = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
            let loaded = try SceneConfiguration.decode(encoded)
            return object["deletionReferences"] == nil && loaded == legacy
                && loaded.schemaVersion == 1 && loaded.deletionReferences == nil
        }
        let schedulerCleanup = SceneReferenceRemoval(kind: .scheduler, identity: a, address: 1,
            name: "Old Timed", slots: [0, 15])
        let unknownProxyCleanup = SceneReferenceRemoval(kind: .kinetic, identity: nil, address: 3,
            objectID: "kinetic-1", name: "Offline Proxy", keys: [1, 2])
        let references = SceneDeletionReferences(scheduleIDs: [4, 31], pending: [schedulerCleanup, unknownProxyCleanup])
        let deleting = SceneConfiguration(schemaVersion: 2, kind: .devices, name: "Deleting",
            deviceMembers: members, pendingOperations: [.init(identity: a, action: .remove)],
            isDeleting: true, deletionReferences: references)
        test("versionTwoRetainsCleanupOwnershipAndUnresolvedIdentity") {
            let loaded = try SceneConfiguration.decode(deleting.encoded())
            return loaded == deleting && loaded.deletionReferences?.scheduleIDs == [4, 31]
                && loaded.deletionReferences?.pending.first?.id == schedulerCleanup.id
                && loaded.deletionReferences?.pending.last?.identity == nil
                && loaded.deletionReferences?.pending.last?.address == 3
        }
        test("versionTwoRequiresDeletionAndReferenceBlock") {
            var missing = deleting; missing.deletionReferences = nil
            var active = deleting; active.isDeleting = false
            var downgraded = deleting; downgraded.schemaVersion = 1
            return rejects { _ = try missing.encoded() }
                && rejects { _ = try active.encoded() }
                && rejects { _ = try downgraded.encoded() }
        }
        test("cleanupIdentityNormalizesOnRoundTrip") {
            var lower = deleting
            lower.deletionReferences?.pending[0].identity = .init(nodeUUID: a.nodeUUID.lowercased(),
                unicastAddress: a.unicastAddress.lowercased(), deviceKeyFingerprint: a.deviceKeyFingerprint.uppercased())
            let loaded = try SceneConfiguration.decode(lower.encoded())
            return loaded.deletionReferences?.pending[0].identity == a
        }
        test("referenceOnlyRestoreMigratesIdentityWithoutAddingSceneWrite") {
            let replacement = TimedSchedulerNodeIdentity(nodeUUID: a.nodeUUID, unicastAddress: "0010", deviceKeyFingerprint: b.deviceKeyFingerprint)
            let original = SceneConfiguration(schemaVersion: 2, kind: .groups, name: "Reference-only",
                isDeleting: true, deletionReferences: .init(scheduleIDs: [4], pending: [schedulerCleanup]))
            let migrated = try original.restoringIdentity(from: a, to: replacement)
            let removed = try original.removingConfirmedIdentities([a])
            return migrated.deletionReferences?.pending.first?.identity == replacement
                && migrated.deletionReferences?.pending.first?.address == 0x10
                && migrated.pendingOperations.isEmpty && migrated.revision != original.revision
                && removed.deletionReferences?.pending.isEmpty == true && removed.deletionReferences?.scheduleIDs == [4]
        }
        test("missingOrNullVersionTwoDependenciesCannotDecodeAsCompleted") {
            let object = try JSONSerialization.jsonObject(with: deleting.encoded()) as! [String: Any]
            return [nil, NSNull() as Any?].allSatisfy { value in
                var missing = object; missing["deletionReferences"] = value
                return rejects { _ = try SceneConfiguration.decode(JSONSerialization.data(withJSONObject: missing)) }
            }
        }
        test("completedReferenceCleanupRetainsSchedulesUntilFinalization") {
            var settled = deleting
            settled.deletionReferences?.pending = []
            let loaded = try SceneConfiguration.decode(settled.encoded())
            return loaded.isDeleting && loaded.deletionReferences?.pending.isEmpty == true
                && loaded.deletionReferences?.scheduleIDs == [4, 31]
                && loaded.pendingOperations == settled.pendingOperations
        }
        test("invalidSchedulerSlotsCannotEnterCleanupQueue") {
            return [[-1], [16], [2, 2]].allSatisfy { slots in
                var invalid = deleting
                invalid.deletionReferences?.pending[0].slots = slots
                return rejects { _ = try invalid.encoded() }
            }
        }
        test("cleanupAddressMustBeUnicastAndMatchKnownIdentity") {
            return [UInt16(0), 0x8000, 0xFFFF, 2].allSatisfy { address in
                var invalid = deleting
                invalid.deletionReferences?.pending = [.init(kind: .scheduler, identity: a,
                    address: address, name: "Invalid target", slots: [0])]
                return rejects { _ = try invalid.encoded() }
            }
        }
        test("incomingInvalidCleanupTargetsAreRejectedBeforeRecovery") {
            let object = try JSONSerialization.jsonObject(with: deleting.encoded()) as! [String: Any]
            let invalidFields: [(String, Any)] = [("slots", [-1]), ("slots", [16]),
                ("slots", [1, 1]), ("address", 0), ("address", 0x8000), ("address", 2)]
            return invalidFields.allSatisfy { field, value in
                var corrupted = object
                var block = corrupted["deletionReferences"] as! [String: Any]
                var pending = block["pending"] as! [[String: Any]]
                pending[0][field] = value
                block["pending"] = pending
                corrupted["deletionReferences"] = block
                return rejects { _ = try SceneConfiguration.decode(JSONSerialization.data(withJSONObject: corrupted)) }
            }
        }
        test("duplicateCleanupIDsAndScheduleIDsAreRejected") {
            var duplicateTask = deleting
            duplicateTask.deletionReferences?.pending.append(schedulerCleanup)
            var duplicateSchedule = deleting
            duplicateSchedule.deletionReferences?.scheduleIDs.append(4)
            return rejects { _ = try duplicateTask.encoded() }
                && rejects { _ = try duplicateSchedule.encoded() }
        }
        test("controllerCleanupRequiresBusinessObjectIdentity") {
            return [SceneReferenceRemoval.Kind.kinetic, .powerSwitch, .emergency].allSatisfy { kind in
                var invalid = deleting
                invalid.deletionReferences?.pending = [.init(kind: kind, identity: b, address: 2,
                    name: "Missing controller ID", keys: [1])]
                return rejects { _ = try invalid.encoded() }
            }
        }
        test("controllerCleanupRequiresDistinctKeysInKindRange") {
            let invalidKeys: [(SceneReferenceRemoval.Kind, [Int])] = [
                (.kinetic, []), (.kinetic, [0]), (.kinetic, [5]), (.kinetic, [1, 1]),
                (.powerSwitch, []), (.powerSwitch, [-1]), (.powerSwitch, [4]), (.powerSwitch, [0, 0]),
                (.emergency, []), (.emergency, [-1]), (.emergency, [2]), (.emergency, [1, 1])]
            return invalidKeys.allSatisfy { kind, keys in
                var invalid = deleting
                invalid.deletionReferences?.pending = [.init(kind: kind, identity: b, address: 2,
                    objectID: "controller", name: "Invalid keys", keys: keys)]
                return rejects { _ = try invalid.encoded() }
            }
        }
        test("cleanupKindsDoNotAcceptEachOthersPayload") {
            var scheduler = deleting
            scheduler.deletionReferences?.pending = [.init(kind: .scheduler, identity: a, address: 1,
                name: "Scheduler", keys: [1], slots: [0])]
            var controller = deleting
            controller.deletionReferences?.pending = [.init(kind: .kinetic, identity: b, address: 2,
                objectID: "switch", name: "Switch", keys: [1], slots: [0])]
            return rejects { _ = try scheduler.encoded() } && rejects { _ = try controller.encoded() }
        }
        test("invalidIdentityAndConflictingOperationsAreRejected") {
            var bad = config
            bad.pendingOperations.append(.init(identity: a, action: .remove))
            let duplicateRejected = rejects { _ = try bad.encoded() }
            bad = config
            bad.deviceMembers[0] = .init(identity: .init(nodeUUID: "invalid", unicastAddress: "8000", deviceKeyFingerprint: "secret"), parameters: on)
            return duplicateRejected && rejects { _ = try bad.encoded() }
        }
        test("writeRequiresMemberAndRemoveCannotTargetActiveMember") {
            var bad = config; bad.deviceMembers = []
            let writeRejected = rejects { _ = try bad.encoded() }
            bad = config; bad.pendingOperations = [.init(identity: a, action: .remove)]
            return writeRejected && rejects { _ = try bad.encoded() }
        }
        test("identityIsProvisioningInstanceNotAddress") {
            let replaced = TimedSchedulerNodeIdentity(nodeUUID: b.nodeUUID, unicastAddress: a.unicastAddress, deviceKeyFingerprint: b.deviceKeyFingerprint)
            return a != replaced && a != .init(nodeUUID: a.nodeUUID, unicastAddress: a.unicastAddress, deviceKeyFingerprint: b.deviceKeyFingerprint)
        }
        test("canonicalEncodingIgnoresMemberOrder") {
            var reordered = config; reordered.deviceMembers.reverse()
            return try reordered.encoded() == config.encoded()
        }
        let scope = SceneScope(meshUUID: "mesh", networkID: "net")
        test("draftCopyDoesNotMutateStoredValues") {
            var draft = try SceneDraft(number: 1, scope: scope, name: config.name, imageId: 2,
                kind: .devices, deviceMembers: config.deviceMembers, sourceConfiguration: config)
            let revision = draft.revision
            var changed = draft.deviceMembers; changed[0].parameters = off
            try draft.setDeviceMembers(changed)
            return config.deviceMembers[0].parameters == on && draft.deviceMembers[0].parameters == off && draft.revision != revision
        }
        test("switchModeClearsOtherModeButStoredMembersPreventConversion") {
            var draft = try SceneDraft(scope: scope, name: "new", imageId: 0, kind: .groups, groupParameters: [0xC001: on])
            try draft.switchKind(to: .devices)
            var stored = try SceneDraft(number: 1, scope: scope, name: config.name, imageId: 0, kind: .devices,
                deviceMembers: config.deviceMembers, sourceConfiguration: config)
            try stored.setDeviceMembers([])
            return draft.groupParameters.isEmpty && rejects { try stored.switchKind(to: .groups) }
        }
        test("emptyGroupBindingAndPendingRemovalPreventConversion") {
            var group = try SceneDraft(number: 1, scope: scope, name: "group", imageId: 0, kind: .groups, groupParameters: [0xC001: on])
            let bound = rejects { try group.switchKind(to: .devices) }
            var pending = config; pending.deviceMembers = []; pending.pendingOperations = [.init(identity: a, action: .remove)]
            var draft = try SceneDraft(number: 1, scope: scope, name: "pending", imageId: 0, kind: .devices, sourceConfiguration: pending)
            return bound && rejects { try draft.switchKind(to: .groups) }
        }
        test("emptyStoredSceneCanSwitchAndFailedMutationIsAtomic") {
            var draft = try SceneDraft(number: 1, scope: scope, name: "empty", imageId: 0, kind: .groups)
            try draft.switchKind(to: .devices)
            let before = draft
            return rejects { try draft.setDeviceMembers([members[0], members[0]]) } && draft == before
        }
        print("model: \(passed) passed, \(failed) failed")
        if failed > 0 { exit(1) }
    }
}
