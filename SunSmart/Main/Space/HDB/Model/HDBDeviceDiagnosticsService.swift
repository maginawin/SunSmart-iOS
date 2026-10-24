import Foundation
import NordicSigMeshSDK

/// Read-only observations. No Store mutation, Sync task, Group allocation, or Node save.
final class HDBDeviceDiagnosticsService {
    private let site: SiteData
    private let space: SpaceData
    private let nodeUuid: UUID
    private let account = UserData.currentUserId
    private let region = String(describing: UserData.currentServerRegion)
    private let coordinator = SyncSessionCoordinator()
    private var task: Task<Void, Never>?
    private var context: HDBDeviceSyncContext?
    private var configuration: HDBConfiguration?
    private var revision: Int64?
    private var composition: [HDBModelTarget] = []
    private var liveModels: [Data] = []
    private var capturedAddress: UInt16?
    private var discardOnStop = false
    private(set) var rows: [HDBDiagnosticRow] = []
    private(set) var kinds: [HDBDiagnosticKind] = []
    private(set) var startedAt: Date?
    private(set) var isRunning = false
    private(set) var warning: String?
    var didChange: (() -> Void)?
    var didFinish: ((Error?) -> Void)?
    var send: (AcknowledgedConfigMessage, UInt16) async throws -> ConfigResponse = {
        try await MeshNetworkManager.instance.send($0, to: $1)
    }

    init(site: SiteData, space: SpaceData, nodeUuid: UUID) {
        self.site = site; self.space = space; self.nodeUuid = nodeUuid
    }

    var summary: String {
        let results = rows.flatMap { row in kinds.map { row[$0] } }
        return String(format: "hdb_diag_summary".localizedString,
                      results.filter { $0.state == .matches }.count,
                      results.filter { $0.state == .different }.count,
                      results.filter { $0.state == .unsupported }.count,
                      results.filter { ![.matches, .different, .unsupported].contains($0.state) }.count)
    }
    var canRetry: Bool {
        !isRunning && rows.contains { row in kinds.contains { ![.matches, .different, .unsupported].contains(row[$0].state) } }
    }

    func refreshValidity() {
        guard !isRunning, !rows.isEmpty, !isCurrent() else { return }
        for index in rows.indices { for kind in kinds { rows[index][kind].state = .changed } }
    }

    func read(_ requested: [HDBDiagnosticKind], retry: Bool = false) throws {
        precondition(Thread.isMainThread)
        guard !isRunning, !MeshProxyMessageCommand.shared.isBusy else { throw HDBConfigurationError.busy }
        guard MeshLibManager.manager.isMeshNetworkConnected else { throw HDBZoneControlError.disconnected }
        let reuse = retry && isCurrent()
        if !reuse { try capture(); startedAt = Date() }
        kinds = requested
        guard !rows.isEmpty else { throw HDBConfigurationError.unsupportedModels }
        var work: [(Int, HDBDiagnosticKind)] = []
        for index in rows.indices {
            for kind in requested where !reuse || ![.matches, .different, .unsupported].contains(rows[index][kind].state) {
                rows[index][kind] = HDBDiagnosticResult()
                work.append((index, kind))
            }
        }
        guard !work.isEmpty else { return }
        discardOnStop = false; isRunning = true; didChange?()
        coordinator.start { [weak self] identifier in
            guard let self else { return }
            self.task = Task { @MainActor [self] in
                var failure: Error?
                do {
                    for (index, kind) in work {
                        try Task.checkCancellation()
                        guard self.isCurrent(), let context = self.context else { throw HDBDiagnosticError.snapshotChanged }
                        guard MeshLibManager.manager.isMeshNetworkConnected else { throw HDBZoneControlError.disconnected }
                        self.rows[index][kind].state = .reading; self.didChange?()
                        do {
                            let request = try Self.request(kind, target: self.rows[index].snapshot.target)
                            let response = try await self.send(request, context.node.primaryUnicastAddress)
                            try Task.checkCancellation()
                            guard self.isCurrent() else { throw HDBDiagnosticError.snapshotChanged }
                            self.rows[index][kind] = try Self.result(response, kind: kind, snapshot: self.rows[index].snapshot)
                        } catch {
                            try Task.checkCancellation()
                            guard self.isCurrent() else { throw HDBDiagnosticError.snapshotChanged }
                            self.rows[index][kind] = .init(state: .failed,
                                errorKey: error is HDBDiagnosticError ? "hdb_diag_response_mismatch" : "hdb_diag_read_failed", readAt: Date())
                        }
                        self.didChange?()
                    }
                    guard self.isCurrent() else { throw HDBDiagnosticError.snapshotChanged }
                } catch {
                    failure = error
                    for index in self.rows.indices {
                        for kind in self.kinds {
                            if error is HDBDiagnosticError {
                                self.rows[index][kind].state = .changed
                            } else if !self.rows[index][kind].state.completed {
                                self.rows[index][kind].state = error is CancellationError ? .cancelled : .failed
                                self.rows[index][kind].errorKey = error is CancellationError ? nil : "hdb_diag_read_failed"
                            }
                        }
                    }
                }
                self.task = nil
                self.coordinator.finish(identifier, settle: { $0() }) { [self] in
                    self.isRunning = false; self.didChange?(); self.didFinish?(failure)
                }
            }
        }
    }

