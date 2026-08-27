import Foundation

@main
struct UpDownRatioCommandSchedulerTests {

    static func main() {
        testSamplingStartsImmediatelyWhenIdle()
        testPendingSamplesKeepOnlyLatestValue()
        testFinalReplacesPendingSample()
        testFinalIsSentEvenWhenItMatchesSamplingValue()
        testSamplingAfterPendingFinalKeepsOrdering()
        testValuesAreClamped()
        print("UpDownRatioCommandSchedulerTests passed")
    }

    private static func testSamplingStartsImmediatelyWhenIdle() {
        var scheduler = UpDownRatioCommandScheduler()

        let command = scheduler.enqueueSampling(value: 30, editGeneration: 1)

        require(command == .init(value: 30, kind: .sampling, editGeneration: 1))
        require(scheduler.isCommandInFlight)
    }

    private static func testPendingSamplesKeepOnlyLatestValue() {
        var scheduler = UpDownRatioCommandScheduler()
        _ = scheduler.enqueueSampling(value: 20, editGeneration: 1)

        require(scheduler.enqueueSampling(value: 30, editGeneration: 2) == nil)
        require(scheduler.enqueueSampling(value: 40, editGeneration: 3) == nil)

        let next = scheduler.completeCurrentCommand()
        require(next == .init(value: 40, kind: .sampling, editGeneration: 3))
    }

    private static func testFinalReplacesPendingSample() {
        var scheduler = UpDownRatioCommandScheduler()
        _ = scheduler.enqueueSampling(value: 20, editGeneration: 1)
        _ = scheduler.enqueueSampling(value: 40, editGeneration: 2)

        require(scheduler.enqueueFinal(value: 45, editGeneration: 3) == nil)

        let next = scheduler.completeCurrentCommand()
        require(next == .init(value: 45, kind: .final, editGeneration: 3))
        require(scheduler.completeCurrentCommand() == nil)
    }

    private static func testFinalIsSentEvenWhenItMatchesSamplingValue() {
        var scheduler = UpDownRatioCommandScheduler()
        let sampling = scheduler.enqueueSampling(value: 60, editGeneration: 1)

        require(sampling == .init(value: 60, kind: .sampling, editGeneration: 1))
        require(scheduler.enqueueFinal(value: 60, editGeneration: 1) == nil)

        let final = scheduler.completeCurrentCommand()
        require(final == .init(value: 60, kind: .final, editGeneration: 1))
    }

    private static func testSamplingAfterPendingFinalKeepsOrdering() {
        var scheduler = UpDownRatioCommandScheduler()
        _ = scheduler.enqueueSampling(value: 20, editGeneration: 1)
        _ = scheduler.enqueueFinal(value: 30, editGeneration: 2)
        _ = scheduler.enqueueSampling(value: 40, editGeneration: 3)
        _ = scheduler.enqueueSampling(value: 50, editGeneration: 4)

        let final = scheduler.completeCurrentCommand()
        require(final == .init(value: 30, kind: .final, editGeneration: 2))

        let latestSampling = scheduler.completeCurrentCommand()
        require(latestSampling == .init(value: 50, kind: .sampling, editGeneration: 4))
    }

    private static func testValuesAreClamped() {
        var scheduler = UpDownRatioCommandScheduler()
        let low = scheduler.enqueueSampling(value: -1, editGeneration: 1)
        require(low?.value == 0)

        _ = scheduler.completeCurrentCommand()
        let high = scheduler.enqueueFinal(value: 101, editGeneration: 2)
        require(high?.value == 100)
    }

    private static func require(
        _ condition: @autoclosure () -> Bool,
        _ message: String = "Requirement failed",
        file: StaticString = #file,
        line: UInt = #line
    ) {
        guard condition() else {
            fatalError(message, file: file, line: line)
        }
    }
}
