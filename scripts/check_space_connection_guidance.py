#!/usr/bin/env python3
"""Run production HUD lifecycle methods with isolated UIKit/Mesh boundaries.

This checks ownership and cancellation, not UIKit hit testing or BLE acceptance.
--baseline reads HEAD to reproduce the old pagination-removal failure.
"""
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
CONTROLLER = 'SunSmart/Main/Device/Controller/DevicesViewController.swift'


def section(source, start, end):
    offset = source.index(start)
    return source[offset:source.index(end, offset)]


def method(source, signature):
    start = source.index(signature)
    opening = source.index('{', start)
    depth = 1
    cursor = opening + 1
    while depth:
        depth += (source[cursor] == '{') - (source[cursor] == '}')
        cursor += 1
    return source[start:cursor].replace('private ', '')


baseline = '--baseline' in sys.argv
source = (subprocess.check_output(['git', 'show', f'HEAD:{CONTROLLER}'], cwd=ROOT, text=True)
          if baseline else (ROOT / CONTROLLER).read_text())
methods = [method(source, signature) for signature in [
    'override func viewDidDisappear', 'private func startGuidanceTimer',
    'private func stopGuidanceTimer', '@objc private func guidanceTimeout']]
if 'private func showConnectionGuidance()' in source:
    methods += [method(source, signature) for signature in [
        'private func showConnectionGuidance', 'private func stopConnectionGuidance',
        'override func willMove']]
else:
    # Execute the original creation block, not a reimplementation of its behavior.
    creation = section(source, '            let margin: CGFloat', '            // 获取设备信号')
    methods.append('func showConnectionGuidance() {\n' + creation + '\n}')

connected = section(source, '                if MeshLibManager.manager.isMeshNetworkConnected,',
                    '                    // 判断是否需要申请地址')
methods.append('func deliverConnected() {\n' + connected + '\n}\n}')
fixture = (ROOT / 'Tests/Device/SpaceConnectionGuidanceTests.swift').read_text()
fixture = fixture.replace('// PRODUCTION_METHODS', '\n'.join(methods))
with tempfile.TemporaryDirectory(prefix='space-connection-guidance-') as directory:
    swift = Path(directory) / 'main.swift'
    binary = Path(directory) / 'tests'
    swift.write_text(fixture)
    subprocess.run(['swiftc', str(swift), '-o', str(binary)], check=True)
    result = subprocess.run([str(binary)], text=True, capture_output=True)
    print(result.stdout, end='')
    if baseline:
        if result.returncode != 1 or 'FAIL: pagination removal left an unfinished HUD' not in result.stdout:
            raise SystemExit('Baseline did not reproduce the expected lifecycle failure.\n' + result.stderr)
        print('Baseline reproduced the expected pagination-removal failure.')
    elif result.returncode:
        raise SystemExit(result.stderr or 'Connection guidance regression failed.')
