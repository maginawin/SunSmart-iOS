#!/usr/bin/env python3
"""Run member-save production code against independent App/Mesh SQLite files.
Only SDK identity/model and UIKit-free boundaries are fixtures; receipts and the
App transaction implementation are production, including final COMMIT failure.
"""
from pathlib import Path
import subprocess
import tempfile
import sys
sys.dont_write_bytecode = True
from check_scene_configuration import function

root = Path(__file__).resolve().parents[1]
sdk = (root / '.local-sdk/nordic-sig-mesh-sdk').resolve()
with tempfile.TemporaryDirectory(prefix='group-member-save-') as directory:
    tmp = Path(directory)
    subprocess.run(['swiftc', '-emit-module', '-emit-library', '-module-name', 'SQLite',
                    *map(str, sorted((sdk / 'Sources/SQLite').rglob('*.swift'))),
                    '-o', str(tmp / 'libSQLite.dylib'), '-emit-module-path', str(tmp / 'SQLite.swiftmodule')], check=True)
    production = tmp / 'GroupMemberPersistence.swift'
    production.write_text((root / 'SunSmart/Main/Group/Model/GroupMemberPersistence.swift').read_text().replace('import NordicSigMeshSDK', ''))
    fixture = (root / 'Tests/Group/GroupMemberPersistenceTests.swift').read_text()
    database = (root / 'SunSmart/Common/Data/Database.swift').read_text()
    fixture = fixture.replace('// ACTUAL_CONFIGURATION_TRANSACTION', function(database, '    @discardableResult\n    func configurationTransaction('))
    # Exercise the actual SDK restore codec (including fields it intentionally omits).
    restore = (sdk / 'Sources/NordicSigMeshSDK/MeshLib/Node/Node+Propertys.swift').read_text()
    fixture += '\n' + function(restore, 'public class NodeRestoreData: Codable {')
    controller = (root / 'SunSmart/Main/Group/Controller/GroupMembersViewController.swift').read_text()
    save = function(controller, '    private func performSave(').replace('private func', 'func')
    # Keep through navigation construction; UIKit callbacks are not executed.
    save = save[:save.index('        vc.syncSuccessCallback')] + '        installed = vc\n    }\n'
    fixture = fixture.replace('// ACTUAL_MEMBER_SAVE', save)
    policy_fixture = (root / 'Tests/Group/SpaceSyncCleanupPolicyTests.swift').read_text()
    fixture += '\nextension GroupMemberPersistenceTests {\n' + function(policy_fixture, '    static func profile(') + '\n}\n'
    support = tmp / 'Tests.swift'; support.write_text(fixture)
    binary = tmp / 'Tests'
    subprocess.run(['swiftc', '-parse-as-library', '-I', str(tmp), '-L', str(tmp), '-lSQLite',
                    '-Xlinker', '-rpath', '-Xlinker', str(tmp),
                    *[str(root / path) for path in [
                        'SunSmart/Main/Timed/Model/TimedSchedulerSlotPolicy.swift',
                        'SunSmart/Common/Data/HDBConfiguration.swift', 'SunSmart/Common/Data/HDBLightingZonePolicy.swift',
                        'SunSmart/Main/Scene/Model/SceneConfiguration.swift', 'SunSmart/Common/Data/SpaceConfigurationIntegrityPolicy.swift',
                        'SunSmart/Main/Group/Model/ProximityLightingTopologyPolicy.swift',
                        'SunSmart/Main/Group/Model/ProximityLightingTopologyReconciler.swift',
                        'SunSmart/Common/Data/SpaceSyncCleanupPolicy.swift']], str(production), str(support), '-o', str(binary)], check=True)
    subprocess.run([str(binary), str(tmp)], check=True)
