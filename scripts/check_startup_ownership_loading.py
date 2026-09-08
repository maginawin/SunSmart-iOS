#!/usr/bin/env python3
"""Run production identity projection and recovery scheduling with real SQLite."""
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
sdk = Path(sys.argv[1])

def section(text, start, end):
    return text[text.index(start):text.index(end, text.index(start))]

database = (root / 'SunSmart/Common/Data/Database.swift').read_text()
cloud = (root / 'SunSmart/Common/Cloud/CloudSynchronizationManager.swift').read_text()
store = section(database, 'enum SiteDeviceOwnershipStore', '\n/// Conservative revision')
gate = section(cloud, 'final class PendingSynchronizationRecoveryGate', '\nclass CloudSynchronizationManager')
resume = section(cloud, '    func resumePendingSynchronizations()', '\n    /// 添加同步云端数据操作')
with tempfile.TemporaryDirectory(prefix='startup-ownership-') as directory:
    output = Path(directory)
    sources = sorted((sdk / 'Sources/SQLite').rglob('*.swift'))
    subprocess.run(['swiftc', '-emit-module', '-emit-library', '-module-name', 'SQLite',
                    *map(str, sources), '-o', str(output / 'libSQLite.dylib'),
                    '-emit-module-path', str(output / 'SQLite.swiftmodule')], check=True)
    production = output / 'Production.swift'
    production.write_text('import Foundation\nimport SQLite\nimport struct SQLite.Expression\n'
        + store + '\n' + gate + '\nextension CloudSynchronizationManager {\n' + resume + '\n}\n')
    binary = output / 'tests'
    subprocess.run(['swiftc', '-parse-as-library', '-I', directory, '-L', directory, '-lSQLite',
                    str(production), str(root / 'Tests/Group/StartupOwnershipLoadingTests.swift'),
                    '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
