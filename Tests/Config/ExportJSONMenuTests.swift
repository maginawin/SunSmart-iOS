import Foundation

// The harness compiles the three production menu blocks and the production share
// entry guards. Only UIKit and the work after those guards are replaced with spies.
extension String { var localizedString: String { self } }
struct UIImage { init?(named: String) {} }
enum MenuPopView {
    struct MenuItem {
        let icon: UIImage?
        let title: String
        let performsActionAfterDismiss: Bool
        let tapItemBack: (Int) -> Void
    }
}
class UIViewController {
    struct View { var window: Int? = 1 }
    var viewIfLoaded: View? = View()
    var presentedViewController: UIViewController?
}
final class SiteData { var permission: Permission = .owner }
final class SpaceData { var permission: Permission = .owner }
enum XWHUDManager {
    static var messages: [String] = []
    static func showErrorTipHUD(_ message: String) { messages.append(message) }
}

@main
struct ExportJSONMenuTests {
    static func visibility(build: FeatureVisibility.BuildMode = .current,
                           roles: [String] = ["owner", "editor"]) throws -> FeatureVisibility {
        let data = try JSONSerialization.data(withJSONObject: ["sites": ["site": [
            "exportJson": ["builds": ["debug"], "roles": roles]
        ]]])
        return FeatureVisibility(build: build) { data }
    }

    static func main() throws {
        let menu = ExportJSONMenuHarness(visibility: try visibility())
        let card = SpaceData()
        var checks = 0
        for siteRole in [Permission.owner, .editor, .visitor] {
            for spaceRole in [Permission.owner, .editor, .visitor] {
                for cardRole in [Permission.owner, .editor, .visitor] {
                    menu.site.permission = siteRole
                    menu.space.permission = spaceRole
                    card.permission = cardRole
                    let entries = [(menu.siteMenu(), siteRole, Optional<SpaceData>.none),
                                   (menu.cardMenu(space: card), cardRole, Optional(card)),
                                   (menu.spaceMenu(), spaceRole, Optional(menu.space))]
                    for (items, role, expectedSpace) in entries {
                        #if DEBUG
                        let expected = role != .visitor
                        #else
                        let expected = false
                        #endif
                        precondition(items.count == (expected ? 1 : 0), "Wrong resource role or build")
                        if let item = items.first {
                            precondition(item.title == "debug_export_json" && item.performsActionAfterDismiss)
                            let before = menu.debugJSONExporter.exports
                            item.tapItemBack(0)
                            precondition(menu.debugJSONExporter.exports == before + 1)
                            precondition(menu.debugJSONExporter.lastSpace === expectedSpace)
                        }
                        checks += 1
                    }
                }
            }
        }
        card.permission = .owner
        let disabled = ExportJSONMenuHarness(visibility: try visibility(roles: []))
        precondition(disabled.siteMenu().isEmpty && disabled.spaceMenu().isEmpty
                     && disabled.cardMenu(space: card).isEmpty)
        disabled.debugJSONExporter.share(site: disabled.site, from: disabled)
        precondition(disabled.debugJSONExporter.exports == 0, "Direct share must respect configuration")
        let release = ExportJSONMenuHarness(visibility: try visibility(build: .release))
        precondition(release.siteMenu().isEmpty && release.spaceMenu().isEmpty
                     && release.cardMenu(space: card).isEmpty)

        #if DEBUG
        // Opening a menu must not freeze the permission used by its later action.
        for kind in 0..<3 {
            menu.site.permission = .editor; menu.space.permission = .editor; card.permission = .editor
            let item = [menu.siteMenu(), menu.cardMenu(space: card), menu.spaceMenu()][kind][0]
            switch kind {
            case 0: menu.site.permission = .visitor
            case 1: card.permission = .visitor
            default: menu.space.permission = .visitor
            }
            let before = menu.debugJSONExporter.exports
            item.tapItemBack(0)
            precondition(menu.debugJSONExporter.exports == before, "Stale menu must not export")
        }
        // A more permissive display rule must never grant export authorization.
        let visitor = ExportJSONMenuHarness(visibility: try visibility(roles: ["visitor"]))
        visitor.site.permission = .visitor
        visitor.siteMenu()[0].tapItemBack(0)
        precondition(visitor.debugJSONExporter.exports == 0)
        precondition(XWHUDManager.messages == ["no_permission"])
        #endif
        print("PASS: \(checks) production menu cases, configuration denial, resource selection and stale action guards (\(FeatureVisibility.BuildMode.current.rawValue))")
    }
}
