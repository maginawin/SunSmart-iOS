#!/usr/bin/env python3
"""Execute production adapters with SDK/storage doubles; no simulator or private fixtures."""
from pathlib import Path
import subprocess
import tempfile
import sys

root = Path(__file__).resolve().parents[1]
baseline = '--baseline' in sys.argv

def source(path):
    if baseline:
        return subprocess.check_output(['git', 'show', 'HEAD:' + path], cwd=root, text=True)
    return (root / path).read_text()

def section(text, start, end):
    return text[text.index(start):text.index(end, text.index(start))]

adapter = source('SunSmart/Main/Group/Model/GroupProximityLightingData.swift')
start = 'enum ProximityLightingTopologyContext' if 'enum ProximityLightingTopologyContext' in adapter else 'enum ProximityLightingTopologyPlanner'
parts = [section(adapter, start, '\nextension SpaceData'),
         source('SunSmart/Main/Group/Model/ProximityLightingLifecycleCoordinator.swift').replace('import NordicSigMeshSDK', ''),
         section(source('SunSmart/Common/Data/ImportData.swift'), 'private struct ProximityLightingImportPreflight', '\n#if DEBUG'),
         'extension Node {\n' + section(source('SunSmart/Common/Data/Node+SyncData.swift'), '    func getNodeSyncProximityLighting(', '    /// 获取网关设备同步的配置') + '\n}',
         (root / 'Tests/Group/ProximityLightingScopedImportTests.swift').read_text()]
with tempfile.TemporaryDirectory(prefix='proximity-scoped-import-') as directory:
    directory = Path(directory)
    harness = directory / 'Harness.swift'
    harness.write_text('\n'.join(parts))
    policy = directory / 'Policy.swift'
    policy.write_text(source('SunSmart/Main/Group/Model/ProximityLightingTopologyPolicy.swift'))
    reconciler = directory / 'Reconciler.swift'
    reconciler.write_text(source('SunSmart/Main/Group/Model/ProximityLightingTopologyReconciler.swift'))
    binary = directory / 'ScopedImportTests'
    subprocess.run(['swiftc', '-parse-as-library', str(root / 'Pods/SwiftyJSON/Source/SwiftyJSON/SwiftyJSON.swift'),
                    str(policy), str(reconciler), str(harness), '-o', str(binary)], check=True)
    fixture_args = sys.argv[sys.argv.index('--snapshot') + 1:][:1] if '--snapshot' in sys.argv else []
    sys.exit(subprocess.run([str(binary), *fixture_args]).returncode)
