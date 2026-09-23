#!/usr/bin/env python3
"""Exercise production orphan SQL and lifecycle decisions against real SQLite."""
from pathlib import Path
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[1]
sdk = (repo / '.local-sdk/nordic-sig-mesh-sdk').resolve()
with tempfile.TemporaryDirectory(prefix='gateway-orphan-') as directory:
    out = Path(directory)
    subprocess.run(['swiftc', '-emit-module', '-emit-library', '-module-name', 'SQLite',
                    *map(str, sorted((sdk / 'Sources/SQLite').rglob('*.swift'))),
                    '-o', str(out / 'libSQLite.dylib'), '-emit-module-path', str(out / 'SQLite.swiftmodule')], check=True)
    source = (repo / 'SunSmart/Common/Data/Database.swift').read_text()
    # Omit unrelated App database adapters, preserving the complete production store.
    start = source.index('enum GatewayOrphanStore {')
    end = source.index('\nextension Node.PreConfiguration {', start)
    (out / 'Store.swift').write_text('import Foundation\nimport SQLite\n' + source[start:end])
    model = (repo / 'SunSmart/Main/Device/Gateway/Model/GatewayModel.swift').read_text()
    adapter = model[model.index('extension GatewayOrphanGuard.Scope {'):model.index('/// 网关连接状态')]
    (out / 'Adapter.swift').write_text('import Foundation\nimport SQLite\n' + adapter)
    subprocess.run(['swiftc', '-parse-as-library', '-I', directory, '-L', directory, '-lSQLite',
                    str(repo / 'SunSmart/Common/Data/SiteGatewayAssociationConsistencyPolicy.swift'),
                    str(out / 'Store.swift'), str(out / 'Adapter.swift'),
                    str(repo / 'Tests/Site/GatewayOrphanCleanupAdapterDoubles.swift'),
                    str(repo / 'Tests/Site/GatewayOrphanCleanupTests.swift'),
                    '-o', str(out / 'tests')], check=True)
    subprocess.run([str(out / 'tests')], check=True)
