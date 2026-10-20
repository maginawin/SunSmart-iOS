import Foundation

// The harness runs the production option builder. The model double supplies
// edit capabilities; membership, recovery and OTA policy are tested separately.
extension String { var localizedString: String { self } }
enum MeshOperate { case edit }
final class SiteData { var isHdbSite = false }
final class SpaceData {
    var permission: Permission = .owner
    var groupOperates: [MeshOperate] = [.edit]
    var deviceOperates: [MeshOperate] = [.edit]
}

@main
struct SpaceMoreMenuTests {
    static func main() throws {
        let bundled = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        for target in FeatureVisibility.Target.allCases {
            let menu = SpaceMoreMenuHarness(visibility: FeatureVisibility(target: target) { bundled })
            for isHdbSite in [false, true] {
                menu.site.isHdbSite = isHdbSite
                for role in [Permission.owner, .editor, .visitor] {
                    menu.space.permission = role
                    let items = menu.items()
                    let expected = isHdbSite && role != .visitor
                    precondition(items.contains(.hdbConfiguration) == expected, "Wrong HDB target or resource role")
                    precondition(items.contains(.triggerZone), "Site feature settings must not gate Space Trigger Zone")
                    if expected {
                        precondition(items.firstIndex(of: .hdbConfiguration)! == items.firstIndex(of: .triggerZone)! + 1,
                                     "HDB must be directly below Trigger Zone")
                        menu.isMeshTestOptionEnabled = true
                        precondition(menu.items().contains(.hdbConfiguration), "Mesh test option lost HDB")
                        menu.isMeshTestOptionEnabled = false
                    }
                }
                menu.space.permission = .owner
                menu.space.groupOperates = []
                precondition(!menu.items().contains(.hdbConfiguration), "Revoked editing capability must hide HDB")
                menu.space.groupOperates = [.edit]
                precondition(menu.items().contains(.hdbConfiguration) == isHdbSite,
                             "Restored editing capability must restore HDB for an HDB Site")
            }
        }
        print("PASS: production Space More ordering, five brands, roles and capability refresh (\(FeatureVisibility.BuildMode.current.rawValue))")
    }
}
