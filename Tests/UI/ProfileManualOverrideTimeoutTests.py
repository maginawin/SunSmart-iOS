"""Run the production Timeout view's value/interaction logic on the host.

Only UIKit construction, layout and the UISlider backend are replaced. The
actual CustomDeviceSlider.value getter/setter and Timeout event handlers run.
This is a numeric/interaction contract test, not UIKit or device acceptance.
Use --baseline to demonstrate the original failure against HEAD.
"""

from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
VIEW = "SunSmart/Main/Profile/View/ProfileManualOverrideTimeoutView.swift"
source = (subprocess.check_output(["git", "show", f"HEAD:{VIEW}"], cwd=ROOT, text=True)
          if "--baseline" in sys.argv else (ROOT / VIEW).read_text())
slider_source = (ROOT / "SunSmart/Common/View/CustomDeviceSlider.swift").read_text()


def block(text, marker):
    start = text.index(marker)
    opening = text.index("{", start)
    end, depth = opening + 1, 1
    while depth:
        depth += (text[end] == "{") - (text[end] == "}")
        end += 1
    return text[start:end]


# Keep behavioral slider configuration from setupUI; only remove image/layout work.
setup = block(source, "private func setupUI()")
config = setup[setup.index("slider = CustomDeviceSlider()"):
               setup.index("contentView.addSubview(slider)")]
config = "\n".join(line for line in config.splitlines()
                   if not any(word in line for word in ["setThumbImage", "TintColor", "cornerRadius"]))
source = source.replace(setup, """private func setupUI() {
    valueLabel = UILabel(); enableSwitch = UISwitch(); enableSwitchBtn = UIButton()
    addBtn = UIButton(); minusBtn = UIButton()
""" + config + "\n}")
source = source.replace(block(source, "override init(frame: CGRect)"), """override init() {
    super.init()
    setData()
    setupUI()
    updateUI()
}""")
source = source.replace(block(source, "required init?(coder: NSCoder)"), "")
source = source.replace("import UIKit", "").replace("@objc ", "").replace("private ", "")

stubs = r"""
import Foundation
class UIView { init() {} }
class UILabel { var text: String? }
class UIButton { var isEnabled = true }
class UISwitch { var isOn = true }
var language = "en"
extension String {
    var localizedString: String {
        if self == "sec" { return language == "zh" ? "秒" : "sec" }
        if self == "infinite" { return language == "zh" ? "无限" : "Infinite" }
        return self
    }
}
protocol CustomDeviceSliderDelegate: AnyObject {
    func slider(_ slider: CustomDeviceSlider, valueChanged value: Float, ended: Bool)
    func slider(_ slider: CustomDeviceSlider, canEditChanged value: Float) -> Bool
}
class UISlider {
    var minimumValue: Float = 0; var maximumValue: Float = 61
    var isEnabled = true
    var backend = 0
    var rawValue: Float = 10
    var value: Float {
        get {
            switch backend {
            case 1: return rawValue > minimumValue ? rawValue.nextDown : rawValue
            case 2: return rawValue < maximumValue ? rawValue.nextUp : rawValue
            case 3: return (rawValue / maximumValue) * maximumValue
            default: return rawValue
            }
        }
        set { rawValue = min(maximumValue, max(minimumValue, newValue)) }
    }
}
class CustomDeviceSlider: UISlider {
    var step: Int?; var limitRange: ClosedRange<Int>?
    var isSliding = false; var throttle = false; var sendsFinalValueOnTouchCancel = false
    weak var delegate: CustomDeviceSliderDelegate?
"""
stubs += block(slider_source, "override var value: Float") + "\n}\n"

