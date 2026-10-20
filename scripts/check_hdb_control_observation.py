#!/usr/bin/env python3
"""Execute the detail page's real observation registration with Foundation notifications."""
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

harness = r'''
import Foundation
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
    func reload() { refreshes += 1 }
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
print("PASS: real page notification registration refreshes on emergency/connection recovery only while visible")
'''
with tempfile.TemporaryDirectory(prefix="hdb-observation-") as directory:
    path = Path(directory) / "main.swift"
    path.write_text(harness)
    binary = Path(directory) / "tests"
    subprocess.run(["swiftc", str(path), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
