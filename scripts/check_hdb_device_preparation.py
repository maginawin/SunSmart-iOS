#!/usr/bin/env python3
"""Run production HDB preparation/ownership policy behavior; no BLE or cloud."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
sources = [
    "SunSmart/Common/Data/HDBConfiguration.swift",
    "SunSmart/Common/Data/HDBLightingZonePolicy.swift",
    "SunSmart/Common/Data/HDBDevicePreparationPolicy.swift",
    "Tests/HDB/HDBDevicePreparationTests.swift",
]
with tempfile.TemporaryDirectory(prefix="hdb-device-preparation-") as directory:
    binary = str(Path(directory) / "tests")
    subprocess.run(["swiftc", "-parse-as-library", *[str(ROOT / p) for p in sources], "-o", binary], check=True)
    subprocess.run([binary], check=True)

# The shared add/Store fixtures use production context/planner/coordinator with
# SDK persistence/radio boundaries doubled; the Session suite covers transport lifecycle.
for mode in ["--device-sync", "--device-tasks", "--add-completion", "--add-execution", "--subelement"]:
    subprocess.run(["python3", str(ROOT / "scripts/check_hdb_integration.py"), mode], check=True)
