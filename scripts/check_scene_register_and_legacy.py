#!/usr/bin/env python3
"""Run the actual SDK register reconciliation and SceneExecuteData Codable.

Transport/node ownership is a minimal fixture. This does not test real Mesh.
"""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
sdk = (root / '.local-sdk/nordic-sig-mesh-sdk').resolve() / 'Sources/NordicSigMeshSDK'
handler = (sdk / 'nRFMeshProvision/Layers/Foundation Layer/SceneClientHandler.swift').read_text()
start = handler.index('        case let status as SceneRegisterStatus:')
end = handler.index('        default:', start)
reconcile = handler[start:end].replace('        case let status as SceneRegisterStatus:', '')
stubs = r'''
import Foundation
public typealias SceneNumber = UInt16
public struct LightLCProperty: Codable {}
final class Element { let unicastAddress: UInt16 = 1; var observedSceneRegister: Set<UInt16>? }
final class Node { let elements = [Element()] }
final class Scene {
    let number: UInt16
    var addresses = Set<UInt16>()
    init(_ number: UInt16) { self.number = number }
    func add(address: UInt16) { addresses.insert(address) }
    func remove(address: UInt16) { addresses.remove(address) }
}
final class Network {
    let node = Node()
    var scenes = [Scene(1), Scene(2)]
    func node(withAddress: UInt16) -> Node? { withAddress == 1 ? node : nil }
}
struct Status { struct Code { let rawValue: UInt8 }; let status: Code; let scenes: [UInt16] }
final class Handler {
    let meshNetwork = Network()
    func apply(_ status: Status, source: UInt16 = 1) {
'''
tests = r'''
    }
}
@main struct Tests {
    static func main() throws {
        let handler = Handler()
        handler.apply(Status(status: .init(rawValue: 0), scenes: [1, 99, 0xFF00]))
        precondition(handler.meshNetwork.scenes.count == 2, "Read must not create foreign business scenes")
        precondition(handler.meshNetwork.scenes[0].addresses == [1])
        precondition(handler.meshNetwork.node.elements[0].observedSceneRegister == [1, 99, 0xFF00])
        handler.apply(Status(status: .init(rawValue: 1), scenes: []))
        precondition(handler.meshNetwork.node.elements[0].observedSceneRegister == [1, 99, 0xFF00])
        handler.apply(Status(status: .init(rawValue: 2), scenes: [2, 2]))
        precondition(handler.meshNetwork.node.elements[0].observedSceneRegister == [1, 99, 0xFF00])
        handler.apply(Status(status: .init(rawValue: 0), scenes: []))
        precondition(handler.meshNetwork.scenes.allSatisfy { $0.addresses.isEmpty })
        precondition(handler.meshNetwork.node.elements[0].observedSceneRegister == [])
        let legacy = Data(#"[{"sceneNumber":7,"isOn":true,"lightness":40000,"cct":3500,"state":1},{"sceneNumber":8,"isOn":false,"lightness":0,"cct":2700,"state":2}]"#.utf8)
        let decoder = JSONDecoder(), encoder = JSONEncoder()
        let old = try decoder.decode([SceneExecuteData].self, from: legacy)
        precondition(old[0].sceneNumber == 7 && old[0].lightness == 40000 && old[0].cct == 3500)
        precondition(old[0].hue == 0 && old[1].state == .waitDelete)
        let restored = try decoder.decode([SceneExecuteData].self, from: encoder.encode(old))
        precondition(restored.map(\.sceneNumber) == [7,8] && restored[1].state == .waitDelete)
        let many = (1...32).map { SceneExecuteData(sceneNumber: UInt16($0), isOn: true, lightness: 1000) }
        let roundtrip = try decoder.decode([SceneExecuteData].self, from: encoder.encode(many))
        precondition(roundtrip.count == 32 && roundtrip[31].sceneNumber == 32)
        let empty = try decoder.decode([SceneExecuteData].self, from: Data("[]".utf8))
        precondition(empty.isEmpty)
        print("Scene register/legacy tests passed: no synthesized scenes, residual/special occupancy, empty read, old defaults, pending deletion, 32-item roundtrip")
    }
}
'''.replace(r'\\.', r'\.')
with tempfile.TemporaryDirectory(prefix='scene-register-') as directory:
    directory = Path(directory)
    assembled = directory / 'Tests.swift'
    assembled.write_text(stubs + reconcile + tests)
    binary = directory / 'Tests'
    subprocess.run(['swiftc', '-parse-as-library', str(sdk / 'MeshLib/Scene/SceneRegisterPolicy.swift'),
                    str(sdk / 'MeshLib/Scene/SceneExecuteData.swift'), str(assembled), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
