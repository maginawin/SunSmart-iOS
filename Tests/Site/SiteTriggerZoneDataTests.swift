import Foundation

@main
struct SiteTriggerZoneDataTests {
    static func cleanupPreservesReceiptsAndUnknownMembers() {
        let existing = SiteTriggerZoneMember(identity: .init(spaceID: "editable", nodeUUID: UUID()),
            groupAddress: 0xC001, primaryAddress: 16, deviceAddress: 16)
        var obsolete = existing
        obsolete.fields["nodeUUID"] = .string(UUID().uuidString)
        obsolete.fields["deviceAddress"] = nil
        obsolete.fields["triggerElementAddress"] = .integer(32)
        var unknown = existing
        unknown.fields["spaceId"] = .string("unavailable")
        unknown.fields["futureMember"] = .integer(99)
        var zone = SiteTriggerZone()
        zone.fields["name"] = .string("Keep")
        zone.fields["futureZone"] = .string("untouched")
        zone.fields["members"] = .array([.object(existing.fields), .object(obsolete.fields), .object(unknown.fields)])
        var data = SiteExtensionData()
        data.fields["schemaVersion"] = .integer(2)
        data.fields["futureSetting"] = .integer(5)
        data.replaceZones([zone])
        let classify: (SiteJSONValue) -> SiteTriggerZoneReferenceCleanup.Classification = { value in
            guard case .object(let fields) = value else { return .unknown }
            if fields["spaceId"] == .string("unavailable") { return .unknown }
            return fields["triggerElementAddress"] != nil ? .obsolete : .valid
        }
        let cleaned = SiteTriggerZoneReferenceCleanup.clean(data, classify: classify)
        precondition(cleaned.zones?.first?.fields["members"] == .array([.object(existing.fields), .object(unknown.fields)]))
        precondition(cleaned.zones?.first?.zoneId == zone.zoneId && cleaned.zones?.first?.fields["futureZone"] == zone.fields["futureZone"])
        precondition(cleaned.fields["futureSetting"] == data.fields["futureSetting"])
        precondition(SiteTriggerZoneReferenceCleanup.clean(cleaned, classify: classify) == cleaned)
        var state = SiteTriggerZoneState()
        state.receive(data, timestamp: 10)
        state.commit(cleaned, now: 20, siteTimestamp: 10)
        precondition(state.pending != nil && state.serverData == data, "Cleanup does not fabricate a cloud receipt")
        state.receive(cleaned, timestamp: 21)
        precondition(state.pending == nil && state.deviceSyncChanges?.first?.previousMembers == zone.fields["members"],
                     "Keep previous members after upload for surviving peer cleanup")
    }
    static func main() throws {
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message)
        }
        cleanupPreservesReceiptsAndUnknownMembers()
        var data = SiteExtensionData()
        let zones = (0..<100).map { _ in SiteTriggerZone() }
        data.replaceZones(zones)
        check(data.supportsEmptyZoneEditing, "100 Site zones are supported")
        check(Set(zones.map(\.zoneId)).count == 100, "Empty zones have distinct durable identities")
        check(tryRoundTrip(data) == data, "IDs and order survive serialization")
        data.replaceZones(zones + [SiteTriggerZone()])
        check(!data.supportsEmptyZoneEditing, "101 zones must not be silently truncated")
        data.replaceZones([zones[0], zones[0]])
        check(!data.supportsEmptyZoneEditing, "Duplicate IDs must block editing")
        data.replaceZones([zones[0]])
        data.fields["futureSetting"] = .object(["value": .integer(Int64.max)])
        check(tryRoundTrip(data) == data, "Unknown extension values survive roundtrip")
        let object = try data.jsonObject()
        let text = String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
        let parsedObject = try SiteExtensionData.parse(object)
        let parsedText = try SiteExtensionData.parse(text)
        check(parsedObject == data && parsedText == data,
              "Server object and JSON-string extensions preserve zones and unknown fields equally")
        let emptyObject = try SiteExtensionData.parse([String: Any]())
        let emptyText = try SiteExtensionData.parse("{}")
        check(emptyText == emptyObject && emptyText.fields["triggerZones"] == nil,
              "The startup response extensionData string is a missing-zone patch, not a deletion")
        let invalidValues: [Any] = [NSNull(), 7, true, [Any](), "", "invalid", "[]", "null", "7",
                                    "true", "\"{}\"", ["invalid": Date()], ["invalid": Double.nan]]
        for value in invalidValues {
            do {
                _ = try SiteExtensionData.parse(value)
                preconditionFailure("Invalid extension must throw a catchable Swift error")
            } catch { /* Unsupported remote data must never raise an Objective-C exception. */ }
        }
        var startup = SiteTriggerZoneState()
        startup.receive(data, timestamp: 10)
        startup.receive(emptyText, timestamp: 11)
        check(startup.data.zones == data.zones, "Stringified empty object does not erase existing zones")
        startup.commit(SiteExtensionData(), now: 20, siteTimestamp: 11)
        let startupPending = startup.pending
        startup.receive(emptyText, timestamp: 30)
        check(startup.pending == startupPending, "Startup stringified empty object cannot acknowledge pending edits")
        var state = SiteTriggerZoneState()
        state.receive(SiteExtensionData(), timestamp: 10)
        state.commit(data, now: 20, siteTimestamp: 10)
        check(state.pending != nil, "Local changes are durable pending work")
        let first = state.pending!
        state.submitted = first
        var secondData = data
        secondData.replaceZones([zones[0], zones[1]])
        state.commit(secondData, now: 20, siteTimestamp: 10)
        state.receive(first.target, timestamp: first.timestamp)
        check(state.data == secondData && state.pending != nil && !state.conflict,
              "An older own response rebases the new draft without discarding it")
        check(state.pending?.base == first.target, "The next request compares against the acknowledged base")
        let second = state.pending!
        state.receive(second.target, timestamp: second.timestamp)
        check(state.pending == nil && state.data == secondData, "Exact readback acknowledges the current draft")
        var serverClock = SiteTriggerZoneState()
        serverClock.receive(SiteExtensionData(), timestamp: 100)
        serverClock.commit(data, now: 10_000, siteTimestamp: 100)
        serverClock.submitted = serverClock.pending
        serverClock.receive(data, timestamp: 101)
        check(serverClock.pending == nil && serverClock.serverTimestamp == 101,
              "Server-generated time confirms an exact readback despite a newer local ordering token")
        serverClock.commit(secondData, now: 10_001, siteTimestamp: 101)
        let skewedFirst = serverClock.pending!
        serverClock.submitted = skewedFirst
        serverClock.commit(data, now: 10_002, siteTimestamp: 101)
        serverClock.receive(skewedFirst.target, timestamp: 102)
        check(serverClock.pending?.target == data && serverClock.pending?.base == secondData,
              "An older submitted readback rebases a newer local edit under server time")
        var missing = SiteExtensionData()
        missing.fields.removeValue(forKey: "triggerZones")
        state.receive(missing, timestamp: second.timestamp + 1)
        check(state.data.zones?.count == 2, "Missing zones do not erase existing zones")
        var deleted = secondData
        deleted.replaceZones([])
        state.commit(deleted, now: 30, siteTimestamp: 10)
        let deletion = state.pending!
        state.receive(missing, timestamp: 50)
        check(state.pending == deletion, "Missing fields cannot confirm a pending deletion")
        state.receive(deleted, timestamp: deletion.timestamp)
        check(state.data.zones?.isEmpty == true && state.pending == nil, "Explicit empty array confirms deletion")
        state.commit(data, now: 60, siteTimestamp: 10)
        let superseded = state.pending!
        state.receive(secondData, timestamp: 61)
        check(!state.conflict && state.data == secondData && state.pending == nil
                && state.archivedPendings == [superseded] && state.needsArchivedReview,
              "A complete conflicting server version becomes active and archives the local edit")
        state.acknowledgeArchivedReview()
        check(!state.needsArchivedReview && state.archivedPendings == [superseded],
              "Acknowledging a review does not delete the archived snapshot")
        state.discardPending()
        check(state.data == secondData && state.pending == nil,
              "Discard after server takeover does not resurrect an old local target")
        let beforeOldResponse = state
        state.receive(SiteExtensionData(), timestamp: 1)
        check(state == beforeOldResponse, "Old responses cannot resurrect deleted or replaced data")
        var ambiguous = SiteTriggerZoneState()
        ambiguous.receive(data, timestamp: 100)
        ambiguous.receive(secondData, timestamp: 100)
        check(ambiguous.hasAmbiguousRemote && ambiguous.data == data
                && ambiguous.serverData == data && ambiguous.serverTimestamp == 100,
              "Equal server versions with different content cannot replace a confirmed target")
        ambiguous.receive(secondData, timestamp: 101)
        check(!ambiguous.hasAmbiguousRemote && ambiguous.data == secondData,
              "A newer version resolves an ambiguous response")
        var future = data
        future.fields["schemaVersion"] = .integer(3)
        check(!future.supportsMemberEditing && tryRoundTrip(future) == future, "Future schema is retained and read-only")
        var nonempty = zones[0]
        nonempty.fields["members"] = .array([.object(["spaceId": .string("private")])])
        future = SiteExtensionData()
        future.replaceZones([nonempty])
        check(!future.supportsEmptyZoneEditing, "Nonempty members cannot be edited by phase-one controls")
        let identity = SiteTriggerZoneMember.Identity(spaceID: "space-A", nodeUUID: UUID())
        var member = SiteTriggerZoneMember(identity: identity, groupAddress: 0xC001,
                                           primaryAddress: 0x0120, deviceAddress: 0x0121)
        member.fields["laterClientField"] = .object(["value": .bool(true)])
        var editable = zones[0]
        editable.replaceMembers([member])
        var memberData = SiteExtensionData()
        memberData.fields["schemaVersion"] = .integer(2)
        memberData.replaceZones([editable])
        check(memberData.supportsMemberEditing && editable.members == [member], "Version 2 members retain stable identity and extension fields")
        var legacyFields = member.fields
        legacyFields.removeValue(forKey: "deviceAddress")
        legacyFields["triggerElementAddress"] = .integer(0x0120)
        var legacyZone = SiteTriggerZone()
        legacyZone.fields["members"] = .array([.object(legacyFields)])
        var legacyData = memberData
        legacyData.replaceZones([legacyZone, editable])
        check(legacyZone.members == nil && legacyZone.hasCompleteDisplayMembers
                && legacyZone.displayMembers.first?.identity == identity,
              "Legacy trigger addresses retain visible member identity without guessing a device address")
        var normalizedFields = legacyFields
        normalizedFields.removeValue(forKey: "triggerElementAddress")
        normalizedFields["deviceAddress"] = .integer(0x0120)
        let metadataMigration = SiteTriggerZoneDeviceSyncChange(
            zoneID: legacyZone.zoneId,
            previousMembers: .array([.object(legacyFields)]),
            targetMembers: .array([.object(normalizedFields)]))
        check(metadataMigration.knownMemberImpact == .init(added: 0, removed: 0, changed: 0)
                && !metadataMigration.hasKnownDeviceDelta,
              "Matching legacy and normalized addresses remain unverified, not a known device delta")
        let addressChange = SiteTriggerZoneDeviceSyncChange(
            zoneID: legacyZone.zoneId,
            previousMembers: .array([.object(legacyFields)]),
            targetMembers: .array([.object(member.fields)]))
        check(addressChange.knownMemberImpact == .init(added: 0, removed: 0, changed: 1)
                && addressChange.hasKnownDeviceDelta,
              "A changed normalized device address remains pending")
        let addedMember = SiteTriggerZoneDeviceSyncChange(zoneID: legacyZone.zoneId,
            previousMembers: .array([]), targetMembers: .array([.object(normalizedFields)]))
        check(addedMember.knownMemberImpact == .init(added: 1, removed: 0, changed: 0)
                && addedMember.hasKnownDeviceDelta,
              "New device membership remains pending")
        let removedMember = SiteTriggerZoneDeviceSyncChange(zoneID: legacyZone.zoneId,
            previousMembers: .array([.object(normalizedFields)]), targetMembers: .array([]))
        check(removedMember.knownMemberImpact == .init(added: 0, removed: 1, changed: 0),
              "A removed Zone member remains attributable after its card disappears")
        let invalidChange = SiteTriggerZoneDeviceSyncChange(zoneID: legacyZone.zoneId,
            previousMembers: .string("invalid"), targetMembers: .array([]))
        check(invalidChange.knownMemberImpact == nil && invalidChange.hasKnownDeviceDelta,
              "Malformed old members must not be silently treated as settled")
        check(!legacyData.supportsMemberEditing && legacyData.supportsZoneEditing(editable.zoneId)
                && !legacyData.supportsZoneEditing(legacyZone.zoneId),
              "A legacy Zone remains read-only without blocking an independent valid Zone")
        var incidentServer = SiteExtensionData()
        incidentServer.fields["schemaVersion"] = .integer(2)
        incidentServer.replaceZones([legacyZone, SiteTriggerZone()])
        var incidentLocal = SiteExtensionData()
        incidentLocal.replaceZones([zones[0], zones[1], zones[2]])
        var incidentState = SiteTriggerZoneState()
        incidentState.receive(incidentLocal, timestamp: 100)
        incidentState.commit(data, now: 101, siteTimestamp: 100)
        incidentState.receive(incidentServer, timestamp: 102)
        check(incidentState.pending == nil && incidentState.data.zones?.count == 2
                && incidentState.data.zones?.first?.displayMembers.count == 1
                && incidentState.archivedPendings?.count == 1,
              "A three-Zone local draft yields to two confirmed server Zones without hiding legacy members")
        var updatedValidZone = editable
        updatedValidZone.replaceMembers([])
        check(legacyData.replacingZone(updatedValidZone)?.zones?.first == legacyZone,
              "A valid row update preserves an unrelated legacy Zone verbatim")
        check(tryRoundTrip(memberData) == memberData, "Version 2 members survive roundtrip")
        var serverExtension = SiteExtensionData()
        var otherZone = zones[2]
        otherZone.fields["futureZoneField"] = .object(["flag": .bool(true)])
        serverExtension.fields["futureSiteField"] = .array([.string("retained")])
        serverExtension.replaceZones([zones[0], otherZone])
        let fullUpdate = serverExtension.replacingZone(editable)!
        check(fullUpdate.zones == [editable, otherZone]
                && fullUpdate.fields["futureSiteField"] == serverExtension.fields["futureSiteField"]
                && fullUpdate.fields["schemaVersion"] == .integer(2)
                && fullUpdate.supportsMemberEditing,
              "A row Save sends the full server extension with other Zones and unknown fields")
        let parsedFullUpdate = try SiteExtensionData.parse(fullUpdate.jsonObject())
        check(parsedFullUpdate == fullUpdate,
              "The complete extensionData request payload roundtrips")
        let props = try SiteTriggerZoneUpdatePayload.props(extensionData: fullUpdate)
        check(props.keys.sorted() == ["extensionData"],
              "Site Trigger Zone updates let the server assign updateTimestamp")
        let parsedProps = try SiteExtensionData.parse(props["extensionData"]!)
        check(parsedProps == fullUpdate, "The update request contains the complete extension object")
        var receipt = SiteTriggerZoneState()
        receipt.receive(serverExtension, timestamp: 100)
        receipt.commit(fullUpdate, now: 10_000, siteTimestamp: 100)
        receipt.submitted = receipt.pending
        receipt.receive(fullUpdate, timestamp: 101)
        check(receipt.pending == nil && receipt.deviceSyncChanges?.count == 1
                && receipt.deviceSyncChanges?.first?.zoneID == editable.zoneId
                && receipt.deviceSyncChanges?.first?.previousMembers == .array([])
                && receipt.deviceSyncChanges?.first?.targetMembers == editable.fields["members"],
              "Any confirmed readback retains device cleanup evidence under server time")
        receipt.commit(serverExtension, now: 10_001, siteTimestamp: 101)
        receipt.receive(serverExtension, timestamp: 102)
        check(receipt.deviceSyncChanges?.isEmpty == true,
              "Returning to the original members clears the outstanding device change")
        var deletedZoneTarget = fullUpdate
        deletedZoneTarget.replaceZones([otherZone])
        var deletedZoneReceipt = SiteTriggerZoneState()
        deletedZoneReceipt.receive(fullUpdate, timestamp: 100)
        deletedZoneReceipt.commit(deletedZoneTarget, now: 101, siteTimestamp: 100)
        deletedZoneReceipt.receive(deletedZoneTarget, timestamp: 102)
        check(deletedZoneReceipt.deviceSyncChanges?.count == 1
                && deletedZoneReceipt.deviceSyncChanges?.first?.zoneID == editable.zoneId
                && deletedZoneReceipt.deviceSyncChanges?.first?.previousMembers == editable.fields["members"]
                && deletedZoneReceipt.deviceSyncChanges?.first?.targetMembers == .array([]),
              "Deleting a nonempty Zone retains its old members for later device cleanup")
        var localOther = otherZone
        localOther.fields["localOnly"] = .bool(true)
        var localTwoZoneEdit = fullUpdate
        localTwoZoneEdit.replaceZones([editable, localOther])
        var rowReceipt = SiteTriggerZoneState()
        rowReceipt.receive(serverExtension, timestamp: 100)
        rowReceipt.commit(localTwoZoneEdit, now: 10_000, siteTimestamp: 100)
        rowReceipt.submitted = .init(operationId: UUID(), timestamp: 10_001,
                                     base: serverExtension, target: fullUpdate)
        rowReceipt.receive(fullUpdate, timestamp: 101)
        check(rowReceipt.pending?.target == localTwoZoneEdit
                && rowReceipt.pending?.base == fullUpdate
                && rowReceipt.deviceSyncChanges?.count == 1
                && rowReceipt.deviceSyncChanges?.first?.zoneID == editable.zoneId,
              "A row Save records only confirmed members and retains another Zone's local pending edit")
        check(serverExtension.replacingZone(zones[3])?.zones == [zones[0], otherZone, zones[3]],
              "Adding one Zone retains all existing server Zones")
        var draft = SiteTriggerZoneDraft(zone: zones[1])!
        check(draft.add(member) && draft.isDirty, "Adding creates only a page draft")
        check(!draft.add(member) && draft.members.count == 1, "Duplicate member identity is ignored")
        draft.reset()
        check(!draft.isDirty && draft.members.isEmpty, "Reset discards unsaved changes")
        check(!draft.remove(identity) && draft.add(member) && draft.remove(identity) && !draft.isDirty,
              "Remove and re-add compare against the saved base")
        var coveredBase = SiteExtensionData()
        coveredBase.replaceZones([zones[0], zones[1]])
        var coveredFirst = zones[0]
        coveredFirst.replaceMembers([member])
        var coveredSecond = zones[1]
        coveredSecond.replaceMembers([member])
        var coveredServer = coveredBase
        coveredServer.fields["schemaVersion"] = .integer(2)
        coveredServer.replaceZones([coveredFirst, zones[1]])
        var coveredTarget = coveredServer
        coveredTarget.replaceZones([coveredFirst, coveredSecond, zones[2], zones[3]])
        var coveredState = SiteTriggerZoneState()
        coveredState.receive(coveredBase, timestamp: 100)
        coveredState.commit(coveredTarget, now: 101, siteTimestamp: 100)
        coveredState.receive(coveredServer, timestamp: 102)
        check(!coveredState.conflict && coveredState.pending?.base == coveredServer
                && coveredState.pending?.target == coveredTarget && coveredState.data == coveredTarget,
              "A server change already present in the local target safely rebases without dropping new Zones")
        check(coveredState.deviceSyncChanges?.first?.zoneID == coveredFirst.zoneId,
              "The already-confirmed server member change retains its device-sync evidence")
        coveredState.receive(coveredTarget, timestamp: 103)
        check(coveredState.pending == nil && coveredState.deviceSyncChanges?.count == 2,
              "Later cloud confirmation preserves both earlier and newly confirmed device changes")
        var incompatibleTarget = coveredTarget
        var incompatibleFirst = zones[0]
        incompatibleFirst.replaceMembers([])
        incompatibleTarget.replaceZones([incompatibleFirst, coveredSecond, zones[2], zones[3]])
        var incompatibleState = SiteTriggerZoneState()
        incompatibleState.receive(coveredBase, timestamp: 100)
        incompatibleState.commit(incompatibleTarget, now: 101, siteTimestamp: 100)
        incompatibleState.receive(coveredServer, timestamp: 102)
        check(!incompatibleState.conflict && incompatibleState.pending == nil
                && incompatibleState.data == coveredServer
                && incompatibleState.archivedPendings?.first?.target == incompatibleTarget,
              "An irreconcilable same-Zone target is archived without replacing the server")
        var duplicate = editable
        duplicate.replaceMembers([member, member])
        memberData.replaceZones([duplicate])
        check(!memberData.supportsMemberEditing, "Duplicate persisted members must not become editable")
        var malformed = editable
        malformed.fields["members"] = .array([.object(["spaceId": .string("space-A")])])
        memberData.replaceZones([malformed])
        check(!memberData.supportsMemberEditing, "Malformed members remain read-only")
        let invalidAddress = SiteJSONValue.object([
            "spaceId": .string("space-A"), "nodeUUID": .string(identity.nodeUUID.uuidString),
            "groupAddress": .integer(0xC001), "primaryAddress": .integer(0x0120),
            "deviceAddress": .integer(0x011F)
        ])
        check(SiteTriggerZoneMember(value: invalidAddress) == nil,
              "A normalized device address before the node primary cannot be persisted")
        var syncState = SiteTriggerZoneState()
        let cleanupGeneration = UUID()
        syncState.referenceCleanupRequests = ["account": cleanupGeneration]
        syncState.deviceSyncChanges = [.init(zoneID: editable.zoneId, previousMembers: .array([]),
                                             targetMembers: editable.fields["members"]!)]
        let restoredSyncState = try JSONDecoder().decode(SiteTriggerZoneState.self,
            from: JSONEncoder().encode(syncState))
        check(restoredSyncState == syncState,
            "Device cleanup evidence survives restart after cloud confirmation")
        var legacyObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(syncState)) as! [String: Any]
        legacyObject.removeValue(forKey: "referenceCleanupRequests")
        let legacyState = try JSONDecoder().decode(SiteTriggerZoneState.self,
            from: JSONSerialization.data(withJSONObject: legacyObject))
        check(legacyState.referenceCleanupRequests == nil, "Old local states decode without cleanup requests")
        syncState.receive(syncState.data, timestamp: 100)
        check(syncState.referenceCleanupRequests?["account"] == cleanupGeneration,
              "Remote reception cannot acknowledge local reference cleanup")
        let cloudObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(syncState.data)) as! [String: Any]
        check(cloudObject["referenceCleanupRequests"] == nil, "Local cleanup requests never enter cloud extension data")
        let restored = try JSONDecoder().decode(SiteTriggerZoneState.self, from: JSONEncoder().encode(state))
        check(restored == state, "Restart restores the full sync state")
        print("PASS: Site Trigger Zone identity, 100-zone limit, compatibility, pending, conflict and restart checks")
    }

    static func tryRoundTrip(_ value: SiteExtensionData) -> SiteExtensionData? {
        guard let encoded = try? JSONEncoder().encode(value) else { return nil }
        return try? JSONDecoder().decode(SiteExtensionData.self, from: encoded)
    }
}
