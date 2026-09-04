import Foundation

@main
struct EnergyStatisticsFilterPolicyTests {

    private struct Sample {
        let name: String
        let meteringType: EnergyMeteringType
    }

    static func main() {
        testKnownTruePowerMeterProducts()
        testMeteringTypeOverrides()
        testExclusiveFilters()
        print("PASS: Energy statistics filter policy tests.")
    }

    private static func testKnownTruePowerMeterProducts() {
        let productIdentifiers: [UInt16] = [
            0x2302, 0x2303, 0x2304, 0x2305, 0x2801, 0x2802
        ]
        for productIdentifier in productIdentifiers {
            require(
                EnergyStatisticsFilterPolicy.supportsTruePowerMeter(
                    productIdentifier: productIdentifier
                ),
                String(format: "Product 0x%04X must support true power metering", productIdentifier)
            )
        }
        require(
            !EnergyStatisticsFilterPolicy.supportsTruePowerMeter(productIdentifier: 0x2502),
            "Manual-rated-power product was classified as a true power meter"
        )
        require(
            !EnergyStatisticsFilterPolicy.supportsTruePowerMeter(productIdentifier: nil),
            "Missing Product ID was classified as a true power meter"
        )
    }

    private static func testMeteringTypeOverrides() {
        require(
            EnergyStatisticsFilterPolicy.meteringType(
                productIdentifier: 0x2304,
                supportsTruePowerMeter: false
            ) == .manualDataEntry,
            "Live node capability must override Product ID fallback"
        )
        require(
            EnergyStatisticsFilterPolicy.meteringType(
                productIdentifier: 0x2502,
                supportsTruePowerMeter: true
            ) == .truePowerMeter,
            "Live node capability override was ignored"
        )
    }

    private static func testExclusiveFilters() {
        let samples = [
            Sample(name: "L12", meteringType: .truePowerMeter),
            Sample(name: "Manual light", meteringType: .manualDataEntry)
        ]

        let all = filteredNames(samples, by: .all)
        let truePower = filteredNames(samples, by: .truePowerMeter)
        let manual = filteredNames(samples, by: .manualDataEntry)

        require(all == ["L12", "Manual light"], "All filter changed the snapshot")
        require(truePower == ["L12"], "True power filter did not keep only true meters")
        require(manual == ["Manual light"], "Manual filter overlapped true meters")
    }

    private static func filteredNames(
        _ samples: [Sample],
        by filter: EnergyStatisticsFilter
    ) -> [String] {
        EnergyStatisticsFilterPolicy.filter(
            samples,
            by: filter,
            meteringType: { $0.meteringType }
        ).map(\.name)
    }

    private static func require(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) {
        guard condition() else {
            fatalError(message)
        }
    }
}
