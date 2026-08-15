//
//  SiteEntryTimeZoneSyncResponseParser.swift
//  SunSmart
//
//  Created by One on 2026/8/12.
//

import Foundation

private func trimmedGatewayIdentifier(_ rawValue: String?) -> String? {
    guard let rawValue else { return nil }
    let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? nil : value
}

enum SiteEntryRole: Equatable {
    case owner
    case editor
    case visitor
}

struct SiteEntrySpaceAccessSnapshot: Equatable {
    let role: SiteEntryRole
    let gatewayId: String?
    let requestGatewayId: String?

    init(role: SiteEntryRole, gatewayId: String?, requestGatewayId: String? = nil) {
        self.role = role
        self.gatewayId = SiteGatewayAccessScope.normalize(gatewayId)
        self.requestGatewayId = trimmedGatewayIdentifier(requestGatewayId ?? gatewayId)
    }
}

struct SiteEntryGatewayTimeZoneSnapshot: Equatable {
    let id: String?
    let requestMAC: String?
    let offsetMinutes: Int?

    init(id: String?, requestMAC: String? = nil, offsetMinutes: Int?) {
        self.id = SiteGatewayAccessScope.normalize(id)
        self.requestMAC = trimmedGatewayIdentifier(requestMAC ?? id)
        self.offsetMinutes = offsetMinutes
    }
}

struct SiteEntryTimeZoneRemoteSnapshot: Equatable {
    let role: SiteEntryRole
    let values: SitePropsValues
    let timestamp: Int64
    let spaces: [SiteEntrySpaceAccessSnapshot]
    let gateways: [SiteEntryGatewayTimeZoneSnapshot]

    var timezone: SiteTimeZoneValue? { values.timezone }
}

enum SiteEntryTimeZoneSyncResponseParser {

    static func parse(
        siteData: [String: Any]
    ) -> SiteEntryTimeZoneRemoteSnapshot? {
        guard
            let siteName = siteData["siteName"] as? String,
            let imageId = integer(from: siteData["imageId"]),
            let timestamp = timestamp(from: siteData["updateTimestamp"])
        else {
            return nil
        }

        let siteRole = role(from: siteData["role"])
        let values = SitePropsValues(
            siteName: siteName,
            imageId: imageId,
            timezone: validTimeZone(from: siteData["timezone"])
        )
        let spaces = (siteData["spaces"] as? [[String: Any]] ?? []).map {
            SiteEntrySpaceAccessSnapshot(
                role: role(from: $0["role"]),
                gatewayId: $0["gatewayId"] as? String,
                requestGatewayId: $0["gatewayId"] as? String
            )
        }
        let gateways = (siteData["gateways"] as? [[String: Any]] ?? []).map {
            SiteEntryGatewayTimeZoneSnapshot(
                id: $0["macAddress"] as? String,
                requestMAC: $0["macAddress"] as? String,
                offsetMinutes: offsetMinutes(from: $0["timezoneOffset"])
            )
        }

        return SiteEntryTimeZoneRemoteSnapshot(
            role: siteRole,
            values: values,
            timestamp: timestamp,
            spaces: spaces,
            gateways: gateways
        )
    }

    private static func role(from rawValue: Any?) -> SiteEntryRole {
        switch (rawValue as? String)?.lowercased() {
        case "owner":
            return .owner
        case "editor":
            return .editor
        default:
            return .visitor
        }
    }

    private static func validTimeZone(from rawValue: Any?) -> SiteTimeZoneValue? {
        guard
            let storageValue = rawValue as? String,
            let value = SiteTimeZoneValue(storageValue: storageValue),
            TimeZone(identifier: value.ianaId) != nil
        else {
            return nil
        }
        return value
    }

    private static func offsetMinutes(from rawValue: Any?) -> Int? {
        guard let value = integer(from: rawValue), (0...255).contains(value) else {
            return nil
        }
        return (value - 64) * 15
    }

    private static func isBoolean(_ rawValue: Any) -> Bool {
        guard let number = rawValue as? NSNumber else { return false }
        return CFGetTypeID(number) == CFBooleanGetTypeID()
    }

    private static func integer(from rawValue: Any?) -> Int? {
        guard let rawValue, !isBoolean(rawValue) else { return nil }

        if let value = rawValue as? Int {
            return value
        }
        if let value = rawValue as? Int64,
           value >= Int64(Int.min),
           value <= Int64(Int.max) {
            return Int(value)
        }
        if let value = rawValue as? NSNumber {
            let double = value.doubleValue
            guard
                double.isFinite,
                double.rounded(.towardZero) == double,
                double >= Double(Int.min),
                double <= Double(Int.max)
            else {
                return nil
            }
            return Int(double)
        }
        if let value = rawValue as? String {
            return Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    private static func timestamp(from rawValue: Any?) -> Int64? {
        guard let rawValue, !isBoolean(rawValue) else { return nil }

        if let value = rawValue as? Int64 {
            return value
        }
        if let value = rawValue as? Int {
            return Int64(value)
        }
        if let value = rawValue as? NSNumber {
            let double = value.doubleValue
            guard
                double.isFinite,
                double.rounded(.towardZero) == double,
                double >= Double(Int64.min),
                double <= Double(Int64.max)
            else {
                return nil
            }
            return Int64(double)
        }
        if let value = rawValue as? String {
            return Int64(value.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }
}
