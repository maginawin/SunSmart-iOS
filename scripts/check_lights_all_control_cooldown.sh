#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/LightsAllControlTests.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
python3 - "$repo_root" "$test_dir" <<'PY'
from pathlib import Path
import sys
root, out = map(Path, sys.argv[1:])
source = (root / 'SunSmart/Main/Device/Lights/Controller/DeviceLightsViewController.swift').read_text()
def member(signature):
    start = source.index(signature)
    end = source.index('\n    }', start) + len('\n    }')
    return source[start:end].replace('private ', '').replace('@objc ', '')
members = [member(signature) for signature in [
    'deinit {', 'override func viewDidAppear(', 'override func viewWillDisappear(',
    'private var isAllControlCoolingDown:', 'private func configureAllControlCell(',
    'private func toggleAllLights()', 'private func refreshAllControlCooldown()',
    'private func suspendAllControlCooldownDisplay()', 'private func updateAllOnOffItemUI()',
    'private func allOnAction()', 'private func allOffAction()', '@objc func deviceAllSetting()',
    'func collectionView(_ collectionView: UICollectionView, didSelectItemAt',
    'func collectionView(_ collectionView: UICollectionView, willDisplay',
    'func collectionView(_ collectionView: UICollectionView, didEndDisplaying'
]]
fields = '\n'.join(line.replace('private ', '') for line in source.splitlines()
                   if line.strip().startswith(('private var allControl', 'private var controlAllOn:',
                                               'private var allOnOffState:', 'private var isPageVisible =',
                                               'private var showsAllControl =', 'var devices: [Node]')))
controller = ('final class DeviceLightsViewController: UIViewController {\n' + fields + '''
    let collectionView = UICollectionView()
    let lightControlView = DeviceLightControlView()
    let deviceNameFilterSession = DeviceNameFilterSession()
    var deviceNameFilterObservation: UUID?
    var emergencyBlocked = false
    func showEmergencyControlBlockedIfNeeded(node: Node? = nil) -> Bool { emergencyBlocked }
    func refreshPendingNodeStateIfPossible() {}
    func effectiveCctRange(for nodes: [Node]) -> ClosedRange<UInt16> { 800...20000 }
    func device(at indexPath: IndexPath) -> Node? { nil }
    func repairNodes(nodes: [Node]) {}
    func reloadCollectionItem(node: Node) {}
    func sendLightItemOnOffCommand(node: Node) {}
''' + '\n'.join(members) + '\n}')
cell = (root / 'SunSmart/Main/Device/View/DeviceAllOnOffViewCell.swift').read_text().replace('import UIKit', '')
tests = (root / 'Tests/Device/LightsAllControlCooldownTests.swift').read_text()
(out / 'main.swift').write_text(tests.replace('// PRODUCTION_CONTROLLER_AND_CELL', controller + '\n' + cell))
PY
swiftc -parse-as-library "$test_dir/main.swift" -o "$test_dir/tests"
"$test_dir/tests"
