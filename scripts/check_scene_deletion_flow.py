#!/usr/bin/env python3
"""Production deletion intent, SQLite transactions, resolver and handle application.
Only SDK transport/session/UI boundaries are deterministic; never operates a Space.
"""
from pathlib import Path
import subprocess
import tempfile
import sys
sys.dont_write_bytecode = True
from check_scene_configuration import scene_authority_support, ROOT, target_sources, function, section

with tempfile.TemporaryDirectory(prefix='scene-deletion-') as directory:
    tmp = Path(directory)
    sdk = (ROOT / '.local-sdk/nordic-sig-mesh-sdk').resolve()
    subprocess.run(['swiftc', '-emit-module', '-emit-library', '-module-name', 'SQLite',
        *map(str, sorted((sdk / 'Sources/SQLite').rglob('*.swift'))), '-o', str(tmp / 'libSQLite.dylib'),
        '-emit-module-path', str(tmp / 'SQLite.swiftmodule')], check=True)
    sources = target_sources(tmp) + [ROOT / 'SunSmart/Main/Timed/Model/TimedSchedulerSlotPolicy.swift',
        ROOT / 'SunSmart/Main/Scene/Model/SceneConfiguration.swift',
        ROOT / 'SunSmart/Common/Data/SceneDeleteCapability.swift',
        sdk / 'Sources/NordicSigMeshSDK/MeshLib/Scene/SceneRegisterPolicy.swift',
        ROOT / 'Tests/Scene/SceneDeletionFlowTests.swift']
    mesh = (ROOT / 'SunSmart/Common/Data/MeshNetwork+SunSmart.swift').read_text()
    binding = (ROOT / 'SunSmart/Main/Timed/Model/TimedSchedulerBindings.swift').read_text()
    def write(name, text):
        path = tmp / name; path.write_text(text); sources.append(path)
    support = (ROOT / 'Tests/Scene/SceneSaveTestSupport.swift').read_text()
    support = scene_authority_support(support)
    support = support.replace('// ACTUAL_TRANSACTION', function((ROOT / 'SunSmart/Common/Data/Database.swift').read_text(), '    @discardableResult\n    func configurationTransaction('))
    support = support.replace('// ACTUAL_TIMED_COMMIT', section('SunSmart/Main/Timed/Model/TimedSchedulerBindings.swift', '    static func commit(_ plan:', '    static func reserveForDeletion('))
    support = support.replace('// ACTUAL_UPDATE_GROUP', function(mesh, '    func updateGroupSyncState()'))
    support += section('SunSmart/Common/Data/Database.swift', 'extension SceneInfo {', '\nextension Schedule {')
    write('Storage.swift', support)
    for name in ['SceneConfigurationStore', 'SceneServer']:
        write(name + '.swift', (ROOT / ('SunSmart/Main/Scene/Model/' + name + '.swift')).read_text().replace('import NordicSigMeshSDK', ''))
    write('Commands.swift', (ROOT / 'SunSmart/Main/Scene/Model/SceneCommandBuilder.swift').read_text().split('private var sceneMessageContextKey')[0].replace('import NordicSigMeshSDK', '').replace('import ObjectiveC', ''))
    write('Transport.swift', (ROOT / 'Tests/Scene/SceneCommandTestSupport.swift').read_text().split('extension SceneInfo')[0])
    node_update = function(mesh, '    func updateData(message: MeshMessage,')
    deletion = node_update[node_update.index('        case is SceneDelete:'):node_update.index('        case is SchedulerActionSet:')]
    lifecycle = 'import Foundation\nextension Node {\n' + function(binding, '    @discardableResult\n    func applyMessageHandle(')
    lifecycle += '\n' + function(mesh[mesh.index('    func delete(sceneId: SceneNumber)', mesh.index('    func delete(sceneId: SceneNumber)') + 1):], '    func delete(sceneId: SceneNumber)')
    lifecycle += '\n' + function((ROOT / 'SunSmart/Common/Data/SceneCapacity.swift').read_text(), '    func needsSceneRemoval(')
    node_sync = (ROOT / 'SunSmart/Common/Data/Node+SyncData.swift').read_text()
    lifecycle += '\n' + '\n'.join(function(node_sync, marker) for marker in ['    func getNodeNeedDeleteSceneDatas(', '    func getNodeSyncSceneDatas('])
    lifecycle += '\nvar syncReadGroup: Group? { group }\nvar scenes: [Scene] { MeshNetworkManager.instance.scenes.filter { scene in sceneExecuteDatas.contains { $0.sceneNumber == scene.number } } }\n'
    lifecycle += '\nfunc updateData(message: Any, isSuccess: Bool, model: Model?) { guard isSuccess else { return }; switch message {\n' + deletion + '\ndefault: break\n} }\n'
    lifecycle += function(mesh, '    @discardableResult\n    func completeGroupSceneRemoval(') + '\n}\nextension Scene {\n'
    lifecycle += '\n'.join(function((ROOT / 'SunSmart/Common/Data/Node+MessageHandles.swift').read_text(), marker) for marker in ['    func getDeleteMessageHandles(node:', '    func getSyncMessageHandles(node:']) + '\n}\n'
    lifecycle += 'struct SchedulerContextBoundary { func matches(node: Node) -> Bool { true } }\nextension MeshMessageHandle { var timedSchedulerContext: SchedulerContextBoundary? { nil } }\n'
    write('Lifecycle.swift', lifecycle)
    result_source = (ROOT / 'SunSmart/Main/Space/Model/SyncExecutionSession+Result.swift').read_text()
    scene_branch = result_source[result_source.index('        if messageHandles.contains(where: { $0.sceneContext != nil })'):result_source.index('        resultMessageHandles.forEach { handle in')]
    write('SceneResult.swift', 'extension SyncExecutionSession { func applySceneBatch(_ resultMessageHandles: [MeshMessageHandle], messageHandles: [MeshMessageHandle]) -> Bool {\n' + scene_branch + '\nreturn false\n} }')

    builder_support = (ROOT / 'Tests/Scene/SceneSyncTaskBuilderSupport.swift').read_text().split('enum MissingGroupSubscriptionCleanup')[0]
    builder_support = builder_support.replace('final class SyncDevicesSectionModel {', 'final class SyncDevicesSectionModel {\n    init(title: String) {}')
    write('BuilderSupport.swift', builder_support)
    write('Builder.swift', 'import Foundation\n' + section('SunSmart/Main/Space/Model/SyncSceneScheduleTaskBuilder.swift', 'struct SyncSceneScheduleTaskBuilder {', '    func appendSchedule') + '\n}')
    binary = tmp / 'Tests'
    subprocess.run(['swiftc', '-parse-as-library', '-I', str(tmp), '-L', str(tmp), '-lSQLite',
        '-Xlinker', '-rpath', '-Xlinker', str(tmp), *map(str, sources), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
