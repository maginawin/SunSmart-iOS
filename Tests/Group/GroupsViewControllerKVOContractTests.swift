import Foundation

@main
struct GroupsViewControllerKVOContractTests {

    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            fatalError("Expected the GroupsViewController.swift path")
        }

        let source = try String(
            contentsOfFile: CommandLine.arguments[1],
            encoding: .utf8
        )

        require(
            source.contains("private var networkableObservation: NSKeyValueObservation?"),
            "GroupsViewController must retain an optional KVO observation token"
        )

        let observation = section(
            in: source,
            from: "networkableObservation = NetworkRequest.shared.observe",
            to: "/// 申请地址提示"
        )
        require(
            observation.contains("NetworkRequest.shared.observe(\\.networkable"),
            "GroupsViewController must observe networkable with token-based KVO"
        )
        require(
            observation.contains("[weak self]"),
            "The networkable observation must not retain GroupsViewController"
        )
        require(
            observation.contains("DispatchQueue.main.async {"),
            "The networkable observation must enter the main queue before presenting UI"
        )
        require(
            !source.contains("NetworkRequest.shared.addObserver(self, forKeyPath: \"networkable\""),
            "GroupsViewController must not register networkable with manual KVO"
        )
        require(
            !source.contains("NetworkRequest.shared.removeObserver(self, forKeyPath: \"networkable\""),
            "GroupsViewController must not remove a possibly unregistered manual KVO observer"
        )
        require(
            !source.contains("override func observeValue"),
            "GroupsViewController must not retain its legacy unscoped KVO callback"
        )

        print("GroupsViewControllerKVOContractTests passed")
    }

    private static func section(
        in source: String,
        from startMarker: String,
        to endMarker: String
    ) -> String {
        guard let startRange = source.range(of: startMarker) else {
            preconditionFailure("Missing source marker: \(startMarker)")
        }
        let remainder = source[startRange.lowerBound...]
        guard let endRange = remainder.range(of: endMarker) else {
            preconditionFailure("Missing source marker: \(endMarker)")
        }
        return String(remainder[..<endRange.lowerBound])
    }

    private static func require(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) {
        precondition(condition(), message)
    }
}
