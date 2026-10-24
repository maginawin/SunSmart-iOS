import Foundation

@main
enum HDBDevicePreparationTests {
    static func main() throws {
        let expected = Data([1, 0, 1, 0xC0, 0x0F, 0x13])
        precondition(HDBDevicePreparationPolicy.matchesConfigurationStatus(request: expected, response: Data([0]) + expected, successful: true))
        precondition(!HDBDevicePreparationPolicy.matchesConfigurationStatus(request: expected, response: Data([0, 9]) + expected, successful: true))
        precondition(!HDBDevicePreparationPolicy.matchesConfigurationStatus(request: expected, response: Data([1]) + expected, successful: false))
        precondition(!HDBDevicePreparationPolicy.matchesConfigurationStatus(request: nil, response: nil, successful: true))

        let id = UUID()
        let models: [HDBModelTarget] = [0x130F, 0x1310, 0x1000, 0x1300].map {
            .init(elementAddress: 10, modelIdentifier: UInt16($0), companyIdentifier: nil)
        } + [.init(elementAddress: 10, modelIdentifier: 1, companyIdentifier: 0x0A78)]
        let sensor = HDBModelTarget(elementAddress: 12, modelIdentifier: 0x1100, companyIdentifier: nil)
        let plan = try HDBDevicePreparationPolicy.plan(nodeUuid: id, nodeAddress: 10,
            appKeyIndex: 1, targets: models + [sensor], sensorGroupId: 0xC080,
            publicationTargets: [sensor, sensor], sensorPublication: [.init(elementAddress: 10)])
        precondition(plan.publicationTargets == [sensor])
        precondition(plan.publicationAddress == 10)
        let primarySensor = HDBModelTarget(elementAddress: 10, modelIdentifier: 0x1100, companyIdentifier: nil)
        let middleSensor = HDBModelTarget(elementAddress: 11, modelIdentifier: 0x1100, companyIdentifier: nil)
        let vendorSensor = HDBModelTarget(elementAddress: 10, modelIdentifier: 0x1100, companyIdentifier: 0x0A78)
        let multiSensor = try HDBDevicePreparationPolicy.plan(nodeUuid: id, nodeAddress: 10,
            appKeyIndex: 1, targets: models + [sensor, primarySensor, middleSensor, sensor, vendorSensor],
            sensorGroupId: 0xC080, publicationTargets: [primarySensor], sensorPublication: [.init(elementAddress: 10)])
        precondition(multiSensor.publicationAddress == 10)
        precondition(multiSensor.publicationTargets == [primarySensor])
        let signature = try HDBDevicePreparationPolicy.signature(plan, deviceKey: Data([1]), createdTimestamp: 1)
        let same = try HDBDevicePreparationPolicy.signature(plan, deviceKey: Data([1]), createdTimestamp: 1)
        precondition(signature == same)
        var replacement = plan; replacement.appKeyIndex = 2
        let variants = [
            try HDBDevicePreparationPolicy.signature(replacement, deviceKey: Data([1]), createdTimestamp: 1),
            try HDBDevicePreparationPolicy.signature(plan, deviceKey: Data([2]), createdTimestamp: 1),
            try HDBDevicePreparationPolicy.signature(plan, deviceKey: Data([1]), createdTimestamp: 2)
        ]
        precondition(variants.allSatisfy { $0 != signature })
        let noSensor = try HDBDevicePreparationPolicy.plan(nodeUuid: id, nodeAddress: 10,
            appKeyIndex: 1, targets: models, sensorGroupId: nil, publicationTargets: [], sensorPublication: [.init(elementAddress: nil)])
        precondition(noSensor.publicationAddress == nil && noSensor.publicationTargets.isEmpty)
        precondition(noSensor.baseTargets.filter { $0.value != nil }.count == 3)
        let unidentifiedSensor = try HDBDevicePreparationPolicy.plan(nodeUuid: id, nodeAddress: 10,
            appKeyIndex: 1, targets: models + [sensor], sensorGroupId: 0xC080, publicationTargets: [], sensorPublication: [.init(elementAddress: 10)])
        precondition(unidentifiedSensor.publicationTargets.isEmpty && unidentifiedSensor.publicationAddress == 10)
        let unallocated = try HDBDevicePreparationPolicy.plan(nodeUuid: id, nodeAddress: 10,
            appKeyIndex: 1, targets: models + [sensor], sensorGroupId: nil,
            publicationTargets: [sensor], sensorPublication: [.init(elementAddress: nil)])
        precondition(unallocated.publicationTargets.isEmpty && unallocated.publicationAddress == nil)
        let noLC = try HDBDevicePreparationPolicy.plan(nodeUuid: id, nodeAddress: 10,
            appKeyIndex: 1, targets: [sensor], sensorGroupId: 0xC080,
            publicationTargets: [sensor], sensorPublication: [.init(elementAddress: nil)])
        precondition(noLC.publicationTargets.isEmpty && noLC.sensorGroupId == 0xC080)
        for destination: UInt16 in [12, 0xC080, 0x1234] {
            do {
                _ = try HDBDevicePreparationPolicy.plan(nodeUuid: id, nodeAddress: 10,
                    appKeyIndex: 1, targets: models + [sensor], sensorGroupId: 0xC080,
                    publicationTargets: [sensor], sensorPublication: [.init(elementAddress: destination)])
                preconditionFailure("Wrong LC destination accepted")
            } catch HDBConfigurationError.invalidData { }
        }
        let secondLC = HDBModelTarget(elementAddress: 14, modelIdentifier: 0x130F, companyIdentifier: nil)
        do {
            _ = try HDBSensorPublication.expected(sensorGroupId: 0xC080, models: models + [secondLC])
            preconditionFailure("Ambiguous LC silently selected")
        } catch HDBConfigurationError.unsupportedModels { }
        var config = HDBConfiguration()
        var device = HDBDeviceConfiguration(nodeUuid: id, nodeAddress: 10, mac: "AA:BB:CC:DD:EE:FF")
        device.sensorGroupId = 0xC080
        config.devices = [device]
        try HDBLightingZonePolicy.validate(config)
        precondition(config.allGroupAddresses == [0xC080])
        var duplicate = device; duplicate.nodeUuid = UUID(); duplicate.nodeAddress = 20
        config.devices.append(duplicate)
        do { try HDBLightingZonePolicy.validate(config); fatalError("duplicate sensor address accepted") }
        catch HDBConfigurationError.invalidData {}
        print("PASS: HDB preparation dependencies, deduplication, initialization identity and unique sensor address ownership")
    }
}
