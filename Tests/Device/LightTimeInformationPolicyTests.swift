import Foundation

@main
struct LightTimeInformationPolicyTests {

    static func main() {
        require(
            LightTimeInformationPolicy.preparation(
                supportsTimeGet: false,
                knowsApplicationKey: true,
                localTimeClientReady: true,
                timeServerBound: true,
                canConfigureTimeServer: true
            ) == .unsupported,
            "A light without Time Server must be shown as unsupported"
        )
        require(
            LightTimeInformationPolicy.preparation(
                supportsTimeGet: true,
                knowsApplicationKey: false,
                localTimeClientReady: true,
                timeServerBound: false,
                canConfigureTimeServer: true
            ) == .missingApplicationKey,
            "A missing Node AppKey must fail closed"
        )
        require(
            LightTimeInformationPolicy.preparation(
                supportsTimeGet: true,
                knowsApplicationKey: true,
                localTimeClientReady: false,
                timeServerBound: true,
                canConfigureTimeServer: true
            ) == .localTimeClientUnavailable,
            "Time Client must be ready before TimeGet"
        )
        require(
            LightTimeInformationPolicy.preparation(
                supportsTimeGet: true,
                knowsApplicationKey: true,
                localTimeClientReady: true,
                timeServerBound: true,
                canConfigureTimeServer: false
            ) == .ready,
            "An already configured light remains readable without edit permission"
        )
        require(
            LightTimeInformationPolicy.preparation(
                supportsTimeGet: true,
                knowsApplicationKey: true,
                localTimeClientReady: true,
                timeServerBound: false,
                canConfigureTimeServer: true
            ) == .bindTimeServer,
            "An editor may repair the Time Server binding"
        )
        require(
            LightTimeInformationPolicy.preparation(
                supportsTimeGet: true,
                knowsApplicationKey: true,
                localTimeClientReady: true,
                timeServerBound: false,
                canConfigureTimeServer: false
            ) == .configurationNotAllowed,
            "A read-only user must not modify the remote Time Server"
        )

        print("LightTimeInformationPolicyTests passed")
    }

    private static func require(
        _ condition: @autoclosure () -> Bool,
        _ message: String,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        guard condition() else {
            fatalError(message, file: file, line: line)
        }
    }
}
