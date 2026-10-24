#!/usr/bin/env python3
"""Exercise real page observation, trigger actions and member routing without UIKit.

UI boundaries verify lifecycle/dispatch behavior, not rendered layout or BLE.
"""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / "SunSmart/Main/Space/HDB/Controller/HDBLightingZoneDetailViewController.swift").read_text()

def block(start):
    opening = source.index("{", start)
    depth = 1
    end = opening + 1
    while depth:
        if source[end] == "{":
            depth += 1
        elif source[end] == "}":
            depth -= 1
        end += 1
    return opening, end

signature = "private func observeControlAvailability()"
if signature in source:
    opening, end = block(source.index(signature))
    registration = source[opening + 1:end - 1]
else:
    # The pre-fix page only registered a connection observer inside viewDidLoad.
    start = source.index("connectionObserver = MeshLibManager.manager.addGlobalConnectionObserver")
    _, end = block(start)
    registration = source[start:end]

def method(signature):
    start = source.index(signature)
    _, end = block(start)
    return source[start:end].replace("private func", "func", 1)


member_start = source.index("override func tableView(_ tableView: UITableView, didSelectRowAt")
member_opening, member_end = block(member_start)
member_selection = source[member_opening + 1:member_end - 1]

harness = r'''
import Foundation
enum Color { case secondaryLabel, bar }
let Bar_Color = Color.bar
extension String {
    var localizedString: String { self == "hdb_control_requested" ? "Requested: %@" : self }
}
final class Label { var text: String?; var textColor: Color = .secondaryLabel }
final class UIButton { var isSelected = false; var accessibilityValue: String? }
struct IndexPath { let row: Int; let section: Int }
final class Table {
    var updates = 0
    func beginUpdates() { updates += 1 }
    func endUpdates() {}
    func deselectRow(at: IndexPath, animated: Bool) {}
}
enum TestError: Error { case rejected }
final class Service {
    var isRunning = false, reject = false
    var sends: [(Int, UInt16, Bool)] = []
    func publishPresence(zoneId: Int, groupAddress: UInt16, detected: Bool) throws {
        if reject { throw TestError.rejected }
        sends.append((zoneId, groupAddress, detected))
    }
}
struct Member { let nodeUuid: Int }
struct HDBLightingZoneDeviceViewController {
    let nodeUuid: Int
    init(site: Int, space: Int, nodeUuid: Int) { self.nodeUuid = nodeUuid }
}
final class Navigation {
    var nodes: [Int] = []
    func pushViewController(_ page: HDBLightingZoneDeviceViewController, animated: Bool) { nodes.append(page.nodeUuid) }
}
let emergencyFireControllerManualControlStateDidChangeNotificationName = "emergencyFireControllerManualControlStateDidChangeNotification"
final class MeshLibManager {
    static let manager = MeshLibManager()
    var callback: ((Int, Bool) -> Void)?
    func addGlobalConnectionObserver(_ callback: @escaping (Int, Bool) -> Void) -> UUID {
        self.callback = callback; return UUID()
    }
}
final class Page {
    var pageActive = false
    var connectionObserver: UUID?
    var emergencyObserver: NSObjectProtocol?
    var refreshes = 0
    let zoneId = 7, groupAddress: UInt16 = 0xC123
    let site = 1, space = 1
    let service = Service(), tableView = Table()
    let navigationController: Navigation? = Navigation()
    var members = [Member(nodeUuid: 42)]
    var requestedPresence: Bool?
    var requested: String? = "On", requestedControlKey: String? = "on"
    var controlButtons = ["on": UIButton()]
    let requestLabel = Label(), triggerRequestLabel = Label()
    var feedback = 0, errors = 0
    func reload() { refreshes += 1 }
    func show(_ error: Error) { errors += 1 }
    func showRequestFeedback(_ button: UIButton) { feedback += 1 }
''' + method("private func publishPresence(") + "\n" + method("private func updateRequestLabel()") + r'''
    func select(_ indexPath: IndexPath) {
''' + member_selection + r'''
    }
    func observe() {
''' + registration + r'''
    }
}
let page = Page()
page.observe()
let event = Notification.Name("emergencyFireControllerManualControlStateDidChangeNotification")
NotificationCenter.default.post(name: event, object: nil)
precondition(page.refreshes == 0)
page.pageActive = true
NotificationCenter.default.post(name: event, object: nil)
precondition(page.refreshes == 1, "Emergency state changes must refresh the visible page")
page.pageActive = false
NotificationCenter.default.post(name: event, object: nil)
precondition(page.refreshes == 1, "A hidden page must not refresh")
page.pageActive = true
MeshLibManager.manager.callback?(0, true)
RunLoop.main.run(until: Date().addingTimeInterval(0.03))
precondition(page.refreshes == 2, "Connection recovery must refresh the visible page")
let button = UIButton()
page.updateRequestLabel()
let controlText = page.requestLabel.text
page.pageActive = false
page.publishPresence(true, source: button)
precondition(page.service.sends.isEmpty && page.requestedPresence == nil)
page.pageActive = true
for detected in [true, false] {
    page.publishPresence(detected, source: button)
    precondition(page.service.sends.last!.0 == 7 && page.service.sends.last!.1 == 0xC123)
    precondition(page.service.sends.last!.2 == detected && page.requestedPresence == detected)
    precondition(page.triggerRequestLabel.text == "Requested: " + (detected ? "hdb_publish_occupancy" : "hdb_publish_vacancy"))
    precondition(page.requestLabel.text == controlText && page.requestedControlKey == "on")
    precondition(page.controlButtons["on"]!.isSelected)
}
precondition(page.service.sends.count == 2 && page.feedback == 2 && page.tableView.updates == 2)
page.service.reject = true
page.publishPresence(true, source: button)
precondition(page.errors == 1 && page.requestedPresence == false && page.service.sends.count == 2)
precondition(page.feedback == 2 && page.tableView.updates == 2)
page.pageActive = false
page.select(IndexPath(row: 0, section: 3))
page.pageActive = true
for section in 0...2 { page.select(IndexPath(row: 0, section: section)) }
page.select(IndexPath(row: 1, section: 3))
page.service.isRunning = true
page.select(IndexPath(row: 0, section: 3))
precondition(page.navigationController!.nodes.isEmpty)
page.service.isRunning = false
page.select(IndexPath(row: 0, section: 3))
precondition(page.navigationController!.nodes == [42])
page.members = []
page.select(IndexPath(row: 0, section: 3))
precondition(page.navigationController!.nodes == [42])
print("PASS: visible-only observers and Presence actions; separate request feedback; rejection preserves last request; exact Members routing")
'''
with tempfile.TemporaryDirectory(prefix="hdb-observation-") as directory:
    path = Path(directory) / "main.swift"
    path.write_text(harness)
    binary = Path(directory) / "tests"
    subprocess.run(["swiftc", str(path), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
