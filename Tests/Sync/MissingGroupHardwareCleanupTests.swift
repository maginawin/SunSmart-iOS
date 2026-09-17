import Foundation

typealias Address = UInt16
final class Model: Codable {
    var modelId: UInt32 = 0x1000
    var publish: Int? = 1
    var subscriptions: Set<UInt16> = [0xC00D, 0xFEFD]
    func unsubscribe(from address: UInt16) { subscriptions.remove(address) }
    func copy(from model: Model) { subscriptions = model.subscriptions; publish = model.publish }
}
struct Element { var unicastAddress: UInt16; var models: [Model] }
struct Scene: Equatable { let number: UInt16 }
struct SceneData { enum State { case normal, waitDelete }; let sceneNumber: UInt16; var state: State = .normal }
struct GroupInfo { var sceneExecuteDatas: [SceneData] = [] }
struct Group { var info = GroupInfo() }
struct Condition { let index: UInt8 }
struct Properties {
    var mode: Bool? = true
    var occupancyMode: Bool? = true
    var manualControlMode: Bool? = true
    var lightAutoAdjustEnabled: Bool? = true
}
enum ProfileType {
    case sensorDisable(sensorModels: [Model]), highLowEndTrim(range: ClosedRange<Int>)
    case sensitivity(value: UInt16), lightControlDelete(sceneNumber: UInt16)
    case profileToggleTriggerConditionLuxDelete(id: UInt8), mode(enabled: Bool)
    case occupancyMode(enabled: Bool), manualControl(enabled: Bool), lightAutoAdujustEnabled(enabled: Bool)
}
final class Node {
    enum GroupState { case none, inGroup, exitFailure }
    var group: Group?
    var groupState = GroupState.exitFailure
    var primaryUnicastAddress: UInt16 = 0x10
    var elements = [Element(unicastAddress: 0x10, models: [Model()])]
    var sensorModels: [Model] { elements[0].models }
    var lightnessSetupModel: Model? = Model()
    var lightnessRange: ClosedRange<UInt16> = 100...1000
    var presenceDetectedSensorModel: Model? = Model()
    var motionSensitivity: UInt16 = 123
    var lightLCSetupModel: Model? = Model()
    var supportLightLCScene = true
    var lightControlSceneExecuteDatas = [SceneData(sceneNumber: 0xFF01)]
    var lightControlLuxTriggerConditions = [Condition(index: 1)]
    var lightLCProperty = Properties()
    var sunricherVendorModel: Model? = Model()
    var sceneSetupModel: Model? = Model()
    var scenes = [Scene(number: 1), Scene(number: 2)]
    var saveSucceeds = true
    var saves = 0
    func save() -> Bool { saves += 1; return saveSucceeds }
    func clearSyncStateCache() {}
}
struct ConfigModelSubscriptionDelete {
    var elementAddress: UInt16 = 0x10
    var address: UInt16 = 0xC00D
    var modelId: UInt32 = 0x1000
}
protocol StaticMeshMessage {}
struct ConfigModelSubscriptionStatus: StaticMeshMessage {
    var isSuccess = true
    var elementAddress: UInt16 = 0x10
    var address: UInt16 = 0xC00D
    var modelId: UInt32 = 0x1000
}
struct MeshMessageHandle {
    var isSuccessful = true
    var address: UInt16? = 0x10
    var message: Any = ConfigModelSubscriptionDelete()
}
enum MissingGroupSubscriptionCleanup {
    static func addresses(for node: Node) -> Set<UInt16> {
        node.elements[0].models[0].subscriptions.subtracting([0xFEFD])
    }
}

@main
enum MissingGroupHardwareCleanupTests {
    static func main() {
        let node = Node()
        precondition(node.getMissingGroupCleanupProfiles().count == 9)
        precondition(node.getNodeNeedDeleteSceneDatas() == node.scenes)
        precondition(node.getNodeNeedDeleteSceneDatas(scene: Scene(number: 99)).isEmpty)
        precondition(node.elements[0].models[0].subscriptions == [0xC00D, 0xFEFD], "Planning retains observations")
        node.groupState = .none
        precondition(node.getMissingGroupCleanupProfiles().isEmpty && node.getNodeNeedDeleteSceneDatas().isEmpty)
        node.groupState = .inGroup
        node.group = Group()
        precondition(node.getMissingGroupCleanupProfiles().isEmpty && node.getNodeNeedDeleteSceneDatas().isEmpty)
        node.groupState = .exitFailure; node.group = nil
        node.sceneSetupModel = nil
        precondition(node.getNodeNeedDeleteSceneDatas().isEmpty)

        var response = MeshMessageHandle()
        var status = ConfigModelSubscriptionStatus()
        status.isSuccess = false
        precondition(!MissingGroupSubscriptionCleanup.acknowledge(response, status: status, for: node))
        precondition(node.saves == 0 && node.elements[0].models[0].subscriptions.contains(0xC00D))
        status.isSuccess = true; status.modelId = 0x1001
        precondition(!MissingGroupSubscriptionCleanup.acknowledge(response, status: status, for: node), "A late response for another model cannot confirm this request")
        status.modelId = 0x1000; response.address = 0x20
        precondition(!MissingGroupSubscriptionCleanup.acknowledge(response, status: status, for: node))
        response.address = 0x10; node.saveSucceeds = false
        precondition(!MissingGroupSubscriptionCleanup.acknowledge(response, status: status, for: node))
        precondition(node.elements[0].models[0].subscriptions.contains(0xC00D), "Failed persistence must remain retryable")
        node.saveSucceeds = true
        precondition(MissingGroupSubscriptionCleanup.acknowledge(response, status: status, for: node))
        precondition(node.elements[0].models[0].subscriptions == [0xFEFD], "Only the acknowledged old Group is cleared")
        print("PASS: missing Group scene/Profile cleanup, retained observations, failed receipt/persistence retry and acknowledged subscription removal")
    }
}
