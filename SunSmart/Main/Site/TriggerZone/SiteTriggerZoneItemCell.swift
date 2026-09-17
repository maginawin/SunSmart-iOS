import UIKit

/// Site alerts follow their owning window during rotation and iPad resizing.
final class SiteTriggerZoneAlertView: SRAlertView {
    override func show() {
        frame = UIApplication.shared.keyWindow().bounds
        super.show()
        snp.remakeConstraints { make in make.edges.equalToSuperview() }
    }
}

/// Shared presentation helpers for the Site-only components.
enum SiteTriggerZoneItemStyle {
    static func syncButton(_ sync: SiteTriggerZoneItemModel.Sync, identifier: String, action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .custom)
        if sync.isUnverified {
            button.setTitle("?", for: .normal)
            button.setTitleColor(AssistText_Color, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
            button.layer.borderColor = AssistText_Color.cgColor
            button.layer.borderWidth = 1
            button.layer.cornerRadius = 12
        } else {
            button.setImage(UIImage(named: "site_zone_sync"), for: .normal)
        }
        button.accessibilityLabel = syncTitle(sync)
        button.accessibilityIdentifier = identifier
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 24),
            button.heightAnchor.constraint(equalToConstant: 24)
        ])
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }

    static func syncAlert() -> SRAlertView {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.minimumLineHeight = 22
        paragraph.maximumLineHeight = 22
        let message = "site_zones_sync_explanation".localizedString
        let alert = SiteTriggerZoneAlertView(title: "devices_not_synced".localizedString,
                                titleColor: Title_Color, titleFont: .systemFont(ofSize: 14, weight: .light),
                                message: message,
                                messageAttStr: NSAttributedString(string: message, attributes: [
                                    .font: UIFont.systemFont(ofSize: 12, weight: .light),
                                    .foregroundColor: Title_Color, .paragraphStyle: paragraph
                                ]),
                                messageColor: Title_Color, messageFont: .systemFont(ofSize: 12, weight: .light),
                                actions: [SRAlertAction(title: "ok".localizedString, titleColor: Title_Color,
                                                        titleFont: .systemFont(ofSize: 15, weight: .light))])
        alert.accessibilityIdentifier = "site-zone-sync-alert"
        alert.firstBtn.accessibilityIdentifier = "site-zone-sync-ok"
        alert.contentView.snp.remakeConstraints { make in
            make.center.equalTo(alert.safeAreaLayoutGuide)
            make.width.equalTo(302).priority(.high)
            make.width.lessThanOrEqualTo(302)
            make.width.lessThanOrEqualTo(alert.safeAreaLayoutGuide).offset(-32)
            make.height.greaterThanOrEqualTo(210)
        }
        alert.titleLabel.snp.remakeConstraints { make in
            make.top.equalTo(24)
            make.left.right.equalToSuperview().inset(27)
        }
        alert.messageLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        alert.messageLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        alert.messageLabel.snp.remakeConstraints { make in
            make.top.equalTo(alert.titleLabel.snp.bottom).offset(12)
            make.left.right.equalTo(alert.titleLabel)
        }
        alert.hLineView.snp.remakeConstraints { make in
            make.left.right.equalToSuperview()
            make.height.equalTo(0.5)
            make.top.equalTo(alert.messageLabel.snp.bottom).offset(12)
        }
        return alert
    }

    static func syncTitle(_ sync: SiteTriggerZoneItemModel.Sync) -> String {
        if sync.cloud == .pending && sync.devices == .pending { return "site_zones_item_sync_both".localizedString }
        if sync.cloud == .pending { return "site_zones_item_sync_cloud".localizedString }
        if sync.devices == .pending { return "site_zones_item_sync_devices".localizedString }
        if sync.cloud == .unknown && sync.devices != .unknown {
            return "site_zones_item_status_unverified".localizedString
        }
        return "site_zones_item_device_unverified".localizedString
    }

    static func label(_ text: String, size: CGFloat = 12, color: UIColor = SubText_Color) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: size, weight: .light)
        label.textColor = color
        return label
    }

    static func icon(_ name: String, size: CGFloat) -> UIImageView {
        let image = UIImageView(image: UIImage(named: name))
        image.contentMode = .scaleAspectFit
        image.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            image.widthAnchor.constraint(equalToConstant: size),
            image.heightAnchor.constraint(equalToConstant: size)
        ])
        return image
    }

    static func accessTitle(_ access: SiteTriggerZoneItemModel.Access) -> String {
        switch access {
        case .owner, .editor, .visitor: return access.rawValue.localizedString
        case .noAccess: return "site_zones_no_access".localizedString
        case .unknown: return "site_zones_access_unknown".localizedString
        }
    }

    static func accessColor(_ access: SiteTriggerZoneItemModel.Access) -> UIColor {
        switch access {
        case .owner: return RGB(112, 103, 237)
        case .editor: return RGB(255, 127, 62)
        case .visitor: return RGB(64, 142, 255)
        case .noAccess: return RGB(255, 62, 62)
        case .unknown: return SubText_Color
        }
    }

    static func pin(_ child: UIView, to parent: UIView, insets: UIEdgeInsets = .zero) {
        child.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(child)
        NSLayoutConstraint.activate([
            child.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: insets.left),
            child.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -insets.right),
            child.topAnchor.constraint(equalTo: parent.topAnchor, constant: insets.top),
            child.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -insets.bottom)
        ])
    }
}

