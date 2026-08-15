import Foundation

@main
struct SiteGatewayCloudTimeZoneResponseParserTests {

    static func main() {
        testParsesPositiveRequestIDsAcrossSupportedIntegerRepresentations()
        testRejectsInvalidRequestIDs()
        testParsesAndNormalizesKnownGatewayStatuses()
        testIgnoresUnknownOrMalformedGatewayStatusEntries()
        testDistinguishesMalformedStatusDataFromAnEmptyStatusArray()
        print("SiteGatewayCloudTimeZoneResponseParserTests passed")
    }

    private static func testParsesPositiveRequestIDsAcrossSupportedIntegerRepresentations() {
        let cases: [(Any, Int64)] = [
            (42, 42),
            (Int64.max, Int64.max),
            (NSNumber(value: 73), 73),
            (" 9223372036854775807 ", Int64.max)
        ]

        for (rawValue, expected) in cases {
            let response: [String: Any] = ["data": ["requestId": rawValue]]
            require(
                SiteGatewayCloudTimeZoneResponseParser.parseRequestID(from: response) == expected,
                "A positive integer requestId must parse without changing its value"
            )
        }
    }

    private static func testRejectsInvalidRequestIDs() {
        let invalidValues: [Any] = [
            true,
            0,
            -1,
            1.5,
            NSNumber(value: 2.5),
            "",
            "   ",
            "1.5",
            "9223372036854775808",
            "-1"
        ]

        for rawValue in invalidValues {
            let response: [String: Any] = ["data": ["requestId": rawValue]]
            require(
                SiteGatewayCloudTimeZoneResponseParser.parseRequestID(from: response) == nil,
                "Bool, non-positive, fractional, empty, and overflowing requestId values must be rejected"
            )
        }

        require(
            SiteGatewayCloudTimeZoneResponseParser.parseRequestID(from: [:]) == nil,
            "A missing data.requestId must be rejected"
        )
        require(
            SiteGatewayCloudTimeZoneResponseParser.parseRequestID(from: ["data": [:]]) == nil,
            "An omitted requestId inside data must be rejected"
        )
    }

    private static func testParsesAndNormalizesKnownGatewayStatuses() {
        let response: [String: Any] = [
            "data": [
                [" EF725643A2B9 ": " requested "],
                ["ef725643a2b9": "SUCCEED", " AA:BB ": " Failed "],
                ["aa:bb": "expired"]
            ]
        ]

        let snapshots = SiteGatewayCloudTimeZoneResponseParser.parseStatuses(from: response)

        require(
            snapshots == [
                .init(id: "ef725643a2b9", statuses: [.requested, .succeed]),
                .init(id: "aa:bb", statuses: [.failed, .expired])
            ],
            "Trimmed, case-insensitive MAC/status values must coalesce into their known status sets"
        )
    }

    private static func testIgnoresUnknownOrMalformedGatewayStatusEntries() {
        let response: [String: Any] = [
            "data": [
                ["valid": "Succeed", "unknown": "waiting", "nil": " NIL "],
                ["null": NSNull(), "number": 1, "empty": "   "],
                ["   ": "failed"],
                "not a dictionary"
            ]
        ]

        require(
            SiteGatewayCloudTimeZoneResponseParser.parseStatuses(from: response) == [
                .init(id: "valid", statuses: [.succeed])
            ],
            "Only non-empty MACs with the four known string statuses may produce snapshots"
        )
    }

    private static func testDistinguishesMalformedStatusDataFromAnEmptyStatusArray() {
        require(
            SiteGatewayCloudTimeZoneResponseParser.parseStatuses(from: ["data": [:]]) == nil,
            "A non-array data value must be rejected as malformed"
        )
        require(
            SiteGatewayCloudTimeZoneResponseParser.parseStatuses(from: ["data": []]) == [],
            "A valid empty data array must remain an empty result"
        )
    }
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fatalError(message)
    }
}
