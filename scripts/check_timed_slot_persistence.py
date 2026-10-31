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
                       .replace('    // ACTUAL_NEEDS_DELETE', target_source[delete_start:delete_end])
                       .replace('    // ACTUAL_CODEC', codec)
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
    runtime = directory / 'Bindings.swift'
    runtime.write_text((root / 'SunSmart/Main/Timed/Model/TimedSchedulerBindings.swift').read_text().replace('import NordicSigMeshSDK', ''))
    resolver = directory / 'SceneResolver.swift'
    resolver.write_text((root / 'SunSmart/Main/Scene/Model/SceneTargetResolver.swift').read_text().replace('import NordicSigMeshSDK', ''))
    binary = directory / 'Tests'
    subprocess.run(['swiftc', '-parse-as-library', '-I', str(directory), '-L', str(directory),
                    '-lSQLite', '-Xlinker', '-rpath', '-Xlinker', str(directory),
                    str(root / 'SunSmart/Main/Timed/Model/TimedSchedulerSlotPolicy.swift'),
                    str(root / 'SunSmart/Main/Timed/Model/TimedSchedulerOwnerPolicy.swift'),
                    str(root / 'SunSmart/Common/Data/SceneDeleteCapability.swift'),
                    str(root / 'SunSmart/Main/Scene/Model/SceneConfiguration.swift'), str(resolver),
                    str(runtime), str(harness), '-o', str(binary)], check=True)
    subprocess.run([str(binary), str(directory / 'app.sqlite')], check=True)
