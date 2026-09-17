import Foundation

@main
struct GatewayDeletionCoordinatorTests {
    @MainActor
    final class Fixture {
        var events: [String] = []
        var online = true
        var current = true
        var permitted = GatewayDeletionCoordinator.Permission.allowed
        var prepared = true
        var serverSucceeded = true
        var recordSucceeded = true
        var alreadyDeleted = false
        var bluetoothReady = true
        var resetSucceeded = true
        var localSucceeded = true
        var loseInternetAfterServer = false
        var switchAccountAfterServer = false
        var duringServer: (() async -> Void)?

        var steps: GatewayDeletionCoordinator.Steps {
            .init(isOnline: { self.online }, isCurrent: { self.current },
                  serverAlreadyDeleted: { self.alreadyDeleted },
                  permission: { self.events.append("permission"); return self.permitted },
                  prepare: { self.events.append("prepare"); return self.prepared },
                  deleteServer: {
                      self.events.append("server")
                      await self.duringServer?()
                      if self.loseInternetAfterServer { self.online = false }
                      if self.switchAccountAfterServer { self.current = false }
                      return self.serverSucceeded
                  },
                  recordServerDeletion: {
                      self.events.append("record")
                      self.alreadyDeleted = self.recordSucceeded
                      return self.recordSucceeded
                  },
                  canReset: { self.events.append("bluetooth"); return self.bluetoothReady },
                  reset: { self.events.append("reset"); return self.resetSucceeded },
                  finishLocal: { confirmed in self.events.append("local:\(confirmed)"); return self.localSucceeded },
                  cancelPreparation: { self.events.append("cancelPreparation") })
        }
    }

    @MainActor
    static func main() async throws {
        // No Space or association is needed to authorize Reset or local completion.
        let connected = Fixture()
        let connectedResult = await GatewayDeletionCoordinator().delete(using: connected.steps)
        require(connectedResult == .deleted(resetConfirmed: true), "connected Gateway completes")
        require(connected.events == ["permission", "prepare", "server", "record", "bluetooth", "reset", "local:true"],
                "server confirmation and persistence precede Reset and local cleanup")

        for pending in [false, true] {
            let f = Fixture(); f.online = false; f.alreadyDeleted = pending
            let result = await GatewayDeletionCoordinator().delete(using: f.steps)
            require(result == .failed(.offline) && f.events.isEmpty, "offline user action never mutates even a legacy pending Gateway")
        }
        let denied = Fixture(); denied.permitted = .denied
        let deniedResult = await GatewayDeletionCoordinator().delete(using: denied.steps)
        require(deniedResult == .failed(.permission) && denied.events == ["permission"], "Editor permission denied before Reset")
        let unknownPermission = Fixture(); unknownPermission.permitted = .unavailable
        let unknownResult = await GatewayDeletionCoordinator().delete(using: unknownPermission.steps)
        require(unknownResult == .failed(.server) && unknownPermission.events == ["permission"], "unverified Editor permission stops deletion")

        let serverFailure = Fixture(); serverFailure.serverSucceeded = false
        let serverResult = await GatewayDeletionCoordinator().delete(using: serverFailure.steps)
        require(serverResult == .failed(.server) && serverFailure.events == ["permission", "prepare", "server", "cancelPreparation"],
                "API failure or timeout keeps Node and gateway local data")

        let unprepared = Fixture(); unprepared.prepared = false
        let unpreparedResult = await GatewayDeletionCoordinator().delete(using: unprepared.steps)
        require(unpreparedResult == .failed(.local) && unprepared.events == ["permission", "prepare"], "local preflight failure has no remote effects")
        let failedReceipt = Fixture(); failedReceipt.recordSucceeded = false
        let receiptResult = await GatewayDeletionCoordinator().delete(using: failedReceipt.steps)
        require(receiptResult == .failed(.local) && !failedReceipt.events.contains("reset"), "unpersisted server receipt does not start Reset")

        let offlineGateway = Fixture(); offlineGateway.bluetoothReady = false
        let offlineResult = await GatewayDeletionCoordinator().delete(using: offlineGateway.steps)
        require(offlineResult == .deleted(resetConfirmed: false) && !offlineGateway.events.contains("reset")
            && offlineGateway.events.last == "local:false", "offline Gateway completes with manual-reset feedback")
        let lostReceipt = Fixture(); lostReceipt.resetSucceeded = false
        let lostResult = await GatewayDeletionCoordinator().delete(using: lostReceipt.steps)
        require(lostResult == .deleted(resetConfirmed: false) && lostReceipt.events.last == "local:false", "Reset timeout completes without a force-delete choice")
        let lostInternet = Fixture(); lostInternet.loseInternetAfterServer = true
        let lostInternetResult = await GatewayDeletionCoordinator().delete(using: lostInternet.steps)
        require(lostInternetResult == .deleted(resetConfirmed: true), "internet loss after server confirmation does not stop Bluetooth/local completion")

        let switched = Fixture(); switched.switchAccountAfterServer = true
        let switchedResult = await GatewayDeletionCoordinator().delete(using: switched.steps)
        require(switchedResult == .failed(.changedContext) && !switched.events.contains("record") && !switched.events.contains("reset"),
                "old callback cannot mutate another account")
        let pending = Fixture(); pending.alreadyDeleted = true
        let pendingResult = await GatewayDeletionCoordinator().delete(using: pending.steps)
        require(pendingResult == .deleted(resetConfirmed: true) && pending.events == ["prepare", "bluetooth", "reset", "local:true"],
                "known server deletion resumes without querying a deleted Gateway")
        let diskFailure = Fixture(); diskFailure.localSucceeded = false
        let diskResult = await GatewayDeletionCoordinator().delete(using: diskFailure.steps)
        require(diskResult == .failed(.local), "local persistence failure never reports deletion completed")

        let duplicate = Fixture(); let coordinator = GatewayDeletionCoordinator()
        duplicate.duringServer = {
            let result = await coordinator.delete(using: duplicate.steps)
            require(result == .failed(.busy), "double tap cannot issue a second server delete or Reset")
        }
        _ = await coordinator.delete(using: duplicate.steps)
        require(duplicate.events.filter { $0 == "server" }.count == 1, "only one server request")

        try testReceipts()
        print("GatewayDeletionCoordinatorTests passed")
    }

