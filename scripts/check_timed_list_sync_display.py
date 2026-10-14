#!/usr/bin/env python3
"""Run production Timed presentation and operation callbacks with controlled replies."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def section(path, start, end):
    text = (ROOT / path).read_text()
    offset = text.index(start)
    return text[offset:text.index(end, offset)]


source = (ROOT / 'Tests/Timed/TimedListSyncDisplayTests.swift').read_text()
source = source.replace('// PRODUCTION_DISPLAY', section(
    'SunSmart/Common/Data/SpacePageSyncRead.swift',
    'final class TimedListSyncDisplayState', 'struct ScheduleTargetSyncSnapshot'))
source = source.replace('// PRODUCTION_OPERATION', section(
    'SunSmart/Main/Timed/Controller/TimedViewController.swift',
    '    private func setScheduleEnabled', '    private func refreshVisibleUI'))
source = source.replace('// PRODUCTION_INDICATOR', section(
    'SunSmart/Main/Timed/View/SchedulesViewCell.swift',
    '    func updateSyncIndicator', '    /// 启用/禁用事件回调'))
source = source.replace('// PRODUCTION_WILL_DISPLAY', section(
    'SunSmart/Main/Timed/Controller/TimedViewController.swift',
    '    func collectionView(_ collectionView: UICollectionView, willDisplay',
    '    func collectionView(_ collectionView: UICollectionView, layout'))
with tempfile.TemporaryDirectory(prefix='timed-list-display-') as directory:
    swift = Path(directory) / 'Tests.swift'
    binary = Path(directory) / 'tests'
    swift.write_text(source)
    subprocess.run(['swiftc', '-parse-as-library', str(swift), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
