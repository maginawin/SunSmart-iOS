#!/usr/bin/env python3
"""Run production add-batch ownership, cloud scheduling and HTTP upload flow.

Only platform observations, database, exports and receipt/network boundaries are
doubled. The real receipt protocol is covered by check_space_recovery_receipts.py.
"""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
cloud = (root / 'SunSmart/Common/Cloud/CloudSynchronizationManager.swift').read_text()
for module in ['Moya', 'NordicSigMeshSDK', 'SwiftyJSON', 'UIKit']:
    cloud = cloud.replace(f'import {module}', '')
cloud = cloud.replace('    private var networkObservation: NSKeyValueObservation?', '')
cloud = cloud.replace('    private var foregroundObservation: NSObjectProtocol?', '')
a = cloud.index('    private init() {')
b = cloud.index('\n    func resumePendingSynchronizations()', a)
cloud = cloud[:a] + '    init() {}\n' + cloud[b:]
add = (root / 'SunSmart/Main/Device/Model/HDBDeviceAddCompletion.swift').read_text()
add = add[add.index('/// Owns provisioning-to-HDB completion'):]
with tempfile.TemporaryDirectory(prefix='device-add-cloud-') as directory:
    source = Path(directory) / 'Production.swift'
    source.write_text(cloud + '\n' + add)
    binary = Path(directory) / 'tests'
    subprocess.run(['swiftc', '-parse-as-library', str(source),
                    str(root / 'Tests/Cloud/DeviceAddCloudBatchTests.swift'),
                    '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
