import Foundation

@main
struct SiteTriggerZoneItemPolicyTests {
    static func main() {
        typealias Item = SiteTriggerZoneItemModel
        let fixtures = SiteTriggerZonePreviewFixtures.makeItems { "Zone \($0)" }
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message)
        }
        func item(_ code: String) -> Item { fixtures.first { $0.previewCode == code }! }
        check(fixtures.count == 29, "All approved base fixtures are present")
        check(Set(fixtures.map(\.id)).count == fixtures.count, "Zone IDs are unique")
        check(fixtures == SiteTriggerZonePreviewFixtures.makeItems { "Zone \($0)" }, "Preview identities survive reloads")
        for code in ["S01", "S02", "D01", "D02", "D03", "D06", "T01", "T03", "Q01", "Q03"] {
            check(item(code).canEdit, "Owner/Editor combinations are editable: \(code)")
        }
        for code in ["S03", "S04", "S07", "S08", "D04", "D05", "T02", "T04", "T05", "Q02", "Q04", "B02", "B03", "B04"] {
            check(!item(code).canEdit, "A restricted or unverified Space blocks the whole Zone: \(code)")
        }
        for first in Item.Access.allCases {
            for second in Item.Access.allCases {
                var zone = item("D01")
                zone.spaces[0].access = first
                zone.spaces[1].access = second
                check(zone.canEdit == (first.permitsEditing && second.permitsEditing), "Full role intersection")
            }
        }
        var zone = item("D06")
        zone.hasCompleteSpaceList = false
        check(!zone.canEdit, "An incomplete all-Editor list is not authorization")
        zone = item("D06")
        zone.spaces = [zone.spaces[0], zone.spaces[0]]
        check(!zone.canEdit, "Duplicate Space summaries are not a complete authorized list")
        zone = item("D06")
        zone.allowsEditing = false
        zone.hasUnverifiedMembers = true
        check(!zone.canEdit && zone.spaces.count == 2 && zone.hasCompleteSpaceList,
              "A legacy member blocks edits without hiding known Space sections")
        zone = item("E01")
        zone.canEditEmpty = false
        check(!zone.canEdit && zone.usesEmptyStyle, "An empty list does not grant edit rights")
        zone.isConfirmedEmpty = false
        check(!zone.usesEmptyStyle && !zone.canEdit, "Unknown content cannot become No Data")
        check(item("T05").spaces.count == 3 && !item("T05").usesEmptyStyle && item("T05").dividerCount == 2,
              "All restricted Spaces retain their sections and dividers")
        check(item("Q04").dividerCount == 3 && item("S01").dividerCount == 0, "N Spaces produce N-1 dividers")
        let restricted = item("D05").spaces[1]
        check(!restricted.canDisplayDevices && restricted.devices.isEmpty && restricted.displayedDeviceCount == 3,
              "No access has only an explicitly disclosed count")
        check(item("B04").spaces[0].displayedDeviceCount == nil, "Unknown count must not become zero")
        check(item("B03").spaces[0].access == .editor && !item("B03").spaces[0].canDisplayDevices,
              "Pending verification does not change the role or expose device data")
        check(item("D02").needsSync && item("D02").spaces[0].sync.needsSync && !item("D02").spaces[1].sync.needsSync,
              "Pending work belongs only to the affected Space")
        check(item("B01").sync.needsSync && item("B01").spaces.allSatisfy { !$0.sync.needsSync },
              "Zone metadata work is not attributed to an arbitrary Space")
        var sync = Item.Sync(cloud: .pending, devices: .pending)
        sync.cloud = .settled
        check(sync.needsSync, "Cloud success does not acknowledge device work")
        sync = .init(cloud: .unknown, devices: .unknown)
        check(!sync.needsSync && !sync.isKnown && sync.showsStatus && sync.isUnverified,
              "Unknown needs a visible status without claiming a pending device task")
        check(Item.TaskState.devices(hasMembers: false, hasPendingChange: false) == .settled,
              "An empty Zone without cleanup has no device work")
        check(Item.TaskState.devices(hasMembers: true, hasPendingChange: false) == .unknown,
              "A nonempty Zone without device evidence is unverified")
        check(Item.TaskState.devices(hasMembers: true, hasPendingChange: true) == .pending
                && Item.TaskState.devices(hasMembers: false, hasPendingChange: true) == .pending,
              "Confirmed member changes and old-member cleanup stay pending")
        zone = item("D01")
        zone.sync.devices = .unknown
        check(zone.showsSyncStatus && !zone.needsSync,
              "An unverified Zone stays visible without being reported as synchronized")
        for fixture in fixtures {
            for space in fixture.spaces where space.canDisplayDevices {
                check(space.displayedDeviceCount == space.devices.count, "Count matches displayed members")
            }
            let identities = fixture.spaces.flatMap { space in space.devices.map { space.id + "/" + $0.id } }
            check(Set(identities).count == identities.count, "Same device address in different Spaces stays distinct")
        }
        var presentation = SiteTriggerZonePresentationState()
        let liveID = UUID()
        presentation.select(liveID)
        presentation.togglePreview(defaultSelectedID: item("D02").id)
        check(!presentation.permitsLiveOperations && presentation.selectedID == item("D02").id, "Preview isolates live operations")
        presentation.select(item("Q04").id)
        presentation.reconcileLiveIDs([liveID])
        check(presentation.selectedID == item("Q04").id, "A live result cannot replace preview selection")
        presentation.togglePreview(defaultSelectedID: nil)
        check(presentation.selectedID == liveID && presentation.permitsLiveOperations, "Live selection is restored")
        presentation.togglePreview(defaultSelectedID: nil)
        presentation.reconcileLiveIDs([])
        presentation.togglePreview(defaultSelectedID: nil)
        check(presentation.selectedID == nil, "A deleted live Zone is not resurrected on returning")
        var preview = SiteTriggerZonePreviewState()
        preview.begin(items: fixtures)
        func apply(_ mutation: SiteTriggerZonePreviewState.Mutation, _ id: UUID) -> Bool {
            preview.apply(mutation, zoneID: id, expectedRevision: preview.revision!, zoneName: { "Zone \($0)" })
        }
        for fixture in fixtures where !fixture.canEdit {
            let before = preview.items
            check(!apply(.reset, fixture.id) && !apply(.delete, fixture.id), "Restricted Zone rejects all mutations")
            if let space = fixture.spaces.first, let device = space.devices.first {
                check(!apply(.remove(spaceID: space.id, deviceID: device.id), fixture.id), "Editor side of locked Zone cannot remove")
            }
            check(preview.items == before, "Rejected mutation preserves every member")
        }
        let pair = item("D02")
        let originalRevision = preview.revision!
        check(apply(.remove(spaceID: pair.spaces[0].id, deviceID: "device-0"), pair.id), "Device removal succeeds")
        let changed = preview.items.first { $0.id == pair.id }!
        check(changed.spaces[0].devices.count == 2 && changed.spaces[1] == pair.spaces[1], "Same device ID in another Space is untouched")
        check(preview.items.first { $0.id == item("D01").id } == item("D01"), "Another Zone is untouched")
        check(!preview.apply(.delete, zoneID: pair.id, expectedRevision: originalRevision, zoneName: { "Zone \($0)" }), "Stale menu revision is rejected")
        for device in changed.spaces[0].devices {
            check(apply(.remove(spaceID: changed.spaces[0].id, deviceID: device.id), pair.id), "Remove remaining first Space devices")
        }
        let single = preview.items.first { $0.id == pair.id }!
        check(single.spaces.count == 1 && single.dividerCount == 0 && single.spaces[0].id == pair.spaces[1].id, "Only emptied target Space disappears")
        for device in single.spaces[0].devices {
            check(apply(.remove(spaceID: single.spaces[0].id, deviceID: device.id), pair.id), "Remove final Space devices")
        }
        let empty = preview.items.first { $0.id == pair.id }!
        check(empty.usesEmptyStyle && empty.canEdit && empty.id == pair.id && empty.name == pair.name && empty.sync.needsSync,
              "Final removal keeps identity, empty edit capability and pending work")
        check(!apply(.reset, pair.id), "Reset of empty Zone is a no-op")
        let resetID = item("Q03").id
        let count = preview.items.count
        check(apply(.reset, resetID) && preview.items.count == count && preview.items.first { $0.id == resetID }!.usesEmptyStyle,
              "Reset retains the Zone")
        presentation.togglePreview(defaultSelectedID: resetID)
        check(apply(.delete, resetID), "Reset Zone can be deleted")
        presentation.reconcilePreviewIDs(preview.items.map(\.id))
        check(presentation.selectedID == nil && preview.items.count == count - 1, "Delete clears selection and removes exactly one Zone")
        check(preview.items.enumerated().allSatisfy { $0.element.name.hasPrefix("Zone \($0.offset + 1)") }, "Display names follow list order")
        let endedRevision = preview.revision!
        preview.end()
        check(!preview.apply(.delete, zoneID: pair.id, expectedRevision: endedRevision, zoneName: { "Zone \($0)" }), "Leaving preview rejects delayed callbacks")
        preview.begin(items: fixtures)
        check(preview.items == fixtures && preview.revision != endedRevision, "New preview session restores fixtures with a new revision")
        check(!preview.apply(.delete, zoneID: pair.id, expectedRevision: endedRevision, zoneName: { "Zone \($0)" }), "Old session cannot mutate restored IDs")
        preview.begin(items: [item("S02")])
        check(apply(.delete, item("S02").id) && preview.items.isEmpty, "Deleting the last item produces an empty list")
        #if DEBUG
        print("PASS: 29 Site Zone fixtures, role matrix, completeness, restricted summaries, sync scope and mode isolation")
        #endif
    }
}
