import Foundation
import CoreGraphics

// Run the real controller edit/apply method, draft selection and SDK display policy.
// UIKit layout and BLE transport are boundaries; visual/radio acceptance is separate.
// SDK_CONTROL_PAGE
enum NodeAbsoluteCctRange { static let defaultRange: ClosedRange<UInt16> = 2700...6500 }
final class Node {
    var companyIdentifier: UInt16? = 0x0A78, productIdentifier: UInt16? = 0x2132
    var changeControlPage: NodeChangeControlPage?
    var rawSupportCct = true, state = true
    var name: String? = "Lamp", lightnessModel: Int? = 1
    var lightnessRange: ClosedRange<UInt16> = 0...65535
    var effectiveCctRange = NodeAbsoluteCctRange.defaultRange
    // SDK_NODE_PROPERTIES
}
extension SceneParameters {
    // PRODUCTION_RESOLVE
}
enum SceneDevicesSelectionView {
    // PRODUCTION_SUMMARY
}

// Minimal UIKit/SnapKit surface needed to execute the unchanged editor method.
final class EditingConstraints {
    var top: EditingConstraints { self }; var bottom: EditingConstraints { self }
    var left: EditingConstraints { self }; var right: EditingConstraints { self }; var height: EditingConstraints { self }
    @discardableResult func equalTo<T>(_ value: T) -> EditingConstraints { self }
    @discardableResult func lessThanOrEqualTo<T>(_ value: T) -> EditingConstraints { self }
    @discardableResult func equalToSuperview() -> EditingConstraints { self }
    @discardableResult func offset(_ value: Int) -> EditingConstraints { self }
    @discardableResult func inset(_ value: Int) -> EditingConstraints { self }
    func makeConstraints(_ body: (EditingConstraints) -> Void) { body(self) }
    func remakeConstraints(_ body: (EditingConstraints) -> Void) { body(self) }
}
class EditingView {
    let snp = EditingConstraints()
    var window: Int? = 1
    func addSubview(_ view: EditingView) {}
}
final class CustomSegmentedControl: EditingView {
    var selectedIndex = 0, delegate: SceneRelayLiveControl?
    init(frame: CGRect, titles: [String]) {}
}
final class SceneRelayLiveControl { init(_ body: @escaping (Bool) -> Void) {} }
final class SRAlertView {
    struct Action {
        enum Style { case cancel }
        let title: String
        var style: Style? = nil
        let actionHandler: (Int) -> Void
    }
    let contentView = EditingView(), titleLabel = EditingView(), messageLabel = EditingView(), hLineView = EditingView()
    let actions: [Action]
    init(title: String?, message: String, tapBackgroundHide: Bool, contentMinHeight: Int, actions: [Action]) { self.actions = actions }
    func show() {}
    func removeFromSuperview() {}
}
final class SceneExecuteDataPickerView {
    enum LiveEvent { case lightness(Int, ended: Bool), temperature(Int, ended: Bool), off, cancel }
    final class Slider { var value = 0 }
    var lightnessSliderView = Slider(), cctSliderView: Slider!
    var cct = 0, showCct = true, cctRange = NodeAbsoluteCctRange.defaultRange
    var pickerCallback: ((Bool, Int, Int) -> Void)?
    static func show(lightness: Int, isOn: Bool, cct: Int, lightnessLimitRange: ClosedRange<Int>, cctRange: ClosedRange<UInt16>,
                     showCct: Bool, showDelete: Bool, liveControl: ((LiveEvent) -> Void)?, picker: @escaping (Bool, Int, Int) -> Void) -> SceneExecuteDataPickerView {
        let sheet = SceneExecuteDataPickerView()
        sheet.showCct = showCct; sheet.cct = cct; sheet.cctRange = cctRange; sheet.pickerCallback = picker
        sheet.lightnessSliderView.value = isOn ? min(lightnessLimitRange.upperBound, lightness) : 0
        if showCct { sheet.cctSliderView = Slider(); sheet.cctSliderView.value = min(Int(cctRange.upperBound), max(Int(cctRange.lowerBound), cct)) }
        return sheet
    }
    func cancel() { pickerCallback = nil }
    func finishLiveInteraction() {}
    func dismiss() { pickerCallback = nil }
    // PRODUCTION_PICKER
}
final class SceneDeviceParameterEditingHarness {
    final class Devices {
        var nodes: [TimedSchedulerNodeIdentity: Node] = [:]
        func node(for identity: TimedSchedulerNodeIdentity) -> Node? { nodes[identity] }
    }
    final class Coordinator { var committedNumber: Int? }
    let devicesView = Devices(), coordinator = Coordinator()
    var selection: SceneDraftSelection?, picker: SceneExecuteDataPickerView?, alert: SRAlertView?
    var viewIfLoaded: EditingView? = EditingView()
    var lifecycle = UUID(), busy = false, active = true, changes = 0
    var relayLiveControl: SceneRelayLiveControl?
    init(_ members: [SceneDeviceMember], nodes: [TimedSchedulerNodeIdentity: Node]) throws {
        selection = SceneDraftSelection(draft: try SceneDraft(scope: .init(meshUUID: "mesh", networkID: "net"), name: "Scene", imageId: 1,
                                                            kind: .devices, deviceMembers: members))
        devicesView.nodes = nodes
    }
    func stopDeviceLiveControl() {}
    func makeDeviceLiveControl(_ target: SceneDeviceSettingsTarget) -> ((SceneExecuteDataPickerView.LiveEvent) -> Void)? { nil }
    func draftChanged() { changes += 1 }
    func failed(_ error: Error) { preconditionFailure("Unexpected edit failure: \(error)") }
    // PRODUCTION_EDIT_DEVICES
}

