#!/usr/bin/env python3
"""执行生产同步刷新、拓扑与任务生成逻辑；使用隔离的 SDK/数据库边界。"""
from pathlib import Path
import subprocess
import tempfile
import re

ROOT = Path(__file__).resolve().parents[1]
def section(text, start, end):
    offset = text.index(start)
    return text[offset:text.index(end, offset)]
def read(name):
    return (ROOT / name).read_text()
def production():
    adapter = read('SunSmart/Main/Group/Model/GroupProximityLightingData.swift')
    policy = read('SunSmart/Main/Group/Model/ProximityLightingTopologyPolicy.swift')
    # Count entry to the real pure planner without substituting its algorithm.
    policy = policy.replace('        let sortedGroups = groups.sorted', '        TestMetrics.planBuilds += 1\n        let sortedGroups = groups.sorted')
    targets = read('SunSmart/Main/Site/TriggerZone/SiteTriggerZoneTopologyReader.swift')
    tests = read('Tests/Group/NodeSyncStatusRefreshTests.swift').replace('// LOCAL_TARGET_SNAPSHOT',
        section(targets, '    enum LocalTargetSnapshot {', '\n    static func localTargetSnapshot('))
    cell = read('SunSmart/Main/Group/View/GroupsViewCell.swift')
    controller = read('SunSmart/Main/Group/Controller/GroupsViewController.swift')
    appearance = read('Tests/Group/GroupsLiveAppearanceTests.swift')
    appearance = appearance.replace('// PRODUCTION_CELL', section(cell, '    private var syncStatusRequestID', '    override init('))
    appearance = appearance.replace('// PRODUCTION_APPEAR', section(controller, '    override func viewWillAppear', '    override func viewDidAppear'))
    appearance = appearance.replace('// PRODUCTION_VISIBLE', section(controller, '    private func refreshVisibleOnOffAppearance()', '    private func refreshVisibleUI()'))
    appearance = appearance.replace('// PRODUCTION_DISPLAY', section(controller, '    public func collectionView(_ collectionView: UICollectionView, willDisplay', '    public func collectionView(_ collectionView: UICollectionView, layout'))
    scene = read('SunSmart/Main/Scene/Controller/SceneViewController.swift')
    settings = read('SunSmart/Main/Scene/Controller/SceneSettingsViewController.swift')
    appearance = appearance.replace('// PRODUCTION_SCENE_APPEAR', section(scene, '    override func viewWillAppear', '    override func viewDidAppear'))
    appearance = appearance.replace('// PRODUCTION_SCENE_LAYOUT', section(scene, '    override func viewDidLayoutSubviews', '    /// 添加通知监听'))
    appearance = appearance.replace('// PRODUCTION_SCENE_SETTINGS_APPEAR', section(settings, '    override func viewWillAppear', '    override func viewDidAppear'))
    scene_tests = read('Tests/Scene/SceneGroupSyncReadTests.swift').replace('// PRODUCTION_SCENE_COMPARISON',
        section(read('SunSmart/Common/Data/MeshNetwork+SunSmart.swift'), '    /// 当前场景数据应用到指定设备时的目标值', '//    convenience init(lightness:'))
    device_cell = read('SunSmart/Main/Device/View/DevicesViewCell.swift')
    group_detail = read('SunSmart/Main/Group/Controller/GroupViewController.swift')
    members = read('SunSmart/Main/Group/Controller/GroupMembersViewController.swift')
    group_device_tests = read('Tests/Group/GroupDeviceSyncDisplayTests.swift')
    group_device_tests = group_device_tests.replace('// PRODUCTION_DEVICE_SYNC', section(device_cell, '    private var groupSyncDisplay', '    override init('))
    group_device_tests = group_device_tests.replace('// PRODUCTION_MEMBERS_SYNC', section(members, '    override func viewWillDisappear', '    private func isVisibleGroupMemberNode'))
    group_device_tests = group_device_tests.replace('// PRODUCTION_DETAIL_SYNC', section(group_detail, '    private func refreshVisibleGroupSyncStatus()', '    private func updateGroupControlSummaryIfNeeded'))
    group_device_tests = group_device_tests.replace('// PRODUCTION_DETAIL_DISAPPEAR', section(group_detail, '    override func viewWillDisappear', '    /// 刷新Auto状态'))
    for marker, source in [('DETAIL', group_detail), ('MEMBERS', members)]:
        group_device_tests = group_device_tests.replace('// PRODUCTION_' + marker + '_DISPLAY',
            section(source, '    func collectionView(_ collectionView: UICollectionView, willDisplay',
                    '    func collectionView(_ collectionView: UICollectionView, didSelectItemAt' if marker == 'DETAIL' else '    public func collectionView(_ collectionView: UICollectionView, layout'))
    picker_probes = []
    for kind in ['Devices', 'Groups', 'Scenes']:
        source = read(f'SunSmart/Main/Timed/View/Schedule{kind}View.swift')
        observer = re.search(r'        (observe\w+Changes)\(\)', source).group(1)
        cleanup = section(source, '    deinit {', '\n    }') + '\n    }'
        picker_probes.append(f'''
private final class Schedule{kind}ForegroundProbe: PickerForegroundProbe {{
    let schedule: Schedule?
    var superview: NSObject?
    var attached: Bool {{
        get {{ superview != nil }}
        set {{ superview = newValue ? NSObject() : nil }}
    }}
    var appearanceUpdates = 0
    private var deviceNameFilterObservation: UUID?
    private let deviceNameFilterSession = PickerFilterSession()
    private var meshNetworkConnectedObservation: NSObject?
    {section(source, '    private var isShowing', '    init(')}
    init(schedule: Schedule?) {{
        self.schedule = schedule
        {observer}()
    }}
    {cleanup}
    var currentSnapshot: ScheduleTargetSyncSnapshot? {{ syncDisplay.currentSnapshot }}
    func refreshVisibleSyncStatus() {{ appearanceUpdates += 1 }}
    func present() {{ isShowing = true; attached = true; refreshSyncStatus() }}
    func dismiss() {{ hide(); attached = false }}
    {section(source, '    private func hide()', '        UIView.animate')}
    }}
}}
''')
    picker_tests = read('Tests/Timed/TimedPickerForegroundTests.swift').replace(
        '// PRODUCTION_PICKER_PROBES', '\n'.join(picker_probes))
    pieces = [read('SunSmart/Common/Data/AppPerformance.swift'),
        read('SunSmart/Common/Data/DeviceScheduleAddressCleanup.swift'),
        read('SunSmart/Common/Data/SpaceProtectionReadSnapshot.swift'), policy, section(adapter, 'enum ProximityLightingTopologyContext', '\nextension SpaceData'),
        read('SunSmart/Common/Data/NodeSyncTopologySnapshot.swift'),
        read('SunSmart/Common/Data/NodeSyncReadContext.swift'), read('SunSmart/Common/Data/NodeSyncStatusRefresh.swift'),
        read('SunSmart/Common/Data/SpacePageSyncRead.swift'),
        read('SunSmart/Main/Timed/Model/TimedSchedulerOwnerPolicy.swift'),
        'import ObjectiveC\nextension Group {\nprivate static var isOnKey: UInt8 = 0\n'
        + section(read('SunSmart/Common/Data/MeshNetwork+SunSmart.swift'), '    /// 组开关', '    /// 是否支持onoff')
        + section(read('SunSmart/Common/Data/MeshNetwork+SunSmart.swift'), '    /// 有效色温范围', '    func clampEffectiveCct') + '\n}',
        section(read('SunSmart/Common/Data/SpaceSchedulerReadCoordinator.swift'), 'final class SpaceSchedulerReadQueue', '\nfinal class SpaceSchedulerReadCoordinator'),
        'extension Schedule {\n' + section(read('SunSmart/Common/Data/MeshNetwork+SunSmart.swift'), '    func getNeedSyncDatas() -> ScheduleSyncData', '\nextension DeviceSwitchData'),
        read('Tests/Group/SpaceRuntimeCacheTests.swift'), read('Tests/Timed/TimedSyncReadTests.swift'), picker_tests, scene_tests, appearance, group_device_tests,
        'extension Node {\n' + section(read('SunSmart/Common/Data/Node+SyncData.swift'), '    func getNodeSyncProximityLighting(', '    /// 获取网关设备同步的配置') + '\n}',
        'extension Group {\n' + section(read('SunSmart/Common/Data/MeshNetwork+SunSmart.swift'), '    func getNeedSyncScheduleDataNodes(', '\nextension Scene'),
        'extension Schedule {\n' + section(read('SunSmart/Common/Data/MeshNetwork+SunSmart.swift'), '    func targets(node:', '\n    func needsSync(on') + '\n}', tests]
    return '\n'.join(pieces).replace('import NordicSigMeshSDK', '')
if __name__ == '__main__':
    with tempfile.TemporaryDirectory(prefix='node-sync-refresh-') as directory:
        source = Path(directory) / 'Tests.swift'; source.write_text(production())
        binary = Path(directory) / 'tests'
        subprocess.run(['swiftc', '-O', '-D', 'SUNSMART_PERFORMANCE', '-parse-as-library', str(source), '-o', str(binary)], check=True)
        subprocess.run([str(binary)], check=True)
