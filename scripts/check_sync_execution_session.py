#!/usr/bin/env python3
"""执行生产 Session/Coordinator；传输、协议对象和专用业务读取使用可控替身。"""
from pathlib import Path
import subprocess
import tempfile
ROOT = Path(__file__).resolve().parents[1]
def region(source, start, end):
    a = source.index(start)
    return source[a:source.index(end, a)]
def main():
    model = (ROOT / 'SunSmart/Main/Space/Model/SyncDevicesCellModel.swift').read_text()
    fixtures = (ROOT / 'Tests/Sync/SyncTaskBuilderFixtures.swift').read_text()
    # Build fixtures already exercise the production compatibility models.
    fixtures = fixtures.replace('case profileToggleTriggerConditionLuxDelete, occupancyLevel', 'case profileToggleTriggerConditionLuxDelete, occupancyLevel, lightControlRestore')
    fixtures = fixtures.replace('struct PJEightKeySwitchData { let name: String }', 'struct PJEightKeySwitchData { let name: String; var requiresActivationBeforeOwnConfiguration = false }')
    fixtures = fixtures.replace('case collectionSchedule(index:', 'case profileSensorProtectionDisable, profileSensorTargetEnable, batteryPowerSwitchKeyConfig\n    case collectionSchedule(index:')
    fixtures = fixtures.replace('return Self.testHandles', 'switch self { case .configuration(let node, _), .delete(let node, _): return node.testHandles }')
    fixtures = fixtures.replace('final class MeshNetwork {', 'final class MeshNetwork { var nodes: [Node] = []')
    fixtures = fixtures.replace('final class Node: Equatable {', '''final class Node: Equatable {
    var testHandles: [MeshMessageHandle] = []
    var state = true
    var updates = 0
    var applied = false
    func updateData(message: Int, isSuccess: Bool, model: Int?) { updates += 1; applied = isSuccess }
    func clearSyncStateCache() {}
    var sunricherVendorModel: Int? { 1 }
    func sendHandleCompleteIdentify(deviceBlinkMode: DeviceBlinkMode) {}
''')
    fixtures = fixtures.replace('final class MeshMessageHandle {', '''final class MeshMessageHandle {
    var address: Address? = 1
    var model: TestVendorModel? = nil
    var message = 0
    var isSuccessful = true
''').replace('model: Int?)', 'model: TestVendorModel?)')
    source = 'import Foundation\n' + fixtures
    node = (ROOT / 'SunSmart/Common/Data/Node+SyncData.swift').read_text()
    source += region(node, 'enum NodeSyncData {', 'extension Group {')
    source += region(model, 'enum SyncDevicesState', 'struct SunricherVendorSetUnacknowledged')
    source += region(model, 'class SyncDevicesSectionModel', '/// 当前同步轮次的显示上下文')
    source += (ROOT / 'Tests/Sync/SyncExecutionSessionFixtures.swift').read_text()
    for name in ['SyncExecutionSession', 'SyncExecutionSession+Tasks', 'SyncExecutionSession+Result', 'SyncRetryPolicy']:
        source += (ROOT / f'SunSmart/Main/Space/Model/{name}.swift').read_text().replace('import NordicSigMeshSDK', '')
    controller = (ROOT / 'SunSmart/Main/Space/Controller/SyncDevicesViewController.swift').read_text()
    builder = (ROOT / 'SunSmart/Main/Space/Model/SyncTaskPlanBuilder.swift').read_text()
    source += builder[builder.index('struct SyncTaskPlanResult {'):]
    source += '\nfinal class SessionPlanInstallationHarness {\n'
    source += (ROOT / 'Tests/Sync/SyncSessionPlanInstallationHarness.txt').read_text()
    source += region(controller, '    private func installTaskPlan(', '    override func viewDidAppear(').replace('private func', 'func', 1) + '\n}\n'
    with tempfile.TemporaryDirectory(prefix='sync-execution-session-') as directory:
        production = Path(directory) / 'Production.swift'
        production.write_text(source)
        binary = Path(directory) / 'Tests'
        shared = [str(ROOT / f'SunSmart/Main/Space/Model/{name}.swift') for name in ['SyncRunLifecycle', 'SyncSessionCoordinator', 'SyncCommandStopGate', 'SyncOperationResultPolicy']]
        subprocess.run(['swiftc', '-parse-as-library', *shared, str(production), str(ROOT / 'Tests/Sync/SyncExecutionSessionTests.swift'), '-o', str(binary)], check=True)
        subprocess.run([str(binary)], check=True)
        subprocess.run(['swiftc', '-parse-as-library', *shared, str(ROOT / 'Tests/Sync/SyncSessionCoordinatorTests.swift'), '-o', str(binary)], check=True)
        subprocess.run([str(binary)], check=True)
if __name__ == '__main__': main()
