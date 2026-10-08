import Foundation

@main
struct TimedDeviceSlotTests {
    static func main() throws {
        let manager = MeshNetworkManager()
        manager.schedules = (0..<16).map { Schedule(id: $0) }
        guard manager.getNextAvailableScheduleId() == 16 else {
            print("FAIL: a Space with 16 schedules must allocate logical id 16")
            exit(1)
        }
        manager.schedules = [Schedule(id: 0), Schedule(id: 300)]
        precondition(manager.getNextAvailableScheduleId() == 301)
        manager.schedules = [Schedule(id: Int.max)]
        precondition(manager.getNextAvailableScheduleId() == nil)
        try slotsAreIndependentPerDevice()
        try preservesPendingAndRejectsUnknownCapacity()
        try migratesLegacyWithoutRenumbering()
        try rejectsConflictingBindings()
        print("PASS: logical schedule identity is independent of the 4-bit device slot")
    }

    static let first = TimedSchedulerNodeIdentity(
        nodeUUID: "11111111-1111-1111-1111-111111111111",
        unicastAddress: "0001", deviceKeyFingerprint: String(repeating: "a", count: 64))
    static let second = TimedSchedulerNodeIdentity(
        nodeUUID: "22222222-2222-2222-2222-222222222222",
        unicastAddress: "0005", deviceKeyFingerprint: String(repeating: "b", count: 64))

    static func intent(_ id: Int, target: Bool = true, legacy: Bool = false,
                       binding: TimedSchedulerNodeSlot? = nil) -> TimedSchedulerSlotPolicy.Intent {
        .init(scheduleID: id, targetsNode: target, legacy: legacy, binding: binding)
    }

    static func slotsAreIndependentPerDevice() throws {
        let a = try TimedSchedulerSlotPolicy.plan(identity: first,
            intents: (0..<16).map { intent($0) }, observedSlots: [])
        let b = try TimedSchedulerSlotPolicy.plan(identity: second,
            intents: (16..<32).map { intent($0) }, observedSlots: [])
        precondition(Set(a.values.map(\.slot)) == Set(0..<16))
        precondition(Set(b.values.map(\.slot)) == Set(0..<16))
        precondition(b[16]?.slot == 0 && b[31]?.slot == 15)
        try rejects {
            _ = try TimedSchedulerSlotPolicy.plan(identity: first,
                intents: (0..<17).map { intent($0) }, observedSlots: [])
        }
        let different = try TimedSchedulerSlotPolicy.plan(identity: second,
            intents: [intent(300)], observedSlots: [0, 1, 2])
        precondition(different[300]?.slot == 3)
    }

    static func preservesPendingAndRejectsUnknownCapacity() throws {
        let saved = TimedSchedulerNodeSlot(identity: first, slot: 7, state: .assigned)
        let plan = try TimedSchedulerSlotPolicy.plan(identity: first,
            intents: [intent(300, target: false, binding: saved), intent(301)], observedSlots: [])
        precondition(plan[300]?.slot == 7 && plan[300]?.state == .pendingRemoval)
        precondition(plan[300]?.generation == saved.generation)
        precondition(plan[301]?.slot == 0)
        let restored = try JSONDecoder().decode([Int: TimedSchedulerNodeSlot].self,
            from: JSONEncoder().encode(plan))
        precondition(restored == plan)
        try rejects {
            _ = try TimedSchedulerSlotPolicy.plan(identity: first, intents: [intent(301)], observedSlots: nil)
        }
        let existing = try TimedSchedulerSlotPolicy.plan(identity: first,
            intents: [intent(300, binding: saved)], observedSlots: nil)
        precondition(existing[300] == saved, "unknown observations must not block editing an existing binding")
        let pending = try TimedSchedulerSlotPolicy.plan(identity: first,
            intents: [intent(300, target: false, binding: saved)], observedSlots: nil)
        precondition(pending[300]?.slot == 7)
    }

    static func migratesLegacyWithoutRenumbering() throws {
        let result = try TimedSchedulerSlotPolicy.plan(identity: first,
            intents: [intent(8, legacy: true), intent(3, target: false, legacy: true)], observedSlots: [3, 8])
        precondition(result[8]?.slot == 8 && result[3]?.slot == 3)
        precondition(result[3]?.state == .pendingRemoval)
        let empty = try TimedSchedulerSlotPolicy.plan(identity: first,
            intents: [intent(8, target: false, legacy: true)], observedSlots: [])
        precondition(empty.isEmpty)
        try rejects {
            _ = try TimedSchedulerSlotPolicy.plan(identity: first,
                intents: [intent(16, legacy: true)], observedSlots: [])
        }
    }

    static func rejectsConflictingBindings() throws {
        let same = TimedSchedulerNodeSlot(identity: first, slot: 2, state: .assigned)
        try rejects {
            _ = try TimedSchedulerSlotPolicy.plan(identity: first,
                intents: [intent(1, binding: same), intent(2, binding: same)], observedSlots: [])
        }
        try rejects {
            _ = try TimedSchedulerSlotPolicy.plan(identity: second,
                intents: [intent(1, binding: same)], observedSlots: [])
        }
        try rejects {
            _ = try TimedSchedulerSlotPolicy.plan(identity: first,
                intents: [intent(1), intent(1)], observedSlots: [])
        }
    }

    static func rejects(_ body: () throws -> Void) throws {
        do { try body() } catch { return }
        print("FAIL: invalid or over-capacity slot plan was accepted")
        exit(1)
    }
}
