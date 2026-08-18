import Foundation

@main
struct SiteUpdateToastUIContractTests {

    static func main() throws {
        let arguments = CommandLine.arguments
        guard arguments.count >= 2 else {
            fatalError("Expected component or routing mode")
        }

        switch arguments[1] {
        case "component":
            guard arguments.count == 5 else {
                fatalError("Expected ToastStatusView and two imageset Contents paths")
            }
            try testComponent(arguments: arguments)
        case "routing":
            guard arguments.count == 8 else {
                fatalError("Expected Edit, Sites, Site, English, Chinese, and project paths")
            }
            try testRouting(arguments: arguments)
        default:
            fatalError("Unknown mode: \(arguments[1])")
        }

        print("SiteUpdateToastUIContractTests passed")
    }

    private static func testComponent(arguments: [String]) throws {
        let toast = try String(contentsOfFile: arguments[2], encoding: .utf8)
        let standard = substring(
            in: toast,
            from: "private func setupStandardUI",
            through: "private func setupSiteUpdateUI"
        )
        let siteUpdate = substring(
            in: toast,
            from: "private func setupSiteUpdateUI",
            through: "// MARK: - Show"
        )
        let show = substring(
            in: toast,
            from: "static func show(",
            through: "// Initial state"
        )

        require(
            toast.contains("enum Appearance") &&
                toast.contains("case standard") &&
                toast.contains("case siteUpdate") &&
                toast.contains("appearance: Appearance = .standard"),
            "Toast must add an opt-in Site Update appearance and keep Standard as default"
        )
        require(
            toast.contains("site_update_toast_success") &&
                toast.contains("site_update_toast_failure"),
            "Site Update appearance must use dedicated Figma assets"
        )
        require(
            toast.contains("equalToSuperview().offset(-32)") &&
                toast.contains("lessThanOrEqualTo(343)") &&
                toast.contains("equalTo(30)") &&
                toast.contains("equalTo(16)"),
            "Site Update Toast must encode 16pt margins, 343pt max width, and 30/16pt icon sizes"
        )
        require(
            toast.contains("systemFont(ofSize: 15, weight: .light)") &&
                toast.contains("stackView.spacing = 10") &&
                toast.contains("layer.cornerRadius = 13"),
            "Site Update Toast must encode the Figma typography, gap, and radius"
        )
        require(
            standard.contains("stackView.alignment = .center") &&
                standard.contains("messageLabel.text = message") &&
                standard.contains("messageLabel.numberOfLines = 0") &&
                standard.contains("messageLabel.lineBreakMode = .byWordWrapping") &&
                standard.contains("make.top.equalToSuperview().offset(12)") &&
                standard.contains("make.bottom.equalToSuperview().offset(-12)") &&
                standard.contains("make.centerX.equalToSuperview()") &&
                !standard.contains("messageLabel.numberOfLines = 2") &&
                !standard.contains("byTruncatingTail") &&
                !standard.contains("baselineOffset") &&
                !standard.contains("CGAffineTransform"),
            "Standard Toast must wrap all text and derive its height from centered content with 12pt vertical insets"
        )
        require(
            siteUpdate.contains("messageLabel.text = message") &&
                siteUpdate.contains("messageLabel.font = font") &&
                siteUpdate.contains("messageLabel.numberOfLines = 0") &&
                siteUpdate.contains("messageLabel.lineBreakMode = .byWordWrapping") &&
                siteUpdate.contains("stackView.alignment = .center") &&
                siteUpdate.contains("make.leading.greaterThanOrEqualToSuperview().offset(22)") &&
                siteUpdate.contains("make.trailing.lessThanOrEqualToSuperview().offset(-22)") &&
                siteUpdate.contains("make.top.equalToSuperview().offset(7)") &&
                siteUpdate.contains("make.bottom.equalToSuperview().offset(-7)") &&
                !siteUpdate.contains("messageLabel.numberOfLines = 1") &&
                !siteUpdate.contains("make.height.equalTo(22)") &&
                !siteUpdate.contains("byTruncatingTail") &&
                !siteUpdate.contains("minimumLineHeight") &&
                !siteUpdate.contains("maximumLineHeight") &&
                !siteUpdate.contains("messageLabel.attributedText") &&
                !siteUpdate.contains("baselineOffset") &&
                !siteUpdate.contains("CGAffineTransform"),
            "Site Update Toast must wrap all text and derive its height from centered content with preserved insets"
        )
        require(
            show.contains("make.height.greaterThanOrEqualTo(44)") &&
                !show.contains("make.height.equalTo(44)"),
            "Both Toast appearances must keep 44pt as a minimum height instead of a fixed height"
        )
        require(
            toast.contains("shadowOpacity = 0.15") &&
                toast.contains("height: 2") &&
                toast.contains("withAlphaComponent(0.6)"),
            "Site Update Toast must encode the Figma shadow and black overlay"
        )

        let successContents = try String(contentsOfFile: arguments[3], encoding: .utf8)
        let failureContents = try String(contentsOfFile: arguments[4], encoding: .utf8)
        require(
            successContents.contains("site_update_toast_success.svg") &&
                successContents.contains("preserves-vector-representation"),
            "Success imageset must preserve the exact Figma vector"
        )
        require(
            failureContents.contains("site_update_toast_failure.svg") &&
                failureContents.contains("preserves-vector-representation"),
            "Failure imageset must preserve the exact Figma vector"
        )
    }

