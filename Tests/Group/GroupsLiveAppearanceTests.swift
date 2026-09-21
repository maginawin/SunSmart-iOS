#if os(macOS)
import CoreGraphics
// Execute production binding/lifecycle bodies with minimal UIKit value sinks.
// This checks behavior only; UIKit layout and actual page transitions are manual.
private struct UIColor: Equatable {
    let red: Int, green: Int, blue: Int
    static let white = UIColor(red: 255, green: 255, blue: 255)
}
private func RGB(_ red: Int, _ green: Int, _ blue: Int) -> UIColor {
    .init(red: red, green: green, blue: blue)
}
private struct UIImage: Equatable { let named: String }
private final class Label {
    var isHidden = false
    var text: String?
}
private final class ImageView {
    var isHidden = false
    var image: UIImage?
}
private class UICollectionViewCell {
    var backgroundColor: UIColor?
    func prepareForReuse() {}
}
private final class GroupsViewCell: UICollectionViewCell {
    let imageView = ImageView(), imageLabel = Label(), nameLabel = Label()
    // PRODUCTION_CELL
}
private final class UICollectionView {
    var visibleCells: [UICollectionViewCell] = []
}
private class UIViewController {
    func viewWillAppear(_ animated: Bool) {}
    func viewWillDisappear(_ animated: Bool) {}
    func viewDidLayoutSubviews() {}
}

private func SCRYFrom(_ value: CGFloat) -> CGFloat { value }
private struct SceneInsets { var left: CGFloat = 0, right: CGFloat = 0, top: CGFloat = 0, bottom: CGFloat = 0 }
private final class SceneHeightConstraint {
    var value: CGFloat = 0, updates = 0
    func equalTo(_ value: CGFloat) { self.value = value; updates += 1 }
}
private final class SceneConstraints {
    let height = SceneHeightConstraint()
    func updateConstraints(_ body: (SceneConstraints) -> Void) { body(self) }
}
private final class SceneLayoutCollection {
    var width: CGFloat = 800
    var contentInset = SceneInsets()
    let snp = SceneConstraints()
    func layoutIfNeeded() {}
}
private final class SceneFlowLayout {
    var itemSize = CGSize.zero
    var minimumInteritemSpacing: CGFloat = 20, minimumLineSpacing: CGFloat = 20
    var sectionInset = SceneInsets(left: 40, right: 40, top: 44, bottom: 44)
}
private class ScenePageProbe: UIViewController {
    var refreshData = true, isPageVisible = false, reloads = 0, appearanceRefreshes = 0, statusRefreshes = 0
    var renderedRevision: SpacePageRevision?
    let syncDisplay = SceneGroupDisplayState()
    func updateUI() { reloads += 1; refreshData = false; renderedRevision = SpacePageRevision() }
    func refreshVisibleAppearance() { appearanceRefreshes += 1 }
    func refreshSyncStatus() { statusRefreshes += 1 }
}
private final class SceneViewController: ScenePageProbe {
    let collectionView = SceneLayoutCollection(), flowLayout = SceneFlowLayout()
    let rowNum = 6, columnNum = 4
    // PRODUCTION_SCENE_APPEAR
    // PRODUCTION_SCENE_LAYOUT
}
private final class SceneSettingsViewController: ScenePageProbe {
    // PRODUCTION_SCENE_SETTINGS_APPEAR
}

extension NodeSyncStatusRefreshTests {
    static func scenePresentationLayoutTests() {
        _ = fixture(1)
        let page = SceneViewController(), settings = SceneSettingsViewController()
        page.viewWillAppear(false); settings.viewWillAppear(false)
        require(page.reloads == 1 && settings.reloads == 1, "first Scene presentation did not prepare data")
        for _ in 0..<20 { page.viewDidLayoutSubviews() }
        require(page.reloads == 1 && page.collectionView.snp.height.updates == 1,
                "unchanged modal layout reloaded data or updated constraints repeatedly")
        let height = page.collectionView.snp.height.value
        page.collectionView.width = 600
        page.viewDidLayoutSubviews()
        require(page.collectionView.snp.height.updates == 2 && page.collectionView.snp.height.value < height
                && page.reloads == 1, "resizing did not update layout independently of data")
        page.viewWillDisappear(false); settings.viewWillDisappear(false)
        require(!page.isPageVisible && !settings.isPageVisible, "hidden Scene page remained active")
        page.viewWillAppear(false); settings.viewWillAppear(false)
        require(page.reloads == 1 && settings.reloads == 1 && page.appearanceRefreshes == 1
                && settings.appearanceRefreshes == 1, "unchanged reentry did not preserve data and refresh live appearance")
        NodeSyncStatusGeneration.invalidate()
        page.viewWillAppear(false); settings.viewWillAppear(false)
        require(page.reloads == 2 && settings.reloads == 2, "configuration change did not refresh Scene pages")
        print("PASS: Scene initial display, repeated layout, resize, hidden/reentry and version refresh bodies")
    }
}
private final class GroupsViewController: UIViewController {
    let collectionView = UICollectionView()
    var refreshData = false, isPageVisible = false, reloads = 0
    var renderedRevision: SpacePageRevision? = SpacePageRevision()
    func updateUI() { reloads += 1 }
    // PRODUCTION_APPEAR
    // PRODUCTION_VISIBLE
    // PRODUCTION_DISPLAY
}

