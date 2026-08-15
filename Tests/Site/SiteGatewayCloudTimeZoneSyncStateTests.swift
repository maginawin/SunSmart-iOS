import Foundation

@main
struct SiteGatewayCloudTimeZoneSyncStateTests {

    static func main() {
        testInitializationSeparatesAlreadySyncedTargetsFromPushingTargets()
        testRequestMACsAndCountsExposeOnlyAuthorizedPendingRows()
        testApplyMatchesIDsCaseInsensitivelyAndIgnoresExtraMACs()
        testRequestedAndUnknownStatusesLeavePushingRowsUnchanged()
        testTerminalStatusesMapToSyncedOrFailed()
        testTerminalStatusesCannotBeReopened()
        testConflictingTerminalStatusesDoNotUpdateInThisRound()
        testCanDismissWhenAllRowsAreTerminalIncludingEmptyBatch()
        testFailPushingOnlyFailsUnfinishedRows()
        testReviewContextProjectsOnlyFailedGatewayIDs()
        testReviewContextSurvivesStaleRemoteEvidence()
        testReviewContextClearsAcknowledgedOrUnauthorizedGateways()
        testReviewProjectionStaysHiddenAfterExplicitContextAcknowledgment()
        testReviewProjectionHidesWhenExplicitLocalTargetChanges()
        testReviewProjectionAllowsMatchingOrdinaryRemoteTarget()
        testReviewProjectionHidesVisitorAndInvalidTimeZones()
        print("SiteGatewayCloudTimeZoneSyncStateTests passed")
    }

    private static func testInitializationSeparatesAlreadySyncedTargetsFromPushingTargets() {
        let state = SiteGatewayCloudTimeZoneBatchState(targets: [
            target(id: "synced", requestMAC: "SYNCED", requiresSync: false),
            target(id: "pending", requestMAC: "PENDING", requiresSync: true)
        ])

        require(
            state.items.map(\.status) == [.synced, .pushing],
            "Targets matching the site offset must start Synced while others start Pushing"
        )
    }

    private static func testRequestMACsAndCountsExposeOnlyAuthorizedPendingRows() {
        let state = SiteGatewayCloudTimeZoneBatchState(targets: [
            target(id: "first", requestMAC: "FIRST", requiresSync: false),
            target(id: "second", requestMAC: "SECOND", requiresSync: true),
            target(id: "third", requestMAC: "THIRD", requiresSync: true)
        ])

        require(state.authorizedCount == 3, "Authorized count must include every target row")
        require(state.requestMACs == ["SECOND", "THIRD"], "Requests must include only rows requiring sync in target order")
        require(state.hasPushing, "A pending target must keep the batch in Pushing state")
        require(state.failedCount == 0, "A newly created batch has no failed rows")
        require(!state.canDismiss, "DONE must be unavailable while any row is Pushing")
    }

    private static func testApplyMatchesIDsCaseInsensitivelyAndIgnoresExtraMACs() {
        var state = SiteGatewayCloudTimeZoneBatchState(targets: [
            target(id: "ef725643a2b9", requestMAC: "EF725643A2B9", requiresSync: true),
            target(id: "ef725643a2b0", requestMAC: "EF725643A2B0", requiresSync: true)
        ])

        state.apply([
            .init(id: " EF725643A2B9 ", statuses: [.succeed]),
            .init(id: "extra-mac", statuses: [.failed]),
            .init(id: "EF725643A2B0", statuses: [.failed])
        ])

        require(
            state.items.map(\.status) == [.synced, .failed],
            "Normalized IDs must update their own rows and ignore extra MACs"
        )
    }

    private static func testRequestedAndUnknownStatusesLeavePushingRowsUnchanged() {
        var state = SiteGatewayCloudTimeZoneBatchState(targets: [
            target(id: "requested", requestMAC: "REQUESTED", requiresSync: true),
            target(id: "unknown", requestMAC: "UNKNOWN", requiresSync: true)
        ])

        state.apply([
            .init(id: "requested", statuses: [.requested]),
            .init(id: "unknown", statuses: [])
        ])

        require(
            state.items.map(\.status) == [.pushing, .pushing],
            "Requested or unknown-only snapshots must not enter the reducer"
        )
    }

