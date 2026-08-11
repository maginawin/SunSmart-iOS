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
                toast.contains("equalTo(44)") &&
                toast.contains("equalTo(30)") &&
                toast.contains("equalTo(16)"),
            "Site Update Toast must encode 16pt margins, 343pt max width, 44pt height, and 30/16pt icon sizes"
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
                !standard.contains("baselineOffset") &&
                !standard.contains("CGAffineTransform"),
            "Standard Toast must center natural-height text and icon without visual offsets"
        )
        require(
            siteUpdate.contains("messageLabel.text = message") &&
                siteUpdate.contains("messageLabel.font = font") &&
                siteUpdate.contains("messageLabel.snp.makeConstraints") &&
                siteUpdate.contains("make.height.equalTo(22)") &&
                siteUpdate.contains("stackView.alignment = .center") &&
                !siteUpdate.contains("minimumLineHeight") &&
                !siteUpdate.contains("maximumLineHeight") &&
                !siteUpdate.contains("messageLabel.attributedText") &&
                !siteUpdate.contains("baselineOffset") &&
                !siteUpdate.contains("CGAffineTransform"),
            "Site Update Toast must center natural-height text in its 22pt text area without visual offsets"
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
        require(
            edit.contains("typealias SiteReturnCompletion = (UIView) -> Void") &&
                edit.contains("typealias ReturnToSitesHandler = (@escaping SiteReturnCompletion) -> Void") &&
                edit.contains("private let returnToSitesHandler: ReturnToSitesHandler"),
            "Edit Site must require an escaping route completion that returns the final host view"
        )
        require(
            ordinary.contains("returnToSites {") &&
                ordinary.contains("toastHost in") &&
                ordinary.contains("ToastStatusView.show") &&
                ordinary.contains("appearance: .siteUpdate") &&
                ordinary.contains("\"site_updated_toast\".localizedString") &&
                ordinary.contains("\"site_update_failed_toast\".localizedString") &&
                !ordinary.contains("XWHUDManager"),
            "Ordinary update results must use the Site Update Toast on the returned Sites host"
        )
        require(
            occurrences(of: "XWHUDManager.showErrorTipHUD", in: edit) == 1 &&
                edit.contains("SiteTimeZoneSyncStatusView"),
            "Only local persistence failure keeps the old HUD and timezone keeps its status card"
        )
        require(
            sites.contains("returnToSitesHandler:") &&
                sites.contains("completion(self.view)"),
            "Sites entry must pass its visible view after modal dismissal"
        )
        require(
            site.contains("returnToSitesHandler:") &&
                site.contains("transitionCoordinator") &&
                site.contains("context.isCancelled") &&
                site.contains("completion(destinationView)") &&
                site.contains("assertionFailure"),
            "Site entry must wait for pop completion and provide a safe visible host"
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
