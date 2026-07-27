@main
struct KineticSwitchBindingPolicyTests {

    static func main() {
        testCleanupGroupsIncludeActiveAndPendingRemovalAddresses()
        testCleanupGroupsRemoveDuplicateAddresses()
        testCleanupProxiesIncludePendingAndCurrentAddresses()
        testCleanupProxiesRemoveDuplicateAddresses()
        testUnclaimedMacUsesNormalBinding()
        testOriginalProxyCanTakeOverResidualBinding()
        testAnotherSwitchOwnershipCannotBeTakenOver()
        testDifferentProxyCannotTakeOverResidualBinding()
        testRemovingCurrentProxyPreservesItUntilUnbindSucceeds()
        testReplacingCurrentProxyMarksOldProxyForRemoval()
        testDifferentPendingProxyRejectsNewRemoval()
        testPendingRemovalOfCurrentProxySuppressesConfiguration()
        testProxyReplacementAllowsNewProxyConfiguration()
        testGroupExitSuppressesProxyConfiguration()
        testGroupMemberRemovalMarksCurrentProxyForRemoval()
        testGroupMemberRemovalReusesMatchingPendingRemoval()
        testGroupMemberRemovalRejectsDifferentPendingRemoval()
        testReferenceCleanupClearsMatchingCurrentAndPendingProxy()
        testReferenceCleanupPreservesNewCurrentProxyWhenOldProxyIsRemoved()
        print("KineticSwitchBindingPolicyTests passed")
    }

    private static func testCleanupGroupsIncludeActiveAndPendingRemovalAddresses() {
        let addresses = KineticSwitchBindingPolicy.cleanupGroupAddresses(
            active: [0xC001],
            pendingRemoval: [0xC002]
        )

        precondition(addresses == [0xC001, 0xC002])
    }

    private static func testCleanupGroupsRemoveDuplicateAddresses() {
        let addresses = KineticSwitchBindingPolicy.cleanupGroupAddresses(
            active: [0xC001],
            pendingRemoval: [0xC001]
        )

        precondition(addresses == [0xC001])
    }

    private static func testCleanupProxiesIncludePendingAndCurrentAddresses() {
        let addresses = KineticSwitchBindingPolicy.cleanupProxyAddresses(
            current: 0x0002,
            pendingRemoval: 0x0001
        )

        precondition(addresses == [0x0001, 0x0002])
    }

    private static func testCleanupProxiesRemoveDuplicateAddresses() {
        let addresses = KineticSwitchBindingPolicy.cleanupProxyAddresses(
            current: 0x0001,
            pendingRemoval: 0x0001
        )

        precondition(addresses == [0x0001])
    }

    private static func testUnclaimedMacUsesNormalBinding() {
        let decision = KineticSwitchBindingPolicy.scanDecision(
            detectedProxyAddress: Optional<UInt16>.none,
            selectedProxyAddress: 0x0001,
            ownedByAnotherSwitch: false
        )

        precondition(decision == .allowBinding)
    }

    private static func testOriginalProxyCanTakeOverResidualBinding() {
        let decision = KineticSwitchBindingPolicy.scanDecision(
            detectedProxyAddress: 0x0001,
            selectedProxyAddress: 0x0001,
            ownedByAnotherSwitch: false
        )

        precondition(decision == .allowProxyTakeover)
    }

    private static func testAnotherSwitchOwnershipCannotBeTakenOver() {
        let decision = KineticSwitchBindingPolicy.scanDecision(
            detectedProxyAddress: 0x0001,
            selectedProxyAddress: 0x0001,
            ownedByAnotherSwitch: true
        )

        precondition(decision == .rejectExistingBinding)
    }

    private static func testDifferentProxyCannotTakeOverResidualBinding() {
        let decision = KineticSwitchBindingPolicy.scanDecision(
            detectedProxyAddress: 0x0001,
            selectedProxyAddress: 0x0002,
            ownedByAnotherSwitch: false
        )

        precondition(decision == .rejectExistingBinding)
    }

