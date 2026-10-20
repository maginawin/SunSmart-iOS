#!/usr/bin/env python3
"""Execute the real HDB matcher and scoped Vendor SDK codecs on macOS.

UIKit prevents linking the whole iOS SDK into this CLI fixture. Extract the
unchanged 0x32/0x33/0x34/0x35 encoding, common status header, echo decoding,
and preparation/Auto SIG Set constructors/parameters from the mapped SDK. Property
value byte serialization and unrelated SIG messages are test boundaries.
This checks preparation values and packet compatibility, not BLE transport.
"""
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SDK = ROOT / ".local-sdk/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK"
status = (SDK / "MeshLib/Message/Vendor/SunricherVendorStatus.swift").read_text()
request = (SDK / "MeshLib/Message/Vendor/SunricherVendorSet.swift").read_text()
data = (SDK / "nRFMeshProvision/Type Extensions/Data.swift").read_text()
messages = (ROOT / "SunSmart/Main/Space/HDB/Model/HDBLightingMessages.swift").read_text()
lighting = SDK / "nRFMeshProvision/Mesh Messages/Lighting"


def section(text, start, end):
    offset = text.index(start)
    return text[offset:text.index(end, offset)]


def block(text, start):
    offset = text.index(start)
    opening = text.index("{", offset)
    depth = 1
    for index in range(opening + 1, len(text)):
        depth += (text[index] == "{") - (text[index] == "}")
        if depth == 0:
            return text[offset:index + 1]
    raise ValueError(f"Unclosed Swift block: {start}")


names = ("manualOverrideTimeout", "manualControlEnabled",
         "lightAutoAdjustEnabled", "lightControlEnabled")
declarations = "\n".join(re.search(r"    case " + name + r"\([^\n]+", request)[0] for name in names)
function_parameters = "\n".join(
    re.search(r"    case " + name + r"\([^\n]+", status)[0] for name in names[:3]
)
response_init = block(status, "    init?(opcode: VendorOpCode, subcode: UInt8?)")
response_code = block(status, "    var code: [UInt8]")
request_data = block(request, "    var data: Data")
request_command = block(request, "    var command: ResponseCode")
status_init = block(status, "        init?(data: Data)")

parts = [
    "import Foundation",
    (ROOT / "SunSmart/Common/Data/HDBConfiguration.swift").read_text(),
    (ROOT / "SunSmart/Common/Data/HDBLightingConfigurationPolicy.swift").read_text(),
    "public protocol MeshMessage { var parameters: Data? { get } }",
    "public protocol AcknowledgedMeshMessage: MeshMessage {}",
    "public protocol StaticVendorResponse: MeshMessage {}",
    block(status, "public enum VendorOpCode:"),
    block(status, "public enum ManualOverrideState:"),
    # All four SDK response mappings ignore subcode. The HDB matcher must
    # independently reject nonzero subcodes.
    "public enum ResponseCode {\n" + "\n".join("case " + name for name in names)
    + "\ninit?(opcode: VendorOpCode, subcode: UInt8?) { switch opcode {\n"
    + section(response_init, "        case .manualOverrideTimeout:", "        case .enOcean:")
    + "default: return nil\n} }\nvar code: [UInt8] { switch self {\n"
    + section(response_code, "        case .manualOverrideTimeout:", "        case .motionSensitivity:")
    + "} }\n}",
    "public enum FunctionParameters {\n" + function_parameters + "\n}",
    "public enum VendorFunctionSet {\n" + declarations
    + "\nvar data: Data { let data = Data(command.code); switch self {\n"
    + section(request_data, "        case .manualOverrideTimeout(", "        case .motionSensitivity(")
    + "} }\nvar command: ResponseCode { switch self {\n"
    + section(request_command, "        case .manualOverrideTimeout:", "        case .motionSensitivity:")
    + "} }\n}",
    # The public request/response wrappers retain their production properties
    # and constructors. Sending validation and unrelated request decoding are
    # outside this fixture.
    "public struct SunricherVendorSet: AcknowledgedMeshMessage {\n"
    + section(request, "    public let function:", "    public func validateForSending()")
    + "}",
    block(status, "public struct SunricherVendorStatus:"),
    "extension SunricherVendorStatus {\n"
    + section(status, "    public struct Status {", "        private static func wifiGatewayParameters")
    + section(status_init, "        init?(data: Data)", "            if status == 0 {")
    + section(status_init, "            if data.count >= 4 {", "                case .pwmFrequency:")
    + section(status_init, "                case .manualOverrideTimeout:", "                case .daylightConditionRecall:")
    + "default: self.parameters = nil\n} } else { self.parameters = nil }\n}\n}\n}",
    "extension Data {\n"
    + block(data, "    func read<R: FixedWidthInteger>")
    + "\n}",
    # Foundation-only byte append boundaries; request field order is SDK code.
    """func + <T: FixedWidthInteger>(lhs: Data, rhs: T) -> Data {
        var value = rhs.littleEndian
        return lhs + withUnsafeBytes(of: &value) { Data($0) }
    }
    func + (lhs: Data, rhs: Bool) -> Data { lhs + UInt8(rhs ? 1 : 0) }
    """,
    # Keep the real SIG Set field selection and constructors. The small property
    # serializer boundary supports the lightness/time values used by HDB.
    """public struct DeviceProperty {
        public let id: UInt16
        init(_ id: UInt16) { self.id = id }
        init(id: UInt16) { self.id = id }
        static let lightControlTimeProlong = DeviceProperty(id: 0x003B)
    }
    public enum DevicePropertyCharacteristic {
        case timeMillisecond24(UInt32?)
        case perceivedLightness(UInt16)
        var data: Data {
            switch self {
            case .timeMillisecond24(let value): return Data((Data() + (value ?? 0xFFFFFF)).prefix(3))
            case .perceivedLightness(let value): return Data() + value
            }
        }
    }
    public struct TransitionTime {
        let rawValue: UInt8
        static let `default` = TransitionTime(rawValue: 0x41)
    }
    """,
    *[
        "public struct " + name + ": "
        + ("MeshMessage" if name.endswith("Unacknowledged") else "AcknowledgedMeshMessage") + " {\n"
        + section((lighting / (name + ".swift")).read_text(), "    public let ", "    public init?(parameters:")
        + "\n}"
        for name in ("LightLCPropertySet", "LightLCPropertySetUnacknowledged", "LightLCModeSet", "LightLCOccupancyModeSet")
    ],
    *[
        "public struct " + name + ": " + protocol + " {\n"
        + re.search(r"    public static let opCode[^\n]+", (lighting / (name + ".swift")).read_text())[0]
        + "\n" + section((lighting / (name + ".swift")).read_text(), "    public var tid:", "    public init?(parameters:")
        + "\n}"
        for name, protocol in (("LightLCLightOnOffSet", "AcknowledgedMeshMessage"),
                               ("LightLCLightOnOffSetUnacknowledged", "MeshMessage"))
    ],
    "enum HDBLightingMessages {\n" + block(messages, "    static func message(")
    + "\n" + block(messages, "    static func preparation(")
    + "\n" + block(messages, "    static func matches(") + "\n}",
    (ROOT / "Tests/HDB/HDBLightingMessagesTests.swift").read_text(),
]
with tempfile.TemporaryDirectory(prefix="hdb-lighting-messages-") as directory:
    harness = Path(directory) / "Harness.swift"
    harness.write_text("\n".join(parts))
    binary = Path(directory) / "tests"
    subprocess.run(["swiftc", "-parse-as-library", str(harness), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