    func cancel(discard: Bool = false) {
        precondition(Thread.isMainThread)
        discardOnStop = discard
        guard isRunning else { if discard { clear() }; return }
        let active = coordinator.isRunning
        coordinator.stop { [self] done in
            guard let task else { stopped(); done(); return }
            task.cancel()
            Task { @MainActor in
                await task.value
                stopped(); done()
            }
        }
        if !active && !coordinator.isSettling {
            for index in rows.indices { for kind in kinds where !rows[index][kind].state.completed { rows[index][kind].state = .cancelled } }
            stopped()
        }
    }
    private func stopped() {
        isRunning = false
        if discardOnStop { clear() }
        didChange?()
    }
    private func clear() {
        rows = []; kinds = []; startedAt = nil; warning = nil; context = nil; capturedAddress = nil
    }

    private func capture() throws {
        guard account == UserData.currentUserId, region == String(describing: UserData.currentServerRegion), site.id == space.siteId,
              let network = MeshNetworkManager.instance.meshNetwork,
              let node = network.nodes.first(where: { $0.uuid == nodeUuid }), node.deviceKey != nil,
              let context = try HDBDeviceSyncContext.resolve(space: space, node: node), context.isCurrent() else {
            throw HDBConfigurationError.unavailable
        }
        let config = try HDBConfigurationStore.load(space: space)
        let persisted = try savedNode(context)
        let snapshots = try makeSnapshots(context, config: config, saved: persisted)
        self.context = context; configuration = config
        capturedAddress = node.primaryUnicastAddress
        revision = try HDBConfigurationStore.revision(space: space)
        composition = context.targets; liveModels = try fingerprint(node)
        rows = snapshots.map { HDBDiagnosticRow(snapshot: $0) }
        warning = (try? HDBLightingZonePolicy.requiredZoneTargets(from: context.targets, primaryAddress: context.node.primaryUnicastAddress)) == nil ? "hdb_diag_missing_models" : nil
    }

    private func savedNode(_ context: HDBDeviceSyncContext) throws -> Node {
        guard let network = MeshNetwork.load(meshUUID: space.meshUUID, subnetworkId: space.meshNetworkId),
              let saved = network.nodes.first(where: { $0.uuid == nodeUuid }),
              saved.primaryUnicastAddress == context.node.primaryUnicastAddress,
              saved.deviceKey == context.node.deviceKey, saved.subNetworkId == space.meshNetworkId else {
            throw HDBConfigurationError.unavailable
        }
        return saved
    }

    private func isCurrent() -> Bool {
        guard account == UserData.currentUserId, region == String(describing: UserData.currentServerRegion),
              let context, context.isCurrent(), context.node.deviceKey != nil,
              context.targets == composition, let config = try? HDBConfigurationStore.load(space: space), config == configuration,
              (try? HDBConfigurationStore.revision(space: space)) == revision,
              (try? fingerprint(context.node)) == liveModels,
              let saved = try? savedNode(context),
              let current = try? makeSnapshots(context, config: config, saved: saved) else { return false }
        return current == rows.map(\.snapshot)
    }

    private func fingerprint(_ node: Node) throws -> [Data] {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try node.elements.flatMap(\.models).map { try encoder.encode($0) }
    }

