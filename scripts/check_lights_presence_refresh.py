#!/usr/bin/env python3
"""Execute production Lights lifecycle and refresh decisions with SDK/UI boundaries."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'SunSmart/Main/Device/Lights/Controller/DeviceLightsViewController.swift').read_text()
def member(marker):
    start = source.index(marker)
    end = source.index('\n    }', start) + len('\n    }')
    return source[start:end].replace('private ', '')
production = '\n'.join(member(marker) for marker in [
    'override func viewDidAppear(', 'private func getNodesState()',
    'private func refreshPendingNodeStateIfPossible()'])
fixture = (root / 'Tests/Device/LightsPresenceRefreshTests.swift').read_text()
with tempfile.TemporaryDirectory(prefix='lights-presence-') as directory:
    path = Path(directory)
    (path / 'main.swift').write_text(fixture.replace('// PRODUCTION', production))
    subprocess.run(['swiftc', str(path / 'main.swift'), '-o', str(path / 'tests')], check=True)
    subprocess.run([str(path / 'tests')], check=True)
