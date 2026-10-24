#!/usr/bin/env python3
"""Exercise production snapshots, comparisons, codecs and async service; no radio/UI/cloud."""
from pathlib import Path
import sys
import subprocess
import tempfile
ROOT = Path(__file__).resolve().parents[1]
SDK = (ROOT / '.local-sdk/nordic-sig-mesh-sdk').resolve()
sys.dont_write_bytecode = True
sys.path.insert(0, str(SDK / 'scripts'))
from configuration_readback_test_source import source, block
files = [
    'SunSmart/Common/Data/HDBConfiguration.swift',
    'SunSmart/Common/Data/HDBLightingZonePolicy.swift',
    'SunSmart/Common/Data/HDBDevicePreparationPolicy.swift',
    'SunSmart/Main/Space/Model/SyncRunLifecycle.swift',
    'SunSmart/Main/Space/Model/SyncSessionCoordinator.swift',
    'SunSmart/Main/Space/HDB/Model/HDBDeviceSyncContext.swift',
    'SunSmart/Main/Space/HDB/Model/HDBDeviceDiagnostics.swift',
    'SunSmart/Main/Space/HDB/Model/HDBDeviceDiagnosticsService.swift',
    'Tests/HDB/HDBDiagnosticsBoundaries.swift',
    'Tests/HDB/HDBDiagnosticsTests.swift',
]
text = source(SDK) + '\n' + '\n'.join((ROOT / f).read_text().replace('import NordicSigMeshSDK', '') for f in files)
mesh_store = (ROOT / 'SunSmart/Common/Data/HDBConfigurationStore+Mesh.swift').read_text()
text += '\nextension HDBConfigurationStore {\n' + '\n'.join(block(mesh_store, marker) for marker in [
    '    static func modelTargets(', '    static func broadcastTargets(', '    static func publicationTargets('
]) + '\n}\n'
text = text.replace('// Inject SensorPublicationPolicy here.', block((ROOT / 'SunSmart/Common/Data/Node+SyncData.swift').read_text(), 'enum SensorPublicationPolicy {'))
text = text.replace('// Inject production sensorPublicationRetransmit here.', block((ROOT / 'SunSmart/Main/Space/HDB/Model/HDBDeviceSyncService.swift').read_text(), '    static var sensorPublicationRetransmit:'))
with tempfile.TemporaryDirectory(prefix='hdb-diagnostics-') as directory:
    p = Path(directory)
    (p / 'Harness.swift').write_text(text)
    subprocess.run(['swiftc', '-parse-as-library', str(p / 'Harness.swift'), '-o', str(p / 'tests')], check=True)
    subprocess.run([str(p / 'tests')], check=True)
