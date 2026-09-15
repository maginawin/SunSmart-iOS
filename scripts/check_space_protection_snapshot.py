#!/usr/bin/env python3
"""真实保护文件、失效边界及固定旧版本读取器的对照基准。"""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
BASELINE = '28b918b2'

def section(text, start, end):
    offset = text.index(start)
    return text[offset:text.index(end, offset)]

def fixtures():
    old = subprocess.check_output(['git', 'show', BASELINE + ':SunSmart/Common/Data/SpaceConfigurationSafety.swift'], cwd=ROOT, text=True)
    blocked = section(old, '    static func isBlocked(meshUUID:', '    static func isBlocked(_ space:')
    blocked = blocked.replace('isBlocked(meshUUID: String, networkId: String)', 'isBlocked(_ request: SpaceProtectionReadRequest)')
    blocked = blocked.replace('key(meshUUID: meshUUID, networkId: networkId)', 'request.scope.storageKey')
    blocked = blocked.replace('recoveryRoot', 'request.root').replace('UserDefaults.standard', 'request.defaults')
    deletion = section(old, '    private static func deletionCleanupPending(', '    static func deletionJournal(')
    return 'enum LegacyProtectionReader {\n' + blocked + deletion + '}\n' + (ROOT / 'Tests/Group/SpaceProtectionReadSnapshotTests.swift').read_text()

if __name__ == '__main__':
    with tempfile.TemporaryDirectory(prefix='space-protection-') as directory:
        source = Path(directory) / 'Tests.swift'
        source.write_text(fixtures())
        binary = Path(directory) / 'tests'
        subprocess.run(['swiftc', '-O', '-D', 'DEBUG', '-D', 'SUNSMART_PERFORMANCE', '-parse-as-library',
            str(ROOT / 'SunSmart/Common/Data/AppPerformance.swift'),
            str(ROOT / 'SunSmart/Common/Data/DeviceScheduleAddressCleanup.swift'),
            str(ROOT / 'SunSmart/Common/Data/SpaceProtectionReadSnapshot.swift'),
            str(source), '-o', str(binary)], check=True)
        subprocess.run([str(binary)], check=True)
