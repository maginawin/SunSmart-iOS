import Foundation

enum NetworkApiError: Error, Equatable {
    case resourceNotFound, noSitePermission, requestTimeout, unknown
}
enum NetowrkReqeustApi: Equatable {
    case shareInfo(shareId: String)
    case transferSite(siteId: String, password: String)
}
enum NetworkRequest {
    static let shared = Client()
    struct Client {
        func request(_ api: NetowrkReqeustApi) async -> Result<[String: Any], NetworkApiError> { .failure(.unknown) }
    }
}
enum UserData {
    static var currentUserId = "owner"
    static var currentServerRegion = 1
}
extension String {
    var localizedString: String { self }
    static func generateRandomNumberString() -> String { "fixture-password" }
}
enum SpaceMembershipResponseContext {
    static var epoch = 0
    static func capture(account: String, region: String) -> [String: String] {
        ["account": account, "region": region, "epoch": String(epoch)]
    }
    static func matches(_ value: [String: String], account: String, region: String) -> Bool {
        value == capture(account: account, region: region)
    }
}
final class SiteData {
    enum Permission { case owner, visitor }
    enum State { case normal, waitDeleted }
    var id = "site", region = 1, create: Int64 = 1
    var permission = Permission.owner, state = State.normal
    var transferCode: String?, transferPassword: String?
    static var stored: SiteData?
    static var failWrite = false
    static var writes = 0
    func copy() -> SiteData {
        let site = SiteData()
        site.id = id; site.region = region; site.create = create
        site.permission = permission; site.state = state
        site.transferCode = transferCode; site.transferPassword = transferPassword
        return site
    }
    static func load(siteId: String) -> SiteData? { stored?.id == siteId ? stored?.copy() : nil }
    func replaceTransferCredentials(_ value: SiteTransferCredentials, expected: SiteTransferCredentials) -> Bool {
        guard !Self.failWrite, let saved = Self.stored, SiteTransferCredentials(site: saved) == expected else { return false }
        Self.writes += 1
        saved.transferCode = value.code; saved.transferPassword = value.password
        transferCode = value.code; transferPassword = value.password
        return true
    }
}

