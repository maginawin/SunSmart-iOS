#!/usr/bin/env python3
"""运行完整快照清理策略，不连接云端或设备。"""
from pathlib import Path
import argparse
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--snapshot", type=Path, help="额外验证外部 Space JSON（支持云端 data 包装），不复制数据")
args = parser.parse_args()
if args.snapshot is not None and not args.snapshot.is_file():
    parser.error("--snapshot 必须是现有的 JSON 文件")

ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="space-sync-cleanup-") as directory:
    binary = str(Path(directory) / "tests")
    files = ["SunSmart/Common/Data/SpaceConfigurationIntegrityPolicy.swift",
             "SunSmart/Main/Group/Model/ProximityLightingTopologyPolicy.swift",
             "SunSmart/Main/Group/Model/ProximityLightingTopologyReconciler.swift",
             "SunSmart/Common/Data/SpaceSyncCleanupPolicy.swift",
             "Tests/Group/SpaceSyncCleanupPolicyTests.swift"]
    subprocess.run(["swiftc", "-parse-as-library", *[str(ROOT / file) for file in files], "-o", binary], check=True)
    command = [binary]
    if args.snapshot is not None:
        command.extend(["--snapshot", str(args.snapshot.resolve())])
    subprocess.run(command, check=True)
