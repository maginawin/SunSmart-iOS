import Foundation

// HTTP and App DB are controlled boundaries. Production clear/readback/current
// methods run unchanged, including account epochs and per-Space operation ordering.
struct UserData {
    let name: String, uuid: String
    static var currentUserId = "owner", currentServerRegion = "region"
}
enum Permission { case owner, editor, visitor }
enum SpaceMembershipRecord {
    struct Scope: Hashable {
        let account: String, region: String, siteID: String, spaceID: String
    }
}
enum SpaceMembershipCoordinator {
    static func scope(_ space: SpaceData) -> SpaceMembershipRecord.Scope {
        .init(account: UserData.currentUserId, region: UserData.currentServerRegion, siteID: space.siteId, spaceID: space.id)
    }
    static func isLeaving(_ space: SpaceData) -> Bool { space.leaving }
    static func accepts(_ payload: [String: Any]) -> Bool { true }
}
final class SpaceData {
    enum State { case normal, waitDeleted }
    let siteId: String, id: String
    var editor: UserData?
    var permission = Permission.owner, state = State.normal
    var leaving = false, name = "configuration-v1", authorizationPassword: String?
    static var rows: [SpaceMembershipRecord.Scope: SpaceData] = [:]
    static var failingSaves = Set<String>()
    init(_ id: String, editor: String? = "E", site: String = "site") {
        self.id = id; siteId = site; self.editor = editor.map { UserData(name: $0, uuid: $0) }
    }
    func copy() -> SpaceData {
        let copy = SpaceData(id, editor: editor?.uuid, site: siteId)
        copy.editor = editor; copy.permission = permission; copy.state = state; copy.name = name
        copy.leaving = leaving; copy.authorizationPassword = authorizationPassword
        return copy
    }
    @discardableResult func save() -> Bool {
        guard !Self.failingSaves.contains(id) else { return false }
        Self.rows[SpaceMembershipCoordinator.scope(self)] = copy(); return true
    }
    static func load(siteId: String, spaceId: String) -> [SpaceData] {
        rows[.init(account: UserData.currentUserId, region: UserData.currentServerRegion,
                   siteID: siteId, spaceID: spaceId)].map { [$0.copy()] } ?? []
    }
}
enum NetworkApiError: Error {
    case editorBeingUsedSpace, noSpacePermission, noNetwork
    var code: Int {
        switch self { case .editorBeingUsedSpace: return 4006; case .noSpacePermission: return 4009; case .noNetwork: return -1009 }
    }
}
enum NetowrkReqeustApi {
    case clearSpaceMember(siteId: String, spaceId: String, userId: String, permission: Permission, force: Bool)
    case clearSpacesMembers(siteId: String, spaces: [String], permission: Permission, force: Bool)
    case spaceMembers(siteId: String, spaceId: String)
    case spaceInfo(siteId: String, spaceId: String, password: String?)
    var spaceID: String? {
        switch self {
        case .spaceMembers(_, let id), .spaceInfo(_, let id, _), .clearSpaceMember(_, let id, _, _, _): return id
        default: return nil
        }
    }
}
@MainActor final class NetworkRequest {
    static let shared = NetworkRequest()
    var calls: [NetowrkReqeustApi] = []
    var handler: (NetowrkReqeustApi) async -> Result<[String: Any], NetworkApiError> = { _ in .failure(.noNetwork) }
    func request(_ api: NetowrkReqeustApi) async -> Result<[String: Any], NetworkApiError> {
        calls.append(api); return await handler(api)
    }
}

