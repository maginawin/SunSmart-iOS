#!/usr/bin/env python3
"""Execute production Switch model, SQL scope, deletion and journal against temporary SQLite."""
from pathlib import Path
import subprocess
import tempfile
import sys
root = Path(__file__).resolve().parents[1]
sdk = Path(sys.argv[1]) if len(sys.argv) > 1 else root.parent.parent / 'nordic-sig-mesh-sdk-worktrees/one-dev'
def read(p): return (root / p).read_text()
def section(s, a, b): return s[s.index(a):s.index(b, s.index(a))]
model = read('SunSmart/Main/Device/Switches/Model/DeviceSwitchData.swift')
model = model[:model.index('    var batteryPowerSwitchData:')] + '\n}'
model = model.replace('import NordicSigMeshSDK', '')
db = read('SunSmart/Common/Data/Database.swift')
records = section(db, 'extension DeviceSwitchData {', '\nextension DeviceDongleData')
transaction = section(db, '    @discardableResult\n    func configurationTransaction(', '\n}\n')
repo = read('SunSmart/Main/Device/Device1.5/NEightKeySwitches/Repositories/PJEightKeySwitchRepository.swift')
repo = ('final class PJEightKeySwitchRepository {\nstatic let shared = PJEightKeySwitchRepository()\n' +
        section(repo, '    private static let tableName', '    static func initDatabase()') +
        section(repo, '    @discardableResult\n    func delete(for', '\n}\n\nstruct PJEightKeySwitchSharePayload') + '\n}')
cleanup = read('SunSmart/Common/Data/DevicePermanentDeletionCleanup.swift').split('enum SwitchRecordDeletion')[1]
power = read('SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift')
power = (section(power, 'final class PJEightKeySwitchData:', '    convenience init(') +
         section(power, '    override func copy()', '    var isACPowerSwitch:') + '\n}')
mesh = read('SunSmart/Common/Data/MeshNetwork+SunSmart.swift')
unbind = ('extension Node {\n' + section(mesh, '    func commitSuccessfulEnOceanSwitchUnbind(',
          '    /// 节点从 Space 删除时') + '\n}')
parts = [read('Tests/Group/SwitchRecordScopeTests.swift'), model, power, records, repo, unbind,
         read('SunSmart/Main/Device/Switches/Model/KineticSwitchBindingPolicy.swift'),
         read('SunSmart/Common/Data/DeviceScheduleAddressCleanup.swift'),
         'enum SwitchRecordDeletion' + cleanup,
         'extension SunSmartDataManager {\n' + transaction + '\n}']
with tempfile.TemporaryDirectory(prefix='switch-record-scope-') as directory:
    temp = Path(directory)
    sources = sorted((sdk / 'Sources/SQLite').rglob('*.swift'))
    assert sources, f'SQLite source missing: {sdk}'
    subprocess.run(['swiftc', '-emit-module', '-emit-library', '-module-name', 'SQLite',
                    *map(str, sources), '-o', str(temp / 'libSQLite.dylib'),
                    '-emit-module-path', str(temp / 'SQLite.swiftmodule')], check=True)
    harness = temp / 'Harness.swift'
    harness.write_text('\n'.join(parts))
    binary = temp / 'Tests'
    subprocess.run(['swiftc', '-parse-as-library', '-I', str(temp), '-L', str(temp), '-lSQLite',
                    str(harness), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
