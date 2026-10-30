"""Execute production device-control routing with a recording transport boundary.

This covers command count, ownership and draft-preview invalidation, not radio delivery.
"""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
source = (ROOT / 'SunSmart/Main/Scene/Controller/SceneSettingsViewController.swift').read_text()
picker = (ROOT / 'SunSmart/Main/Scene/View/SceneExecuteDataPickerView.swift').read_text()
selection = (ROOT / 'SunSmart/Main/Scene/Model/SceneDraftSelection.swift').read_text()


def block(text, marker):
    start = text.index(marker)
    opening = text.index('{', start)
    end, depth = opening + 1, 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[start:end].replace('private func', 'func').replace('@objc ', '')


swift = r'''
import Foundation
typealias TimedSchedulerNodeIdentity = Int
// TARGET
final class UIApplication {
    enum State { case active, background }
    static let shared = UIApplication(); var applicationState = State.active
}
final class Model { let address: UInt16; init(_ address: UInt16) { self.address = address } }
protocol UnacknowledgedMeshMessage {}
struct GenericOnOffSetUnacknowledged: UnacknowledgedMeshMessage { let isOn: Bool; init(_ value: Bool) { isOn = value } }
struct LightLightnessSetUnacknowledged: UnacknowledgedMeshMessage { let lightness: UInt16 }
struct LightCTLTemperatureSetUnacknowledged: UnacknowledgedMeshMessage { let temperature: UInt16; let deltaUV: Int }
final class Node {
    var state = true, effectiveSupportCct = true
    var lightnessRange: ClosedRange<UInt16> = 100...50000
    var lightnessModel: Model? = Model(0x100), temperatureModel: Model? = Model(0x101), onoffModel: Model? = Model(0x100)
    static func getLightness(lightness100: Int) -> UInt16 { UInt16(lightness100 * 655) }
    func clampEffectiveCct(_ value: UInt16) -> UInt16 { max(2700, min(6500, value)) }
}
final class MeshNetworkManager {
    static let instance = MeshNetworkManager()
    struct Sent { let message: UnacknowledgedMeshMessage; let model: Model }
    enum Failure: Error { case busy }
    var sent: [Sent] = [], fails = false
    func send(_ message: UnacknowledgedMeshMessage, to model: Model, completion: ((Result<Void, Error>) -> Void)?) throws {
        if fails { throw Failure.busy }
        sent.append(.init(message: message, model: model))
    }
}
final class MeshLibManager { static let manager = MeshLibManager(); var isMeshNetworkConnected = true }
enum SceneConfigurationStore {
    static var allowed = true
    enum Failure: Error { case access }
    static func validateAccess(_ scope: Int) throws { if !allowed { throw Failure.access } }
}
enum EmergencyFireControllerSceneEventManager {
    static var blocked = false
    static func isManualControlBlocked(for node: Node) -> Bool { blocked }
}
struct Draft { enum Kind { case devices, groups }; var kind = Kind.devices; var scope = 0; var revision = UUID() }
final class Selection {
    var draft = Draft(); var selected = Set([1, 2])
    func isSelected(_ identity: Int) -> Bool { selected.contains(identity) }
}
final class Coordinator { var committedNumber: Int? }
final class Devices {
    var nodes: [Int: Node] = [:]; var previewPhase = SceneDevicePreviewState.Phase.recommended
    func node(for identity: Int) -> Node? { nodes[identity] }
}
final class SceneExecuteDataPickerView {
    // EVENT
    final class Slider {
        var pending: (() -> Void)?
        func cancelPendingInteraction() { pending = nil }
    }
    final class FunctionView { let slider = Slider(); var value = 50 }
    var lightnessSliderView: FunctionView! = FunctionView(), cctSliderView: FunctionView! = FunctionView()
    var lightnessNeedsFinal = false, cctNeedsFinal = false, isOn = true
    var liveControl: ((LiveEvent) -> Void)?
    var selectedCct: Int { cctSliderView.value }
    let maximumLightness = 100
    func setLightnessValue(_ value: Int) { lightnessSliderView.value = value; isOn = value > 0 }
    // PICKER_HANDLERS
}
final class View { var window: Int? = 1 }
final class Navigation { weak var topViewController: Settings? }
final class Settings {
    var active = true, busy = false
    var selection: Selection? = Selection()
    var lifecycle = UUID(), deviceLiveGeneration = UUID()
    var lastLightnessSample: UInt16?, lastTemperatureSample: UInt16?
    var relayLiveControl: Int?
    var onDeviceLiveControl: (() -> Void)?
    let coordinator = Coordinator()
    var devicesView: Devices! = Devices()
    var picker: SceneExecuteDataPickerView? = SceneExecuteDataPickerView()
    var viewIfLoaded: View? = View()
    var navigationController: Navigation? = Navigation()
    var devicePreview = SceneDevicePreviewState()
    var previewComparison: Int?, previewOnline: Set<Int> = [], previewReport: Int?
    var toastClears = 0
    func clearPreviewToast() { toastClears += 1 }
    init() { navigationController!.topViewController = self }
    // HANDLERS
}
'''
swift = swift.replace('// TARGET', block(selection, 'enum SceneDeviceSettingsTarget'))
swift = swift.replace('// EVENT', block(picker, '    enum LiveEvent'))
swift = swift.replace('// PICKER_HANDLERS', '\n'.join(block(picker, marker) for marker in [
    '    @objc private func cancelSliderGesture()', '    @objc func cancelLiveInteraction()',
    '    private func finishLiveInteraction()', '    private func emitLightness(',
    '    private func emitTemperature(', '    @objc private func offBtnAction()'
]))
swift = swift.replace('// HANDLERS', '\n'.join(block(source, marker) for marker in [
    '    private func accepts(', '    private func makeDeviceLiveControl(',
    '    private func interruptDeviceLiveControl()', '    private func stopDeviceLiveControl()',
    '    private func invalidatePreviewAfterLiveControl()', '    private func canControlDevice(',
    '    private func handleDeviceLiveControl('
]))
swift += '\n' + block(selection, 'struct SceneDevicePreviewState')
swift += r'''
var checks = 0
func expect(_ value: @autoclosure () -> Bool, _ message: String) { checks += 1; precondition(value(), message) }
let manager = MeshNetworkManager.instance
let parent = Settings(), page = Settings(), node = Node()
page.devicesView.nodes = [1: node, 2: Node()]
page.onDeviceLiveControl = { parent.invalidatePreviewAfterLiveControl() }
expect(page.makeDeviceLiveControl(.category([1, 2])) == nil, "group/ungrouped batch never gets a transport callback")
expect(page.makeDeviceLiveControl(.category([1])) == nil, "one-member category must not become a device control")
expect(page.makeDeviceLiveControl(.device(99)) == nil, "missing identity has no live callback")
let control = page.makeDeviceLiveControl(.device(1))!
expect(manager.sent.isEmpty, "opening a single popup sends nothing")
let parentClears = parent.toastClears
control(.lightness(90, ended: false))
expect(manager.sent.count == 1 && manager.sent[0].model === node.lightnessModel, "one lightness sample targets one device model")
expect((manager.sent[0].message as? LightLightnessSetUnacknowledged)?.lightness == 50000, "brightness clamps to device maximum")
expect(parent.toastClears == parentClears + 1 && parent.devicePreview.phase == .recommended, "child control invalidates parent preview without changing the draft")
let revision = page.selection!.draft.revision
control(.lightness(90, ended: true))
expect(manager.sent.count == 1, "identical final sample is not duplicated")
control(.lightness(89, ended: true))
expect(manager.sent.count == 2, "each button event sends exactly one command")
control(.temperature(7000, ended: false))
expect(manager.sent.count == 3 && manager.sent.last!.model.address == 0x101, "temperature uses correct secondary Element, never primary or all Elements")
expect((manager.sent.last!.message as? LightCTLTemperatureSetUnacknowledged)?.temperature == 6500, "temperature clamps to device range")
control(.temperature(6500, ended: true))
expect(manager.sent.count == 3, "temperature final is not duplicated")
control(.off)
expect(manager.sent.count == 4 && (manager.sent.last!.message as? GenericOnOffSetUnacknowledged)?.isOn == false, "OFF is one OnOff UNACK")
control(.cancel)
expect(manager.sent.count == 4, "cancel sends no restore command")
control(.lightness(100, ended: true))
expect(manager.sent.count == 5 && manager.sent.last!.message is LightLightnessSetUnacknowledged, "restore sends brightness only, without an extra ON")
expect(page.selection!.draft.revision == revision && page.coordinator.committedNumber == nil, "live commands never persist or modify draft revision")
func rejects(_ message: String, change: () -> Void, restore: () -> Void) {
    let before = manager.sent.count
    change(); control(.off); expect(manager.sent.count == before, message); restore()
}
rejects("offline device", change: { node.state = false }, restore: { node.state = true })
rejects("disconnected mesh", change: { MeshLibManager.manager.isMeshNetworkConnected = false }, restore: { MeshLibManager.manager.isMeshNetworkConnected = true })
rejects("permission lost", change: { SceneConfigurationStore.allowed = false }, restore: { SceneConfigurationStore.allowed = true })
rejects("emergency control blocked", change: { EmergencyFireControllerSceneEventManager.blocked = true }, restore: { EmergencyFireControllerSceneEventManager.blocked = false })
rejects("background", change: { UIApplication.shared.applicationState = .background }, restore: { UIApplication.shared.applicationState = .active })
rejects("formal preview/save running", change: { page.busy = true }, restore: { page.busy = false })
rejects("committed scene", change: { page.coordinator.committedNumber = 1 }, restore: { page.coordinator.committedNumber = nil })
rejects("removed member", change: { page.selection!.selected.remove(1) }, restore: { page.selection!.selected.insert(1) })
rejects("replaced node at same identity", change: { page.devicesView.nodes[1] = Node() }, restore: { page.devicesView.nodes[1] = node })
rejects("hidden parent", change: { page.navigationController!.topViewController = parent }, restore: { page.navigationController!.topViewController = page })
rejects("inactive page", change: { page.active = false }, restore: { page.active = true })
rejects("wrong scene type", change: { page.selection!.draft.kind = .groups }, restore: { page.selection!.draft.kind = .devices })
let beforeFailure = manager.sent.count
manager.fails = true; control(.lightness(50, ended: false)); manager.fails = false
expect(manager.sent.count == beforeFailure, "busy failure does not enqueue or retry")
control(.lightness(50, ended: true))
expect(manager.sent.count == beforeFailure + 1, "a failed sample does not suppress a fresh final input")
page.picker!.lightnessSliderView.slider.pending = { control(.off) }
page.interruptDeviceLiveControl()
expect(page.picker!.lightnessSliderView.slider.pending == nil, "interruption cancels the pending slider interaction")
let beforeStop = manager.sent.count
page.stopDeviceLiveControl(); control(.off)
expect(manager.sent.count == beforeStop, "old popup callback cannot send after ownership ends")
let fresh = page.makeDeviceLiveControl(.device(1))!
fresh(.off)
expect(manager.sent.count == beforeStop + 1, "new popup remains usable")
page.lifecycle = UUID(); fresh(.off)
expect(manager.sent.count == beforeStop + 1, "late callback from old lifecycle is rejected")
let revised = page.makeDeviceLiveControl(.device(1))!
page.selection!.draft.revision = UUID(); revised(.off)
expect(manager.sent.count == beforeStop + 1, "draft changes reject old popup callback")
node.lightnessModel = nil; node.effectiveSupportCct = false
let relay = page.makeDeviceLiveControl(.device(1))!
let beforeRelay = manager.sent.count
relay(.lightness(100, ended: true)); relay(.off)
expect(manager.sent.count == beforeRelay + 2, "relay sends one message for each ON/OFF action")
expect((manager.sent[beforeRelay].message as? GenericOnOffSetUnacknowledged)?.isOn == true, "relay ON uses Generic OnOff")
expect((manager.sent.last!.message as? GenericOnOffSetUnacknowledged)?.isOn == false, "relay OFF uses Generic OnOff")
relay(.temperature(4500, ended: true))
expect(manager.sent.count == beforeRelay + 2, "relay receives no unsupported temperature command")
let sheet = SceneExecuteDataPickerView()
var events: [SceneExecuteDataPickerView.LiveEvent] = []
sheet.liveControl = { events.append($0) }
sheet.lightnessNeedsFinal = true; sheet.cctNeedsFinal = true
sheet.lightnessSliderView.slider.pending = { sheet.emitLightness(20, ended: false) }
sheet.offBtnAction()
expect(events.count == 1 && sheet.lightnessSliderView.slider.pending == nil, "OFF cancels pending samples and emits one event")
sheet.finishLiveInteraction()
expect(events.count == 1, "closing after OFF emits no old slider values")
sheet.offBtnAction()
expect(events.count == 3, "restore emits only cancellation plus one brightness event")
sheet.emitLightness(30, ended: false); sheet.lightnessNeedsFinal = true
sheet.emitLightness(30, ended: true)
let afterFinal = events.count
sheet.finishLiveInteraction()
expect(events.count == afterFinal, "closing after slider end has no duplicate final")
sheet.cctNeedsFinal = true; sheet.cctSliderView.value = 5000
sheet.cancelSliderGesture() // +/- touchDown takes ownership from the other slider.
sheet.emitLightness(31, ended: true)
let afterButton = events.count
sheet.finishLiveInteraction()
expect(events.count == afterButton, "closing after +/- cannot replay a cancelled temperature gesture")
sheet.lightnessNeedsFinal = true; sheet.lightnessSliderView.value = 32
sheet.finishLiveInteraction()
expect(events.count == afterButton + 1, "closing an active gesture still submits its needed final value")
sheet.finishLiveInteraction()
expect(events.count == afterButton + 1, "a second close cannot resubmit the final value")
print("SceneDeviceLiveControlTests passed: \(checks) checks")
'''
with tempfile.TemporaryDirectory(prefix='scene-device-live-control-') as directory:
    path = Path(directory) / 'main.swift'
    path.write_text(swift)
    binary = Path(directory) / 'tests'
    subprocess.run(['swiftc', str(path), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