    private static func testTerminalStatusesMapToSyncedOrFailed() {
        var state = SiteGatewayCloudTimeZoneBatchState(targets: [
            target(id: "succeed", requestMAC: "SUCCEED", requiresSync: true),
            target(id: "failed", requestMAC: "FAILED", requiresSync: true),
            target(id: "expired", requestMAC: "EXPIRED", requiresSync: true)
        ])

        state.apply([
            .init(id: "succeed", statuses: [.succeed]),
            .init(id: "failed", statuses: [.failed]),
            .init(id: "expired", statuses: [.expired])
        ])

        require(
            state.items.map(\.status) == [.synced, .failed, .failed],
            "Succeed must map to Synced and Failed or Expired to Failed"
        )
        require(state.failedCount == 2, "Failed count must include Failed and Expired outcomes")
    }

    private static func testTerminalStatusesCannotBeReopened() {
        var state = SiteGatewayCloudTimeZoneBatchState(targets: [
            target(id: "synced", requestMAC: "SYNCED", requiresSync: true),
            target(id: "failed", requestMAC: "FAILED", requiresSync: true)
        ])
        state.apply([
            .init(id: "synced", statuses: [.succeed]),
            .init(id: "failed", statuses: [.failed])
        ])

        state.apply([
            .init(id: "synced", statuses: [.failed]),
            .init(id: "failed", statuses: [.succeed])
        ])

        require(
            state.items.map(\.status) == [.synced, .failed],
            "Terminal rows must never transition back to another status"
        )
    }

    private static func testConflictingTerminalStatusesDoNotUpdateInThisRound() {
        var state = SiteGatewayCloudTimeZoneBatchState(targets: [
            target(id: "conflict", requestMAC: "CONFLICT", requiresSync: true),
            target(id: "failed", requestMAC: "FAILED", requiresSync: true)
        ])

        state.apply([
            .init(id: "conflict", statuses: [.succeed, .failed]),
            .init(id: "failed", statuses: [.expired, .failed])
        ])

        require(
            state.items.map(\.status) == [.pushing, .failed],
            "A success and failure conflict must skip only that row while same-terminal failure values may reduce"
        )
    }

    private static func testCanDismissWhenAllRowsAreTerminalIncludingEmptyBatch() {
        var state = SiteGatewayCloudTimeZoneBatchState(targets: [
            target(id: "already-synced", requestMAC: "SYNCED", requiresSync: false),
            target(id: "pending", requestMAC: "PENDING", requiresSync: true)
        ])
        require(!state.canDismiss, "A batch with a pending row cannot be dismissed early")

        state.apply([.init(id: "pending", statuses: [.succeed])])
        require(state.canDismiss, "DONE becomes available after every row is terminal")

        let emptyState = SiteGatewayCloudTimeZoneBatchState(targets: [])
        require(emptyState.canDismiss, "An empty authorized batch is already terminal")
    }

    private static func testFailPushingOnlyFailsUnfinishedRows() {
        var state = SiteGatewayCloudTimeZoneBatchState(targets: [
            target(id: "synced", requestMAC: "SYNCED", requiresSync: false),
            target(id: "pushing", requestMAC: "PUSHING", requiresSync: true),
            target(id: "failed", requestMAC: "FAILED", requiresSync: true)
        ])
        state.apply([.init(id: "failed", statuses: [.failed])])

        state.failPushing()

        require(
            state.items.map(\.status) == [.synced, .failed, .failed],
            "failPushing must fail only rows that are still Pushing"
        )
        require(state.canDismiss, "A failed terminal batch can be dismissed")
    }

