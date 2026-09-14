import Foundation

/// A display snapshot, independent of Mesh nodes, imported Spaces and persistence formats.
struct SiteTriggerZoneItemModel: Equatable {
    enum Access: String, CaseIterable {
        case owner, editor, visitor, noAccess, unknown

        var permitsEditing: Bool { self == .owner || self == .editor }
    }

    enum TaskState: Equatable {
        case settled, pending, unknown

        static func devices(hasMembers: Bool, hasPendingChange: Bool) -> Self {
            if hasPendingChange { return .pending }
            return hasMembers ? .unknown : .settled
        }
    }

    struct Sync: Equatable {
        var cloud: TaskState = .settled
        var devices: TaskState = .settled
        var needsSync: Bool { cloud == .pending || devices == .pending }
        var isKnown: Bool { cloud != .unknown && devices != .unknown }
        var isUnverified: Bool { !needsSync && !isKnown }
        var showsStatus: Bool { needsSync || !isKnown }
    }

    struct Device: Equatable {
        /// Unique within its Space. The display identity also includes Space.id.
        let id: String
        var name: String
    }

    struct Space: Equatable {
        let id: String
        var name: String?
        var access: Access
        var authorizationConfirmed = true
        var devices: [Device] = []
        /// Only an explicitly disclosed count; never inferred from a restricted empty list.
        var disclosedDeviceCount: Int?
        var sync = Sync()

        var canEdit: Bool { access.permitsEditing && authorizationConfirmed }
        var canDisplayDevices: Bool { access != .noAccess && access != .unknown && authorizationConfirmed }
        var displayedDeviceCount: Int? {
            if canDisplayDevices { return devices.count }
            return disclosedDeviceCount
        }
    }

    let id: UUID
    var name: String
    var spaces: [Space] = []
    var isConfirmedEmpty = false
    var hasCompleteSpaceList = true
    var hasUnverifiedMembers = false
    var needsCloudMigration = false
    var allowsEditing = true
    var canEditEmpty = false
    var hasUnsavedChanges = false
    var hasSavedMembers = false
    /// Work that cannot be attributed to a member Space.
    var sync = Sync()
    var previewCode: String?

    var usesEmptyStyle: Bool { isConfirmedEmpty && spaces.isEmpty && hasCompleteSpaceList }
    var canEdit: Bool {
        if usesEmptyStyle { return allowsEditing && canEditEmpty }
        return allowsEditing && hasCompleteSpaceList && !spaces.isEmpty
            && Set(spaces.map(\.id)).count == spaces.count
            && spaces.allSatisfy(\.canEdit)
    }
    var needsSync: Bool { sync.needsSync || spaces.contains { $0.sync.needsSync } }
    var showsSyncStatus: Bool { sync.showsStatus || spaces.contains { $0.sync.showsStatus } }
    var dividerCount: Int { max(0, spaces.count - 1) }

    static func empty(id: UUID, name: String, canEdit: Bool) -> Self {
        .init(id: id, name: name, isConfirmedEmpty: true, canEditEmpty: canEdit)
    }
}

/// Keeps selection and operation routing separate across live and preview data sources.
struct SiteTriggerZonePresentationState {
    private(set) var isPreview = false
    private(set) var liveSelectedID: UUID?
    private(set) var previewSelectedID: UUID?
    var selectedID: UUID? { isPreview ? previewSelectedID : liveSelectedID }
    var permitsLiveOperations: Bool { !isPreview }

    mutating func select(_ id: UUID) {
        if isPreview { previewSelectedID = id }
        else { liveSelectedID = id }
    }

    mutating func reconcileLiveIDs(_ ids: [UUID]) {
        if let liveSelectedID, !ids.contains(liveSelectedID) { self.liveSelectedID = nil }
    }

    #if DEBUG
    mutating func reconcilePreviewIDs(_ ids: [UUID]) {
        if let previewSelectedID, !ids.contains(previewSelectedID) { self.previewSelectedID = nil }
    }

    mutating func togglePreview(defaultSelectedID: UUID?) {
        isPreview.toggle()
        if isPreview { previewSelectedID = defaultSelectedID }
    }
    #endif
}
