import Foundation

@main
struct SiteTimeZoneSyncPresentationStateTests {

    static func main() {
        testCanDismissTracksOnlyThePresentationLifecycle()
        testSitePresentationUsesLocalSaveSemantics()
        print("SiteTimeZoneSyncPresentationStateTests passed")
    }

    private static func testCanDismissTracksOnlyThePresentationLifecycle() {
        let site = SiteTimeZoneSyncSitePresentation.savedSuccessfully
        let pushingBatch = batch(requiresSync: true)
        let terminalBatch = batch(requiresSync: false)

        require(
            !SiteTimeZoneSyncPresentationState.working(.savingSite).canDismiss,
            "A saving Site state must not be dismissible"
        )
        require(
            !SiteTimeZoneSyncPresentationState.result(
                site: site,
                gateways: .batch(pushingBatch)
            ).canDismiss,
            "A Gateway batch with a pushing row must not be dismissible"
        )
        require(
            SiteTimeZoneSyncPresentationState.result(
                site: site,
                gateways: .batch(terminalBatch)
            ).canDismiss,
            "A terminal Gateway batch must be dismissible"
        )
        require(
            SiteTimeZoneSyncPresentationState.result(
                site: site,
                gateways: .notStarted
            ).canDismiss,
            "A not-started Gateway presentation must be dismissible"
        )
        require(
            SiteTimeZoneSyncPresentationState.result(
                site: site,
                gateways: .unavailable
            ).canDismiss,
            "An unavailable Gateway presentation must be dismissible"
        )
    }

    private static func testSitePresentationUsesLocalSaveSemantics() {
        require(
            SiteTimeZoneSyncSitePresentation.savedSuccessfully == .savedSuccessfully,
            "Edit Site presentation must express only the successful local save"
        )
    }

    private static func batch(requiresSync: Bool) -> SiteGatewayCloudTimeZoneBatchState {
        SiteGatewayCloudTimeZoneBatchState(targets: [
            SiteGatewayCloudTimeZoneTarget(
                id: "gateway",
                requestMAC: "GATEWAY",
                displayName: "Gateway",
                remoteOrder: 0,
                effectiveOffsetMinutes: requiresSync ? 0 : 480,
                requiresSync: requiresSync
            )
        ])
    }

    private static func require(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) {
        if !condition() {
            fatalError(message)
        }
    }
}
