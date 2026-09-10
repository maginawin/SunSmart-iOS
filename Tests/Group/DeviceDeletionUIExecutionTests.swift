import Foundation

// Only presentation and BLE boundaries are doubled. The shared production UI
// flow and deletion context execute together with the journal/store fixtures.
let TextBlack_Color = "text", Message_Color = "note"
extension NSAttributedString.Key { static let foregroundColor = Self("color") }
final class SRAlertAction {
    enum Style { case cancel, destructive }
    let title: String
    let actionHandler: (SRAlertAction) -> Void
    init(title: String, style: Style, actionHandler: @escaping (SRAlertAction) -> Void) {
        self.title = title; self.actionHandler = actionHandler
    }
}
final class SRAlertView {
    final class Label { var attributedText: NSAttributedString? }
    let messageLabel = Label()
    let actions: [SRAlertAction]
    static var onShow: (([SRAlertAction]) -> Void)?
    init(title: String, actions: [SRAlertAction]) { self.actions = actions }
    func show() { Self.onShow?(actions) }
}
enum MeshAPI {
    static var calls = 0
    static var successAddresses = Set<Address>()
    static func resetNodes(addressDataList: [(address: Address, timeout: TimeInterval)],
                           resetSuccess: ((Address) -> Void)?, resetFail: ((Address) -> Void)?,
                           resetFinish: ([Address], [Address]) -> Void) {
        calls += 1
        let successes = addressDataList.map(\.address).filter { successAddresses.contains($0) }
        if let network = MeshNetworkManager.instance.meshNetwork {
            network.nodes.filter { successes.contains($0.primaryUnicastAddress) }.forEach { network.remove(node: $0) }
        }
        resetFinish(successes, addressDataList.map(\.address).filter { !successAddresses.contains($0) })
    }
}
extension ScopedImportTests {
    @MainActor static func testDeviceDeletionUI() async throws {
        let controller = DeviceDeletionUIHarness()
        let offline = try fixture(networkId: "UI-KEYLESS")
        activate(offline)
        SpaceMeshKeyStore.missing = true
        MeshAPI.calls = 0
        var confirmations = 0
        SRAlertView.onShow = { actions in
            confirmations += 1
            let force = actions.first { $0.title == "force_delete" }!
            force.actionHandler(force)
        }
        let forced: ([Node], [Node]) = await withCheckedContinuation { continuation in
            controller.deleteNodes(nodes: offline.nodes, space: offline.space) {
                continuation.resume(returning: ($0, $1))
            }
        }
        require(MeshAPI.calls == 0 && confirmations == 1, "missing-key deletion directly offers Force Delete without sending Reset")
        require(forced.0.count == 2 && forced.1.isEmpty && offline.network.nodes.isEmpty,
                "Force Delete completion follows persisted removal of the selected nodes")

        let partial = try fixture(networkId: "UI-PARTIAL")
        activate(partial)
        SpaceMeshKeyStore.missing = false
        MeshAPI.successAddresses = [partial.nodes[0].primaryUnicastAddress]
        SRAlertView.onShow = { actions in actions[0].actionHandler(actions[0]) }
        let cancelled: ([Node], [Node]) = await withCheckedContinuation { continuation in
            controller.deleteNodes(nodes: partial.nodes, space: partial.space) {
                continuation.resume(returning: ($0, $1))
            }
        }
        require(cancelled.0.count == 1 && cancelled.1.count == 1 && partial.network.nodes.count == 1,
                "cancelling Force Delete retains failed nodes and reports only persisted successes")
        require(!SpaceConfigurationSafety.hasPendingDeletionCleanup(partial.space),
                "cancelled Reset intent does not block later sync")

        let changed = try fixture(networkId: "UI-STALE")
        activate(changed)
        SpaceMeshKeyStore.missing = true
        SRAlertView.onShow = { actions in
            changed.nodes[0].createdTimestamp += 1
            actions[1].actionHandler(actions[1])
        }
        let failed: ([Node], [Node]) = await withCheckedContinuation { continuation in
            controller.deleteNodes(nodes: [changed.nodes[0]], space: changed.space) {
                continuation.resume(returning: ($0, $1))
            }
        }
        require(failed.0.isEmpty && failed.1.count == 1 && changed.network.nodes.count == 2,
                "failed forced removal must stay selected instead of reporting all nodes deleted")
        SRAlertView.onShow = nil
        SpaceMeshKeyStore.missing = false
        print("PASS: production shared deletion UI flow, keyless Force confirmation, partial Reset cancellation and persisted per-device outcomes")
    }
}
