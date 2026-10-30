import Foundation

@main struct SceneGroupPayloadTests {
    static func main() throws {
        let lc = LightLCProperty()
        lc.mode = true; lc.lightnessOn = 2345; lc.timeFade = 9876
        lc.regulatorKiu = 1.25; lc.manualOverrideTimeout = UInt32.max
        let group = SceneExecuteData(sceneNumber: 7, isOn: false, lightness: 12345, cct: 5678, lightControlData: lc)
        group.hue = 222; group.saturation = 333; group.state = .waitDelete
        let data = try JSONEncoder().encode([group])
        let original = try JSONSerialization.jsonObject(with: data)
        let imported = try JSONDecoder().decode([SceneExecuteData].self, from: data)
        let after = try JSONSerialization.jsonObject(with: JSONEncoder().encode(imported))
        let first = try JSONSerialization.data(withJSONObject: SceneConfigurationPayload.groupParameters(original), options: .sortedKeys)
        let second = try JSONSerialization.data(withJSONObject: SceneConfigurationPayload.groupParameters(after), options: .sortedKeys)
        precondition(first == second, "SDK legacy LC defaults must not cause import/readback conflicts")
        precondition(imported[0].lightness == 12345 && imported[0].hue == 222 && imported[0].saturation == 333)
        precondition(imported[0].lightControlData?.regulatorKiu == 1.25 && imported[0].lightControlData?.manualOverrideTimeout == UInt32.max)
        print("PASS: actual SDK group codec preserves raw HSL/LC parameters, cleanup state and unit values")
    }
}
