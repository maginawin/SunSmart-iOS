import Foundation

enum GatewayFastAddTimeInitializationPolicy {
    static func accepts(
        seconds: UInt64,
        offsetMinutes: Int,
        targetOffsetMinutes: Int
    ) -> Bool {
        seconds > 0 && offsetMinutes == targetOffsetMinutes
    }
}

#if canImport(NordicSigMeshSDK)
import NordicSigMeshSDK

struct GatewayFastAddTimeInitialization {
    let handle: MeshMessageHandle
    let targetOffsetMinutes: Int

    static func make(
        node: Node,
        siteTimeZoneStorageValue: String?,
        phoneTimeZone: TimeZone = .current,
        at date: Date = Date()
    ) -> GatewayFastAddTimeInitialization? {
        guard let model = node.timeSetupModel,
              let resolution = SiteTimeSetMessageFactory.resolve(
                  storageValue: siteTimeZoneStorageValue,
                  phoneTimeZone: phoneTimeZone,
                  at: date
              ) else {
            return nil
        }
        let plan = SiteTimeSetMessageFactory.makePlan(
            model: model,
            resolution: resolution
        )
        return GatewayFastAddTimeInitialization(
            handle: plan.handle,
            targetOffsetMinutes: plan.targetOffsetMinutes
        )
    }

    func acceptsCurrentNodeState(_ node: Node) -> Bool {
        GatewayFastAddTimeInitializationPolicy.accepts(
            seconds: node.timestamp,
            offsetMinutes: node.timezone.map { $0.secondsFromGMT() / 60 } ?? Int.min,
            targetOffsetMinutes: targetOffsetMinutes
        )
    }

    static func clearUninitializedTime(on node: Node) {
        node.timezone = nil
        node.timestamp = 0
        _ = node.savePropertys()
    }
}
#endif
