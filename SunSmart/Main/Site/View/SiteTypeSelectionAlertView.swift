import UIKit

/// A transient single choice. Only Done copies the selected value back to the creation form.
final class SiteTypeSelectionAlertView: SRAlertView {
    private var selectedType: SiteExtensionData.ProjectType = .standard
    private var choices: [UIButton] = []

    static func make(selectedType: SiteExtensionData.ProjectType, onDone: @escaping (SiteExtensionData.ProjectType) -> Void) -> SiteTypeSelectionAlertView {
        weak var current: SiteTypeSelectionAlertView?
        let alert = SiteTypeSelectionAlertView(
            title: "site_type_selection".localizedString,
            tapBackgroundHide: false,
            actions: [
                SRAlertAction(title: "alert_item_cancel".localizedString),
                SRAlertAction(title: "done".localizedString) { _ in
                    guard let alert = current else { return }
                    onDone(alert.selectedType)
                }
            ])
        current = alert
        alert.accessibilityIdentifier = "site-type-selection"
        alert.firstBtn.accessibilityIdentifier = "site-type-cancel"
        alert.secondBtn.accessibilityIdentifier = "site-type-done"
        alert.selectedType = selectedType
        alert.setupChoices()
        return alert
    }

    override func show() {
        frame = UIApplication.shared.keyWindow().bounds
        super.show()
        snp.remakeConstraints { make in make.edges.equalToSuperview() }
    }

    private func setupChoices() {
        contentView.snp.remakeConstraints { make in
            make.center.equalTo(safeAreaLayoutGuide)
            make.width.equalTo(340).priority(999)
            make.width.lessThanOrEqualTo(340)
            make.width.lessThanOrEqualTo(safeAreaLayoutGuide).offset(-32)
        }
        titleLabel.snp.remakeConstraints { make in
            make.top.equalTo(24)
            make.left.right.equalToSuperview().inset(24)
        }
        messageLabel.isHidden = true
        // Hidden views still participate in Auto Layout; do not let the empty message shrink this alert.
        messageLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 8
        contentView.addSubview(stack)
        stack.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(16)
            make.left.right.equalToSuperview().inset(20)
        }
        for (index, key) in ["site_type_standard", "site_type_hdb"].enumerated() {
            let button = UIButton(type: .system)
            button.setTitle(key.localizedString, for: .normal)
            button.titleLabel?.font = FONTS(16)
            button.titleLabel?.numberOfLines = 0
            button.contentHorizontalAlignment = .left
            var configuration = UIButton.Configuration.plain()
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
            configuration.imagePadding = 8
            configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                var attributes = attributes
                attributes.font = FONTS(16)
                return attributes
            }
            button.configuration = configuration
            button.layer.cornerRadius = 8
            button.accessibilityIdentifier = index == 0 ? "site-type-standard" : "site-type-hdb"
            button.addAction(UIAction { [weak self] _ in
                self?.selectedType = index == 1 ? .hdb : .standard
                self?.updateSelection()
            }, for: .touchUpInside)
            stack.addArrangedSubview(button)
            button.snp.makeConstraints { make in make.height.greaterThanOrEqualTo(48) }
            choices.append(button)
        }
        hLineView.snp.remakeConstraints { make in
            make.top.equalTo(stack.snp.bottom).offset(16)
            make.left.right.equalToSuperview()
            make.height.equalTo(0.5)
        }
        updateSelection()
    }

    private func updateSelection() {
        for (index, button) in choices.enumerated() {
            let selected = (index == 1 ? SiteExtensionData.ProjectType.hdb : .standard) == selectedType
            button.setImage(UIImage(systemName: selected ? "checkmark.circle.fill" : "circle"), for: .normal)
            button.tintColor = selected ? Bar_Color : AssistText_Color
            button.setTitleColor(Title_Color, for: .normal)
            button.backgroundColor = selected ? Bar_Color.withAlphaComponent(0.1) : .clear
            button.accessibilityTraits = selected ? [.button, .selected] : [.button]
        }
    }
}
