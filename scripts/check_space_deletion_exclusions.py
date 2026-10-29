#!/usr/bin/env python3
"""Run App deletion and SDK exclusion persistence against SQLite.

Mesh topology/key operations and unrelated App tables are explicit doubles.
The SDK manager selection, subnetwork removal, exclusion mutation and SQLite
load/save/delete implementations are executed from the mapped SDK sources.
"""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
sdk = (root / '.local-sdk/nordic-sig-mesh-sdk').resolve()


def section(source, start, end):
    offset = source.index(start)
    return source[offset:source.index(end, offset)]


app = (root / 'SunSmart/Common/Data/MeshNetwork+SunSmart.swift').read_text()
custom = (sdk / 'Sources/NordicSigMeshSDK/MeshLib/MeshNetwork/MeshNetwork+Custom.swift').read_text()
manager = (sdk / 'Sources/NordicSigMeshSDK/MeshLib/Manager/MeshLibManager.swift').read_text()
database = (sdk / 'Sources/NordicSigMeshSDK/MeshLib/MeshDatabase.swift').read_text()
exclusions = (sdk / 'Sources/NordicSigMeshSDK/nRFMeshProvision/Mesh Model/ExclusionList.swift').read_text()
test = (root / 'Tests/Group/SpaceDeletionExclusionTests.swift').read_text()
test = test.replace('// APP_DELETE', section(app, '    /// Finish local removal', '\n}\n'))
test = test.replace('// SDK_MANAGER_REMOVE', section(manager, '    static func removeSubnetwork(meshUUID:', '\n    }') + '\n    }')
test = test.replace('// SDK_NETWORK_REMOVE', section(custom, '    func removeSubnetwork(networkId:', '\n    }') + '\n    }')
test = test.replace('// SDK_INSERT_EXCLUSION', section(custom, '    public func insetExclusionAddress(', '    /// 删除网络废弃设备地址'))
test = test.replace('// SDK_SAVE_EXCLUSIONS', section(database, '                if let exclusionList = self.networkExclusions', '\n            }catch'))
test += '\n' + section(exclusions, 'internal class ExclusionList:', 'internal extension Array')
test += '\n' + section(database, 'extension ExclusionList {', '\n}\n') + '\n}\n'

with tempfile.TemporaryDirectory(prefix='space-delete-exclusions-') as directory:
    output = Path(directory)
    subprocess.run(['swiftc', '-emit-module', '-emit-library', '-module-name', 'SQLite',
                    *map(str, sorted((sdk / 'Sources/SQLite').rglob('*.swift'))),
                    '-o', str(output / 'libSQLite.dylib'),
                    '-emit-module-path', str(output / 'SQLite.swiftmodule')], check=True)
    source = output / 'Harness.swift'
    source.write_text(test)
    binary = output / 'tests'
    subprocess.run(['swiftc', '-parse-as-library', '-I', directory, '-L', directory, '-lSQLite',
                    str(source), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
