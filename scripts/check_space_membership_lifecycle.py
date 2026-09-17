#!/usr/bin/env python3
"""Execute production membership storage, import preparation and leave orchestration.

SDK key decoding, Mesh import, transport and App DB are explicit test boundaries.
"""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'SunSmart/Common/Data/SpaceMembershipCoordinator.swift').read_text()

def section(start, end):
    offset = source.index(start)
    return source[offset:source.index(end, offset)]

with tempfile.TemporaryDirectory(prefix='space-membership-') as directory:
    temp = Path(directory)
    coordinator = section('enum SpaceMembershipCoordinator {', '    static var savedCopiesDirectory:')
    coordinator += section('    @MainActor static func queueLeave(', '\nextension SpaceData {')
    coordinator = coordinator.replace('URL(fileURLWithPath: NSHomeDirectory())\n        .appendingPathComponent("Library/Application Support/SpaceMembership")',
                                      'URL(fileURLWithPath: ' + '"' + str(temp / 'records') + '"' + ')')
    restore = section('    @MainActor\n    func restoreConfiguration(', '    /// Configuration copies')
    test = (root / 'Tests/Group/SpaceMembershipLifecycleTests.swift').read_text().replace('// RESTORE_METHOD', restore)
    # Swift precondition uses a synchronous nonthrowing autoclosure.
    test = test.replace('precondition(try ', 'try expect(')
    helpers = '''
func expect(_ value: @autoclosure () throws -> Bool) rethrows { precondition(try value()) }
'''.replace('precondition(try value())', 'let result = try value(); precondition(result)')
    harness = temp / 'Harness.swift'
    harness.write_text(test + '\n' + coordinator + helpers)
    binary = temp / 'Tests'
    subprocess.run(['swiftc', '-parse-as-library', str(root / 'SunSmart/Common/Data/SpaceMembershipStore.swift'),
                    str(harness), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
