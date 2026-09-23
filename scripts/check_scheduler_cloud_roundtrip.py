#!/usr/bin/env python3
"""Offline production codec round-trip; optional real backend mapping, no DB/network.

Usage: python3 scripts/check_scheduler_cloud_roundtrip.py [--server-root PATH]
Node object identity and SQLite are isolated boundaries. The App adapter, SDK
wire codec and SDK save/load blocks execute unchanged against synthetic data.
"""
import argparse
import ast
import json
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--server-root', type=Path)
args = parser.parse_args()
sdk = (root / '.local-sdk/nordic-sig-mesh-sdk').resolve()
if not (sdk / 'Package.swift').exists():
    raise SystemExit('Local SDK mapping is missing; initialize SunSmartLocal first.')
source = sdk / 'Sources/NordicSigMeshSDK'

def section(text, start, end):
    return text[text.index(start):text.index(end, text.index(start))]

exports = (root / 'SunSmart/Common/Data/ExportData.swift').read_text()
adapter = section(exports, '// MARK: - Scheduler Model snapshot adapter', '// MARK: - Gateway export')
wire = (source / 'nRFMeshProvision/Mesh Messages/SchedulerMessage.swift').read_text()
data_extensions = (source / 'nRFMeshProvision/Type Extensions/Data.swift').read_text()
data_extensions = data_extensions[:data_extensions.index('extension CBUUID')].replace('import CoreBluetooth', '')
database = (source / 'MeshLib/MeshDatabase.swift').read_text()
saving = section(database, '        var modelSchedulerContainers:', '        let lightLCPropertysData')
loading = section(database, '                switch SchedulerModelCachePersistence.decode(schedulersData)', '\n            }\n            \n            if let data = row[PropertyExpressionKey.lightLCPropertys]')
methods = ('func saveSnapshotProperty() -> Data {\n' + saving + '\nreturn allSchedulersData!\n}\n'
           + 'func loadSnapshotProperty(_ schedulersData: Data) {\n' + loading + '\n}\n')
harness = (root / 'Tests/Group/SchedulerModelSnapshotTests.swift').read_text().replace('// SDK_PERSISTENCE_METHODS', methods)

with tempfile.TemporaryDirectory(prefix='scheduler-cloud-roundtrip-') as temp:
    temp = Path(temp)
    assembled = temp / 'Harness.swift'
    assembled.write_text(harness + '\n' + adapter + '\n' + wire + '\n' + data_extensions)
    binary = temp / 'Tests'
    subprocess.run(['swiftc', '-parse-as-library',
                    str(root / 'SunSmart/Common/Data/SpaceConfigurationIntegrityPolicy.swift'),
                    str(source / 'nRFMeshProvision/Mesh Model/StepResolution.swift'),
                    str(source / 'nRFMeshProvision/Mesh Model/TransitionTime.swift'),
                    str(source / 'MeshLib/Node/SchedulerModelCachePersistence.swift'),
                    str(assembled), '-o', str(binary)], check=True)
    exported = temp / 'export.json'
    subprocess.run([str(binary), 'export', str(exported)], check=True)
    payload = json.loads(exported.read_text())
    if args.server_root:
        # Execute only pure functions/constant mappings from the supplied checkout.
        # Do not import Django settings, open a database, or contact a real server.
        namespace = {'json': json, 'model_to_dict': lambda row: row}
        snippet = ast.parse((args.server_root / 'sitespace/snippet.py').read_text())
        names = {'convert_to_camel_case', 'safe_get', 'node_outgoing',
                 'site_str_cols', 'site_exclude_cols', 'spec_cols_mapp'}
        selected = [n for n in snippet.body if
                    isinstance(n, ast.FunctionDef) and n.name in names or
                    isinstance(n, ast.Assign) and any(isinstance(t, ast.Name) and t.id in names for t in n.targets)]
        exec(compile(ast.Module(body=selected, type_ignores=[]), '<server node mapping>', 'exec'), namespace)
        services = ast.parse((args.server_root / 'sitespace/services_4_space.py').read_text())
        selected = [n for n in services.body if isinstance(n, ast.FunctionDef) and n.name == 'build_node_data']
        exec(compile(ast.Module(body=selected, type_ignores=[]), '<server node storage>', 'exec'), namespace)
        def roundtrip(node):
            stored = namespace['build_node_data']('synthetic-site', 'synthetic-space', node['uuid'], node)
            # JSON serialization represents the TextField transport, not ORM acceptance.
            return namespace['node_outgoing'](json.loads(json.dumps(stored)))
        old_client = dict(payload['nodes'][2])
        old_client.pop('custProps')
        assert roundtrip(old_client)['custProps'] == {}, 'Update documented old-client compatibility result'
        print('CONFIRMED backend risk: old-client full upload defaults custProps to {}, overwriting snapshots')
        payload['nodes'] = [roundtrip(node) for node in payload['nodes']]
        print('PASS: backend build_node_data -> JSON TextField mapping -> node_outgoing retains new snapshots')
    returned = temp / 'returned.json'
    returned.write_text(json.dumps(payload))
    subprocess.run([str(binary), 'verify', str(returned)], check=True)
