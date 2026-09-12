import UIKit

// Isolated fixture models. Production exporter/menu/file code is compiled unchanged.
enum Permission: Int { case owner = 1, editor, visitor }
enum FixtureValue: Int { case normal = 1, other }
struct FixtureZone: Codable { var value = 1 }
enum UserData { static var currentUserName = "Fixture"; static var currentUserId = "fixture-user" }
struct ConfigurationSnapshotRevision: Equatable {
    static var version = 0
    let version: Int
    let account: String
    static func current() -> Self? { .init(version: version, account: UserData.currentUserId) }
}
final class SpaceData {
    var id = UUID().uuidString, siteId = "site", meshUUID = "mesh", meshNetworkId = "network", name = "Space"
    var permission = Permission.owner, state = FixtureValue.normal, sourceType = FixtureValue.normal
    var imageId = 0, create: Int64 = 10, lastUpdate: Int64 = 20
    var displayDeviceNamePrefix = false, showCCTQuickButtons = false, triggerZonesLoadFailed = false
    var controlType = FixtureValue.normal, deviceBlinkMode = FixtureValue.normal
    var triggerZones = [FixtureZone]()
    var unavailable = false
    static var exportHook: (() -> Void)?
    func copy() -> SpaceData {
        let result = SpaceData()
        result.id = id; result.siteId = siteId; result.name = name; result.permission = permission
        result.unavailable = unavailable; result.triggerZones = triggerZones
        return result
    }
    func export(purpose: SpaceSnapshotExportPurpose) async -> [String: Any]? {
        precondition(purpose == .debugInspection)
        Self.exportHook?()
        return unavailable ? nil : ["uuid": id, "spaceName": name, "nodes": [], "groups": [], "updateTimestamp": lastUpdate]
    }
}
enum SpaceSnapshotExportPurpose { case debugInspection }
final class SiteData {
    var id = "site", meshUUID = "mesh", meshNetworkId = "network", name = "Site"
    var permission = Permission.owner, state = FixtureValue.normal, sourceType = FixtureValue.normal
    var imageId = 0, create: Int64 = 10, lastUpdate: Int64 = 20
    var type = FixtureValue.normal
    var timezone: String? = "Asia/Singapore"
    var localAddress: UInt16? = 12
    var spaces = [SpaceData]()
    func copy() -> SiteData {
        let result = SiteData(); result.spaces = spaces.map { $0.copy() }; return result
    }
    func export(spaceIds: [String]) async -> [String: Any]? {
        precondition(spaceIds.isEmpty)
        return ["uuid": id, "siteName": name, "spaces": [], "updateTimestamp": lastUpdate]
    }
}
enum SpaceConfigurationSafety {
    static var unavailable = Set<String>()
    static func canReadDebugSnapshot(_ space: SpaceData) -> Bool { !unavailable.contains(space.id) }
}
enum NetowrkReqeustApi {
    case siteUpload(siteData: [String: Any]), spaceUpload(siteId: String, spaceId: String, spaceData: [String: Any])
    var parameters: [String: Any]? {
        switch self {
        case .siteUpload(let data): return ["site": data, "user": ["userId": UserData.currentUserId, "username": UserData.currentUserName]]
        case .spaceUpload(let site, let space, let data): return ["siteId": site, "spaceId": space, "spaces": [data], "userId": UserData.currentUserId]
        }
    }
}

