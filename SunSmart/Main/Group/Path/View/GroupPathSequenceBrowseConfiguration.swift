import UIKit

/// Read-only candidates supplied by the owning page; never wraps an SDK Node.
struct GroupPathSequenceBrowseConfiguration {
    private enum MenuPlacement {
        case belowSource
        case belowTrailing(width: CGFloat)
    }

    struct Space {
        let id: String
        let title: String
        let enabled: Bool
    }
    struct Device: Equatable {
        let id: String
        let name: String
    }
    let spaces: [Space]
    let selectedSpaceID: String?
    let placeholder: String
    let includeAdded: Bool
    let devices: [Device]
    let emptyMessage: String?
    let unavailableMessage: String?
    let selectSpace: (String) -> Void
    let changeFilter: (Bool) -> Void
    let retry: (() -> Void)?

    var spaceTitle: String { spaces.first { $0.id == selectedSpaceID }?.title ?? placeholder }
    var filterTitle: String { (includeAdded ? "used" : "space_trigger_zone_new_only").localizedString }
    var filterWidth: CGFloat {
        let font = UIFont.systemFont(ofSize: 13, weight: .light)
        return max(100, ceil(("used".localizedString as NSString).size(withAttributes: [.font: font]).width) + 40)
    }

    func configureAccessibility(space: UIView, filter: UIView) {
        space.isAccessibilityElement = true
        space.accessibilityIdentifier = "site-zone-space-filter"
        space.accessibilityLabel = spaceTitle
        space.accessibilityTraits = spaces.isEmpty ? [.staticText] : [.button]
        filter.isAccessibilityElement = true
        filter.accessibilityIdentifier = "site-zone-added-filter"
        filter.accessibilityLabel = filterTitle
        filter.accessibilityTraits = .button
    }

    func showSpaces(from source: UIView) {
        showMenu(from: source, titles: spaces.map(\.title), enabled: spaces.map(\.enabled),
                 selected: spaces.firstIndex { $0.id == selectedSpaceID }, placement: .belowSource) { index in
            guard spaces.indices.contains(index), spaces[index].enabled else { return }
            selectSpace(spaces[index].id)
        }
    }

    func showFilter(from source: UIView) {
        showMenu(from: source, titles: ["quick_add_ignore_added_devices".localizedString, "zone_trigger_add_show_added_devices".localizedString],
                 enabled: [true, true], selected: includeAdded ? 1 : 0, placement: .belowTrailing(width: isIPad ? 320 : 256)) { changeFilter($0 == 1) }
    }

    private func showMenu(from source: UIView, titles: [String], enabled: [Bool], selected: Int?, placement: MenuPlacement,
                          action: @escaping (Int) -> Void) {
        guard !titles.isEmpty, let window = source.window else { return }
        window.layoutIfNeeded()
        let safe = window.bounds.inset(by: window.safeAreaInsets).insetBy(dx: 8, dy: 8)
        let rect = source.convert(source.bounds, to: window)
        let width: CGFloat
        let leading: CGFloat
        switch placement {
        case .belowSource:
            width = rect.width
            leading = rect.minX
        case .belowTrailing(let preferredWidth):
            width = min(preferredWidth, safe.width)
            leading = min(max(rect.maxX - width, safe.minX), safe.maxX - width)
        }
        let itemHeight: CGFloat = 30
        let below = max(0, safe.maxY - rect.maxY - 4)
        let desired = CGFloat(min(8, titles.count)) * itemHeight
        let height = min(desired, below)
        guard width > 0, height >= itemHeight else { return }
        let anchor = CGPoint(x: leading, y: rect.maxY + 4)
        TitleSelectView.show(titles: titles, style: .default, anchorPoint: anchor, selectIndex: selected ?? -1,
                             menuWidth: width, itemHeight: itemHeight, titleColor: SubText_Color,
                             titleFont: .systemFont(ofSize: 12, weight: .regular), backgroundColor: .white,
                             selectBackgroundColor: Bar_Color.withAlphaComponent(0.12), enabledStates: enabled,
                             disabledTitleColor: SubText_Color.withAlphaComponent(0.5), selectedTitleColor: Bar_Color,
                             highlightSelectedWithoutIcon: true, titleAlignment: .left, contentBorderColor: Border_Color,
                             contentBorderWidth: 1, contentCornerRadius: 10,
                             rowHighlightInsets: UIEdgeInsets(top: 4, left: 4, bottom: 4, right: 4),
                             maximumHeight: height, hostWindow: window, selectBack: action)
    }

    static func configureMessage(_ label: UILabel, message: String?, retry: Bool) {
        label.text = message
        label.numberOfLines = 0
        label.textAlignment = .center
        label.lineBreakMode = .byWordWrapping
        label.textColor = retry ? Bar_Color : Message_Color
        label.isUserInteractionEnabled = retry
        label.accessibilityTraits = retry ? [.button] : [.staticText]
        label.accessibilityHint = retry ? "site_zone_retry_hint".localizedString : nil
        label.isHidden = message == nil
    }

    static func proximityHintHeight(width: CGFloat) -> CGFloat {
        let fittingWidth = (width > 0 ? width : SCREEN_WIDTH - 32) - 28
        let size = ("space_trigger_zone_quick_add_hint".localizedString as NSString).boundingRect(
            with: CGSize(width: max(1, fittingWidth), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: UIFont.systemFont(ofSize: 12, weight: .light)], context: nil)
        return ceil(size.height)
    }

    static func minimumHeight(message: String?, width: CGFloat, font: UIFont = .systemFont(ofSize: 14, weight: .light), messageTop: CGFloat = 50) -> CGFloat {
        guard let message else { return 160 }
        let size = (message as NSString).boundingRect(with: CGSize(width: max(width - 32, 160), height: .greatestFiniteMagnitude),
                                                     options: [.usesLineFragmentOrigin, .usesFontLeading],
                                                     attributes: [.font: font], context: nil)
        // Status messages remain centered 20pt below the card center, clear of the top content.
        return max(160, ceil(size.height) + max(86, 2 * (messageTop - 20)))
    }
}
