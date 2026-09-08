import Foundation

@main
enum SyncRunLifecycleTests {
    static func main() {
        let lifecycle = SyncRunLifecycle()
        let run = lifecycle.begin()
        let waiter = lifecycle.makeWaiter(for: run)!
        lifecycle.invalidate() // SDK may replace the old callback during STOP.
        precondition(waiter.wait(timeout: .now() + .milliseconds(100)) == .success,
                     "STOP must release the worker even when SDK drops its completion")
        precondition(lifecycle.makeWaiter(for: run) == nil && !lifecycle.claimCompletion(run), "invalid run cannot wait or finish")
        let next = lifecycle.begin()
        let nextWaiter = lifecycle.makeWaiter(for: next)!
        lifecycle.finishWaiting(waiter) // A late callback must only address its own waiter.
        precondition(nextWaiter.wait(timeout: .now() + .milliseconds(10)) == .timedOut, "old callback cannot release new wait")
        lifecycle.finishWaiting(nextWaiter)
        precondition(nextWaiter.wait(timeout: .now() + .milliseconds(100)) == .success, "new wait completes normally")
        let attempt = SyncAttemptCompletionGate()
        precondition(attempt.claim() && !attempt.claim(), "one SDK attempt may write back only once")
        precondition(SyncAttemptCompletionGate().claim(), "a retry owns an independent completion")
        let finishingRun = lifecycle.begin()
        let finishingWaiter = lifecycle.makeWaiter(for: finishingRun)!
        precondition(lifecycle.claimCompletion(finishingRun), "valid completion")
        precondition(finishingWaiter.wait(timeout: .now() + .milliseconds(100)) == .success, "completion drains outstanding waits")

        let output = SyncTaskPlanResult(sections: [TestSection(allModels: [TestModel()])],
            initialState: .inSync, proximityLightingTasks: [TestModel()], failureMessages: ["diagnostic"])
        let leaving = InstallationHarness()
        DispatchQueue.main.async { leaving.installTaskPlan(output) }
        leaving.hasLeftSyncPage = true
        DispatchQueue.main.drain()
        precondition(leaving.sections.isEmpty && leaving.starts == 0 && leaving.tableView.reloads == 0,
                     "exit before background build completion must reject installation and automatic start")
        precondition(XWHUDManager.errors.isEmpty && XWHUDManager.hides == 0, "late build must not publish HUD on another page")
        let installed = InstallationHarness()
        installed.installTaskPlan(output)
        precondition(installed.sections.count == 1 && installed.proximityLightingTaskModels.count == 1
            && installed.starts == 1 && installed.tableView.reloads == 1, "valid result installs and starts once")
        let manual = InstallationHarness()
        manual.installTaskPlan(.init(sections: output.sections, initialState: .syncFailure,
            proximityLightingTasks: [], failureMessages: []))
        precondition(manual.starts == 0 && manual.syncState == .syncFailure, "manual retry plan must wait for the user")
        let stopped = InstallationHarness()
        let pendingModel = TestModel()
        pendingModel.state = .wait
        DispatchQueue.main.async {
            stopped.installTaskPlan(.init(sections: [TestSection(allModels: [pendingModel])],
                initialState: .inSync, proximityLightingTasks: [], failureMessages: []))
        }
        stopped.syncState = .syncFailure // STOP before the background result reaches the main queue.
        DispatchQueue.main.drain()
        precondition(stopped.starts == 0 && stopped.syncState == .syncFailure,
                     "late plan must preserve STOP and must not automatically restart")
        precondition(stopped.sections.count == 1 && pendingModel.state == .failed && pendingModel.isFineshed,
                     "stopped plan must expose installed tasks for manual retry")
        precondition(stopped.tableView.reloads == 1 && stopped.stateUpdates == 1,
                     "stopped plan must refresh the installed task list and retry controls")
        print("PASS: production plan installation rejects closed pages; lifecycle receipts release waits once")
    }
}
