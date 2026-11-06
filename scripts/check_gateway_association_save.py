#!/usr/bin/env python3
"""Real Gateway JSON/SQLite round trips; UIKit/HTTP/Mesh remain controlled boundaries."""
from pathlib import Path
import subprocess
import tempfile
import sys
sys.dont_write_bytecode = True
from check_scene_configuration import function
ROOT = Path(__file__).resolve().parents[1]
model = (ROOT / 'SunSmart/Main/Device/Gateway/Model/GatewayModel.swift').read_text()
db = (ROOT / 'SunSmart/Common/Data/Database.swift').read_text()
with tempfile.TemporaryDirectory(prefix='gateway-association-save-') as directory:
    out = Path(directory)
    sdk = (ROOT / '.local-sdk/nordic-sig-mesh-sdk').resolve()
    subprocess.run(['swiftc', '-module-cache-path', str(out / 'ModuleCache'), '-emit-module', '-emit-library', '-module-name', 'SQLite',
                    *map(str, sorted((sdk / 'Sources/SQLite').rglob('*.swift'))),
                    '-o', str(out / 'libSQLite.dylib'), '-emit-module-path', str(out / 'SQLite.swiftmodule')], check=True)
    production = 'import Foundation\nimport SQLite\n'
    production += function(model, 'extension GatewayOrphanGuard.Scope {')
    for marker in ['enum GatewayConnectStatus', 'enum GatewaySignalLevel:', 'class GatewayModel:', 'class GatewaySpaceData:']:
        production += '\n' + function(model, marker)
    table = db[db.index('extension GatewayModel {'):]
    declarations = table[:table.index('    /// 初始化能耗静态统计数据信息表')]
    production += '\n' + declarations
    for marker in ['    private static func normalizedMac(', '    static func load(siteId:', '    @discardableResult func save(importingConfiguration:', '    private func saveCurrentGateway(']:
        production += '\n' + function(table, marker)
    production += '\n}\n'
    controller = (ROOT / 'SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift').read_text()
    methods = '\n'.join(function(controller, marker).replace('private ', '') for marker in [
        '    private struct AssociatedSpacesSaveResult', '    private func saveAssociatedSpacesIfNeeded(',
        '    private func reconcileAssociatedSpacesAfterPartialSave(', '    @discardableResult private func commitAssociatedSpaces(',
        '    private func applyAuthoritativeAssociatedSpaces('])
    fixture = (ROOT / 'Tests/Device/GatewayAssociationPersistenceTests.swift').read_text().replace('// PRODUCTION_SAVE_METHODS', methods)
    (out / 'Fixture.swift').write_text(fixture)
    (out / 'Production.swift').write_text(production)
    subprocess.run(['swiftc', '-module-cache-path', str(out / 'ModuleCache'), '-parse-as-library', '-I', directory, '-L', directory, '-lSQLite',
                    str(out / 'Production.swift'),
                    str(ROOT / 'SunSmart/Common/Data/SiteGatewayAssociationConsistencyPolicy.swift'),
                    str(ROOT / 'SunSmart/Main/Device/Gateway/Model/GatewayCloudSyncGenerationPolicy.swift'),
                    str(ROOT / 'SunSmart/Main/Device/Gateway/Model/GatewayAssociatedSpaceCandidatePolicy.swift'),
                    str(out / 'Fixture.swift'),
                    '-o', str(out / 'tests')], check=True)
    subprocess.run([str(out / 'tests')], check=True)
