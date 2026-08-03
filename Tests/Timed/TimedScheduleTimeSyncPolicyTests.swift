import Foundation

@main
struct TimedScheduleTimeSyncPolicyTests {

    static func main() {
        testSixteenEnabledSchedulesRequireOneTimeSync()
        testDisabledSchedulesDoNotRequireTimeSync()
        testMixedSchedulesOnlyMarkEnabledDependencies()
        testMissingTimeModelDisablesTimeSyncDependencies()
        testEmptyScheduleBatchDoesNotRequireTimeSync()
        print("TimedScheduleTimeSyncPolicyTests passed")
    }

    private static func testSixteenEnabledSchedulesRequireOneTimeSync() {
        let plan = TimedScheduleTimeSyncPolicy.makePlan(
            hasTimeModel: true,
            scheduleEnabledStates: Array(repeating: true, count: 16)
        )

        precondition(plan.requiresTimeSync)
        precondition(plan.scheduleRequiresTimeSync == Array(repeating: true, count: 16))
    }

    private static func testDisabledSchedulesDoNotRequireTimeSync() {
        let plan = TimedScheduleTimeSyncPolicy.makePlan(
            hasTimeModel: true,
            scheduleEnabledStates: Array(repeating: false, count: 16)
        )

        precondition(!plan.requiresTimeSync)
        precondition(plan.scheduleRequiresTimeSync == Array(repeating: false, count: 16))
    }

    private static func testMixedSchedulesOnlyMarkEnabledDependencies() {
        let plan = TimedScheduleTimeSyncPolicy.makePlan(
            hasTimeModel: true,
            scheduleEnabledStates: [true, false, true, false]
        )

        precondition(plan.requiresTimeSync)
        precondition(plan.scheduleRequiresTimeSync == [true, false, true, false])
    }

    private static func testMissingTimeModelDisablesTimeSyncDependencies() {
        let plan = TimedScheduleTimeSyncPolicy.makePlan(
            hasTimeModel: false,
            scheduleEnabledStates: [true, true]
        )

        precondition(!plan.requiresTimeSync)
        precondition(plan.scheduleRequiresTimeSync == [false, false])
    }

    private static func testEmptyScheduleBatchDoesNotRequireTimeSync() {
        let plan = TimedScheduleTimeSyncPolicy.makePlan(
            hasTimeModel: true,
            scheduleEnabledStates: []
        )

        precondition(!plan.requiresTimeSync)
        precondition(plan.scheduleRequiresTimeSync.isEmpty)
    }
}