@main @MainActor struct SpaceEditorReclaimTests {
    static func require(_ value: Bool, _ message: String) { precondition(value, message) }
    static func reset(_ ids: [String] = ["A", "B"]) -> [SpaceData] {
        UserData.currentUserId = "owner"; UserData.currentServerRegion = "region"
        SpaceMembershipResponseContext.invalidate()
        SpaceData.rows = [:]; SpaceData.failingSaves = []
        NetworkRequest.shared.calls = []
        let spaces = ids.map { SpaceData($0) }; spaces.forEach { $0.save() }
        return spaces
    }
    static func member(_ id: String?) -> Result<[String: Any], NetworkApiError> {
        .success(["data": ["editor": id.map { ["userId": $0, "username": $0] } as Any? ?? NSNull()]])
    }
    static func detail(_ results: [String: [String: Int]]) -> Result<[String: Any], NetworkApiError> {
        .success(["data": ["detail": results]])
    }
    static func stored(_ id: String) -> SpaceData { SpaceData.load(siteId: "site", spaceId: id).first! }
    static func main() async {
        var spaces = reset()
        NetworkRequest.shared.handler = { api in
            switch api {
            case .clearSpacesMembers(_, let ids, let role, let force):
                require(ids == ["A", "B"] && role == .editor && !force, "retain non-forced editor request")
                return detail(["A": ["E": 200], "B": ["E": 4006]])
            default: return member(api.spaceID == "A" ? nil : "E")
            }
        }
        var result = await SpaceEditorReclaim.clear(spaces: spaces)
        require(result == [.cleared, .busy], "same Editor has independent per-Space outcomes")
        require(spaces[0].editor == nil && spaces[1].editor?.uuid == "E" && stored("B").editor?.uuid == "E",
            "success in A must not clear B")

        spaces = reset()
        NetworkRequest.shared.handler = { api in
            if case .clearSpacesMembers = api { return detail(["A": ["E": 4009], "B": ["E": 4009]]) }
            return member("E")
        }
        result = await SpaceEditorReclaim.clear(spaces: spaces)
        require(result == [.failed, .failed] && spaces.allSatisfy { $0.editor != nil }, "other errors cannot report success")

        for response in [detail(["A": [:]]), detail([:]), .success(["data": ["detail": ["A": "invalid"]]])] {
            spaces = reset(["A"])
            NetworkRequest.shared.handler = { api in
                if case .clearSpacesMembers = api { return response }
                return .failure(.noNetwork)
            }
            result = await SpaceEditorReclaim.clear(spaces: spaces)
            require(result == [.unconfirmed] && spaces[0].editor?.uuid == "E", "unknown results preserve cache without readback")
            require(NetworkRequest.shared.calls.count == 3, "unknown membership uses bounded owner GET fallback")
        }

        spaces = reset(["A"])
        NetworkRequest.shared.handler = { api in
            switch api {
            case .clearSpacesMembers: return detail(["A": [:]])
            case .spaceMembers: return .success(["data": ["visitors": []]])
            case .spaceInfo: return .success(["data": ["uuid": "A", "role": "owner"]])
            default: return .failure(.noNetwork)
            }
        }
        result = await SpaceEditorReclaim.clear(spaces: spaces)
        require(result == [.cleared] && stored("A").editor == nil, "complete owner GET resolves omitted editor")

        for editor in ["E", "new-editor"] {
            spaces = reset(["A"])
            NetworkRequest.shared.handler = { api in
                if case .clearSpacesMembers = api { return detail(["A": ["E": 200]]) }
                return member(editor)
            }
            result = await SpaceEditorReclaim.clear(spaces: spaces)
            require(result == [.unconfirmed] && stored("A").editor?.uuid == editor,
                "readback wins over success receipt; new editor is retained")
        }

        spaces = reset(["A"])
        spaces[0].editor = nil // Old buggy UI cache differs from the saved row.
        NetworkRequest.shared.handler = { api in
            if case .clearSpacesMembers = api { return detail(["A": ["E": 200]]) }
            return member(nil)
        }
        result = await SpaceEditorReclaim.clear(spaces: spaces)
        require(result == [.cleared] && stored("A").editor == nil, "old inconsistent cache can converge")

        for mutateDuringReadback in [false, true] {
            spaces = reset(["A"])
            NetworkRequest.shared.handler = { api in
                if case .clearSpacesMembers = api {
                    if !mutateDuringReadback { let row = stored("A"); row.editor = .init(name: "New", uuid: "new"); row.save() }
                    return detail(["A": ["E": 200]])
                }
                let row = stored("A"); row.editor = .init(name: "New", uuid: "new"); row.save()
                return member(nil)
            }
            result = await SpaceEditorReclaim.clear(spaces: spaces)
            require(result == [.changed] && stored("A").editor?.uuid == "new", "late receipt never removes replacement membership")
        }

        for change in ["account", "region", "epoch", "leave", "role"] {
            spaces = reset(["A"])
            let space = spaces[0]
            NetworkRequest.shared.handler = { _ in
                switch change {
                case "account": UserData.currentUserId = "other"
                case "region": UserData.currentServerRegion = "other"
                case "epoch": SpaceMembershipResponseContext.invalidate()
                case "leave": space.leaving = true
                default: space.permission = .visitor
                }
                return detail(["A": ["E": 200]])
            }
            result = await SpaceEditorReclaim.clear(spaces: spaces)
            require(result == [.changed] && space.editor?.uuid == "E" && NetworkRequest.shared.calls.count == 1,
                "authority change rejects old operation: \(change)")
        }

        spaces = reset(["A"])
        SpaceData.failingSaves = ["A"]
        NetworkRequest.shared.handler = { api in
            if case .clearSpacesMembers = api { return detail(["A": ["E": 200]]) }
            return member(nil)
        }
        result = await SpaceEditorReclaim.clear(spaces: spaces)
        require(result == [.unconfirmed] && stored("A").editor?.uuid == "E" && spaces[0].editor?.uuid == "E",
            "storage failure preserves visible and stored state")

        spaces = reset(["A"])
        NetworkRequest.shared.handler = { api in
            if case .clearSpaceMember(_, let id, let userID, let role, let force) = api {
                require(id == "A" && userID == "E" && role == .editor && !force, "single target identity retained")
                return .success([:])
            }
            let latest = stored("A"); latest.name = "configuration-v2"; latest.save()
            return .success(["data": ["space": ["uuid": "A", "editor": NSNull()]]])
        }
        result = await SpaceEditorReclaim.clear(spaces: spaces, single: true)
        require(result == [.cleared] && stored("A").name == "configuration-v2", "single clear saves latest row and reads nested member response")

        for payload: [String: Any] in [["uuid": "wrong", "role": "owner"], ["uuid": "A", "role": "visitor"],
                                      ["uuid": "A", "role": "owner", "editor": ["userId": "new"]]] {
            spaces = reset(["A"])
            NetworkRequest.shared.handler = { api in
                if case .clearSpacesMembers = api { return detail(["A": ["E": 200]]) }
                if case .spaceMembers = api { return .success(["data": [:]]) }
                return .success(["data": payload])
            }
            result = await SpaceEditorReclaim.clear(spaces: spaces)
            require(result == [.unconfirmed] && stored("A").editor?.uuid == "E", "invalid readback cannot erase membership")
        }

        // A retry starts while the first request is suspended. Its generation wins.
        spaces = reset(["A"])
        var held: CheckedContinuation<Result<[String: Any], NetworkApiError>, Never>?
        var reclaimCount = 0
        NetworkRequest.shared.handler = { api in
            if case .clearSpacesMembers = api {
                reclaimCount += 1
                if reclaimCount == 1 { return await withCheckedContinuation { held = $0 } }
                return detail(["A": ["E": 200]])
            }
            return member(nil)
        }
        let originalSpaces = spaces
        let first = Task { await SpaceEditorReclaim.clear(spaces: originalSpaces) }
        while held == nil { await Task.yield() }
        let second = await SpaceEditorReclaim.clear(spaces: originalSpaces)
        held!.resume(returning: detail(["A": ["E": 4006]]))
        let old = await first.value
        require(second == [.cleared] && old == [.changed] && stored("A").editor == nil, "superseded operation cannot restore stale membership")

        spaces = reset(["A"])
        held = nil
        NetworkRequest.shared.handler = { _ in await withCheckedContinuation { held = $0 } }
        let cancelledSpaces = spaces
        let cancelled = Task { await SpaceEditorReclaim.clear(spaces: cancelledSpaces) }
        while held == nil { await Task.yield() }
        cancelled.cancel(); held!.resume(returning: detail(["A": ["E": 200]]))
        let cancelledResult = await cancelled.value
        require(cancelledResult == [.changed] && stored("A").editor?.uuid == "E", "cancelled work does not apply later callbacks")
        print("Editor reclaim scope, readback, partial failure, persistence and stale-callback tests passed")
    }
}
