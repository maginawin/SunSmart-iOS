final class FlowLiveNode { var state: Bool; init(_ state: Bool) { self.state = state } }
typealias AsyncTask = _Concurrency.Task
// Executed with the real recovery implementation and its disk/codec fixture.
final class UploadFlowHarness {
    let operation: SyncOperation
    var configurationUploadTask: Task<Void, Never>?
    var state = FlowState.wait
    var handleCallback: ((UploadFlowHarness, FlowState) -> Void)?
    var isCurrentDeviceAddContext: Bool { true }
    var configurationSpaces: [SpaceData] {
        switch operation {
        case .syncSpace(let space): return [space]
        case .syncSite(_, let spaces), .addSpaces(_, let spaces): return spaces
        case .syncGateway: return []
        }
    }
    init(_ operation: SyncOperation) { self.operation = operation }
    func finishInvalidatedConfiguration(lifecycle: [String: SpaceRecoveryState]? = nil) { state = .cancel }
    func finishConfigurationFailure(_ error: NetworkApiError) {
        state = .failure(error: error)
        for space in configurationSpaces { space.syncCloudError = error; _ = space.save() }
    }
    func finishExportFailure() { finishConfigurationFailure(.configurationExportInvalid) }
    // CONFIRM_SITE
    @MainActor func start() {
        // CONFIGURATION_TASK
    }
}
enum FlowState { case wait, successful, failure(error: NetworkApiError), cancel }
final class FlowGateway {
    var syncCloudError: NetworkApiError?
    func save() {}
}
enum SiteExtensionStore {
    struct State { var pending: Int? }
    static func load(_ site: SiteData) throws -> State { .init() }
}
extension SyncOperation {
    @MainActor func getNetworkApi() async -> NetowrkReqeustApi? {
        switch self {
        case .syncSpace(let space):
            guard let payload = await space.export(purpose: .cloudSync) else { return nil }
            return .spaceUpload(siteId: space.siteId, spaceId: space.id, spaceData: payload)
        case .syncSite(_, let spaces), .addSpaces(_, let spaces):
            var payloads: [[String: Any]] = []
            for space in spaces {
                guard let payload = await space.export(purpose: .cloudSync) else { return nil }
                payloads.append(payload)
            }
            return .siteUpload(siteData: ["updateTimestamp": Int64(100), "spaces": payloads])
        case .syncGateway: return nil
        }
    }
}
extension SiteData {
    var uploadCloud: Bool { lastUploadCloudTimestamp != nil }
    var needUploadCloud: Bool { lastUpdate > (lastUploadCloudTimestamp ?? 0) }
}
extension NetworkRequest {
    func request(_ api: NetowrkReqeustApi) async -> Result<[String: Any], NetworkApiError> {
        switch api {
        case .spaceUpload(let site, let id, let payload):
            return await request(API.spaceUpload(siteId: site, spaceId: id, spaceData: payload))
        case .siteUpload(let payload), .siteAdd(let payload, _):
            return await request(API.spaceUpload(siteId: "site", spaceId: "batch", spaceData: payload))
        }
    }
}
@main struct SpaceUploadFlowTests {
    @MainActor static func main() async throws {
        typealias S = SpaceConfigurationSafety
        defer { try? FileManager.default.removeItem(at: S.testRoot); S.testDefaults.removePersistentDomain(forName: S.suite) }
        let request = NetworkRequest.shared
        for mode in ["success", "business", "http", "timeout", "newEdit", "account", "localSave"] {
            let space = SpaceData("flow-" + mode)
            let liveNodes = space.liveNodes
            let writes = request.uploads, calls = request.calls
            request.result = ["business", "http", "timeout"].contains(mode)
                ? .failure(mode == "timeout" ? .requestTimeout : mode == "business" ? .editorBeingUsedSpace : .serverNotRespond) : .success([:])
            request.onRequest = {
                if mode == "newEdit" { space.lastUpdate = 51 }
                if mode == "account" { UserData.currentUserId = "other" }
                if mode == "localSave" { space.savesSucceed = false }
            }
            let flow = UploadFlowHarness(.syncSpace(space: space)); flow.start()
            await flow.configurationUploadTask?.value
            precondition(request.uploads == writes + 1 && request.calls == calls + 1, "ordinary upload must have 1 write and 0 reads")
            precondition(space.restoreCalls == 0)
            precondition(zip(liveNodes, space.liveNodes).allSatisfy { $0 === $1 })
            precondition(space.liveNodes.map(\.state) == [true, true, false], "upload must not replace or rewrite presence")
            if ["success", "newEdit"].contains(mode) {
                guard case .successful = flow.state else { preconditionFailure(mode) }
                precondition(space.lastUploadCloudTimestamp == 50 && space.needUploadCloud == (mode == "newEdit"))
            } else {
                precondition(space.lastUploadCloudTimestamp == nil && space.needUploadCloud)
                if mode != "account" { guard case .failure = flow.state else { preconditionFailure(mode) } }
            }
            UserData.currentUserId = "test-account"
        }
        let legacy = SpaceData("ordinary-legacy")
        for batch in [false, true] {
            let space = SpaceData("failed-device-add-\(batch)")
            space.lastUpdate = 40; ProximityLightingImportPreflight.storedSpace = space
            let baseline = S.prepareSubmission(space, payload: space.payload)!
            precondition(S.markSubmissionAccepted(baseline, space: space) && S.finishAcceptedSubmission(baseline, space: space))
            space.nodes = try [SpaceRecoveryReceiptTests.membershipNode(1), SpaceRecoveryReceiptTests.membershipNode(2)]
            space.lastUpdate = 50
            request.result = .failure(.init(code: 9999, message: "unknown error", httpStatusCode: 500,
                responseBody: "{\"code\":\"9999\",\"message\":\"unknown error\"}"))
            let operation: SyncOperation = batch ? .syncSite(site: SiteData(), syncSpaces: [space]) : .syncSpace(space: space)
            let flow = UploadFlowHarness(operation); flow.start()
            await flow.configurationUploadTask?.value
            guard case .failure = flow.state else { preconditionFailure("fixture POST must fail") }
            let receipt = try S.recoveryState(space)
            precondition(receipt.submission?.phase == .prepared)
            var remote = space.payload; remote["nodes"] = [[String: Any]](); remote["deviceCount"] = 2
            let outcome = await space.update(spaceJsonData: remote)
            precondition(outcome == .preserved("unconfirmedLocalNodes"))
            precondition(space.nodes.count == 2 && space.needUploadCloud && space.lastUploadCloudTimestamp == 40)
            precondition(try! S.recoveryState(space) == receipt)
        }
        ProximityLightingImportPreflight.storedSpace = nil
        print("PASS: production Space/Site upload 500 followed by equal empty detail preserves both added nodes and the original durable receipt")
        legacy.lastUploadCloudTimestamp = 40
        let legacyCalls = request.calls
        let legacyPrepared = await S.prepareUpload(legacy, payload: legacy.payload)
        precondition(!legacyPrepared && request.calls == legacyCalls && legacy.needUploadCloud,
            "legacy review must be deferred to entry, never silently GET or overwrite")
        for phase in [SpaceRecoveryState.Submission.Phase.prepared, .accepted, .verified] {
            let space = SpaceData("reopened-\(phase)")
            let context = S.prepareSubmission(space, payload: space.payload)!
            var state = context; state.submission?.phase = phase
            try S.testSaveState(state, space: space)
            let reopened = SpaceData(space.id)
            let calls = request.calls, writes = request.uploads
            request.result = .success([:])
            let flow = UploadFlowHarness(.syncSpace(space: reopened)); flow.start()
            await flow.configurationUploadTask?.value
            guard case .successful = flow.state else { preconditionFailure("local recovery") }
            precondition(!S.hasPendingUpload(reopened) && reopened.lastUploadCloudTimestamp == 50)
            precondition(request.calls - calls == (phase == .prepared ? 1 : 0) && request.uploads - writes == (phase == .prepared ? 1 : 0))
        }
        let site = SiteData(), one = SpaceData("batch-one"), two = SpaceData("batch-two"), untouched = SpaceData("untouched")
        site.lastUploadCloudTimestamp = 99
        request.result = .success([:]); request.onRequest = { two.savesSucceed = false }
        let batch = UploadFlowHarness(.syncSite(site: site, syncSpaces: [one, two]))
        batch.start(); await batch.configurationUploadTask?.value
        precondition(one.lastUploadCloudTimestamp == 50 && two.lastUploadCloudTimestamp == nil && untouched.lastUploadCloudTimestamp == nil)
        precondition(try! S.recoveryState(two).submission?.phase == .accepted)
        two.savesSucceed = true
        let calls = request.calls
        if case .failure = S.resumeLocalUpload(two) { preconditionFailure("durable partial completion") }
        precondition(request.calls == calls && two.lastUploadCloudTimestamp == 50)
        print("PASS: production upload task + local export preparation + real disk receipts: write-only success/failure/timeout, new edits, identity, reopened old receipts, partial batch persistence")
    }
}
