import Foundation

@main enum HDBDiagnosticsTests {
    static func node() -> Node {
        let e0 = Element(8, models: [Model(0x1000), Model(0x1300), Model(1, company: 0x0A78), Model(0x1100)])
        let e1 = Element(9, index: 1, models: [Model(0x1100)])
        let lc = Model(0x130F), setup = Model(0x1310), onoff = Model(0x1000)
        let e2 = Element(10, index: 2, models: [lc, setup, onoff, Model(0x1100)])
        let node = Node(8, elements: [e0, e1, e2])
        for model in [lc, setup, onoff] { model.relatedModels = [lc, setup, onoff].filter { $0 !== model } }
        for (index, element) in node.elements.enumerated() {
            for model in element.models {
                model.subscribe = model.modelIdentifier == 0x1100 ? [] : index == 2 ? ["C001", "FEFD"] : ["C001"]
                if model.modelIdentifier == 0x1100 { node.sensorModelTypes[model] = .init(id: [0x004D, 0x004E, 0x0072][index]) }
            }
        }
        e0.models.last!.publish = Publish(to: "000A", withKeyIndex: 1, friendshipCredentialsFlag: 0,
            ttl: 255, period: .disabled, retransmit: HDBDeviceSyncService.sensorPublicationRetransmit)
        return node
    }
    static func fixture() -> (HDBDeviceDiagnosticsService, Node, Node) {
        let active = MeshNetwork(), saved = MeshNetwork(), current = node(), stored = node()
        stored.uuid = current.uuid
        active.nodes = [current]; current.network = active
        saved.nodes = [stored]; stored.network = saved
        MeshNetwork.saved = saved; MeshNetworkManager.instance.meshNetwork = active
        SpaceData.persisted = SpaceData(); SpaceConfigurationSafety.blocked = false
        var device = HDBDeviceConfiguration(nodeUuid: current.uuid, nodeAddress: 8, mac: "AA:BB:CC:DD:EE:FF", lightingZones: [.init(zoneId: 1)])
        let targets = HDBConfigurationStore.modelTargets(node: current)
        device.zoneModels = HDBLightingZonePolicy.zoneTargets(from: targets, primaryAddress: 8).map(HDBModelReference.init)
        device.sensorGroupModels = HDBLightingZonePolicy.sensorGroupTargets(from: targets).map(HDBModelReference.init)
        device.broadcastModels = HDBConfigurationStore.broadcastTargets(node: current).map(HDBModelReference.init)
        device.sensorGroupId = 0xC080
        try! device.refreshSensorPublication()
        HDBConfigurationStore.config = .init(lightingZones: [.init(zoneId: 1, name: "One", groupAddress: 0xC001)], devices: [device])
        let service = HDBDeviceDiagnosticsService(site: SiteData(), space: SpaceData.persisted, nodeUuid: current.uuid)
        service.send = { request, address in
            precondition(address == 8 && (request as? ConfigModelReadbackMessage)?.updatesLocalState == false)
            return response(request, node: current)
        }
        return (service, current, stored)
    }
    static func response(_ request: AcknowledgedConfigMessage, node: Node) -> ConfigResponse {
        let target = request as! ConfigModelMessage
        let model = node.element(withAddress: target.elementAddress)!.model(withModelId: target.modelId)!
        let addresses = model.subscribe.compactMap { UInt16($0, radix: 16) }
        if let request = request as? ConfigSIGModelSubscriptionGet { return ConfigSIGModelSubscriptionList(responseTo: request, with: addresses.reversed()) }
        if let request = request as? ConfigVendorModelSubscriptionGet { return ConfigVendorModelSubscriptionList(responseTo: request, with: addresses) }
        return ConfigModelPublicationStatus(responseTo: request as! ConfigModelPublicationGet, with: model.publish)
    }
    static func main() throws {
        let (service, current, saved) = fixture()
        let initial = HDBConfigurationStore.config
        try service.read(HDBDiagnosticKind.allCases); pump { !service.isRunning }
        precondition(service.rows.count == 9)
        precondition(service.rows.allSatisfy { $0.subscriptions.state == .matches && $0.publication.state == .matches })
        let lc = service.rows.first { $0.snapshot.target.modelId == 0x130F }!
        precondition(lc.snapshot.expectedSubscriptions == [0xC001, 0xFEFD])
        precondition(lc.detail(.subscriptions).contains("hdb_diag_requirements_met"))
        precondition(service.rows.filter { $0.snapshot.target.modelId == 0x1100 }.allSatisfy { $0.snapshot.expectedSubscriptions == [] })
        precondition(service.rows.filter { $0.snapshot.expectedPublication != nil }.map { $0.snapshot.target.elementAddress } == [8])
        precondition(Node.saves == 0 && HDBConfigurationStore.config == initial)
        let report = try service.report()
        precondition(!report.contains("deviceKey") && !report.contains("qrvM") && report.contains("capturedAt"))
        precondition(HDBDiagnosticPolicy.received([0xC001, 0xC001], saved: [0xFFFF, 0xC001]).state == .matches)
        precondition(HDBDiagnosticPolicy.received([], saved: []).state == .matches)
        precondition(HDBDiagnosticPolicy.received([], saved: nil).state == .failed)
        var disabled = HDBDiagnosticPublication.disabled; disabled.ttl = 255
        precondition(disabled.differences(from: .disabled).isEmpty)
        let publication = service.rows.first { $0.snapshot.expectedPublication != nil }!.snapshot.expectedPublication!
        for index in 0..<8 {
            var changed = publication
            switch index {
            case 0: changed.address += 1
            case 1: changed.keyIndex += 1
            case 2: changed.credentials = 1
            case 3: changed.ttl = 5
            case 4: changed.periodSteps = 1
            case 5: changed.periodResolution = 1
            case 6: changed.retransmitCount = 1
            default: changed.retransmitInterval = 50
            }
            precondition(changed.differences(from: publication).count == 1)
        }
        // Both sides can agree on a broken HDB link.
        current.elements[2].models[0].subscribe = ["C001"]
        saved.elements[2].models[0].subscribe = ["C001"]
        try service.read([.subscriptions]); pump { !service.isRunning }
        let broken = service.rows.first { $0.snapshot.target.modelId == 0x130F }!
        precondition(broken.subscriptions.state == .matches && broken.detail(.subscriptions).contains("hdb_diag_requirements_missing"))
        // An extra Sensor subscription is legal for HDB Add, but is a saved-value difference.
        service.send = { request, _ in
            if let request = request as? ConfigSIGModelSubscriptionGet, request.modelIdentifier == 0x1100 {
                return ConfigSIGModelSubscriptionList(responseTo: request, with: [0xC080, 0xC099])
            }
            return response(request, node: current)
        }
        try service.read([.subscriptions]); pump { !service.isRunning }
        let sensor = service.rows.first { $0.snapshot.target.modelId == 0x1100 }!
        precondition(sensor.subscriptions.state == .different && sensor.detail(.subscriptions).contains("hdb_diag_requirements_met"))
        // Wrong-model response and errors stay incomplete; other rows still finish.
        var count = 0
        service.send = { request, _ in
            count += 1
            if count == 1 { return ConfigSIGModelSubscriptionList(parameters: Data([0, 8, 0, 1, 0x10]))! }
            if count == 2 { throw HDBConfigurationError.unavailable }
            if let r = request as? ConfigSIGModelSubscriptionGet, count == 3 { return ConfigSIGModelSubscriptionList(responseTo: r, with: .notASubscribeModel) }
            return response(request, node: current)
        }
        try service.read([.subscriptions]); pump { !service.isRunning }
        precondition(service.rows[0].subscriptions.state == .failed && service.rows[1].subscriptions.state == .failed)
        precondition(service.rows.contains { $0.subscriptions.state == .unsupported })
        count = 0; service.send = { request, _ in count += 1; return response(request, node: current) }
        try service.read([.subscriptions], retry: true); pump { !service.isRunning }
        precondition(count == 2)
        // Pending reads are cancelled, a late reply cannot overwrite the cancelled result.
        var continuation: CheckedContinuation<ConfigResponse, Error>?
        var pending: AcknowledgedConfigMessage?
        service.send = { request, _ in pending = request; return try await withCheckedThrowingContinuation { continuation = $0 } }
        try service.read([.publication]); pump { continuation != nil }
        service.cancel(); precondition(service.isRunning)
        continuation!.resume(returning: response(pending!, node: current)); continuation = nil
        pump { !service.isRunning }
        precondition(service.rows.allSatisfy { $0.publication.state == .cancelled })
        // Change baseline during a read: invalidate the complete snapshot, including earlier results.
        service.send = { request, _ in
            HDBConfigurationStore.version += 1
            return response(request, node: current)
        }
        try service.read([.subscriptions]); pump { !service.isRunning }
        precondition(service.rows.allSatisfy { $0.subscriptions.state == .changed })
        service.cancel(discard: true); precondition(service.rows.isEmpty)
        // An unknown Sensor does not hide readable models or pretend HDB chose a Presence publisher.
        let (unknown, unknownNode, _) = fixture()
        unknownNode.sensorModelTypes.removeValue(forKey: unknownNode.elements[1].models[0])
        try unknown.read([.publication]); pump { !unknown.isRunning }
        precondition(unknown.rows.filter { $0.snapshot.target.modelId == 0x1100 }.allSatisfy {
            $0.snapshot.expectedPublication == nil && $0.snapshot.publicationIssue == "hdb_diag_sensor_unknown"
        })
        unknownNode.elements[0].models.removeAll { $0.companyIdentifier != nil }
        try unknown.read([.subscriptions]); pump { !unknown.isRunning }
        precondition(unknown.warning == "hdb_diag_missing_models" && !unknown.rows.isEmpty)
        // Empty Zones retain only Sensor Group / FEFD on the protected receiver.
        let (empty, emptyNode, _) = fixture()
        HDBConfigurationStore.config.devices[0].lightingZones = []
        try empty.read([.subscriptions]); pump { !empty.isRunning }
        precondition(empty.rows.first { $0.snapshot.target.modelId == 0x130F }!.snapshot.expectedSubscriptions == [0xFEFD])
        // Multiple known Presence models are reported without hiding their raw publications.
        emptyNode.sensorModelTypes[emptyNode.elements[1].models[0]] = .init(id: 0x004D)
        try empty.read([.publication]); pump { !empty.isRunning }
        precondition(empty.rows.filter { $0.snapshot.target.modelId == 0x1100 }.allSatisfy { $0.snapshot.publicationIssue == "hdb_diag_sensor_ambiguous" })
        // Baselines retain unknown local group addresses and Label UUIDs without resolving Groups.
        let (raw, rawNode, rawSaved) = fixture()
        rawSaved.elements[0].models[0].subscribe += ["C077", "12345678-1234-1234-1234-123456789ABC"]
        try raw.read([.subscriptions]); pump { !raw.isRunning }
        let rawRow = raw.rows.first { $0.snapshot.target.elementAddress == 8 && $0.snapshot.target.modelId == 0x1000 }!
        precondition(rawRow.snapshot.savedSubscriptions == [0x8123, 0xC001, 0xC077] && rawRow.snapshot.savedLabels.count == 1)
        precondition(rawRow.subscriptions.state == .different)
        // A network identity change invalidates in-flight observations, and the report keeps the captured address.
        raw.send = { request, _ in
            let response = response(request, node: rawNode)
            rawNode.primaryUnicastAddress = 20
            return response
        }
        try raw.read([.publication]); pump { !raw.isRunning }
        precondition(raw.rows.allSatisfy { $0.publication.state == .changed })
        let captured = try JSONSerialization.jsonObject(with: Data(raw.report().utf8)) as! [String: Any]
        precondition(captured["nodeAddress"] as? Int == 8)
        // Queued cancellation cannot acquire or stop another owner's lane.
        let (queued, _, _) = fixture()
        let owner = SyncSessionCoordinator(); var ownerID: UUID?
        owner.start { ownerID = $0 }
        var sends = 0; queued.send = { _, _ in sends += 1; throw HDBConfigurationError.unavailable }
        try queued.read([.subscriptions]); precondition(queued.isRunning)
        queued.cancel(discard: true)
        precondition(!queued.isRunning && queued.rows.isEmpty && sends == 0 && owner.isRunning)
        owner.finish(ownerID!, settle: { $0() }, finished: {})
        // Configuration reads need DeviceKey, not an AppKey binding or completed preparation.
        let (noAppKey, noAppKeyNode, _) = fixture()
        MeshNetworkManager.instance.meshNetwork!.applicationKeys = []
        try noAppKey.read([.publication]); pump { !noAppKey.isRunning }
        precondition(noAppKey.rows.allSatisfy { $0.publication.state == .matches })
        precondition(noAppKey.rows.first { $0.snapshot.target.elementAddress == 8 && $0.snapshot.target.modelId == 0x1100 }!.snapshot.publicationIssue == "hdb_diag_expectation_unavailable")
        noAppKeyNode.deviceKey = nil
        do { try noAppKey.read([.subscriptions]); fatalError("missing DeviceKey accepted") } catch HDBConfigurationError.unavailable {}
        let (noSensor, noSensorNode, noSensorSaved) = fixture()
        for node in [noSensorNode, noSensorSaved] {
            node.elements.forEach { $0.models.removeAll { $0.modelIdentifier == 0x1100 } }
            node.sensorModelTypes = [:]
        }
        HDBConfigurationStore.config.devices[0].sensorGroupId = nil
        try! HDBConfigurationStore.config.devices[0].refreshSensorPublication()
        try noSensor.read([.subscriptions]); pump { !noSensor.isRunning }
        precondition(noSensor.rows.count == 6 && noSensor.rows.allSatisfy { $0.snapshot.target.modelId != 0x1100 })
        precondition(noSensor.rows.first { $0.snapshot.target.modelId == 0x130F }!.snapshot.expectedSubscriptions == [0xC001, 0xFEFD])
        // Excluded Vendor models do not require Zones; an unaffected temperature
        // receiver keeps its ordinary initialization FEFD even outside broadcastModels.
        let (extraModels, extraNode, extraSaved) = fixture()
        for node in [extraNode, extraSaved] {
            let element = node.elements[1]
            let vendor = Model(1, company: 0x0A78), temperature = Model(0x1306)
            vendor.parentElement = element; temperature.parentElement = element
            temperature.subscribe = ["FEFD"]
            element.models += [vendor, temperature]
        }
        try extraModels.read([.subscriptions]); pump { !extraModels.isRunning }
        let extraVendor = extraModels.rows.first { $0.snapshot.target.elementAddress == 9 && $0.snapshot.target.modelId == 0x0A780001 }!
        precondition(extraVendor.snapshot.expectedSubscriptions == [] && extraVendor.subscriptions.state == .matches)
        let unaffectedTemperature = extraModels.rows.first { $0.snapshot.target.modelId == 0x1306 }!
        precondition(unaffectedTemperature.snapshot.expectedSubscriptions == [0xFEFD] && unaffectedTemperature.subscriptions.state == .matches)
        precondition(!HDBConfigurationStore.config.devices[0].broadcastModels.contains { $0.modelId == 0x1306 })
        // Device-key/permission failures remain guards; preparation readiness was never required.
        let (denied, _, _) = fixture()
        SpaceData.persisted.canEditing = false
        do { try denied.read([.subscriptions]); fatalError("permission bypass") } catch HDBConfigurationError.unavailable {}
        precondition(Node.saves == 0)
        print("PASS: production diagnostic scope/snapshots, raw local subscriptions, HDB expectations, comparison, strict responses, partial failure/retry, cancellation/late response, revision/permission invalidation and secret-free reports; no radio/UI/cloud")
    }
    static func pump(_ done: () -> Bool) {
        let deadline = Date().addingTimeInterval(3)
        while !done() && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.001)) }
        precondition(done(), "async operation failed to settle")
    }
}
