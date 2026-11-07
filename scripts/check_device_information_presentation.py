#!/usr/bin/env python3
"""Run Information's production refresh/lifecycle methods with UI/SDK boundaries.

The full source compiles its Foundation snapshot/session on macOS; extracted
controller methods use deterministic UI/SDK doubles. This is not a UIKit run.
"""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
controller = root / 'SunSmart/Main/Device/Controller/DeviceInformationViewController.swift'
source = controller.read_text()


def member(marker):
    start = source.index(marker)
    end = source.index('\n    }', start) + len('\n    }')
    return source[start:end].replace('private ', '')


production = '\n'.join(member(marker) for marker in [
    'override func viewWillAppear(', 'override func viewDidAppear(',
    'override func viewWillDisappear(', 'override func viewDidDisappear(',
    'private func dismissTTLAlerts()', 'private func requestInitialTTL()',
    'private func requestGatewayTime()', 'private func requestLightTime()',
    'private func getData()', 'private func refreshRSSI()',
    'private func reloadInformation()', 'func numberOfSections(',
    'func tableView(_ tableView: UITableView, numberOfRowsInSection',
    'func tableView(_ tableView: UITableView, viewForHeaderInSection',
])
fixture = (root / 'Tests/Device/DeviceInformationPresentationTests.swift').read_text()
with tempfile.TemporaryDirectory(prefix='device-information-') as directory:
    path = Path(directory)
    (path / 'main.swift').write_text(fixture.replace('// PRODUCTION', production))
    subprocess.run(['swiftc', str(controller), str(path / 'main.swift'),
                    '-o', str(path / 'tests')], check=True)
    subprocess.run([str(path / 'tests')], check=True)
