import Foundation

@main
struct GatewayFirmwareScanDiagnosticPolicyTests {
    static func main() {
        precondition(
            GatewayFirmwareScanDiagnosticPolicy.siteCandidateReason(
                nodeResolved: false,
                canConfigure: true,
                isOwner: true,
                hasAssociatedSpace: true
            ) == "gateway_model_node_unresolved"
        )
        precondition(
            GatewayFirmwareScanDiagnosticPolicy.siteCandidateReason(
                nodeResolved: true,
                canConfigure: false,
                isOwner: false,
                hasAssociatedSpace: true
            ) == "permission_denied"
        )
        precondition(
            GatewayFirmwareScanDiagnosticPolicy.siteCandidateReason(
                nodeResolved: true,
                canConfigure: true,
                isOwner: false,
                hasAssociatedSpace: false
            ) == "no_associated_space"
        )
        precondition(
            GatewayFirmwareScanDiagnosticPolicy.siteCandidateReason(
                nodeResolved: true,
                canConfigure: false,
                isOwner: true,
                hasAssociatedSpace: false
            ) == "candidate_accepted"
        )
        precondition(
            GatewayFirmwareScanDiagnosticPolicy.pageCandidateReason(
                productID: nil
            ) == "missing_product_id"
        )
        precondition(
            GatewayFirmwareScanDiagnosticPolicy.pageCandidateReason(
                productID: 0x2701
            ) == "page_candidate_accepted"
        )
        precondition(
            GatewayFirmwareScanDiagnosticPolicy.pageMatchReason(
                isExpectedAddress: false
            ) == "unexpected_node_address"
        )
        precondition(
            GatewayFirmwareScanDiagnosticPolicy.pageMatchReason(
                isExpectedAddress: true
            ) == "page_match_accepted"
        )

        let eligibilityCases: [(
            current: String?,
            target: String?,
            eligibility: FirmwareVersionUpdateEligibility,
            rssi: Int?,
            scanFinished: Bool,
            expected: String?
        )] = [
            ("1.0.0", nil, .invalid, nil, false, "missing_local_firmware"),
            (nil, "1.0.1", .invalid, nil, false, "missing_current_version"),
            ("bad", "1.0.1", .invalid, nil, false, "invalid_version"),
            ("1.0.1", "1.0.1", .disallowed, nil, false, "target_not_upgradeable"),
            ("1.0.0", "1.0.1", .allowed, nil, false, nil),
            ("1.0.0", "1.0.1", .allowed, nil, true, "rssi_unavailable"),
            ("1.0.0", "1.0.1", .allowed, -81, false, "rssi_below_threshold"),
            ("1.0.0", "1.0.1", .allowed, -80, false, "upgrade_eligible")
        ]

        for testCase in eligibilityCases {
            let actual = GatewayFirmwareScanDiagnosticPolicy.eligibilityReason(
                currentVersion: testCase.current,
                targetVersion: testCase.target,
                versionEligibility: testCase.eligibility,
                rssi: testCase.rssi,
                scanFinished: testCase.scanFinished
            )
            precondition(
                actual == testCase.expected,
                "Unexpected eligibility reason: \(String(describing: actual))"
            )
        }

        print("GatewayFirmwareScanDiagnosticPolicyTests passed")
    }
}
