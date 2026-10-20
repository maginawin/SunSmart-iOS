#!/usr/bin/env python3
"""Run actual HDB control and shared sender against SDK/database/cloud boundaries."""
from pathlib import Path
import subprocess
import tempfile
from hdb_publication_test_source import with_publication_policy

ROOT = Path(__file__).resolve().parents[1]
files = [
    "SunSmart/Common/Data/HDBConfiguration.swift",
    "SunSmart/Common/Data/HDBLightingZonePolicy.swift",
    "SunSmart/Common/Data/HDBConfigurationStore.swift",
    "SunSmart/Common/Data/HDBConfigurationStore+Mesh.swift",
    "SunSmart/Common/Data/LightGroupControlCommandSender.swift",
    "SunSmart/Main/Space/Model/SyncRunLifecycle.swift",
    "SunSmart/Main/Space/Model/SyncSessionCoordinator.swift",
    "SunSmart/Main/Space/HDB/Model/HDBLightingZoneExecutor.swift",
    "SunSmart/Main/Space/HDB/Model/HDBLightingZoneService.swift",
    "Tests/HDB/HDBTestBoundaries.swift",
    "Tests/HDB/HDBMeshTestBoundaries.swift",
    "Tests/HDB/HDBControlTestBoundaries.swift",
    "Tests/HDB/HDBZoneControlTests.swift",
]
files += ["SunSmart/Common/Data/HDBLightingConfigurationPolicy.swift", "SunSmart/Common/Data/HDBDevicePreparationPolicy.swift", "SunSmart/Main/Space/HDB/Model/HDBDeviceSyncContext.swift", "Tests/HDB/HDBDeviceSyncTestBoundaries.swift"]
with tempfile.TemporaryDirectory(prefix="hdb-control-") as directory:
    harness = Path(directory) / "Harness.swift"
    harness.write_text(with_publication_policy("enum HDBLightingError: Error { case notPrepared }\n" + "\n".join((ROOT / f).read_text().replace("import NordicSigMeshSDK", "") for f in files) + "\n" + (ROOT / "SunSmart/Main/Space/HDB/Model/HDBDeviceSyncService.swift").read_text().split("/// A task owns")[0].replace("import NordicSigMeshSDK", ""), ROOT))
    binary = Path(directory) / "tests"
    subprocess.run(["swiftc", "-parse-as-library", str(harness), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
