#!/usr/bin/env python3
"""Run actual HDB control and shared sender against SDK/database/cloud boundaries."""
from pathlib import Path
import subprocess
import tempfile
from hdb_publication_test_source import with_publication_policy

ROOT = Path(__file__).resolve().parents[1]


def block(text, start):
    offset = text.index(start)
    opening = text.index("{", offset)
    depth = 1
    for index in range(opening + 1, len(text)):
        depth += (text[index] == "{") - (text[index] == "}")
        if depth == 0:
            return text[offset:index + 1]
    raise ValueError(f"Unclosed Swift block: {start}")


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
    "SunSmart/Common/Data/HDBLightingConfigurationPolicy.swift",
    "SunSmart/Main/Space/HDB/Model/HDBLightingConfigurationService.swift",
    "Tests/HDB/HDBLightingTransportBoundaries.swift",
    "Tests/HDB/HDBLightingConfigurationServiceTests.swift",
]
files += ["SunSmart/Common/Data/HDBDevicePreparationPolicy.swift", "SunSmart/Main/Space/HDB/Model/HDBDeviceSyncContext.swift", "Tests/HDB/HDBDeviceSyncTestBoundaries.swift"]

with tempfile.TemporaryDirectory(prefix="hdb-control-") as directory:
    harness = Path(directory) / "Harness.swift"
    source = "\n".join((ROOT / f).read_text().replace("import NordicSigMeshSDK", "") for f in files)
    source += "\n" + (ROOT / "SunSmart/Main/Space/HDB/Model/HDBDeviceSyncService.swift").read_text().split("/// A task owns")[0].replace("import NordicSigMeshSDK", "")
    # Exercise the production binding check; the transport/database remain boundaries.
    model = "    static func model("
    production = (ROOT / "SunSmart/Main/Space/HDB/Model/HDBLightingMessages.swift").read_text()
    source = source.replace(block(source, model), block(production, model), 1)
    harness.write_text(with_publication_policy(source, ROOT))
    binary = Path(directory) / "tests"
    subprocess.run(["swiftc", "-parse-as-library", str(harness), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
