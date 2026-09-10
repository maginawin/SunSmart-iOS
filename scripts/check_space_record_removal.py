#!/usr/bin/env python3
"""Execute the production local deletion path against isolated stores."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'SunSmart/Common/Data/MeshNetwork+SunSmart.swift').read_text()
start = source.index('    var canDeleteEmptySpaceRecords: Bool')
end = source.index('\n}\n\nextension MeshLibManager', start)
method = source[start:end]
with tempfile.TemporaryDirectory(prefix='space-removal-') as temp:
    temp = Path(temp)
    bridge = temp / 'Production.swift'
    bridge.write_text('import Foundation\nextension SpaceData {\n' + method + '\n}\n')
    binary = temp / 'Tests'
    subprocess.run(['swiftc', '-parse-as-library', str(bridge),
                    str(root / 'Tests/Group/SpaceRecordRemovalTests.swift'), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
