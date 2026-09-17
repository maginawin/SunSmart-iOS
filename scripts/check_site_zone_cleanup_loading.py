#!/usr/bin/env python3
"""运行生产 Zone 清理分类器，验证 Mesh 加载次数及保守清理行为。"""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'SunSmart/Main/Site/TriggerZone/SiteTriggerZoneTopologyReader.swift').read_text()
start = source.index('    static func cleanupClassifier(site:')
end = source.index('\n    static func mergedLocalTarget(', start)
with tempfile.TemporaryDirectory(prefix='site-zone-cleanup-loading-') as directory:
    output = Path(directory)
    production = output / 'Production.swift'
    production.write_text('import Foundation\nenum SiteTriggerZoneTopologyReader {\n' + source[start:end] + '\n}\n')
    binary = output / 'tests'
    subprocess.run(['swiftc', '-parse-as-library', str(production),
                    str(root / 'SunSmart/Main/Site/TriggerZone/SiteTriggerZoneData.swift'),
                    str(root / 'Tests/Site/SiteZoneCleanupLoadingTests.swift'), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
