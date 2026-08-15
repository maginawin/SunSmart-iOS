//
//  SiteTimeZoneEditSyncCoordinator.swift
//  SunSmart
//
//  Created by One on 2026/8/16.
//

import Foundation

@MainActor
protocol SiteTimeZoneEditSubmitting: AnyObject {
    func submit(_ snapshot: SitePropsUpdateSnapshot) async -> Bool
}

enum SiteTimeZoneEditSyncOutcome: Equatable {
    case siteFailed
    case completed(SiteGatewayCloudTimeZoneSessionResult)
}

@MainActor
final class SiteTimeZoneEditSyncCoordinator {

    private let siteID: String
    private let submitter: SiteTimeZoneEditSubmitting
    private let gatewaySession: SiteGatewayCloudTimeZoneSessionCoordinator
    private let makeTargets: @MainActor (
        SiteTimeZoneValue
    ) -> [SiteGatewayCloudTimeZoneTarget]
    private var activeToken: UUID?

    init(
        siteID: String,
        submitter: SiteTimeZoneEditSubmitting,
        gatewaySession: SiteGatewayCloudTimeZoneSessionCoordinator,
        makeTargets: @escaping @MainActor (
            SiteTimeZoneValue
        ) -> [SiteGatewayCloudTimeZoneTarget]
    ) {
        self.siteID = siteID
        self.submitter = submitter
        self.gatewaySession = gatewaySession
        self.makeTargets = makeTargets
    }

    func run(
        snapshot: SitePropsUpdateSnapshot,
        onUpdate: @escaping @MainActor (SiteTimeZoneSyncPresentationState) -> Void
    ) async -> SiteTimeZoneEditSyncOutcome? {
        guard snapshot.fields.contains(.timezone),
              let targetTimeZone = snapshot.values.timezone else {
            return .siteFailed
        }

        let token = UUID()
        cancel()
        activeToken = token
        defer {
            if activeToken == token {
                activeToken = nil
            }
        }

        return await withTaskCancellationHandler(operation: {
            guard publish(.working(.savingSite), token: token, onUpdate: onUpdate) else {
                return nil
            }

            let didSubmit = await submitter.submit(snapshot)
            guard activeToken == token else { return nil }

            let siteResult = SiteTimeZoneSyncSitePresentation.savedSuccessfully
            let targets = makeTargets(targetTimeZone)
            guard activeToken == token else { return nil }

            guard didSubmit else {
                let result = failedGatewayResult(
                    targetTimeZone: targetTimeZone,
                    targets: targets
                )
                _ = publish(
                    .result(site: siteResult, gateways: .batch(result.terminalState)),
                    token: token,
                    onUpdate: onUpdate
                )
                return .completed(result)
            }

            let sessionResult = await gatewaySession.run(
                input: SiteGatewayCloudTimeZoneSessionInput(
                    siteID: siteID,
                    targetTimeZone: targetTimeZone,
                    targets: targets,
                    confirmedOffsetMinutesByGatewayID: [:]
                ),
                onUpdate: { [weak self] batch in
                    guard self?.activeToken == token else { return }
                    onUpdate(.result(site: siteResult, gateways: .batch(batch)))
                }
            )
            guard activeToken == token, let sessionResult else { return nil }
            return .completed(sessionResult)
        }, onCancel: { [weak self] in
            Task { @MainActor in
                self?.cancel(token: token)
            }
        })
    }

    func cancel() {
        activeToken = nil
        gatewaySession.cancel()
    }

    private func failedGatewayResult(
        targetTimeZone: SiteTimeZoneValue,
        targets: [SiteGatewayCloudTimeZoneTarget]
    ) -> SiteGatewayCloudTimeZoneSessionResult {
        let initialState = SiteGatewayCloudTimeZoneBatchState(targets: targets)
        var terminalState = initialState
        terminalState.failPushing()
        return SiteGatewayCloudTimeZoneSessionResult(
            initialState: initialState,
            terminalState: terminalState,
            confirmedOffsetMinutesByGatewayID: [:],
            reviewContext: SiteGatewayTimeZoneReviewContext.make(
                targetTimeZone: targetTimeZone,
                terminalState: terminalState
            )
        )
    }

    private func cancel(token: UUID) {
        guard activeToken == token else { return }
        cancel()
    }

    @discardableResult
    private func publish(
        _ state: SiteTimeZoneSyncPresentationState,
        token: UUID,
        onUpdate: @MainActor (SiteTimeZoneSyncPresentationState) -> Void
    ) -> Bool {
        guard activeToken == token else { return false }
        onUpdate(state)
        return true
    }
}
