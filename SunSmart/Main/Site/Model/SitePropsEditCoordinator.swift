//
//  SitePropsEditCoordinator.swift
//  SunSmart
//
//  Created by One on 2026/8/11.
//

import Foundation

struct SitePropsEditDraft: Equatable {
    let original: SitePropsValues
    var values: SitePropsValues
}

struct SitePropsCommitPlan: Equatable {
    let targetState: SitePropsLocalState
    let updateSnapshot: SitePropsUpdateSnapshot?
    let hasNewChanges: Bool
    let includesTimezone: Bool

    var hasPendingFields: Bool {
        return !targetState.pending.fields.isEmpty
    }
}

enum SitePropsLocalSaveError: Error {
    case databaseWriteFailed
}

@MainActor
final class SitePropsEditCoordinator {

    let site: SiteData
    private let apiClient: SitePropsAPIClientProtocol

    init(
        site: SiteData,
        apiClient: SitePropsAPIClientProtocol = SitePropsAPIClient()
    ) {
        self.site = site
        self.apiClient = apiClient
    }

    func prepareDraft(online: Bool) async -> SitePropsEditDraft {
        guard online else {
            return makeDraft(from: currentState())
        }

        let result = await apiClient.retrieve(siteId: site.id)
        guard case .success(let remote) = result else {
            return makeDraft(from: currentState())
        }

        let local = currentState()
        let merge = SitePropsEditPolicy.mergeRetrieve(local: local, remote: remote)
        guard merge.shouldPersist else {
            return makeDraft(from: merge.state)
        }

        guard persistState(merge.state) else {
            return makeDraft(from: local)
        }
        return makeDraft(from: merge.state)
    }

    func makeCommitPlan(
        draft: SitePropsEditDraft,
        online: Bool,
        now: Int64
    ) -> SitePropsCommitPlan {
        let local = currentState()
        let changedFields = SitePropsEditPolicy.changedFields(
            from: draft.original,
            to: draft.values
        )
        guard let snapshot = SitePropsEditPolicy.makeUpdateSnapshot(
            siteId: site.id,
            local: local,
            original: draft.original,
            draft: draft.values,
            now: now
        ) else {
            return SitePropsCommitPlan(
                targetState: local,
                updateSnapshot: nil,
                hasNewChanges: false,
                includesTimezone: false
            )
        }

        let targetState = SitePropsLocalState(
            values: draft.values,
            lastUpdate: snapshot.timestamp,
            lastUploadCloudTimestamp: local.lastUploadCloudTimestamp,
            pending: SitePropsPendingState(
                fields: snapshot.fields,
                timestamp: snapshot.timestamp
            )
        )
        return SitePropsCommitPlan(
            targetState: targetState,
            updateSnapshot: online ? snapshot : nil,
            hasNewChanges: !changedFields.isEmpty,
            includesTimezone: snapshot.fields.contains(.timezone)
        )
    }

    func persist(
        _ plan: SitePropsCommitPlan
    ) -> Result<SitePropsUpdateSnapshot?, SitePropsLocalSaveError> {
        let local = currentState()
        guard plan.targetState != local else {
            return .success(plan.updateSnapshot)
        }

        guard persistState(plan.targetState) else {
            return .failure(.databaseWriteFailed)
        }
        return .success(plan.updateSnapshot)
    }

    func submit(_ snapshot: SitePropsUpdateSnapshot) async -> Bool {
        let result = await apiClient.update(snapshot: snapshot)
        guard
            case .success(let response) = result,
            SitePropsEditPolicy.updateResponseMatches(
                request: snapshot,
                response: response
            )
        else {
            return false
        }

        let local = currentState()
        let updated = SitePropsEditPolicy.localStateAfterSuccessfulUpdate(
            current: local,
            request: snapshot
        )
        guard updated != local else {
            return true
        }

        guard persistState(updated) else {
            return false
        }
        return true
    }

    func currentState() -> SitePropsLocalState {
        return SitePropsLocalState(
            values: SitePropsValues(
                siteName: site.name,
                imageId: site.imageId,
                timezone: site.timezone.flatMap(SiteTimeZoneValue.init(storageValue:))
            ),
            lastUpdate: site.lastUpdate,
            lastUploadCloudTimestamp: site.lastUploadCloudTimestamp,
            pending: SitePropsPendingState(
                fields: site.pendingSitePropsMask,
                timestamp: site.pendingSitePropsTimestamp
            )
        )
    }

    @discardableResult
    func persistState(_ state: SitePropsLocalState) -> Bool {
        let local = currentState()
        apply(state)
        guard site.save() else {
            apply(local)
            return false
        }
        return true
    }

    private func makeDraft(from state: SitePropsLocalState) -> SitePropsEditDraft {
        return SitePropsEditDraft(original: state.values, values: state.values)
    }

    private func apply(_ state: SitePropsLocalState) {
        site.name = state.values.siteName
        site.imageId = state.values.imageId
        site.timezone = state.values.timezone?.storageValue
        site.lastUpdate = state.lastUpdate
        site.lastUploadCloudTimestamp = state.lastUploadCloudTimestamp
        site.pendingSitePropsMask = state.pending.fields
        site.pendingSitePropsTimestamp = state.pending.timestamp
    }
}

extension SitePropsEditCoordinator: SiteTimeZoneEditSubmitting {}

extension SitePropsEditCoordinator: SiteEntryTimeZoneSyncStore {}
