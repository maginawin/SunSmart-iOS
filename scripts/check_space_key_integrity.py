#!/usr/bin/env python3
"""Exercise the production Space key contract with isolated Mesh storage doubles."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'SunSmart/Common/Data/SpaceConfigurationSafety.swift').read_text()
contract = source[source.index('enum SpaceKeyIntegrity {'):source.index('/// Recovery data stays')]
fixture = (root / 'Tests/Group/SpaceKeyIntegrityTests.swift').read_text()
with tempfile.TemporaryDirectory(prefix='space-key-integrity-') as directory:
    harness = Path(directory) / 'Harness.swift'
    harness.write_text(fixture.replace('// PRODUCTION_KEY_CONTRACT', contract))
    binary = Path(directory) / 'Tests'
    subprocess.run(['swiftc', '-parse-as-library', str(harness), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
