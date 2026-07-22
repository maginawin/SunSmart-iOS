import Foundation

@main
struct DeviceNameFilterMenuViewContractTests {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            fatalError("Expected DeviceNameFilterMenuView.swift path")
        }

        let source = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)

        require(source.contains("private static let dividerHeight ="),
                "Divider should define the only divider-area height")
        require(!source.contains("dividerAreaHeight"),
                "Divider should not retain a taller parent area")
        require(source.contains("height: Self.dividerHeight"),
                "Divider parent and divider should both use dividerHeight")
        require(source.contains("y: 0,"),
                "Divider should start at the top of its same-height parent")
        require(source.contains("Self.rowHeight + Self.dividerHeight"),
                "Reset row should start immediately after the divider")
        require(!source.contains("contentEdgeInsets"),
                "Filter menu buttons should not use the deprecated contentEdgeInsets API")
        require(source.contains("var configuration = UIButton.Configuration.plain()"),
                "Filter menu buttons should use UIButton.Configuration")
        require(source.contains("configuration.title = title"),
                "Button title should be owned by the configuration")
        require(source.contains("configuration.baseForegroundColor = .white"),
                "Configuration should preserve the white title color")
        require(source.contains("configuration.contentInsets = NSDirectionalEdgeInsets("),
                "Configuration should own the directional content insets")
        require(source.contains("leading: SCRXFrom(16)"),
                "Configuration should preserve the leading inset")
        require(source.contains("trailing: SCRXFrom(16)"),
                "Configuration should preserve the trailing inset")
        require(source.contains("UIButton(configuration: configuration, primaryAction: nil)"),
                "Button should be created with the configuration")

        print("DeviceNameFilterMenuViewContractTests passed")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
    }
}
