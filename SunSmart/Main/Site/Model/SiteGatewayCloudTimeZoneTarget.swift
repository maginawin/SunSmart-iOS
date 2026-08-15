//
//  SiteGatewayCloudTimeZoneTarget.swift
//  SunSmart
//
//  Created by One on 2026/8/15.
//

import Foundation

struct SiteGatewayCloudTimeZoneLocalSnapshot: Equatable {
    let displayName: String
    let dirtyOffsetMinutes: Int?
}

struct SiteGatewayCloudTimeZoneTarget: Equatable, Identifiable {
    let id: String
    let requestMAC: String
    let displayName: String
    let remoteOrder: Int
    let effectiveOffsetMinutes: Int?
    let requiresSync: Bool
}

enum SiteGatewayCloudTimeZoneConfirmationPolicy {
    static func acknowledgedGatewayIDs(
        confirmedOffsetMinutesByGatewayID: [String: Int],
        remote: [SiteEntryGatewayTimeZoneSnapshot]
    ) -> Set<String> {
        let confirmedByID = confirmedOffsetMinutesByGatewayID.reduce(
            into: [String: Int]()
        ) { result, pair in
            guard let id = SiteGatewayAccessScope.normalize(pair.key) else { return }
            result[id] = pair.value
        }
        let remoteByID = remote.reduce(
            into: [String: [SiteEntryGatewayTimeZoneSnapshot]]()
        ) { result, gateway in
            guard let id = SiteGatewayAccessScope.normalize(gateway.id) else { return }
            result[id, default: []].append(gateway)
        }

        return Set(confirmedByID.compactMap { id, confirmedOffset in
            guard let entries = remoteByID[id],
                  !entries.isEmpty,
                  entries.allSatisfy({ gateway in
                      gateway.offsetMinutes.map { $0 == confirmedOffset } == true
                  }) else {
                return nil
            }
            return id
        })
    }
}

enum SiteGatewayCloudTimeZoneTargetBuilder {

    static func build(
        targetOffsetMinutes: Int,
        remote: SiteEntryTimeZoneRemoteSnapshot,
        localByGatewayID: [String: SiteGatewayCloudTimeZoneLocalSnapshot],
        confirmedOffsetMinutesByGatewayID: [String: Int] = [:]
    ) -> [SiteGatewayCloudTimeZoneTarget] {
        let localByID = normalized(localByGatewayID)
        let confirmedByID = normalized(confirmedOffsetMinutesByGatewayID)
        let remoteEntries = remoteEntriesByID(remote.gateways)
        let remoteOffsets = remoteOffsetsByID(remoteEntries)

        let candidates: [(id: String, remoteOrder: Int, space: SiteEntrySpaceAccessSnapshot?)]
        switch SiteGatewayAccessScope.resolve(remote: remote) {
        case .visitor:
            return []

        case .owner:
            candidates = orderedRemoteCandidates(
                gateways: remote.gateways,
                allowedIDs: nil
            )

        case .editor(let gatewayIDs):
            let remoteCandidates = orderedRemoteCandidates(
                gateways: remote.gateways,
                allowedIDs: gatewayIDs
            )
            var seen = Set(remoteCandidates.map(\.id))
            var missingOrder = remote.gateways.count
            let missingCandidates = remote.spaces.compactMap { space -> (String, Int, SiteEntrySpaceAccessSnapshot?)? in
                guard
                    space.role == .editor,
                    let id = space.gatewayId,
                    gatewayIDs.contains(id),
                    seen.insert(id).inserted
                else {
                    return nil
                }
                defer { missingOrder += 1 }
                return (id, missingOrder, space)
            }
            candidates = remoteCandidates + missingCandidates
        }

        return candidates.map { candidate in
            let remoteEntry = remoteEntries[candidate.id]?.first
            let requestMAC = remoteEntry?.requestMAC
                ?? candidate.space?.requestGatewayId
                ?? candidate.id
            let local = localByID[candidate.id]
            let displayName = trimmed(local?.displayName) ?? requestMAC
            let remoteOffset = remoteOffsets[candidate.id] ?? nil
            let effectiveOffset = confirmedByID[candidate.id]
                ?? local?.dirtyOffsetMinutes
                ?? remoteOffset

            return SiteGatewayCloudTimeZoneTarget(
                id: candidate.id,
                requestMAC: requestMAC,
                displayName: displayName,
                remoteOrder: candidate.remoteOrder,
                effectiveOffsetMinutes: effectiveOffset,
                requiresSync: effectiveOffset != targetOffsetMinutes
            )
        }
    }

    private static func orderedRemoteCandidates(
        gateways: [SiteEntryGatewayTimeZoneSnapshot],
        allowedIDs: Set<String>?
    ) -> [(id: String, remoteOrder: Int, space: SiteEntrySpaceAccessSnapshot?)] {
        var seen = Set<String>()
        return gateways.enumerated().compactMap { index, gateway in
            guard
                let id = gateway.id,
                (allowedIDs == nil || allowedIDs?.contains(id) == true),
                seen.insert(id).inserted
            else {
                return nil
            }
            return (id, index, nil)
        }
    }

    private static func remoteEntriesByID(
        _ gateways: [SiteEntryGatewayTimeZoneSnapshot]
    ) -> [String: [SiteEntryGatewayTimeZoneSnapshot]] {
        gateways.reduce(into: [String: [SiteEntryGatewayTimeZoneSnapshot]]()) { result, gateway in
            guard let id = gateway.id else { return }
            result[id, default: []].append(gateway)
        }
    }

    private static func remoteOffsetsByID(
        _ entriesByID: [String: [SiteEntryGatewayTimeZoneSnapshot]]
    ) -> [String: Int?] {
        entriesByID.reduce(into: [String: Int?]()) { result, entry in
            let offsets = Set(entry.value.compactMap(\.offsetMinutes))
            result[entry.key] = offsets.count == 1 ? offsets.first : nil
        }
    }

    private static func normalized(
        _ snapshots: [String: SiteGatewayCloudTimeZoneLocalSnapshot]
    ) -> [String: SiteGatewayCloudTimeZoneLocalSnapshot] {
        snapshots.reduce(into: [String: SiteGatewayCloudTimeZoneLocalSnapshot]()) { result, pair in
            guard let id = SiteGatewayAccessScope.normalize(pair.key) else { return }
            result[id] = pair.value
        }
    }

    private static func normalized(_ offsets: [String: Int]) -> [String: Int] {
        offsets.reduce(into: [String: Int]()) { result, pair in
            guard let id = SiteGatewayAccessScope.normalize(pair.key) else { return }
            result[id] = pair.value
        }
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
