#!/usr/bin/env python3
"""Run the production key policy and SDK bridge against isolated persistence."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
policy = root / 'SunSmart/Common/Data/SpaceConfigurationIntegrityPolicy.swift'
source = (root / 'SunSmart/Common/Data/ExportData.swift').read_text()
start = source.index('enum SpaceMeshKeyStore {')
end = source.index('private struct SpaceSnapshotExportIntegritySnapshot:')
bridge = source[start:end]
encoder = source[source.index('private var jsonEncoder:'):start]
site_start = source.index('        if spaceIds != nil {')
site_end = source.index('        return siteData', site_start) + len('        return siteData')
site_export = '\nextension TestSite { func export(spaceIds: [String]?) async -> [String: Any]? {\nvar siteData: [String: Any] = [:]\n' + source[site_start:site_end] + '\n} }\n'
with tempfile.TemporaryDirectory(prefix='space-mesh-keys-') as temp:
    temp = Path(temp)
    extracted = temp / 'Bridge.swift'
    extracted.write_text('import Foundation\n' + encoder + bridge + site_export)
    for test, extra in [('SpaceMeshKeyPolicyTests', []), ('SpaceMeshKeyStoreTests', [str(extracted)])]:
        binary = temp / test
        subprocess.run(['swiftc', '-parse-as-library', str(policy), *extra,
                        str(root / 'Tests/Group' / (test + '.swift')), '-o', str(binary)], check=True)
        subprocess.run([str(binary)], check=True)
