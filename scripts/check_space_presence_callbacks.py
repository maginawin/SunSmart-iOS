#!/usr/bin/env python3
"""Execute Space's production presence callbacks with deterministic UI/transport boundaries."""
from pathlib import Path
import re
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'SunSmart/Main/Space/Controller/SpaceViewController.swift').read_text()


def declaration(marker):
    start = source.index(marker)
    opening = source.index('{', start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]


members = [declaration(marker) for marker in [
    'private var canHandleSpacePresenceCallbacks:',
    'private func showTransferPermissionAlert()',
    'private func presentPendingTransferPermissionAlert()',
    'private func disableEditorPermission()',
    'private func checkTheSpaceMembersRequest()',
    'private func checkMeshMemberPermissions()',
    'private func startUserAskTimer()',
    'private func stopUserAskTimer()',
    '@objc private func userPermissionAskTimeout()',
    'private func startHeartbeatTimer()',
    'private func stopHeartbeatTimer()',
    'private func startNodePresenceObservation()',
    'private func stopSpacePresenceTracking(reason:',
    '@objc private func heartbeatRequest()',
    'private func handleSpacePermissionLoss()',
    'override func viewDidDisappear(',
    'func meshNetworkManager(_ manager: MeshNetworkManager,',
]]
for name in ['hasStoppedPresenceTracking', 'hasHandledPermissionLoss',
             'hasPendingTransferPermissionAlert', 'transferPermissionAlert',
             'isHandlingExternalVendorMessages', 'cloudPermissionValidation',
             'meshPermissionValidation', 'nodePresenceObservation']:
    members.append(re.search(r'^    private (?:weak )?var ' + name + r'[^\n]+', source, re.M).group())

production = '\n'.join(members).replace('private ', '').replace('@objc ', '')
# Only Objective-C selector syntax is adapted; scheduling, guards and callback bodies remain production code.
production = re.sub(r'#selector\((\w+)\)', r'"\1"', production)
fixture = (root / 'Tests/Space/SpacePresenceCallbackTests.swift').read_text()
fixture = fixture.replace('// INSERT_PRODUCTION_MEMBERS', production)
fixture += '\n' + declaration('private enum SpacePresenceStopReason:').replace('private ', '')
with tempfile.TemporaryDirectory(prefix='space-presence-callbacks-') as directory:
    path = Path(directory)
    harness = path / 'Harness.swift'
    harness.write_text(fixture)
    subprocess.run(['swiftc', '-parse-as-library', str(harness), '-o', str(path / 'Tests')], check=True)
    subprocess.run([str(path / 'Tests')], check=True)
