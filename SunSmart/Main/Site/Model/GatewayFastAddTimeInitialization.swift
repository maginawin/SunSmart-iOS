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
        siteTimeZone: SiteTimeZoneValue
    ) -> GatewayFastAddTimeInitialization? {
        guard let model = node.timeSetupModel,
              let fixedTimeZone = TimeZone(
                secondsFromGMT: siteTimeZone.offsetMinutes * 60
              ) else {
            return nil
        }
        let message = Node.setLocalTimeMessage(
            date: Date(),
            timeZone: fixedTimeZone
        )
        return GatewayFastAddTimeInitialization(
            handle: MeshMessageHandle(message: message, model: model),
            targetOffsetMinutes: siteTimeZone.offsetMinutes
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
