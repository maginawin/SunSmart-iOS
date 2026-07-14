import Foundation

@main
struct FirmwareVersionUpdatePolicyTests {
    static func main() {
        let cases: [(String?, String?, FirmwareVersionUpdateEligibility)] = [
            ("1.2.3", "2.0.0", .allowed),
            ("1.2.3.8", "2.0.0.1", .allowed),
            ("1.2.3", "1.3.0", .allowed),
            ("1.2.3", "1.2.4", .allowed),
            ("2.0.0", "1.9.9.100", .disallowed),
            ("1.2.3", "1.2.3", .disallowed),
            ("1.2.3", "1.2.3.4", .disallowed),
            ("1.2.3.4", "1.2.3", .allowed),
            ("1.2.3.4", "1.2.3.4", .disallowed),
            ("1.2.3.4", "1.2.3.5", .allowed),
            ("1.2.3.10", "1.2.3.9", .allowed),
            ("1.2.3.9", "1.2.3.10", .allowed),
            (nil, "1.2.3", .invalid),
            ("1.2.3", nil, .invalid),
            ("", "1.2.3", .invalid),
            ("1.2", "1.2.3", .invalid),
            ("1.2.3.4.5", "1.2.3", .invalid),
            ("1.a.3", "1.2.3", .invalid),
            ("1.2.3.", "1.2.3", .invalid)
        ]

        for testCase in cases {
            let actual = FirmwareVersionUpdatePolicy.bleBatchAware.eligibility(
                currentVersion: testCase.0,
                targetVersion: testCase.1
            )
            precondition(
                actual == testCase.2,
                "Unexpected result for \(String(describing: testCase.0)) -> \(String(describing: testCase.1)): \(actual)"
            )
        }

        precondition(
            FirmwareVersionUpdatePolicy.numeric.eligibility(
                currentVersion: "1.2.3",
                targetVersion: "1.2.4"
            ) == .allowed
        )
        precondition(
            FirmwareVersionUpdatePolicy.numeric.eligibility(
                currentVersion: "1.2.4",
                targetVersion: "1.2.3"
            ) == .disallowed
        )
        precondition(
            FirmwareVersionUpdatePolicy.bleBatchAware.isCurrentVersionUpToDate(
                currentVersion: "1.2.3",
                targetVersion: "1.2.3.4"
            )
        )
        precondition(
            !FirmwareVersionUpdatePolicy.bleBatchAware.isCurrentVersionUpToDate(
                currentVersion: "1.2.3.4",
                targetVersion: "1.2.3.5"
            )
        )
        precondition(
            !FirmwareVersionUpdatePolicy.bleBatchAware.isCurrentVersionUpToDate(
                currentVersion: nil,
                targetVersion: "1.2.3"
            )
        )

        print("FirmwareVersionUpdatePolicyTests passed")
    }
}
