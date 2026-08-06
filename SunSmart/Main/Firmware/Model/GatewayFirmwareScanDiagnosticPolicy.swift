//
//  GatewayFirmwareScanDiagnosticPolicy.swift
//  SunSmart
//
//  Created by One on 2026/8/6.
//

import Foundation

enum GatewayFirmwareScanDiagnosticPolicy {
    static func siteCandidateReason(
        nodeResolved: Bool,
        canConfigure: Bool,
        isOwner: Bool,
        hasAssociatedSpace: Bool
    ) -> String {
        guard nodeResolved else {
            return "gateway_model_node_unresolved"
        }
        guard isOwner || canConfigure else {
            return "permission_denied"
        }
        guard isOwner || hasAssociatedSpace else {
            return "no_associated_space"
        }
        return "candidate_accepted"
    }

    static func pageCandidateReason(productID: UInt16?) -> String {
        productID == nil ? "missing_product_id" : "page_candidate_accepted"
    }

    static func pageMatchReason(isExpectedAddress: Bool) -> String {
        isExpectedAddress ? "page_match_accepted" : "unexpected_node_address"
    }

    static func eligibilityReason(
        currentVersion: String?,
        targetVersion: String?,
        versionEligibility: FirmwareVersionUpdateEligibility,
        rssi: Int?,
        scanFinished: Bool
    ) -> String? {
        guard targetVersion != nil else {
            return "missing_local_firmware"
        }
        guard currentVersion != nil else {
            return "missing_current_version"
        }

        switch versionEligibility {
        case .invalid:
            return "invalid_version"
        case .disallowed:
            return "target_not_upgradeable"
        case .allowed:
            guard let rssi else {
                return scanFinished ? "rssi_unavailable" : nil
            }
            return rssi >= -80 ? "upgrade_eligible" : "rssi_below_threshold"
        }
    }
}
