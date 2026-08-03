import Foundation

struct TimedScheduleTimeSyncPlan {
    let requiresTimeSync: Bool
    let scheduleRequiresTimeSync: [Bool]
}

enum TimedScheduleTimeSyncPolicy {

    static func makePlan(
        hasTimeModel: Bool,
        scheduleEnabledStates: [Bool]
    ) -> TimedScheduleTimeSyncPlan {
        let requiresTimeSync = hasTimeModel && scheduleEnabledStates.contains(true)
        return TimedScheduleTimeSyncPlan(
            requiresTimeSync: requiresTimeSync,
            scheduleRequiresTimeSync: scheduleEnabledStates.map {
                requiresTimeSync && $0
            }
        )
    }
}