    private func makeSnapshots(_ context: HDBDeviceSyncContext, config: HDBConfiguration, saved: Node) throws -> [HDBDiagnosticModelSnapshot] {
        let device = config.devices.first { $0.nodeUuid == nodeUuid && $0.nodeAddress == context.node.primaryUnicastAddress }
        let zoneTargets = Set(HDBLightingZonePolicy.zoneTargets(from: context.targets, primaryAddress: context.node.primaryUnicastAddress))
        let sensorTargets = Set(HDBLightingZonePolicy.sensorGroupTargets(from: context.targets))
        let broadcastTargets = Set(HDBConfigurationStore.broadcastTargets(node: context.node))
        let targetsValid = device.map {
            Set($0.zoneModels.map(\.target)) == zoneTargets && Set($0.sensorGroupModels.map(\.target)) == sensorTargets
                && Set($0.broadcastModels.map(\.target)) == broadcastTargets && $0.broadcastId == 0xFEFD
        } ?? false
        let publicationTargets = try? context.publicationTargets
        let publicationValid = device.map { device in
            guard let publicationTargets else { return false }
            return (try? device.validateSensorPublication(models: context.targets, publicationTargets: publicationTargets)) != nil
        } ?? false
        let sensorModels = context.node.elements.flatMap(\.models).filter { $0.companyIdentifier == nil && $0.modelIdentifier == 0x1100 }
        let propertiesKnown = sensorModels.allSatisfy { (context.node.sensorModelTypes[$0]?.id ?? 0) != 0 }
        let zones = device?.lightingZones.compactMap { member in config.lightingZones.first { $0.zoneId == member.zoneId }?.groupAddress }
        var result: [HDBDiagnosticModelSnapshot] = []
        for element in context.node.elements {
            for model in element.models {
                let target = HDBModelTarget(elementAddress: element.unicastAddress, modelIdentifier: model.modelIdentifier, companyIdentifier: model.companyIdentifier)
                guard HDBDiagnosticPolicy.includes(target) else { continue }
                let stored = saved.elements.first { $0.unicastAddress == target.elementAddress }?.models.first {
                    $0.modelIdentifier == target.modelIdentifier && $0.companyIdentifier == target.companyIdentifier
                }
                struct Stored: Decodable { let subscribe: [String] }
                let raw = try stored.map { try JSONDecoder().decode(Stored.self, from: JSONEncoder().encode($0)).subscribe }
                let addresses = raw?.compactMap { MeshAddress(hex: $0)?.address }
                let baselineValid = raw != nil && raw?.count == addresses?.count
                var expected: [UInt16]?
                var subIssue: String?
                if target.modelId == 0x1100 {
                    expected = []
                } else if let zones, zones.count == device?.lightingZones.count, targetsValid {
                    let shared = Set(([model] + model.relatedModels.filter { $0.parentElement === element }).map {
                        HDBModelTarget(elementAddress: element.unicastAddress, modelIdentifier: $0.modelIdentifier, companyIdentifier: $0.companyIdentifier)
                    })
                    expected = shared.isDisjoint(with: zoneTargets) ? [] : zones
                    // Ordinary initialization also owns FEFD on unaffected receivers.
                    let initializedBroadcast = element.unicastAddress != context.node.primaryUnicastAddress
                        && shared.contains { [0x1306, 0x130F].contains($0.modelId) }
                    if initializedBroadcast || !shared.isDisjoint(with: broadcastTargets) { expected?.append(0xFEFD) }
                }
                if expected == nil { subIssue = "hdb_diag_expectation_unavailable" }
                var expectedPublish: HDBDiagnosticPublication?
                var pubIssue: String? = "hdb_diag_unmanaged_publication"
                if target.modelId == 0x1100 {
                    if !propertiesKnown { pubIssue = "hdb_diag_sensor_unknown" }
                    else if publicationTargets == nil { pubIssue = "hdb_diag_sensor_ambiguous" }
                    else if publicationTargets?.contains(target) == true {
                        if publicationValid, let address = device?.sensorPublication.first(where: { $0.target == target })?.publishAddress, let key = context.key {
                            expectedPublish = Self.publication(Publish(to: MeshAddress(address), using: key,
                                usingFriendshipMaterial: false, ttl: SensorPublicationPolicy.ttl, period: .disabled,
                                retransmit: HDBDeviceSyncService.sensorPublicationRetransmit))
                            pubIssue = nil
                        } else if publicationValid && device?.sensorPublication.first(where: { $0.target == target })?.publishAddress == nil { pubIssue = "hdb_diag_unmanaged_publication" }
                        else { pubIssue = "hdb_diag_expectation_unavailable" }
                    }
                }
                result.append(.init(target: target, elementIndex: Int(element.index), sensorProperty: context.node.sensorModelTypes[model]?.id,
                    savedSubscriptions: baselineValid ? addresses.map(HDBDiagnosticPolicy.normalized) : nil,
                    savedPublication: Self.publication(stored?.publish), savedLabels: raw?.filter { $0.count > 4 } ?? [],
                    baselineIssue: baselineValid ? nil : "hdb_diag_no_baseline",
                    expectedSubscriptions: expected.map(HDBDiagnosticPolicy.normalized), exactSubscriptions: target.modelId != 0x1100,
                    subscriptionIssue: subIssue, expectedPublication: expectedPublish, publicationIssue: pubIssue))
            }
        }
        return result.sorted {
            $0.target.elementAddress == $1.target.elementAddress ? $0.target.modelId < $1.target.modelId : $0.target.elementAddress < $1.target.elementAddress
        }
    }

