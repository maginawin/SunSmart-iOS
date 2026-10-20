import Foundation

// The script includes production preparation/Auto messages, HDB matching, and
// mapped SDK Set encoders and Vendor response parsing.
struct LightLCPropertyStatus: MeshMessage { var parameters: Data? }
struct LightLCModeStatus: MeshMessage { var parameters: Data? }
struct LightLCOccupancyModeStatus: MeshMessage { var parameters: Data? }
struct LightLCLightOnOffStatus: MeshMessage { var parameters: Data?; var targetState: Bool?; var isOn: Bool }
struct GenericOnOffSet: AcknowledgedMeshMessage { var parameters: Data? = nil; var isOn: Bool; init(_ on: Bool) { isOn = on } }
struct GenericOnOffSetUnacknowledged: MeshMessage { var parameters: Data? = nil; var isOn: Bool; init(_ on: Bool) { isOn = on } }
struct GenericOnOffStatus: MeshMessage { var parameters: Data?; var targetState: Bool?; var isOn: Bool }
struct LightLightnessSet: AcknowledgedMeshMessage { var parameters: Data? = nil; var lightness: UInt16 }
struct LightLightnessSetUnacknowledged: MeshMessage { var parameters: Data? = nil; var lightness: UInt16 }
struct LightLightnessStatus: MeshMessage { var parameters: Data?; var targetLightness: UInt16?; var lightness: UInt16 }

@main enum HDBLightingMessagesTests {
    static func main() throws {
        testAutoUsesSavedRampUp()
        try testPreparationValues()
        let manual = SunricherVendorSet(function: .manualControlEnabled(enabled: false))
        let captured = SunricherVendorStatus(parameters: Data([0x33, 0, 0]))!
        precondition(captured.status.isSuccessful && captured.status.parameters == nil)
        precondition(HDBLightingMessages.matches(manual, response: captured),
                     "captured successful 33 00 00 must not fail preparation")

        let cases: [(VendorFunctionSet, [UInt8])] = [
            (.manualControlEnabled(enabled: false), [0x33, 0]),
            (.manualControlEnabled(enabled: true), [0x33, 1]),
            (.lightAutoAdjustEnabled(enabled: false), [0x34, 0]),
            (.lightAutoAdjustEnabled(enabled: true), [0x34, 1]),
            (.manualOverrideTimeout(enabled: true, state: .standby, interval: .max),
             [0x32, 1, 0, 0xFF, 0xFF, 0xFF, 0xFF]),
            (.manualOverrideTimeout(enabled: false, state: .prolong, interval: 30_000),
             [0x32, 0, 2, 0x30, 0x75, 0, 0])
        ]
        for (function, encoded) in cases {
            let request = SunricherVendorSet(function: function)
            precondition(request.parameters == Data(encoded))
            let code = encoded[0]
            expect(request, [code, 0, 0], true, "short success ACK")
            let echo = [code, 0, 0] + encoded.dropFirst()
            expect(request, echo, true, "matching echo")
            for offset in 3..<echo.count {
                var changed = echo
                changed[offset] ^= 1
                expect(request, changed, false, "mismatched echo field at \(offset)")
            }
            expect(request, echo + [0], false, "trailing bytes")
            expect(request, [code, 1, 0], false, "unexpected subcode")
            var wrongSubcodeEcho = echo
            wrongSubcodeEcho[1] = 1
            expect(request, wrongSubcodeEcho, false, "unexpected subcode with echo")
            for error in [UInt8(1), 2, 0xFF] {
                expect(request, [code, 0, error], false, "device error")
            }
            for otherCode: UInt8 in [0x32, 0x33, 0x34, 0x35] where otherCode != code {
                expect(request, [otherCode, 0, 0], false, "wrong command")
            }
            for length in 0..<3 {
                precondition(SunricherVendorStatus(parameters: Data([code, 0, 0].prefix(length))) == nil)
            }
        }
        // The SDK normalizes nonzero boolean bytes and unknown override states.
        // A full echo must still exactly match the requested protocol values.
        expect(.init(function: .manualControlEnabled(enabled: true)), [0x33, 0, 0, 2], false, "invalid boolean")
        let timeout = SunricherVendorSet(function: .manualOverrideTimeout(enabled: true, state: .standby, interval: .max))
        expect(timeout, [0x32, 0, 0, 1, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF], false, "invalid state")
        for length in 4..<9 {
            // The existing SDK decoder reads a six-byte timeout echo without
            // checking its full length. Inject malformed raw bytes after a
            // valid decode to test the HDB boundary without hiding that SDK
            // limitation or claiming it safely decodes truncated wire packets.
            var truncated = SunricherVendorStatus(parameters: Data([0x32, 0, 0]))!
            truncated.parameters = Data([UInt8(0x32), 0, 0, 1, 0, 0xFF, 0xFF, 0xFF, 0xFF].prefix(length))
            precondition(!HDBLightingMessages.matches(timeout, response: truncated), "truncated timeout echo")
        }
        expect(.init(function: .lightControlEnabled(enabled: true)), [0x35, 0, 0], false, "unsupported short ACK")
        precondition(!HDBLightingMessages.matches(manual, response: GenericOnOffStatus(parameters: Data([0]), targetState: nil, isOn: false)))
        print("PASS: captured Vendor ACK; 0x32/33/34 short and echoed success; wrong command/subcode/value, device errors, malformed lengths")
    }