    private static func testReviewContextProjectsOnlyFailedGatewayIDs() {
        var state = SiteGatewayCloudTimeZoneBatchState(targets: [
            target(id: " FIRST ", requestMAC: "FIRST", requiresSync: true),
            target(id: " Failed ", requestMAC: "FAILED", requiresSync: true),
            target(id: "already", requestMAC: "ALREADY", requiresSync: false)
        ])
        state.failPushing()
        let targetTimeZone = timeZone()

        let context = SiteGatewayTimeZoneReviewContext.make(
            targetTimeZone: targetTimeZone,
            terminalState: state
        )

        require(
            context == SiteGatewayTimeZoneReviewContext(
                targetTimeZone: targetTimeZone,
                failedGatewayIDs: ["first", "failed"]
            ),
            "A failed Site submit must normalize and retain every initially pending Gateway ID"
        )
        require(
            SiteGatewayTimeZoneReviewContext.make(
                targetTimeZone: targetTimeZone,
                terminalState: SiteGatewayCloudTimeZoneBatchState(targets: [])
            ) == nil,
            "A terminal batch without failures must not retain Review context"
        )
    }

    private static func testReviewContextSurvivesStaleRemoteEvidence() {
        let context = SiteGatewayTimeZoneReviewContext(
            targetTimeZone: timeZone(),
            failedGatewayIDs: ["failed", "missing"]
        )

        let reconciled = context.reconciled(with: remote(
            role: .owner,
            gateways: [
                gateway("FAILED", offsetMinutes: 0),
                gateway("failed", offsetMinutes: nil)
            ]
        ))

        require(
            reconciled?.failedGatewayIDs == ["failed", "missing"],
            "Stale, incomplete, or missing remote evidence must not hide failed Review rows"
        )
    }

    private static func testReviewContextClearsAcknowledgedOrUnauthorizedGateways() {
        let context = SiteGatewayTimeZoneReviewContext(
            targetTimeZone: timeZone(),
            failedGatewayIDs: ["acknowledged", "revoked"]
        )

        let reconciled = context.reconciled(with: remote(
            role: .visitor,
            spaces: [space(.editor, gatewayId: "acknowledged")],
            gateways: [
                gateway("ACKNOWLEDGED", offsetMinutes: 480),
                gateway("acknowledged", offsetMinutes: 480),
                gateway("revoked", offsetMinutes: 0)
            ]
        ))

        require(
            reconciled == nil,
            "Fully acknowledged failed Gateways and Gateways outside the latest permission scope must leave no Review context"
        )
    }

    private static func testReviewProjectionStaysHiddenAfterExplicitContextAcknowledgment() {
        let localA = timeZone(offset: "+08:00")
        let remoteB = timeZone(offset: "+09:00")
        let activeContext = SiteGatewayTimeZoneReviewContext(
            targetTimeZone: localA,
            failedGatewayIDs: ["failed"]
        )
        let staleRemote = remote(
            role: .owner,
            timezone: remoteB,
            gateways: [gateway("failed", offsetMinutes: 540)]
        )
        require(
            SiteGatewayTimeZoneReviewProjectionPolicy.project(
                localTimeZone: localA,
                remote: staleRemote,
                explicitContext: activeContext
            ) == .explicit(activeContext),
            "A failed Site target remains actionable while local Site still equals its explicit target"
        )

        let acknowledgedRemote = remote(
            role: .owner,
            timezone: remoteB,
            gateways: [gateway("failed", offsetMinutes: 480)]
        )
        let reconciledContext = activeContext.reconciled(with: acknowledgedRemote)
        require(reconciledContext == nil, "Complete target evidence must acknowledge the explicit failure")
        require(
            SiteGatewayTimeZoneReviewProjectionPolicy.project(
                localTimeZone: localA,
                remote: acknowledgedRemote,
                explicitContext: reconciledContext
            ) == .hidden,
            "Acknowledging target A must not fall through to an unactionable remote target B Review"
        )
    }

    private static func testReviewProjectionHidesWhenExplicitLocalTargetChanges() {
        let targetA = timeZone(offset: "+08:00")
        let context = SiteGatewayTimeZoneReviewContext(
            targetTimeZone: targetA,
            failedGatewayIDs: ["failed"]
        )

        let projection = SiteGatewayTimeZoneReviewProjectionPolicy.project(
            localTimeZone: timeZone(offset: "+10:00"),
            remote: remote(
                role: .owner,
                timezone: timeZone(offset: "+09:00"),
                gateways: []
            ),
            explicitContext: context
        )

        require(
            projection == .hidden,
            "An explicit Review becomes hidden when local Site no longer equals its target"
        )
    }

