#!/usr/bin/env python3
"""Run Scene production logic with SQLite/BLE/UIKit fixture boundaries.
Reference cleanup uses an empty-reference boundary here; its production behavior
is covered separately by check_scene_deletion_cascade.py.
"""
from pathlib import Path
import argparse
import subprocess
import tempfile
import sys
sys.dont_write_bytecode = True
from scene_group_codec_source import scene_group_codec_source

ROOT = Path(__file__).resolve().parents[1]

def section(path, start, end):
    text = (ROOT / path).read_text()
    begin = text.index(start)
    return text[begin:text.index(end, begin)]

def function(text, marker):
    start = text.index(marker)
    opening = text.index('{', start)
    depth, end = 1, opening + 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[start:end]

def target_sources(tmp):
    mesh = (ROOT / 'SunSmart/Common/Data/MeshNetwork+SunSmart.swift').read_text()
    timed = (ROOT / 'SunSmart/Main/Timed/Model/TimedSchedulerBindings.swift').read_text()
    capacity = (ROOT / 'SunSmart/Common/Data/SceneCapacity.swift').read_text()
    harness = (ROOT / 'Tests/Scene/SceneTargetTestSupport.swift').read_text()
    harness = harness.replace(function(harness, '    func deviceTarget(for node:'), function(mesh, '    func deviceTarget(for node:'))
    harness += '\nextension SceneExecuteData {\n' + function(mesh, '    func isSynced(with groupSceneData:') + '\n}\n'
    harness = harness.replace('// ACTUAL_SCENE_INFO', section('SunSmart/Common/Data/MeshNetwork+SunSmart.swift', 'class SceneInfo {', '\nclass GroupInfo {'))
    harness += '\nextension Scene {\n' + function(mesh, '    static func sortedForDisplay(') + '\n}\n'
    harness = harness.replace('// ACTUAL_ACTIVE_SCENE_GROUPS', function(timed, '    var activeSceneGroups:'))
    harness = harness.replace('// ACTUAL_SCHEDULE_TARGETS', function(mesh, '    func targets(node:'))
    harness = harness.replace('// ACTUAL_EXIST_NODES', function((ROOT / 'SunSmart/Main/Timed/Model/Scheduler.swift').read_text(), '    var existNodes:'))
    markers = ['    struct Failure:', '    static func intendedScenes(', '    static func validateTopology(',
               '    static func label(', '    static func unknownNodes(', '    static func nodesRequiringRead(',
               '    static func validateStore(', '    static func validSceneAllocation(', '    static func validateConfigurations(']
    harness = harness.replace('// ACTUAL_SCENE_CAPACITY', 'enum SceneCapacity {\n' + '\n'.join(function(capacity, m) for m in markers) + '\n}')
    harness = harness.replace('// ACTUAL_TIMED_BINDINGS', 'enum TimedSchedulerBindings {\n' + '\n'.join(function(timed, m) for m in [
        '    enum Failure:', '    struct Plan {', '    static func prepare(', '    static func prepareTopology(',
        '    static func topologyTargets(', '    static func nodesRequiringTopologyRead(']) + '\n}')
    support = tmp / 'Support.swift'; support.write_text(harness)
    resolver = tmp / 'Resolver.swift'
    resolver.write_text((ROOT / 'SunSmart/Main/Scene/Model/SceneTargetResolver.swift').read_text().replace('import NordicSigMeshSDK', ''))
    return [support, resolver, ROOT / 'SunSmart/Common/Data/SceneCapacityPolicy.swift']

def scene_authority_support(harness):
    space = (ROOT / 'SunSmart/Common/Data/SpaceData.swift').read_text()
    imports = (ROOT / 'SunSmart/Common/Data/ImportData.swift').read_text()
    return harness.replace('// ACTUAL_SCENE_AUTHORITY', '\n'.join([
        function(space, '    var canEditing:'), function(space, '    var sceneOperates:'),
        function(imports, '    @discardableResult\n    func applyRemoteSpaceAuthorityRestrictions(')]))

