import Foundation

@main
struct LBXScanNavigationLifecycleContractTests {

    static func main() throws {
        guard CommandLine.arguments.count == 4 else {
            fatalError(
                "Expected paths for LBXScanViewController.swift, "
                    + "SitesViewController.swift, and EnOceanProxyViewController.swift"
            )
        }

        let scannerSource = try source(at: CommandLine.arguments[1])
        let sitesSource = try source(at: CommandLine.arguments[2])
        let enOceanProxySource = try source(at: CommandLine.arguments[3])

        let scannerStatusBarBody = try declarationBody(
            containing: "var prefersStatusBarHidden:",
            in: scannerSource
        )
        require(
            scannerStatusBarBody.contains("return true"),
            "LBXScanViewController must keep its full-screen status bar hidden"
        )

        let scannerAppearBody = try methodBody(
            named: "viewWillAppear",
            in: scannerSource
        )
        require(
            scannerAppearBody.contains(
                "navigationController?.setNavigationBarHidden(true, animated: true)"
            ),
            "LBXScanViewController must keep its navigation bar hidden while visible"
        )

        let scannerDisappearBody = try methodBody(
            named: "viewWillDisappear",
            in: scannerSource
        )
        require(
            scannerDisappearBody.contains("super.viewWillDisappear(animated)"),
            "LBXScanViewController must forward viewWillDisappear to UIViewController"
        )
        require(
            scannerDisappearBody.contains("setNavigationBarHidden(false"),
            "LBXScanViewController must preserve navigation-bar restoration for legacy push callers"
        )

        let dismissBody = try methodBody(
            named: "dismissScanViewController",
            in: scannerSource
        )
        require(
            dismissBody.contains("presentingViewController != nil")
                && dismissBody.contains("dismiss(animated: animated, completion: completion)"),
            "LBXScanViewController must dismiss itself when presented modally"
        )
        require(
            dismissBody.contains("navigationController?.popViewController(animated: animated)"),
            "LBXScanViewController must preserve push/pop compatibility"
        )

        let backActionBody = try methodBody(named: "backAction", in: scannerSource)
        require(
            backActionBody.contains("dismissScanViewController(animated: true)"),
            "The scanner back button must use the unified exit path"
        )

        let resultBody = try methodBody(named: "handleCodeResult", in: scannerSource)
        require(
            resultBody.contains("dismissScanViewController(animated: true)"),
            "Automatic scan completion must use the unified exit path"
        )

        try requireFullScreenScannerPresentation(
            in: sitesSource,
            controllerName: "SitesViewController"
        )
        try requireFullScreenScannerPresentation(
            in: enOceanProxySource,
            controllerName: "EnOceanProxyViewController"
        )

        print("LBXScanNavigationLifecycleContractTests passed")
    }

    private static func source(at path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    private static func requireFullScreenScannerPresentation(
        in source: String,
        controllerName: String
    ) throws {
        let scanBody = try methodBody(named: "scanQRCode", in: source)
        require(
            scanBody.contains("vc.modalPresentationStyle = .fullScreen"),
            "\(controllerName) must configure the scanner as full screen"
        )
        require(
            scanBody.contains("present(vc, animated: true)"),
            "\(controllerName) must present the scanner modally"
        )
        require(
            !scanBody.contains("pushViewController(vc"),
            "\(controllerName) must not push the scanner onto its business navigation stack"
        )
        require(
            source.contains("dismissScanViewController"),
            "\(controllerName) must close the scanner through its modal-aware exit path"
        )
    }

    private static func methodBody(
        named name: String,
        in source: String
    ) throws -> Substring {
        let signature = "func \(name)("
        guard source.range(of: signature) != nil else {
            throw ContractError.missingMethod(name)
        }

        return try declarationBody(containing: signature, in: source)
    }

    private static func declarationBody(
        containing marker: String,
        in source: String
    ) throws -> Substring {
        guard let markerRange = source.range(of: marker),
              let openingBrace = source[markerRange.upperBound...].firstIndex(of: "{") else {
            throw ContractError.missingMethod(marker)
        }

        var depth = 0
        var index = openingBrace
        while index < source.endIndex {
            switch source[index] {
            case "{":
                depth += 1
            case "}":
                depth -= 1
                if depth == 0 {
                    return source[openingBrace...index]
                }
            default:
                break
            }
            index = source.index(after: index)
        }

        throw ContractError.unterminatedMethod(marker)
    }

    private static func require(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) {
        precondition(condition(), message)
    }

    private enum ContractError: Error {
        case missingMethod(String)
        case unterminatedMethod(String)
    }
}