@main enum SiteTransferCoordinatorTests {
    @MainActor static func fixture(code: String? = "old") -> SiteData {
        UserData.currentUserId = "owner"; UserData.currentServerRegion = 1
        SpaceMembershipResponseContext.epoch = 0
        SiteData.failWrite = false; SiteData.writes = 0
        let site = SiteData(); site.transferCode = code; site.transferPassword = code == nil ? nil : "old-password"
        SiteData.stored = site.copy()
        return site
    }
    static func response(code: String = "new", lookup: Bool = false, owner: String = "owner") -> [String: Any] {
        ["data": ["siteId": "site", "owner": ["userId": owner], "token": code,
                  "type": "ownertrans", lookup ? "transPasswd" : "passwd": "server-password"]]
    }
    @MainActor static func main() async {
        var site = fixture(code: nil)
        var calls: [NetowrkReqeustApi] = []
        var coordinator = SiteTransferCoordinator { api in calls.append(api); return .success(response()) }
        guard case .success(let created) = await coordinator.prepare(site: site) else { fatalError("Initial create") }
        precondition(calls == [.transferSite(siteId: "site", password: "fixture-password")])
        precondition(created.transferCode == "new" && site.transferPassword == "server-password")

        site = fixture(); calls = []
        coordinator = SiteTransferCoordinator { api in calls.append(api); return .success(response(code: "old", lookup: true)) }
        guard case .success = await coordinator.prepare(site: site) else { fatalError("Valid reuse") }
        precondition(calls == [.shareInfo(shareId: "old")])

        site = fixture(); calls = []
        coordinator = SiteTransferCoordinator { api in
            calls.append(api)
            if case .shareInfo = api { return .failure(.resourceNotFound) }
            precondition(SiteData.stored?.transferCode == nil && SiteData.stored?.transferPassword == nil)
            return .success(response())
        }
        guard case .success = await coordinator.prepare(site: site) else { fatalError("Expired cache recovery") }
        precondition(calls.count == 2 && SiteData.stored?.transferCode == "new")

        for error in [NetworkApiError.requestTimeout, .noSitePermission, .unknown] {
            site = fixture(); calls = []
            coordinator = SiteTransferCoordinator { api in calls.append(api); return .failure(error) }
            guard case .failure(.network(let actual)) = await coordinator.prepare(site: site) else { fatalError("Network error") }
            precondition(actual == error && calls.count == 1 && SiteData.writes == 0)
            precondition(SiteData.stored?.transferCode == "old")
        }

        site = fixture(); calls = []; SiteData.failWrite = true
        coordinator = SiteTransferCoordinator { api in calls.append(api); return .failure(.resourceNotFound) }
        guard case .failure(.storage) = await coordinator.prepare(site: site) else { fatalError("Failed clear") }
        precondition(calls.count == 1 && SiteData.stored?.transferCode == "old")

        site = fixture(code: nil); SiteData.failWrite = true
        coordinator = SiteTransferCoordinator { _ in .success(response()) }
        guard case .failure(.storage) = await coordinator.prepare(site: site) else { fatalError("Failed create persistence") }
        precondition(SiteData.stored?.transferCode == nil)
        SiteData.failWrite = false
        guard case .success = await coordinator.prepare(site: site) else { fatalError("Persistence retry") }

        site = fixture(); calls = []
        coordinator = SiteTransferCoordinator { api in
            calls.append(api)
            if case .shareInfo = api { return .failure(.resourceNotFound) }
            return .failure(.requestTimeout)
        }
        guard case .failure(.network(.requestTimeout)) = await coordinator.prepare(site: site) else { fatalError("Create failure") }
        precondition(calls.count == 2 && SiteData.stored?.transferCode == nil)
        coordinator = SiteTransferCoordinator { _ in .success(response()) }
        guard case .success = await coordinator.prepare(site: site) else { fatalError("Explicit retry after create failure") }

        for change in 0..<7 {
            site = fixture(); calls = []
            coordinator = SiteTransferCoordinator { api in
                calls.append(api)
                switch change {
                case 0: UserData.currentUserId = "another-account"
                case 1: UserData.currentServerRegion = 2
                case 2: SpaceMembershipResponseContext.epoch += 1 // Successful receipt invalidates earlier operations.
                case 3: SiteData.stored?.transferCode = "newer-task"
                case 4: SiteData.stored?.permission = .visitor
                case 5: SiteData.stored?.state = .waitDeleted
                default: SiteData.stored?.create += 1
                }
                return .failure(.resourceNotFound)
            }
            guard case .failure(.superseded) = await coordinator.prepare(site: site) else { fatalError("Late lookup") }
            precondition(calls.count == 1 && SiteData.writes == 0)
        }

        site = fixture(code: nil)
        coordinator = SiteTransferCoordinator { _ in
            SpaceMembershipResponseContext.epoch += 1
            return .success(response())
        }
        guard case .failure(.superseded) = await coordinator.prepare(site: site) else { fatalError("Late create") }
        precondition(SiteData.writes == 0)

        site = fixture(); calls = []
        coordinator = SiteTransferCoordinator { api in calls.append(api); return .success(response(code: "old", lookup: true, owner: "other")) }
        guard case .failure(.network(.unknown)) = await coordinator.prepare(site: site) else { fatalError("Wrong owner") }
        precondition(calls.count == 1 && SiteData.writes == 0)

        site = fixture(); calls = []
        coordinator = SiteTransferCoordinator { api in calls.append(api); return .success(response()) }
        guard case .success = await coordinator.prepare(site: site, password: "changed") else { fatalError("Password change") }
        precondition(calls == [.transferSite(siteId: "site", password: "changed")])
        precondition(site.transferCode == "new" && site.transferPassword == "server-password")

        site = fixture(code: nil); calls = []
        var pending: CheckedContinuation<Result<[String: Any], NetworkApiError>, Never>?
        coordinator = SiteTransferCoordinator { api in
            calls.append(api)
            return await withCheckedContinuation { pending = $0 }
        }
        let first = Task { [coordinator, site] in await coordinator.prepare(site: site) }
        while pending == nil { await Task.yield() }
        guard case .failure(.busy) = await coordinator.prepare(site: site) else { fatalError("Duplicate request") }
        pending?.resume(returning: .success(response()))
        guard case .success = await first.value else { fatalError("First request completion") }
        precondition(calls.count == 1)

        site = fixture(code: nil); pending = nil
        coordinator = SiteTransferCoordinator { _ in
            await withCheckedContinuation { pending = $0 }
        }
        let cancelled = Task { [coordinator, site] in await coordinator.prepare(site: site) }
        while pending == nil { await Task.yield() }
        cancelled.cancel()
        pending?.resume(returning: .success(response()))
        guard case .failure(.superseded) = await cancelled.value else { fatalError("Cancelled response") }
        precondition(SiteData.writes == 0)

        site = fixture()
        precondition(SiteTransferImportPolicy.canOpenOwnedSite(local: site, ownerID: "owner", currentUserID: "owner"))
        precondition(!SiteTransferImportPolicy.canOpenOwnedSite(local: site, ownerID: "other", currentUserID: "owner"))
        site.state = .waitDeleted
        precondition(!SiteTransferImportPolicy.canOpenOwnedSite(local: site, ownerID: "owner", currentUserID: "owner"))
        print("PASS: transfer create/reuse/expiry, storage retry, error boundaries, late responses, duplicate requests and import routing")
    }
}
