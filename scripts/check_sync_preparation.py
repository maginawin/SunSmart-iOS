#!/usr/bin/env python3
"""Execute production sync access and controller preparation with controlled I/O/UI."""
from pathlib import Path
import subprocess
import sys
import tempfile
sys.dont_write_bytecode = True
from check_scene_configuration import function, section, ROOT

with tempfile.TemporaryDirectory(prefix='sync-preparation-') as directory:
    tmp = Path(directory)
    cleanup = (ROOT / 'SunSmart/Common/Data/SpaceSyncCleanupCoordinator.swift').read_text()
    access = section('SunSmart/Common/Data/SpaceSyncCleanupCoordinator.swift', 'enum SpaceSyncAccess {', 'enum SpaceSyncTaskScope {')
    source = (ROOT / 'Tests/Sync/SpaceSyncAccessTests.swift').read_text()
    source = source.replace('// PRODUCTION_ACCESS', access).replace('// PRODUCTION_CLEANUP', function(cleanup, '    static func prepareForDeviceSync('))
    path = tmp / 'Access.swift'; path.write_text(source)
    binary = tmp / 'Access'
    subprocess.run(['swiftc', '-parse-as-library', str(path), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)

    controller = (ROOT / 'SunSmart/Main/Space/Controller/SyncDevicesViewController.swift').read_text()
    methods = '\n'.join(function(controller, marker).replace('@objc ', '').replace('private func', 'func') for marker in [
        '    private func rebuildTaskPlan(', '    private func acceptsPreparation(', '    private func cancelTaskPreparation(',
        '    private func failTaskPreparation(', '    private func buildPreparedTaskPlan(',
        '    @objc private func rightItemAction(', '    private func updateSyncStateUI('])
    source = (ROOT / 'Tests/Sync/SyncPreparationTests.swift').read_text().replace('// PRODUCTION_METHODS', methods)
    path = tmp / 'Controller.swift'; path.write_text(source)
    binary = tmp / 'Controller'
    subprocess.run(['swiftc', '-parse-as-library', str(path), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