    private static func testRouting(arguments: [String]) throws {
        let edit = try String(contentsOfFile: arguments[2], encoding: .utf8)
        let sites = try String(contentsOfFile: arguments[3], encoding: .utf8)
        let site = try String(contentsOfFile: arguments[4], encoding: .utf8)
        let english = try String(contentsOfFile: arguments[5], encoding: .utf8)
        let chinese = try String(contentsOfFile: arguments[6], encoding: .utf8)
        let project = try String(contentsOfFile: arguments[7], encoding: .utf8)

        let ordinary = substring(
            in: edit,
            from: "private func finishOrdinaryCommit",
            through: "private func finishTimeZoneCommit"
        )
        let timeZone = substring(
            in: edit,
            from: "private func finishTimeZoneCommit",
            through: "private func finishEditing"
        )
        let sitesEdit = substring(
            in: sites,
            from: "private func editSite(site: SiteData)",
            through: "/// 删除场所"
        )
        let siteEdit = substring(
            in: site,
            from: "private func editSite()",
            through: "/// 删除场所"
        )
        require(
            edit.contains("typealias SiteResultHostCompletion = (UIView) -> Void") &&
                edit.contains("typealias FinishEditingHandler = (@escaping SiteResultHostCompletion) -> Void") &&
                edit.contains("private let finishEditingHandler: FinishEditingHandler"),
            "Edit Site must require an escaping completion that returns the source result host"
        )
        require(
            ordinary.contains("finishEditing {") &&
                ordinary.contains("resultHost in") &&
                ordinary.contains("ToastStatusView.show") &&
                ordinary.contains("appearance: .siteUpdate") &&
                ordinary.contains("\"site_updated_toast\".localizedString") &&
                ordinary.contains("\"site_update_failed_toast\".localizedString") &&
                !ordinary.contains("XWHUDManager"),
            "Ordinary update results must use the Site Update Toast on the source result host"
        )
        require(
            timeZone.contains("SiteTimeZoneEditSyncCoordinator(") &&
                timeZone.contains("statusView.update(state: state)") &&
                !timeZone.contains("ToastStatusView.show") &&
                !timeZone.contains("\"site_updated_toast\".localizedString") &&
                !timeZone.contains("\"site_update_failed_toast\".localizedString"),
            "Timezone synchronization must not reuse or alter the ordinary update Toast route"
        )
        require(
            occurrences(of: "XWHUDManager.showErrorTipHUD", in: edit) == 1 &&
                edit.contains("SiteTimeZoneSyncStatusView"),
            "Only local persistence failure keeps the old HUD and timezone keeps its status card"
        )
        require(
            sitesEdit.contains("finishEditingHandler:") &&
                sitesEdit.contains("completion(self.view)") &&
                sitesEdit.contains("vc.timeZoneSyncDidFinish = { [weak self] _ in") &&
                sitesEdit.contains("self?.reloadSiteData(site)"),
            "Sites entry must pass its own visible view after modal dismissal"
        )
        require(
            siteEdit.contains("finishEditingHandler:") &&
                siteEdit.contains("completion(self.view)") &&
                siteEdit.contains("vc.timeZoneSyncDidFinish = { [weak self] outcome in") &&
                siteEdit.contains("self?.reconcileEditTimeZoneSyncOutcome(outcome)") &&
                !siteEdit.contains("popViewController") &&
                !siteEdit.contains("transitionCoordinator") &&
                !siteEdit.contains("SitesViewController"),
            "Site entry must keep the Site page and pass its own visible view"
        )
        require(
            english.contains("\"site_updated_toast\" = \"Site updated.\";") &&
                english.contains("\"site_update_failed_toast\" = \"Failed to update site.\";") &&
                chinese.contains("\"site_updated_toast\" = \"场所已更新。\";") &&
                chinese.contains("\"site_update_failed_toast\" = \"场所更新失败。\";"),
            "Site update copy must remain exact in both supported languages"
        )

        let sourcePhase = substring(
            in: project,
            from: "/* Begin PBXSourcesBuildPhase section */",
            through: "/* End PBXSourcesBuildPhase section */"
        )
        let resourcePhase = substring(
            in: project,
            from: "/* Begin PBXResourcesBuildPhase section */",
            through: "/* End PBXResourcesBuildPhase section */"
        )
        require(
            occurrences(of: "ToastStatusView.swift in Sources", in: sourcePhase) == 4 &&
                occurrences(of: "Localizable.strings in Resources", in: resourcePhase) == 4 &&
                occurrences(of: "/* Assets.xcassets in Resources */", in: resourcePhase) == 4,
            "Shared Toast, localization, and assets must remain available to all four targets"
        )
    }

    private static func substring(
        in text: String,
        from start: String,
        through end: String
    ) -> String {
        guard let startRange = text.range(of: start),
              let endRange = text.range(
                of: end,
                range: startRange.upperBound..<text.endIndex
              ) else {
            return ""
        }
        return String(text[startRange.lowerBound..<endRange.lowerBound])
    }

    private static func occurrences(of needle: String, in haystack: String) -> Int {
        return haystack.components(separatedBy: needle).count - 1
    }

    private static func require(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) {
        guard condition() else {
            fatalError(message)
        }
    }
}
