#if DEBUG
import Foundation

/// Mutable preview data never enters the live coordinator or persistence format.
struct SiteTriggerZonePreviewState {
    enum Mutation {
        case remove(spaceID: String, deviceID: String)
        case reset
        case delete
    }

    private(set) var items: [SiteTriggerZoneItemModel] = []
    private(set) var revision: UUID?

    mutating func begin(items: [SiteTriggerZoneItemModel]) {
        self.items = items
        revision = UUID()
    }

    mutating func end() { revision = nil }

    @discardableResult
    mutating func apply(_ mutation: Mutation, zoneID: UUID, expectedRevision: UUID,
                        zoneName: (Int) -> String) -> Bool {
        guard revision == expectedRevision,
              let index = items.firstIndex(where: { $0.id == zoneID }), items[index].canEdit else { return false }
        var item = items[index]
        switch mutation {
        case .remove(let spaceID, let deviceID):
            guard let space = item.spaces.firstIndex(where: { $0.id == spaceID }),
                  let device = item.spaces[space].devices.firstIndex(where: { $0.id == deviceID }) else { return false }
            item.spaces[space].devices.remove(at: device)
            if item.spaces[space].devices.isEmpty { item.spaces.remove(at: space) }
        case .reset:
            guard !item.usesEmptyStyle else { return false }
            item.spaces.removeAll()
        case .delete:
            items.remove(at: index)
            for offset in items.indices {
                let suffix = items[offset].name.components(separatedBy: " · ").dropFirst().joined(separator: " · ")
                items[offset].name = zoneName(offset + 1) + (suffix.isEmpty ? "" : " · " + suffix)
            }
            revision = UUID()
            return true
        }
        // Preview removal represents unsaved membership and unacknowledged device work.
        // Keep that work visible even when the final Space section disappears.
        item.sync = .init(cloud: .pending, devices: .pending)
        if item.spaces.isEmpty {
            item.isConfirmedEmpty = true
            item.canEditEmpty = true // Captured only after the complete Zone passed authorization.
        }
        items[index] = item
        revision = UUID()
        return true
    }
}

enum SiteTriggerZonePreviewFixtures {
    typealias Item = SiteTriggerZoneItemModel

    /// Names here are sample data, not application copy. No SpaceData/Node/Auth is created.
    static func makeItems(zoneName: (Int) -> String) -> [Item] {
        let names = ["1F East Hall", "5F", "External Building A", "West Wing"]
        let cloud = Item.Sync(cloud: .pending)
        let devices = Item.Sync(devices: .pending)
        let both = Item.Sync(cloud: .pending, devices: .pending)
        var items: [Item] = []
        func append(_ code: String, _ roles: [Item.Access], counts: [Int] = [], syncs: [Item.Sync] = [], zoneSync: Item.Sync = .init()) {
            let index = items.count + 1
            let id = UUID(uuidString: String(format: "FADE0000-0000-4000-8000-%012d", index))!
            let spaces = roles.enumerated().map { offset, role -> Item.Space in
                let count = offset < counts.count ? counts[offset] : 2
                let allowed = role != .noAccess && role != .unknown
                return .init(id: "preview-\(code)-space-\(offset)", name: names[offset % names.count], access: role,
                             devices: allowed ? (0..<count).map { .init(id: "device-\($0)", name: String(format: "ID%03d", $0 + 1)) } : [],
                             disclosedDeviceCount: count,
                             sync: offset < syncs.count ? syncs[offset] : .init())
            }
            items.append(.init(id: id, name: zoneName(index), spaces: spaces, isConfirmedEmpty: roles.isEmpty,
                               canEditEmpty: true, sync: zoneSync, previewCode: code))
        }
        append("E01", [])
        append("S01", [.owner])
        append("S02", [.editor], counts: [1])
        append("S03", [.visitor])
        append("S04", [.noAccess])
        append("S05", [.owner], counts: [5], syncs: [cloud])
        append("S06", [.editor], counts: [6], syncs: [devices])
        append("S07", [.visitor], syncs: [both])
        append("S08", [.noAccess], syncs: [cloud])
        append("D01", [.owner, .owner], counts: [4, 4])
        append("D02", [.owner, .owner], counts: [3, 4], syncs: [devices])
        append("D03", [.editor, .editor], counts: [7, 4])
        append("D04", [.editor, .visitor], syncs: [devices])
        append("D05", [.editor, .noAccess], counts: [3, 3])
        append("D06", [.owner, .editor], syncs: [cloud, devices])
        append("T01", [.owner, .owner, .owner])
        append("T02", [.editor, .visitor, .noAccess], syncs: [cloud, devices, both])
        append("T03", [.editor, .editor, .editor], counts: [10, 2, 1])
        append("T04", [.visitor, .visitor, .visitor])
        append("T05", [.noAccess, .noAccess, .noAccess])
        append("Q01", [.owner, .owner, .owner, .owner])
        append("Q02", [.owner, .editor, .visitor, .noAccess], syncs: [cloud, devices, both])
        append("Q03", [.editor, .editor, .editor, .editor], counts: [11, 2, 5, 1], syncs: [both])
        append("Q04", [.noAccess, .noAccess, .noAccess, .noAccess], syncs: [cloud])
        append("B01", [.owner, .editor], zoneSync: cloud)
        append("B02", [.owner, .unknown], syncs: [.init(), .init(cloud: .unknown, devices: .unknown)])
        items[items.count - 1].hasCompleteSpaceList = false
        append("B03", [.editor])
        items[items.count - 1].spaces[0].authorizationConfirmed = false
        append("B04", [.unknown])
        items[items.count - 1].spaces[0].name = nil
        items[items.count - 1].spaces[0].disclosedDeviceCount = nil
        append("B05", [.owner, .editor, .visitor, .noAccess], counts: [7, 0, 2, 3], syncs: [both])
        items[items.count - 1].name += " · East Hall / West Wing / External Building"
        for index in 0..<4 {
            items[items.count - 1].spaces[index].name = "East Hall / West Wing / External Building"
        }
        items[items.count - 1].spaces[0].devices[0].name = "Entrance lighting sensor"
        return items
    }
}
#endif