    static func testAutoUsesSavedRampUp() {
        var acknowledged = HDBLightingMessages.message(.auto) as! LightLCLightOnOffSet
        var unacknowledged = LightLCLightOnOffSetUnacknowledged(true)
        acknowledged.tid = 0x42
        unacknowledged.tid = 0x43
        precondition(LightLCLightOnOffSet.opCode == 0x829A && LightLCLightOnOffSetUnacknowledged.opCode == 0x829B)
        precondition(acknowledged.parameters == Data([1, 0x42]) && unacknowledged.parameters == Data([1, 0x43]),
                     "Auto must omit transition fields so firmware uses saved RampUp")
        precondition(acknowledged.transitionTime == nil && acknowledged.delay == nil)
        precondition(unacknowledged.transitionTime == nil && unacknowledged.delay == nil)
        print("PASS: production Auto uses mapped SDK encoders with only On and TID for acknowledged/unacknowledged messages")
    }

    static func testPreparationValues() throws {
        let models = [
            HDBModelTarget(elementAddress: 26, modelIdentifier: 1, companyIdentifier: 0x0A78),
            .init(elementAddress: 26, modelIdentifier: 0x1000, companyIdentifier: nil),
            .init(elementAddress: 26, modelIdentifier: 0x1300, companyIdentifier: nil),
            .init(elementAddress: 28, modelIdentifier: 0x130F, companyIdentifier: nil),
            .init(elementAddress: 28, modelIdentifier: 0x1310, companyIdentifier: nil)
        ]
        let defaults = models.map { HDBPreparationTarget(model: $0) }
        let writes = try HDBLightingMessages.preparation(defaults)
        let expected: [[UInt8]] = [
            [0x33, 0], [0x34, 0], [0x32, 1, 0, 0xFF, 0xFF, 0xFF, 0xFF],
            [1], [0x3B, 0, 0xFE, 0xFF, 0xFF], [1]
        ]
        precondition(writes.map { Array($0.1.parameters!) } == expected)
        precondition(writes.map { $0.0.elementAddress } == [26, 26, 26, 28, 28, 28])
        precondition(writes.map { $0.0.modelId } == [0x0A780001, 0x0A780001, 0x0A780001, 0x130F, 0x1310, 0x130F])
        precondition(writes.last!.1 is LightLCModeSet)
        let secondaryVendor = HDBPreparationTarget(model: .init(elementAddress: 29, modelIdentifier: 1, companyIdentifier: 0x0A78))
        let withSecondaryVendor = try HDBLightingMessages.preparation(defaults + [secondaryVendor])
        precondition(withSecondaryVendor.filter { $0.0 == secondaryVendor.model }.map { Array($0.1.parameters!) } == Array(expected.prefix(3)),
                     "Primary-only Zone filtering must not remove secondary Vendor initialization")
        // Nondefault values must survive persistence and drive every emitted field.
        var changed = defaults
        changed[0].value = .vendor(.init(manualControlEnabled: true, lightAutoAdjustEnabled: true,
            manualOverrideTimeout: .init(enabled: false, state: .prolong, intervalMilliseconds: 30_000)))
        changed[3].value = .lc(.init(occupancyMode: false, mode: false))
        changed[4].value = .lcSetup(.init(prolongTimeMilliseconds: 123_456))
        let restored = try JSONDecoder().decode([HDBPreparationTarget].self, from: JSONEncoder().encode(changed))
        let changedWrites = try HDBLightingMessages.preparation(restored)
        let changedExpected: [[UInt8]] = [
            [0x33, 1], [0x34, 1], [0x32, 0, 2, 0x30, 0x75, 0, 0],
            [0], [0x3B, 0, 0x40, 0xE2, 1], [0]
        ]
        precondition(changedWrites.map { Array($0.1.parameters!) } == changedExpected)
        precondition(changedWrites.map(\.0) == writes.map(\.0))
        var secondLC = HDBPreparationTarget(model: .init(elementAddress: 29, modelIdentifier: 0x130F, companyIdentifier: nil))
        secondLC.value = .lc(.init(occupancyMode: true, mode: false))
        let multiple = try HDBLightingMessages.preparation([secondLC] + defaults)
        precondition(multiple.count == 8)
        precondition(multiple.suffix(2).allSatisfy { $0.1 is LightLCModeSet })
        precondition(multiple.suffix(2).map { $0.0.elementAddress } == [29, 28])
        for badValue: HDBPreparationValue? in [nil, .lcSetup(.init(prolongTimeMilliseconds: 1))] {
            var invalid = defaults
            invalid[3].value = badValue
            do { _ = try HDBLightingMessages.preparation(invalid); fatalError("invalid preparation encoded") }
            catch HDBConfigurationError.invalidData {}
        }
        print("PASS: preparation JSON values drive all six messages, defaults preserved, all LC modes last, identities unchanged")
    }

    static func expect(_ request: SunricherVendorSet, _ bytes: [UInt8], _ accepted: Bool, _ reason: String) {
        guard let response = SunricherVendorStatus(parameters: Data(bytes)) else {
            precondition(!accepted, "SDK rejected \(reason)")
            return
        }
        precondition(HDBLightingMessages.matches(request, response: response) == accepted, reason)
    }
}