tests = r"""
final class Spy: ProfileManualOverrideTimeoutViewDelegate {
    var values: [UInt32] = []; var rejected = 0
    func timeoutViewHelpAction(view: ProfileManualOverrideTimeoutView) {}
    func timeoutViewDisableEditAction(view: ProfileManualOverrideTimeoutView) { rejected += 1 }
    func view(_ view: ProfileManualOverrideTimeoutView, timeoutValueChanged second: UInt32) {
        values.append(second)
    }
}
var checks = 0
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
    checks += 1
}
let choices: [UInt32] = [5] + (1...60).map { UInt32($0 * 60) } + [.max]
func label(_ seconds: UInt32) -> String {
    if seconds == .max { return "infinite".localizedString }
    if seconds == 5 { return "5 s" }
    if seconds <= 3600 && seconds % 60 == 0 && seconds > 0 { return "\(seconds / 60) min" }
    return "\(seconds) \("sec".localizedString)"
}
func fixture(_ backend: Int = 0) -> (ProfileManualOverrideTimeoutView, Spy) {
    let view = ProfileManualOverrideTimeoutView(); let spy = Spy()
    view.delegate = spy; view.slider.backend = backend
    return (view, spy)
}
func begin(_ view: ProfileManualOverrideTimeoutView) {
    expect(view.slider(view.slider, canEditChanged: view.slider.value), "editable drag")
    view.slider.isSliding = true
}
func drag(_ view: ProfileManualOverrideTimeoutView, _ value: Float, ended: Bool = false) {
    view.slider.rawValue = value
    view.slider.isSliding = !ended
    view.slider(view.slider, valueChanged: value, ended: ended)
}

// Reload and every adjacent button pair, with four independent Float backends.
let (reopened, reopenedSpy) = fixture(3)
reopened.second = 60
expect(reopened.valueLabel.text == "1 min" && reopened.second == 60 && reopenedSpy.values.isEmpty,
       "60-second reload must show 1 min despite Float normalization")
for backend in 0...3 {
    for (index, seconds) in choices.enumerated() {
        let (view, spy) = fixture(backend)
        view.second = seconds
        expect(view.second == seconds && view.valueLabel.text == label(seconds), "reload \(seconds), backend \(backend)")
        expect(spy.values.isEmpty, "loading must not edit the Profile")
        expect(view.enableSwitch.isOn == (seconds != .max), "switch follows model")
        expect(view.slider.isEnabled == (seconds != .max), "infinite disables idle slider")
        if seconds != .max {
            view.addBtnClick()
            expect(view.second == choices[index + 1] && spy.values.last == choices[index + 1], "plus advances exactly one option")
            expect(view.valueLabel.text == label(choices[index + 1]), "plus label matches callback")
            view.second = seconds; spy.values.removeAll()
            view.minusBtnClick()
            expect(view.second == choices[max(0, index - 1)], "minus advances exactly one option")
            expect(index == 0 ? spy.values.isEmpty : spy.values == [choices[index - 1]], "minimum is a no-op")
        }
    }
}

// Both sides of every integer, midpoint rounding, endpoint clamping, repeated events.
for index in 0...61 {
    for raw in [Float(index).nextDown, Float(index), Float(index).nextUp] {
        let (view, spy) = fixture()
        view.second = 90; begin(view); drag(view, raw); drag(view, raw, ended: true)
        expect(view.second == choices[index] && spy.values == [choices[index]], "rounded option emitted once")
        expect(view.valueLabel.text == label(choices[index]), "drag label matches model")
    }
}
for (raw, expected): (Float, UInt32) in [(-100, 5), (0.49, 5), (0.5, 60), (60.49, 3600), (60.5, .max), (100, .max)] {
    let (view, _) = fixture(); begin(view); drag(view, raw); drag(view, raw, ended: true)
    expect(view.second == expected, "half-step and clamp \(raw)")
}
let (moving, movingSpy) = fixture()
begin(moving); drag(moving, 61)
expect(moving.second == .max && moving.slider.isEnabled, "infinite must not trap an active drag")
drag(moving, 60); drag(moving, 60, ended: true)
expect(moving.second == 3600 && moving.enableSwitch.isOn, "drag back from infinite")
begin(moving); drag(moving, 61); drag(moving, 61, ended: true)
expect(!moving.slider.isEnabled && !moving.enableSwitch.isOn, "release/cancel at infinite disables slider")
expect(moving.slider.sendsFinalValueOnTouchCancel, "cancel participates in finalization")
moving.enableSwitchBtnAction()
expect(moving.second == 600 && movingSpy.values.last == 600, "enable restores ten minutes")
moving.enableSwitchBtnAction()
expect(moving.second == .max && movingSpy.values.last == .max, "disable uses infinite sentinel")

// Non-preset data survives reload, no-motion release/cancel and unrelated editing.
for locale in ["en", "zh"] {
    language = locale
    for (seconds, previous, next): (UInt32, UInt32, UInt32) in [
        (0, 0, 5), (1, 1, 5), (30, 5, 60), (90, 60, 120),
        (3601, 3600, .max), (3660, 3600, .max), (.max - 1, 3600, .max)
    ] {
        let (view, spy) = fixture(3); view.second = seconds
        expect(view.second == seconds && view.valueLabel.text == label(seconds), "custom value exact/localized")
        begin(view); drag(view, view.slider.value, ended: true)
        expect(view.second == seconds && spy.values.isEmpty, "no-motion release/cancel preserves custom value")
        view.addBtnClick()
        expect(view.second == next && spy.values == [next], "custom plus selects strictly larger preset")
        view.second = seconds; spy.values.removeAll(); view.minusBtnClick()
        expect(view.second == previous, "custom minus selects strictly smaller preset")
        expect(previous == seconds ? spy.values.isEmpty : spy.values == [previous], "no smaller preset preserves value")
    }
}
let (readonly, readonlySpy) = fixture()
readonly.second = 90; readonly.editable = false
readonly.addBtnClick(); readonly.minusBtnClick(); readonly.enableSwitchBtnAction()
readonly.enableSwitch.isOn = false; readonly.enableSwitchValueChanged(sender: readonly.enableSwitch)
expect(!readonly.slider(readonly.slider, canEditChanged: 1), "readonly cannot begin tracking")
readonly.slider(readonly.slider, valueChanged: 1, ended: false)
expect(readonly.second == 90 && readonlySpy.values.isEmpty && readonly.enableSwitch.isOn, "all readonly paths preserve model")
expect(readonlySpy.rejected == 6, "readonly actions report disabled editing")
let (invalid, invalidSpy) = fixture()
begin(invalid)
for value: Float in [.nan, .infinity, -.infinity] { drag(invalid, value) }
expect(invalid.second == 600 && invalidSpy.values.isEmpty, "non-finite samples cannot index options")
print("ProfileManualOverrideTimeoutTests passed: \(checks) checks (UIKit/device behavior not exercised)")
"""

with tempfile.TemporaryDirectory(prefix="profile-timeout-tests-") as folder:
    path = Path(folder) / "main.swift"
    path.write_text(stubs + source + tests)
    binary = Path(folder) / "tests"
    subprocess.run(["swiftc", "-module-cache-path", "/tmp/sunsmart-profile-analysis-module-cache",
                    str(path), "-o", str(binary)], check=True)
    if "--baseline" in sys.argv:
        result = subprocess.run([str(binary)], capture_output=True, text=True)
        assert result.returncode != 0 and "60-second reload" in result.stderr, result
        print("Baseline reproduced: " + result.stderr.strip())
    else:
        subprocess.run([str(binary)], check=True)
