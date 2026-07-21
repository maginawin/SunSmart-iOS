import Foundation

@main
struct WiFiGatewayCredentialMutationReducerTests {
    static let old = WiFiGatewayCredentialSnapshot(
        ssid: Data("old".utf8),
        password: Data("password".utf8)
    )
    static let target = WiFiGatewayCredentialSnapshot(
        ssid: Data("中文WiFi".utf8),
        password: Data("密码,PA\"ss".utf8)
    )

    static func main() {
        testSetConfirmed()
        testSetRecoveryReached()
        testSetRecoveryNotReachedAndUnknown()
        testClearConfirmedAndRecovery()
        testDuplicateInputsNeverResend()
        print("WiFiGatewayCredentialMutationReducerTests passed")
    }

    static func testSetConfirmed() {
        var reducer = WiFiGatewayCredentialMutationReducer()
        precondition(reducer.reduce(.start(.set(target: target))) == .sendSet(target))
        precondition(reducer.reduce(.mutationResponse(.confirmed)) == .setTargetReached)
    }

    static func testSetRecoveryReached() {
        var reducer = WiFiGatewayCredentialMutationReducer()
        _ = reducer.reduce(.start(.set(target: target)))
        precondition(reducer.reduce(.mutationResponse(.unconfirmed)) == .requestCredentials)
        precondition(
            reducer.reduce(.recoveryResponse(.credentials(target))) == .setTargetReached
        )
    }

    static func testSetRecoveryNotReachedAndUnknown() {
        var notReached = WiFiGatewayCredentialMutationReducer()
        _ = notReached.reduce(.start(.set(target: target)))
        _ = notReached.reduce(.mutationResponse(.unconfirmed))
        precondition(
            notReached.reduce(.recoveryResponse(.credentials(old))) == .setTargetNotReached
        )

        var unknown = WiFiGatewayCredentialMutationReducer()
        _ = unknown.reduce(.start(.set(target: target)))
        _ = unknown.reduce(.mutationResponse(.unconfirmed))
        precondition(unknown.reduce(.recoveryResponse(.unconfirmed)) == .setTargetUnknown)
    }

    static func testClearConfirmedAndRecovery() {
        var confirmed = WiFiGatewayCredentialMutationReducer()
        precondition(confirmed.reduce(.start(.clear(previous: old))) == .sendClear)
        precondition(confirmed.reduce(.mutationResponse(.confirmed)) == .clearTargetReached)

        var reached = WiFiGatewayCredentialMutationReducer()
        _ = reached.reduce(.start(.clear(previous: old)))
        precondition(reached.reduce(.mutationResponse(.unconfirmed)) == .requestCredentials)
        precondition(reached.reduce(.recoveryResponse(.notConfigured)) == .clearTargetReached)

        var notReached = WiFiGatewayCredentialMutationReducer()
        _ = notReached.reduce(.start(.clear(previous: old)))
        _ = notReached.reduce(.mutationResponse(.unconfirmed))
        precondition(
            notReached.reduce(.recoveryResponse(.credentials(old))) ==
                .clearTargetNotReached(old)
        )
    }

    static func testDuplicateInputsNeverResend() {
        var reducer = WiFiGatewayCredentialMutationReducer()
        precondition(reducer.reduce(.start(.set(target: target))) == .sendSet(target))
        precondition(reducer.reduce(.start(.set(target: target))) == .none)
        precondition(reducer.reduce(.mutationResponse(.unconfirmed)) == .requestCredentials)
        precondition(reducer.reduce(.mutationResponse(.unconfirmed)) == .none)
        precondition(reducer.reduce(.recoveryResponse(.unconfirmed)) == .setTargetUnknown)
        precondition(reducer.reduce(.recoveryResponse(.unconfirmed)) == .none)
    }
}
