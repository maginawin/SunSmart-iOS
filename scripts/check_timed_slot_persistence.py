#!/usr/bin/env python3
"""Exercise production Schedule table migration/load/save against real SQLite."""
from pathlib import Path
import subprocess
import tempfile
import sys
sys.dont_write_bytecode = True
from check_scene_configuration import function

root = Path(__file__).resolve().parents[1]
sdk = (root / '.local-sdk/nordic-sig-mesh-sdk').resolve()
database = (root / 'SunSmart/Common/Data/Database.swift').read_text()
start = database.index('extension Schedule {')
end = database.index('\nextension Profile {', start)
with tempfile.TemporaryDirectory(prefix='timed-sqlite-') as directory:
    directory = Path(directory)
    sources = sorted((sdk / 'Sources/SQLite').rglob('*.swift'))
    subprocess.run(['swiftc', '-emit-module', '-emit-library', '-module-name', 'SQLite',
                    *map(str, sources), '-o', str(directory / 'libSQLite.dylib'),
                    '-emit-module-path', str(directory / 'SQLite.swiftmodule')], check=True)
    harness = directory / 'Harness.swift'
    target_source = (root / 'SunSmart/Common/Data/MeshNetwork+SunSmart.swift').read_text()
    target_start = target_source.index('    func targets(node: Node, contextGroup: Group? = nil) -> Bool {')
    target_end = target_source.index('\n    }', target_start) + len('\n    }')
    delete_start = target_source.index('    func needsDelete(from node: Node, contextGroup: Group? = nil) -> Bool {')
    delete_end = target_source.index('\n    }', delete_start) + len('\n    }')
    schedule = (root / 'SunSmart/Main/Timed/Model/Scheduler.swift').read_text()
    message_source = (root / 'SunSmart/Common/Data/Node+MessageHandles.swift').read_text().split('extension Schedule {', 1)[1]
    codec_start = schedule.index('    private enum CodingKeys:', schedule.index('// MARK: - Codable'))
    codec = schedule[codec_start:schedule.index('    /// 复制日程', codec_start)]
    weekdays_start = schedule.index('    static func getWeekDays(')
    weekdays = schedule[weekdays_start:schedule.index('    static func == (lhs: Schedule,', weekdays_start)]
    server = (root / 'SunSmart/Main/Timed/Model/ScheduleServer.swift').read_text()
    toggle_start = server.index('    static func setEnabledState(')
    toggle_end = server.index('\n    }', toggle_start) + len('\n    }')
    group = (root / 'SunSmart/Main/Group/Model/GroupServer.swift').read_text()
    exit_start = group.index('    func getNodeExitMessageHandles(')
    exit_end = group.index('\n    }', exit_start) + len('\n    }')
    scene_start = target_source.index('    func getNeedSyncDataNodes(scene: Scene)')
    scene_end = target_source.index('\n    }', scene_start) + len('\n    }')
    builder = (root / 'SunSmart/Main/Space/Model/SyncSceneScheduleTaskBuilder.swift').read_text()
    builder_start = builder.index('    func appendScene(')
    builder_end = builder.index('\n    func appendSchedule(', builder_start)
    node_sync = (root / 'SunSmart/Common/Data/Node+SyncData.swift').read_text()
    node_scene_start = node_sync.index('        case .scenes(let scene):')
    node_scene_end = node_sync.index('        case .schedules(let schedule):', node_scene_start)
    capacity = (root / 'SunSmart/Common/Data/SceneCapacity.swift').read_text()
    removal = capacity[capacity.index('    func needsSceneRemoval('):capacity.index('\n}')]
    harness.write_text((root / 'Tests/Timed/TimedSlotPersistenceTests.swift').read_text()
                       .replace('    // ACTUAL_CONFIGURATION_TRANSACTION', function(database, '    @discardableResult\n    func configurationTransaction('))
                       .replace('    // ACTUAL_SCENE_REMOVAL', removal)
                       .replace('    // ACTUAL_TARGETS', target_source[target_start:target_end])
                       .replace('    // ACTUAL_SYNC_DIFFERENCE', function(target_source, '    func schedulerSyncDifference('))
                       .replace('    // ACTUAL_MESSAGE_HANDLES', function(message_source, '    func getMessageHandles('))
                       .replace('// ACTUAL_MODEL_OWNER', schedule[schedule.index('extension Schedule {'):schedule.index('class Schedule:')])
                       .replace('    // ACTUAL_NEEDS_DELETE', target_source[delete_start:delete_end])
                       .replace('    // ACTUAL_CODEC', codec)
                       .replace('    // ACTUAL_PROFILE_CODEC', function(schedule, '    struct ScheduleProfile:'))
                       .replace('    // ACTUAL_WEEKDAYS', weekdays)
                       .replace('    // ACTUAL_EXIST_NODES', function(schedule, '    var existNodes:'))
                       .replace('    // ACTUAL_TOGGLE', server[toggle_start:toggle_end])
                       .replace('    // ACTUAL_GROUP_EXIT', group[exit_start:exit_end])
                       .replace('    // ACTUAL_SCENE_READER', target_source[scene_start:scene_end])
                       + '\n' + (root / 'Tests/Timed/TimedSceneRecoveryTests.swift').read_text()
                       .replace('    // ACTUAL_SCENE_TASKS', builder[builder_start:builder_end].replace('node.getNodeSyncSceneDatas(scene: scene).first?.data', 'node.sceneBuilderData(scene: scene)'))
                       .replace('        // ACTUAL_SCENE_DISPLAY', node_sync[node_scene_start:node_scene_end])
                       + '\n' + database[start:end])
    update = function(target_source, '    func updateData(message: MeshMessage,')
    ack = update[update.index('        case is SchedulerActionSet:'):update.index('        case is LightLCLightOnOffSet,')]
    harness.write_text(harness.read_text().replace('// ACTUAL_SCHEDULER_ACK', ack))
    proxy = (sdk / 'Sources/NordicSigMeshSDK/MeshLib/Manager/MeshProxyMessageCommand.swift').read_text()
    harness.write_text(harness.read_text().replace('// ACTUAL_SCHEDULER_SUCCESS', function(proxy, '    var isSuccessful: Bool'))
                       + '\n' + (root / 'Tests/Timed/TimedSchedulerResultTests.swift').read_text())
    controller = (root / 'SunSmart/Main/Timed/Controller/ScheduleAddViewController.swift').read_text()
    create = function(controller, '    @objc private func saveBtnAction()')
    edit = function(controller, '    @objc private func doneBtnAction()')
    # Execute production decision + connection gate + authoritative pre-read.
    # UIKit navigation and asynchronous transport are recording boundaries.
    create = create[create.index('        let needSync ='):create.index('        do {')]
    edit = edit[edit.index('        let affectedNodes ='):edit.index('        var candidates =')]
    harness.write_text(harness.read_text() + '\n' + (root / 'Tests/Timed/TimedDeviceSceneEntryTests.swift').read_text()
                       .replace('// ACTUAL_CREATE_DECISION', create)
                       .replace('// ACTUAL_EDIT_PREREAD', edit))
    space_controller = (root / 'SunSmart/Main/Space/Controller/SpaceViewController.swift').read_text()
    cleanup = (root / 'SunSmart/Common/Data/SpaceSyncCleanupCoordinator.swift').read_text()
    harness.write_text(harness.read_text()
        .replace('    // ACTUAL_MARK_LOCAL_CHANGE', function(space_controller, '    func markLocalChangePendingCloudSync('))
        .replace('    // ACTUAL_MARK_UPLOAD', function(space_controller, '    private func markSpaceUploadNeeded('))
        + '\n' + (root / 'Tests/Timed/TimedCleanupRoundTripTests.swift').read_text()
        + '\nenum SpaceSyncCleanupCoordinator {\n' + function(cleanup, '    static func cleanupSchedules(') + '\n}\n')
    runtime = directory / 'Bindings.swift'
    lifecycle = '--scheduler-lifecycle' in sys.argv
    if lifecycle:
        from timed_scheduler_lifecycle_source import expand
        harness.write_text(expand(harness.read_text(), root, sdk))
    runtime.write_text((root / 'SunSmart/Main/Timed/Model/TimedSchedulerBindings.swift').read_text().replace('import NordicSigMeshSDK', ''))
    runtime.write_text(runtime.read_text() + '\n' + (root / 'SunSmart/Main/Timed/Model/TimedSchedulerTaskCoordinator.swift').read_text().replace('import NordicSigMeshSDK', ''))
    resolver = directory / 'SceneResolver.swift'
    resolver.write_text((root / 'SunSmart/Main/Scene/Model/SceneTargetResolver.swift').read_text().replace('import NordicSigMeshSDK', ''))
    binary = directory / 'Tests'
    subprocess.run(['swiftc', '-parse-as-library', *(['-D', 'DEBUG'] if lifecycle else []), '-I', str(directory), '-L', str(directory),
                    '-lSQLite', '-Xlinker', '-rpath', '-Xlinker', str(directory),
                    str(root / 'SunSmart/Common/Data/HDBConfiguration.swift'),
                    str(root / 'SunSmart/Common/Data/HDBLightingZonePolicy.swift'),
                    str(root / 'SunSmart/Common/Data/SpaceConfigurationIntegrityPolicy.swift'),
                    str(root / 'SunSmart/Main/Group/Model/ProximityLightingTopologyPolicy.swift'),
                    str(root / 'SunSmart/Main/Group/Model/ProximityLightingTopologyReconciler.swift'),
                    str(root / 'SunSmart/Common/Data/SpaceSyncCleanupPolicy.swift'),
                    str(root / 'SunSmart/Main/Timed/Model/TimedSchedulerSlotPolicy.swift'),
                    str(root / 'SunSmart/Main/Timed/Model/TimedSchedulerOwnerPolicy.swift'),
                    str(root / 'SunSmart/Common/Data/SceneDeleteCapability.swift'),
                    str(root / 'SunSmart/Common/Data/AppPerformance.swift'),
                    str(root / 'SunSmart/Main/Scene/Model/SceneConfiguration.swift'), str(resolver),
                    str(sdk / 'Sources/NordicSigMeshSDK/MeshLib/Manager/MeshSchedulerTask.swift'),
                    str(runtime), str(harness), '-o', str(binary)], check=True)
    if lifecycle:
        result = subprocess.run([str(binary), str(directory / 'app.sqlite')], text=True, capture_output=True)
        if result.returncode:
            print(result.stdout)
            print(result.stderr, file=sys.stderr)
            result.check_returncode()
        for expected in ['stage=completed', 'reason=unknownModels', 'reason=nodeSave',
                         'reason=releaseScheduleSave', 'reason=cancelledBeforeApply',
                         'reason=cancelledOwner', 'reason=requiresFullRead']:
            assert expected in result.stdout, f'Missing runtime diagnostic: {expected}'
        print('\n'.join(line for line in result.stdout.splitlines() if line.startswith('PASS:')))
        print('PASS: runtime diagnostics distinguish observation rejection, unknown Models, persistence and cancellation')
    else:
        subprocess.run([str(binary), str(directory / 'app.sqlite')], check=True)
