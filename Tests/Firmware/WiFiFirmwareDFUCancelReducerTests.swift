import Foundation

@main
struct WiFiFirmwareDFUCancelReducerTests {
    static func main() {
        testSendOnce()
        testSuccessAndTerminalEventOrder()
        testVerifyingRaceAndNotCancelledResponse()
        testOrdinaryNotCancelledStartsRecovery()
        testUnconfirmedAndReservedStartRecovery()
        testBusyStartsAuthoritativeRecovery()
        testPendingTimeoutAndRecoveryLimit()
        testRecoveryObservations()
        testUnknownPolling()
        testResumeBehavior()
        testTimingConstants()
        print("WiFiFirmwareDFUCancelReducerTests passed")
    }

    private static func testSendOnce() {
        var reducer = WiFiFirmwareDFUCancelReducer()
        precondition(reducer.reduce(.sent) == .none)
        precondition(reducer.state.phase == .pending)
        precondition(reducer.state.hasAttempted)
        precondition(reducer.state.blocksNewStart)
        precondition(reducer.reduce(.sent) == .none)
        precondition(reducer.state.phase == .pending)
    }

    private static func testSuccessAndTerminalEventOrder() {
        var responseFirst = WiFiFirmwareDFUCancelReducer(
            state: .init(phase: .pending)
        )
        precondition(responseFirst.reduce(.response(.success)) == .cancellationSucceeded)
        precondition(responseFirst.state.phase == .resolved)
        precondition(responseFirst.reduce(.matchedStatus(.cancelled)) == .none)

        var eventFirst = WiFiFirmwareDFUCancelReducer(
            state: .init(phase: .pending)
        )
        precondition(eventFirst.reduce(.matchedStatus(.cancelled)) == .cancellationSucceeded)
        precondition(eventFirst.reduce(.response(.success)) == .none)

        var originalTerminal = WiFiFirmwareDFUCancelReducer(
            state: .init(phase: .pending)
        )
        precondition(originalTerminal.reduce(.matchedStatus(.success)) == .originalOTAFinished)
        precondition(originalTerminal.state.phase == .resolved)
    }

    private static func testVerifyingRaceAndNotCancelledResponse() {
        var reducer = WiFiFirmwareDFUCancelReducer(
            state: .init(phase: .pending)
        )
        precondition(reducer.reduce(.matchedStatus(.verifying)) == .updateOriginalOTA)
        precondition(reducer.state.sawVerifyingWhilePending)
        precondition(
            reducer.reduce(.response(.notCancelled)) ==
                .continueOriginalOTA(showFailureTip: true)
        )
        precondition(reducer.state.phase == .resolved)
    }

    private static func testOrdinaryNotCancelledStartsRecovery() {
        var reducer = WiFiFirmwareDFUCancelReducer(
            state: .init(phase: .pending)
        )
        precondition(reducer.reduce(.response(.notCancelled)) == .requestRecoveryQuery)
        precondition(reducer.state.phase == .recovering)
    }

    private static func testUnconfirmedAndReservedStartRecovery() {
        for result in [WiFiFirmwareDFUCancelRET.unconfirmed, .reserved] {
            var reducer = WiFiFirmwareDFUCancelReducer(
                state: .init(phase: .pending)
            )
            precondition(reducer.reduce(.response(result)) == .requestRecoveryQuery)
            precondition(reducer.state.phase == .recovering)
        }
    }

    private static func testBusyStartsAuthoritativeRecovery() {
        var pending = WiFiFirmwareDFUCancelReducer(state: .init(phase: .pending))
        precondition(pending.reduce(.response(.busy)) == .requestRecoveryQuery)
        precondition(pending.state.phase == .recovering)

        var unknown = WiFiFirmwareDFUCancelReducer(state: .init(phase: .unknown))
        precondition(unknown.reduce(.response(.busy)) == .requestUnknownQuery)
        precondition(unknown.state.phase == .unknown)
    }

