import Foundation

@main
struct SceneCapacityTests {
    static func main() throws {
        let fifteen = Set((1...15).map(UInt16.init))
        let sixteen = Set((1...16).map(UInt16.init))
        try SceneCapacityPolicy.validate(previous: fifteen, desired: sixteen, observed: fifteen)
        try SceneCapacityPolicy.validate(previous: sixteen, desired: sixteen, observed: nil)
        try SceneCapacityPolicy.validate(previous: sixteen, desired: fifteen, observed: sixteen)
        try SceneCapacityPolicy.validate(previous: [], desired: [], observed: nil)
        try SceneCapacityPolicy.validate(previous: [], desired: [7], observed: [7])
        try SceneCapacityPolicy.validate(previous: [], desired: [7], observed: [])
        expectFailure(.capacity, previous: sixteen, desired: sixteen.union([17]), observed: sixteen)
        expectFailure(.unknown, previous: [], desired: [7], observed: nil)
        expectFailure(.capacity, previous: [], desired: [17], observed: sixteen)
        expectFailure(.capacity, previous: [], desired: [17], observed: fifteen.union([0xFF00]))
        // Pending physical removal cannot release a slot before confirmation.
        expectFailure(.capacity, previous: sixteen, desired: fifteen.union([17]), observed: sixteen)
        try SceneCapacityPolicy.validate(previous: sixteen, desired: fifteen.union([17]), observed: fifteen)
        let overfull = sixteen.union([17])
        try SceneCapacityPolicy.validate(previous: overfull, desired: sixteen, observed: overfull)
        // Distinct devices each have their own budget; the Space has no 16 ceiling.
        try SceneCapacityPolicy.validate(previous: [], desired: sixteen, observed: [])
        try SceneCapacityPolicy.validate(previous: [], desired: Set((17...32).map(UInt16.init)), observed: [])
        precondition(SceneRegisterPolicy.accepts(status: 0, scenes: [4], storing: 4, deleting: nil))
        precondition(!SceneRegisterPolicy.accepts(status: 1, scenes: [], storing: 4, deleting: nil))
        precondition(!SceneRegisterPolicy.accepts(status: 0, scenes: [], storing: 4, deleting: nil))
        precondition(!SceneRegisterPolicy.accepts(status: 0, scenes: [4], storing: nil, deleting: 4))
        precondition(SceneRegisterPolicy.accepts(status: 0, scenes: [], storing: nil, deleting: 4))
        precondition(SceneRegisterPolicy.accepts(status: 2, scenes: [], storing: nil, deleting: 4))
        precondition(!SceneRegisterPolicy.accepts(status: 2, scenes: [], storing: nil, deleting: nil))
        precondition(!SceneRegisterPolicy.accepts(status: 0, scenes: [0], storing: nil, deleting: nil))
        precondition(SceneRegisterPolicy.nextOrdinaryNumber(used: [1, 3], ranges: [1...5]) == 2)
        precondition(SceneRegisterPolicy.nextOrdinaryNumber(used: [1, 2], ranges: [1...2, 0xFF00...0xFFFF]) == nil)
        precondition(SceneRegisterPolicy.nextOrdinaryNumber(used: [0xFEFE], ranges: [0xFEFE...0xFFFF]) == 0xFEFF)
        precondition(SceneDeleteCapability.needsRemoval(observed: nil, number: 7, hasCachedData: false))
        precondition(SceneDeleteCapability.needsRemoval(observed: [7], number: 7, hasCachedData: false))
        precondition(!SceneDeleteCapability.needsRemoval(observed: [], number: 7, hasCachedData: false))
        precondition(SceneDeleteCapability.needsRemoval(observed: [], number: 7, hasCachedData: true))
        print("SceneCapacityTests passed: capacity, residuals, legacy unknown, independent devices, Store/Delete status")
    }

    static func expectFailure(_ expected: SceneCapacityPolicy.Failure, previous: Set<UInt16>,
                              desired: Set<UInt16>, observed: Set<UInt16>?) {
        do {
            try SceneCapacityPolicy.validate(previous: previous, desired: desired, observed: observed)
            fatalError("Expected \(expected)")
        } catch { precondition(error as? SceneCapacityPolicy.Failure == expected) }
    }
}
