import Foundation

@main enum HDBLightingConfigurationTests {
    static func main() throws {
        func check(_ condition: @autoclosure () throws -> Bool) rethrows { let result = try condition(); precondition(result) }
        let id = UUID()
        let targets = [HDBModelTarget(elementAddress: 1, modelIdentifier: 0x1300, companyIdentifier: nil),
                       HDBModelTarget(elementAddress: 1, modelIdentifier: 0x1000, companyIdentifier: nil),
                       HDBModelTarget(elementAddress: 2, modelIdentifier: 0x130F, companyIdentifier: nil),
                       HDBModelTarget(elementAddress: 2, modelIdentifier: 0x1310, companyIdentifier: nil),
                       HDBModelTarget(elementAddress: 1, modelIdentifier: 1, companyIdentifier: 0x0A78)]
        let recipient = HDBLightingRecipient(nodeUuid: id, nodeAddress: 1, targets: targets)
        let values = HDBLightingValues.defaults
        let intensity = try HDBLightingConfigurationPolicy.writes(.intensity, values: values)
        precondition(intensity == [.property(0x002F, 13107), .property(0x002E, 52428)])
        try check(try HDBLightingConfigurationPolicy.writes(.override, values: .init(lightingControl: .auto)) == [.auto])
        try check(try HDBLightingConfigurationPolicy.writes(.override, values: .init(lightingControl: .forceOff)) == [.off])
        try check(try HDBLightingConfigurationPolicy.writes(.override, values: .init(lightingControl: .forceOn)) == [.lightness(65535)])
        try check(try HDBLightingConfigurationPolicy.writes(.override, values: .init(failsafeDelay: 0)).isEmpty)
        let deliveries = try HDBLightingConfigurationPolicy.route([.lightness(65535)] + intensity, recipient: recipient)
        precondition(deliveries.map(\.address) == [1, 2, 2])
        precondition(deliveries.allSatisfy { $0.nodeUuid == id && $0.target.elementAddress == $0.address })
        let secondaryOnOff = HDBModelTarget(elementAddress: 2, modelIdentifier: 0x1000, companyIdentifier: nil)
        let dualOnOff = HDBLightingRecipient(nodeUuid: id, nodeAddress: 1, targets: targets + [secondaryOnOff])
        let off = try HDBLightingConfigurationPolicy.route([.off], recipient: dualOnOff)
        precondition(off.map(\.address) == [1], "Force Off must only target the primary OnOff")
        let secondaryOnly = HDBLightingRecipient(nodeUuid: id, nodeAddress: 1,
            targets: dualOnOff.targets.filter { !($0.elementAddress == 1 && $0.modelIdentifier == 0x1000) })
        do {
            _ = try HDBLightingConfigurationPolicy.route([.off], recipient: secondaryOnly)
            fatalError("Force Off must not fall back to a secondary OnOff")
        } catch HDBConfigurationError.unsupportedModels {}
        let multiLightness = HDBLightingRecipient(nodeUuid: id, nodeAddress: 1,
            targets: dualOnOff.targets + [.init(elementAddress: 2, modelIdentifier: 0x1300, companyIdentifier: nil)])
        let forceOn = try HDBLightingConfigurationPolicy.route([.lightness(65535)], recipient: multiLightness)
        precondition(forceOn.map(\.address) == [1, 2], "Force On must retain secondary delivery")
        var device = HDBDeviceConfiguration(nodeUuid: id, nodeAddress: 1, mac: "AA:BB:CC:DD:EE:FF", lightingZones: [.init(zoneId: 1)])
        device.zoneModels = HDBLightingZonePolicy.zoneTargets(from: targets, primaryAddress: 1).map(HDBModelReference.init)
        device.sensorGroupModels = HDBLightingZonePolicy.sensorGroupTargets(from: targets).map(HDBModelReference.init)
        device.lightingConfiguration = .init(values: .init(holdTime: 120))
        var config = HDBConfiguration(lightingZones: [.init(zoneId: 1, name: "A", groupAddress: 0xC001), .init(zoneId: 2, name: "B", groupAddress: 0xC002)], devices: [device])
        try HDBLightingConfigurationPolicy.record(nodeUuid: id, command: .intensity, values: values, status: .synced, in: &config)
        precondition(config.devices[0].lightingConfiguration?.values.holdTime == 120)
        precondition(config.devices[0].lightingConfiguration?.values.brightIntensity == 80)
        let changed = try HDBLightingZonePolicy.replacingZones([2], for: device, in: config)
        precondition(changed.devices[0].lightingConfiguration == config.devices[0].lightingConfiguration)
        let unprepared = changed
        let subscriptions = try HDBLightingZonePolicy.operations(for: unprepared.devices[0], in: unprepared, targets: targets)
        precondition(subscriptions.count == 2 && subscriptions[0].stage == .reset && subscriptions[1].stage == .add,
                     "subscription planning must not implicitly generate HDB preparation")
        try HDBLightingConfigurationPolicy.record(nodeUuid: id, command: .override, values: .init(lightingControl: .forceOn), status: .pending, in: &config)
        let failedControl = config.devices[0].lightingConfiguration?.lightingControl
        precondition(failedControl?.status == .pending)
        try HDBLightingConfigurationPolicy.record(nodeUuid: id, command: .override, values: .init(failsafeDelay: 5), status: .synced, in: &config)
        precondition(config.devices[0].lightingConfiguration?.lightingControl == failedControl, "metadata-only must not clear failed control")
        let other = UUID()
        config.devices.append(.init(nodeUuid: other, nodeAddress: 10, mac: "AA:BB:CC:DD:EE:FF"))
        let otherBefore = config.devices[1]
        let zonesBefore = config.lightingZones
        try HDBLightingConfigurationPolicy.record(nodeUuid: id, command: .intensity, values: .init(brightIntensity: 100), status: .pending, in: &config)
        precondition(config.devices[0].lightingConfiguration?.brightIntensity?.value == 100 && config.devices[0].lightingConfiguration?.brightIntensity?.status == .pending)
        precondition(config.devices[1] == otherBefore && config.lightingZones == zonesBefore)
        precondition(config.devices[0].lightingConfiguration?.values.holdTime == 120)
        let roundtrip = try JSONDecoder().decode(HDBConfiguration.self, from: JSONEncoder().encode(config))
        precondition(roundtrip == config)
        for invalid in [HDBLightingValues(dimIntensity: 51), .init(failsafeDelay: -1), .init(installDate: "31-02-2026")] {
            do { try invalid.validate(); fatalError("invalid values accepted") } catch HDBConfigurationError.invalidData {}
        }
        print("PASS: selective commands, metadata zero, unicast primary/secondary targets, independent persistence, two statuses, field patches and round trip")
    }
}
