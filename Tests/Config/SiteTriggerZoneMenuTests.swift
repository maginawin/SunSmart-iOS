import Foundation

// 菜单方法由验证脚本从实际 SiteViewController 提取；依赖替身仅记录导航和权限提示。
extension String { var localizedString: String { self } }
struct UIImage { init?(named: String) {} }
enum MenuPopView {
    struct MenuItem {
        let icon: UIImage?
        let title: String
        let tapItemBack: (Int) -> Void
    }
}
final class SiteData {
    var permission: Permission = .owner
    var canManageSiteTriggerZones = true
}
final class SiteTriggerZoneViewController {
    let site: SiteData
    init(site: SiteData) { self.site = site }
}
final class NavigationSpy {
    var pushed: [SiteTriggerZoneViewController] = []
    func pushViewController(_ controller: SiteTriggerZoneViewController, animated: Bool) { pushed.append(controller) }
}
enum XWHUDManager {
    static var messages: [String] = []
    static func showTipHUD(_ message: String) { messages.append(message) }
}

@main
struct SiteTriggerZoneMenuTests {
    static func visibility(build: FeatureVisibility.BuildMode, builds: [String], roles: [String]) throws -> FeatureVisibility {
        let bytes = try JSONSerialization.data(withJSONObject: ["sites": ["site": ["triggerZone": ["builds": builds, "roles": roles]]]])
        return FeatureVisibility(build: build) { bytes }
    }

    static func main() throws {
        let site = SiteData()
        let menu = SiteMenuHarness(site: site)
        let normal = try visibility(build: .debug, builds: ["debug"], roles: ["owner", "editor"])
        for role in [Permission.owner, .editor] {
            site.permission = role
            let item = menu.item(normal)!
            precondition(item.title == "trigger_zone")
            item.tapItemBack(0)
            precondition(menu.navigationController!.pushed.last!.site === site)
        }
        precondition(menu.navigationController!.pushed.count == 2)
        site.permission = .visitor
        precondition(menu.item(normal) == nil)

        site.permission = .owner
        let stale = menu.item(normal)!
        site.permission = .visitor
        stale.tapItemBack(0)
        precondition(menu.navigationController!.pushed.count == 2, "A stale menu must not navigate")
        precondition(XWHUDManager.messages.isEmpty)
        site.permission = .editor
        precondition(menu.item(normal) != nil, "Reopening the menu must read the current Site role")

        let allRoles = try visibility(build: .debug, builds: ["debug", "release"], roles: ["owner", "editor", "visitor"])
        site.permission = .visitor
        site.canManageSiteTriggerZones = false
        let visibleVisitor = menu.item(allRoles)!
        visibleVisitor.tapItemBack(0)
        precondition(menu.navigationController!.pushed.count == 2)
        precondition(XWHUDManager.messages == ["no_permission"])

        site.permission = .owner
        let restrictedOwner = menu.item(normal)!
        restrictedOwner.tapItemBack(0)
        precondition(menu.navigationController!.pushed.count == 2)
        precondition(XWHUDManager.messages.count == 2)
        site.canManageSiteTriggerZones = true
        restrictedOwner.tapItemBack(0)
        precondition(menu.navigationController!.pushed.count == 3)

        let releaseHidden = try visibility(build: .release, builds: ["debug"], roles: ["owner"])
        precondition(menu.item(releaseHidden) == nil)
        let releaseOnly = try visibility(build: .release, builds: ["release"], roles: ["owner"])
        precondition(menu.item(releaseOnly) != nil)
        let debugHidden = try visibility(build: .debug, builds: ["release"], roles: ["owner"])
        precondition(menu.item(debugHidden) == nil)
        print("PASS: production Site menu, current Site roles, stale click rejection, operation denial and correct destination")
    }
}
