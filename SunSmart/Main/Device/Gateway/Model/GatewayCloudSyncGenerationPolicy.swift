//
//  GatewayCloudSyncGenerationPolicy.swift
//  SunSmart
//
//  Created by One on 2026/8/13.
//

import Foundation

enum GatewayCloudSyncGenerationPolicy {
    static func next(
        now: Int64,
        current: Int64,
        uploaded: Int64?
    ) -> Int64 {
        max(now, current + 1, (uploaded ?? 0) + 1)
    }

    static func confirmed(
        previous: Int64?,
        submitted: Int64
    ) -> Int64 {
        max(previous ?? 0, submitted)
    }

    static func needsAnotherUpload(
        current: Int64,
        confirmed: Int64?
    ) -> Bool {
        current > (confirmed ?? 0)
    }
}
