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
    operation = (root / 'SunSmart/Common/Data/LightsBatchDeletionOperation.swift').read_text()
    delete_server = operation.split('                deleteServer: {', 1)[1].split(
        '                recordServerDeletion:', 1)[0].rsplit('},', 1)[0]
    # Execute the production request closure; replace only its monotonic clock.
    delete_server = delete_server.replace('ProcessInfo.processInfo.systemUptime', 'BatchRequestClock.now')
    fixture = folder / 'Fixture.swift'
    fixture.write_text((root / 'Tests/Device/GatewayDeletionContextTests.swift').read_text().replace(
        '// BATCH_DELETE_SERVER', delete_server))
    binary = folder / 'Tests'
    subprocess.run(['swiftc', '-parse-as-library',
        str(root / 'SunSmart/Main/Device/Gateway/Model/GatewayDeletionCoordinator.swift'),
        str(adapter), str(fixture),
        '-o', str(binary)], check=True)
    subprocess.run([str(binary), str(folder / 'storage')], check=True)
