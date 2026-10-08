#!/usr/bin/env python3
"""Exercise production Schedule table migration/load/save against real SQLite."""
from pathlib import Path
import subprocess
import tempfile

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
    harness.write_text((root / 'Tests/Timed/TimedSlotPersistenceTests.swift').read_text()
                       .replace('    // ACTUAL_TARGETS', target_source[target_start:target_end])
                       .replace('    // ACTUAL_TOGGLE', server[toggle_start:toggle_end])
                       .replace('    // ACTUAL_GROUP_EXIT', group[exit_start:exit_end])
                       .replace('    // ACTUAL_SCENE_READER', target_source[scene_start:scene_end])
                       + '\n' + (root / 'Tests/Timed/TimedSceneRecoveryTests.swift').read_text()
                       .replace('    // ACTUAL_SCENE_TASKS', builder[builder_start:builder_end])
                       .replace('        // ACTUAL_SCENE_DISPLAY', node_sync[node_scene_start:node_scene_end])
                       + '\n' + database[start:end])
    runtime = directory / 'Bindings.swift'
    runtime.write_text((root / 'SunSmart/Main/Timed/Model/TimedSchedulerBindings.swift').read_text().replace('import NordicSigMeshSDK', ''))
    binary = directory / 'Tests'
    subprocess.run(['swiftc', '-parse-as-library', '-I', str(directory), '-L', str(directory),
                    '-lSQLite', '-Xlinker', '-rpath', '-Xlinker', str(directory),
                    str(root / 'SunSmart/Main/Timed/Model/TimedSchedulerSlotPolicy.swift'),
                    str(runtime), str(harness), '-o', str(binary)], check=True)
    subprocess.run([str(binary), str(directory / 'app.sqlite')], check=True)
