import Foundation

@main
struct SiteEditAlertTransitionContractTests {

    static func main() throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 3 else {
            fatalError("Expected mode and source path")
        }

        switch arguments[1] {
        case "component":
            try testAlertComponent(path: arguments[2])
        case "edit-site":
            try testEditSiteRouting(path: arguments[2])
        default:
            fatalError("Unknown mode: \(arguments[1])")
        }

        print("SiteEditAlertTransitionContractTests passed")
    }

    private static func testAlertComponent(path: String) throws {
        let source = try String(contentsOfFile: path, encoding: .utf8)
        let dismiss = substring(
            in: source,
            from: "public func dismiss(",
            through: "/// 更新进度条进度"
        )
        let actionRouting = substring(
            in: source,
            from: "private func handleAction(_ action: SRAlertAction)",
            through: "/// 左侧按钮点击"
        )
        let buttonRouting = substring(
            in: source,
            from: "@objc private func firstBtnClick()",
            through: "/// 点击背景遮罩"
        )
        let actionType = substring(
            in: source,
            from: "struct SRAlertAction",
            through: "extension SRAlertView"
        )

        require(
            dismiss.contains("completion: (() -> Void)? = nil") &&
                appearsInOrder(
                    ["let finishDismiss", "self?.removeFromSuperview()", "completion?()"],
                    in: dismiss
                ) &&
                occurrences(of: "finishDismiss()", in: dismiss) == 2,
            "Dismiss must remove the alert before completing in animated and immediate paths"
        )
        require(
            actionType.contains("var performsActionAfterDismiss: Bool = false") &&
                actionType.contains("performsActionAfterDismiss: Bool = false") &&
                actionType.contains("self.performsActionAfterDismiss = performsActionAfterDismiss"),
            "SRAlertAction must expose an opt-in flag that defaults to false"
        )
        require(
            actionRouting.contains("action.closeAlert && action.performsActionAfterDismiss") &&
                appearsInOrder(
                    [
                        "dismiss(animation: action.hideAnimation) {",
                        "action.actionHandler?(action)",
                        "} else {",
                        "action.actionHandler?(action)",
                        "if action.closeAlert",
                        "dismiss(animation: action.hideAnimation)"
                    ],
                    in: actionRouting
                ),
            "Opt-in actions must run in dismiss completion while legacy actions keep their order"
        )
        require(
            occurrences(of: "handleAction(action)", in: buttonRouting) == 2,
            "Left and right alert buttons must use the same action routing"
        )
    }

    private static func testEditSiteRouting(path: String) throws {
        let source = try String(contentsOfFile: path, encoding: .utf8)
        let online = substring(
            in: source,
            from: "private func showTimeZoneConfirmation()",
            through: "private func showOfflineTimeZoneAlert()"
        )
        let offline = substring(
            in: source,
            from: "private func showOfflineTimeZoneAlert()",
            through: "private func performCommit(online: Bool)"
        )

        require(
            online.contains(".cancelAction") &&
                online.contains("performsActionAfterDismiss: true") &&
                online.contains("self?.performCommit(online: true)"),
            "Online timezone confirmation must dismiss fully before commit while Cancel remains non-committing"
        )
        require(
            offline.contains("performsActionAfterDismiss: true") &&
                offline.contains("self?.performCommit(online: false)"),
            "Offline timezone acknowledgement must dismiss fully before local commit"
        )
        require(
            occurrences(of: "performsActionAfterDismiss: true", in: source) == 2,
            "Only the two approved Edit Site actions may opt in"
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

    private static func appearsInOrder(_ needles: [String], in text: String) -> Bool {
        var remaining = text[text.startIndex...]
        for needle in needles {
            guard let range = remaining.range(of: needle) else { return false }
            remaining = remaining[range.upperBound...]
        }
        return true
    }

    private static func occurrences(of needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    private static func require(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) {
        guard condition() else { fatalError(message) }
    }
}
