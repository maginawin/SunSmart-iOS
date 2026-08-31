import Foundation

@main
struct SceneExecuteDataPickerThemeContractTests {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            fatalError("Expected SceneExecuteDataPickerView source path")
        }

        let source = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)

        require(
            source.contains("offBtn.backgroundColor = isOff ? Bar_Color : .white"),
            "Selected OFF background must use the current brand Bar_Color"
        )
        require(
            source.contains("offBtn.setTitleColor(isOff ? .white : Bar_Color, for: .normal)"),
            "Unselected OFF title must use the current brand Bar_Color"
        )
        require(
            source.contains("offBtn.layer.borderColor = Bar_Color.withAlphaComponent(0.6).cgColor"),
            "Unselected OFF border must derive from the current brand Bar_Color"
        )
        require(
            source.contains("titleColor: Bar_Color"),
            "OFF button initialization must not start with a fixed SunSmart title color"
        )
        require(
            !source.contains("offBtn.backgroundColor = isOff ? RGB(102, 103, 171) : .white") &&
                !source.contains("offBtn.layer.borderColor = RGB(147, 148, 196).cgColor"),
            "Scene OFF styling must not retain the fixed SunSmart RGB values"
        )

        print("SceneExecuteDataPickerThemeContractTests passed")
    }

    private static func require(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) {
        guard condition() else { fatalError(message) }
    }
}