def run(suite):
    with tempfile.TemporaryDirectory(prefix=f'scene-{suite}-') as tmp:
        tmp = Path(tmp)
        flags = []
        sources = []
        model = ROOT / 'SunSmart/Main/Scene/Model/SceneConfiguration.swift'
        if model.exists():
            sources += [ROOT / 'SunSmart/Main/Timed/Model/TimedSchedulerSlotPolicy.swift', model]
        if suite == 'save':
            sources += [ROOT / 'SunSmart/Main/Scene/Model/SceneDraftSelection.swift', ROOT / 'SunSmart/Main/Device/Filter/Model/DeviceNameFilterSession.swift']
        if suite in ['storage', 'save', 'roundtrip-storage']:
            sdk = (ROOT / '.local-sdk/nordic-sig-mesh-sdk').resolve()
            subprocess.run(['swiftc', '-emit-module', '-emit-library', '-module-name', 'SQLite',
                            *map(str, sorted((sdk / 'Sources/SQLite').rglob('*.swift'))),
                            '-o', str(tmp / 'libSQLite.dylib'), '-emit-module-path', str(tmp / 'SQLite.swiftmodule')], check=True)
            flags += ['-I', str(tmp), '-L', str(tmp), '-lSQLite', '-Xlinker', '-rpath', '-Xlinker', str(tmp)]
            if suite in ['save', 'roundtrip-storage']:
                flags += ['-D', 'SCENE_CASCADE_STORE_BOUNDARY']
                sources += [ROOT / 'Tests/Scene/SceneDeletionCascadeBoundarySupport.swift']
                sources += target_sources(tmp) + [ROOT / ('Tests/Scene/SceneSaveFlowTests.swift' if suite == 'save' else 'Tests/Scene/ScenePayloadPersistenceTests.swift')]
                harness = (ROOT / 'Tests/Scene/SceneSaveTestSupport.swift').read_text()
                harness = scene_authority_support(harness)
                harness = harness.replace('// ACTUAL_TRANSACTION', function((ROOT / 'SunSmart/Common/Data/Database.swift').read_text(), '    @discardableResult\n    func configurationTransaction('))
                harness = harness.replace('// ACTUAL_TIMED_COMMIT', section('SunSmart/Main/Timed/Model/TimedSchedulerBindings.swift', '    static func commit(_ plan:', '    static func reserveForDeletion('))
                harness = harness.replace('// ACTUAL_UPDATE_GROUP', function((ROOT / 'SunSmart/Common/Data/MeshNetwork+SunSmart.swift').read_text(), '    func updateGroupSyncState()'))
                harness += section('SunSmart/Common/Data/Database.swift', 'extension SceneInfo {', '\nextension Schedule {')
                store = tmp / 'Store.swift'
                store.write_text((ROOT / 'SunSmart/Main/Scene/Model/SceneConfigurationStore.swift').read_text().replace('import NordicSigMeshSDK', ''))
                sources += [store, sdk / 'Sources/NordicSigMeshSDK/MeshLib/Scene/SceneRegisterPolicy.swift']
                path = tmp / 'SaveSupport.swift'; path.write_text(harness); sources += [path]
            else:
                harness = (ROOT / 'Tests/Scene/SceneConfigurationPersistenceTests.swift').read_text()
                harness = harness.replace('// ACTUAL_SCENE_INFO', section('SunSmart/Common/Data/MeshNetwork+SunSmart.swift', 'class SceneInfo {', '\nclass GroupInfo {'))
                harness = harness.replace('// ACTUAL_SCENE_DATABASE', section('SunSmart/Common/Data/Database.swift', 'extension SceneInfo {', '\nextension Schedule {'))
                path = tmp / 'Harness.swift'
                path.write_text(harness)
                sources += [path]
        elif suite == 'selection':
            selection_tests = tmp / 'SelectionTests.swift'
            selection_source = (ROOT / 'SunSmart/Main/Scene/Controller/SceneSettingsViewController.swift').read_text()
            select_method = '\n'.join(function(selection_source, marker).replace('@objc ', '').replace('private func', 'func') for marker in [
                '    @objc private func selectDevices()', '    private func showDeviceSelection(', '    @objc private func closeAction()'])
            header_method = function((ROOT / 'SunSmart/Main/Scene/View/SceneDevicesSelectionView.swift').read_text(), '    private func updateEditorHeader()').replace('private func', 'func')
            selection_tests.write_text((ROOT / 'Tests/Scene/SceneDraftSelectionTests.swift').read_text()
                                      .replace('// PRODUCTION_SELECT_DEVICES', select_method)
                                      .replace('// PRODUCTION_EDITOR_HEADER', header_method))
            sources += [ROOT / 'SunSmart/Main/Device/Filter/Model/DeviceNameFilterSession.swift', ROOT / 'SunSmart/Main/Scene/Model/SceneDraftSelection.swift', selection_tests]
            editing = (ROOT / 'Tests/Scene/SceneDeviceParameterEditingTests.swift').read_text()
            editing = editing.replace('// PRODUCTION_EDIT_DEVICES', '\n'.join(function(selection_source, marker).replace('private func', 'func') for marker in [
                '    private func editDevices(', '    private func accepts(']))
            sdk_node = (ROOT / '.local-sdk/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Node/Node+Propertys.swift').read_text()
            editing = editing.replace('// SDK_CONTROL_PAGE', function(sdk_node, 'public enum NodeChangeControlPage:'))
            editing = editing.replace('// SDK_NODE_PROPERTIES', '\n'.join(function(sdk_node, marker) for marker in [
                '    var isSingleWhiteDefaultCctProduct:', '    var defaultChangeControlPage:',
                '    var effectiveChangeControlPage:', '    var effectiveSupportCct:', '    var singleDeviceDisplaySupportCct:',
                '    func clampEffectiveCct(', '    static func getLightness(', '    static func getLightness100(']))
            resolver = (ROOT / 'SunSmart/Main/Scene/Model/SceneTargetResolver.swift').read_text()
            editing = editing.replace('// PRODUCTION_RESOLVE', function(resolver, '    func resolved(for node:'))
            picker = (ROOT / 'SunSmart/Main/Scene/View/SceneExecuteDataPickerView.swift').read_text()
            editing = editing.replace('// PRODUCTION_PICKER', '\n'.join(function(picker, marker).replace('private var', 'var').replace('@objc private func', 'func') for marker in [
                '    private var selectedCct:', '    private var selectedIsOn:', '    @objc private func shadeViewAction()']))
            editing_tests = tmp / 'ParameterEditingTests.swift'; editing_tests.write_text(editing)
            sources += [editing_tests]
        elif suite == 'model':
            sources += [ROOT / 'Tests/Scene/SceneConfigurationTests.swift']
        elif suite in ['sync', 'integration']:
            flags += ['-D', 'SCENE_CASCADE_TASK_BOUNDARY']
            sources += [ROOT / 'Tests/Scene/SceneDeletionCascadeBoundarySupport.swift']
            sources += target_sources(tmp) + [ROOT / 'Tests/Scene/SceneCommandTestSupport.swift', ROOT / ('Tests/Scene/SceneCommandTests.swift' if suite == 'sync' else 'Tests/Scene/SceneIntegrationTests.swift')]
            if suite == 'integration':
                picker = tmp / 'Pickers.swift'
                text = (ROOT / 'Tests/Scene/ScenePickerIntegrationSupport.swift').read_text()
                text = text.replace('// PRODUCTION_VISIBLE_SCENES', function((ROOT / 'SunSmart/Main/Scene/Controller/ScenesViewController.swift').read_text(), '    private var visibleScenes:').replace('private var', 'var'))
                text = text.replace('// PRODUCTION_SCHEDULE_INIT', function((ROOT / 'SunSmart/Main/Timed/View/ScheduleScenesView.swift').read_text(), '    init(scenes:'))
                text = text.replace('// PRODUCTION_SWITCH_PAGE_INIT', function((ROOT / 'SunSmart/Main/Group/Switch/Controller/SwitchSelectScenePageController.swift').read_text(), '    init(scenes:'))
                text = text.replace('// PRODUCTION_SCENE_SNAPSHOT', section('SunSmart/Common/Data/SpacePageSyncRead.swift', 'struct SceneGroupSyncSnapshot {', '\nstruct SceneGroupAppearance'))
                text = text.replace('// PRODUCTION_SCHEDULE_PENDING', function((ROOT / 'SunSmart/Main/Timed/View/ScheduleScenesView.swift').read_text(), '    private func sceneNeedsSync(').replace('private func', 'func'))
                text = text.replace('// PRODUCTION_SCHEDULE_SELECT', function((ROOT / 'SunSmart/Main/Timed/View/ScheduleScenesView.swift').read_text(), '    func collectionView(_ collectionView: UICollectionView, didSelectItemAt'))
                text = text.replace('// PRODUCTION_SWITCH_SELECT', function((ROOT / 'SunSmart/Main/Group/Switch/Controller/SwitchSelectSceneViewController.swift').read_text(), '    func tableView(_ tableView: UITableView, didSelectRowAt'))
                text = text.replace('// PRODUCTION_LIST_RECALL', function((ROOT / 'SunSmart/Main/Scene/Controller/ScenesViewController.swift').read_text(), '    func collectionView(_ collectionView: UICollectionView, didSelectItemAt'))
                text = text.replace('// PRODUCTION_IDENTITY_LOOKUP', function((ROOT / 'SunSmart/Main/Scene/View/SceneDevicesSelectionView.swift').read_text(), '    func node(for identity:'))
                text = text.replace('// PRODUCTION_IDENTIFY', function((ROOT / 'SunSmart/Main/Scene/Controller/SceneSettingsViewController.swift').read_text(), '    private func identify(').replace('private func', 'func', 1))
                picker.write_text(text); sources += [picker]
            command = tmp / 'Commands.swift'
            command.write_text('extension Scene {\n' + '\n'.join(function((ROOT / 'SunSmart/Common/Data/Node+MessageHandles.swift').read_text(), m) for m in ['    func getSyncMessageHandles(node:', '    func getDeleteMessageHandles(node:']) + '\n}')
            command.write_text(command.read_text() + '\nextension Scene {\n' + function((ROOT / 'SunSmart/Common/Data/MeshNetwork+SunSmart.swift').read_text().split('extension Scene {', 1)[1], '    var needSync: Bool {') + '\n}')
            node_source = (ROOT / 'SunSmart/Common/Data/Node+SyncData.swift').read_text()
            command.write_text(command.read_text() + '\nextension Node {\n' + '\n'.join(function(node_source, m) for m in ['    func getNodeSyncSceneDatas(', '    func getNodeNeedDeleteSceneDatas(', '    func getStandardNeedSync()']) + '\n}')
            sources += [command]
            builder = tmp / 'Builder.swift'
            builder.write_text((ROOT / 'SunSmart/Main/Scene/Model/SceneCommandBuilder.swift').read_text().split('private var sceneMessageContextKey')[0].replace('import NordicSigMeshSDK', '').replace('import ObjectiveC', ''))
            task_builder = tmp / 'TaskBuilder.swift'
            task_builder.write_text('import Foundation\n' + section('SunSmart/Main/Space/Model/SyncSceneScheduleTaskBuilder.swift', 'struct SyncSceneScheduleTaskBuilder {', '    func appendSchedule') + '\n}')
            sources += [builder, task_builder, ROOT / 'Tests/Scene/SceneSyncTaskBuilderSupport.swift']
        elif suite == 'roundtrip-group':
            codecs = tmp / 'SDKCodecs.swift'
            codecs.write_text(scene_group_codec_source(ROOT))
            sources += [codecs, ROOT / 'Tests/Scene/SceneGroupPayloadTests.swift']
        elif suite == 'roundtrip':
            sources += [ROOT / 'SunSmart/Common/Data/HDBConfiguration.swift', ROOT / 'SunSmart/Common/Data/HDBLightingZonePolicy.swift', ROOT / 'SunSmart/Common/Data/SpaceConfigurationIntegrityPolicy.swift', ROOT / 'Tests/Scene/SceneConfigurationRoundTripTests.swift']
        elif suite == 'targets':
            sources += target_sources(tmp) + [ROOT / 'Tests/Scene/SceneTargetResolverTests.swift']
        else:
            raise SystemExit(f'UNIMPLEMENTED suite: {suite} (no tests run)')
        binary = tmp / 'Tests'
        subprocess.run(['swiftc', '-parse-as-library', *flags, *map(str, sources), '-o', str(binary)], check=True)
        subprocess.run([str(binary), str(tmp / 'app.sqlite')], check=True)
        if suite == 'selection':
            subprocess.run(['swiftc', '-parse-as-library', str(ROOT / 'SunSmart/Main/Device/Filter/Model/DeviceNameFilterSession.swift'), str(ROOT / 'Tests/Device/DeviceNameFilterSessionTests.swift'), '-o', str(binary)], check=True)
            subprocess.run([str(binary)], check=True)
        if suite == 'save':
            sources = [p for p in sources if p.name != 'SceneSaveFlowTests.swift']
            command = tmp / 'CommandBuilder.swift'
            command.write_text((ROOT / 'SunSmart/Main/Scene/Model/SceneCommandBuilder.swift').read_text().split('private var sceneMessageContextKey')[0].replace('import NordicSigMeshSDK', '').replace('import ObjectiveC', ''))
            command_support = tmp / 'CommandSupport.swift'
            command_support.write_text((ROOT / 'Tests/Scene/SceneCommandTestSupport.swift').read_text().split('extension SceneInfo')[0])
            coordinator = tmp / 'Coordinator.swift'
            coordinator.write_text((ROOT / 'SunSmart/Main/Scene/Model/SceneSaveCoordinator.swift').read_text().replace('import NordicSigMeshSDK', ''))
            # Exercise the actual handle wrapper and SceneDelete branch, with only
            # unrelated messages/SDK transport at the fixture boundary.
            mesh = (ROOT / 'SunSmart/Common/Data/MeshNetwork+SunSmart.swift').read_text()
            bindings = (ROOT / 'SunSmart/Main/Timed/Model/TimedSchedulerBindings.swift').read_text()
            node_update = function(mesh, '    func updateData(message: MeshMessage,')
            deletion = node_update[node_update.index('        case is SceneDelete:'):node_update.index('        case is SchedulerActionSet:')]
            lifecycle = tmp / 'SceneDeletionLifecycle.swift'
            lifecycle_source = 'import Foundation\nextension Node {\n' + function(bindings, '    @discardableResult\n    func applyMessageHandle(')
            lifecycle_source += '\n' + function(mesh[mesh.index('    func delete(sceneId: SceneNumber)', mesh.index('    func delete(sceneId: SceneNumber)') + 1):], '    func delete(sceneId: SceneNumber)')
            lifecycle_source += '\n' + function((ROOT / 'SunSmart/Common/Data/SceneCapacity.swift').read_text(), '    func needsSceneRemoval(')
            lifecycle_source += '\n' + function((ROOT / 'SunSmart/Common/Data/Node+SyncData.swift').read_text(), '    func getNodeNeedDeleteSceneDatas(')
            lifecycle_source += '\nvar syncReadGroup: Group? { group }\nvar scenes: [Scene] { MeshNetworkManager.instance.scenes.filter { scene in sceneExecuteDatas.contains { $0.sceneNumber == scene.number } } }\n'
            lifecycle_source += '\nfunc updateData(message: Any, isSuccess: Bool, model: Model?) { guard isSuccess else { return }; switch message {\n' + deletion + '\ndefault: break\n} }\n'
            if '    func completeGroupSceneRemoval(' in mesh:
                lifecycle_source += function(mesh, '    @discardableResult\n    func completeGroupSceneRemoval(')
            lifecycle_source += '\n}\nextension Scene {\n'
            lifecycle_source += function((ROOT / 'SunSmart/Common/Data/Node+MessageHandles.swift').read_text(), '    func getDeleteMessageHandles(node:') + '\n}\n'
            lifecycle_source += 'struct SchedulerContextBoundary { func matches(node: Node) -> Bool { true } }\nextension MeshMessageHandle { var timedSchedulerContext: SchedulerContextBoundary? { nil } }\n'
            lifecycle.write_text(lifecycle_source)
            sources += [lifecycle, ROOT / 'SunSmart/Common/Data/SceneDeleteCapability.swift', command, command_support, coordinator, ROOT / 'Tests/Scene/SceneSaveCoordinatorTestSupport.swift', ROOT / 'Tests/Scene/SceneSaveCoordinatorTests.swift']
            subprocess.run(['swiftc', '-parse-as-library', *flags, *map(str, sources), '-o', str(binary)], check=True)
            subprocess.run([str(binary), str(tmp / 'coordinator.sqlite')], check=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--suite', required=True, choices=['model', 'storage', 'targets', 'sync', 'save', 'roundtrip', 'selection', 'integration', 'all'])
    suite = parser.parse_args().suite
    if suite == 'all':
        for implemented in ['model', 'storage', 'targets', 'sync', 'save', 'roundtrip', 'roundtrip-storage', 'roundtrip-group', 'selection', 'integration']:
            run(implemented)
        raise SystemExit(0)
    run(suite)
    if suite == 'roundtrip':
        run('roundtrip-storage')
        run('roundtrip-group')