    private static func testRemovingCurrentProxyPreservesItUntilUnbindSucceeds() {
        let decision = KineticSwitchBindingPolicy.proxySaveDecision(
            savedCurrent: 0x0001,
            pendingRemoval: Optional<UInt16>.none,
            requestedCurrent: Optional<UInt16>.none
        )

        precondition(decision == .preserveCurrentForRemoval(0x0001))
    }

    private static func testReplacingCurrentProxyMarksOldProxyForRemoval() {
        let decision = KineticSwitchBindingPolicy.proxySaveDecision(
            savedCurrent: 0x0001,
            pendingRemoval: Optional<UInt16>.none,
            requestedCurrent: 0x0002
        )

        precondition(decision == .replaceCurrent(pendingRemoval: 0x0001))
    }

    private static func testDifferentPendingProxyRejectsNewRemoval() {
        let decision = KineticSwitchBindingPolicy.proxySaveDecision(
            savedCurrent: 0x0002,
            pendingRemoval: 0x0001,
            requestedCurrent: Optional<UInt16>.none
        )

        precondition(decision == .rejectPendingRemovalConflict)
    }

    private static func testPendingRemovalOfCurrentProxySuppressesConfiguration() {
        precondition(
            !KineticSwitchBindingPolicy.shouldConfigureProxy(
                current: 0x0001,
                pendingRemoval: 0x0001,
                isExitingGroup: false
            )
        )
    }

    private static func testProxyReplacementAllowsNewProxyConfiguration() {
        precondition(
            KineticSwitchBindingPolicy.shouldConfigureProxy(
                current: 0x0002,
                pendingRemoval: 0x0001,
                isExitingGroup: false
            )
        )
    }

    private static func testGroupExitSuppressesProxyConfiguration() {
        precondition(
            !KineticSwitchBindingPolicy.shouldConfigureProxy(
                current: 0x0001,
                pendingRemoval: Optional<UInt16>.none,
                isExitingGroup: true
            )
        )
    }

    private static func testGroupMemberRemovalMarksCurrentProxyForRemoval() {
        let decision = KineticSwitchBindingPolicy.groupMemberRemovalDecision(
            node: 0x0001,
            current: 0x0001,
            pendingRemoval: Optional<UInt16>.none
        )

        precondition(decision == .markPendingRemoval)
    }

    private static func testGroupMemberRemovalReusesMatchingPendingRemoval() {
        let decision = KineticSwitchBindingPolicy.groupMemberRemovalDecision(
            node: 0x0001,
            current: 0x0002,
            pendingRemoval: 0x0001
        )

        precondition(decision == .reusePendingRemoval)
    }

    private static func testGroupMemberRemovalRejectsDifferentPendingRemoval() {
        let decision = KineticSwitchBindingPolicy.groupMemberRemovalDecision(
            node: 0x0002,
            current: 0x0002,
            pendingRemoval: 0x0001
        )

        precondition(decision == .rejectPendingRemovalConflict)
    }

    private static func testReferenceCleanupClearsMatchingCurrentAndPendingProxy() {
        let decision = KineticSwitchBindingPolicy.referenceCleanupDecision(
            node: 0x0001,
            current: 0x0001,
            pendingRemoval: 0x0001
        )

        precondition(decision.clearsCurrent)
        precondition(decision.clearsPendingRemoval)
        precondition(decision.clearsCredentials)
    }

    private static func testReferenceCleanupPreservesNewCurrentProxyWhenOldProxyIsRemoved() {
        let decision = KineticSwitchBindingPolicy.referenceCleanupDecision(
            node: 0x0001,
            current: 0x0002,
            pendingRemoval: 0x0001
        )

        precondition(!decision.clearsCurrent)
        precondition(decision.clearsPendingRemoval)
        precondition(!decision.clearsCredentials)
    }
}
