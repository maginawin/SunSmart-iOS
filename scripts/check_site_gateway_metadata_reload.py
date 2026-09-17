#!/usr/bin/env python3
"""Execute production metadata import, three reload paths and Site projections.

SQLite/SDK/UI and deletion receipts are explicit test boundaries. Database reads
return fresh objects without gateway metadata, matching SpaceData.load. Pass
--revision HEAD to reproduce the regression against the pre-fix production code.
"""
from pathlib import Path
import argparse
import os
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--revision')
args = parser.parse_args()


def read(path):
    if args.revision:
        return subprocess.check_output(
            ['git', 'show', f'{args.revision}:{path}'], cwd=root, text=True)
    return (root / path).read_text()


def section(source, start, end):
    offset = source.index(start)
    return source[offset:source.index(end, offset)]


site = read('SunSmart/Common/Data/SiteData.swift')
imports = read('SunSmart/Common/Data/ImportData.swift')
controller = read('SunSmart/Main/Site/Controller/SiteViewController.swift')
production = 'import Foundation\nextension SiteData {\n'
helper = '    func reloadSpacesPreservingGatewayMetadata('
if helper in site:
    production += section(site, helper, '    func copy()')
production += '    func importReload(gateways: [[String: Any]]? = nil) async {\n'
if 'let gatewayLastOnlineSnapshot =' in imports:
    production += '        let gatewayDicts = gateways\n        let importedSpaces = spaces\n        let siteJsonData: [String: Any] = [:]\n'
    production += section(imports, '        let gatewayLastOnlineSnapshot =',
                          '        let gatewaySnapshot =')
    production += section(imports, '                for space in importedSpaces where',
                          '                let changed = SiteDeviceOwnershipReconciler.reconcile(siteId: self.id)')
production += section(imports,
    '                let changed = SiteDeviceOwnershipReconciler.reconcile(siteId: self.id)',
    '                for space in self.spaces where changed.contains(space.id)')
production += '    }\n}\nextension SpaceData {\n'
production += section(imports, '    func applyRemoteSpaceMetadata(',
                      '    /// 更新空间内基本数据+设备、组、场景、日程')
production += '}\nextension SiteController {\n    func reappear() {\n'
production += section(controller,
    '        let ownershipChanges = SiteDeviceOwnershipReconciler.reconcile(siteId: site.id)',
    '        if NetworkRequest.shared.networkable {')
production += '    }\n    func refreshList() {\n'
production += '        let notification = Notification(name: .init("refresh"), object: true)\n'
production += section(controller, '            if notification.object as? Bool ?? false {',
                      '            self.setupData()')
production += '    }\n'
production += section(controller, '    private func loadGatewaysData()',
                      '    private func shouldShowGatewayStatus(')
production += '    func gateways() -> [Gateway] { loadGatewaysData() }\n'
production += '    func overview() -> GatewayOverviewStats {\n'
production += '        let spaces = allSpaces\n        let headerView = Header()\n'
production += section(controller, '            let onlineSpaces = spaces.filter',
                      '        }else {\n            headerView.gatewayStatusView.setDisplayMode(.gateway)')
production += '        return headerView.gatewayStatusView.stats\n    }\n}\n'

with tempfile.TemporaryDirectory(prefix='site-gateway-metadata-') as folder:
    folder = Path(folder)
    adapter = folder / 'Production.swift'
    adapter.write_text(production)
    binary = folder / 'Tests'
    subprocess.run(['swiftc', '-parse-as-library',
        str(root / 'Pods/SwiftyJSON/Source/SwiftyJSON/SwiftyJSON.swift'),
        str(root / 'SunSmart/Common/Data/SiteGatewayAssociationConsistencyPolicy.swift'),
        str(root / 'SunSmart/Common/Data/SiteTimeZoneValue.swift'),
        str(root / 'SunSmart/Common/Extension/String+Date.swift'),
        str(adapter), str(root / 'Tests/Site/SiteGatewayMetadataReloadTests.swift'),
        '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True, env={**os.environ, 'TZ': 'UTC'})
