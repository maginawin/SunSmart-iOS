"""Run Settings production live-control handlers against transport/UI boundaries."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
source = (ROOT / 'SunSmart/Main/Scene/Controller/SceneSettingsViewController.swift').read_text()
picker = (ROOT / 'SunSmart/Main/Scene/View/SceneExecuteDataPickerView.swift').read_text()
detail = (ROOT / 'SunSmart/Main/Scene/Controller/SceneViewController.swift').read_text()


def block(text, marker):
    start = text.index(marker)
    opening = text.index('{', start)
    end, depth = opening + 1, 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[start:end].replace('private func', 'func')


swift = r'''
import Foundation
final class UIApplication {
    enum State { case active, background }
    static let shared = UIApplication(); var applicationState = State.active
}
struct GroupAddress { var address: UInt16 = 0xC001 }
struct LightControlData { var highEndTrim = 80 }
struct Profile { var lightControlData = LightControlData() }
struct GroupInfo { var profile = Profile() }
final class Group {
    var address = GroupAddress(), info = GroupInfo(), effectiveSupportCct = true
    func clampEffectiveCct(_ value: UInt16) -> UInt16 { max(2700, min(6500, value)) }
}
enum Node { static func getLightness(lightness100: Int) -> UInt16 { UInt16(lightness100 * 655) } }
final class MeshNetworkManager { static let instance = MeshNetworkManager(); var groups: [Group] = [] }
final class MeshLibManager { static let manager = MeshLibManager(); var isMeshNetworkConnected = true }
enum SceneConfigurationStore {
    enum Failure: Error { case access }
    static var allowed = true
    static func validateAccess(_ scope: Int) throws { if !allowed { throw Failure.access } }
}
enum EmergencyFireControllerSceneEventManager {
    static var blocked = false
    static func isManualControlBlocked(for group: Group) -> Bool { blocked }
}
struct Draft { enum Kind { case groups, devices }; var kind = Kind.groups; var scope = 1 }
final class Selection { var draft = Draft() }
final class Coordinator { var committedNumber: Int? }
final class SceneExecuteDataPickerView {
    // LIVE_EVENT
    var cancellations = 0
    func cancelLiveInteraction() { cancellations += 1 }
}
struct GenericOnOffSetUnacknowledged { let isOn: Bool; init(_ on: Bool) { isOn = on } }
struct LightLightnessSetUnacknowledged { let lightness: UInt16 }
struct LightCTLTemperatureSetUnacknowledged { let temperature: UInt16; let deltaUV: Int }
final class MeshGroupControlSession {
    enum Channel { case lightness, temperature }
    struct Sent { var address: UInt16; var message: Any; var final: Bool; var all: Bool }
    static var sent: [Sent] = []
    let address: UInt16; let isValid: () -> Bool
    var cancelled = false
    var onFailure: (() -> Void)?
    init(address: UInt16, isValid: @escaping () -> Bool) { self.address = address; self.isValid = isValid }
    func send(_ message: Any, channel: Channel, isFinal: Bool, replacingAll: Bool = false) -> Bool {
        guard !cancelled, isValid() else { return false }
        Self.sent.append(.init(address: address, message: message, final: isFinal, all: replacingAll)); return true
    }
    func cancel() { cancelled = true }
}
enum LightGroupControlCommandSender {}
final class SpaceData {
    enum Operation { case edit }
    var sceneOperates: [Operation] = [.edit]
}
struct Configuration { var isDeleting = false }
struct SceneInfo { var configuration: Configuration? = Configuration() }
final class Scene { var info = SceneInfo() }
final class Navigation {
    var pushed: [Settings] = []
    func pushViewController(_ controller: Settings, animated: Bool) { pushed.append(controller) }
}
typealias SceneSettingsViewController = Settings
final class SceneDetail {
    let space = SpaceData(), scene = Scene()
    var navigationController: Navigation? = Navigation()
    // SETTINGS_ENTRY
}
final class Settings {
    var active = true, busy = false, enablesGroupLiveControl = false
    init(space: SpaceData, scene: Scene) {}
    let coordinator = Coordinator()
    var selection: Selection? = Selection()
    var groupPreview: MeshGroupControlSession?
    var groupPreviewGeneration = UUID()
    var picker: SceneExecuteDataPickerView? = SceneExecuteDataPickerView()
    var tips: [String] = []
    func tip(_ key: String) { tips.append(key) }
    // HANDLERS
}
'''
swift = swift.replace('// LIVE_EVENT', block(picker, '    enum LiveEvent'))
swift = swift.replace('// SETTINGS_ENTRY', block(detail, '    private func settings()'))
swift = swift.replace('// HANDLERS', '\n'.join(block(source, marker) for marker in [
    '    private func cancelGroupPreview()', '    private func interruptGroupPreview()',
    '    private func stopGroupPreview()', '    private func canControlGroup(',
    '    private func handleGroupLiveControl('
]))
swift += source[source.index('private extension LightGroupControlCommandSender'):]
swift += r'''
var checks = 0
func expect(_ value: @autoclosure () -> Bool, _ message: String) { checks += 1; if !value() { fatalError(message) } }
let group = Group(), detail = SceneDetail()
detail.settings()
let settings = detail.navigationController!.pushed[0]
expect(settings.enablesGroupLiveControl, "existing Scene Settings enables the shared group-control popup")
MeshNetworkManager.instance.groups = [group]
settings.handleGroupLiveControl(.lightness(90, ended: true), group: group)
expect((MeshGroupControlSession.sent.last?.message as? LightLightnessSetUnacknowledged)?.lightness == 80 * 655, "brightness uses high end trim and conversion")
expect(MeshGroupControlSession.sent.last?.address == group.address.address, "targets exact selected group")
settings.handleGroupLiveControl(.temperature(7000, ended: false), group: group)
let cct = MeshGroupControlSession.sent.last?.message as? LightCTLTemperatureSetUnacknowledged
expect(cct?.temperature == 6500 && cct?.deltaUV == 0 && MeshGroupControlSession.sent.last?.final == false, "CCT clamps and preserves sample phase")
settings.handleGroupLiveControl(.off, group: group)
expect((MeshGroupControlSession.sent.last?.message as? GenericOnOffSetUnacknowledged)?.isOn == false && MeshGroupControlSession.sent.last?.all == true, "OFF clears both channels and sends false")
let offOwner = settings.groupPreview!
settings.handleGroupLiveControl(.cancel, group: group)
settings.handleGroupLiveControl(.lightness(80, ended: true), group: group)
expect(offOwner.cancelled && settings.groupPreview !== offOwner, "maximum restore discards the old OFF and CCT owner")
expect((MeshGroupControlSession.sent.last?.message as? LightLightnessSetUnacknowledged)?.lightness == 80 * 655 && MeshGroupControlSession.sent.last?.final == true, "maximum restore submits a final group brightness")
let old = settings.groupPreview!
settings.stopGroupPreview()
expect(old.cancelled && !old.isValid() && settings.picker?.cancellations == 1, "stop cancels owner and invalidates handoff")
settings.handleGroupLiveControl(.lightness(20, ended: true), group: group)
expect(settings.groupPreview !== old, "next authorized input gets a fresh owner")
let before = MeshGroupControlSession.sent.count
MeshLibManager.manager.isMeshNetworkConnected = false
settings.handleGroupLiveControl(.lightness(25, ended: false), group: group)
expect(settings.groupPreview == nil && settings.tips.isEmpty, "offline sample is discarded silently")
settings.handleGroupLiveControl(.lightness(25, ended: true), group: group)
expect(settings.tips.isEmpty && MeshGroupControlSession.sent.count == before, "offline final stays silent and does not queue")
MeshLibManager.manager.isMeshNetworkConnected = true
settings.handleGroupLiveControl(.lightness(30, ended: true), group: group)
expect(MeshGroupControlSession.sent.count == before + 1, "reconnected fresh input remains usable")
let current = settings.groupPreview!
SceneConfigurationStore.allowed = false
expect(!current.isValid(), "permissions rechecked at handoff")
settings.handleGroupLiveControl(.off, group: group)
expect(current.cancelled && MeshGroupControlSession.sent.count == before + 1, "permission loss stops pending preview")
SceneConfigurationStore.allowed = true
EmergencyFireControllerSceneEventManager.blocked = true
settings.handleGroupLiveControl(.off, group: group)
expect(MeshGroupControlSession.sent.count == before + 1, "emergency blocks actual group control")
EmergencyFireControllerSceneEventManager.blocked = false
settings.selection?.draft.kind = .devices
expect(!settings.canControlGroup(group), "Devices is not a group preview target")
settings.selection?.draft.kind = .groups
MeshNetworkManager.instance.groups = []
expect(!settings.canControlGroup(group), "removed group rejected")
MeshNetworkManager.instance.groups = [group]
UIApplication.shared.applicationState = .background
expect(!settings.canControlGroup(group), "background prevents handoff")
UIApplication.shared.applicationState = .active
settings.busy = true; expect(!settings.canControlGroup(group), "formal sending excludes preview")
settings.busy = false; settings.coordinator.committedNumber = 7
expect(!settings.canControlGroup(group), "committed scene cannot receive draft preview")
let restricted = SceneDetail()
restricted.space.sceneOperates = []; restricted.settings()
expect(restricted.navigationController!.pushed.isEmpty, "read-only Scene cannot open Settings")
restricted.space.sceneOperates = [.edit]; restricted.scene.info.configuration?.isDeleting = true
restricted.settings()
expect(restricted.navigationController!.pushed.isEmpty, "deleting Scene cannot open Settings")
print("SceneGroupLiveControlTests passed: \(checks) checks")
'''
with tempfile.TemporaryDirectory(prefix='scene-group-live-control-') as directory:
    path = Path(directory) / 'main.swift'
    path.write_text(swift)
    binary = Path(directory) / 'tests'
    subprocess.run(['swiftc', str(path), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