@MainActor func runSnapshotTests() async throws {
    let site = SiteData(), owner = SpaceData(), editor = SpaceData(), visitor = SpaceData()
    editor.permission = .editor; visitor.permission = .visitor
    site.spaces = [owner, editor, visitor]
    let snapshot = try DebugCloudJSONExporter.Snapshot(site: site, space: nil)
    let payload = try await snapshot.payload()
    let members = (payload["site"] as! [String: Any])["spaces"] as! [[String: Any]]
    precondition(members.compactMap { $0["uuid"] as? String } == [owner.id, editor.id])
    let single = try await DebugCloudJSONExporter.Snapshot(site: site, space: editor).payload()
    precondition(single["spaceId"] as? String == editor.id && (single["spaces"] as! [Any]).count == 1)
    func rejects(_ action: () throws -> Void) {
        do { try action(); preconditionFailure("Invalid snapshot accepted") } catch {}
    }
    owner.name = "Changed"
    rejects { try snapshot.validate() }
    let accountSnapshot = try DebugCloudJSONExporter.Snapshot(site: site, space: owner)
    UserData.currentUserId = "another"
    rejects { try accountSnapshot.validate() }
    UserData.currentUserId = "fixture-user"
    let permissionSnapshot = try DebugCloudJSONExporter.Snapshot(site: site, space: editor)
    editor.permission = .visitor
    rejects { try permissionSnapshot.validate() }
    rejects { _ = try DebugCloudJSONExporter.Snapshot(site: site, space: visitor) }
    editor.permission = .editor
    let dbSnapshot = try DebugCloudJSONExporter.Snapshot(site: site, space: nil)
    ConfigurationSnapshotRevision.version += 1
    rejects { try dbSnapshot.validate() }
    let topologySnapshot = try DebugCloudJSONExporter.Snapshot(site: site, space: owner)
    owner.triggerZones.append(.init())
    rejects { try topologySnapshot.validate() }
    editor.unavailable = true
    do {
        _ = try await DebugCloudJSONExporter.Snapshot(site: site, space: nil).payload()
        preconditionFailure("Failed Space silently omitted")
    } catch {}
    editor.unavailable = false
    SpaceData.exportHook = { ConfigurationSnapshotRevision.version += 1 }
    do {
        _ = try await DebugCloudJSONExporter.Snapshot(site: site, space: owner).payload()
        preconditionFailure("Concurrent mutation accepted")
    } catch {}
    SpaceData.exportHook = nil
    site.spaces = []
    let empty = try await DebugCloudJSONExporter.Snapshot(site: site, space: nil).payload()
    precondition(((empty["site"] as! [String: Any])["spaces"] as! [Any]).isEmpty)
    print("PASS: snapshot scope, roles, invalid members, account, database and memory changes")
}

extension String { var localizedString: String { NSLocalizedString(self, comment: "") } }
var isIPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
func SCRXFrom(_ x: CGFloat) -> CGFloat { x * UIScreen.main.bounds.width / (isIPad ? 834 : 375) }
func SCRYFrom(_ y: CGFloat) -> CGFloat { y * UIScreen.main.bounds.height / (isIPad ? 1210 : 812) }
func RGB(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> UIColor { UIColor(red: r/255, green: g/255, blue: b/255, alpha: a) }
let TextBlack_Color = UIColor.black, Message_Color = UIColor.gray, Bar_Color = UIColor.blue, Line_Color = UIColor.lightGray
let FontName_Medium = "Helvetica"
func FONTS(_ value: CGFloat) -> UIFont { .systemFont(ofSize: value) }
extension UIView {
    var width: CGFloat { bounds.width }; var height: CGFloat { bounds.height }
}
extension UILabel {
    convenience init(text: String, textColor: UIColor, fontSize: CGFloat) {
        self.init(); self.text = text; self.textColor = textColor; font = .systemFont(ofSize: SCRXFrom(fontSize))
    }
}
extension UIButton {
    convenience init(target: Any?, action: Selector) { self.init(type: .custom); addTarget(target, action: action, for: .touchUpInside) }
}
extension UIApplication {
    func keyWindow() -> UIWindow { (delegate as! AppDelegate).window! }
}
enum XWHUDManager {
    static func showCustomHUD(withMessage: String?, view: UIView) {}
    static func hide() {}
    static func showErrorTipHUD(_ message: String) { print("EXPORT ERROR: " + message) }
}