    static func publication(_ publish: Publish?) -> HDBDiagnosticPublication {
        guard let publish else { return .disabled }
        return .init(address: publish.publicationAddress.address, keyIndex: publish.index, credentials: publish.isUsingFriendshipSecurityMaterial ? 1 : 0,
                     ttl: publish.ttl, periodSteps: publish.period.numberOfSteps, periodResolution: publish.period.resolution.rawValue,
                     retransmitCount: publish.retransmit.count, retransmitInterval: publish.retransmit.interval)
    }

    static func request(_ kind: HDBDiagnosticKind, target: HDBModelTarget) throws -> AcknowledgedConfigMessage {
        var data = Data()
        for value in [target.elementAddress] + (target.companyIdentifier.map { [$0] } ?? []) + [target.modelIdentifier] {
            data.append(UInt8(value & 255)); data.append(UInt8(value >> 8))
        }
        if kind == .publication, var message = ConfigModelPublicationGet(parameters: data) {
            message.updatesLocalState = false; return message
        }
        if target.companyIdentifier != nil, var message = ConfigVendorModelSubscriptionGet(parameters: data) {
            message.updatesLocalState = false; return message
        }
        if target.companyIdentifier == nil, var message = ConfigSIGModelSubscriptionGet(parameters: data) {
            message.updatesLocalState = false; return message
        }
        throw HDBDiagnosticError.responseMismatch
    }

    static func result(_ response: ConfigResponse, kind: HDBDiagnosticKind, snapshot: HDBDiagnosticModelSnapshot) throws -> HDBDiagnosticResult {
        guard let model = response as? ConfigModelMessage, let status = response as? ConfigStatusMessage,
              model.elementAddress == snapshot.target.elementAddress, model.modelId == snapshot.target.modelId else {
            throw HDBDiagnosticError.responseMismatch
        }
        if kind == .subscriptions {
            guard (snapshot.target.companyIdentifier == nil && response is ConfigSIGModelSubscriptionList)
                || (snapshot.target.companyIdentifier != nil && response is ConfigVendorModelSubscriptionList),
                  let list = response as? ConfigModelSubscriptionList else { throw HDBDiagnosticError.responseMismatch }
            guard status.isSuccess else { return HDBDiagnosticPolicy.rejected(status.status.rawValue) }
            return HDBDiagnosticPolicy.received(list.addresses, saved: snapshot.savedSubscriptions)
        }
        guard let status = response as? ConfigModelPublicationStatus else { throw HDBDiagnosticError.responseMismatch }
        guard status.isSuccess else { return HDBDiagnosticPolicy.rejected(status.status.rawValue) }
        guard snapshot.baselineIssue == nil else {
            return .init(state: .failed, publication: publication(status.publish), errorKey: "hdb_diag_no_baseline", readAt: Date())
        }
        return HDBDiagnosticPolicy.received(publication(status.publish), saved: snapshot.savedPublication)
    }

    func report() throws -> String {
        struct Report: Encodable {
            let capturedAt: Date?
            let nodeUUID: UUID
            let nodeAddress: UInt16?
            let appVersion: String
            let sdkVersion: String
            let sdkReadbackAPI: String
            let sensorGroupID: UInt16?
            let lightingZones: [HDBLightingZone]
            let scope: [HDBDiagnosticKind]
            let warning: String?
            let rows: [HDBDiagnosticRow]
        }
        let bundle = Bundle.main
        let sdkBundle = Bundle(for: MeshNetworkManager.self)
        let device = configuration?.devices.first { $0.nodeUuid == nodeUuid }
        let selectedZones = Set(device?.lightingZones.map(\.zoneId) ?? [])
        let report = Report(capturedAt: startedAt, nodeUUID: nodeUuid, nodeAddress: capturedAddress,
            appVersion: "\(bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") ?? "?") (\(bundle.object(forInfoDictionaryKey: "CFBundleVersion") ?? "?"))",
            sdkVersion: sdkBundle == bundle ? "not separately versioned" : String(describing: sdkBundle.object(forInfoDictionaryKey: "CFBundleVersion") ?? "unknown"),
            sdkReadbackAPI: "ConfigModelReadbackMessage/1", sensorGroupID: device?.sensorGroupId,
            lightingZones: configuration?.lightingZones.filter { selectedZones.contains($0.zoneId) } ?? [],
            scope: kinds, warning: warning, rows: rows)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        return String(decoding: try encoder.encode(report), as: UTF8.self)
    }
}

enum HDBDiagnosticError: Error { case snapshotChanged, responseMismatch }
