import Foundation

// The runner compiles the real Controller refresh/finish/review-action methods and
// Overlay showResult method against these UI boundaries. No UIKit or Mesh is run.
final class EntryOverlayBoundary {
    enum State { case checking, gatewaysNeedSync(SiteEntryTimeZoneResult), result(SiteEntryTimeZoneResult) }
    var state: State = .checking
    var superview: Bool? = true
    func update(state: State) { self.state = state }
    func dismiss() { superview = nil }
}
final class CoordinatorBoundary { func cancel() {} }
extension String { var localizedString: String { self } }
enum XWHUDManager {
    static var messages: [String] = []
    static func showTipHUD(_ message: String) { messages.append(message) }
}
final class EntryHostBoundary {
    var entrySyncSessionToken: UUID? = UUID()
    var entrySyncTask: Task<Void, Never>?
    let entrySyncCoordinator = CoordinatorBoundary()
    let entrySyncOverlay = EntryOverlayBoundary()
    var navigationLocked = true
    var continuations = 0
    var routes = 0
    var routeDecision: SiteGatewayReviewRouteDecision = .noPending
    var gatewayTimeZoneReviewContext: SiteGatewayTimeZoneReviewContext?
    var entryEvaluation: SiteEntryGatewayEvaluation?
    var review: (projection: SiteGatewayTimeZoneReviewProjection, evaluation: SiteEntryGatewayEvaluation)?
    var headerSummary: SiteEntryGatewaySummary?
    func setEntrySyncNavigationLocked(_ locked: Bool) { navigationLocked = locked }
    func continuePostImportNavigationIfNeeded() { continuations += 1 }
    func observeSiteTimeZone() {}
    func entryGatewayEvaluation(timezone: SiteTimeZoneValue) -> SiteEntryGatewayEvaluation? { entryEvaluation }
    func currentGatewayReview() -> (projection: SiteGatewayTimeZoneReviewProjection, evaluation: SiteEntryGatewayEvaluation)? { review }
    func updateTimeZoneReviewState(_ review: (projection: SiteGatewayTimeZoneReviewProjection, evaluation: SiteEntryGatewayEvaluation)?) {
        headerSummary = review?.evaluation.summary
    }
    func logEntryGatewayReview(_ phase: String, summary: SiteEntryGatewaySummary? = nil) {}
    // Runtime context construction is tested by its policy suite; its UI effects
    // execute the production finishGatewayReviewRoute, not a copied switch.
    func showSyncGatewaysPage() {
        finishGatewayReviewRoute(routeDecision)
        if routeDecision == .ready { routes += 1 }
    }
    func clickReview() { handleEntrySyncReview() }
    func closeNormally() { finishEntrySyncOverlay() }
    func refresh() { refreshCurrentGatewayTimeZoneReviewProjection() }
}

@main struct SiteEntryGatewayHostTests {
    static func main() {
        let timezone = SiteTimeZoneValue(storageValue: "America/New_York")!
        let remote = SiteEntryTimeZoneRemoteSnapshot(role: .owner,
            values: .init(siteName: "Site", imageId: 0, timezone: timezone), timestamp: 100,
            spaces: [], gateways: [.init(id: "gateway", offsetMinutes: -300)])
        let pending = SiteEntryTimeZoneResult(timezone: timezone, site: .alreadyInSync, gateway: .pending(1))
        let host = EntryHostBoundary()
        host.entrySyncOverlay.showResult(pending)
        host.review = (.remote(timezone), .init(targetOffsetMinutes: -300, remote: remote))
        host.refresh()
        guard case .result(let updated) = host.entrySyncOverlay.state else { fatalError("A late in-sync observation must remove Review") }
        precondition(updated.gateway == .inSync && host.headerSummary == .inSync)
        host.review = (.remote(timezone), .init(targetOffsetMinutes: nil, remote: remote))
        host.refresh()
        guard case .result(let unavailable) = host.entrySyncOverlay.state else { fatalError("Expired offset must remove Review") }
        precondition(unavailable.gateway == .unavailable)
        host.review = nil
        host.refresh()
        guard case .result(let changed) = host.entrySyncOverlay.state else { fatalError("Lost context must remove Review") }
        precondition(changed.gateway == .unavailable)

        // Site upload is confirmed while its old remote metadata is still being
        // reconciled. No remaining failures must not turn the result into unknown.
        host.entryEvaluation = .init(targetOffsetMinutes: -300, remote: remote)
        host.entrySyncOverlay.showResult(.init(timezone: timezone, site: .updatedToServer, gateway: .unavailable))
        host.refresh()
        guard case .result(let uploaded) = host.entrySyncOverlay.state else { fatalError("Completed upload must stay dismissible") }
        precondition(uploaded.gateway == .inSync && host.gatewayTimeZoneReviewContext == nil)

        for (decision, expectedRoutes, expectedMessage) in [
            (SiteGatewayReviewRouteDecision.ready, 1, nil),
            (.noPending, 0, "site_entry_sync_no_gateways"),
            (.unavailable(.offsetUnavailable), 0, "site_entry_sync_offset_unavailable"),
            (.unavailable(.changedContext), 0, "site_entry_sync_context_changed"),
            (.unavailable(.missingSnapshot), 0, "site_entry_sync_review_unavailable"),
            (.unavailable(.missingNetwork), 0, "site_entry_sync_review_unavailable"),
            (.unavailable(.missingNavigation), 0, "site_entry_sync_review_unavailable")
        ] {
            let action = EntryHostBoundary()
            XWHUDManager.messages = []
            action.routeDecision = decision
            action.clickReview()
            precondition(action.continuations == 0, "Review must not also enter a Space")
            precondition(action.routes == expectedRoutes && action.entrySyncOverlay.superview == nil)
            precondition(action.entrySyncSessionToken == nil && !action.navigationLocked)
            precondition(XWHUDManager.messages == expectedMessage.map { [$0] } ?? [])
        }
        let normal = EntryHostBoundary()
        normal.closeNormally()
        precondition(normal.continuations == 1, "Got it/Later must still continue deferred navigation")
        print("SiteEntryGatewayHostTests passed (production overlay refresh and Review completion methods)")
    }
}
