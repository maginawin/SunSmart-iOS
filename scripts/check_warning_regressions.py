#!/usr/bin/env python3
"""执行生产 Operation、照片请求状态和云同步授权任务的聚焦行为回归。"""
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
sdk = Path(sys.argv[1]) if len(sys.argv) > 1 else root / '.local-sdk/nordic-sig-mesh-sdk'


def section(source, start, end):
    begin = source.index(start)
    return source[begin:source.index(end, begin)]


with tempfile.TemporaryDirectory(prefix='warning-regressions-') as directory:
    out = Path(directory)

    def run(name, sources):
        executable = out / name
        subprocess.run(['swiftc', '-swift-version', '5', '-parse-as-library',
                        *map(str, sources), '-o', str(executable)], check=True)
        subprocess.run([str(executable)], check=True, timeout=45)

    utils = sdk / 'Sources/NordicSigMeshSDK/nRFMeshProvision/Utils'
    run('operations', [utils / 'AsyncOperation.swift', utils / 'AsyncResultOperation.swift',
                       sdk / 'Tests/Standalone/AsyncOperationLifecycleTests.swift'])
    remote = (sdk / 'Sources/NordicSigMeshSDK/nRFMeshProvision/Bearer/Remote/PBRemoteBearer.swift').read_text()
    send = section(remote, 'final private class Send:', '/// Implementation of the PB Remote bearer.')
    remote_harness = (sdk / 'Tests/Standalone/RemoteProvisioningSendLifecycleHarness.swift').read_text()
    remote_test = out / 'Remote.swift'
    remote_test.write_text(remote_harness.replace('// PRODUCTION_SEND', send))
    run('remote', [utils / 'AsyncOperation.swift', utils / 'AsyncResultOperation.swift', remote_test])

    scanner = (root / 'SunSmart/Thirdparty/ScanQRCode/LBXScanWrapper.swift').read_text()
    source = section(scanner, 'struct ScanPhotoCaptureState', 'open class LBXScanWrapper')
    source += '''
@main struct PhotoTests {
    static func main() {
        var state = ScanPhotoCaptureState<String>()
        precondition(!state.begin(id: 0, results: []))
        precondition(state.begin(id: 1, results: ["QR1", "QR2"]))
        precondition(!state.begin(id: 2, results: ["duplicate"]))
        precondition(state.take(id: 2) == nil)
        precondition(state.take(id: 1) == ["QR1", "QR2"])
        precondition(state.take(id: 1) == nil)
        precondition(state.begin(id: 3, results: ["cancelled"]))
        state.cancel()
        precondition(state.begin(id: 4, results: ["restarted"]))
        precondition(state.take(id: 3) == nil)
        precondition(state.take(id: 4) == ["restarted"])
        print("PASS: Photo duplicate, empty, cancellation and stale completion handling")
    }
}
'''
    photo = out / 'Photo.swift'
    photo.write_text(source)
    run('photos', [photo])

    view_model = (root / 'SunSmart/Main/Group/Switch/Model/GroupPowerSwitchesViewModel.swift').read_text()
    formatting = (root / 'SunSmart/Common/Extension/String+Extension.swift').read_text()
    mac_source = '''import Foundation
struct Proxy { let isPowerSwitch = true; let macAddressResult: String? }
struct PJEightKeySwitchData { let proxyNode: Proxy?; let enOceanMacAddress: String? }
extension String {
    var localizedString: String {
        ["switch_mac_format": "MAC: %@", "switch_mac_unavailable": "MAC: N/A", "not_linked_to_switch": "Unlinked"][self] ?? self
    }
    func subString(rang: NSRange) -> String { (self as NSString).substring(with: rang) }
'''
    mac_source += section(formatting, '    func getMacAddressSegmentString()', '    /// 是否有效的Decimal')
    mac_source += '\n}\nstruct ViewModel {\n' + section(view_model, '    func isRealSwitch(', '    func groupTitle(') + '\n}\n'
    mac_source += '''
@main struct MacTests {
    static func main() {
        let model = ViewModel()
        precondition(model.detailText(for: .init(proxyNode: nil, enOceanMacAddress: "001122334455")) == "Unlinked")
        precondition(model.detailText(for: .init(proxyNode: Proxy(macAddressResult: "11:22"), enOceanMacAddress: nil)) == "MAC: 11:22")
        precondition(model.detailText(for: .init(proxyNode: Proxy(macAddressResult: nil), enOceanMacAddress: "001122334455")) == "MAC: 00:11:22:33:44:55")
        for value: String? in [nil, "", "12345"] {
            precondition(model.detailText(for: .init(proxyNode: Proxy(macAddressResult: nil), enOceanMacAddress: value)) == "MAC: N/A")
        }
        print("PASS: MAC linked, formatted, missing and malformed-length display")
    }
}
'''
    mac = out / 'Mac.swift'
    mac.write_text(mac_source)
    run('mac', [mac])

    cloud = (root / 'SunSmart/Common/Cloud/CloudSynchronizationManager.swift').read_text()
    task = section(cloud, '            gatewayAuthorizationTask?.cancel()\n            gatewayAuthorizationTask =',
                   '            return\n        }\n        configurationUploadTask?.cancel()')
    harness = (root / 'Tests/Cloud/WarningCloudTaskHarness.swift').read_text()
    cloud_test = out / 'Cloud.swift'
    cloud_test.write_text(harness.replace('// PRODUCTION_GATEWAY_TASK', task))
    run('cloud', [cloud_test, root / 'SunSmart/Main/Device/Gateway/Model/GatewayCloudSyncGenerationPolicy.swift'])
