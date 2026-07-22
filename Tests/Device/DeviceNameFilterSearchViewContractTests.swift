import Foundation

@main
struct DeviceNameFilterSearchViewContractTests {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            fatalError("Expected DeviceNameFilterSearchView.swift path")
        }

        let source = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)

        require(source.contains("private let searchBackgroundView = UIView()"),
                "Search field should have a dedicated fixed background view")
        require(source.contains("searchBackgroundView.addSubview(textField)"),
                "Text field should be inside the fixed search background")
        require(source.contains("searchBackgroundView.addSubview(cancelButton)"),
                "Cancel should be inside the fixed search background")
        require(source.contains("textField.borderStyle = .none"),
                "Text field should be borderless")
        require(source.contains("textField.backgroundColor = .clear"),
                "Text field should be transparent")
        require(!source.contains("textField.layer.border"),
                "Text field should not own the search field border")
        require(source.contains("searchBackgroundView.backgroundColor = RGB(248, 250, 252)"),
                "Fixed search background should use the Figma fill color")
        require(source.contains("searchBackgroundView.layer.borderColor = RGB(193, 207, 226).cgColor"),
                "Fixed search background should use the Figma border color")
        require(source.contains("searchBackgroundView.layer.cornerRadius = SCRYFrom(10)"),
                "Fixed search background should use the Figma corner radius")
        require(source.contains("cardView.layer.cornerRadius = SCRYFrom(16)"),
                "Search panel should use the Figma corner radius")
        require(source.contains("cardView.layer.shadowOffset = CGSize(width: 0, height: SCRYFrom(-4))"),
                "Search panel shadow should point upward as in Figma")
        require(source.contains("make.right.equalTo(SCRXFrom(-12))"),
                "Cancel should be 12 points from the search background right edge")
        require(source.contains("make.right.equalTo(cancelButton.snp.left).offset(SCRXFrom(-12))"),
                "Text field should be 12 points from the Cancel button")
        require(source.contains("cancelButton.setContentHuggingPriority(.required, for: .horizontal)"),
                "Cancel should keep its intrinsic width before text entry")
        require(source.contains("cancelButton.setContentCompressionResistancePriority(.required, for: .horizontal)"),
                "Cancel should not be compressed by the text field")
        require(source.contains("textField.setContentHuggingPriority(.defaultLow, for: .horizontal)"),
                "Text field should consume the remaining horizontal space")
        require(source.contains("textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)"),
                "Text field should remain the flexible horizontal element")

        print("DeviceNameFilterSearchViewContractTests passed")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
    }
}
