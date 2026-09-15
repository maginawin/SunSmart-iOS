#!/usr/bin/env python3
"""执行生产批量协调、Zone 清理、SQLite 持久化和三个调用入口。"""
from pathlib import Path
import subprocess
import tempfile
import sys

root = Path(__file__).resolve().parents[1]
if len(sys.argv) != 2:
    raise SystemExit('Usage: check_site_zone_cleanup_batch.py <NordicSigMeshSDK path>')
sdk = Path(sys.argv[1])

def read(path):
    return (root / path).read_text()

def section(source, start, end):
    offset = source.index(start)
    return source[offset:source.index(end, offset)]

cleanup = read('SunSmart/Common/Data/SpaceSyncCleanupCoordinator.swift')
zones = read('SunSmart/Main/Site/TriggerZone/SiteTriggerZoneCoordinator.swift')
topology = read('SunSmart/Main/Site/TriggerZone/SiteTriggerZoneTopologyReader.swift')
cloud = read('SunSmart/Common/Cloud/CloudSynchronizationManager.swift')
production = 'import Foundation\nimport SQLite\n'
production += section(cleanup, '@MainActor\nenum SpaceSyncCleanupCoordinator',
                      '    private static func perform(')
# The expensive Space repair is the only coordinator seam. Its policy already
# has a separate suite; batching, ownership, durability and Zone reads are real.
production += '''    private static func perform(_ space: SpaceData, scope: Scope) async -> Bool {
        await CleanupFixture.perform(space)
    }
}
'''
production += '@MainActor\nstruct SiteTriggerZoneCoordinator {\n'
production += section(zones, '    let site: SiteData', '    func add(count:')
production += section(zones, '    @discardableResult\n    func cleanObsoleteMembers()', '    private func mutate(')
production += '''    func synchronize() async -> Bool {
        CleanupFixture.synchronizations += 1
        CleanupFixture.membersAtSynchronization = (try? state().data.zones?.first?.displayMembers.count) ?? -1
        return true
    }
}
'''
production += 'enum SiteTriggerZoneTopologyReader {\n'
production += section(topology, '    static func cleanupClassifier(site:', '    static func mergedLocalTarget(')
production += '}\n'
production += section(cloud, 'final class PendingSynchronizationRecoveryGate', '\nclass CloudSynchronizationManager')
production += 'extension CloudSynchronizationManager {\n'
production += section(cloud, '    func resumePendingSynchronizations()', '\n    /// 添加同步云端数据操作')
production += '}\nenum SyncOperation {\n'
production += '''    case syncSite(site: SiteData, syncSpaces: [SpaceData] = [])
    case syncSpace(space: SpaceData)
    case addSpaces(site: SiteData, spaces: [SpaceData])
'''
# Compile the complete production branches under test, omitting only gateways.
production += section(cloud, '    func getNetworkApi()', '        case .syncGateway(let gateway, let node):')
production += '        }\n    }\n}\n'

with tempfile.TemporaryDirectory(prefix='site-zone-cleanup-batch-') as directory:
    output = Path(directory)
    subprocess.run(['swiftc', '-emit-module', '-emit-library', '-module-name', 'SQLite',
                    *map(str, sorted((sdk / 'Sources/SQLite').rglob('*.swift'))),
                    '-o', str(output / 'libSQLite.dylib'),
                    '-emit-module-path', str(output / 'SQLite.swiftmodule')], check=True)
    source = output / 'Production.swift'
    source.write_text(production)
    binary = output / 'tests'
    subprocess.run(['swiftc', '-parse-as-library', '-I', directory, '-L', directory, '-lSQLite',
                    str(source), str(root / 'SunSmart/Main/Site/TriggerZone/SiteTriggerZoneData.swift'),
                    str(root / 'SunSmart/Main/Site/TriggerZone/SiteTriggerZoneStore.swift'),
                    str(root / 'Tests/Site/SiteZoneCleanupBatchTests.swift'),
                    '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
