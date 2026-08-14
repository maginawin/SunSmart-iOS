import Foundation

enum SiteGatewayHeaderLayoutPolicy {

    static func height(
        gatewayListHeight: CGFloat,
        gatewayStatusHeight: CGFloat,
        reviewSyncHeight: CGFloat,
        showsGatewayStatus: Bool,
        showsReviewSync: Bool
    ) -> CGFloat {
        gatewayListHeight +
            (showsGatewayStatus ? gatewayStatusHeight : 0) +
            (showsReviewSync ? reviewSyncHeight : 0)
    }
}
