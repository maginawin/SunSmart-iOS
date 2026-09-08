#!/usr/bin/env python3
"""生产构建结果安装和轮次等待兼容测试，使用可控 UI 队列，不连接设备。"""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def block(source, marker):
    start = source.index(marker)
    opening = source.index('{', start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]


def main():
    controller = (ROOT / 'SunSmart/Main/Space/Controller/SyncDevicesViewController.swift').read_text()
    installation = block(controller, '    private func installTaskPlan(').replace('private func', 'func', 1)
    production = 'import Foundation\n' + (ROOT / 'Tests/Sync/SyncRunLifecycleFixtures.swift').read_text()
    production += '\nfinal class InstallationHarness {\n' + (ROOT / 'Tests/Sync/SyncPlanInstallationHarness.txt').read_text() + installation + '\n}\n'
    with tempfile.TemporaryDirectory(prefix='sync-run-lifecycle-') as directory:
        source = Path(directory) / 'Production.swift'
        binary = Path(directory) / 'Tests'
        source.write_text(production)
        subprocess.run(['swiftc', '-parse-as-library',
                        str(ROOT / 'SunSmart/Main/Space/Model/SyncRunLifecycle.swift'), str(source),
                        str(ROOT / 'Tests/Sync/SyncRunLifecycleTests.swift'), '-o', str(binary)], check=True)
        subprocess.run([str(binary)], check=True)


if __name__ == '__main__':
    main()
