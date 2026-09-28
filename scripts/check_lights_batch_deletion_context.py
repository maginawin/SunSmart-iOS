#!/usr/bin/env python3
"""Exercise production deletion preparation and guards with isolated storage/SDK doubles."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]


def source(name):
    return (root / 'SunSmart/Common/Data' / name).read_text()


def section(text, start, end):
    offset = text.index(start)
    return text[offset:text.index(end, offset)]


safety = source('SpaceConfigurationSafety.swift')
fixture = (root / 'Tests/Device/LightsBatchDeletionContextTests.swift').read_text()
fixture = fixture.replace('// DEVICE_OPERATES', section(source('SpaceData.swift'),
    '    var deviceOperates:', '    /// 组操作权限'))
fixture = fixture.replace('// OPERATION_CURRENT', section(source('LightsBatchDeletionOperation.swift'),
    '    private var isCurrent:', '    func cancel()').replace('private var isCurrent:', 'var isCurrent:'))
fixture = fixture.replace('// SAFETY_METHODS', '\n'.join([
    section(safety, '    static func isBlocked(meshUUID:', '    static func block(_ space:'),
    section(safety, '    private static func deletionCleanupPending(', '    static func deletionJournal('),
    section(safety, '    static func isCurrent(_ context:', '    private static func storedDirectory('),
    section(safety, '    static func hasPendingImport(', '    #if DEBUG'),
]).replace('UserDefaults.standard', 'testDefaults'))
preparation = section(source('DevicePermanentDeletionCleanup.swift'),
    'final class DevicePermanentDeletionContext {', '    func cancel()') + '\n}\n'

with tempfile.TemporaryDirectory(prefix='lights-deletion-context-') as folder:
    folder = Path(folder)
    harness = folder / 'Harness.swift'
    harness.write_text('import Foundation\n' + preparation + fixture)
    binary = folder / 'tests'
    subprocess.run(['swiftc', '-parse-as-library',
        str(root / 'SunSmart/Common/Data/SpaceConfigurationIntegrityPolicy.swift'),
        str(root / 'SunSmart/Common/Data/DeviceScheduleAddressCleanup.swift'),
        str(harness), '-o', str(binary)], check=True)
    subprocess.run([str(binary), str(folder / 'storage')], check=True)
