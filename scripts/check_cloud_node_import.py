#!/usr/bin/env python3
"""Run the cloud adapter with actual SDK optional-field decoding and the App staging gate.

The remaining Node model and persistence boundaries are doubles. --snapshot reads
a private response in memory only; it never prints or copies credentials.
"""
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
sdk = root / '.local-sdk/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/nRFMeshProvision'

def section(text, start, end):
    offset = text.index(start)
    return text[offset:text.index(end, offset)]

imports = (root / 'SunSmart/Common/Data/ImportData.swift').read_text()
node = (sdk / 'Mesh Model/Node.swift').read_text()
hex_source = (sdk / 'Type Extensions/Int+Hex.swift').read_text()
test = (root / 'Tests/Group/CloudNodeImportTests.swift').read_text()
test = test.replace('// SDK_OPTIONAL_FIELDS', section(node,
    '        if let companyIdentifierAsString = try container.decodeIfPresent',
    '        self.features = try container.decodeIfPresent'))
test = test.replace('// IMPORT_STAGING_GATE', section(imports,
    '            guard groups.count == groupDicts.count else {', '            var appliedOutcome:'))
recovery = (root / 'SunSmart/Main/Space/Controller/SpaceRecoveryViewController.swift').read_text()
test = test.replace('// RECOVERY_MESSAGE', section(recovery, '    static func message(', '    override func viewDidLoad()'))
parts = [test, section(hex_source, 'internal extension UInt16 {', 'internal extension Int16 {'),
         section(imports, 'enum CloudNodeImport {', '\n/// Stage timings')]
with tempfile.TemporaryDirectory(prefix='cloud-node-import-') as directory:
    directory = Path(directory)
    harness = directory / 'Harness.swift'
    harness.write_text('\n'.join(parts))
    binary = directory / 'Tests'
    subprocess.run(['swiftc', '-D', 'DEBUG', '-parse-as-library', str(harness), '-o', str(binary)], check=True)
    args = sys.argv[sys.argv.index('--snapshot') + 1:][:1] if '--snapshot' in sys.argv else []
    subprocess.run([str(binary), *args], check=True)
