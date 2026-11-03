#!/usr/bin/env python3
"""Run actual Scene list/detail deletion methods with deterministic UI/server boundaries."""
from pathlib import Path
import subprocess
import tempfile
import sys

sys.dont_write_bytecode = True
from check_scene_configuration import ROOT, function

with tempfile.TemporaryDirectory(prefix="scene-deletion-ui-") as directory:
    temporary = Path(directory)
    source = (ROOT / "Tests/Scene/SceneDeletionUITests.swift").read_text()
    for placeholder, controller, markers in [
        ("// PRODUCTION_DETAIL_METHODS", "SceneViewController", ["    private func deleteScene()", "    private func pushToSyncDevicesVc()"]),
        ("// PRODUCTION_LIST_METHODS", "ScenesViewController", ["    private func deleteScene(scene:", "    private func pushToSyncDevicesVc(scene:"]),
    ]:
        production = (ROOT / f"SunSmart/Main/Scene/Controller/{controller}.swift").read_text()
        source = source.replace(placeholder, "\n".join(function(production, marker) for marker in markers))
    harness = temporary / "SceneDeletionUITests.swift"
    harness.write_text(source)
    executable = temporary / "Tests"
    subprocess.run(["swiftc", "-parse-as-library", str(harness), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
