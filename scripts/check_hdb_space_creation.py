#!/usr/bin/env python3
"""Run real Site creation, HDB Store and normal Space deletion with DB/SDK/cloud doubles.
Does not prove actual SQLite durability, cloud upload or firmware behavior.
"""
from pathlib import Path
import subprocess
import tempfile
from hdb_publication_test_source import with_publication_policy
ROOT = Path(__file__).resolve().parents[1]
files = ["SunSmart/Common/Data/HDBConfiguration.swift", "SunSmart/Common/Data/HDBLightingZonePolicy.swift", "SunSmart/Common/Data/HDBConfigurationStore.swift", "SunSmart/Common/Data/HDBConfigurationStore+Mesh.swift", "Tests/HDB/HDBTestBoundaries.swift", "Tests/HDB/HDBMeshTestBoundaries.swift", "Tests/HDB/HDBSpaceCreationTests.swift"]
files += ["SunSmart/Common/Data/HDBDevicePreparationPolicy.swift", "SunSmart/Main/Space/HDB/Model/HDBDeviceSyncContext.swift"]
source = (ROOT / "SunSmart/Common/Data/MeshNetwork+SunSmart.swift").read_text()
creation = source[source.index("    func addSpace(name:"):source.index("    /// 克隆场所数据")]
deletion = source[source.index("    /// Finish local removal"):source.index("\nextension MeshLibManager")].rstrip().removesuffix("}")
with tempfile.TemporaryDirectory(prefix="hdb-space-creation-") as directory:
    harness = Path(directory) / "Harness.swift"
    harness.write_text(with_publication_policy("\n".join((ROOT / f).read_text().replace("import NordicSigMeshSDK", "") for f in files)
                       + "\nextension SiteData {\n" + creation + "\n}\nextension SpaceData {\n" + deletion + "\n}", ROOT))
    binary = Path(directory) / "tests"
    subprocess.run(["swiftc", "-parse-as-library", str(harness), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
