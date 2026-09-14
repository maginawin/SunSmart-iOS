import UIKit

final class SiteTriggerZoneItemHeaderView: UITableViewHeaderFooterView, UIGestureRecognizerDelegate {
    enum Operation: CaseIterable {
        case test, reset, delete, save
        var key: String {
            switch self {
            case .test: return "test"
            case .reset: return "reset"
            case .delete: return "delete"
            case .save: return "Save"
            }
        }
    }

    var select: (() -> Void)?
    var operate: ((Operation) -> Void)?
    var syncTap: (() -> Void)?

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        // Only the title area gets the selection gesture; buttons retain their own action.
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ item: SiteTriggerZoneItemModel, selected: Bool, width: CGFloat, actionsEnabled: Bool) {
        contentView.subviews.forEach { $0.removeFromSuperview() }
        let titleRow = UIStackView()
        titleRow.alignment = .center
        titleRow.spacing = 8
        titleRow.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleRow)
        let name = UILabel(text: item.name, textColor: SubText_Color, fontSize: 14, fontWeight: .light)
        name.accessibilityIdentifier = "site-zone-item-name"
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        name.lineBreakMode = .byTruncatingTail
        titleRow.addArrangedSubview(name)
        if item.sync.showsStatus {
            let icon = SiteTriggerZoneItemStyle.syncButton(item.sync, identifier: "site-zone-metadata-sync") { [weak self] in
                self?.syncTap?()
            }
            titleRow.addArrangedSubview(icon)
        }
        if !item.canEdit {
            let badge = SiteTriggerZoneItemBadge(text: "site_zones_view_only".localizedString,
                                                color: SubText_Color, imageName: "site_zone_view_only")
            badge.accessibilityIdentifier = "site-zone-view-only"
            titleRow.addArrangedSubview(badge)
        }
        let spacer = UIView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        spacer.heightAnchor.constraint(equalToConstant: 0).isActive = true
        titleRow.addArrangedSubview(spacer)
        let selectionTap = UITapGestureRecognizer(target: self, action: #selector(selectAction))
        selectionTap.delegate = self
        titleRow.addGestureRecognizer(selectionTap)
        // Match the legacy No Data header. Selection must not affect vertical geometry.
        NSLayoutConstraint.activate([
            titleRow.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: SCRXFrom(8)),
            titleRow.heightAnchor.constraint(equalToConstant: max(24, ceil(name.font.lineHeight))),
            name.topAnchor.constraint(equalTo: contentView.topAnchor, constant: SCRYFrom(15))
        ])
        if selected {
            let actions = UIStackView()
            actions.spacing = SCRXFrom(8)
            actions.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(actions)
            for (index, operation) in Operation.allCases.enumerated() {
                let button = UIButton(type: .custom)
                button.setTitle(operation.key.localizedString, for: .normal)
                button.titleLabel?.font = .systemFont(ofSize: SCRYFrom(12))
                button.setTitleColor(Bar_Color, for: .normal)
                button.setTitleColor(Bar_Color.withAlphaComponent(0.5), for: .disabled)
                let allowed: Bool
                if item.previewCode != nil {
                    allowed = !(item.usesEmptyStyle && (operation == .test || operation == .reset))
                } else {
                    switch operation {
                    case .test: allowed = false
                    case .reset: allowed = item.hasUnsavedChanges
                    case .delete: allowed = item.usesEmptyStyle && !item.hasSavedMembers && !item.hasUnsavedChanges
                    case .save: allowed = item.hasUnsavedChanges || item.sync.cloud == .pending
                        || item.needsCloudMigration
                    }
                }
                button.isEnabled = actionsEnabled && allowed && (item.previewCode != nil || item.canEdit)
                button.tag = index
                button.accessibilityIdentifier = "site-zone-item-\(operation.key.lowercased())-\(item.id.uuidString)"
                button.addTarget(self, action: #selector(operationAction(_:)), for: .touchUpInside)
                button.backgroundColor = .white
                button.layer.cornerRadius = SCRYFrom(5)
                button.layer.borderWidth = 1
                button.layer.borderColor = RGB(220, 220, 220).cgColor
                button.widthAnchor.constraint(equalToConstant: SCRXFrom(44)).isActive = true
                button.heightAnchor.constraint(equalToConstant: CGFloat(Int(SCRYFrom(28)))).isActive = true
                actions.addArrangedSubview(button)
            }
            NSLayoutConstraint.activate([
                actions.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: SCRXFrom(-9)),
                actions.topAnchor.constraint(equalTo: contentView.topAnchor, constant: SCRYFrom(8)),
                titleRow.trailingAnchor.constraint(equalTo: actions.leadingAnchor, constant: SCRXFrom(-8))
            ])
        } else {
            titleRow.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: SCRXFrom(-9)).isActive = true
        }
    }

    @objc private func selectAction() { select?() }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var view = touch.view
        while let current = view, current !== gestureRecognizer.view {
            if current is UIControl { return false }
            view = current.superview
        }
        return true
    }
    @objc private func operationAction(_ sender: UIButton) { operate?(Operation.allCases[sender.tag]) }
    override func prepareForReuse() {
        super.prepareForReuse()
        select = nil
        operate = nil
        syncTap = nil
    }
}
