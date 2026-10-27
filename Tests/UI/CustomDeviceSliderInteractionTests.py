"""Exercise production slider lifecycle and Group/Device control handlers.

UIKit tracking, layout, clock and Mesh transport are deterministic boundaries.
This verifies event ordering and emitted commands, not actual UIKit/radio behavior.
Run with --baseline to reproduce the late-event failure against HEAD.
"""
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
baseline = "--baseline" in sys.argv


def read(path):
    if baseline:
        return subprocess.check_output(["git", "show", f"HEAD:{path}"], cwd=ROOT, text=True)
    return (ROOT / path).read_text()


def block(source, marker):
    start = source.index(marker)
    opening = source.index("{", start)
    end, depth = opening + 1, 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end].replace("@objc ", "").replace("private func", "func")


slider = read("SunSmart/Common/View/CustomDeviceSlider.swift")
panel = read("SunSmart/Main/Device/View/DeviceLightControlPanelView.swift")
group = read("SunSmart/Main/Group/Controller/GroupViewController.swift")
device = read("SunSmart/Main/Device/Controller/DeviceLightViewController.swift")
hdb = read("SunSmart/Main/Space/HDB/Controller/HDBLightingZoneDetailViewController.swift")
methods = ["override var value:", "override func beginTracking", "func sliderValueChanged",
           "func sliderEndValueChange", "func startTimer", "func stopTimer",
           "override func touchesEnded", "override func touchesCancelled"]
methods += [marker for marker in ["func beginInteraction", "func cancelPendingInteraction",
            "override func cancelTracking", "func finishCancelledInteraction",
            "override func didMoveToWindow", "override func accessibilityIncrement",
            "override func accessibilityDecrement", "func performAccessibilityAdjustment", "deinit"]
            if marker in slider]

swift = r'''
import Foundation

var checks = 0
func expect(_ value: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    if !value() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
final class Timer {
    static var all: [Timer] = []
    let callback: (Timer) -> Void
    var valid = true
    init(timeInterval: TimeInterval, repeats: Bool, block: @escaping (Timer) -> Void) {
        callback = block; Self.all.append(self)
    }
    func invalidate() { valid = false }
    func fire() { if valid { callback(self) } }
    static func tick() { for timer in all { timer.fire() } }
}
final class RunLoop {
    enum Mode { case common }
    static let current = RunLoop()
    func add(_ timer: Timer, forMode: Mode) {}
}
class UITouch: NSObject {}
class UIEvent {}
class UIControl { var isSelected = false }
class UIButton: UIControl {}
class UISlider {
    var value: Float = 0
    var minimumValue: Float = 0, maximumValue: Float = 100
    var isEnabled = true
    var window: Int? = 1
    var accessibilitySendsEvent = false
    var valueEvent: (() -> Void)?
    func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool { true }
    func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {}
    func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { cancelTracking(with: event) }
    func cancelTracking(with event: UIEvent?) {}
    func didMoveToWindow() {}
    func accessibilityIncrement() { value += 1; if accessibilitySendsEvent { valueEvent?() } }
    func accessibilityDecrement() { value -= 1; if accessibilitySendsEvent { valueEvent?() } }
}
protocol CustomDeviceSliderDelegate: AnyObject {
    func slider(_ slider: CustomDeviceSlider, canEditChanged value: Float) -> Bool
    func slider(_ slider: CustomDeviceSlider, valueChanged value: Float, ended: Bool)
    func slider(_ slider: CustomDeviceSlider, throttleValueChanged value: Float, ended: Bool)
}
extension CustomDeviceSliderDelegate {
    func slider(_ slider: CustomDeviceSlider, canEditChanged value: Float) -> Bool { true }
}
class CustomDeviceSlider: UISlider {
    var sendsFinalValueOnTouchCancel = false
    var throttle = true, isSliding = false
    var interval: TimeInterval = 0.3
    var step: Int?, limitRange: ClosedRange<Int>?
    var valueChangedTimer: Timer?, lastSendValue: Float?
    var interactionValue: Float?, pendingValue: Float?
    weak var delegate: CustomDeviceSliderDelegate?
'''
swift += "\n".join(block(slider, method) for method in methods)
if baseline:
    swift += "\nfunc cancelPendingInteraction() {}\n"