final class SiteTriggerZoneItemBadge: UIView {
    init(text: String, color: UIColor, imageName: String? = nil) {
        super.init(frame: .zero)
        backgroundColor = imageName == nil ? color.withAlphaComponent(0.15) : RGB(239, 239, 244)
        layer.cornerRadius = imageName == nil ? 6 : 5
        let label = SiteTriggerZoneItemStyle.label(text, color: color)
        label.font = .systemFont(ofSize: 12)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        let stack = UIStackView()
        stack.alignment = .center
        stack.spacing = 2
        if let imageName { stack.addArrangedSubview(SiteTriggerZoneItemStyle.icon(imageName, size: 12)) }
        stack.addArrangedSubview(label)
        SiteTriggerZoneItemStyle.pin(stack, to: self, insets: .init(top: 3, left: 8, bottom: 3, right: 8))
        isAccessibilityElement = true
        accessibilityLabel = text
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

private final class SiteTriggerZoneDividerView: UIView {
    override class var layerClass: AnyClass { CAShapeLayer.self }

    override init(frame: CGRect) {
        super.init(frame: frame)
        let shape = layer as! CAShapeLayer
        shape.strokeColor = RGB(202, 213, 227).cgColor
        shape.fillColor = nil
        shape.lineWidth = 1
        shape.lineDashPattern = [2, 2]
        heightAnchor.constraint(equalToConstant: 1).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let path = UIBezierPath()
        path.move(to: CGPoint(x: bounds.minX, y: bounds.midY))
        path.addLine(to: CGPoint(x: bounds.maxX, y: bounds.midY))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        (layer as! CAShapeLayer).path = path.cgPath
        CATransaction.commit()
    }
}

final class SiteTriggerZoneItemCell: UITableViewCell {
    var deviceTap: ((String, String, UIView) -> Void)?
    var syncTap: (() -> Void)?
    private let card = UIView()
    private let stack = UIStackView()
    private var sections: [SiteTriggerZoneSpaceSectionView] = []
    private var item: SiteTriggerZoneItemModel?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none
        card.backgroundColor = .white
        card.layer.cornerRadius = 10
        card.layer.borderColor = Yellow_Color.cgColor
        SiteTriggerZoneItemStyle.pin(card, to: contentView, insets: .init(top: 0, left: 8, bottom: 0, right: 8))
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        let bottom = stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16)
        // UITableView rounds measured heights to pixels. Leave that fraction at the bottom,
        // rather than ambiguously stretching several multiline Space summaries.
        bottom.priority = .init(249)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: card.bottomAnchor, constant: -16), bottom
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ item: SiteTriggerZoneItemModel, selected: Bool, width: CGFloat) {
        card.layer.borderWidth = selected ? 1 : 0
        if self.item != item {
            self.item = item
            stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
            sections = []
            for (index, space) in item.spaces.enumerated() {
                if index > 0 {
                    let divider = SiteTriggerZoneDividerView(frame: .zero)
                    divider.accessibilityIdentifier = "site-zone-divider-\(index)"
                    stack.addArrangedSubview(divider)
                }
                let section = SiteTriggerZoneSpaceSectionView(space: space, locked: !item.canEdit,
                    deviceTap: { [weak self] deviceID, source in self?.deviceTap?(space.id, deviceID, source) },
                    syncTap: { [weak self] in self?.syncTap?() })
                sections.append(section)
                stack.addArrangedSubview(section)
            }
            if item.spaces.isEmpty || !item.hasCompleteSpaceList {
                let message = SiteTriggerZoneItemStyle.label("site_zones_summary_incomplete".localizedString, color: AssistText_Color)
                message.numberOfLines = 0
                stack.addArrangedSubview(message)
            } else if item.hasUnverifiedMembers {
                let message = SiteTriggerZoneItemStyle.label("site_zone_members_need_verification".localizedString,
                                                             color: AssistText_Color)
                message.numberOfLines = 0
                stack.addArrangedSubview(message)
            }
        }
        updateWidth(width)
        if selected { accessibilityTraits.insert(.selected) }
        else { accessibilityTraits.remove(.selected) }
    }

    private func updateWidth(_ width: CGFloat) {
        sections.forEach { $0.updateWidth(max(1, width - 48)) }
    }

    override func systemLayoutSizeFitting(_ targetSize: CGSize, withHorizontalFittingPriority horizontalFittingPriority: UILayoutPriority,
                                         verticalFittingPriority: UILayoutPriority) -> CGSize {
        updateWidth(targetSize.width)
        return super.systemLayoutSizeFitting(targetSize, withHorizontalFittingPriority: horizontalFittingPriority,
                                            verticalFittingPriority: verticalFittingPriority)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        card.layer.borderWidth = 0
        accessibilityValue = nil
        accessibilityTraits.remove(.selected)
        deviceTap = nil
        syncTap = nil
    }
}

