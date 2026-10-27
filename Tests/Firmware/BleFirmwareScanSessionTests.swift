import Foundation

@main
struct BleFirmwareScanSessionTests {
    static func main() {
        automaticScanRenewsOnlyOnFirstDiscovery()
        activationWaitStopsAtThirtySecondsWithoutRenewal()
        allTargetsMustBeDiscoveredInTheCurrentSession()
        cancelledSessionRejectsLateDiscoveries()
        staleTimeoutCannotEndTheReplacementSession()
        unexpectedAddressDoesNotRenewOrCompleteScan()
        countdownUsesTheSameDeadlineAndNeverGoesNegative()
        expiredAutomaticSessionCannotBeRevived()
        manualWaitingRejectsSelectionChangesWithoutLosingExistingSelection()
        print("BleFirmwareScanSessionTests passed (9 cases)")
    }

    // Extending on duplicate advertisements would keep ordinary scans alive forever.
    private static func automaticScanRenewsOnlyOnFirstDiscovery() {
        var scan = BleFirmwareScanSession()
        let id = scan.begin(mode: .automatic, targetAddresses: [1, 2], at: 100)
        precondition(scan.accepts(sessionID: id, at: 109.9))
        let first = scan.receive(address: 1, sessionID: id, at: 109)
        precondition(first?.isFirstDiscovery == true && first?.foundAllTargets == false)
        precondition(scan.deadline == 119)
        let repeated = scan.receive(address: 1, sessionID: id, at: 115)
        precondition(repeated?.isFirstDiscovery == false)
        precondition(scan.deadline == 119)
        precondition(scan.receive(address: 2, sessionID: id, at: 118)?.foundAllTargets == true)
    }

    // The old ten-second timeout or renewal branch must not shorten/extend manual waiting.
    private static func activationWaitStopsAtThirtySecondsWithoutRenewal() {
        var scan = BleFirmwareScanSession()
        let id = scan.begin(mode: .batteryActivation, targetAddresses: [1, 2], at: 100)
        precondition(scan.receive(address: 1, sessionID: id, at: 111) != nil)
        precondition(scan.receive(address: 1, sessionID: id, at: 129) != nil)
        precondition(scan.deadline == 130)
        precondition(scan.receive(address: 2, sessionID: id, at: 130) == nil)
        precondition(!scan.accepts(sessionID: id, at: 130.1))
    }

    // A previous round's discoveries must not make a new wait finish immediately.
    private static func allTargetsMustBeDiscoveredInTheCurrentSession() {
        var scan = BleFirmwareScanSession()
        let old = scan.begin(mode: .batteryActivation, targetAddresses: [1, 2], at: 0)
        _ = scan.receive(address: 1, sessionID: old, at: 1)
        precondition(scan.receive(address: 2, sessionID: old, at: 2)?.foundAllTargets == true)
        precondition(scan.end(sessionID: old))
        let current = scan.begin(mode: .batteryActivation, targetAddresses: [1, 2], at: 3)
        precondition(scan.receive(address: 2, sessionID: current, at: 4)?.foundAllTargets == false)
        precondition(scan.receive(address: 1, sessionID: current, at: 5)?.foundAllTargets == true)
    }

    // Cancellation must invalidate first, including a synchronous SDK completion during stop.
    private static func cancelledSessionRejectsLateDiscoveries() {
        var scan = BleFirmwareScanSession()
        let id = scan.begin(mode: .batteryActivation, targetAddresses: [1], at: 0)
        precondition(scan.end(sessionID: id))
        precondition(!scan.isActive && scan.mode == nil)
        precondition(scan.receive(address: 1, sessionID: id, at: 1) == nil)
        precondition(!scan.end(sessionID: id))
        precondition(scan.remainingSeconds(at: 1) == nil)
    }

    // The former automatic timeout must not stop a manually restarted scan.
    private static func staleTimeoutCannotEndTheReplacementSession() {
        var scan = BleFirmwareScanSession()
        let old = scan.begin(mode: .automatic, targetAddresses: [1], at: 0)
        let current = scan.begin(mode: .batteryActivation, targetAddresses: [1], at: 5)
        precondition(!scan.end(sessionID: old))
        precondition(scan.isActive && scan.sessionID == current)
        precondition(scan.receive(address: 1, sessionID: old, at: 10) == nil)
        precondition(scan.remainingSeconds(at: 10) == 25)
        precondition(scan.receive(address: 1, sessionID: current, at: 11)?.foundAllTargets == true)
    }

    private static func unexpectedAddressDoesNotRenewOrCompleteScan() {
        var scan = BleFirmwareScanSession()
        let id = scan.begin(mode: .automatic, targetAddresses: [1], at: 0)
        precondition(scan.receive(address: 9, sessionID: id, at: 9) == nil)
        precondition(scan.deadline == 10)
        precondition(scan.receive(address: 1, sessionID: id, at: 9)?.foundAllTargets == true)
    }

    // Display and expiry must agree after delayed ticks, scrolling or suspension.
    private static func countdownUsesTheSameDeadlineAndNeverGoesNegative() {
        var scan = BleFirmwareScanSession()
        _ = scan.begin(mode: .batteryActivation, targetAddresses: [1], at: 100)
        let samples: [(TimeInterval, Int)] = [(100, 30), (100.2, 30), (101, 29), (129.8, 1), (130, 0), (160, 0)]
        for (time, expected) in samples {
            precondition(scan.remainingSeconds(at: time) == expected)
        }
    }

    private static func expiredAutomaticSessionCannotBeRevived() {
        var scan = BleFirmwareScanSession()
        let id = scan.begin(mode: .automatic, targetAddresses: [1], at: 0)
        precondition(scan.receive(address: 1, sessionID: id, at: 10) == nil)
        precondition(scan.deadline == 10)
        precondition(scan.end(sessionID: id))
    }

    private static func manualWaitingRejectsSelectionChangesWithoutLosingExistingSelection() {
        var scan = BleFirmwareScanSession()
        let id = scan.begin(mode: .batteryActivation, targetAddresses: [1], at: 0)
        var selected: Set<UInt16> = [10]
        precondition(!scan.performSelectionChange { selected.insert(11) })
        precondition(selected == [10], "A blocked row tap must preserve existing selections")
        precondition(!scan.performSelectionChange { selected.removeAll() })
        precondition(selected == [10], "A blocked category select-all must preserve existing selections")
        scan.end(sessionID: id)
        precondition(scan.performSelectionChange { selected.insert(11) })
        precondition(selected == [10, 11], "Selection must work again after cancellation")
    }
}