func runSceneDeviceParameterEditingTests() throws {
    var checks = 0
    func check(_ value: @autoclosure () -> Bool, _ message: String) { precondition(value(), message); checks += 1 }
    func identity(_ index: Int) -> TimedSchedulerNodeIdentity {
        .init(nodeUUID: String(format: "00000000-0000-0000-0000-%012d", index), unicastAddress: String(format: "%04X", index),
              deviceKeyFingerprint: String(repeating: "A", count: 64))
    }
    let a = identity(1), b = identity(2), c = identity(3)
    func member(_ identity: TimedSchedulerNodeIdentity, _ cct: UInt16) -> SceneDeviceMember {
        .init(identity: identity, parameters: .init(isOn: true, lightness: 32768, cct: cct))
    }
    func value(_ page: SceneDeviceParameterEditingHarness, _ id: TimedSchedulerNodeIdentity) -> SceneParameters {
        page.selection!.draft.deviceMembers.first { $0.identity == id }!.parameters
    }
    for (product, preference, hardware, expected) in [
        (UInt16(0x2132), NodeChangeControlPage.singleWhite as NodeChangeControlPage?, true, false),
        (0x2132, .tunableWhite, true, true), (0x2132, .tunableWhite, false, false),
        (0x2132, nil, true, true), (0x2013, nil, true, false), (0x24B1, nil, true, false),
        (0x2134, nil, true, false), (0x2134, .tunableWhite, true, true)
    ] {
        let node = Node(); node.productIdentifier = product; node.changeControlPage = preference; node.rawSupportCct = hardware
        let original: UInt16 = hardware ? 5100 : 0
        let page = try SceneDeviceParameterEditingHarness([member(a, original)], nodes: [a: node])
        check(SceneDevicesSelectionView.summary(value(page, a), node: node) == (expected ? "50% · \(original)K" : "50%"),
              "device row uses hardware, preference and product default")
        page.editDevices(.device(a))
        let sheet = page.picker!
        check(sheet.showCct == expected, "display uses hardware, preference and product default")
        sheet.shadeViewAction()
        check(value(page, a).cct == original && value(page, a).lightness == 32768, "closing without input preserves CCT and exact brightness units")
    }
    let hidden = Node(), visible = Node(), untouched = Node()
    hidden.changeControlPage = .singleWhite; hidden.effectiveCctRange = 1000...10000
    visible.changeControlPage = .tunableWhite
    let members = [member(a, 5100), member(b, 3000), member(c, 6000)]
    let page = try SceneDeviceParameterEditingHarness(members, nodes: [a: hidden, b: visible, c: untouched])
    page.editDevices(.category([a, b]))
    check(page.picker!.showCct && page.picker!.selectedCct == 3000, "first visible member supplies mixed-category CCT")
    check(page.picker!.cctRange == 2700...6500, "hidden member cannot widen the editor range")
    page.picker!.lightnessSliderView.value = 60; page.picker!.cctSliderView.value = 4000
    page.picker!.shadeViewAction()
    check(value(page, a).cct == 5100 && value(page, b).cct == 4000, "mixed batch preserves each hidden member's CCT")
    check(value(page, a).lightness == Node.getLightness(lightness100: 60) && value(page, b).lightness == value(page, a).lightness, "both batch members accept brightness")
    check(value(page, c) == members[2].parameters, "unselected or filtered-out member remains unchanged")
    visible.changeControlPage = .singleWhite
    page.editDevices(.category([a, b]))
    check(!page.picker!.showCct, "all-hidden batch has no temperature editor")
    page.picker!.lightnessSliderView.value = 0; page.picker!.shadeViewAction()
    check(!value(page, a).isOn && !value(page, b).isOn && value(page, a).cct == 5100 && value(page, b).cct == 4000, "OFF preserves distinct hidden CCTs")

    let offline = Node(); offline.state = false; offline.changeControlPage = .singleWhite
    offline.effectiveCctRange = 3000...5000
    let offlinePage = try SceneDeviceParameterEditingHarness([member(a, 6500)], nodes: [a: offline])
    offlinePage.editDevices(.device(a)); offlinePage.picker!.lightnessSliderView.value = 70; offlinePage.picker!.shadeViewAction()
    check(value(offlinePage, a).cct == 6500, "offline hidden CCT is preserved even outside the current range")
    check(SceneDevicesSelectionView.summary(value(offlinePage, a), node: offline) == "70%", "offline single-white row hides stored CCT")
    let missingPage = try SceneDeviceParameterEditingHarness([member(a, 4500)], nodes: [:])
    missingPage.editDevices(.device(a)); missingPage.picker!.lightnessSliderView.value = 70; missingPage.picker!.shadeViewAction()
    check(value(missingPage, a).cct == 4500 && !missingPage.picker!.showCct, "unresolved identity preserves its CCT")

    for initiallyVisible in [false, true] {
        let node = Node(); node.changeControlPage = initiallyVisible ? .tunableWhite : .singleWhite
        let changing = try SceneDeviceParameterEditingHarness([member(a, 4500)], nodes: [a: node])
        changing.editDevices(.device(a))
        let callback = changing.picker!.pickerCallback!
        node.changeControlPage = initiallyVisible ? .singleWhite : .tunableWhite
        check(SceneDevicesSelectionView.summary(value(changing, a), node: node) == (initiallyVisible ? "50%" : "50% · 4500K"),
              "row refresh reads the current control-page preference")
        callback(true, 80, 5500)
        check(value(changing, a).cct == 4500, "both open-time and commit-time CCT eligibility are required")
        changing.editDevices(.device(a))
        check(changing.picker!.showCct == !initiallyVisible, "reopening reads the current preference")
    }
    let node = Node(); node.changeControlPage = .tunableWhite; node.effectiveCctRange = 3000...5000
    let constrained = try SceneDeviceParameterEditingHarness([member(a, 4000)], nodes: [a: node])
    constrained.editDevices(.device(a))
    check(constrained.picker!.cctRange == 3000...5000, "single-device range remains device-specific")
    constrained.picker!.pickerCallback!(true, 50, 6500)
    check(value(constrained, a).cct == 5000, "editable CCT is clamped by the device")
    constrained.editDevices(.device(a)); let old = constrained.picker!.pickerCallback!
    constrained.editDevices(.device(a)); old(true, 50, 3000)
    check(value(constrained, a).cct == 5000, "superseded popup cannot overwrite the new editor")
    let late = constrained.picker!.pickerCallback!; constrained.lifecycle = UUID(); late(true, 50, 3000)
    check(value(constrained, a).cct == 5000, "exited lifecycle rejects late popup callback")
    constrained.editDevices(.device(a)); let removedNode = constrained.picker!.pickerCallback!
    constrained.devicesView.nodes[a] = nil; removedNode(true, 50, 3000)
    check(value(constrained, a).cct == 5000, "node lost during editing preserves old CCT")

    let selected = page.selection!
    let candidate = SceneDraftSelection.Candidate(identity: a, name: "Lamp", category: "Room", categoryID: 1, canAdd: true, defaults: member(a, 4500).parameters)
    try selected.setSelected(candidate, selected: false); try selected.setSelected(candidate, selected: true)
    check(value(page, a).cct == 5100, "remove and reselect retains hidden CCT after editing")
    let selectionPage = SceneSelectionEntryHarness(selection: selected)
    selectionPage.selectDevices(); selectionPage.navigationController!.topViewController!.closeAction()
    check(selected === selectionPage.selection && value(page, a).cct == 5100, "selection-page return retains shared parameters")
    let encoded = try SceneConfiguration(kind: .devices, name: "Roundtrip", deviceMembers: selected.draft.deviceMembers).encoded()
    let decoded = try SceneConfiguration.decode(encoded)
    check(decoded.deviceMembers == selected.draft.deviceMembers, "serialization retains mixed CCT values")
    let relay = Node(); relay.lightnessModel = nil
    let on = member(a, 4500).parameters
    let off = SceneParameters(isOn: false, lightness: 32768, cct: 4500)
    check(SceneDevicesSelectionView.summary(on, node: relay) == "ON", "relay row remains ON")
    check(SceneDevicesSelectionView.summary(off, node: node) == "OFF", "off row remains OFF")
    check(SceneDevicesSelectionView.summary(on, node: nil) == "ON", "missing device retains existing summary fallback")
    print("device parameter editing: \(checks) passed")
}