final class SiteTriggerZoneSpaceSectionView: UIView {
    private let stack = UIStackView()
    private let row = UIStackView()
    private let countLabel: UILabel
    private let nameLabel: UILabel
    private let badge: SiteTriggerZoneItemBadge
    private var grid: SiteTriggerZoneDeviceGridView?
    private let hasCount: Bool
    private let reservedIconWidth: CGFloat
    private var countOnSecondLine = false

    init(space: SiteTriggerZoneItemModel.Space, locked: Bool,
         deviceTap: @escaping (String, UIView) -> Void = { _, _ in }, syncTap: @escaping () -> Void = {}) {
        let name = space.name?.isEmpty == false ? space.name! : "space".localizedString
        nameLabel = SiteTriggerZoneItemStyle.label(name, size: 14, color: TextBlack_Color)
        badge = SiteTriggerZoneItemBadge(text: SiteTriggerZoneItemStyle.accessTitle(space.access), color: SiteTriggerZoneItemStyle.accessColor(space.access))
        hasCount = space.displayedDeviceCount != nil
        let count = space.displayedDeviceCount ?? 0
        countLabel = SiteTriggerZoneItemStyle.label(String(format: (count == 1 ? "site_zones_device_count_one" : "site_zones_device_count_many").localizedString, count), color: AssistText_Color)
        reservedIconWidth = (locked ? 22 : 0) + (space.sync.showsStatus ? 30 : 0)
        super.init(frame: .zero)
        accessibilityIdentifier = "site-zone-space-\(space.id)"
        stack.axis = .vertical
        stack.spacing = 20
        SiteTriggerZoneItemStyle.pin(stack, to: self)
        row.alignment = .center
        row.spacing = 6
        row.heightAnchor.constraint(equalToConstant: 24).isActive = true
        if locked {
            let lock = SiteTriggerZoneItemStyle.icon("site_zone_lock", size: 16)
            lock.accessibilityIdentifier = "site-zone-lock"
            row.addArrangedSubview(lock)
        }
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.font = .systemFont(ofSize: 14)
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(nameLabel)
        row.addArrangedSubview(badge)
        if hasCount { row.addArrangedSubview(countLabel) }
        countLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        let spacer = UIView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        spacer.heightAnchor.constraint(equalToConstant: 0).isActive = true
        row.addArrangedSubview(spacer)
        if space.sync.showsStatus {
            let sync = SiteTriggerZoneItemStyle.syncButton(space.sync, identifier: "site-zone-space-sync", action: syncTap)
            row.addArrangedSubview(sync)
        }
        stack.addArrangedSubview(row)
        if space.canDisplayDevices && !space.devices.isEmpty {
            let grid = SiteTriggerZoneDeviceGridView(spaceID: space.id, devices: space.devices, canEdit: !locked, deviceTap: deviceTap)
            self.grid = grid
            stack.addArrangedSubview(grid)
        } else {
            let key: String
            if space.access == .noAccess { key = "site_zones_no_access_message" }
            else if !space.canDisplayDevices { key = "site_zones_access_pending_message" }
            else { key = "No_Data" }
            let message = SiteTriggerZoneItemStyle.label(key.localizedString, color: AssistText_Color)
            message.numberOfLines = 0
            message.accessibilityIdentifier = "site-zone-space-message"
            stack.addArrangedSubview(message)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func updateWidth(_ width: CGFloat) {
        let badgeWidth = badge.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).width
        let secondLine = hasCount && width < reservedIconWidth + badgeWidth + countLabel.intrinsicContentSize.width + 78
        if secondLine != countOnSecondLine {
            countOnSecondLine = secondLine
            countLabel.removeFromSuperview()
            if secondLine {
                stack.insertArrangedSubview(countLabel, at: 1)
                stack.setCustomSpacing(4, after: row)
            } else {
                row.insertArrangedSubview(countLabel, at: row.arrangedSubviews.firstIndex(of: badge)! + 1)
                stack.setCustomSpacing(20, after: row)
            }
        }
        grid?.updateWidth(width)
    }
}

/// A non-scrolling grid with an explicit width-derived height for UITableView self sizing.
final class SiteTriggerZoneDeviceGridView: UIView {
    private let rows = UIStackView()
    private let tiles: [UIView]
    private var columnCount = 0
    private var gridHeight: NSLayoutConstraint!
    private let tileSize = GroupPathSequenceDeviceItemMetrics.controlSize
    private let gap: CGFloat = 18

