#if DEBUG
import Foundation

enum SiteTriggerZoneCandidatePreview {
    static let siteID = "candidate-preview"

    static func spaces(from items: [SiteTriggerZoneItemModel]) -> [SiteTriggerZoneCandidates.Space] {
        var result: [SiteTriggerZoneCandidates.Space] = [
            .init(id: "preview-no-groups", name: "No Proximity Groups", accessLabelKey: nil, availability: .noGroups)
        ]
        for code in ["D02", "S01", "S03"] {
            guard let item = items.first(where: { $0.previewCode == code }) else { continue }
            for space in item.spaces {
                let members = space.devices + (0..<12).map {
                    SiteTriggerZoneItemModel.Device(id: "candidate-\($0)", name: String(format: "Light %02d", $0 + 1))
                }
                result.append(.init(id: space.id, name: space.name ?? "Space", accessLabelKey: space.canEdit ? nil : "visitor",
                                    availability: space.canEdit ? .ready : .restricted,
                                    devices: space.canEdit ? members.enumerated().map { index, device in
                    .init(identity: .init(siteID: siteID, spaceID: space.id, deviceID: device.id), name: device.name,
                          address: UInt16(index + 1), groupAddress: 0xC001)
                } : [], devicesLoaded: true))
            }
        }
        result.append(.init(id: "preview-empty-group", name: "Empty Proximity Group", accessLabelKey: nil,
                            availability: .ready, devicesLoaded: true))
        return result
    }
}
#endif
