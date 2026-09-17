#!/usr/bin/env python3
"""Run production snapshot and raw SQLite export logic on isolated fixtures."""
from pathlib import Path
import subprocess
import tempfile
import sys

repo = Path(__file__).resolve().parents[1]
sdk = Path(sys.argv[1]) if len(sys.argv) > 1 else Path('/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev')

def read(path):
    return (repo / path).read_text()

with tempfile.TemporaryDirectory(prefix='debug-json-tests-') as output:
    out = Path(output)
    sqlite = sorted((sdk / 'Sources/SQLite').rglob('*.swift'))
    subprocess.run(['swiftc', '-emit-module', '-emit-library', '-module-name', 'SQLite',
                    *map(str, sqlite), '-o', str(out / 'libSQLite.dylib'),
                    '-emit-module-path', str(out / 'SQLite.swiftmodule')], check=True)
    records = read('SunSmart/Common/Cloud/DebugCloudJSONRecords.swift').replace('import NordicSigMeshSDK', '')
    # Production SQL/Blob logic is unchanged; only app singleton adapters are omitted.
    start = records.index('    static func space(')
    end = records.index('    static func read(', start)
    records = records[:start] + records[end:]
    (out / 'Records.swift').write_text(records)
    subprocess.run(['swiftc', '-DDEBUG', '-parse-as-library', '-I', output, '-L', output, '-lSQLite',
                    str(out / 'Records.swift'), str(repo / 'Tests/Cloud/DebugCloudJSONRecordsTests.swift'),
                    '-o', str(out / 'records')], check=True)
    subprocess.run([str(out / 'records')], check=True)

    exporter = read('SunSmart/Common/Cloud/DebugCloudJSONExporter.swift')
    start = exporter.index('    enum ExportError: Error')
    fixture = read('Tests/Cloud/DebugCloudJSONFixtures.swift')
    fixture = fixture[:fixture.index('extension String {')].replace('import UIKit', 'import Foundation')
    source = 'import Foundation\n@MainActor final class DebugCloudJSONExporter {\n'
    source += 'static func canExport(_ permission: Permission) -> Bool { permission == .owner || permission == .editor }\n'
    source += exporter[start:exporter.rindex('#endif')]
    source += '\nextension String { var localizedString: String { self } }\n'
    source += fixture + '\n@main struct Run { static func main() async throws { try await runSnapshotTests() } }\n'
    (out / 'Snapshot.swift').write_text(source)
    files = str(repo / 'SunSmart/Common/Cloud/DebugCloudJSONFile.swift')
    subprocess.run(['swiftc', '-DDEBUG', '-parse-as-library', files, str(out / 'Snapshot.swift'),
                    '-o', str(out / 'snapshot')], check=True)
    subprocess.run([str(out / 'snapshot')], check=True)
    subprocess.run(['swiftc', '-DDEBUG', '-parse-as-library', files,
                    str(repo / 'Tests/Cloud/DebugCloudJSONFileTests.swift'), '-o', str(out / 'files')], check=True)
    subprocess.run([str(out / 'files')], check=True)
