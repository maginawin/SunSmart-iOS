//
//  SiteGatewayCloudTimeZoneResponseParser.swift
//  SunSmart
//
//  Created by One on 2026/8/15.
//

import Foundation

enum SiteGatewayCloudTimeZoneResponseParser {

    static func parseRequestID(from response: [String: Any]) -> Int64? {
        guard
            let data = response["data"] as? [String: Any],
            let requestID = positiveInt64(data["requestId"])
        else {
            return nil
        }
        return requestID
    }

    static func parseStatuses(
        from response: [String: Any]
    ) -> [SiteGatewayCloudTimeZoneRemoteStatusSnapshot]? {
        guard let data = response["data"] as? [Any] else {
            return nil
        }

        var statusesByID = [String: Set<SiteGatewayCloudTimeZoneRemoteStatus>]()
        var orderedIDs = [String]()

        for item in data {
            guard let values = item as? [String: Any] else {
                continue
            }

            for (rawID, rawStatus) in values.sorted(by: { $0.key < $1.key }) {
                guard
                    let id = normalizedID(rawID),
                    let status = remoteStatus(rawStatus)
                else {
                    continue
                }

                if statusesByID[id] == nil {
                    orderedIDs.append(id)
                }
                statusesByID[id, default: []].insert(status)
            }
        }

        return orderedIDs.compactMap { id in
            guard let statuses = statusesByID[id] else {
                return nil
            }
            return SiteGatewayCloudTimeZoneRemoteStatusSnapshot(id: id, statuses: statuses)
        }
    }

    private static func positiveInt64(_ value: Any?) -> Int64? {
        guard let value else {
            return nil
        }
        if value is Bool {
            return nil
        }
        if let value = value as? NSNumber {
            let type = String(cString: value.objCType)
            guard ["c", "s", "i", "l", "q", "C", "S", "I", "L", "Q"].contains(type) else {
                return nil
            }
            let requestID = value.int64Value
            return requestID > 0 ? requestID : nil
        }
        if let value = value as? String {
            let requestID = Int64(value.trimmingCharacters(in: .whitespacesAndNewlines))
            return requestID.flatMap { $0 > 0 ? $0 : nil }
        }
        return nil
    }

    private static func normalizedID(_ value: String) -> String? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? nil : normalized
    }

    private static func remoteStatus(_ value: Any) -> SiteGatewayCloudTimeZoneRemoteStatus? {
        guard let value = value as? String else {
            return nil
        }

        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "requested":
            return .requested
        case "succeed", "succeeded":
            return .succeed
        case "failed":
            return .failed
        case "expired":
            return .expired
        default:
            return nil
        }
    }
}
