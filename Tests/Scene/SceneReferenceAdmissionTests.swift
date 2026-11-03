import Foundation

// Only persistence, Mesh and UI are substitutes. The tested methods are injected unchanged.
typealias SceneNumber = UInt16
extension UInt16 { var hex: String { String(format: "%04X", self) } }
final class Network { let uuid = UUID() }
final class Scene {
    struct Configuration { var isDeleting = false }
    struct Info { var configuration: Configuration? = Configuration() }
    let number: SceneNumber
    var info = Info()
    init(_ number: SceneNumber) { self.number = number }
}
final class MeshNetworkManager {
    struct Key { var networkId: UInt16 = 1; var index: UInt16 = 0 }
    static let instance = MeshNetworkManager()
    var meshNetwork: Network? = Network()
    var currentNetworkKey = Key(), currentApplicationKey = Key()
    var switchs: [DeviceSwitchData] = []
    var scenes: [Scene] = []
}
class DeviceSwitchData {
    let id: String
    var sceneANumber: SceneNumber?
    var saveSucceeds = true, saves = 0, updates = 0
    init(_ id: String) { self.id = id }
    func save() -> Bool { saves += 1; return saveSucceeds }
    func update(switchData: DeviceSwitchData) { updates += 1; sceneANumber = switchData.sceneANumber }
}
final class PJEightKeySwitchData: DeviceSwitchData {
    struct Settings { var ledIndicatorEnabled = true }
    var proxyNodeAddress: UInt16? = 2
    var enabled = true, moreSettingsState = Settings()
    func batteryPowerSwitchKeyConfigurations(appKeyIndex: UInt16) -> [Int] { [0, 1, 2, 3] }
}
final class Schedule {
    enum Action { case noAction, sceneRecall }
    var id = 10, action: Action = .sceneRecall
    var sceneNumber: SceneNumber?
    var nodeAddresses: [UInt16] = [], groupAddresses: [UInt16] = []
}
enum SceneDeletionCascade {
    static var deleting: Set<SceneNumber> = [], ownedSchedules: Set<Int> = []
    static func sceneNumbers(_ item: DeviceSwitchData) -> [SceneNumber] { item.sceneANumber.map { [$0] } ?? [] }
    static func permitsReferences(_ numbers: [SceneNumber], meshUUID: String, networkID: String) -> Bool {
        Set(numbers).isDisjoint(with: deleting)
    }
    static func owns(scheduleID: Int, meshUUID: String, networkID: String) -> Bool { ownedSchedules.contains(scheduleID) }
}
final class PJEightKeySwitchRepository {
    static let shared = PJEightKeySwitchRepository()
    var succeeds = true, saves = 0
    func save(_ data: PJEightKeySwitchData) -> Bool { saves += 1; return succeeds }
}
final class GroupSwitchsViewController {
    func publish(_ data: DeviceSwitchData) -> Bool { syncRealSwitchData(copySwitch: data) }
    // PRODUCTION_GROUP_SAVE
}
final class PJEightKeySwitchMonitorViewModel {
    let switchData: PJEightKeySwitchData
    init(_ data: PJEightKeySwitchData) { switchData = data }
    // PRODUCTION_MONITOR_SAVE
}
final class SyncDevicesViewController {
    enum SyncType {
        case enOceanSwitch(DeviceSwitchData, deleteSwitch: Bool = false)
        case batteryPowerSwitch(PJEightKeySwitchData), schedule(Schedule), devices
    }
    var type: SyncType
    init(_ type: SyncType) { self.type = type }
    func allowed() -> Bool { permitsSceneReferences() }
    // PRODUCTION_SYNC_ADMISSION
}
final class Model {}
final class Node {
    var primaryUnicastAddress: UInt16 = 2
    var sunricherVendorModel: Model? = Model()
}
struct SunricherVendorSet {
    enum Function { case batteryPowerSwitchKeyConfig(Int), batteryPowerSwitchTxEnabled(Bool), batteryPowerSwitchLEDEnabled(Bool) }
    let function: Function
}
final class MeshMessageHandle {
    var continuous = true
    init(message: SunricherVendorSet, model: Model) {}
}
enum BatteryPowerSwitchAddConfiguration {
    static func isSupportedAddNode(_ node: Node) -> Bool { true }
    // PRODUCTION_POWER_MESSAGES
}