swift += r'''
    func begin() { expect(beginTracking(UITouch(), with: nil), "tracking accepted") }
    func input(_ value: Float) { self.value = value; sliderValueChanged() }
    func end() { touchesEnded([], with: nil) }
    func cancel() { touchesCancelled([], with: nil) }
}
final class Recorder: CustomDeviceSliderDelegate {
    var allowed = true
    var changes: [Float] = [], samples: [Float] = [], finals: [Float] = []
    var onChange: ((CustomDeviceSlider, Float, Bool) -> Void)?
    func slider(_ slider: CustomDeviceSlider, canEditChanged value: Float) -> Bool { allowed }
    func slider(_ slider: CustomDeviceSlider, valueChanged value: Float, ended: Bool) {
        changes.append(value); onChange?(slider, value, ended)
    }
    func slider(_ slider: CustomDeviceSlider, throttleValueChanged value: Float, ended: Bool) {
        if ended { finals.append(value) } else { samples.append(value) }
    }
}
func fixture() -> (CustomDeviceSlider, Recorder) {
    let slider = CustomDeviceSlider(), recorder = Recorder()
    slider.limitRange = 1...100; slider.delegate = recorder
    return (slider, recorder)
}

// Exact failure order from the field log: ended -> late valueChanged -> OFF refresh.
do {
    let (s, r) = fixture()
    s.begin(); s.input(66); Timer.tick(); s.end()
    s.sliderValueChanged(); s.value = 0
    for _ in 0..<4 { Timer.tick() }
    expect(r.samples == [66], "late valueChanged must not emit 1% after OFF")
    expect(r.finals == [66] && !s.isSliding, "one final and closed interaction")
    s.end(); expect(r.finals == [66], "duplicate end is silent")
}

do {
    let (s, r) = fixture()
    s.value = 30; Timer.tick()
    expect(r.samples.isEmpty && r.changes.isEmpty, "programmatic initialization is silent")
    s.begin(); s.input(66); s.value = 0; Timer.tick(); s.end()
    expect(r.samples == [66] && r.finals == [66], "pending and final use user snapshot")
    s.begin(); s.input(66); Timer.tick(); s.end()
    expect(r.samples == [66, 66], "new gesture resets deduplication")
    s.begin(); s.input(1); Timer.tick(); s.end()
    expect(r.samples.last == 1 && r.finals.last == 1, "legitimate 1% remains allowed")
    s.limitRange = 20...80; s.begin(); s.input(95); Timer.tick(); s.end()
    expect(r.samples.last == 80 && r.finals.last == 80, "trim remains enforced")
    s.limitRange = 0...100; s.begin(); s.input(0); s.end()
    expect(r.finals.last == 0, "zero remains allowed for zero-based consumers")
}

for finalOnCancel in [false, true] {
    let (s, r) = fixture(); s.sendsFinalValueOnTouchCancel = finalOnCancel
    s.begin(); s.input(48); s.cancel(); s.sliderValueChanged(); s.value = 0; Timer.tick(); s.cancel()
    expect(r.samples.isEmpty && !s.isSliding, "cancel always discards timer")
    expect(r.finals == (finalOnCancel ? [48] : []), "cancel final remains opt-in and unique")
    s.begin(); s.input(32); s.cancelTracking(with: nil); s.end(); Timer.tick()
    expect(r.finals == (finalOnCancel ? [48, 32] : []), "system tracking cancellation closes once")
    expect(r.samples.isEmpty && !s.isSliding, "system cancellation leaves no pending sample")
}

do {
    let (s, r) = fixture()
    s.begin(); s.input(53); let obsoleteTimer = s.valueChangedTimer!
    s.cancelPendingInteraction(); s.end(); s.sliderValueChanged(); Timer.tick()
    expect(r.samples.isEmpty && r.finals.isEmpty, "explicit takeover drops old gesture")
    s.begin(); s.input(72); obsoleteTimer.callback(obsoleteTimer)
    expect(r.samples.isEmpty, "old queued timer cannot consume a new gesture")
    Timer.tick(); expect(r.samples == [72], "new timer sends new input")
    s.window = nil; s.didMoveToWindow(); s.value = 0; Timer.tick(); s.end()
    expect(r.samples == [72] && r.finals.isEmpty, "detaching closes without final")
    s.window = 1; s.didMoveToWindow(); s.begin(); s.input(31); s.end()
    expect(r.finals == [31], "reattached slider accepts fresh gesture")
}

do {
    let (s, r) = fixture(); s.throttle = false
    r.onChange = { slider, _, ended in if ended { slider.value = 0 } }
    s.begin(); s.input(60); Timer.tick(); s.end()
    expect(r.samples.isEmpty && r.finals == [60], "non-throttled final survives delegate refresh")
    r.allowed = false
    expect(!s.beginTracking(UITouch(), with: nil), "denied interaction rejected")
    s.input(80); s.end(); expect(r.finals == [60], "denied interaction emits nothing")
}

for emitsEvent in [false, true] {
    let (s, r) = fixture(); s.value = 50; s.accessibilitySendsEvent = emitsEvent
    s.valueEvent = { [weak s] in s?.sliderValueChanged() }
    s.accessibilityIncrement(); s.accessibilityDecrement(); Timer.tick()
    expect(r.finals == [51, 50] && r.changes == [51, 51, 50, 50], "accessibility completes each adjustment once")
    expect(!s.isSliding && r.samples.isEmpty, "accessibility leaves no timer")
    s.value = 50
    r.onChange = { slider, _, _ in slider.value = 0 }
    s.accessibilityIncrement()
    expect(r.finals.last == 51, "accessibility callback refresh cannot replace user input")
}

do {
    let r = Recorder(); var s: CustomDeviceSlider? = CustomDeviceSlider()
    s!.delegate = r; s!.begin(); s!.input(50); let timer = s!.valueChangedTimer!
    weak var released = s; s = nil
    expect(released == nil && !timer.valid, "deinit invalidates retained run-loop timer")
    released = nil
}

// Production controller methods, with UI and Mesh replaced by observable boundaries.
typealias Address = UInt16
class Node {
    var isOn = true, isEmergencySignController = false
    var lightness: UInt16 = 32767, trunOffLightness: UInt16?
    var lightnessRange: ClosedRange<UInt16> = 1...65535
    let primaryUnicastAddress: Address = 2
    static func getLightness(lightness100: Int) -> UInt16 { UInt16(Double(lightness100) / 100 * 65535) }
    static func getLightness100(lightness: UInt16) -> Int { Int((Double(lightness) / 65535 * 100).rounded()) }
}
struct MeshAddress { let address: Address = 0xC000 }
class Group {
    var isOn = true, lightness: UInt16 = 32767
    var nodes = [Node()]; let address = MeshAddress()
}
enum Command: Equatable { case onOff(Address, Bool), brightness(Address, UInt16) }
enum LightGroupControlCommandSender {
    static var commands: [Command] = []
    static func setGroupOnOff(address: Address, isOn: Bool) { commands.append(.onOff(address, isOn)) }
    static func setGroupLightness(address: Address, lightness: UInt16) { commands.append(.brightness(address, lightness)) }
    static func setNodeLightness(address: Address, lightness: UInt16) { commands.append(.brightness(address, lightness)) }
}
class Buoy { let slider = CustomDeviceSlider() }
class Detailed {
    let slider = CustomDeviceSlider()
    func cancelPendingInteraction() { slider.cancelPendingInteraction() }
}
class Panel: CustomDeviceSliderDelegate {
    let simpleBrightnessSlider = Buoy(), simpleCCTSlider = Buoy()
    let detailedBrightnessView = Detailed(), detailedCCTView = Detailed()
    var brightnessValueChanged: ((Int) -> Void)?
    var brightnessThrottleValueChanged: ((Int, Bool) -> Void)?
    var detailed = false
    var active: CustomDeviceSlider { detailed ? detailedBrightnessView.slider : simpleBrightnessSlider.slider }
    init() {
        for s in [simpleBrightnessSlider.slider, simpleCCTSlider.slider, detailedBrightnessView.slider, detailedCCTView.slider] {
            s.delegate = self; s.limitRange = 1...100
        }
    }
    func setBrightnessValue(_ value: Int) {
        simpleBrightnessSlider.slider.value = Float(value)
        detailedBrightnessView.slider.value = Float(value)
    }
    func slider(_ slider: CustomDeviceSlider, valueChanged value: Float, ended: Bool) { brightnessValueChanged?(Int(value)) }
    func slider(_ slider: CustomDeviceSlider, throttleValueChanged value: Float, ended: Bool) { brightnessThrottleValueChanged?(Int(value), ended) }
'''
swift += (block(panel, "func cancelPendingInteraction()") if not baseline
          else "func cancelPendingInteraction() {}")
