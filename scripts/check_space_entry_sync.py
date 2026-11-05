#!/usr/bin/env python3
from pathlib import Path
import subprocess, tempfile, sys
sys.dont_write_bytecode = True
from check_scene_configuration import function
root = Path(__file__).resolve().parents[1]
source = (root / 'SunSmart/Main/Space/Controller/SpaceViewController.swift').read_text()
start = source.index('    // Entry reconciliation session')
end = source.index('    // End entry reconciliation session', start)
production = source[start:end].replace('private ', '')
fixture = (root / 'Tests/Space/SpaceEntrySyncTests.swift').read_text().replace('// PRODUCTION', production)
with tempfile.TemporaryDirectory(prefix='space-entry-') as directory:
    path = Path(directory); harness = path / 'Harness.swift'; harness.write_text(fixture)
    subprocess.run(['swiftc', '-parse-as-library', str(harness), '-o', str(path / 'Tests')], check=True)
    subprocess.run([str(path / 'Tests')], check=True)
