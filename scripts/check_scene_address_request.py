#!/usr/bin/env python3
"""Exercise the production allocation callback with HTTP/UI/storage boundaries.

No server requests, UIKit session or physical devices are involved. A failing
assertion reports a review regression, not an expected-success characterization.
"""
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
capacity = (ROOT / 'SunSmart/Common/Data/SceneCapacity.swift').read_text()
fixture = (ROOT / 'Tests/Scene/SceneAddressRequestTests.swift').read_text()
fixture = fixture.replace('// PRODUCTION_REQUEST', declaration(controller, '    private func requestSceneAddresses()'))
fixture = fixture.replace('// PRODUCTION_VALIDATION', declaration(capacity, '    static func validSceneAllocation('))
with tempfile.TemporaryDirectory(prefix='scene-address-request-') as directory:
    source = Path(directory) / 'Tests.swift'
    binary = Path(directory) / 'Tests'
    source.write_text(fixture)
    subprocess.run(['swiftc', '-parse-as-library', str(source), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