swift += r'''
}
class Collection { func reloadData() {} }
class GroupPage {
    let group = Group(), onoffBtn = UIButton(), controlPanelView = Panel(), collectionView = Collection()
    let currentGroupBrightnessRange = 1...100
    init() { onoffBtn.isSelected = true; bind() }
    func showEmergencyControlBlockedIfNeeded() -> Bool { false }
    func updateControlPanel() {}
    func updateUpDownRatioUI() {}
    func deferNextScheduledUIFlush() {}
    func refreshAutoState() {}
    func reloadVisibleGroupDeviceItems() {}
    func bind() {
'''
swift += "\n".join(block(group, marker) for marker in [
    "controlPanelView.brightnessValueChanged =", "controlPanelView.brightnessThrottleValueChanged ="])
swift += "\n}\n"
swift += "\n".join(block(group, marker) for marker in [
    "func onoffBtnClick", "func applyGroupBrightnessValue", "func sendGroupBrightnessValue"])
swift += r'''
}
class DevicePage {
    let node = Node(), controlPanelView = Panel()
    init() { bind() }
    func updateData(refreshControlPanel: Bool) {}
    func updateControlPanel() { controlPanelView.setBrightnessValue(node.isOn ? Node.getLightness100(lightness: node.lightness) : 0) }
    func sendLightDetailOnOffCommand() { LightGroupControlCommandSender.commands.append(.onOff(node.primaryUnicastAddress, node.isOn)) }
    func sendLightDetailBrightnessCommand(percent: Int, lightness: UInt16) { LightGroupControlCommandSender.setNodeLightness(address: node.primaryUnicastAddress, lightness: lightness) }
    func bind() {
'''
swift += "\n".join(block(device, marker) for marker in [
    "controlPanelView.brightnessValueChanged =", "controlPanelView.brightnessThrottleValueChanged ="])
