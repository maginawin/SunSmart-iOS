#!/usr/bin/env python3
"""Run the original topology assertions with the shared Scene production fixture."""
from pathlib import Path
import subprocess
import tempfile
import sys
sys.dont_write_bytecode = True
from check_scene_configuration import ROOT, target_sources

with tempfile.TemporaryDirectory(prefix='scene-topology-') as directory:
    directory = Path(directory)
    binary = directory / 'Tests'
    sources = target_sources(directory) + [
        ROOT / 'SunSmart/Main/Timed/Model/TimedSchedulerSlotPolicy.swift',
        ROOT / 'SunSmart/Main/Scene/Model/SceneConfiguration.swift',
        ROOT / 'Tests/Scene/SceneTopologyTests.swift']
    subprocess.run(['swiftc', '-parse-as-library', *map(str, sources), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
