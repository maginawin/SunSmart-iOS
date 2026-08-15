//
//  SiteTimeZoneSyncPresentationState.swift
//  SunSmart
//
//  Created by One on 2026/8/16.
//

import Foundation

enum SiteTimeZoneSyncSitePresentation: Equatable {
    case savedSuccessfully
}

enum SiteTimeZoneSyncWorkingStage: Equatable {
    case checkingSite
    case savingSite
}

enum SiteTimeZoneGatewayPresentation: Equatable {
    case notStarted
    case unavailable
    case batch(SiteGatewayCloudTimeZoneBatchState)
}

enum SiteTimeZoneSyncPresentationState: Equatable {
    case working(SiteTimeZoneSyncWorkingStage)
    case result(
        site: SiteTimeZoneSyncSitePresentation,
        gateways: SiteTimeZoneGatewayPresentation
    )

    var canDismiss: Bool {
        switch self {
        case .working:
            return false
        case .result(_, .batch(let batch)):
            return batch.canDismiss
        case .result(_, .notStarted), .result(_, .unavailable):
            return true
        }
    }
}

struct SiteTimeZoneSyncResultLayoutPolicy {

    struct Layout: Equatable {
        let resultCardHeight: CGFloat
        let contentViewportHeight: CGFloat
        let footerHeight: CGFloat
        let contentScrolls: Bool
    }

    static func makeLayout(
        contentHeight: CGFloat,
        availableHeight: CGFloat,
        requestedFooterHeight: CGFloat
    ) -> Layout {
        let normalizedContentHeight = max(0, contentHeight)
        let normalizedAvailableHeight = max(0, availableHeight)
        let normalizedFooterHeight = max(0, requestedFooterHeight)
        let footerHeight = normalizedAvailableHeight > 0
            ? min(normalizedFooterHeight, normalizedAvailableHeight)
            : normalizedFooterHeight
        let preferredResultHeight = normalizedContentHeight + footerHeight
        let resultCardHeight = normalizedAvailableHeight > 0
            ? min(preferredResultHeight, normalizedAvailableHeight)
            : preferredResultHeight
        let contentViewportHeight = max(0, resultCardHeight - footerHeight)

        return Layout(
            resultCardHeight: resultCardHeight,
            contentViewportHeight: contentViewportHeight,
            footerHeight: footerHeight,
            contentScrolls: normalizedContentHeight > contentViewportHeight + 0.5
        )
    }
}
