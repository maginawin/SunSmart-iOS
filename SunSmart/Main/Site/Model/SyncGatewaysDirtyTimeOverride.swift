//
//  SyncGatewaysDirtyTimeOverride.swift
//  SunSmart
//
//  Created by One on 2026/8/13.
//

import Foundation

struct SyncGatewayDirtyTimeCandidate: Equatable {
    let id: String?
    let isCloudDirty: Bool
    let localTimestamp: UInt64
    let localOffsetMinutes: Int?
    let remoteOffsetMinutes: Int?
}

struct SyncGatewayDirtyTimeOverride: Equatable {
    let timestamp: UInt64
    let offsetMinutes: Int
}

enum SyncGatewaysDirtyTimeOverridePolicy {
    static func capture(
        targetOffsetMinutes: Int,
        candidates: [SyncGatewayDirtyTimeCandidate]
    ) -> [String: SyncGatewayDirtyTimeOverride] {
        candidates.reduce(into: [String: SyncGatewayDirtyTimeOverride]()) {
            result, candidate in
            guard let id = normalized(candidate.id),
                  result[id] == nil,
                  candidate.isCloudDirty,
                  candidate.localTimestamp > 0,
                  candidate.localOffsetMinutes == targetOffsetMinutes,
                  candidate.remoteOffsetMinutes != targetOffsetMinutes else {
                return
            }
            result[id] = SyncGatewayDirtyTimeOverride(
                timestamp: candidate.localTimestamp,
                offsetMinutes: targetOffsetMinutes
            )
        }
    }

    private static func normalized(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return value.isEmpty ? nil : value
    }
}
