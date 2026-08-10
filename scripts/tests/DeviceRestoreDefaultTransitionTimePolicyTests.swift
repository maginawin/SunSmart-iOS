@main
struct DeviceRestoreDefaultTransitionTimePolicyTests {
    private struct TestCase {
        let name: String
        let restoreTargetRawValue: UInt8?
        let currentRawValue: UInt8?
        let isSupported: Bool
        let expectedRawValue: UInt8?
    }

    static func main() {
        let cases = [
            TestCase(
                name: "supported mismatch restores 3 seconds",
                restoreTargetRawValue: 0x1E,
                currentRawValue: 0x0A,
                isSupported: true,
                expectedRawValue: 0x1E
            ),
            TestCase(
                name: "supported unknown current restores target",
                restoreTargetRawValue: 0x1E,
                currentRawValue: nil,
                isSupported: true,
                expectedRawValue: 0x1E
            ),
            TestCase(
                name: "equal values do not need restore",
                restoreTargetRawValue: 0x1E,
                currentRawValue: 0x1E,
                isSupported: true,
                expectedRawValue: nil
            ),
            TestCase(
                name: "missing restore target does not sync",
                restoreTargetRawValue: nil,
                currentRawValue: 0x0A,
                isSupported: true,
                expectedRawValue: nil
            ),
            TestCase(
                name: "unsupported mismatch does not sync",
                restoreTargetRawValue: 0x1E,
                currentRawValue: 0x0A,
                isSupported: false,
                expectedRawValue: nil
            ),
            TestCase(
                name: "unsupported unknown current does not sync",
                restoreTargetRawValue: 0x1E,
                currentRawValue: nil,
                isSupported: false,
                expectedRawValue: nil
            ),
            TestCase(
                name: "zero raw target is preserved",
                restoreTargetRawValue: 0x00,
                currentRawValue: 0x0A,
                isSupported: true,
                expectedRawValue: 0x00
            ),
            TestCase(
                name: "unknown hundred-millisecond target does not sync",
                restoreTargetRawValue: 0x3F,
                currentRawValue: 0x0A,
                isSupported: true,
                expectedRawValue: nil
            ),
            TestCase(
                name: "unknown second target does not sync",
                restoreTargetRawValue: 0x7F,
                currentRawValue: 0x0A,
                isSupported: true,
                expectedRawValue: nil
            ),
            TestCase(
                name: "unknown ten-second target does not sync",
                restoreTargetRawValue: 0xBF,
                currentRawValue: 0x0A,
                isSupported: true,
                expectedRawValue: nil
            ),
            TestCase(
                name: "unknown ten-minute target does not sync",
                restoreTargetRawValue: 0xFF,
                currentRawValue: 0x0A,
                isSupported: true,
                expectedRawValue: nil
            ),
        ]

        for testCase in cases {
            let actualRawValue = DeviceRestoreDefaultTransitionTimePolicy.pendingTargetRawValue(
                restoreTargetRawValue: testCase.restoreTargetRawValue,
                currentRawValue: testCase.currentRawValue,
                isSupported: testCase.isSupported
            )
            guard actualRawValue == testCase.expectedRawValue else {
                fatalError(
                    "\(testCase.name): expected \(String(describing: testCase.expectedRawValue)), "
                        + "got \(String(describing: actualRawValue))"
                )
            }
        }

        let cleanupCases: [(String, UInt8?, UInt8, Bool)] = [
            ("matching successful SET clears restore target", 0x1E, 0x1E, true),
            ("different successful SET preserves restore target", 0x1E, 0x0A, false),
            ("missing restore target is not cleared", nil, 0x1E, false),
        ]

        for (name, restoreTargetRawValue, successfulSetRawValue, expected) in cleanupCases {
            let actual = DeviceRestoreDefaultTransitionTimePolicy.shouldClearRestoreTarget(
                restoreTargetRawValue: restoreTargetRawValue,
                successfulSetRawValue: successfulSetRawValue
            )
            guard actual == expected else {
                fatalError("\(name): expected \(expected), got \(actual)")
            }
        }

        print("PASS: \(cases.count) default transition time pending-target cases")
        print("PASS: \(cleanupCases.count) default transition time cleanup cases")
    }
}