@main struct SceneReferenceAdmissionTests {
    static var passed = 0, failed = 0
    static let manager = MeshNetworkManager.instance
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        if value() { passed += 1 } else { failed += 1; print("FAIL admission: \(message)") }
    }
    static func main() {
        manager.scenes = [Scene(1), Scene(2), Scene(3)]
        let saved = DeviceSwitchData("switch"), edit = DeviceSwitchData("switch")
        saved.sceneANumber = 2; edit.sceneANumber = 1; edit.saveSucceeds = false
        manager.switchs = [saved]
        let group = GroupSwitchsViewController()
        check(!group.publish(edit) && saved.sceneANumber == 2 && saved.updates == 0,
              "group save refusal does not publish stale draft")
        edit.saveSucceeds = true
        check(group.publish(edit) && saved.sceneANumber == 1 && saved.updates == 1,
              "group save success publishes committed draft")
        let missing = DeviceSwitchData("missing")
        check(!group.publish(missing) && missing.saves == 0, "removed group switch is not silently recreated")

        let power = PJEightKeySwitchData("switch")
        power.sceneANumber = 2; power.saveSucceeds = false
        let monitor = PJEightKeySwitchMonitorViewModel(power)
        let repository = PJEightKeySwitchRepository.shared
        check(!monitor.persist() && repository.saves == 0 && saved.updates == 1,
              "monitor base-save refusal stops metadata and cache publication")
        power.saveSucceeds = true; repository.succeeds = false
        check(!monitor.persist() && saved.updates == 1, "monitor metadata refusal preserves live cache")
        repository.succeeds = true
        check(monitor.persist() && saved.sceneANumber == 2 && saved.updates == 2,
              "monitor publishes only after both writes succeed")

        SceneDeletionCascade.deleting = [1]
        let kineticPage = SyncDevicesViewController(.enOceanSwitch(edit))
        check(!kineticPage.allowed(), "stale kinetic draft cannot enter sync plan")
        kineticPage.type = .enOceanSwitch(edit, deleteSwitch: true)
        check(kineticPage.allowed(), "removing a switch remains allowed")
        let powerPage = SyncDevicesViewController(.batteryPowerSwitch(power))
        check(powerPage.allowed(), "unrelated power Scene remains allowed")
        SceneDeletionCascade.deleting.insert(2)
        check(!powerPage.allowed(), "same activation-waiting draft rechecks deletion admission")
        power.sceneANumber = nil
        check(powerPage.allowed(), "clearing references remains allowed")
        let schedule = Schedule(); schedule.sceneNumber = 1
        let schedulePage = SyncDevicesViewController(.schedule(schedule))
        check(!schedulePage.allowed(), "Timed cannot recall deleting Scene")
        schedule.sceneNumber = 3; SceneDeletionCascade.ownedSchedules.insert(schedule.id)
        check(!schedulePage.allowed(), "owned Timed ID cannot reactivate with a different Scene")
        schedule.sceneNumber = nil; schedule.action = .noAction
        check(schedulePage.allowed(), "owned Timed cleanup remains allowed")
        schedule.nodeAddresses = [2]
        check(!schedulePage.allowed(), "owned Timed cannot acquire new device targets")
        check(SyncDevicesViewController(.devices).allowed(), "ordinary device recovery remains available")

        let node = Node()
        power.sceneANumber = 1
        check(BatteryPowerSwitchAddConfiguration.defaultConfigurationMessageHandles(for: power, node: node).isEmpty,
              "default power configuration cannot emit stale Scene keys")
        check(BatteryPowerSwitchAddConfiguration.linkedConfigurationMessageHandles(for: power, node: node).isEmpty,
              "linked and restored power configuration cannot emit stale Scene keys")
        power.sceneANumber = 3
        check(BatteryPowerSwitchAddConfiguration.defaultConfigurationMessageHandles(for: power, node: node).count == 4,
              "valid default power configuration retains all key messages")
        check(BatteryPowerSwitchAddConfiguration.linkedConfigurationMessageHandles(for: power, node: node).count == 6,
              "valid linked power configuration retains key, TX and LED messages")
        manager.scenes.removeAll { $0.number == 2 }
        SceneDeletionCascade.deleting.remove(2)
        power.sceneANumber = 2
        check(!powerPage.allowed(), "released tombstone cannot authorize old draft referencing removed Scene")
        kineticPage.type = .enOceanSwitch(power)
        check(!kineticPage.allowed(), "removed Scene cannot reenter kinetic configuration")
        SceneDeletionCascade.ownedSchedules.removeAll()
        schedule.sceneNumber = 2; schedule.action = .sceneRecall
        check(!schedulePage.allowed(), "removed Scene cannot reenter Timed configuration")
        check(BatteryPowerSwitchAddConfiguration.defaultConfigurationMessageHandles(for: power, node: node).isEmpty,
              "default power generation rejects removed Scene after tombstone release")
        check(BatteryPowerSwitchAddConfiguration.linkedConfigurationMessageHandles(for: power, node: node).isEmpty,
              "linked power generation rejects removed Scene after tombstone release")
        power.sceneANumber = 3; manager.scenes.last?.info.configuration?.isDeleting = true
        check(!powerPage.allowed(), "live deleting Scene is rejected before persisted snapshot catches up")
        check(BatteryPowerSwitchAddConfiguration.linkedConfigurationMessageHandles(for: power, node: node).isEmpty,
              "power generation also rejects live deletion intent")
        manager.scenes.last?.info.configuration?.isDeleting = false
        manager.meshNetwork = nil
        check(!powerPage.allowed(), "missing network cannot authorize proposed switch references")
        check(BatteryPowerSwitchAddConfiguration.linkedConfigurationMessageHandles(for: power, node: node).isEmpty,
              "missing network cannot emit power configuration")
        print("admission: \(passed) passed, \(failed) failed")
        if failed > 0 { exit(1) }
    }
}
