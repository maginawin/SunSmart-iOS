#!/usr/bin/env python3
"""Production configuration-task body + real disk receipts, preparation and completion.

Reuse recovery fixture codecs; SQLite, Mesh loading, cleanup, UIKit and HTTP are
boundaries. Queue coalescing is separately run by check_device_add_cloud_batch.
"""
import os
import subprocess
from pathlib import Path
root = Path(__file__).resolve().parents[1]
subprocess.run(['python3', str(root / 'scripts/check_space_recovery_receipts.py')],
               env={**os.environ, 'SUNSMART_UPLOAD_FLOW': '1'}, check=True)

# Real App SQLite boundary for the narrow cloud outcome write.
import tempfile
import sys
sys.dont_write_bytecode = True
from check_scene_configuration import function
with tempfile.TemporaryDirectory(prefix='space-upload-sqlite-') as directory:
    out = Path(directory)
    sdk = root / '.local-sdk/nordic-sig-mesh-sdk'
    subprocess.run(['swiftc', '-module-cache-path', str(out / 'module-cache'), '-emit-module', '-emit-library', '-module-name', 'SQLite',
        *map(str, sorted((sdk / 'Sources/SQLite').rglob('*.swift'))), '-o', str(out / 'libSQLite.dylib'),
        '-emit-module-path', str(out / 'SQLite.swiftmodule')], check=True)
    method = function((root / 'SunSmart/Common/Data/Database.swift').read_text(), '    @discardableResult func saveCloudSyncOutcome(')
    source = (root / 'Tests/Cloud/SpaceUploadPersistenceTests.swift').read_text().replace('// PRODUCTION', method)
    (out / 'Harness.swift').write_text(source)
    subprocess.run(['swiftc', '-module-cache-path', str(out / 'module-cache'), '-parse-as-library', '-I', directory, '-L', directory, '-lSQLite',
        str(out / 'Harness.swift'), '-o', str(out / 'Tests')], check=True)
    subprocess.run([str(out / 'Tests')], env={**os.environ, 'DYLD_LIBRARY_PATH': directory}, check=True)
