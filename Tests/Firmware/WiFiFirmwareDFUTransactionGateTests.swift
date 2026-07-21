import Foundation

@main
struct WiFiFirmwareDFUTransactionGateTests {
    static func main() throws {
        testBlocksUntilCallback()
        testBlocksUntilDeadlineWithoutCallback()
        try testRoundTripPersistence()
        print("WiFiFirmwareDFUTransactionGateTests passed")
    }

    static func testBlocksUntilCallback() {
        var gate = WiFiFirmwareDFUTransactionGate()
        precondition(gate.beginCancel(at: 100, timeout: 7))
        precondition(!gate.beginCancel(at: 101, timeout: 7))
        precondition(gate.blocksStart(at: 106.9))
        gate.finishCancel()
        precondition(!gate.blocksStart(at: 106.9))
    }

    static func testBlocksUntilDeadlineWithoutCallback() {
        var gate = WiFiFirmwareDFUTransactionGate()
        precondition(gate.beginCancel(at: 100, timeout: 7))
        precondition(gate.blocksStart(at: 106.9))
        precondition(!gate.blocksStart(at: 107))
        precondition(gate.expireIfNeeded(at: 107))
        precondition(gate.cancelDeadline == nil)
    }

    static func testRoundTripPersistence() throws {
        var gate = WiFiFirmwareDFUTransactionGate()
        _ = gate.beginCancel(at: 100, timeout: 7)
        let data = try JSONEncoder().encode(gate)
        let decoded = try JSONDecoder().decode(
            WiFiFirmwareDFUTransactionGate.self,
            from: data
        )
        precondition(decoded.blocksStart(at: 106))
    }
}
