import Foundation

struct SceneRecallUnacknowledged { let scene: UInt16; init(_ scene: UInt16) { self.scene = scene } }
struct GenericOnOffSet { let isOn: Bool; init(_ value: Bool) { isOn = value } }
enum TransitionTime { case immediate }
struct LightCTLSet {
    let lightness: UInt16; let temperature: UInt16
    init(lightness: UInt16, temperature: UInt16, deltaUV: Int, transitionTime: TransitionTime, delay: Int) { self.lightness = lightness; self.temperature = temperature }
}
struct LightLightnessSet {
    let lightness: UInt16
    init(lightness: UInt16, transitionTime: TransitionTime, delay: Int) { self.lightness = lightness }
}
struct SceneStore { let scene: UInt16; init(_ value: UInt16) { scene = value } }
struct SceneDelete { let scene: UInt16; init(_ value: UInt16) { scene = value } }
final class MeshMessageHandle {
    var sceneContext: SceneMessageContext?
    let message: Any; let model: Model?
    var address: UInt16?
    var continuous = true
    var isSuccessful = true
    init(message: Any, model: Model) { self.message = message; self.model = model }
    init(message: Any, address: UInt16) { self.message = message; self.address = address; self.model = nil }
}
extension Node { var ctlModel: Model? { effectiveSupportCct ? Model() : nil } }
extension SceneInfo {
    func saveConfiguration(meshUUID: String? = nil, subnetworkId: String? = nil) throws {
        if TestPersistence.fail { throw TestPersistence.Failure.failed }
    }
}
enum TestPersistence { enum Failure: Error { case failed }; static var fail = false }

extension Node {
    var syncReadGroup: Group? { group }
    var scenes: [Scene] { MeshNetworkManager.instance.scenes.filter { scene in sceneExecuteDatas.contains { $0.sceneNumber == scene.number } } }
    func needsSceneRemoval(_ number: UInt16) -> Bool { sceneExecuteDatas.contains { $0.sceneNumber == number } }
}
enum SceneDeleteCapability { static func isSupported(sceneSetupModel: Model?) -> Bool { sceneSetupModel != nil } }

enum SceneConfigurationStore {
    enum Failure: Error { case staleDraft, unavailable, noNumber, persistence, invalidTargets }
    static var authorized = true
    static func validateAccess(_ scope: SceneScope) throws {
        guard authorized else { throw TestPersistence.Failure.failed }
    }
}

// SDK message objects and cache writes are boundaries. Production routing,
// delayed submission, plan comparison and Scene generation run unchanged.
struct ConfigModelSubscriptionAdd { let address: UInt16 }
struct ConfigModelSubscriptionDelete { let address: UInt16 }
struct ConfigCompositionDataGet { var page: UInt8 = 0 }
struct LightLightnessRangeSet { let range: ClosedRange<UInt16> }
enum NodeSyncTopologyCapture {
    static func isMembershipGroup(_ group: Group) -> Bool { !group.isVirtual && group.address.address < 0xFF00 }
}
extension Network {
    func node(withAddress address: UInt16) -> Node? {
        MeshNetworkManager.instance.realNodes.first { $0.primaryUnicastAddress == address || $0.addressAliases.contains(address) }
    }
}
enum SpaceSyncTaskScope {
    // ACTUAL_EXPECT_SCENE_PROGRESS
}
typealias MessageCommandSuccessfulCallback = (MeshMessageHandle, Int) -> Void
typealias MessageCommandFailedCallback = (MeshMessageHandle) -> Void
typealias MessageCommandFinishedCallback = ([MeshMessageHandle]) -> Void
final class SceneProgressTransport {
    var configurationWillSend: ([MeshMessageHandle]) -> Void = { _ in }
    var send: ([MeshMessageHandle], TimeInterval, MessageCommandSuccessfulCallback?, MessageCommandFailedCallback?, MessageCommandFinishedCallback?) -> Void = { _, _, _, _, _ in }
    // ACTUAL_ADD_MESSAGE
}
