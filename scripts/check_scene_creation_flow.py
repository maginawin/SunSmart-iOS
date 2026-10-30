#!/usr/bin/env python3
"""Exercise CREATE controller behavior with deterministic HTTP/UI/time boundaries."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def declaration(source, marker):
    start = source.index(marker)
    opening = source.index('{', start)
    depth, end = 1, opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]


controller = (ROOT / 'SunSmart/Main/Scene/Controller/SceneAddViewController.swift').read_text()
shared = (ROOT / 'Tests/Scene/SceneAddressRequestTests.swift').read_text().split('final class SceneAddressRequestHarness')[0]
for marker in ['enum DispatchQueue', 'enum SceneConfigurationStore', 'enum XWHUDManager', 'final class AllocationCoordinator']:
    shared = shared.replace(declaration(shared, marker), '')
capacity = (ROOT / 'SunSmart/Common/Data/SceneCapacity.swift').read_text()
shared = shared.replace('// PRODUCTION_VALIDATION', declaration(capacity, '    static func validSceneAllocation('))
fixture = (ROOT / 'Tests/Scene/SceneCreationFlowTests.swift').read_text().replace('// SHARED_BOUNDARIES', shared)
methods = '\n'.join(declaration(controller, marker) for marker in [
    '    private func addSceneHandle()',
    '    private func acceptsCreation(',
    '    private func cancelCreationRequest()',
    '    private func updateCreationInteraction()',
    '    private func saveCreatedScene(',
    '    private func failCreation(',
])
fixture = fixture.replace('// PRODUCTION_CREATION', methods)
with tempfile.TemporaryDirectory(prefix='scene-creation-flow-') as directory:
    source = Path(directory) / 'Tests.swift'
    binary = Path(directory) / 'Tests'
    source.write_text(fixture)
    subprocess.run(['swiftc', '-parse-as-library', str(source), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
