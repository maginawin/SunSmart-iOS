import Foundation

private enum TestFailure: Error, CustomStringConvertible {
    case assertion(String)

    var description: String {
        switch self {
        case .assertion(let message):
            return message
        }
    }
}

@main
struct SceneDeleteCapabilityTests {
    static func main() throws {
        try expect(
            SceneDeleteCapability.isSupported(sceneSetupModel: "scene-setup"),
            "A Scene Setup Model must enable Scene Delete evaluation even without a Scheduler Model."
        )
        try expect(
            !SceneDeleteCapability.isSupported(sceneSetupModel: Optional<String>.none),
            "A node without a Scene Setup Model must not generate Scene Delete operations."
        )
        print("SceneDeleteCapabilityTests passed")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else {
            throw TestFailure.assertion(message)
        }
    }
}
