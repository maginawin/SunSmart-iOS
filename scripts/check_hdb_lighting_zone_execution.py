#!/usr/bin/env python3
"""Compile and exercise the production HDB value policies without Mesh or cloud."""
from pathlib import Path
import subprocess
import tempfile
ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="hdb-tests-") as directory:
    binary = str(Path(directory) / "tests")
    cache = Path.home() / "Library/Developer/Xcode/ModuleCache.noindex/HDBTests"
    cache.mkdir(parents=True, exist_ok=True)
    sources = ["SunSmart/Common/Data/HDBConfiguration.swift", "SunSmart/Common/Data/HDBLightingZonePolicy.swift", "SunSmart/Main/Space/Model/SyncRunLifecycle.swift", "SunSmart/Main/Space/Model/SyncSessionCoordinator.swift", "SunSmart/Main/Space/HDB/Model/HDBLightingZoneExecutor.swift", "Tests/HDB/HDBLightingZoneExecutorTests.swift"]
    subprocess.run(["swiftc", "-module-cache-path", str(cache), "-parse-as-library", *[str(ROOT / path) for path in sources], "-o", binary], check=True)
    subprocess.run([binary], check=True)
