//
//  SiteTimeSetMessageFactory.swift
//  SunSmart
//
//  Created by One on 2026/8/16.
//

import Foundation

enum SiteTimeSetPhoneFallbackReason: Equatable {
    case missingSite
    case missingTimeZone
    case invalidTimeZone
    case unencodableSiteOffset
}

enum SiteTimeSetTimeZoneSource: Equatable {
    case site
    case phoneFallback(SiteTimeSetPhoneFallbackReason)
}

struct SiteTimeSetTimeZoneResolution {
    let timeZone: TimeZone
    let offsetMinutes: Int
    let source: SiteTimeSetTimeZoneSource
}

enum SiteTimeSetMessageFactory {

    static func resolve(
        storageValue: String?,
        phoneTimeZone: TimeZone = .current,
        at date: Date = Date()
    ) -> SiteTimeSetTimeZoneResolution? {
        let fallbackReason: SiteTimeSetPhoneFallbackReason
        if let storageValue,
           !storageValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let value = SiteTimeZoneValue(storageValue: storageValue) {
                if value.isMeshTimeZoneOffsetEncodable,
                   let fixedTimeZone = TimeZone(
                       secondsFromGMT: value.offsetMinutes * 60
                   ) {
                    return SiteTimeSetTimeZoneResolution(
                        timeZone: fixedTimeZone,
                        offsetMinutes: value.offsetMinutes,
                        source: .site
                    )
                }
                fallbackReason = .unencodableSiteOffset
            } else {
                fallbackReason = .invalidTimeZone
            }
        } else {
            fallbackReason = .missingTimeZone
        }

        return phoneFallback(
            reason: fallbackReason,
            phoneTimeZone: phoneTimeZone,
            at: date
        )
    }

    private static func phoneFallback(
        reason: SiteTimeSetPhoneFallbackReason,
        phoneTimeZone: TimeZone,
        at date: Date
    ) -> SiteTimeSetTimeZoneResolution? {
        let secondsFromGMT = phoneTimeZone.secondsFromGMT(for: date)
        guard secondsFromGMT.isMultiple(of: 15 * 60) else {
            return nil
        }
        let offsetMinutes = secondsFromGMT / 60
        let encodedOffset = offsetMinutes / 15 + 64
        guard (0...Int(UInt8.max)).contains(encodedOffset),
              let fixedTimeZone = TimeZone(secondsFromGMT: secondsFromGMT) else {
            return nil
        }
        return SiteTimeSetTimeZoneResolution(
            timeZone: fixedTimeZone,
            offsetMinutes: offsetMinutes,
            source: .phoneFallback(reason)
        )
    }
}

#if canImport(NordicSigMeshSDK)
import NordicSigMeshSDK

struct SiteTimeSetMessagePlan {
    let handle: MeshMessageHandle
    let targetOffsetMinutes: Int
    let source: SiteTimeSetTimeZoneSource
}

extension SiteTimeSetMessageFactory {

    static func resolve(
        siteID: String,
        phoneTimeZone: TimeZone = .current,
        at date: Date = Date()
    ) -> SiteTimeSetTimeZoneResolution? {
        guard let site = SiteData.load(siteId: siteID) else {
            return phoneFallback(
                reason: .missingSite,
                phoneTimeZone: phoneTimeZone,
                at: date
            )
        }
        return resolve(
            storageValue: site.timezone,
            phoneTimeZone: phoneTimeZone,
            at: date
        )
    }

    static func resolve(
        node: Node,
        phoneTimeZone: TimeZone = .current,
        at date: Date = Date()
    ) -> SiteTimeSetTimeZoneResolution? {
        guard let siteID = node.network?.uuid.uuidString else {
            return phoneFallback(
                reason: .missingSite,
                phoneTimeZone: phoneTimeZone,
                at: date
            )
        }
        return resolve(
            siteID: siteID,
            phoneTimeZone: phoneTimeZone,
            at: date
        )
    }

    static func makeMessage(
        siteID: String,
        date: Date = Date(),
        phoneTimeZone: TimeZone = .current
    ) -> TimeSet? {
        guard let resolution = resolve(
            siteID: siteID,
            phoneTimeZone: phoneTimeZone,
            at: date
        ) else {
            return nil
        }
        logFallbackIfNeeded(resolution.source)
        return Node.setLocalTimeMessage(
            date: date,
            timeZone: resolution.timeZone
        )
    }

    static func makeHandle(
        node: Node,
        model: Model,
        phoneTimeZone: TimeZone = .current,
        at date: Date = Date()
    ) -> MeshMessageHandle? {
        return makePlan(
            node: node,
            model: model,
            phoneTimeZone: phoneTimeZone,
            at: date
        )?.handle
    }

    static func makePlan(
        node: Node,
        model: Model,
        phoneTimeZone: TimeZone = .current,
        at date: Date = Date()
    ) -> SiteTimeSetMessagePlan? {
        guard let resolution = resolve(
            node: node,
            phoneTimeZone: phoneTimeZone,
            at: date
        ) else {
            return nil
        }
        return makePlan(model: model, resolution: resolution)
    }

    static func makePlan(
        model: Model,
        resolution: SiteTimeSetTimeZoneResolution
    ) -> SiteTimeSetMessagePlan {
        logFallbackIfNeeded(resolution.source)
        return SiteTimeSetMessagePlan(
            handle: Node.makeLocalTimeSetMessageHandle(
                model: model,
                timeZone: resolution.timeZone
            ),
            targetOffsetMinutes: resolution.offsetMinutes,
            source: resolution.source
        )
    }

    private static func logFallbackIfNeeded(
        _ source: SiteTimeSetTimeZoneSource
    ) {
        #if DEBUG
        if case .phoneFallback(let reason) = source {
            print("[TimeSet] use phone timezone fallback reason=\(reason)")
        }
        #endif
    }
}
#endif
