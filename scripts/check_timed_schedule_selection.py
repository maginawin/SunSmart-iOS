#!/usr/bin/env python3
"""Execute production picker handlers with UIKit/SDK boundaries replaced."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def section(source, start, end):
    offset = source.index(start)
    return source[offset:source.index(end, offset)]


controller = (ROOT / 'SunSmart/Main/Timed/Controller/ScheduleAddViewController.swift').read_text()
picker = (ROOT / 'SunSmart/Main/Timed/View/ScheduleDevicesView.swift').read_text()
source = (ROOT / 'Tests/Timed/TimedPickerSelectionTests.swift').read_text()
source = source.replace('// PRODUCTION_SELECTION', section(
    controller, '    func view(_ view: ScheduleAddTargetView, didClickTargetAction target:',
    '    /// 点击同步失败提示回调'))
source = source.replace('// PRODUCTION_EDITOR_REFRESH', section(
    controller, '    private func refreshSyncStatus()', '    private func setupData()'))
source = source.replace('// PRODUCTION_EDITOR_HIDE', section(
    controller, '    override func viewWillDisappear', '    private func refreshSyncStatus()'))
source = source.replace('// PRODUCTION_PICKER_REFRESH', section(
    picker, '    private func refreshSyncStatus()', '    private func observeSchedulerChanges()'))
source = source.replace('// PRODUCTION_OFFLINE', section(
    picker, '    private func checkOffline()', '    private func updateEmptyUI()'))
source = source.replace('// PRODUCTION_SELECT_ALL', section(
    picker, '    @objc private func selectAllBtnAction', '    @objc private func deviceFilterBtnAction'))
source = source.replace('// PRODUCTION_FINISH', section(
    picker, '    @objc private func cancelBtnAction', '    /// 更新全选状态'))
source = source.replace('@objc private func ', 'func ').replace('private func checkOffline', 'func checkOffline')
source = source.replace('private func refreshSyncStatus', 'func refreshSyncStatus')
source = source.replace('override func viewWillDisappear', 'func viewWillDisappear').replace('        super.viewWillDisappear(animated)\n', '')
with tempfile.TemporaryDirectory(prefix='timed-selection-') as directory:
    path = Path(directory) / 'Tests.swift'
    path.write_text(source)
    binary = Path(directory) / 'tests'
    subprocess.run(['swiftc', str(path), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
