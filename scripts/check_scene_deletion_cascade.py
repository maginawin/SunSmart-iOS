#!/usr/bin/env python3
"""Execute the production Scene cascade with deterministic storage/SDK/UI boundaries.

This checks deletion decisions, payloads and receipt lifetime, not radio or UIKit behavior.
"""
from pathlib import Path
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
import sys
sys.dont_write_bytecode = True
from check_scene_configuration import function
with tempfile.TemporaryDirectory(prefix="scene-cascade-") as directory:
    temporary = Path(directory)
    source = temporary / "SceneDeletionCascade.swift"
    source.write_text((ROOT / "SunSmart/Main/Scene/Model/SceneDeletionCascade.swift").read_text()
                      .replace("import NordicSigMeshSDK\n", ""))
    observations = temporary / "Observations.swift"
    observations.write_text("extension Node {\n" + function(
        (ROOT / "SunSmart/Main/Timed/Model/TimedSchedulerBindings.swift").read_text(),
        "    var observedTimedSlots:") + "\n}")
    binary = temporary / "Tests"
    environment = dict(os.environ)
    environment.setdefault("CLANG_MODULE_CACHE_PATH", str(temporary / "clang-cache"))
    environment.setdefault("SWIFT_MODULECACHE_PATH", str(temporary / "swift-cache"))
    subprocess.run([
        "swiftc", "-parse-as-library",
        str(ROOT / "SunSmart/Main/Timed/Model/TimedSchedulerSlotPolicy.swift"),
        str(ROOT / "SunSmart/Main/Scene/Model/SceneConfiguration.swift"),
        str(ROOT / "Tests/Scene/SceneDeletionCascadeTestSupport.swift"),
        str(source), str(observations), str(ROOT / "Tests/Scene/SceneDeletionCascadeTests.swift"),
        "-o", str(binary),
    ], check=True, env=environment)
    subprocess.run([str(binary)], check=True, env=environment)
