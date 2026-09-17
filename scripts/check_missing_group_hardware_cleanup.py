#!/usr/bin/env python3
"""隔离运行生产无组收尾与回执方法；不连接云端或蓝牙。"""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]

def method(text, signature):
    start = text.index(signature)
    opening = text.index('{', start)
    depth = 1
    end = opening + 1
    while depth:
        if text[end] == '{':
            depth += 1
        elif text[end] == '}':
            depth -= 1
        end += 1
    return text[start:end]

node = (ROOT / 'SunSmart/Common/Data/Node+SyncData.swift').read_text()
cleanup = (ROOT / 'SunSmart/Common/Data/SpaceSyncCleanupCoordinator.swift').read_text()
production = 'import Foundation\nextension Node {\n'
for signature in ['func getMissingGroupCleanupProfiles()', 'func getNodeNeedDeleteSceneDatas(']:
    production += method(node, signature) + '\n'
production += '}\nextension MissingGroupSubscriptionCleanup {\n'
production += method(cleanup, 'static func acknowledge(') + '\n}\n'

with tempfile.TemporaryDirectory(prefix='missing-group-cleanup-') as directory:
    source = Path(directory) / 'Production.swift'
    source.write_text(production)
    binary = Path(directory) / 'Tests'
    subprocess.run(['swiftc', '-parse-as-library', str(source),
                    str(ROOT / 'SunSmart/Common/Data/SceneDeleteCapability.swift'),
                    str(ROOT / 'Tests/Sync/MissingGroupHardwareCleanupTests.swift'),
                    '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
