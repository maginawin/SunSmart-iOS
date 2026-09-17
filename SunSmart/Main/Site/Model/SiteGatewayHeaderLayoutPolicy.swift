import Foundation

enum SiteGatewayHeaderLayoutPolicy {

    static func showsGatewayStatus(
        selectedGatewayID: String?,
        visibleGatewayIDs: [String],
        hasSiteSpaces: Bool,
        hasServerGatewayStatus: Bool,
        isSiteOwner: Bool
    ) -> Bool {
        if let selectedGatewayID, visibleGatewayIDs.contains(selectedGatewayID) {
            return true
        }
        return hasSiteSpaces &&
            (!visibleGatewayIDs.isEmpty || hasServerGatewayStatus || !isSiteOwner)
    }

    static func emptyStateFrame(
        collectionBounds: CGRect,
        headerHeight: CGFloat
    ) -> CGRect {
        var frame = collectionBounds
        frame.origin.y = headerHeight
        return frame
    }

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
