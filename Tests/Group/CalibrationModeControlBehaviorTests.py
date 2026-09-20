"""Run extracted controller methods with UI stubs and a recording MeshAPI.

Checks mode browsing, sensor selection/activation, explicit dimming and calibration lifecycle.
Includes publication TTL repair and transaction rollback with immediate callbacks.
Does not exercise UIKit, BLE, SDK sampling or real asynchronous callback timing.
Run: python3 Tests/Group/CalibrationModeControlBehaviorTests.py
"""

from pathlib import Path
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[2]
source = (repo / 'SunSmart/Main/Group/Controller/LightSensorCalibrationViewController.swift').read_text()
policy_source = (repo / 'SunSmart/Common/Data/Node+SyncData.swift').read_text()

def method(name, optional=False):
    import re
    match = re.search(r'    (?:private |override )?func ' + name + r'\(', source)
    if match is None:
        if optional:
            return ''
        raise RuntimeError(name)
    start = match.start()
    opening = source.index('{', match.end())
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end].replace('private func ', 'func ')

methods = ['updateCalibrationModeUI', 'recalibrateNight', 'recalibrateSensor',
           'restoreGroupAutoAfterDaylightCalibration', 'suspendGroupAutoForDaylightCalibration',
           'beginDaylightCalibration', 'finishDaylightCalibrationSDKStage',
           'finishDaylightCalibrationFailure', 'restoreGroupAutoAfterSensorDraftIfNeeded',
           'setSensorCalibrationGroupDimLevel', 'restoreSensorDimLevel', 'viewWillAppear',
           'sensorEnabled', 'commitCalibrationSensorSelection', 'publicationRestoreHandle']
