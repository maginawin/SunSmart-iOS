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
