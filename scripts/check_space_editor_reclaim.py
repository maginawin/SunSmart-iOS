#!/usr/bin/env python3
"""Execute production Editor reclaim orchestration with transport/storage boundaries."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'SunSmart/Main/Share/Model/BatchSpaceData.swift').read_text()
operation = source[source.index('@MainActor\nenum SpaceEditorReclaim {'):source.index('/// 批量分享space数据')]
store = (root / 'SunSmart/Common/Data/SpaceMembershipStore.swift').read_text()
context = store[store.index('enum SpaceMembershipResponseContext {'):]
test = (root / 'Tests/Group/SpaceEditorReclaimTests.swift').read_text()
with tempfile.TemporaryDirectory(prefix='space-editor-reclaim-') as directory:
    directory = Path(directory)
    harness = directory / 'Harness.swift'
    harness.write_text(test + '\n' + operation + '\n' + context)
    binary = directory / 'Tests'
    subprocess.run(['swiftc', '-parse-as-library', str(harness), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
