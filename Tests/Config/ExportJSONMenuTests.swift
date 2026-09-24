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
                           roles: [String] = ["owner", "editor", "visitor"]) throws -> FeatureVisibility {
        let data = try JSONSerialization.data(withJSONObject: ["sites": ["site": [
            "exportJson": ["builds": ["debug"], "roles": roles]
        ]]])
        return FeatureVisibility(build: build) { data }
    }

    static func main() throws {
        let bundled = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let menu = ExportJSONMenuHarness(visibility: FeatureVisibility { bundled })
        let card = SpaceData()
        var checks = 0
        for siteRole in [Permission.owner, .editor, .visitor] {
            for spaceRole in [Permission.owner, .editor, .visitor] {
                for cardRole in [Permission.owner, .editor, .visitor] {
                    menu.site.permission = siteRole
                    menu.space.permission = spaceRole
                    card.permission = cardRole
                    let entries = [(menu.siteMenu(), Optional<SpaceData>.none),
                                   (menu.cardMenu(space: card), Optional(card)),
                                   (menu.spaceMenu(), Optional(menu.space))]
                    for (items, expectedSpace) in entries {
                        #if DEBUG
                        let expected = true
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
        let release = ExportJSONMenuHarness(visibility: FeatureVisibility(build: .release) { bundled })
        for role in [Permission.owner, .editor, .visitor] {
            release.site.permission = role; release.space.permission = role; card.permission = role
            precondition(release.siteMenu().isEmpty && release.spaceMenu().isEmpty
                         && release.cardMenu(space: card).isEmpty)
            release.debugJSONExporter.share(site: release.site, from: release)
            release.debugJSONExporter.share(site: release.site, space: card, from: release)
            release.debugJSONExporter.share(site: release.site, space: release.space, from: release)
            precondition(release.debugJSONExporter.exports == 0, "Release direct share must remain hidden")
        }

        #if DEBUG
        // A restricted rule must still reject a role change after the menu opens.
        let restricted = ExportJSONMenuHarness(visibility: try visibility(roles: ["owner", "editor"]))
        for kind in 0..<3 {
            restricted.site.permission = .editor; restricted.space.permission = .editor; card.permission = .editor
            let item = [restricted.siteMenu(), restricted.cardMenu(space: card), restricted.spaceMenu()][kind][0]
            switch kind {
            case 0: restricted.site.permission = .visitor
            case 1: card.permission = .visitor
            default: restricted.space.permission = .visitor
            }
            let before = restricted.debugJSONExporter.exports
            item.tapItemBack(0)
            precondition(restricted.debugJSONExporter.exports == before, "Stale menu must not export")
        }
        precondition(XWHUDManager.messages.isEmpty, "Allowed visitor must not see a permission error")
        #endif
        print("PASS: \(checks) production menu cases using bundled configuration, configuration denial, resource selection and stale action guards (\(FeatureVisibility.BuildMode.current.rawValue))")
    }
}
