#!/usr/bin/env python3
"""执行生产同步刷新、拓扑与任务生成逻辑；使用隔离的 SDK/数据库边界。"""
from pathlib import Path
import subprocess
import tempfile

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
        read('Tests/Group/SpaceRuntimeCacheTests.swift'), scene_tests, appearance,
        'extension Node {\n' + section(read('SunSmart/Common/Data/Node+SyncData.swift'), '    func getNodeSyncProximityLighting(', '    /// 获取网关设备同步的配置') + '\n}',
        'extension Schedule {\n' + section(read('SunSmart/Common/Data/MeshNetwork+SunSmart.swift'), '    func targets(node:', '\n    func needsSync(on') + '\n}', tests]
    return '\n'.join(pieces).replace('import NordicSigMeshSDK', '')
if __name__ == '__main__':
    with tempfile.TemporaryDirectory(prefix='node-sync-refresh-') as directory:
        source = Path(directory) / 'Tests.swift'; source.write_text(production())
        binary = Path(directory) / 'tests'
        subprocess.run(['swiftc', '-O', '-D', 'SUNSMART_PERFORMANCE', '-parse-as-library', str(source), '-o', str(binary)], check=True)
        subprocess.run([str(binary)], check=True)
