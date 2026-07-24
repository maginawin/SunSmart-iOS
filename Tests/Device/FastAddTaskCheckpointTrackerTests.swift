final class TestMessageHandle {}

@main
struct FastAddTaskCheckpointTrackerTests {
    static func main() {
        testBatchPreservesMessageOrderAndTailIdentity()
        testActualTailHandleCompletesCheckpoint()
        testEquivalentHandleInstancesRemainIndependent()
        testNonTailHandleDoesNotCompleteCheckpoint()
        testUnknownHandleDoesNotCompletePendingCheckpoint()
        testEmptySourceIsIgnored()
        testEmptyBatchSucceeds()
        testNightResultSurvivesDayOverwrite()
        testFailedCheckpointCannotBecomeSuccessfulLater()
        testDuplicateSuccessDoesNotReevaluateCheckpoint()
        testUnknownHandleDoesNotAffectCompletedCheckpoint()
        testPendingCheckpointIsFailure()
        print("FastAddTaskCheckpointTrackerTests passed")
    }

    private static func testBatchPreservesMessageOrderAndTailIdentity() {
        let first = TestMessageHandle()
        let firstTail = TestMessageHandle()
        let secondTail = TestMessageHandle()
        let batch = FastAddTaskCheckpointBatch(
            sources: [
                FastAddTaskCheckpointSource(
                    messageHandles: [first, firstTail],
                    verify: { true }
                ),
                FastAddTaskCheckpointSource(
                    messageHandles: [secondTail],
                    verify: { true }
                )
            ]
        )

        precondition(batch.messageHandles.count == 3)
        precondition(batch.messageHandles[0] === first)
        precondition(batch.messageHandles[1] === firstTail)
        precondition(batch.messageHandles[2] === secondTail)

        batch.tracker.recordSuccess(for: firstTail)
        precondition(batch.tracker.hasFailure)
        batch.tracker.recordSuccess(for: secondTail)
        precondition(!batch.tracker.hasFailure)
    }

    private static func testActualTailHandleCompletesCheckpoint() {
        let first = TestMessageHandle()
        let tail = TestMessageHandle()
        let batch = FastAddTaskCheckpointBatch(
            sources: [
                FastAddTaskCheckpointSource(
                    messageHandles: [first, tail],
                    verify: { true }
                )
            ]
        )

        let actualTail = batch.messageHandles[1]
        precondition(actualTail === tail)
        batch.tracker.recordSuccess(for: actualTail)

        precondition(!batch.tracker.hasFailure)
    }

    private static func testEquivalentHandleInstancesRemainIndependent() {
        let firstTail = TestMessageHandle()
        let secondTail = TestMessageHandle()
        let batch = FastAddTaskCheckpointBatch(
            sources: [
                FastAddTaskCheckpointSource(
                    messageHandles: [firstTail],
                    verify: { true }
                ),
                FastAddTaskCheckpointSource(
                    messageHandles: [secondTail],
                    verify: { true }
                )
            ]
        )

        batch.tracker.recordSuccess(for: firstTail)
        precondition(batch.tracker.hasFailure)
        batch.tracker.recordSuccess(for: secondTail)
        precondition(!batch.tracker.hasFailure)
    }

    private static func testNonTailHandleDoesNotCompleteCheckpoint() {
        let first = TestMessageHandle()
        let tail = TestMessageHandle()
        let batch = FastAddTaskCheckpointBatch(
            sources: [
                FastAddTaskCheckpointSource(
                    messageHandles: [first, tail],
                    verify: { true }
                )
            ]
        )

        batch.tracker.recordSuccess(for: first)

        precondition(batch.tracker.hasFailure)
    }

    private static func testUnknownHandleDoesNotCompletePendingCheckpoint() {
        let tail = TestMessageHandle()
        let unknown = TestMessageHandle()
        let batch = FastAddTaskCheckpointBatch(
            sources: [
                FastAddTaskCheckpointSource(
                    messageHandles: [tail],
                    verify: { true }
                )
            ]
        )

        batch.tracker.recordSuccess(for: unknown)

        precondition(batch.tracker.hasFailure)
    }

    private static func testEmptySourceIsIgnored() {
        let batch = FastAddTaskCheckpointBatch<TestMessageHandle>(
            sources: [
                FastAddTaskCheckpointSource(
                    messageHandles: [],
                    verify: { false }
                )
            ]
        )

        precondition(batch.messageHandles.isEmpty)
        precondition(!batch.tracker.hasFailure)
    }

    private static func testEmptyBatchSucceeds() {
        let batch = FastAddTaskCheckpointBatch<TestMessageHandle>(sources: [])

        precondition(batch.messageHandles.isEmpty)
        precondition(!batch.tracker.hasFailure)
    }

    private static func testNightResultSurvivesDayOverwrite() {
        let nightHandle = TestMessageHandle()
        let dayHandle = TestMessageHandle()
        var currentLevel = 100
        let tracker = FastAddTaskCheckpointTracker(
            checkpoints: [
                FastAddTaskCheckpoint(lastMessageHandle: nightHandle) {
                    currentLevel == 100
                },
                FastAddTaskCheckpoint(lastMessageHandle: dayHandle) {
                    currentLevel == 0
                }
            ]
        )

        tracker.recordSuccess(for: nightHandle)
        currentLevel = 0
        tracker.recordSuccess(for: dayHandle)

        precondition(!tracker.hasFailure)
    }

    private static func testFailedCheckpointCannotBecomeSuccessfulLater() {
        let handle = TestMessageHandle()
        var currentLevel = 0
        let tracker = FastAddTaskCheckpointTracker(
            checkpoints: [
                FastAddTaskCheckpoint(lastMessageHandle: handle) {
                    currentLevel == 100
                }
            ]
        )

        tracker.recordSuccess(for: handle)
        currentLevel = 100
        tracker.recordSuccess(for: handle)

        precondition(tracker.hasFailure)
    }

    private static func testDuplicateSuccessDoesNotReevaluateCheckpoint() {
        let handle = TestMessageHandle()
        var currentLevel = 100
        let tracker = FastAddTaskCheckpointTracker(
            checkpoints: [
                FastAddTaskCheckpoint(lastMessageHandle: handle) {
                    currentLevel == 100
                }
            ]
        )

        tracker.recordSuccess(for: handle)
        currentLevel = 0
        tracker.recordSuccess(for: handle)

        precondition(!tracker.hasFailure)
    }

    private static func testUnknownHandleDoesNotAffectCompletedCheckpoint() {
        let expectedHandle = TestMessageHandle()
        let unknownHandle = TestMessageHandle()
        let tracker = FastAddTaskCheckpointTracker(
            checkpoints: [
                FastAddTaskCheckpoint(lastMessageHandle: expectedHandle) {
                    true
                }
            ]
        )

        tracker.recordSuccess(for: expectedHandle)
        tracker.recordSuccess(for: unknownHandle)

        precondition(!tracker.hasFailure)
    }

    private static func testPendingCheckpointIsFailure() {
        let tracker = FastAddTaskCheckpointTracker(
            checkpoints: [
                FastAddTaskCheckpoint(lastMessageHandle: TestMessageHandle()) {
                    true
                }
            ]
        )

        precondition(tracker.hasFailure)
    }

}
