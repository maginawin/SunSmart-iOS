import Foundation

@main
struct SiteTimeZoneReviewSyncContractTests {

    static func main() throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 9 else {
            fatalError(
                "Expected review view, header, Site controller, Sync gateways " +
                    "controller, English, Chinese, project, and warning asset paths"
            )
        }

        let reviewView = try String(contentsOfFile: arguments[1], encoding: .utf8)
        let header = try String(contentsOfFile: arguments[2], encoding: .utf8)
        let siteController = try String(contentsOfFile: arguments[3], encoding: .utf8)
        let syncController = try String(contentsOfFile: arguments[4], encoding: .utf8)
        let english = try String(contentsOfFile: arguments[5], encoding: .utf8)
        let simplifiedChinese = try String(contentsOfFile: arguments[6], encoding: .utf8)
        let project = try String(contentsOfFile: arguments[7], encoding: .utf8)
        let warningAsset = try String(contentsOfFile: arguments[8], encoding: .utf8)

        require(reviewView.contains("final class SiteTimeZoneReviewSyncView: UIView"))
        require(reviewView.contains("RGB(255, 249, 239)"))
        require(reviewView.contains("layer.cornerRadius = SCRYFrom(14)"))
        require(reviewView.contains("UIImage(named: \"site_entry_sync_warning\")"))
        require(reviewView.contains("make.size.equalTo(SCRYFrom(16))"))
        require(reviewView.contains("RGB(100, 116, 139)"))
        require(reviewView.contains("RGB(151, 60, 0)"))
        require(reviewView.contains("make.height.equalTo(SCRYFrom(28))"))
        require(reviewView.contains("numberOfLines = 2"))
        require(reviewView.contains("var onReviewSync: (() -> Void)?"))

        for key in [
            "site_time_zone_review_sync_single",
            "site_time_zone_review_sync_multiple",
            "site_time_zone_review_sync_action"
        ] {
            require(
                occurrences(of: "\"\(key)\" =", in: english) == 1,
                "English must define \(key) exactly once"
            )
            require(
                occurrences(of: "\"\(key)\" =", in: simplifiedChinese) == 1,
                "Simplified Chinese must define \(key) exactly once"
            )
            require(
                reviewView.contains("\"\(key)\".localizedString"),
                "Review view must consume \(key)"
            )
        }

        require(header.contains("let timeZoneReviewSyncView = SiteTimeZoneReviewSyncView()"))
        require(header.contains("var timeZoneReviewState: SiteTimeZoneReviewState"))
        require(header.contains("var onReviewSync: (() -> Void)?"))
        require(header.contains("timeZoneReviewSyncView.isHidden = true"))
        require(siteController.contains("headerView.timeZoneReviewState = timeZoneReviewState"))
        require(siteController.contains("SiteGatewayHeaderLayoutPolicy.height("))
        require(
            siteController.contains("private func siteGatewayHeaderHeight(") &&
                occurrences(
                    of: "siteGatewayHeaderHeight(for:",
                    in: siteController
                ) == 2,
            "Header size and empty frame must share one height calculation"
        )
        require(
            occurrences(of: "emptyFrame(", in: siteController) == 4,
            "Three empty states must use the shared empty frame helper"
        )
        require(
            !siteController.contains("SCRYFrom(96)"),
            "Empty states must not retain the pre-review fixed header offset"
        )
        let reviewStateSetter = sourceSection(
            in: siteController,
            from: "private func setTimeZoneReviewState(",
            to: "private func setEntrySyncNavigationLocked("
        )
        require(
            appearsInOrder(
                [
                    "timeZoneReviewState = state",
                    "favouritesCollectionView.reloadData()",
                    "updateEmptyView()"
                ],
                in: reviewStateSetter
            ),
            "Review state changes must refresh existing empty frames"
        )
        require(siteController.contains("headerView.onReviewSync = { [weak self] in"))
        require(siteController.contains("self?.showSyncGatewaysPage()"))
        require(siteController.contains("private func showSyncGatewaysPage()"))
        require(siteController.contains("latestTimeZoneRemoteSnapshot"))
        require(siteController.contains("SyncGatewaysContextBuilder.make("))
        require(siteController.contains("SyncGatewaysViewController("))
        require(siteController.contains("context: context"))
        require(siteController.contains("cloudBridge: syncGatewaysCloudBridge"))
        require(siteController.contains("canStartSync:"))
        require(siteController.contains("navigationController?.pushViewController(controller, animated: true)"))

