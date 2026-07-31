enum TimedSchedulerOwner {
    case ordinary
    case lightLC
}

enum TimedSchedulerActionKind {
    case autoOn
    case ordinary
}

enum TimedSchedulerMembership: CaseIterable {
    case noGroup
    case manualControlGroup
    case automaticGroup
}

enum TimedSchedulerOwnerPolicy {
    static func resolve(
        action: TimedSchedulerActionKind,
        membership: TimedSchedulerMembership
    ) -> TimedSchedulerOwner {
        guard action == .autoOn, membership == .automaticGroup else {
            return .ordinary
        }
        return .lightLC
    }
}

enum TimedSchedulerGroupMemberExitStepDestination {
    case removal
    case configuration
}

enum TimedSchedulerGroupMemberExitStepPolicy {
    static func destination(
        isExitingGroup: Bool
    ) -> TimedSchedulerGroupMemberExitStepDestination {
        return isExitingGroup ? .removal : .configuration
    }

    static func shouldBlockGroupExit(
        isExitingGroup: Bool
    ) -> Bool {
        return !isExitingGroup
    }
}

enum TimedSchedulerCacheRepairPolicy {
    static func needsAuthoritativeRead(
        modelKnownStates: [Bool]
    ) -> Bool {
        return !modelKnownStates.isEmpty
            && modelKnownStates.contains(false)
    }
}

enum TimedSchedulerOwnerEntryState {
    case unknownModel
    case missingEntry
    case matchingEntry
    case mismatchingEntry
}

enum TimedSchedulerCleanupEntryState {
    case unknownModel
    case clearEntry
    case residualEntry
}

enum TimedSchedulerSyncDifference: String {
    case notApplicable = "not-applicable"
    case synchronized
    case ownerModelUnknown = "owner-model-unknown"
    case ownerEntryMissing = "owner-entry-missing"
    case ownerEntryMismatch = "owner-entry-mismatch"
    case cleanupModelUnknown = "cleanup-model-unknown"
    case cleanupEntryResidual = "cleanup-entry-residual"

    var needsSync: Bool {
        return self != .notApplicable && self != .synchronized
    }
}

enum TimedSchedulerSyncPolicy {
    static func evaluate(
        ownerState: TimedSchedulerOwnerEntryState,
        cleanupStates: [TimedSchedulerCleanupEntryState]
    ) -> TimedSchedulerSyncDifference {
        switch ownerState {
        case .unknownModel:
            return .ownerModelUnknown
        case .missingEntry:
            return .ownerEntryMissing
        case .mismatchingEntry:
            return .ownerEntryMismatch
        case .matchingEntry:
            break
        }

        if cleanupStates.contains(where: { $0 == .unknownModel }) {
            return .cleanupModelUnknown
        }
        if cleanupStates.contains(where: { $0 == .residualEntry }) {
            return .cleanupEntryResidual
        }
        return .synchronized
    }
}
