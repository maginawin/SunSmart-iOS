#!/usr/bin/env python3
"""Run the production Site deletion adapter with storage/SDK doubles, without devices."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='gateway-deletion-') as folder:
    folder = Path(folder)
    source = (root / 'SunSmart/Main/Device/Gateway/Model/GatewayDeletionContext.swift').read_text()
    # Replace only the SDK dependency and filesystem root. All deletion decisions
    # and cleanup calls execute the production implementation unchanged.
    source = source.replace('import NordicSigMeshSDK', '')
    source = source.replace('NSHomeDirectory()', 'testHomeDirectory')
    adapter = folder / 'Context.swift'
    adapter.write_text(source)
    binary = folder / 'Tests'
    subprocess.run(['swiftc', '-parse-as-library',
        str(root / 'SunSmart/Main/Device/Gateway/Model/GatewayDeletionCoordinator.swift'),
        str(adapter), str(root / 'Tests/Device/GatewayDeletionContextTests.swift'),
        '-o', str(binary)], check=True)
    subprocess.run([str(binary), str(folder / 'storage')], check=True)
