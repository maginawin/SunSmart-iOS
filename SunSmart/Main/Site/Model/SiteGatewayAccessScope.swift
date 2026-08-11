//
//  SiteGatewayAccessScope.swift
//  SunSmart
//
//  Created by One on 2026/8/13.
//

import Foundation

enum SiteGatewayAccessScope: Equatable {
    case owner
    case editor(Set<String>)
    case visitor

    static func resolve(
        remote: SiteEntryTimeZoneRemoteSnapshot
    ) -> SiteGatewayAccessScope {
        if remote.role == .owner {
            return .owner
        }

        let editorSpaces = remote.spaces.filter { $0.role == .editor }
        guard !editorSpaces.isEmpty else {
            return .visitor
        }
        return .editor(Set(editorSpaces.compactMap { normalize($0.gatewayId) }))
    }

    func contains(normalizedGatewayID: String) -> Bool {
        switch self {
        case .owner:
            return true
        case .editor(let gatewayIDs):
            return gatewayIDs.contains(normalizedGatewayID)
        case .visitor:
            return false
        }
    }

    static func normalize(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return value.isEmpty ? nil : value
    }
}