extension NodeSyncStatusRefreshTests {
    static func groupsLiveAppearanceTests() async {
        let network = fixture(2), owner = NSObject(), markerOwner = NSObject()
        let group = network.groups[0], cell = GroupsViewCell(), page = GroupsViewController()
        group.info.imageText = "Group"
        NodeSyncStatusRefresh.beginSession(owner: owner)
        defer { NodeSyncStatusRefresh.endSession(owner: owner) }
        network.nodes[0].isOn = true
        cell.group = group
        require(cell.backgroundColor == .white, "binding did not publish live on immediately")
        page.collectionView.visibleCells = [cell]
        var done = false
        NodeSyncStatusRefresh.request(group: group, owner: markerOwner) { _ in done = true }
        await drain { done }
        let reads = Model.subscriptionReads, checks = network.nodes.reduce(0) { $0 + $1.checks }
        network.nodes[0].isOn = false // Main changes live state only.
        page.viewWillAppear(false)
        require(page.reloads == 0 && cell.backgroundColor == RGB(226, 226, 226), "unchanged page retained stale on background")
        network.nodes[1].isOn = true
        page.viewWillAppear(false)
        require(page.reloads == 0 && cell.backgroundColor == .white, "reentry did not reflect a newly lit member")
        network.nodes[1].isOn = false
        page.collectionView(page.collectionView, willDisplay: cell, forItemAt: IndexPath(index: 0))
        require(cell.backgroundColor == RGB(226, 226, 226), "willDisplay retained prefetch background")
        require(Model.subscriptionReads == reads && network.nodes.reduce(0, { $0 + $1.checks }) == checks,
                "appearance caused member/sync recomputation")

        // Both unavailable-revision and unavailable-topology callbacks must
        // leave live off appearance intact while publishing a sync warning.
        for invalidRevision in [true, false] {
            ConfigurationSnapshotRevision.value = invalidRevision ? nil : 1
            SpaceData.current!.triggerZonesLoadFailed = !invalidRevision
            cell.group = group
            require(cell.backgroundColor == RGB(226, 226, 226), "unavailable binding initially displayed on")
            await drain { !cell.imageView.isHidden && cell.imageView.image == UIImage(named: "sync_failed_big") }
            require(cell.backgroundColor == RGB(226, 226, 226) && cell.imageLabel.isHidden,
                    "unavailable sync changed off background or lost warning")
            group.isOn = true; cell.refreshOnOffAppearance()
            require(cell.backgroundColor == .white && cell.imageLabel.isHidden, "live refresh erased warning")
            group.isOn = false; cell.refreshOnOffAppearance()
            require(cell.backgroundColor == RGB(226, 226, 226), "local off waited for sync availability")
        }
        ConfigurationSnapshotRevision.value = 2
        SpaceData.current!.triggerZonesLoadFailed = false
        cell.group = group
        cell.prepareForReuse()
        let replacement = Group(0xC002); replacement.network = network
        replacement.info.imageText = "Replacement"; network.groups.append(replacement)
        cell.group = replacement
        done = false
        NodeSyncStatusRefresh.request(group: replacement, owner: markerOwner) { _ in done = true }
        await drain { done }
        require(cell.backgroundColor == .white && cell.imageLabel.text == "Replacement" && cell.imageView.isHidden,
                "old callback overwrote reused Cell or empty Group changed appearance")
        ConfigurationSnapshotRevision.value = 3
        page.viewWillAppear(false)
        require(page.reloads == 1, "configuration invalidation no longer reloads the page")
    }
}
#endif
