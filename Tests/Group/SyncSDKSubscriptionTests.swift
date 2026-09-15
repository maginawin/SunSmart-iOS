import Foundation
import NordicSigMeshSDK

/// Exercises the linked SDK's string-backed subscriptions. No account, keys,
/// persistence, Mesh manager initialization or Bluetooth commands are involved.
enum SyncSDKSubscriptionTests {
    static func installRefreshLookup() {
        Model.makeSubscriptionLookup = { addresses in
            let data = try! JSONSerialization.data(withJSONObject: ["modelId": "1000", "subscribe": addresses.map { String(format: "%04X", $0) }, "bind": []])
            let model = try! JSONDecoder().decode(NordicSigMeshSDK.Model.self, from: data)
            return { model.isSubscribed(to: NordicSigMeshSDK.MeshAddress($0)) }
        }
    }
    static func run() throws -> String {
        let addresses = ["C001", "C032", "FFFF", "00000000000000000000000000000001"]
        let data = try JSONSerialization.data(withJSONObject: [
            "modelId": "1000", "subscribe": addresses, "bind": []
        ])
        let models = try (0..<10_000).map { _ in try JSONDecoder().decode(NordicSigMeshSDK.Model.self, from: data) }
        for model in models {
            for value in addresses {
                precondition(model.isSubscribed(to: NordicSigMeshSDK.MeshAddress(hex: value)!))
            }
            precondition(!model.isSubscribed(to: NordicSigMeshSDK.MeshAddress(hex: "C002")!))
        }
        return "SDK PASS: 10000 real Models, ordinary/virtual/special string subscriptions"
    }
}
