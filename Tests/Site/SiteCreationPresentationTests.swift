import Foundation

// UI/navigation/cloud boundaries; the Site-list completion is extracted from production.
final class SiteData {
    let id: String, region = "region"
    init(_ id: String) { self.id = id }
}
final class SiteViewController {
    let site: SiteData
    init(site: SiteData, addSite: Bool) { self.site = site }
}
final class NavigationSpy {
    var opened: [String] = []
    func pushViewController(_ controller: SiteViewController, animated: Bool) { opened.append(controller.site.id) }
}
final class CollectionSpy { func reloadData() {} }
final class CloudSynchronizationManager {
    enum Operation { case syncSite(site: SiteData) }
    enum Level { case normal }
    static let shared = CloudSynchronizationManager()
    var queued: [String] = []
    func addSynchronizationHandle(operation: Operation, level: Level) {
        if case .syncSite(let site) = operation { queued.append(site.id) }
    }
}

@main enum SiteCreationPresentationTests {
    static func main() {
        let normal = SiteCreationHarness()
        normal.allSites = [SiteData("previous")]
        normal.complete(SiteData("new"))
        precondition(normal.allSites.map(\.id) == ["previous", "new"])
        precondition(normal.navigationController!.opened == ["new"])

        let interleaved = SiteCreationHarness()
        let refreshed = SiteData("new")
        // setupData() has already reloaded the saved Site while the alert is dismissing.
        interleaved.allSites = [refreshed]
        CloudSynchronizationManager.shared.queued = []
        interleaved.complete(SiteData("new"))
        precondition(interleaved.allSites.count == 1, "Dismiss completion must not duplicate a Site already loaded by refresh")
        precondition(interleaved.allSites[0] === refreshed, "Keep the refreshed list instance")
        precondition(interleaved.navigationController!.opened == ["new"])
        precondition(CloudSynchronizationManager.shared.queued == ["new"])
        print("PASS: Site creation presentation and list refresh during alert dismissal")
    }
}
