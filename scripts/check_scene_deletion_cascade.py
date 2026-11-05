#!/usr/bin/env python3
"""Execute the production Scene cascade with deterministic storage/SDK/UI boundaries.

This checks deletion decisions, payloads and receipt lifetime, not radio or UIKit behavior.
"""
from pathlib import Path
import argparse
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
import sys
sys.dont_write_bytecode = True
from check_scene_configuration import function
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--cascade-source", type=Path,
                    default=ROOT / "SunSmart/Main/Scene/Model/SceneDeletionCascade.swift",
                    help="Override only the cascade source to reproduce a prior revision without changing the worktree")
parser.add_argument("--skip-coverage-recovery", action="store_true",
                    help="Run identity regression against an older cascade without the recovery helper")
args = parser.parse_args()
with tempfile.TemporaryDirectory(prefix="scene-cascade-") as directory:
    temporary = Path(directory)
    source = temporary / "SceneDeletionCascade.swift"
    source.write_text(args.cascade_source.read_text()
                      .replace("import NordicSigMeshSDK\n", ""))
    observations = temporary / "Observations.swift"
    observations.write_text("extension Node {\n" + function(
        (ROOT / "SunSmart/Main/Timed/Model/TimedSchedulerBindings.swift").read_text(),
        "    var observedTimedSlots:") + "\n}")
    identities = temporary / "Identities.swift"
    identities.write_text("import Foundation\nimport CryptoKit\n"
        + "enum SchedulerModelSnapshot { enum Invalid: Error { case identity }\n"
        + function((ROOT / "SunSmart/Common/Data/SpaceConfigurationIntegrityPolicy.swift").read_text(),
                   "    static func keyFingerprint(") + "\n}\nextension Node {\n"
        + function((ROOT / "SunSmart/Main/Scene/Model/SceneTargetResolver.swift").read_text(),
                   "    var sceneConfigurationIdentity:") + "\n}\n")
    recovery_sources = []
    recovery_flags = []
    if not args.skip_coverage_recovery:
        recovery = temporary / "CoverageRecovery.swift"
        helper = function((ROOT / "SunSmart/Main/Scene/Model/SceneConfigurationStore.swift").read_text(),
                          "    private func restoreDeletionSchedulerCoverage(")
        recovery.write_text("import Foundation\nextension SceneConfigurationStore {\n"
            + helper.replace("private func restoreDeletionSchedulerCoverage", "static func restoreDeletionSchedulerCoverage", 1)
            + "\n}\n")
        recovery_sources = [str(recovery)]
        recovery_flags = ["-D", "SCENE_CASCADE_COVERAGE_RECOVERY"]
    binary = temporary / "Tests"
    environment = dict(os.environ)
    environment.setdefault("CLANG_MODULE_CACHE_PATH", str(temporary / "clang-cache"))
    environment.setdefault("SWIFT_MODULECACHE_PATH", str(temporary / "swift-cache"))
    subprocess.run([
        "swiftc", "-parse-as-library", *recovery_flags,
        str(ROOT / ".local-sdk/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Manager/MeshSchedulerTask.swift"),
        str(ROOT / "SunSmart/Main/Timed/Model/TimedSchedulerSlotPolicy.swift"),
        str(ROOT / "SunSmart/Main/Scene/Model/SceneConfiguration.swift"),
        str(ROOT / "Tests/Scene/SceneDeletionCascadeTestSupport.swift"),
        str(source), str(observations), str(identities), *recovery_sources,
        str(ROOT / "Tests/Scene/SceneDeletionCascadeTests.swift"),
        "-o", str(binary),
    ], check=True, env=environment)
    subprocess.run([str(binary)], check=True, env=environment)
