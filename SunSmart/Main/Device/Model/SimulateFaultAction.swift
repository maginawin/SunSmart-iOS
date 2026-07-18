import Foundation

enum SimulateFaultAction: Hashable {
    enum SensorState: Hashable {
        case normal
        case fault
    }

    enum LightState: Hashable {
        case normal
        case dim
        case flicker
        case dimFlicker
        case off
    }

    case motionSensor(SensorState)
    case photocellSensor(SensorState)
    case lightStatus(LightState)
}

extension SimulateFaultAction {
    var alertPayload: SimulateFaultAlertPayload {
        switch self {
        case .motionSensor(.normal):
            return .init(type: "motion_sensor", status: "normal", level: "3")
        case .motionSensor(.fault):
            return .init(type: "motion_sensor", status: "fault", level: "3")
        case .photocellSensor(.normal):
            return .init(type: "photocell_sensor", status: "normal", level: "2")
        case .photocellSensor(.fault):
            return .init(type: "photocell_sensor", status: "fault", level: "2")
        case .lightStatus(.normal):
            return .init(type: "light_status", status: "normal", level: "1")
        case .lightStatus(.dim):
            return .init(type: "light_status", status: "dim", level: "1")
        case .lightStatus(.flicker):
            return .init(type: "light_status", status: "flicker", level: "1")
        case .lightStatus(.dimFlicker):
            return .init(type: "light_status", status: "dim_flicker", level: "1")
        case .lightStatus(.off):
            return .init(type: "light_status", status: "off", level: "1")
        }
    }
}

enum SimulateFaultGridMetrics {
    static let itemWidth: CGFloat = 71
    static let itemHeight: CGFloat = 28
    static let interitemSpacing: CGFloat = 8
    static let lineSpacing: CGFloat = 7
    static let topInset: CGFloat = 8

    static func columns(availableWidth: CGFloat, itemCount: Int) -> Int {
        guard itemCount > 0 else { return 0 }
        let count = Int((availableWidth + interitemSpacing) / (itemWidth + interitemSpacing))
        return min(itemCount, max(1, count))
    }

    static func rows(availableWidth: CGFloat, itemCount: Int) -> Int {
        let columnCount = columns(availableWidth: availableWidth, itemCount: itemCount)
        guard columnCount > 0 else { return 0 }
        return Int(ceil(Double(itemCount) / Double(columnCount)))
    }

    static func collectionHeight(availableWidth: CGFloat, itemCount: Int) -> CGFloat {
        let rowCount = rows(availableWidth: availableWidth, itemCount: itemCount)
        guard rowCount > 0 else { return 0 }
        return topInset
            + CGFloat(rowCount) * itemHeight
            + CGFloat(rowCount - 1) * lineSpacing
    }
}

enum SimulateFaultPresentationMetrics {
    static let contentHorizontalInset: CGFloat = 16
    static let sectionHorizontalInset: CGFloat = 16
    static let contentTopInset: CGFloat = 8
    static let headerHeight: CGFloat = 40
    static let headerToSectionSpacing: CGFloat = 8
    static let sectionSpacing: CGFloat = 11
    static let sectionVerticalPadding: CGFloat = 24
    static let sectionHeaderHeight: CGFloat = 21
    static let minimumBottomInset: CGFloat = 30

    static func bottomInset(safeAreaBottom: CGFloat) -> CGFloat {
        max(minimumBottomInset, safeAreaBottom - 4)
    }

    static func contentHeight(availableWidth: CGFloat, safeAreaBottom: CGFloat) -> CGFloat {
        let collectionWidth = max(
            0,
            availableWidth
                - contentHorizontalInset * 2
                - sectionHorizontalInset * 2
        )
        let sectionHeights = [2, 2, 5].map { itemCount in
            sectionVerticalPadding
                + sectionHeaderHeight
                + SimulateFaultGridMetrics.collectionHeight(
                    availableWidth: collectionWidth,
                    itemCount: itemCount
                )
        }
        return contentTopInset
            + headerHeight
            + headerToSectionSpacing
            + sectionHeights.reduce(0, +)
            + sectionSpacing * CGFloat(sectionHeights.count - 1)
            + bottomInset(safeAreaBottom: safeAreaBottom)
    }
}
