#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"
swiftc -parse-as-library \
  SunSmart/Main/Device/Gateway/Model/GatewayDeletionCoordinator.swift \
  Tests/Device/GatewayDeletionCoordinatorTests.swift \
  -o /tmp/GatewayDeletionCoordinatorTests
/tmp/GatewayDeletionCoordinatorTests
python3 scripts/check_gateway_deletion_context.py

swiftc -parse-as-library Tests/Device/GatewayForceClearSpacesContractTests.swift \
  -o /tmp/GatewayForceClearSpacesContractTests
/tmp/GatewayForceClearSpacesContractTests \
  SunSmart/Common/Network/NetowrkReqeustApi.swift \
  SunSmart/Common/Network/NetworkRequest.swift \
  SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift \
  SunSmart/Main/Device/Gateway/Model/GatewayModel.swift \
  SunSmart/Common/Data/Database.swift \
  SunSmart/Common/Cloud/CloudSynchronizationManager.swift \
  SunSmart/en.lproj/Localizable.strings \
  SunSmart/zh-Hans.lproj/Localizable.strings

python3 - <<'PY'
from pathlib import Path
controller = Path('SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift').read_text()
deletion = controller.split('private func beginGatewayDeletion()', 1)[1].split('/// 服务器授权绑定网关', 1)[0]
assert 'deleteNodes(' not in deletion
assert 'configuration_deletion_cleanup_pending' not in deletion
assert 'force_delete' not in deletion
assert 'MeshAPI.resetNodes' in deletion
context = Path('SunSmart/Main/Device/Gateway/Model/GatewayDeletionContext.swift').read_text()
assert 'DevicePermanentDeletionContext' not in context
assert 'hasPendingDeletion' in context and 'blocksImport' in context
project = Path('SunSmart.xcodeproj/project.pbxproj').read_text()
for filename in ['GatewayDeletionCoordinator.swift', 'GatewayDeletionContext.swift']:
    assert project.count(f'/* {filename} in Sources */ = ') == 5, filename
for language in ['en', 'zh-Hans']:
    text = Path(f'SunSmart/{language}.lproj/Localizable.strings').read_text()
    for key in ['gateway_deleted_manual_reset', 'gateway_delete_local_failed']:
        assert text.count(f'"{key}" = ') == 1
print('Gateway deletion integration checks passed')
PY
