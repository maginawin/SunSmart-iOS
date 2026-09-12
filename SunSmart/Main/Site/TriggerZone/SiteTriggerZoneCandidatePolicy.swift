import Foundation

/// Detached display data. No Mesh objects, keys, online state or writable Zone members.
enum SiteTriggerZoneCandidates {
    struct Identity: Hashable {
        let siteID: String
        let spaceID: String
        let deviceID: String
    }

    struct Device: Equatable {
        let identity: Identity
        let name: String
        let address: UInt16
        let groupAddress: UInt16
    }

    enum Availability: Equatable {
        case loading, ready, noGroups, restricted, unavailable
    }

    struct Space: Equatable {
        let id: String
        let name: String
        let accessLabelKey: String?
        var availability: Availability
        var devices: [Device] = []
        var devicesLoaded = false
        var isSelectable: Bool { availability == .ready }
    }

    struct Membership {
        let zoneID: UUID
        let devices: Set<Identity>
    }

    struct Selection {
        private(set) var spaceID: String?
        var includeAdded = false

        mutating func reconcile(_ spaces: [Space]) {
            if spaces.contains(where: { $0.id == spaceID && $0.isSelectable }) { return }
            spaceID = spaces.first(where: \.isSelectable)?.id
        }

        mutating func select(_ id: String, in spaces: [Space]) {
            guard spaces.contains(where: { $0.id == id && $0.isSelectable }) else { return }
            spaceID = id
        }
    }

    /// A failed device projection stays unavailable until an explicit refresh.
    /// Otherwise the next Group-only read could reselect it indefinitely.
    struct LoadState {
        private var failedDeviceSpaces = Set<String>()

        mutating func reset() { failedDeviceSpaces.removeAll() }

        mutating func accept(_ spaces: [Space], devicesFor spaceID: String?) -> [Space] {
            if let spaceID, spaces.first(where: { $0.id == spaceID })?.availability == .unavailable {
                failedDeviceSpaces.insert(spaceID)
            }
            return spaces.map { space in
                guard failedDeviceSpaces.contains(space.id), space.availability == .ready else { return space }
                var space = space
                space.availability = .unavailable
                space.devices = []
                space.devicesLoaded = false
                return space
            }
        }
    }

    static func filteredDevices(in space: Space?, zoneID: UUID?, memberships: [Membership], includeAdded: Bool) -> [Device] {
        guard let space, space.isSelectable, let zoneID else { return [] }
        let excluded = memberships.filter { !includeAdded || $0.zoneID == zoneID }
            .reduce(into: Set<Identity>()) { $0.formUnion($1.devices) }
        var seen = Set<Identity>()
        return space.devices.filter { seen.insert($0.identity).inserted && !excluded.contains($0.identity) }
    }

    static func placeholderKey(for spaces: [Space]) -> String {
        if spaces.isEmpty { return "site_zone_no_spaces" }
        if spaces.contains(where: { $0.availability == .loading }) { return "site_zone_loading_spaces" }
        if spaces.contains(where: { $0.availability == .unavailable }) { return "site_zone_data_unavailable" }
        if spaces.allSatisfy({ $0.availability == .restricted }) { return "site_zone_no_editable_spaces" }
        return "site_zone_no_eligible_spaces"
    }

    static func emptyMessageKey(spaces: [Space], selected: Space?, visibleDevices: [Device], includeAdded: Bool) -> String? {
        guard let selected else {
            switch placeholderKey(for: spaces) {
            case "site_zone_no_spaces": return nil
            case "site_zone_no_eligible_spaces": return "site_zone_assign_proximity_profile"
            case "site_zone_no_editable_spaces": return "site_zone_editable_space_required"
            default: return placeholderKey(for: spaces)
            }
        }
        if !selected.devicesLoaded { return "site_zone_loading_devices" }
        if selected.devices.isEmpty { return "filter_no_devices" }
        if visibleDevices.isEmpty { return includeAdded ? "site_zone_no_available_devices" : "site_zone_no_new_devices" }
        return nil
    }
}
