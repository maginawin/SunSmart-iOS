import Foundation

struct LightingTestMessage: AcknowledgedMeshMessage {
    var write: HDBLightingWrite?
    var parameters: Data { Data(String(describing: write).utf8) }
}
struct LightLCModeGet: AcknowledgedMeshMessage { var parameters = Data() }
struct LightLCLightOnOffGet: AcknowledgedMeshMessage { var parameters = Data() }
struct LightLightnessGet: AcknowledgedMeshMessage { var parameters = Data() }
struct DeviceProperty { let id: UInt16; init(_ id: UInt16) { self.id = id } }
struct LightLCPropertyGet: AcknowledgedMeshMessage { var parameters = Data(); init(_ property: DeviceProperty) {} }
extension HDBLightingMessages {
    static func message(_ write: HDBLightingWrite) -> AcknowledgedMeshMessage { LightingTestMessage(write: write) }
    static func observation(request: MeshMessage, response: MeshMessage) throws -> (String, String) { ("test", "1") }
}
extension Node { var parentApplicationKey: ApplicationKey? { ApplicationKey() } }
extension ApplicationKey { var key: Data { Data([1]) } }
// Hold one send until the test releases it; cancellation is observed on release.
enum LightingTestRadio {
    static var sends: [UInt16] = []
    static var pending: CheckedContinuation<Void, Error>?
    static var fail = false
}
extension MeshNetworkManager {
    func send(_ message: MeshMessage, to destination: MeshAddress, using key: ApplicationKey) async throws {
        LightingTestRadio.sends.append(destination.address)
        try await withCheckedThrowingContinuation { LightingTestRadio.pending = $0 }
        try Task.checkCancellation()
        if LightingTestRadio.fail { throw HDBConfigurationError.unavailable }
    }
}
