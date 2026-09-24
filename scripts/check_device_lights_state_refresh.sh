#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/DeviceLightsStateRefreshTests.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
python3 - "$repo_root" "$test_dir" <<'PY'
from pathlib import Path
import sys
root, out = map(Path, sys.argv[1:])
source = (root / 'SunSmart/Main/Device/Lights/Controller/DeviceLightsViewController.swift').read_text()
def method(signature):
    start = source.index(signature)
    end = source.index('\n    }', start) + len('\n    }')
    return source[start:end].replace('private func', 'func')
methods = [method(signature) for signature in [
    'override func viewDidAppear(', 'override func viewWillDisappear(',
    'private func getNodesState()', 'private func refreshPendingNodeStateIfPossible()',
    'func meshNetworkManager(bluetoothDidUpdateState',
    'func meshNetworkManager(_ manager: MeshNetworkManager, bearerDidOpen'
]]
fields = '\n'.join(line.replace('private ', '') for line in source.splitlines()
                   if 'private var isPageVisible =' in line or 'private var needsNodeStateRefresh =' in line)
controller = ('final class DeviceLightsViewController: UIViewController {\n' + fields +
              '\nlet collectionView = CollectionView()\nvar devices = [1]\n' + '\n'.join(methods) + '\n}')
tests = (root / 'Tests/DeviceLightsStateRefreshTests.swift').read_text()
(out / 'main.swift').write_text(tests.replace('// PRODUCTION_CONTROLLER_METHODS', controller))
PY
swiftc -parse-as-library "$test_dir/main.swift" -o "$test_dir/test"
"$test_dir/test"
