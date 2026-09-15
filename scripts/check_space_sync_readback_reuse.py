#!/usr/bin/env python3
"""执行生产清理 perform；仅持久化、拓扑适配和网络边界为受控替身。"""
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[1]
source = (root / 'SunSmart/Common/Data/SpaceSyncCleanupCoordinator.swift').read_text()
start = source.index('    private static func perform(')
end = source.index('\n    static func prepareCurrentSpace()', start)
method = source[start:end].replace('private static func perform(', 'static func run(')
production = '''import Foundation
@MainActor enum SpaceSyncCleanupCoordinator {
    struct Scope { var isCurrent: Bool { true } }
    static func extensionChanges(space: SpaceData, network: MeshNetwork, cleaned: SpaceSyncCleanupPolicy.Result) throws -> [() throws -> Void] { [] }
''' + method + '\n}\n'
with tempfile.TemporaryDirectory(prefix='sync-readback-') as directory:
    path = Path(directory); (path / 'Production.swift').write_text(production)
    binary = path / 'tests'
    subprocess.run(['swiftc', '-parse-as-library', str(root / 'SunSmart/Common/Data/AppPerformance.swift'), str(path / 'Production.swift'), str(root / 'Tests/Group/SpaceSyncReadbackReuseTests.swift'), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
