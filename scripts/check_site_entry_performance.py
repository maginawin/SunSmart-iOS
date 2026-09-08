#!/usr/bin/env python3
"""Execute production address projection, snapshot revisions and gzip encoding on macOS."""
from pathlib import Path
import subprocess
import tempfile
import sys

root = Path(__file__).resolve().parents[1]
sdk = Path(sys.argv[1])

def section(source, start, end):
    return source[source.index(start):source.index(end, source.index(start))]

mesh = (sdk / 'Sources/NordicSigMeshSDK/MeshLib/MeshDatabase.swift').read_text()
database = (root / 'SunSmart/Common/Data/Database.swift').read_text()
network = (root / 'SunSmart/Common/Network/NetworkRequest.swift').read_text()
membership = section(mesh, '                    let usedAddressSet =', '                    if addresses.count > 0')
projection = section(mesh, '    public static func loadAddresses(meshUUID: String, subnetworkId: String? = nil) -> [Address]', '    /// 获取节点属性')
revision = section(mesh, '    public func databaseReadRevision()', '    public func initDatabase()')
snapshot = section(database, 'struct ConfigurationSnapshotRevision', '\nclass SunSmartDataManager')
encoding = section(network, 'enum HTTPBodyEncoding', '\nprivate final class NetworkTransferMetricsMonitor')
with tempfile.TemporaryDirectory(prefix='site-entry-performance-') as directory:
    output = Path(directory)
    sources = sorted((sdk / 'Sources/SQLite').rglob('*.swift'))
    subprocess.run(['swiftc', '-emit-module', '-emit-library', '-module-name', 'SQLite',
                    *map(str, sources), '-o', str(output / 'libSQLite.dylib'),
                    '-emit-module-path', str(output / 'SQLite.swiftmodule')], check=True)
    source = output / 'Production.swift'
    source.write_text('import Foundation\nimport SQLite\nimport struct SQLite.Expression\n'
        + 'func missingAddresses(network: MeshNetwork, existNodeAddresses: [UInt16], exclustionAddresses: [UInt16]) -> [UInt16] {\n'
        + membership + '\nreturn addresses\n}\n'
        + 'extension Node {\n' + projection + '\n}\n'
        + 'extension MeshDataManager {\n' + revision + '\n}\n'
        + snapshot + '\n' + encoding)
    binary = output / 'tests'
    subprocess.run(['swiftc', '-parse-as-library', '-I', directory, '-L', directory, '-lSQLite',
                    str(source), str(root / 'SunSmart/Thirdparty/Gzip/Data+Gzip.swift'),
                    str(root / 'Tests/Group/SiteEntryPerformanceTests.swift'),
                    '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