swift += "\n}\n"
swift += "\n".join(block(device, marker) for marker in ["func onoffAction", "func applyBrightnessValue"])
swift += r'''
}
for detailed in [false, true] {
    let p = GroupPage(); p.controlPanelView.detailed = detailed; let s = p.controlPanelView.active
    s.begin(); s.input(66); Timer.tick(); s.end(); s.sliderValueChanged()
    LightGroupControlCommandSender.commands = []
    for _ in 0..<3 {
        p.onoffBtnClick(sender: p.onoffBtn); Timer.tick()
        expect(!p.group.isOn && !p.group.nodes[0].isOn, "Group OFF stays OFF")
        p.onoffBtnClick(sender: p.onoffBtn); Timer.tick()
        expect(p.group.isOn && p.group.lightness == Node.getLightness(lightness100: 66), "Group ON keeps user brightness")
    }
    expect(LightGroupControlCommandSender.commands == Array(repeating: [.onOff(0xC000, false), .onOff(0xC000, true)], count: 3).flatMap { $0 }, "Group emits only alternating OFF/ON")
    s.begin(); s.input(53); LightGroupControlCommandSender.commands = []
    p.onoffBtnClick(sender: p.onoffBtn); s.end(); Timer.tick()
    expect(LightGroupControlCommandSender.commands == [.onOff(0xC000, false)], "Group OFF cancels pending dimming")

    let d = DevicePage(); d.controlPanelView.detailed = detailed; let ds = d.controlPanelView.active
    ds.begin(); ds.input(66); Timer.tick(); ds.end(); ds.sliderValueChanged()
    LightGroupControlCommandSender.commands = []
    d.onoffAction(sender: UIControl()); Timer.tick(); d.onoffAction(sender: UIControl()); Timer.tick()
    expect(LightGroupControlCommandSender.commands == [.onOff(2, false), .onOff(2, true)], "Device emits only OFF/ON")
    expect(d.node.isOn && d.node.lightness == Node.getLightness(lightness100: 66), "Device restores user brightness")
    ds.begin(); ds.input(53); LightGroupControlCommandSender.commands = []
    d.onoffAction(sender: UIControl()); ds.end(); Timer.tick()
    expect(LightGroupControlCommandSender.commands == [.onOff(2, false)], "Device OFF cancels pending dimming")
}
'''
swift += r'''
extension String { var localizedString: String { self } }
enum HDBZoneControlAction: Equatable { case auto, on, off, brightness(Int) }
class HDBService {
    var actions: [HDBZoneControlAction] = []
    func control(zoneId: Int, groupAddress: Address, action: HDBZoneControlAction) throws { actions.append(action) }
}
class HDBPage {
    var pageActive = true, brightnessEdited = false, requestedBrightness = 50
    var requestedControlKey: String?, requested: String?
    let zoneId = 1, groupAddress: Address = 0xC100
    let brightnessPanel = Panel(), service = HDBService()
    func updateRequestLabel() {}
    func showRequestFeedback(_ source: UIButton) {}
    func show(_ error: Error) {}
    func reload() {}
    init() {
'''
swift += "\n".join(block(hdb, marker) for marker in [
    "brightnessPanel.brightnessValueChanged =", "brightnessPanel.brightnessThrottleValueChanged ="])
