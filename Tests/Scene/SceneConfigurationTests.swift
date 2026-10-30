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
            var bad = config; bad.schemaVersion = 2
            return rejects { _ = try bad.encoded() }
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
