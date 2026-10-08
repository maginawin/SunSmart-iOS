#!/usr/bin/env python3
"""Run the production logical-ID allocator and node-slot policy without UIKit/BLE."""
from pathlib import Path
import subprocess
import tempfile

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

with tempfile.TemporaryDirectory(prefix='timed-payload-') as directory:
    binary = Path(directory) / 'Tests'
    subprocess.run(['swiftc', '-parse-as-library', str(policy),
                    str(root / 'Tests/Timed/TimedPayloadTests.swift'), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
