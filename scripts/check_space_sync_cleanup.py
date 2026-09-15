#!/usr/bin/env python3
"""运行完整快照清理策略，不连接云端或设备。"""
from pathlib import Path
import subprocess
import tempfile
ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="space-sync-cleanup-") as directory:
    binary = str(Path(directory) / "tests")
    files = ["SunSmart/Common/Data/SpaceConfigurationIntegrityPolicy.swift",
             "SunSmart/Main/Group/Model/ProximityLightingTopologyPolicy.swift",
             "SunSmart/Main/Group/Model/ProximityLightingTopologyReconciler.swift",
             "SunSmart/Common/Data/SpaceSyncCleanupPolicy.swift",
             "Tests/Group/SpaceSyncCleanupPolicyTests.swift"]
    subprocess.run(["swiftc", "-parse-as-library", *[str(ROOT / file) for file in files], "-o", binary], check=True)
    subprocess.run([binary], check=True)