    private static func testPendingTimeoutAndRecoveryLimit() {
        var recovery = WiFiFirmwareDFUCancelReducer(
            state: .init(phase: .pending)
        )
        precondition(recovery.reduce(.pendingTimeout) == .requestRecoveryQuery)
        precondition(recovery.state.phase == .recovering)
        precondition(recovery.reduce(.recoveryQuery(.invalid)) == .requestRecoveryQuery)
        precondition(recovery.reduce(.recoveryQuery(.idle)) == .requestRecoveryQuery)
        precondition(recovery.reduce(.recoveryQuery(.invalid)) == .enterUnknown)
        precondition(recovery.state.phase == .unknown)
        precondition(recovery.state.recoveryQueryCount == 3)
    }

    private static func testRecoveryObservations() {
        var intermediate = WiFiFirmwareDFUCancelReducer(
            state: .init(phase: .recovering)
        )
        precondition(
            intermediate.reduce(.recoveryQuery(.matchedIntermediate(.downloading))) ==
                .continueOriginalOTA(showFailureTip: true)
        )
        precondition(intermediate.state.phase == .resolved)

        var cancelled = WiFiFirmwareDFUCancelReducer(
            state: .init(phase: .recovering)
        )
        precondition(
            cancelled.reduce(.recoveryQuery(.matchedCancelled)) ==
                .cancellationSucceeded
        )

        var terminal = WiFiFirmwareDFUCancelReducer(
            state: .init(phase: .recovering)
        )
        precondition(
            terminal.reduce(.recoveryQuery(.matchedOtherTerminal)) ==
                .originalOTAFinished
        )
    }

    private static func testUnknownPolling() {
        var invalid = WiFiFirmwareDFUCancelReducer(
            state: .init(phase: .unknown, recoveryQueryCount: 3)
        )
        precondition(
            invalid.reduce(.unknownQuery(.invalid)) ==
                .scheduleUnknownQuery(updateOriginalOTA: false)
        )
        precondition(invalid.state.phase == .unknown)
        precondition(
            invalid.reduce(.unknownQuery(.matchedIntermediate(.verifying))) ==
                .scheduleUnknownQuery(updateOriginalOTA: true)
        )

        var idle = WiFiFirmwareDFUCancelReducer(
            state: .init(phase: .unknown)
        )
        precondition(idle.reduce(.unknownQuery(.idle)) == .clearSession)
        precondition(idle.state.phase == .resolved)

        var lateResponse = WiFiFirmwareDFUCancelReducer(
            state: .init(phase: .unknown)
        )
        precondition(lateResponse.reduce(.response(.success)) == .cancellationSucceeded)

        var lateUnconfirmed = WiFiFirmwareDFUCancelReducer(
            state: .init(phase: .unknown)
        )
        precondition(lateUnconfirmed.reduce(.response(.unconfirmed)) == .requestUnknownQuery)
        precondition(lateUnconfirmed.state.phase == .unknown)
    }

    private static func testResumeBehavior() {
        for phase in [WiFiFirmwareDFUCancelPhase.pending, .recovering] {
            var reducer = WiFiFirmwareDFUCancelReducer(
                state: .init(phase: phase, recoveryQueryCount: 2)
            )
            precondition(reducer.reduce(.resume) == .requestRecoveryQuery)
            precondition(reducer.state.phase == .recovering)
            precondition(reducer.state.recoveryQueryCount == 0)
        }

        var unknown = WiFiFirmwareDFUCancelReducer(
            state: .init(phase: .unknown, recoveryQueryCount: 3)
        )
        precondition(unknown.reduce(.resume) == .requestUnknownQuery)
        precondition(unknown.state.phase == .unknown)

        var untouched = WiFiFirmwareDFUCancelReducer()
        precondition(untouched.reduce(.resume) == .none)
    }

    private static func testTimingConstants() {
        precondition(WiFiFirmwareDFUCancelTiming.responseTimeout == 7)
        precondition(WiFiFirmwareDFUCancelTiming.statusTimeout == 3)
        precondition(WiFiFirmwareDFUCancelTiming.maximumRecoveryQueries == 3)
        precondition(WiFiFirmwareDFUCancelTiming.unknownQueryInterval == 30)
    }
}
