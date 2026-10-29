#!/usr/bin/env python3
"""Execute production topology projection with BLE/UI replaced at their boundary."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'SunSmart/Common/Data/SceneCapacity.swift').read_text()

def function(text, marker):
    start = text.index(marker)
    opening = text.index('{', start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[start:end]

with tempfile.TemporaryDirectory(prefix='scene-topology-') as directory:
    directory = Path(directory)
    harness = directory / 'Projection.swift'
    harness.write_text('import Foundation\nenum SceneCapacity {\n'
        + function(source, '    struct Failure:') + '\n'
        + '\n'.join(function(source, marker) for marker in [
            '    static func intendedScenes(', '    static func validateTopology(', '    static func label(',
            '    static func unknownNodes(', '    static func nodesRequiringRead(', '    static func validateStore(', '    static func validSceneAllocation(']) + '\n}\n')
    binary = directory / 'Tests'
    subprocess.run(['swiftc', '-parse-as-library', str(root / 'SunSmart/Common/Data/SceneCapacityPolicy.swift'),
                    str(harness), str(root / 'Tests/Scene/SceneTopologyTests.swift'), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
