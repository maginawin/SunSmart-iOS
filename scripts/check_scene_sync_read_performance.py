#!/usr/bin/env python3
"""Count production Scene resolution/difference work with SDK/DB fixture boundaries.

This is an algorithm and semantics regression, not an iPhone timing benchmark.
"""
from pathlib import Path
import subprocess
import tempfile
import sys

sys.dont_write_bytecode = True
from check_scene_configuration import ROOT, target_sources, function

with tempfile.TemporaryDirectory(prefix='scene-sync-read-') as directory:
    directory = Path(directory)
    sources = target_sources(directory)
    difference = directory / 'Difference.swift'
    difference.write_text('import Foundation\nextension Node {\n' + function(
        (ROOT / 'SunSmart/Common/Data/Node+SyncData.swift').read_text(),
        '    func getNodeSyncSceneDatas(') + '\n}\nextension Schedule {\n'
        'func needsSync(on node: Node, contextGroup: Group?) -> Bool { false }\n}\n')
    sources += [difference,
        ROOT / 'SunSmart/Main/Timed/Model/TimedSchedulerSlotPolicy.swift',
        ROOT / 'SunSmart/Main/Scene/Model/SceneConfiguration.swift',
        ROOT / 'Tests/Scene/SceneSyncReadPerformanceTests.swift']
    binary = directory / 'tests'
    subprocess.run(['swiftc', '-Onone', '-D', 'SUNSMART_PERFORMANCE', '-parse-as-library',
                    *map(str, sources), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
