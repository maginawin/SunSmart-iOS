#!/usr/bin/env python3
"""Execute production Timed success exits and Space cloud-change handling.

UIKit scheduling, Mesh storage and queue transport are controlled boundaries.
Real SQLite/Codable and upload receipts are covered by their existing harnesses.
"""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]


def section(source, start, end):
    offset = source.index(start)
    return source[offset:source.index(end, offset)]


controller = (root / 'SunSmart/Main/Timed/Controller/ScheduleAddViewController.swift').read_text()
space = (root / 'SunSmart/Main/Space/Controller/SpaceViewController.swift').read_text()
imports = (root / 'SunSmart/Common/Data/ImportData.swift').read_text()
fixture = (root / 'Tests/Timed/TimedEmptyTargetCloudSyncTests.swift').read_text()
fixture = fixture.replace('// PRODUCTION_ADD_SUCCESS', section(
    controller, '        MeshNetworkManager.instance.schedules.append(schedule)', '    /// 删除（编辑）'))
fixture = fixture.replace('// PRODUCTION_EDIT_SUCCESS', section(
    controller, '        MeshNetworkManager.instance.schedules = candidates', '    /// Read all Models'))
delete = section(controller, '    @objc private func deleteBtnAction()', '        guard MeshLibManager.manager.isMeshNetworkConnected else {')
fixture = fixture.replace('// PRODUCTION_EMPTY_DELETE', delete.replace('@objc private func', 'func') + '    }\n')
fixture = fixture.replace('// PRODUCTION_SPACE_CHANGE', section(
    space, 'enum SpaceChangeDataType {', 'private enum SpacePresenceStopReason:'))
fixture = fixture.replace('// PRODUCTION_IMPORT_DECISION', section(
    imports, '            let shouldApplyServerData =', '            // 服务器最后更新时间'))
with tempfile.TemporaryDirectory(prefix='timed-empty-cloud-') as directory:
    directory = Path(directory)
    source = directory / 'Harness.swift'
    source.write_text(fixture)
    binary = directory / 'Tests'
    subprocess.run(['swiftc', '-parse-as-library', str(source), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
