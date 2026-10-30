#!/usr/bin/env python3
"""执行生产 Session/Coordinator；传输、协议对象和专用业务读取使用可控替身。"""
from pathlib import Path
import subprocess
import tempfile
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
def region(source, start, end):
    a = source.index(start)
    return source[a:source.index(end, a)]
def main():
    model = (ROOT / 'SunSmart/Main/Space/Model/SyncDevicesCellModel.swift').read_text()
    fixtures = (ROOT / 'Tests/Sync/SyncTaskBuilderFixtures.swift').read_text()
    fixtures = fixtures.replace('struct Scene { let name: String; let number: UInt16 }', 'struct Scene { let name: String; let number: UInt16; var testNeedsSync = true }')
    # Build fixtures already exercise the production compatibility models.
    fixtures += """
extension HDBDeviceSyncTask {
    func persist(result: [MeshMessageHandle]) -> Bool { persistCalls += 1; return result.allSatisfy { $0.isSuccessful } }
}
"""
    fixtures = fixtures.replace('case profileToggleTriggerConditionLuxDelete, occupancyLevel', 'case profileToggleTriggerConditionLuxDelete, occupancyLevel, lightControlRestore')
    fixtures = fixtures.replace('struct PJEightKeySwitchData { let name: String }', 'struct PJEightKeySwitchData { let name: String; var requiresActivationBeforeOwnConfiguration = false }')
    fixtures = fixtures.replace('case collectionSchedule(index:', 'case profileSensorProtectionDisable, profileSensorTargetEnable, batteryPowerSwitchKeyConfig\n    case collectionSchedule(index:')
    fixtures = fixtures.replace('return Self.testHandles', 'switch self { case .configuration(let node, _), .delete(let node, _): return node.testHandles }')
    fixtures = fixtures.replace('final class MeshNetwork {', 'final class MeshNetwork { var nodes: [Node] = []')
    fixtures = fixtures.replace('final class Node: Equatable {', '''final class Node: Equatable {
    var fingerprint = String(repeating: "ab", count: 32)
    var sceneBlocked = false
    var sceneAuthorized = true
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
    var sceneContext: SceneMessageContext?
    var address: Address? = 1
    var model: TestVendorModel? = nil
    var message: Any = 0
    var isSuccessful = true
''').replace('model: Int?)', 'model: TestVendorModel?)').replace('updateData(message: Int', 'updateData(message: Any')
    fixtures += '''
struct SceneMessageContext {
    let identity: TimedSchedulerNodeIdentity
    var number: UInt16 = 42
    var removes = false
    init(identity: TimedSchedulerNodeIdentity?) { self.identity = try! SceneConfiguration.identity(identity!) }
    func matches(node: Node) -> Bool { node.sceneConfigurationIdentity == identity && node.sceneAuthorized && (removes || !node.sceneBlocked) }
}
extension Node {
    var timedSchedulerIdentity: TimedSchedulerNodeIdentity? {
        .init(nodeUUID: "00000000-0000-0000-0000-000000000001", unicastAddress: String(format: "%04X", primaryUnicastAddress), deviceKeyFingerprint: fingerprint)
    }
}
enum SceneAcknowledgementProbe { static var accepted = 0 }
extension MeshNetworkManager { var realNodes: [Node] { meshNetwork?.nodes ?? [] } }
'''
    source = 'import Foundation\nstruct SceneDelete {}\nstruct SceneStore { let scene: UInt16; init(_ scene: UInt16) { self.scene = scene } }\n' + fixtures
    node = (ROOT / 'SunSmart/Common/Data/Node+SyncData.swift').read_text()
    source += region(node, 'enum NodeSyncData {', 'extension Group {')
    source += region(model, 'enum SyncDevicesState', 'struct SunricherVendorSetUnacknowledged')
    source += region(model, 'class SyncDevicesSectionModel', '/// 当前同步轮次的显示上下文')
    source += (ROOT / 'Tests/Sync/SyncExecutionSessionFixtures.swift').read_text()
    ack_source = (ROOT / 'SunSmart/Main/Space/Model/SyncExecutionSession+Acknowledgement.swift').read_text()
    hdb_ack = region(ack_source, '        if case .configuration(_, .hdb(let task))', '        if let operation =')
    source = source.replace('func received(handle: MeshMessageHandle, statusMessage: Int, model: SyncCellModel, messageHandles: [MeshMessageHandle]) {}',
        'func received(handle: MeshMessageHandle, statusMessage: Int, model: SyncCellModel, messageHandles: [MeshMessageHandle], cacheOnly: Bool = false) {\n' + hdb_ack + '\nSceneAcknowledgementProbe.accepted += 1\n}')
    for name in ['SyncExecutionSession', 'SyncExecutionSession+Tasks', 'SyncExecutionSession+Result', 'SyncRetryPolicy']:
        source += (ROOT / f'SunSmart/Main/Space/Model/{name}.swift').read_text().replace('import NordicSigMeshSDK', '')
    from check_scene_configuration import function
    identity_source = (ROOT / 'SunSmart/Main/Scene/Model/SceneTargetResolver.swift').read_text()
    source += '\nextension Node {\n' + function(identity_source, '    var sceneConfigurationIdentity:') + '\n}\n'
    coordinator_source = (ROOT / 'SunSmart/Main/Scene/Model/SceneSaveCoordinator.swift').read_text()
    source += """
struct DiagnosticSceneConfiguration { var pendingOperations: [Int] = [] }
struct DiagnosticSceneInfo { var configuration: DiagnosticSceneConfiguration? = nil }
extension Scene { var needSync: Bool { testNeedsSync }; var info: DiagnosticSceneInfo { DiagnosticSceneInfo() } }
enum SceneCommandBuilder {
    static var current = true
    static func captureConfigurations() -> () -> Bool { { current } }
}
struct SyncSceneScheduleTaskBuilder {
    static var devices: [SyncDevicesModel] = []
    func appendScene(to writes: SyncDevicesSectionModel, removal: SyncDevicesSectionModel, scene: Scene) {
        writes.devices = Self.devices
    }
}
final class FormalSaveBoundary {
    var generation = UUID()
    var committedNumber: UInt16? = 42
    var draft: String?, confirmation: String?
    var formalStarted = true
    var session: SyncExecutionSession?
    var onFormalCompletion: ((Bool) -> Void)?
    let makeEnvironment: () -> SyncExecutionEnvironment
    init(environment: SyncExecutionEnvironment) { makeEnvironment = { environment } }
"""
    source += function(coordinator_source, '    private func startFormal(').replace('private func', 'func', 1)
    source += '\n' + function(coordinator_source, '    func cancel()') + '\n}\n'
    restore = (ROOT / 'SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift').read_text()
    source += """
final class RestoreSceneBoundary {
    var deferredSceneSession: SyncExecutionSession?
    var deferredSceneGeneration = UUID()
    var deferredSceneCancelled = false
    let makeEnvironment: () -> SyncExecutionEnvironment
    init(environment: SyncExecutionEnvironment) { makeEnvironment = { environment } }
"""
    # Only transport construction is injected; execute the controller's real
    # Scene adapter, completion ownership, stop and dismiss prefix.
    source += function(restore, '    private func runDeferredSceneTask(').replace('private func', 'func', 1).replace('let environment = SyncExecutionEnvironment()', 'let environment = makeEnvironment()')
    stop = function(restore, '    @objc private func stopAddBtnClick()')
    source += '\nfunc stop() {\n' + region(stop, '        deferredSceneCancelled = true', '        MeshAPI.cancelFastAddAwaitOperations()') + '\n}\n'
    dismiss = function(restore, '    private func dismiss()')
    source += '\nfunc dismiss() {\n' + region(dismiss, '        deferredSceneGeneration = UUID()', '        if automationRestore') + '\n}\n}\n'
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
        identity_models = [str(ROOT / 'SunSmart/Main/Timed/Model/TimedSchedulerSlotPolicy.swift'), str(ROOT / 'SunSmart/Main/Scene/Model/SceneConfiguration.swift')]
        subprocess.run(['swiftc', '-parse-as-library', *shared, *identity_models, str(production), str(ROOT / 'Tests/Sync/SyncExecutionSessionTests.swift'), '-o', str(binary)], check=True)
        subprocess.run([str(binary)], check=True)
        subprocess.run(['swiftc', '-parse-as-library', *shared, str(ROOT / 'Tests/Sync/SyncSessionCoordinatorTests.swift'), '-o', str(binary)], check=True)
        subprocess.run([str(binary)], check=True)
if __name__ == '__main__': main()