    init(spaceID: String, devices: [SiteTriggerZoneItemModel.Device], canEdit: Bool = false,
         deviceTap: @escaping (String, UIView) -> Void = { _, _ in }) {
        tiles = devices.map { device in
            // Keep the control enabled to consume touches even in a read-only Zone.
            let tile = UIButton(type: .custom)
            tile.addAction(UIAction { [weak tile] _ in
                guard canEdit, let tile else { return }
                deviceTap(device.id, tile)
            }, for: .touchUpInside)
            if !canEdit { tile.accessibilityTraits.insert(.notEnabled) }
            tile.backgroundColor = Background_Color
            tile.layer.cornerRadius = GroupPathSequenceDeviceItemMetrics.controlCornerRadius
            tile.layer.borderWidth = 1
            tile.layer.borderColor = RGB(241, 242, 244).cgColor
            tile.isAccessibilityElement = true
            tile.accessibilityLabel = device.name
            tile.accessibilityIdentifier = "site-zone-device-\(spaceID)-\(device.id)"
            let icon = SiteTriggerZoneItemStyle.icon("path_device_offline", size: GroupPathSequenceDeviceItemMetrics.imageSize)
            icon.image = icon.image?.withRenderingMode(.alwaysTemplate)
            icon.tintColor = SubText_Color
            tile.addSubview(icon)
            let label = SiteTriggerZoneItemStyle.label(device.name)
            label.textAlignment = .center
            label.lineBreakMode = .byTruncatingTail
            label.translatesAutoresizingMaskIntoConstraints = false
            tile.addSubview(label)
            NSLayoutConstraint.activate([
                tile.widthAnchor.constraint(equalToConstant: GroupPathSequenceDeviceItemMetrics.controlSize),
                tile.heightAnchor.constraint(equalToConstant: GroupPathSequenceDeviceItemMetrics.controlSize),
                icon.centerXAnchor.constraint(equalTo: tile.centerXAnchor),
                icon.topAnchor.constraint(equalTo: tile.topAnchor, constant: GroupPathSequenceDeviceItemMetrics.imageTopSpacing),
                label.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: GroupPathSequenceDeviceItemMetrics.imageNameSpacing),
                label.leadingAnchor.constraint(equalTo: tile.leadingAnchor, constant: 4),
                label.trailingAnchor.constraint(equalTo: tile.trailingAnchor, constant: -4),
                label.bottomAnchor.constraint(lessThanOrEqualTo: tile.bottomAnchor, constant: -3)
            ])
            return tile
        }
        super.init(frame: .zero)
        rows.axis = .vertical
        rows.alignment = .leading
        rows.spacing = GroupPathSequenceDeviceItemMetrics.lineSpacing
        SiteTriggerZoneItemStyle.pin(rows, to: self)
        gridHeight = heightAnchor.constraint(equalToConstant: 44)
        gridHeight.isActive = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func updateWidth(_ width: CGFloat) {
        let columns = max(1, Int((width + gap) / (tileSize + gap)))
        guard columns != columnCount else { return }
        columnCount = columns
        tiles.forEach { $0.removeFromSuperview() }
        rows.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for start in stride(from: 0, to: tiles.count, by: columns) {
            let row = UIStackView(arrangedSubviews: Array(tiles[start..<min(start + columns, tiles.count)]))
            row.spacing = gap
            rows.addArrangedSubview(row)
        }
        let rowCount = rows.arrangedSubviews.count
        gridHeight.constant = CGFloat(rowCount) * tileSize + CGFloat(max(0, rowCount - 1)) * rows.spacing
    }
}
