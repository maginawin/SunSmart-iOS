#!/usr/bin/env python3
"""Run HDB control with the mapped SDK's Presence/Sensor Status encoding.

The radio, database and unrelated messages remain boundaries; outgoing Sensor
Status constructors, property ID, Bool data and MPID marshalling use SDK code.
"""
from pathlib import Path
import re
import subprocess
import tempfile
from hdb_publication_test_source import with_publication_policy

ROOT = Path(__file__).resolve().parents[1]
SDK = ROOT / ".local-sdk/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/nRFMeshProvision"


def block(text, signature):
    start = text.index(signature)
    opening = text.index("{", start)
    depth = 1
    for index in range(opening + 1, len(text)):
        depth += (text[index] == "{") - (text[index] == "}")
        if depth == 0:
            return text[start:index + 1]
    raise ValueError(f"Unclosed Swift block: {signature}")


sensor = (SDK / "Mesh Messages/Sensors/SensorStatus.swift").read_text()
property_source = (SDK / "Mesh Messages/DeviceProperty.swift").read_text()
data_source = (SDK / "Type Extensions/Data.swift").read_text()
property_id = re.search(r"case \.presenceDetected: return [^\n]+", block(property_source, "public var id:"))[0]
bool_data = re.search(r"case \.bool\(let value\):\s+return [^\n]+", block(property_source, "var data:"))[0]
sensor_codec = "\n".join([
    "struct SensorStatus: MeshMessage {",
    "enum Property { case presenceDetected; var id: UInt16 { switch self { " + property_id + " } } }",
    "enum Value: Equatable { case bool(Bool); var data: Data { switch self { " + bool_data + " } } }",
    "typealias SensorValue = (property: Property, value: Value)",
    # Only adapt visibility and optionality to this fixture's MeshMessage API.
    sensor[sensor.index("    public static let opCode:"):sensor.index("    public init?(parameters:")]
        .replace("public ", "").replace("parameters: Data?", "parameters: Data"),
    block(sensor, "    static func marshal("),
    "}",
    block(property_source, "private extension Bool"),
    block(data_source, "public protocol DataConvertible"),
    block(data_source, "extension DataConvertible"),
    "extension UInt16: DataConvertible {}",
])


def source(path):
    text = (ROOT / path).read_text().replace("import NordicSigMeshSDK", "")
    if path.endswith("HDBControlTestBoundaries.swift"):
        text = text.replace(block(text, "struct SensorStatus:"), sensor_codec)
    return text


files = [
    "SunSmart/Common/Data/HDBConfiguration.swift",
    "SunSmart/Common/Data/HDBLightingZonePolicy.swift",
    "SunSmart/Common/Data/HDBConfigurationStore.swift",
    "SunSmart/Common/Data/HDBConfigurationStore+Mesh.swift",
    "SunSmart/Common/Data/LightGroupControlCommandSender.swift",
    "SunSmart/Main/Space/Model/SyncRunLifecycle.swift",
    "SunSmart/Main/Space/Model/SyncSessionCoordinator.swift",
    "SunSmart/Main/Space/HDB/Model/HDBLightingZoneExecutor.swift",
    "SunSmart/Main/Space/HDB/Model/HDBLightingZoneService.swift",
    "Tests/HDB/HDBTestBoundaries.swift",
    "Tests/HDB/HDBMeshTestBoundaries.swift",
    "Tests/HDB/HDBControlTestBoundaries.swift",
    "Tests/HDB/HDBZoneControlTests.swift",
]
files += ["SunSmart/Common/Data/HDBLightingConfigurationPolicy.swift", "SunSmart/Common/Data/HDBDevicePreparationPolicy.swift", "SunSmart/Main/Space/HDB/Model/HDBDeviceSyncContext.swift", "Tests/HDB/HDBDeviceSyncTestBoundaries.swift"]
with tempfile.TemporaryDirectory(prefix="hdb-control-") as directory:
    harness = Path(directory) / "Harness.swift"
    harness.write_text(with_publication_policy("enum HDBLightingError: Error { case notPrepared }\n" + "\n".join(source(f) for f in files) + "\n" + (ROOT / "SunSmart/Main/Space/HDB/Model/HDBDeviceSyncService.swift").read_text().split("/// A task owns")[0].replace("import NordicSigMeshSDK", ""), ROOT))
    binary = Path(directory) / "tests"
    subprocess.run(["swiftc", "-parse-as-library", str(harness), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