swift += "\n}\n" + block(hdb, "private func send(_ action:") + "\n}\n"
swift += r'''
for action: HDBZoneControlAction in [.on, .off, .auto] {
    let p = HDBPage(), s: CustomDeviceSlider
    s = p.brightnessPanel.active
    s.begin(); s.input(66); Timer.tick()
    expect(p.service.actions == [.brightness(66)], "HDB real user dimming remains allowed")
    s.input(53); p.send(action); s.end(); s.sliderValueChanged(); Timer.tick()
    expect(p.service.actions == [.brightness(66), action] && !p.brightnessEdited, "HDB explicit control supersedes pending dimming")
    s.begin(); s.input(31); s.end()
    expect(p.service.actions.last == .brightness(31), "HDB permits next legitimate drag")
}
print("CustomDeviceSliderInteractionTests passed: \(checks) checks")
'''

with tempfile.TemporaryDirectory(prefix="slider-interaction-") as directory:
    path = Path(directory) / "main.swift"
    path.write_text(swift)
    binary = Path(directory) / "tests"
    subprocess.run(["swiftc", str(path), "-o", str(binary)], check=True)
    result = subprocess.run([str(binary)], capture_output=True, text=True)
    if baseline:
        assert result.returncode != 0 and "late valueChanged must not emit 1% after OFF" in result.stderr, result
        print("Baseline reproduced: " + result.stderr.strip())
    else:
        print(result.stdout, end="")
        if result.returncode:
            print(result.stderr, file=sys.stderr)
            sys.exit(result.returncode)
