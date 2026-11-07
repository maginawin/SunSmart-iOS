#!/usr/bin/env python3
"""Run production coordinator and ScheduleServer with controlled transport completions."""
import sys
sys.dont_write_bytecode = True
from pathlib import Path
import subprocess
import tempfile
from check_scene_configuration import function
root = Path(__file__).resolve().parents[1]
sdk = (root / '.local-sdk/nordic-sig-mesh-sdk').resolve()
server = (root / 'SunSmart/Main/Timed/Model/ScheduleServer.swift').read_text()
methods = function(server, '    static func deleteSchedule(') + '\n' + function(server, '    static func setEnabledState(') + '\n' + server[server.index('    static func saveSchedule('):server.rindex('\n}')]
bindings = (root / 'SunSmart/Main/Timed/Model/TimedSchedulerBindings.swift').read_text()
fixture = (root / 'Tests/Timed/TimedTaskReplacementTests.swift').read_text().replace('// PRODUCTION_SERVER', methods)
fixture = fixture.replace('// PRODUCTION_RELEASE', function(bindings, '    func releaseClearedBinding('))
fixture = fixture.replace('// PRODUCTION_RESULTS', function(bindings, '    func applySchedulerResults(') + '\n' + function(bindings, '    private func schedulerResultFailure('))
fixture = fixture.replace('// PRODUCTION_DELETION', function(bindings, '    func deletionIsSynchronized('))
proxy = (sdk / 'Sources/NordicSigMeshSDK/MeshLib/Manager/MeshProxyMessageCommand.swift').read_text()
fixture = fixture.replace('// PRODUCTION_SUCCESS', function(proxy, '    var isSuccessful: Bool'))
coordinator = (root / 'SunSmart/Main/Timed/Model/TimedSchedulerTaskCoordinator.swift').read_text().replace('import NordicSigMeshSDK', '')
identity = (root / 'SunSmart/Main/Timed/Model/TimedSchedulerSlotPolicy.swift').read_text().split('/// Pure reservation planner.')[0]
with tempfile.TemporaryDirectory(prefix='timed-task-') as directory:
    directory = Path(directory)
    source = directory / 'Tests.swift'
    source.write_text(identity + coordinator + fixture)
    binary = directory / 'Tests'
    subprocess.run(['swiftc', '-parse-as-library',
        str(sdk / 'Sources/NordicSigMeshSDK/MeshLib/Manager/MeshSchedulerTask.swift'),
        str(root / 'SunSmart/Common/Data/TimedScheduleTimeSyncPolicy.swift'), str(source), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
