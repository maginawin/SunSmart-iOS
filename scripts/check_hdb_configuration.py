#!/usr/bin/env python3
"""Compile and exercise the production HDB value policies without Mesh or cloud."""
from pathlib import Path
import subprocess
import tempfile
import re
ROOT = Path(__file__).resolve().parents[1]
# Only current, complete HDB objects belong here. Historical demos are archived.
CURRENT_EXAMPLES = [ROOT / "docs/261021_1806_HDB_unicast_example.json",
                    ROOT / "docs/261022_1626_HDB_json_v2_demo.json"]
CONTRACT = ROOT / "docs/261022_1116_HDB_device_model_arrays_plan.md"
with tempfile.TemporaryDirectory(prefix="hdb-tests-") as directory:
    binary = str(Path(directory) / "tests")
    cache = Path.home() / "Library/Developer/Xcode/ModuleCache.noindex/HDBTests"
    cache.mkdir(parents=True, exist_ok=True)
    sources = ["SunSmart/Common/Data/HDBConfiguration.swift", "SunSmart/Common/Data/HDBLightingZonePolicy.swift", "Tests/HDB/HDBConfigurationTests.swift"]
    subprocess.run(["swiftc", "-module-cache-path", str(cache), "-parse-as-library", *[str(ROOT / path) for path in sources], "-o", binary], check=True)
    marker = "<!-- hdb-complete-example -->"
    contract = CONTRACT.read_text()
    assert contract.count(marker) == 1, "Current contract must identify one complete HDB example"
    example = re.match(r"\s*```json\n(.*?)\n```", contract.split(marker, 1)[1], re.S)
    assert example, "Missing complete JSON block after the contract example marker"
    documented = Path(directory) / "documented_hdb_example.json"
    documented.write_text(example.group(1))
    subprocess.run([binary, *map(str, [*CURRENT_EXAMPLES, documented])], check=True)
    print("PASS: current standalone and documented HDB examples decode, validate and round-trip", flush=True)

    subprocess.run(["swiftc", "-module-cache-path", str(cache), "-parse-as-library", str(ROOT / "SunSmart/Common/Data/HDBConfiguration.swift"), str(ROOT / "Tests/HDB/HDBSchemaSimplificationTests.swift"), "-o", binary], check=True)
    subprocess.run([binary], check=True)
