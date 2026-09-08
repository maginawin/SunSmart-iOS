#!/usr/bin/env python3
"""运行生产构建器及模型；SDK/数据库输入替身不代表协议或真机验收。"""
import argparse
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def section(text, start, end):
    offset = text.index(start)
    return text[offset:text.index(end, offset)]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--baseline-controller', type=Path,
                        help='迁移前控制器，用同一组行为断言建立基线')
    args = parser.parse_args()
    dongle_path = ROOT / 'SunSmart/Main/Space/Model/SyncDongleTaskBuilder.swift'
    models = (ROOT / 'SunSmart/Main/Space/Model/SyncDevicesCellModel.swift').read_text()
    node = (ROOT / 'SunSmart/Common/Data/Node+SyncData.swift').read_text()
    production = 'import Foundation\n' + section(node, 'enum NodeSyncData {', 'extension Group {')
    production += section(models, 'enum SyncDevicesState', 'struct SunricherVendorSetUnacknowledged')
    production += section(models, 'extension NodeSyncData {', 'extension ProfileType {')
    production += section(models, 'class SyncDevicesSectionModel', '/// 当前同步轮次的显示上下文')
    if args.baseline_controller or not dongle_path.exists():
        controller = (args.baseline_controller or ROOT / 'SunSmart/Main/Space/Controller/SyncDevicesViewController.swift').read_text()
        dongle = section(controller, '            case .dongle(let dongleData):', '            case .proximityLightingPath(let datas):')
        dongle = dongle.replace('case .dongle(let dongleData):', 'default:')
        production += '''
func buildDongle(_ dongleData: DeviceDongleData) -> (configturationDevice: SyncDevicesModel?, removeDevice: SyncDevicesModel?) {
    let configurationSection = SyncDevicesSectionModel(title: "configuration")
    let removeSection = SyncDevicesSectionModel(title: "remove")
    switch true {
''' + dongle + '''
    }
    return (configurationSection.devices.first, removeSection.devices.first)
}
'''
    else:
        production += dongle_path.read_text().replace('import NordicSigMeshSDK', '')
        production += '''
func buildDongle(_ data: DeviceDongleData) -> (configturationDevice: SyncDevicesModel?, removeDevice: SyncDevicesModel?) {
    SyncDongleTaskBuilder().makeDeviceModels(data: data)
}
'''
    if args.baseline_controller:
        controller = args.baseline_controller.read_text()
        methods = section(controller, '    private func getSyncDeviceModel(', '    /// 返回')
        methods = methods.replace('private func ', 'func ')
        production += 'class BaselineBuilder {\nvar profileSensorProtectionContext: Bool?\n'
        production += 'typealias GatewayRecoveryTrigger = SyncDevicesViewController.GatewayRecoveryTrigger\n'
        production += methods + '\n}\n'
        production += '''
func buildDevice(group: Group?, node: Node, effectiveMemberCount: Int? = nil, profileSyncContext: GroupProfileSyncContext? = nil, protectsProfileSensors: Bool = false) -> (configturationDevice: SyncDevicesModel?, removeDevice: SyncDevicesModel?) {
    let builder = BaselineBuilder()
    builder.profileSensorProtectionContext = protectsProfileSensors ? true : nil
    return builder.getSyncDeviceModel(group: group, node: node, effectiveMemberCount: effectiveMemberCount, profileSyncContext: profileSyncContext)
}
func buildGateway(node: Node, gateway: GatewayModel, trigger: SyncDevicesViewController.GatewayRecoveryTrigger) -> SyncDevicesModel? {
    BaselineBuilder().makeGatewayRecoveryDeviceModel(node: node, gateway: gateway, trigger: trigger)
}
func buildServerSteps(node: Node, gateway: GatewayModel, dependencies: [SyncDeviceStepModel], includesVerification: Bool) -> [SyncDeviceStepModel] {
    BaselineBuilder().makeGatewayServerRecoverySteps(node: node, gateway: gateway, authorizationDependencies: dependencies, includesVerification: includesVerification)
}
'''
    else:
        for name in ['SyncDeviceTaskBuilder', 'SyncGatewayTaskBuilder', 'SyncProfileTaskBuilder', 'SyncProximityTaskBuilder', 'SyncParameterTaskBuilder']:
            source = (ROOT / f'SunSmart/Main/Space/Model/{name}.swift').read_text()
            assert 'import UIKit' not in source and 'XWHUD' not in source
            production += source.replace('import NordicSigMeshSDK', '')
        production += '''
func buildDevice(group: Group?, node: Node, effectiveMemberCount: Int? = nil, profileSyncContext: GroupProfileSyncContext? = nil, protectsProfileSensors: Bool = false) -> (configturationDevice: SyncDevicesModel?, removeDevice: SyncDevicesModel?) {
    SyncDeviceTaskBuilder().makeDeviceModels(group: group, node: node, effectiveMemberCount: effectiveMemberCount, profileSyncContext: profileSyncContext, protectsProfileSensors: protectsProfileSensors)
}
func buildGateway(node: Node, gateway: GatewayModel, trigger: SyncDevicesViewController.GatewayRecoveryTrigger) -> SyncDevicesModel? {
    try? SyncGatewayTaskBuilder().makeRecoveryDevice(node: node, gateway: gateway, trigger: trigger).get()
}
func buildServerSteps(node: Node, gateway: GatewayModel, dependencies: [SyncDeviceStepModel], includesVerification: Bool) -> [SyncDeviceStepModel] {
    SyncGatewayTaskBuilder().makeServerRecoverySteps(node: node, gateway: gateway, authorizationDependencies: dependencies, includesVerification: includesVerification)
}
'''
    with tempfile.TemporaryDirectory(prefix='sync-task-builders-') as directory:
        source = Path(directory) / 'Production.swift'
        source.write_text(production)
        binary = Path(directory) / 'Tests'
        flags = ['-D', 'BASELINE_BUILD'] if args.baseline_controller else []
        subprocess.run(['swiftc', '-parse-as-library', *flags,
                        str(ROOT / 'Tests/Sync/SyncTaskBuilderFixtures.swift'), str(source),
                        str(ROOT / 'SunSmart/Common/Data/TimedScheduleTimeSyncPolicy.swift'),
                        str(ROOT / 'SunSmart/Main/Timed/Model/TimedSchedulerOwnerPolicy.swift'),
                        str(ROOT / 'Tests/Sync/SyncTaskBuilderTests.swift'), '-o', str(binary)], check=True)
        subprocess.run([str(binary)], check=True)
        if not args.baseline_controller:
            policies = ['SyncOperationResultPolicy', 'SyncRetryPolicy', 'SyncResultCollector']
            policy_source = Path(directory) / 'Policies.swift'
            policy_source.write_text('\n'.join((ROOT / f'SunSmart/Main/Space/Model/{name}.swift').read_text().replace('import NordicSigMeshSDK', '') for name in policies))
            subprocess.run(['swiftc', '-parse-as-library',
                            str(ROOT / 'Tests/Sync/SyncTaskBuilderFixtures.swift'), str(source), str(policy_source),
                            str(ROOT / 'SunSmart/Common/Data/TimedScheduleTimeSyncPolicy.swift'),
                            str(ROOT / 'SunSmart/Main/Timed/Model/TimedSchedulerOwnerPolicy.swift'),
                            str(ROOT / 'Tests/Sync/SyncExecutionPolicyTests.swift'), '-o', str(binary)], check=True)
            subprocess.run([str(binary)], check=True)
            subprocess.run(['swiftc', '-parse-as-library',
                            str(ROOT / 'Tests/Device/GatewayRecoveryAssociatedSpacesContractTests.swift'),
                            '-o', str(binary)], check=True)
            subprocess.run([str(binary), str(ROOT / 'SunSmart/Main/Space/Model/SyncGatewayTaskBuilder.swift')], check=True)


if __name__ == '__main__':
    main()
