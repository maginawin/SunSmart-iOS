#!/usr/bin/env python3
"""Run production SceneServer with deterministic transport and storage boundaries.
Storage failures are injected; this is not a SQLite or physical-device test.
"""
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='scene-deletion-') as folder:
    folder = Path(folder)
    source = folder / 'SceneServer.swift'
    source.write_text((root / 'SunSmart/Main/Scene/Model/SceneServer.swift').read_text().replace('import NordicSigMeshSDK', ''))
    binary = folder / 'Tests'
    subprocess.run(['swiftc', '-parse-as-library', str(source), str(root / 'Tests/Scene/SceneDeletionFlowTests.swift'), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