    static func testReceipts() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = GatewayDeletionReceiptStore(url: root.appendingPathComponent("gateway.json"))
        var receipt = GatewayDeletionReceipt(siteId: "site", meshUUID: "mesh", networkId: "primary", mac: "AABB",
            nodeUUID: "old-node", address: 3, elementAddresses: [3, 4], productId: 0x2721, createdTimestamp: 100, phase: .prepared)
        require(try store.read() == nil, "no journal required for a new Site")
        try store.write(receipt)
        require(try GatewayDeletionReceiptStore(url: store.url).read() == receipt, "operation survives process recreation")
        require(receipt.blocksImport(nodeUUID: "old-node", address: 3, createdTimestamp: nil), "pending delete protects Reset target")
        try store.cancelPreparation()
        require(try store.read() == nil, "server failure can release only its preparation")
        receipt.phase = .serverDeleted
        try store.write(receipt)
        try store.cancelPreparation()
        require(try store.read()?.phase == .serverDeleted, "server deletion receipt cannot be cancelled")
        receipt.phase = .completed
        try store.write(receipt)
        require(receipt.blocksImport(nodeUUID: "OLD-NODE", address: 3, createdTimestamp: nil), "late old cloud response cannot resurrect the deleted Gateway")
        require(!receipt.blocksImport(nodeUUID: "old-node", address: 7, createdTimestamp: 101), "same physical UUID at a new address can be provisioned again")
        require(!receipt.blocksImport(nodeUUID: "old-node", address: 3, createdTimestamp: 101), "new provisioning generation is not the old deleted instance")
        let otherStore = GatewayDeletionReceiptStore(url: root.appendingPathComponent("other-account/gateway.json"))
        require(try otherStore.read() == nil, "storage scopes do not share receipts")
        try Data("corrupted".utf8).write(to: store.url)
        do { _ = try store.read(); fatalError("corrupted receipt must not silently authorize import") }
        catch is DecodingError {}
    }

    static func require(_ value: Bool, _ message: String) {
        if !value { fatalError(message) }
    }
}
