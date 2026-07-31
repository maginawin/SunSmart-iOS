import Foundation

@main
struct TimedSchedulerOwnerPolicyTests {
    static func main() {
        testAutoOnWithoutGroupUsesOrdinaryScheduler()
        testAutoOnInManualControlGroupUsesOrdinaryScheduler()
        testAutoOnInAutomaticGroupUsesLightLCScheduler()
        testOrdinaryActionsAlwaysUseOrdinaryScheduler()
        testKnownSchedulerModelsDoNotNeedAuthoritativeRead()
        testMissingSchedulerModelNeedsAuthoritativeRead()
        testNodeWithoutSchedulerModelsDoesNotNeedAuthoritativeRead()
        testUnknownOwnerModelIsReported()
        testMissingOwnerEntryIsReported()
        testMismatchingOwnerEntryIsReported()
        testUnknownCleanupModelIsReported()
        testResidualCleanupEntryIsReported()
        testMatchingOwnerAndClearCleanupAreSynchronized()
        testGroupMemberExitRoutesScheduleMigrationToRemoval()
        testGroupMemberExitScheduleMigrationDoesNotBlockRemoval()
        testOrdinaryScheduleSyncRoutesToConfiguration()

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

    private static func testKnownSchedulerModelsDoNotNeedAuthoritativeRead() {
        require(
            !TimedSchedulerCacheRepairPolicy.needsAuthoritativeRead(
                modelKnownStates: [true, true]
            ),
            "A Node with every Scheduler Model known must not be read again"
        )
    }

    private static func testMissingSchedulerModelNeedsAuthoritativeRead() {
        require(
            TimedSchedulerCacheRepairPolicy.needsAuthoritativeRead(
                modelKnownStates: [true, false]
            ),
            "A Node with any unknown Scheduler Model must be read"
        )
    }

    private static func testNodeWithoutSchedulerModelsDoesNotNeedAuthoritativeRead() {
        require(
            !TimedSchedulerCacheRepairPolicy.needsAuthoritativeRead(
                modelKnownStates: []
            ),
            "A Node without Scheduler Models must not enter Scheduler repair"
        )
    }

    private static func testUnknownOwnerModelIsReported() {
        require(
            TimedSchedulerSyncPolicy.evaluate(
                ownerState: .unknownModel,
                cleanupStates: []
            ) == .ownerModelUnknown,
            "Unknown owner Model state must remain pending"
        )
    }

    private static func testMissingOwnerEntryIsReported() {
        require(
            TimedSchedulerSyncPolicy.evaluate(
                ownerState: .missingEntry,
                cleanupStates: []
            ) == .ownerEntryMissing,
            "Known owner Model without the index must be reported as missing"
        )
    }

    private static func testMismatchingOwnerEntryIsReported() {
        require(
            TimedSchedulerSyncPolicy.evaluate(
                ownerState: .mismatchingEntry,
                cleanupStates: [.residualEntry]
            ) == .ownerEntryMismatch,
            "Owner mismatch must be reported before cleanup differences"
        )
    }

    private static func testUnknownCleanupModelIsReported() {
        require(
            TimedSchedulerSyncPolicy.evaluate(
                ownerState: .matchingEntry,
                cleanupStates: [.clearEntry, .unknownModel]
            ) == .cleanupModelUnknown,
            "Any unknown cleanup Model must remain pending"
        )
    }

    private static func testResidualCleanupEntryIsReported() {
        require(
            TimedSchedulerSyncPolicy.evaluate(
                ownerState: .matchingEntry,
                cleanupStates: [.clearEntry, .residualEntry]
            ) == .cleanupEntryResidual,
            "Any valid non-owner entry must be reported as residual"
        )
    }

    private static func testMatchingOwnerAndClearCleanupAreSynchronized() {
        let difference = TimedSchedulerSyncPolicy.evaluate(
            ownerState: .matchingEntry,
            cleanupStates: [.clearEntry, .clearEntry]
        )

        require(difference == .synchronized, "Matching owner and clear cleanup Models must be synchronized")
        require(!difference.needsSync, "Synchronized state must not request another SAVE")
    }

    private static func testGroupMemberExitRoutesScheduleMigrationToRemoval() {
        require(
            TimedSchedulerGroupMemberExitStepPolicy.destination(
                isExitingGroup: true
            ) == .removal,
            "Exiting Group Schedule migration must route to Remove Section"
        )
    }

    private static func testGroupMemberExitScheduleMigrationDoesNotBlockRemoval() {
        require(
            !TimedSchedulerGroupMemberExitStepPolicy.shouldBlockGroupExit(
                isExitingGroup: true
            ),
            "Failed Group exit Schedule migration must not block Group removal"
        )
    }

    private static func testOrdinaryScheduleSyncRoutesToConfiguration() {
        require(
            TimedSchedulerGroupMemberExitStepPolicy.destination(
                isExitingGroup: false
            ) == .configuration,
            "Ordinary Schedule synchronization must remain in Configuration Section"
        )
    }

    private static func require(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) {
        precondition(condition(), message)
    }
}
