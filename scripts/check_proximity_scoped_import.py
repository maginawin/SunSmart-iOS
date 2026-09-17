#!/usr/bin/env python3
"""Execute production adapters with SDK/storage doubles; no simulator or private fixtures."""
from pathlib import Path
import subprocess
import tempfile
import sys

root = Path(__file__).resolve().parents[1]
baseline = '--baseline' in sys.argv

def source(path):
    if baseline:
        return subprocess.check_output(['git', 'show', 'HEAD:' + path], cwd=root, text=True)
    return (root / path).read_text()

def section(text, start, end):
    return text[text.index(start):text.index(end, text.index(start))]

adapter = source('SunSmart/Main/Group/Model/GroupProximityLightingData.swift')
start = 'enum ProximityLightingTopologyContext' if 'enum ProximityLightingTopologyContext' in adapter else 'enum ProximityLightingTopologyPlanner'
space_controller = source('SunSmart/Main/Space/Controller/SpaceViewController.swift')
repair_presentation = section(space_controller, '    private func presentProximityLightingRepairSyncIfNeeded()', '\n    // MARK: - Request')
repair_recomputation = section(repair_presentation, '        let preparation =', '        guard !datas.isEmpty else { return }')
test_source = (root / 'Tests/Group/ProximityLightingScopedImportTests.swift').read_text()
safety = source('SunSmart/Common/Data/SpaceConfigurationSafety.swift')
receipt_methods = section(safety, '    static func preservesLocalChanges(', '\n    /// Called only after successful local Space removal.')
if 'static func hasPendingReferenceCleanup(' in safety:
    receipt_methods = section(safety, '    static func hasPendingReferenceCleanup(', '\n    static func finishSyncReferenceCleanup(') + receipt_methods
# Only dependencies/storage boundaries are doubled. Receipt decisions run the
# actual safety methods against an isolated UserDefaults suite.
test_source = test_source.replace('// RECEIPT_METHODS', receipt_methods.replace('UserDefaults.standard', 'testDefaults'))
parts = [source('SunSmart/Common/Data/AppPerformance.swift'), source('SunSmart/Common/Data/SpaceProtectionReadSnapshot.swift'), section(source('SunSmart/Common/Data/ImportData.swift'), 'final class SiteImportTrace', '\nstruct SpaceImportOutcome'),
         section(adapter, start, '\nextension SpaceData'),
         source('SunSmart/Common/Data/DeviceScheduleAddressCleanup.swift'),
         source('SunSmart/Common/Data/SpaceConfigurationIntegrityPolicy.swift'),
         source('SunSmart/Common/Data/DevicePermanentDeletionCleanup.swift').replace('import NordicSigMeshSDK', ''),
         source('SunSmart/Common/Data/SiteDeviceOwnershipReconciler.swift').replace('import NordicSigMeshSDK', ''),
         source('SunSmart/Main/Group/Model/ProximityLightingLifecycleCoordinator.swift').replace('import NordicSigMeshSDK', ''),
         section(source('SunSmart/Common/Data/ImportData.swift'), 'private struct ProximityLightingImportPreflight', '\n#if DEBUG'),
         'extension Node {\n' + section(source('SunSmart/Common/Data/Node+SyncData.swift'), '    func getNodeSyncProximityLighting(', '    /// 获取网关设备同步的配置') + '\n}',
         'final class ImportRepairHarness {\n'
         '    var pendingProximityLightingRepairRequest: Bool? = true\n'
         '    var capturedDatas: [(node: Node, syncData: NodeSyncData)]?\n'
         '    func recompute(latestSpace: SpaceData) {\n' + repair_recomputation +
         '        capturedDatas = datas\n    }\n}',
         test_source,
         (root / 'Tests/Group/DeviceDeletionRecoveryExecutionTests.swift').read_text(),
         (root / 'Tests/Group/SiteDeviceOwnershipExecutionTests.swift').read_text()]
with tempfile.TemporaryDirectory(prefix='proximity-scoped-import-') as directory:
    directory = Path(directory)
    harness = directory / 'Harness.swift'
    harness.write_text('\n'.join(parts))
    policy = directory / 'Policy.swift'
    policy.write_text(source('SunSmart/Main/Group/Model/ProximityLightingTopologyPolicy.swift'))
    reconciler = directory / 'Reconciler.swift'
    reconciler.write_text(source('SunSmart/Main/Group/Model/ProximityLightingTopologyReconciler.swift'))
    binary = directory / 'ScopedImportTests'
    subprocess.run(['swiftc', '-parse-as-library', str(root / 'Pods/SwiftyJSON/Source/SwiftyJSON/SwiftyJSON.swift'),
                    str(policy), str(reconciler), str(harness), '-o', str(binary)], check=True)
    fixture_args = sys.argv[sys.argv.index('--snapshot') + 1:][:1] if '--snapshot' in sys.argv else []
    sys.exit(subprocess.run([str(binary), *fixture_args]).returncode)
