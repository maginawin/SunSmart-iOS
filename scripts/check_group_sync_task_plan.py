#!/usr/bin/env python3
"""Execute the production Group planning branch; device diff generation and storage are separate boundaries."""
from pathlib import Path
import subprocess, tempfile
root = Path(__file__).resolve().parents[1]
source = (root/'SunSmart/Main/Space/Model/SyncTaskPlanBuilder.swift').read_text()
branch = source.split('        case .group(let group, let inNodes, let outNodes):')[1].split('        case .emergencyFire(')[0]
fixture = (root/'Tests/Sync/GroupSyncTaskPlanTests.swift').read_text().replace('// PRODUCTION_GROUP_PLAN', branch)
with tempfile.TemporaryDirectory(prefix='group-sync-plan-') as directory:
    p = Path(directory); swift = p/'Tests.swift'; swift.write_text(fixture)
    subprocess.run(['swiftc','-module-cache-path',str(p/'module-cache'),str(swift),'-o',str(p/'tests')],check=True)
    subprocess.run([str(p/'tests')],check=True)
