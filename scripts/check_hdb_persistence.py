#!/usr/bin/env python3
"""Compile and exercise the production HDB value policies without Mesh or cloud."""
from pathlib import Path
import subprocess
import tempfile
import sys
sys.dont_write_bytecode = True
from hdb_recovery_test_source import recovery_mesh_source
ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="hdb-tests-") as directory:
    binary = str(Path(directory) / "tests")
    cache = Path.home() / "Library/Developer/Xcode/ModuleCache.noindex/HDBTests"
    cache.mkdir(parents=True, exist_ok=True)
    sources = ["SunSmart/Common/Data/HDBConfiguration.swift", "SunSmart/Common/Data/HDBLightingZonePolicy.swift", "SunSmart/Common/Data/HDBConfigurationStore.swift", "SunSmart/Common/Data/SpaceConfigurationIntegrityPolicy.swift", "Tests/HDB/HDBTestBoundaries.swift", "Tests/HDB/HDBPersistenceTests.swift"]
    mesh = Path(directory) / "RecoveryMesh.swift"
    mesh.write_text(recovery_mesh_source(ROOT))
    subprocess.run(["swiftc", "-module-cache-path", str(cache), "-parse-as-library", *[str(ROOT / path) for path in sources], str(mesh), "-o", binary], check=True)
    subprocess.run([binary, str(Path(directory) / "hdb.sqlite")], check=True)
