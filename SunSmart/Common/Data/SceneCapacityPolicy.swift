import Foundation

/// Business intent and physical occupancy are separate. A removal is not free
/// space until the device's Register confirms it; editing the same ID costs zero.
enum SceneCapacityPolicy {
    enum Failure: Error, Equatable { case capacity, unknown }

    static func validate(previous: Set<UInt16>, desired: Set<UInt16>, observed: Set<UInt16>?) throws {
        guard !desired.subtracting(previous).isEmpty else { return }
        guard desired.count <= 16 else { throw Failure.capacity }
        guard let observed else { throw Failure.unknown }
        guard observed.union(desired).count <= 16 else { throw Failure.capacity }
    }
}
