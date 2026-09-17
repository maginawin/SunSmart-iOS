import UIKit

/// Read-only candidates supplied by the owning page; never wraps an SDK Node.
struct GroupPathSequenceBrowseConfiguration {
    enum ConnectionPhase: Equatable {
        case idle, connecting, connected, failed
    }
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
    var connectionPhase: ConnectionPhase = .idle
    var quickConnectionActive = false
    var startConnection: (() -> Void)?
    var retryConnection: (() -> Void)?
    var quickState: QuickAddState = .stop
    var changeQuickState: ((QuickAddState) -> Void)?
    var triggerDevices: [Device] = []
    var selectedDeviceID: String?
    var selectDevice: ((String) -> Void)?
    var connectedNoticeKey = "site_zone_add_unavailable"
    var showHelp: (() -> Void)?

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

/// Connection feedback shared by the three Site Zone browse tabs.
final class GroupPathSequenceConnectionStatusView: UIView {
    private let icon = UIImageView()
    private let label = UILabel()
    private let notice = UILabel()
    private let retryButton = UIButton(type: .system)
    private let statusRow = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .white
        statusRow.axis = .horizontal
        statusRow.alignment = .center
        statusRow.spacing = 8
        icon.contentMode = .scaleAspectFit
        icon.snp.makeConstraints { $0.width.height.equalTo(24) }
        label.font = .systemFont(ofSize: 14, weight: .light)
        label.textColor = ImportantText_Color
        label.lineBreakMode = .byTruncatingMiddle
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        statusRow.addArrangedSubview(icon)
        statusRow.addArrangedSubview(label)
        addSubview(statusRow)
        notice.font = .systemFont(ofSize: 11, weight: .light)
        notice.textColor = SubText_Color
        notice.textAlignment = .center
        notice.numberOfLines = 2
        notice.text = "site_zone_add_unavailable".localizedString
        addSubview(notice)
        notice.snp.makeConstraints {
            $0.top.equalTo(statusRow.snp.bottom).offset(3)
            $0.centerX.equalToSuperview()
            $0.left.greaterThanOrEqualTo(12)
            $0.right.lessThanOrEqualTo(-12)
            $0.bottom.lessThanOrEqualToSuperview()
        }
        retryButton.setTitle("retry".localizedString, for: .normal)
        retryButton.setTitleColor(.white, for: .normal)
        retryButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .light)
        retryButton.backgroundColor = Bar_Color
        retryButton.layer.cornerRadius = 5
        retryButton.accessibilityIdentifier = "site-zone-connection-retry"
        retryButton.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)
        addSubview(retryButton)
        retryButton.snp.makeConstraints {
            $0.width.equalTo(68)
            $0.height.equalTo(28)
            $0.right.equalTo(-12)
            $0.centerY.equalToSuperview()
        }
        statusRow.snp.makeConstraints {
            $0.centerX.equalToSuperview()
            $0.centerY.equalToSuperview()
            $0.left.greaterThanOrEqualTo(12)
            $0.right.lessThanOrEqualTo(-12)
        }
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(phase: GroupPathSequenceBrowseConfiguration.ConnectionPhase, spaceName: String?,
                noticeText: String, retry: (() -> Void)?) {
        notice.text = noticeText
        switch phase {
        case .idle:
            isHidden = true
            notice.isHidden = true
            icon.layer.removeAnimation(forKey: "rotation")
        case .connecting:
            isHidden = false
            notice.isHidden = true
            icon.image = UIImage(named: "loading_20")
            label.text = String(format: "site_zone_connecting_to_space".localizedString, spaceName ?? "")
            retryButton.isHidden = true
            let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
            rotation.fromValue = 0
            rotation.toValue = CGFloat.pi * 2
            rotation.duration = 1
            rotation.repeatCount = .infinity
            icon.layer.add(rotation, forKey: "rotation")
        case .connected:
            isHidden = false
            notice.isHidden = false
            icon.layer.removeAnimation(forKey: "rotation")
            icon.image = UIImage(named: "toast_success")
            label.text = String(format: "site_zone_connected_to_space".localizedString, spaceName ?? "")
            retryButton.isHidden = true
        case .failed:
            isHidden = false
            notice.isHidden = true
            icon.layer.removeAnimation(forKey: "rotation")
            icon.image = UIImage(named: "alert_failed")
            label.text = "wifi_firmware_connection_failed".localizedString
            retryButton.isHidden = false
        }
        statusRow.snp.remakeConstraints {
            $0.centerX.equalToSuperview().offset(phase == .failed ? -25 : 0)
            $0.centerY.equalToSuperview().offset(phase == .connected ? -11 : 0)
            $0.left.greaterThanOrEqualTo(12)
            if phase == .failed { $0.right.lessThanOrEqualTo(retryButton.snp.left).offset(-8) }
            else { $0.right.lessThanOrEqualTo(-12) }
        }
        retryButtonAction = retry
    }

    private var retryButtonAction: (() -> Void)?

    @objc private func retryTapped() { retryButtonAction?() }
}
