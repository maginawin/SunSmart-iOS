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

/// W excludes the menu but includes Overview. Only the gateways scroll.
struct SiteGatewayListLayout {
    let itemWidth: CGFloat
    let viewportWidth: CGFloat
    let contentWidth: CGFloat

    init(availableWidth: CGFloat, gatewayCount: Int) {
        guard gatewayCount > 0 else {
            itemWidth = 0
            viewportWidth = max(0, availableWidth)
            contentWidth = 0
            return
        }
        itemWidth = max(availableWidth / CGFloat(min(gatewayCount + 1, 4)), 100)
        viewportWidth = max(0, availableWidth - itemWidth)
        contentWidth = CGFloat(gatewayCount) * itemWidth
    }

    func clampedOffset(_ offset: CGFloat) -> CGFloat {
        min(max(0, offset), max(0, contentWidth - viewportWidth))
    }

    /// gatewayIndex excludes Overview and is zero based.
    func offsetToReveal(gatewayIndex: Int, currentOffset: CGFloat) -> CGFloat {
        let offset = clampedOffset(currentOffset)
        let start = CGFloat(gatewayIndex) * itemWidth
        let end = start + itemWidth
        if start < offset || viewportWidth < itemWidth {
            return clampedOffset(start)
        }
        if end > offset + viewportWidth {
            return clampedOffset(end - viewportWidth)
        }
        return offset
    }
}

struct SiteGatewayListScrollPosition {
    let gatewayID: String?
    let offsetWithinItem: CGFloat
    let fallbackOffset: CGFloat

    init(gatewayIDs: [String], offset: CGFloat, layout: SiteGatewayListLayout) {
        fallbackOffset = layout.clampedOffset(offset)
        guard layout.itemWidth > 0, !gatewayIDs.isEmpty else {
            gatewayID = nil
            offsetWithinItem = 0
            return
        }
        let index = min(Int(fallbackOffset / layout.itemWidth), gatewayIDs.count - 1)
        gatewayID = gatewayIDs[index]
        offsetWithinItem = fallbackOffset - CGFloat(index) * layout.itemWidth
    }

    func restoredOffset(gatewayIDs: [String], layout: SiteGatewayListLayout) -> CGFloat {
        guard let gatewayID, let index = gatewayIDs.firstIndex(of: gatewayID) else {
            return layout.clampedOffset(fallbackOffset)
        }
        // A narrower item must not move the anchor completely out of view.
        let inset = min(offsetWithinItem, max(0, layout.itemWidth - 1))
        return layout.clampedOffset(CGFloat(index) * layout.itemWidth + inset)
    }
}

/// Owned separately by each Site page; retained across reusable header instances.
final class SiteGatewayListScrollState {
    private(set) var selectedItemID: String?
    var needsSelectionReveal = false
    var position: SiteGatewayListScrollPosition?
    var availableWidth: CGFloat?

    func selectItem(_ id: String?, reveal: Bool = false) {
        needsSelectionReveal = needsSelectionReveal || selectedItemID != id || reveal
        selectedItemID = id
    }
}