    private static func testReviewProjectionAllowsMatchingOrdinaryRemoteTarget() {
        let target = timeZone(offset: "+08:00")
        let projection = SiteGatewayTimeZoneReviewProjectionPolicy.project(
            localTimeZone: target,
            remote: remote(role: .owner, timezone: target, gateways: []),
            explicitContext: nil
        )

        require(
            projection == .remote(target),
            "Without explicit failures, only a local Site matching the remote Site may expose ordinary Review"
        )
    }

    private static func testReviewProjectionHidesVisitorAndInvalidTimeZones() {
        let target = timeZone(offset: "+08:00")
        let visitor = remote(role: .visitor, timezone: target, gateways: [])
        let invalidRemote = remote(role: .owner, timezone: nil, gateways: [])
        let invalidTimeZone = SiteTimeZoneValue(
            ianaId: "Invalid/Zone",
            rawUTCOffset: "+08:00"
        )!

        require(
            SiteGatewayTimeZoneReviewProjectionPolicy.project(
                localTimeZone: target,
                remote: visitor,
                explicitContext: nil
            ) == .hidden,
            "Visitor access must never expose a Gateway Review target"
        )
        require(
            SiteGatewayTimeZoneReviewProjectionPolicy.project(
                localTimeZone: nil,
                remote: remote(role: .owner, timezone: target, gateways: []),
                explicitContext: nil
            ) == .hidden &&
                SiteGatewayTimeZoneReviewProjectionPolicy.project(
                    localTimeZone: target,
                    remote: invalidRemote,
                    explicitContext: nil
                ) == .hidden &&
                SiteGatewayTimeZoneReviewProjectionPolicy.project(
                    localTimeZone: invalidTimeZone,
                    remote: remote(
                        role: .owner,
                        timezone: invalidTimeZone,
                        gateways: []
                    ),
                    explicitContext: nil
                ) == .hidden,
            "Missing or invalid local and remote timezone values must fail closed"
        )
    }

    private static func target(
        id: String,
        requestMAC: String,
        requiresSync: Bool
    ) -> SiteGatewayCloudTimeZoneTarget {
        SiteGatewayCloudTimeZoneTarget(
            id: id,
            requestMAC: requestMAC,
            displayName: id,
            remoteOrder: 0,
            effectiveOffsetMinutes: requiresSync ? 0 : 480,
            requiresSync: requiresSync
        )
    }

    private static func timeZone(offset: String = "+08:00") -> SiteTimeZoneValue {
        SiteTimeZoneValue(
            ianaId: "Asia/Singapore",
            rawUTCOffset: offset
        )!
    }

    private static func remote(
        role: SiteEntryRole,
        timezone: SiteTimeZoneValue? = timeZone(),
        spaces: [SiteEntrySpaceAccessSnapshot] = [],
        gateways: [SiteEntryGatewayTimeZoneSnapshot]
    ) -> SiteEntryTimeZoneRemoteSnapshot {
        SiteEntryTimeZoneRemoteSnapshot(
            role: role,
            values: SitePropsValues(
                siteName: "Site",
                imageId: 0,
                timezone: timezone
            ),
            timestamp: 1,
            spaces: spaces,
            gateways: gateways
        )
    }

    private static func space(
        _ role: SiteEntryRole,
        gatewayId: String
    ) -> SiteEntrySpaceAccessSnapshot {
        SiteEntrySpaceAccessSnapshot(role: role, gatewayId: gatewayId)
    }

    private static func gateway(
        _ id: String,
        offsetMinutes: Int?
    ) -> SiteEntryGatewayTimeZoneSnapshot {
        SiteEntryGatewayTimeZoneSnapshot(id: id, offsetMinutes: offsetMinutes)
    }
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fatalError(message)
    }
}
