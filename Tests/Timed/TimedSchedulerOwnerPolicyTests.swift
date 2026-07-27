import Foundation

@main
struct TimedSchedulerOwnerPolicyTests {
    static func main() {
        testAutoOnWithoutGroupUsesOrdinaryScheduler()
        testAutoOnInManualControlGroupUsesOrdinaryScheduler()
        testAutoOnInAutomaticGroupUsesLightLCScheduler()
        testOrdinaryActionsAlwaysUseOrdinaryScheduler()

        print("TimedSchedulerOwnerPolicyTests passed")
    }

    private static func testAutoOnWithoutGroupUsesOrdinaryScheduler() {
        require(
            TimedSchedulerOwnerPolicy.resolve(
                action: .autoOn,
                membership: .noGroup
            ) == .ordinary,
            "Auto/On without a Group must use the ordinary Scheduler"
        )
    }

    private static func testAutoOnInManualControlGroupUsesOrdinaryScheduler() {
        require(
            TimedSchedulerOwnerPolicy.resolve(
                action: .autoOn,
                membership: .manualControlGroup
            ) == .ordinary,
            "Auto/On in a Manual control Group must use the ordinary Scheduler"
        )
    }

    private static func testAutoOnInAutomaticGroupUsesLightLCScheduler() {
        require(
            TimedSchedulerOwnerPolicy.resolve(
                action: .autoOn,
                membership: .automaticGroup
            ) == .lightLC,
            "Auto/On in a non-Manual control Group must use the Light LC Scheduler"
        )
    }

    private static func testOrdinaryActionsAlwaysUseOrdinaryScheduler() {
        for membership in TimedSchedulerMembership.allCases {
            require(
                TimedSchedulerOwnerPolicy.resolve(
                    action: .ordinary,
                    membership: membership
                ) == .ordinary,
                "Off, Scene Recall and No Action must use the ordinary Scheduler"
            )
        }
    }

    private static func require(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) {
        precondition(condition(), message)
    }
}