swift = r'''
import Foundation
extension String { var localizedString: String { self } }
enum LightSensorCalibrationMode: CaseIterable { case night, sensor, plane }
enum ProfileType: CaseIterable { case daylight, occupancy_daylight, vacancy_daylight }
final class Profile {
    var type = ProfileType.daylight
    var targetNightBrightness = 50
    var lightControlData = LightControlData()
    static func normalizedTargetNightBrightness(_ value: Int) -> Int { value }
}
final class LightControlData { var taskLevel = 300; var occupancyLevel = 300 }
final class Info {
    var profile = Profile()
    var ambientLightSensorNode: Node?
    var ambientLightSensorNodeAddress: Int? {
        get { ambientLightSensorNode?.primaryUnicastAddress }
        set { ambientLightSensorNode = newValue.flatMap { Node.registry[$0] } }
    }
}
final class Group {
    var info = Info(); var address = MeshAddress(); var nodes: [Node] = []
    var ambientLightSensorNodes: [Node] { nodes }
    func sensorServerPublicationRetransmit() -> Int { 0 }
}
typealias Address = Int
struct MeshAddress: Equatable { var address = 49153 }
extension UInt16 { static let sensorServerModelId: UInt16 = 0x1100 }
enum SelectState { case switchOn, switchOff, loading }
final class Node: Equatable {
    static var registry: [Int: Node] = [:]
    let primaryUnicastAddress: Int
    var selectState = SelectState.switchOff
    var ambientLightSensorModel: Model? = Model()
    init(_ address: Int) { primaryUnicastAddress = address; Self.registry[address] = self }
    static func == (lhs: Node, rhs: Node) -> Bool { lhs === rhs }
    func getNodeSyncProfiles() -> [Int] { [] }
    static func getLightness(lightness100: Int) -> Int { lightness100 }
    func sendHandleCompleteIdentify(deviceBlinkMode: Int) {}
}
final class Model { var publish: Publish?; let modelIdentifier: UInt16 = .sensorServerModelId }
struct Publish: Equatable {
    enum Period: Equatable { case disabled, periodic }
    let publicationAddress: MeshAddress
    let ttl: UInt8
    let index: Int
    let friendship: Bool
    let period: Period
    let retransmit: Int
    init(to: MeshAddress, using: Int, usingFriendshipMaterial: Bool, ttl: UInt8,
         period: Period, retransmit: Int) {
        publicationAddress = to; self.ttl = ttl; index = using
        friendship = usingFriendshipMaterial; self.period = period; self.retransmit = retransmit
    }
}
struct ConfigModelPublicationSet { let publish: Publish?; let model: Model
    init?(_ publish: Publish, to model: Model) { self.publish = publish; self.model = model }
    init?(disablePublicationFor model: Model) { self.publish = nil; self.model = model }
}
struct DaylightCalibrationSnapshot {
    let selectedSensorPublish: Publish?
    let groupSensor: Node?
    let groupSensorPublish: Publish?
}
struct MeshMessageHandle {
    let message: ConfigModelPublicationSet
    let address: Int
    var isSuccessful = true
}
final class MeshProxyMessageCommand {
    static let shared = MeshProxyMessageCommand()
    var publishSucceeds = true
    var keepOldTTL = false
    var outcomes: [Bool] = []
    var sentPublications: [Publish?] = []
    func addMessage(messageHandles: [MeshMessageHandle], finishedBack: ([MeshMessageHandle]) -> Void) {
        let results = messageHandles.map { handle in
            var result = handle
            MeshAPI.commands.append(handle.message.publish == nil ? "unpublish:\(handle.address)" : "publish:\(handle.address)")
            sentPublications.append(handle.message.publish)
            result.isSuccessful = outcomes.isEmpty ? publishSucceeds : outcomes.removeFirst()
            if result.isSuccessful && !keepOldTTL { handle.message.model.publish = handle.message.publish }
            return result
        }
        finishedBack(results)
    }
}
struct MeshNetworkManager {
    static let instance = MeshNetworkManager()
    let currentApplicationKey = 0
    let networkParameters = Parameters()
    struct Parameters { let defaultTtl = 5 }
}
// Configuration/UI callbacks are immediate in this isolated activation fixture.
struct DispatchQueue {
    static let main = DispatchQueue()
    func async(execute: () -> Void) { execute() }
}
final class View {
    enum State { case normal }
    var selectedMode = LightSensorCalibrationMode.night
    var isHidden = false
    var value = 50
    var allowedRange = 1...100
    var dimLevel = 50
    var targetValue: Int?
    func reloadSensorCell(sensor: Node) {}
    func setTitle(_ title: String, for state: State) {}
    func setTargetValue(_ value: Int) { targetValue = value }
    func update(targetLux: Int, targetBrightness: Int, showsTargetBrightness: Bool,
                pendingDeviceCount: Int, profileType: ProfileType) {}
}
struct Transition { static let `default` = Transition() }
struct LightLCLightOnOffSetUnacknowledged {
    let isOn: Bool
    init(_ isOn: Bool, transitionTime: Transition? = nil, delay: Int? = nil) { self.isOn = isOn }
}
enum MeshAPI {
    static var commands: [String] = []
    static func sendMessage(message: LightLCLightOnOffSetUnacknowledged, address: Int) {
        commands.append(message.isOn ? "on" : "off")
    }
    static func setGroupLightnessState(address: Int, lightness: Int) {
        commands.append("dim:\(lightness)")
    }
}
final class MeshLibManager {
    static let manager = MeshLibManager()
    weak var messageDelegate: Harness?
}
class Base { func viewWillAppear(_ animated: Bool) {} }
final class Harness: Base {
    let group = Group()
    var onPointLuxView = View(), offPointLuxView = View(), targetNightBrightnessView = View()
    var targetSensorValueView = View(), calibrationCompleteView = View(), calibrationBtn = View()
    var calibrationModeView = View()
    var sensorSelectView = View()
    var selectSensor: Node?
    var deviceBlinkMode = 0
    var disableSucceeds = true
    enum Suspension { case configuration }
    func setLuxPollingSuspended(_ suspended: Bool, for reason: Suspension) {}
    func updateGroupLightSensor() {}
    func configuring(lightNodes: [Node], completion: (Bool) -> Void) { completion(true) }
    func sensorDisable(sensor: Node, lightConfig: Bool, result: (Bool) -> Void) {
        MeshAPI.commands.append("disable:\(sensor.primaryUnicastAddress)")
        if disableSucceeds {
            sensor.ambientLightSensorModel?.publish = nil
            group.info.ambientLightSensorNode = nil
        }
        result(disableSucceeds)
    }
    var isNightRecalibrationDraft = false, isSensorRecalibrationDraft = false
    var nightComplete = false, sensorComplete = false
    var isNightCalibrationComplete: Bool { nightComplete && !isNightRecalibrationDraft }
    var isSensorCalibrationComplete: Bool { sensorComplete && !isSensorRecalibrationDraft }
    var targetNightBrightnessRange: ClosedRange<Int> { 1...100 }
    var sensorCalibrationDimLevel = 50
    var isDaylightGroupAutoSuspended = false, daylightConfigurationPending = false
    var daylightAutoRestoreBlocked = false, isDaylightCalibrationInProgress = false
    var activeDaylightCalibrationMode: String?
    var isViewVisible = false
    var shouldRestoreAutoAfterDaylightCalibration: Bool { true }
    func updateLuxPollingState() {}
    func updateManualCorrectionBtn() {}
    func updateCalibrationState() {}
    func setDaylightCalibrationNavigationLocked(_ locked: Bool) {}
    func select(_ mode: LightSensorCalibrationMode) {
        calibrationModeView.selectedMode = mode
        updateCalibrationModeUI(mode)
    }
'''
swift += '\n'.join(method(name) for name in methods)
swift += '\n' + method('updateSensorManualControlState', True)
swift += '\n' + method('resumeIncompleteSensorDraftIfNeeded', True)
swift += '\n' + method('restorePersistedSensorSelectionForPlane', True)
swift += r'''
}
'''
policy_start = policy_source.index('enum SensorPublicationPolicy {')
policy_end = policy_source.index('    func isSensorServerPublicationConfigured(', policy_start)
swift += policy_source[policy_start:policy_end] + '\n}\n'
swift += r'''
var assertions = 0
func require(_ condition: Bool, _ label: String) {
    assertions += 1
    guard condition else { print("FAIL: \(label)"); exit(1) }
}
func expect(_ commands: [String], _ label: String) {
    assertions += 1
    if MeshAPI.commands != commands {
        print("FAIL: \(label); expected \(commands), got \(MeshAPI.commands)")
        exit(1)
    }
    MeshAPI.commands = []
}
for type in ProfileType.allCases {
    for persistedAddress: Int? in [nil, 24] {
        for selectedAddress: Int? in [nil, 24, 25] {
            let h = Harness()
            h.group.info.profile.type = type
            h.group.nodes = [Node(24), Node(25)]
            h.group.info.ambientLightSensorNodeAddress = persistedAddress
            h.selectSensor = selectedAddress.flatMap { Node.registry[$0] }
            h.selectSensor?.selectState = .switchOn
            for mode in [LightSensorCalibrationMode.night, .sensor, .plane, .sensor, .plane] {
                h.select(mode)
                require(h.selectSensor?.primaryUnicastAddress == selectedAddress, "mode must retain draft sensor")
                require(h.group.nodes.filter { $0.selectState == .switchOn }.map(\.primaryUnicastAddress)
                    == selectedAddress.map { [$0] } ?? [], "mode must retain sensor switches")
                require(h.group.info.ambientLightSensorNodeAddress == persistedAddress, "mode must not commit selection")
                expect([], "selection mode switch sends no commands")
            }
        }
    }
    for complete in [false, true] {
        let h = Harness()
        h.group.info.profile.type = type
        h.sensorComplete = complete
        for mode in [LightSensorCalibrationMode.night, .sensor, .plane, .sensor, .night] {
            h.select(mode)
            h.viewWillAppear(false)
            expect([], "mode/appearance \(type) \(mode) complete=\(complete)")
        }
        h.select(.sensor)
        h.recalibrateSensor()
        expect([], "Recalibrate draft")
        h.restoreGroupAutoAfterSensorDraftIfNeeded()
        expect([], "browse-only exit")
        h.setSensorCalibrationGroupDimLevel(37)
        expect(["off", "dim:37"], "manual dim remains active")
        for mode in [LightSensorCalibrationMode.night, .plane, .sensor] {
            h.select(mode)
            h.viewWillAppear(false)
            expect([], "switch after manual dim")
        }
        h.setSensorCalibrationGroupDimLevel(65)
        expect(["dim:65"], "repeated manual dim")
        h.restoreGroupAutoAfterSensorDraftIfNeeded()
        expect(["on"], "exit after manual dim restores Auto")
        h.restoreGroupAutoAfterSensorDraftIfNeeded()
        expect([], "exit restore is idempotent")
    }
    for mode in ["plane", "night", "sensor"] {
        let h = Harness()
        h.group.info.profile.type = type
        h.beginDaylightCalibration(mode: mode)
        expect(["off"], "formal calibration starts with suspend")
        h.restoreGroupAutoAfterSensorDraftIfNeeded()
        expect([], "running calibration cannot restore via exit")
        h.finishDaylightCalibrationSDKStage()
        for selected in LightSensorCalibrationMode.allCases { h.select(selected) }
        h.restoreGroupAutoAfterSensorDraftIfNeeded()
        expect([], "configuration pending blocks draft restore")
        h.restoreGroupAutoAfterDaylightCalibration()
        expect(["on"], "configuration success restores Auto")
        h.beginDaylightCalibration(mode: mode)
        expect(["off"], "retry starts with suspend")
        h.finishDaylightCalibrationFailure(allowAutoRestore: true)
        expect(["on"], "recoverable calibration failure restores Auto")
        h.beginDaylightCalibration(mode: mode)
        expect(["off"], "next calibration starts with suspend")
        h.finishDaylightCalibrationFailure(allowAutoRestore: false)
        for selected in LightSensorCalibrationMode.allCases { h.select(selected) }
        h.restoreGroupAutoAfterSensorDraftIfNeeded()
        expect([], "rollback failure blocks Auto restore")
    }
}
for disableSucceeds in [false, true] {
    for publishSucceeds in [false, true] {
        let h = Harness()
        let previous = Node(24), selected = Node(25)
        h.group.nodes = [previous, selected]
        h.group.info.ambientLightSensorNode = previous
        previous.ambientLightSensorModel?.publish = Publish(
            to: h.group.address, using: 0, usingFriendshipMaterial: false,
            ttl: 5, period: .disabled, retransmit: 0)
        h.disableSucceeds = disableSucceeds
        MeshProxyMessageCommand.shared.publishSucceeds = publishSucceeds
        var result: Bool?
        h.sensorEnabled(sensor: selected) { result = $0 }
        expect(disableSucceeds ? ["disable:24", "publish:25"] : ["disable:24"],
               "activation must disable persisted sensor before publishing draft")
        require(result == (disableSucceeds && publishSucceeds), "activation result")
        let expectedAddress = disableSucceeds ? (publishSucceeds ? 25 : nil) : 24
        require(h.group.info.ambientLightSensorNodeAddress == expectedAddress, "activation persistence")
    }
}
MeshProxyMessageCommand.shared.publishSucceeds = true
for alreadyPublished in [false, true] {
    let h = Harness()
    let selected = Node(24)
    h.group.info.ambientLightSensorNode = alreadyPublished ? selected : nil
    if alreadyPublished {
        selected.ambientLightSensorModel?.publish = Publish(
            to: h.group.address, using: 0, usingFriendshipMaterial: false,
            ttl: 0xFF, period: .disabled, retransmit: 0)
    }
    var result: Bool?
    h.sensorEnabled(sensor: selected) { result = $0 }
    expect(alreadyPublished ? [] : ["publish:24"], "existing and first sensor activation")
    require(result == true, "activation without previous sensor succeeds")
}

for keepOldTTL in [false, true] {
    let h = Harness(), selected = Node(30)
    h.group.info.ambientLightSensorNode = selected
    selected.ambientLightSensorModel?.publish = Publish(
        to: h.group.address, using: 0, usingFriendshipMaterial: false,
        ttl: 5, period: .disabled, retransmit: 0)
    MeshProxyMessageCommand.shared.keepOldTTL = keepOldTTL
    var result: Bool?
    h.sensorEnabled(sensor: selected) { result = $0 }
    expect(["publish:30"], "same-address old TTL must be repaired")
    require(result == !keepOldTTL, "status success with old TTL must fail target verification")
    require(MeshProxyMessageCommand.shared.sentPublications.last!!.ttl == 0xFF, "activation sends default TTL sentinel")
    MeshProxyMessageCommand.shared.keepOldTTL = false
    if keepOldTTL {
        h.sensorEnabled(sensor: selected) { result = $0 }
        expect(["publish:30"], "failed TTL verification remains retryable")
        require(result == true, "TTL retry succeeds after device applies target")
    }
    h.sensorEnabled(sensor: selected) { result = $0 }
    expect([], "repaired TTL is idempotent")
}
for sameSensor in [false, true] {
    for failure in ["none", "write", "staleTTL", "rollback"] {
        let h = Harness(), previous = Node(40)
        let selected = sameSensor ? previous : Node(41)
        h.group.nodes = sameSensor ? [previous] : [previous, selected]
        h.group.info.ambientLightSensorNode = previous
        let original = Publish(to: h.group.address, using: 7, usingFriendshipMaterial: true,
                               ttl: 5, period: .periodic, retransmit: 6)
        previous.ambientLightSensorModel?.publish = original
        let snapshot = DaylightCalibrationSnapshot(selectedSensorPublish: selected.ambientLightSensorModel?.publish,
            groupSensor: previous, groupSensorPublish: previous.ambientLightSensorModel?.publish)
        let command = MeshProxyMessageCommand.shared
        command.keepOldTTL = failure == "staleTTL"
        let succeeds = failure == "none" || failure == "staleTTL"
        command.outcomes = sameSensor ? [succeeds] : [true, succeeds]
        command.outcomes += sameSensor ? [failure != "rollback"] : [failure != "rollback", true]
        var result: (Bool, Bool)?
        h.commitCalibrationSensorSelection(selected, rollbackSnapshot: snapshot) { result = ($0, $1) }
        require(result?.0 == (failure == "none"), "transaction target verification")
        if failure == "none" {
            require(h.group.info.ambientLightSensorNodeAddress == selected.primaryUnicastAddress, "commit selected sensor")
            require(selected.ambientLightSensorModel?.publish?.ttl == 0xFF, "committed publication TTL")
            if !sameSensor { require(previous.ambientLightSensorModel?.publish == nil, "previous publication disabled") }
        } else {
            require(result?.1 == (failure != "rollback"), "rollback outcome is reported")
            require(h.group.info.ambientLightSensorNodeAddress == previous.primaryUnicastAddress, "failed transaction retains selection")
            if failure != "rollback" {
                require(previous.ambientLightSensorModel?.publish == original, "rollback preserves ALL old publication fields")
                require(selected.ambientLightSensorModel?.publish == snapshot.selectedSensorPublish, "selected sensor snapshot restored")
            }
        }
        command.outcomes = []; command.keepOldTTL = false; MeshAPI.commands = []
    }
}
print("PASS: \(assertions) command-sequence assertions using extracted production methods")
'''
with tempfile.TemporaryDirectory(prefix='calibration-mode-') as d:
    test = Path(d) / 'main.swift'
    test.write_text(swift)
    binary = Path(d) / 'check'
    subprocess.run(['swiftc', str(test), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