        require(syncController.contains("final class SyncGatewaysViewController: UIViewController"))
        require(syncController.contains("init("))
        require(syncController.contains("context: SyncGatewaysContext"))
        require(syncController.contains("cloudBridge: SyncGatewaysCloudBridge"))
        require(syncController.contains("canStartSync: @escaping (SyncGatewayRuntimeTarget) -> Bool"))
        require(!syncController.contains("override init("))
        require(syncController.contains("title = \"site_sync_gateways_title\".localizedString"))
        require(syncController.contains("view.backgroundColor = SyncGatewaysCopy.pageBackgroundColor"))
        require(
            occurrences(of: "\"site_sync_gateways_title\" =", in: english) == 1,
            "English must define site_sync_gateways_title exactly once"
        )
        require(
            occurrences(of: "\"site_sync_gateways_title\" =", in: simplifiedChinese) == 1,
            "Simplified Chinese must define site_sync_gateways_title exactly once"
        )

        require(
            occurrences(
                of: "SiteTimeZoneReviewSyncView.swift in Sources",
                in: project
            ) == 8,
            "Review view must belong to all four app targets"
        )
        for targetSuffix in 1...4 {
            require(
                occurrences(
                    of: "F260813000000000000140\(targetSuffix) /* SiteTimeZoneReviewSyncView.swift in Sources */",
                    in: project
                ) == 2,
                "Review view must be declared and referenced by target \(targetSuffix)"
            )
        }
        require(
            occurrences(of: "SyncGatewaysViewController.swift in Sources", in: project) == 8,
            "Sync gateways controller must belong to all four app targets"
        )
        for targetSuffix in 1...4 {
            require(
                occurrences(
                    of: "F260813000000000000150\(targetSuffix) /* SyncGatewaysViewController.swift in Sources */",
                    in: project
                ) == 2,
                "Sync gateways controller must be declared and referenced by target \(targetSuffix)"
            )
        }
        require(
            occurrences(
                of: "SiteGatewayHeaderLayoutPolicy.swift in Sources",
                in: project
            ) == 8,
            "Header layout policy must belong to all four app targets"
        )
        for targetSuffix in 1...4 {
            require(
                occurrences(
                    of: "F260814000000000000290\(targetSuffix) /* SiteGatewayHeaderLayoutPolicy.swift in Sources */",
                    in: project
                ) == 2,
                "Header layout policy must be declared and referenced by target \(targetSuffix)"
            )
        }
        require(
            warningAsset.contains("site_entry_sync_warning.svg") &&
                warningAsset.contains("preserves-vector-representation"),
            "Review view must reuse the existing vector warning asset"
        )

        print("SiteTimeZoneReviewSyncContractTests passed")
    }

    private static func occurrences(of needle: String, in text: String) -> Int {
        guard !needle.isEmpty else { return 0 }
        var count = 0
        var searchRange = text.startIndex..<text.endIndex
        while let range = text.range(of: needle, range: searchRange) {
            count += 1
            searchRange = range.upperBound..<text.endIndex
        }
        return count
    }

    private static func appearsInOrder(
        _ needles: [String],
        in text: String
    ) -> Bool {
        var searchStart = text.startIndex
        for needle in needles {
            guard let range = text.range(
                of: needle,
                range: searchStart..<text.endIndex
            ) else {
                return false
            }
            searchStart = range.upperBound
        }
        return true
    }

    private static func sourceSection(
        in source: String,
        from start: String,
        to end: String
    ) -> String {
        guard let startRange = source.range(of: start),
              let endRange = source.range(
                  of: end,
                  range: startRange.upperBound..<source.endIndex
              ) else {
            return ""
        }
        return String(source[startRange.lowerBound..<endRange.lowerBound])
    }

    private static func require(
        _ condition: @autoclosure () -> Bool,
        _ message: String = "Review sync contract failed"
    ) {
        guard condition() else { fatalError(message) }
    }
}
