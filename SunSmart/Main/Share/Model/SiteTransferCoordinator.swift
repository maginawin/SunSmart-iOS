import Foundation

/// Local cache of one outbound ownership-transfer task, not Site configuration.
struct SiteTransferCredentials: Equatable {
    var code: String?
    var password: String?

    static let empty = SiteTransferCredentials()

    init(code: String? = nil, password: String? = nil) {
        self.code = code
        self.password = password
    }

    init(site: SiteData) {
        code = site.transferCode
        password = site.transferPassword
    }
}

enum SiteTransferImportPolicy {
    static func canOpenOwnedSite(local: SiteData, ownerID: String, currentUserID: String) -> Bool {
        ownerID == currentUserID && local.permission == .owner && local.state == .normal
    }
}

/// Both transfer menus and password changes use the same scoped request/cache lifecycle.
@MainActor
final class SiteTransferCoordinator {
    enum Failure: Error {
        case network(NetworkApiError)
        case storage
        case superseded
        case busy

        var message: String? {
            switch self {
            case .network(let error): return error.localizedDescription
            case .storage: return "space_recovery_storage_failed".localizedString
            case .superseded, .busy: return nil
            }
        }
    }

    private struct Scope: Hashable {
        let account: String
        let region: String
        let siteID: String
    }

    static let shared = SiteTransferCoordinator()
    private var active: Set<Scope> = []
    private let request: (NetowrkReqeustApi) async -> Result<[String: Any], NetworkApiError>

    init(request: @escaping (NetowrkReqeustApi) async -> Result<[String: Any], NetworkApiError> = {
        await NetworkRequest.shared.request($0)
    }) {
        self.request = request
    }

    func prepare(site selected: SiteData, password newPassword: String? = nil) async -> Result<SiteData, Failure> {
        let scope = Scope(account: UserData.currentUserId,
                          region: String(describing: UserData.currentServerRegion), siteID: selected.id)
        guard active.insert(scope).inserted else { return .failure(.busy) }
        defer { active.remove(scope) }
        let context = SpaceMembershipResponseContext.capture(account: scope.account, region: scope.region)
        guard selected.region == UserData.currentServerRegion,
              let initial = SiteData.load(siteId: selected.id), initial.create == selected.create,
              initial.permission == .owner, initial.state == .normal else {
            return .failure(.network(.noSitePermission))
        }
        var expected = SiteTransferCredentials(site: initial)

        func current() -> SiteData? {
            guard !Task.isCancelled,
                  SpaceMembershipResponseContext.matches(context, account: UserData.currentUserId,
                      region: String(describing: UserData.currentServerRegion)),
                  let site = SiteData.load(siteId: scope.siteID), site.region == selected.region,
                  site.create == initial.create, site.permission == .owner, site.state == .normal,
                  SiteTransferCredentials(site: site) == expected else { return nil }
            return site
        }

        func persist(_ credentials: SiteTransferCredentials) -> Result<SiteData, Failure> {
            guard let site = current() else { return .failure(.superseded) }
            guard site.replaceTransferCredentials(credentials, expected: expected) else { return .failure(.storage) }
            expected = credentials
            selected.transferCode = credentials.code
            selected.transferPassword = credentials.password
            return .success(site)
        }

        if newPassword == nil, let code = expected.code, !code.isEmpty {
            let result = await request(.shareInfo(shareId: code))
            guard current() != nil else { return .failure(.superseded) }
            switch result {
            case .success(let response):
                guard let data = response["data"] as? [String: Any],
                      data["type"] as? String == "ownertrans",
                      data["token"] as? String == code,
                      let credentials = Self.credentials(data, siteID: scope.siteID, ownerID: scope.account,
                                                         passwordKey: "transPasswd", fallbackPassword: nil) else {
                    return .failure(.network(.unknown))
                }
                return persist(credentials)
            case .failure(.resourceNotFound):
                // Only this explicit response authorizes replacing an expired cache.
                if case .failure(let error) = persist(.empty) { return .failure(error) }
            case .failure(let error):
                return .failure(.network(error))
            }
        }

        guard current() != nil else { return .failure(.superseded) }
        let password = newPassword ?? String.generateRandomNumberString()
        let result = await request(.transferSite(siteId: scope.siteID, password: password))
        guard current() != nil else { return .failure(.superseded) }
        switch result {
        case .success(let response):
            guard let data = response["data"] as? [String: Any],
                  let credentials = Self.credentials(data, siteID: scope.siteID, ownerID: scope.account,
                                                     passwordKey: "passwd", fallbackPassword: password) else {
                return .failure(.network(.unknown))
            }
            return persist(credentials)
        case .failure(let error):
            return .failure(.network(error))
        }
    }

    private static func credentials(_ data: [String: Any], siteID: String, ownerID: String,
                                    passwordKey: String, fallbackPassword: String?) -> SiteTransferCredentials? {
        guard data["siteId"] as? String == siteID,
              let owner = data["owner"] as? [String: Any], owner["userId"] as? String == ownerID,
              let code = data["token"] as? String, !code.isEmpty,
              let password = data[passwordKey] as? String ?? fallbackPassword else { return nil }
        return .init(code: code, password: password)
    }
}
