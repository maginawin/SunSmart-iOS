#!/usr/bin/env python3
"""Run the production logical-ID allocator and node-slot policy without UIKit/BLE."""
from pathlib import Path
import subprocess
import tempfile
import sys

root = Path(__file__).resolve().parents[1]
source = (root / 'SunSmart/Common/Data/MeshNetwork+SunSmart.swift').read_text()
start = source.index('    func getNextAvailableScheduleId() -> Int? {')
end = source.index('\n    }', start) + len('\n    }')
allocator = source[start:end]
harness = '''import Foundation
struct Schedule { var id: Int }
final class MeshNetworkManager {
    var schedules: [Schedule] = []
''' + allocator + '\n}\n'
tests = root / 'Tests/Timed/TimedDeviceSlotTests.swift'
policy = root / 'SunSmart/Main/Timed/Model/TimedSchedulerSlotPolicy.swift'
with tempfile.TemporaryDirectory(prefix='timed-device-slots-') as directory:
    directory = Path(directory)
    assembled = directory / 'Harness.swift'
    assembled.write_text(harness)
    binary = directory / 'Tests'
    inputs = [str(assembled), str(tests)]
    if policy.exists():
        inputs.insert(0, str(policy))
    subprocess.run(['swiftc', '-parse-as-library', *inputs, '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)

api = (root / 'SunSmart/Common/Network/NetowrkReqeustApi.swift').read_text()
site = api[api.index('        case .siteAdd(let siteData, let useDeivceAddressNum):', api.index('var parameters')):]
site = site[:site.index('        case .siteDelete')]
space = api[api.index('        case .spaceUpload(let siteId, let spaceId, let spaceData):', api.index('var parameters')):]
space = space[:space.index('        case .spaceDelete')]
request_fixture = """import Foundation
struct UserData { static let currentUserId = "fixture", currentUserName = "fixture" }
enum TimedUploadTestAPI {
    case siteAdd(siteData: [String: Any], useDeivceAddressNum: Int)
    case siteUpload(siteData: [String: Any])
    case spaceUpload(siteId: String, spaceId: String, spaceData: [String: Any])
    var parameters: [String: Any] { switch self {
""" + site + space + "} } }"
with tempfile.TemporaryDirectory(prefix='timed-payload-') as directory:
    binary = Path(directory) / 'Tests'
    request_source = Path(directory) / 'Request.swift'
    request_source.write_text(request_fixture)
    subprocess.run(['swiftc', '-parse-as-library', str(policy), str(request_source),
                    str(root / 'Tests/Timed/TimedPayloadTests.swift'), '-o', str(binary)], check=True)
    snapshot = sys.argv[sys.argv.index('--snapshot') + 1:][:1] if '--snapshot' in sys.argv else []
    if '--stale-snapshot' in sys.argv:
        snapshot = ['--stale-snapshot', sys.argv[sys.argv.index('--stale-snapshot') + 1]]
    subprocess.run([str(binary), *snapshot], check=True)
