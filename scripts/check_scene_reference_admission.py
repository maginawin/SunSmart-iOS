#!/usr/bin/env python3
"""Exercise real Scene-reference admission and switch publication methods at controlled boundaries."""
from pathlib import Path
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True
from check_scene_configuration import ROOT, function

source = (ROOT / "Tests/Scene/SceneReferenceAdmissionTests.swift").read_text()
for placeholder, relative, markers in [
    ("// PRODUCTION_GROUP_SAVE", "SunSmart/Main/Group/Switch/Controller/GroupSwitchsViewController.swift",
     ["    private func syncRealSwitchData(copySwitch:"]),
    ("// PRODUCTION_MONITOR_SAVE", "SunSmart/Main/Device/Device1.5/NEightKeySwitches/ViewModel/PJEightKeySwitchMonitorViewModel.swift",
     ["    func persist()"]),
    ("// PRODUCTION_SYNC_ADMISSION", "SunSmart/Main/Space/Controller/SyncDevicesViewController.swift",
     ["    private func permitsSceneReferences()"]),
    ("// PRODUCTION_POWER_MESSAGES", "SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/BatteryPowerSwitchAddConfiguration.swift",
     ["    static func defaultConfigurationMessageHandles(", "    static func linkedConfigurationMessageHandles("]),
]:
    production = (ROOT / relative).read_text()
    source = source.replace(placeholder, "\n".join(function(production, marker) for marker in markers))

with tempfile.TemporaryDirectory(prefix="scene-reference-admission-") as directory:
    temporary = Path(directory)
    harness = temporary / "Tests.swift"
    harness.write_text(source)
    executable = temporary / "Tests"
    subprocess.run(["swiftc", "-parse-as-library", str(harness), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
