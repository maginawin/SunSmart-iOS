// Protocol and SDK types are boundaries; generation, success predicate, retry
// and Session transport come from production source.
enum OnPowerUp { case off, restore, `default` }
enum RestorePowerState { case off, restore, definedLightLevel(UInt16) }
struct GenericOnPowerUpSet { let state: OnPowerUp }
struct LightCTLDefaultSet { let lightness: UInt16, temperature: UInt16; let deltaUV: Int }
struct LightLightnessDefaultSet { let lightness: UInt16 }
enum RestoreProfile {
    case powerOnState(state: RestorePowerState, cct: UInt16? = nil)
    func targetPowerUpCct(for node: Node) -> UInt16? { nil }
    func getMessageHandles(node: Node) -> [MeshMessageHandle] {
        var messageHandles: [MeshMessageHandle] = []
        // POWER_UP_FACTORY
        return messageHandles
    }
    func isSuccessful(node: Node) -> Bool {
        switch self {
        // POWER_UP_RESULT
        }
    }
}
extension Node {
    static func getLightness(lightness100: Int) -> UInt16 { UInt16(lightness100) }
    var lightnessSetupModel: TestVendorModel? { TestVendorModel() }
    var powerOnOffSetupModel: TestVendorModel? { TestVendorModel() }
    var ctlSetupModel: TestVendorModel? { nil }
    var effectiveSupportCct: Bool { false }
    var defalutLightness: UInt16 { 0 }
    var defaultCct: UInt16 { 3000 }
    func clampEffectiveCct(_ cct: UInt16) -> UInt16 { cct }
    var restoreHandles: [MeshMessageHandle] { RestoreProfile.powerOnState(state: .restore).getMessageHandles(node: self) }
}
