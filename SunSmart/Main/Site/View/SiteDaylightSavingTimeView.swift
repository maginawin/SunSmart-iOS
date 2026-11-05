import UIKit

/// Reusable presentation only: hosts supply timezone data and own disclosure state.
final class SiteDaylightSavingTimeView: UIView {
    enum Style { case formDisclosure, gatewaySummary }
    private let style: Style
    var onToggleExpansion: (() -> Void)?
    var onLayoutChanged: (() -> Void)?

    private let disclosureButton = UIButton(type: .custom)
    private let summaryHeader = UIView()
    private let arrow = UIImageView(image: UIImage(named: "site_dst_disclosure"))
    private let badge = UIView()
    private let statusLabel = UILabel()
    private let currentValue = UILabel()
    private let nextValue = UILabel()
    private let targetValue = UILabel()
    private let staleLabel = UILabel()
    private let helpContainer = UIView()
    private var rendered: SiteDaylightSavingTimePresentation?

    init(frame: CGRect = .zero, style: Style = .formDisclosure) {
        self.style = style
        super.init(frame: frame)
        backgroundColor = style == .gatewaySummary ? .white : .clear
        if style == .gatewaySummary { layer.cornerRadius = SCRYFrom(10) }
        isHidden = true
        clipsToBounds = true
        accessibilityIdentifier = "site-dst-hint"
        let stack = verticalStack(spacing: style == .gatewaySummary ? 0 : 4)
        addSubview(stack)
        stack.snp.makeConstraints { make in
            make.top.left.right.equalToSuperview()
            // UIStackView assigns zero height while this entire arranged view is hidden.
            make.bottom.equalToSuperview().priority(999)
        }
        setupHeader(in: stack)
        setupCard(in: stack)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func render(_ presentation: SiteDaylightSavingTimePresentation) {
        guard rendered != presentation else { return }
        rendered = presentation
        isHidden = presentation.content == nil
        accessibilityElementsHidden = isHidden
        guard let content = presentation.content else {
            helpContainer.isHidden = true
            helpContainer.accessibilityElementsHidden = true
            onLayoutChanged?()
            return
        }
        setText(content.currentOffset, on: currentValue)
        setText(content.nextSwitch, on: nextValue)
        setText(content.switchesTo, on: targetValue)
        switch content.status {
        case .active:
            statusLabel.text = "site_dst_active".localizedString
            statusLabel.textColor = RGB(0, 122, 85)
            badge.backgroundColor = RGB(208, 250, 229)
        case .inactive:
            statusLabel.text = "site_dst_inactive".localizedString
            statusLabel.textColor = RGB(224, 146, 0)
            badge.backgroundColor = RGB(224, 146, 0).withAlphaComponent(0.1)
        case .refreshRequired:
            statusLabel.text = "site_time_zone_refresh_required".localizedString
            statusLabel.textColor = RGB(102, 116, 140)
            badge.backgroundColor = RGB(102, 116, 140).withAlphaComponent(0.1)
        }
        staleLabel.isHidden = content.status != .refreshRequired
        let expanded = style == .formDisclosure && presentation.allowsExpansion && presentation.isExpanded
        helpContainer.isHidden = !expanded
        helpContainer.accessibilityElementsHidden = !expanded
        arrow.transform = presentation.isExpanded ? CGAffineTransform(rotationAngle: .pi) : .identity
        let disclosure = (presentation.isExpanded ? "site_create_expanded" : "site_create_collapsed").localizedString
        disclosureButton.accessibilityValue = [statusLabel.text, disclosure].compactMap { $0 }.joined(separator: ", ")
        summaryHeader.accessibilityValue = statusLabel.text
        onLayoutChanged?()
    }

    private func setupHeader(in stack: UIStackView) {
        let row = UIStackView()
        row.alignment = .center
        row.spacing = SCRXFrom(6)
        row.isUserInteractionEnabled = false
        let clock = UIImageView(image: UIImage(named: "site_dst_clock"))
        clock.contentMode = .scaleAspectFit
        clock.snp.makeConstraints { $0.width.height.equalTo(SCRYFrom(14)) }
        row.addArrangedSubview(clock)
        let title = label("site_dst_title", color: RGB(44, 45, 63))
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        if style == .gatewaySummary { title.setContentHuggingPriority(.defaultLow, for: .horizontal) }
        row.addArrangedSubview(title)

        configureLabel(statusLabel, size: 10, color: RGB(102, 116, 140), weight: .semibold)
        statusLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        badge.layer.cornerRadius = SCRYFrom(9)
        badge.addSubview(statusLabel)
        statusLabel.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: SCRYFrom(2), left: SCRXFrom(6), bottom: SCRYFrom(2), right: SCRXFrom(6)))
            make.height.greaterThanOrEqualTo(SCRYFrom(14))
        }
        row.addArrangedSubview(badge)
        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        if style == .formDisclosure { row.addArrangedSubview(spacer) }
        arrow.contentMode = .scaleAspectFit
        arrow.snp.makeConstraints { $0.width.height.equalTo(SCRYFrom(14)) }
        if style == .formDisclosure { row.addArrangedSubview(arrow) }
        arrow.isHidden = style == .gatewaySummary

        let header: UIView = style == .gatewaySummary ? summaryHeader : disclosureButton
        header.addSubview(row)
        row.snp.makeConstraints { make in
            let vertical: CGFloat = style == .gatewaySummary ? 14 : 8
            let horizontal: CGFloat = style == .gatewaySummary ? 16 : 4
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: SCRYFrom(vertical), left: SCRXFrom(horizontal), bottom: SCRYFrom(vertical), right: SCRXFrom(horizontal)))
        }
        header.snp.makeConstraints { $0.height.greaterThanOrEqualTo(SCRYFrom(style == .gatewaySummary ? 46 : 44)) }
        if style == .formDisclosure {
            disclosureButton.addTarget(self, action: #selector(toggleExpansion), for: .touchUpInside)
        } else {
            summaryHeader.accessibilityTraits = .staticText
        }
        header.isAccessibilityElement = true
        header.accessibilityLabel = title.text
        header.accessibilityIdentifier = style == .gatewaySummary ? "gateway-dst-summary-header" : "site-dst-disclosure"
        stack.addArrangedSubview(header)
    }

    private func setupCard(in stack: UIStackView) {
        let card = UIView()
        card.backgroundColor = .white
        card.layer.borderColor = RGB(220, 220, 220).cgColor
        card.layer.borderWidth = style == .gatewaySummary ? 0 : 0.5
        card.layer.cornerRadius = style == .gatewaySummary ? 0 : SCRYFrom(10)
        card.clipsToBounds = true
        stack.addArrangedSubview(card)
        let content = verticalStack()
        card.addSubview(content)
        content.snp.makeConstraints { $0.edges.equalToSuperview() }
        if style == .gatewaySummary {
            let separator = UIView()
            separator.backgroundColor = RGB(193, 207, 226).withAlphaComponent(0.4)
            separator.snp.makeConstraints { $0.height.equalTo(0.5) }
            content.addArrangedSubview(separator)
        }

        let summary = verticalStack(spacing: style == .gatewaySummary ? 10 : 8)
        summary.isLayoutMarginsRelativeArrangement = true
        summary.layoutMargins = UIEdgeInsets(top: SCRYFrom(style == .gatewaySummary ? 10 : 12), left: SCRXFrom(16), bottom: SCRYFrom(12), right: SCRXFrom(16))
        summary.addArrangedSubview(summaryRow("site_dst_current_offset", value: currentValue, identifier: "site-dst-current-offset"))
        summary.addArrangedSubview(summaryRow("site_dst_next_switch", value: nextValue, identifier: "site-dst-next-switch"))
        summary.addArrangedSubview(summaryRow("site_dst_switches_to", value: targetValue, identifier: "site-dst-switches-to"))
        configureLabel(staleLabel, size: 12, color: RGB(102, 116, 140), weight: .regular)
        setText("site_dst_cached_details".localizedString, on: staleLabel)
        staleLabel.accessibilityIdentifier = "site-dst-stale"
        staleLabel.isHidden = true
        summary.addArrangedSubview(staleLabel)
        content.addArrangedSubview(summary)
        if style == .formDisclosure {
            setupHelp()
            content.addArrangedSubview(helpContainer)
        }
    }

    private func summaryRow(_ key: String, value: UILabel, identifier: String) -> UIView {
        let row = UIStackView()
        row.alignment = .top
        row.spacing = SCRXFrom(12)
        let title = label(key, color: style == .gatewaySummary ? RGB(148, 163, 184) : RGB(154, 164, 183))
        title.setContentHuggingPriority(.required, for: .horizontal)
        configureLabel(value, size: 12, color: style == .gatewaySummary ? RGB(64, 79, 102) : RGB(44, 45, 63), weight: .regular)
        value.textAlignment = .right
        value.lineBreakMode = .byCharWrapping
        value.accessibilityIdentifier = identifier
        row.addArrangedSubview(title)
        row.addArrangedSubview(value)
        title.snp.makeConstraints { $0.width.lessThanOrEqualTo(row.snp.width).multipliedBy(0.42) }
        return row
    }

    private func setupHelp() {
        helpContainer.isHidden = true
        helpContainer.clipsToBounds = true
        let separator = UIView()
        separator.backgroundColor = RGB(193, 207, 226).withAlphaComponent(0.4)
        helpContainer.addSubview(separator)
        separator.snp.makeConstraints { make in make.top.left.right.equalToSuperview(); make.height.equalTo(0.667) }
        let help = verticalStack(spacing: 12)
        helpContainer.addSubview(help)
        help.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(SCRYFrom(12))
            make.left.right.equalToSuperview().inset(SCRXFrom(16))
            make.bottom.equalToSuperview().inset(SCRYFrom(12)).priority(999)
        }
        let heading = label("site_dst_help_title", color: RGB(154, 164, 183), size: 10, weight: .semibold)
        setText("site_dst_help_title".localizedString.uppercased(), on: heading, lineHeight: 14)
        help.addArrangedSubview(heading)
        help.addArrangedSubview(helpRow(icon: textBadge("G", color: RGB(104, 100, 179), background: RGB(104, 100, 179).withAlphaComponent(0.1)),
                                       title: "site_dst_with_gateway", paragraphs: ["site_dst_with_gateway_help"]))
        help.addArrangedSubview(helpRow(icon: textBadge("!", color: RGB(187, 77, 0), background: RGB(254, 243, 198)),
                                       title: "site_dst_without_gateway", paragraphs: ["site_dst_without_gateway_help"]))
        let transition = UIImageView(image: UIImage(named: "site_dst_transition"))
        transition.contentMode = .scaleAspectFit
        transition.snp.makeConstraints { $0.width.height.equalTo(SCRYFrom(20)) }
        help.addArrangedSubview(helpRow(icon: transition, title: "site_dst_next_transition",
                                       paragraphs: ["site_dst_next_with_gateway_help", "site_dst_next_without_gateway_help"]))
    }

    private func helpRow(icon: UIView, title: String, paragraphs: [String]) -> UIView {
        let row = UIStackView()
        row.alignment = .top
        row.spacing = SCRXFrom(10)
        let iconSlot = UIView()
        iconSlot.addSubview(icon)
        icon.snp.makeConstraints { make in make.top.equalToSuperview().offset(SCRYFrom(2)); make.left.right.bottom.equalToSuperview() }
        row.addArrangedSubview(iconSlot)
        let text = verticalStack(spacing: 2)
        text.addArrangedSubview(label(title, color: RGB(30, 35, 41)))
        for (index, key) in paragraphs.enumerated() {
            let body = label(key, color: RGB(102, 116, 140), weight: .light)
            if paragraphs.count > 1 {
                // Keep the localized prefix in the same paragraph, in the design's primary color.
                let prefix = (index == 0 ? "site_dst_with_gateway" : "site_dst_without_gateway").localizedString
                if let source = body.attributedText, source.string.hasPrefix(prefix) {
                    let attributed = NSMutableAttributedString(attributedString: source)
                    attributed.addAttribute(.foregroundColor, value: RGB(44, 45, 63), range: NSRange(location: 0, length: (prefix as NSString).length))
                    body.attributedText = attributed
                }
            }
            text.addArrangedSubview(body)
            if index < paragraphs.count - 1 { text.setCustomSpacing(SCRYFrom(6), after: body) }
        }
        row.addArrangedSubview(text)
        return row
    }

    private func textBadge(_ text: String, color: UIColor, background: UIColor) -> UIView {
        let badge = UIView()
        badge.backgroundColor = background
        badge.layer.cornerRadius = SCRYFrom(10)
        badge.snp.makeConstraints { $0.width.height.equalTo(SCRYFrom(20)) }
        let title = UILabel()
        title.text = text
        title.textColor = color
        title.font = .systemFont(ofSize: SCRYFrom(10), weight: .bold)
        badge.addSubview(title)
        title.snp.makeConstraints { $0.center.equalToSuperview() }
        badge.isAccessibilityElement = false
        badge.accessibilityElementsHidden = true
        return badge
    }

    private func verticalStack(spacing: CGFloat = 0) -> UIStackView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = SCRYFrom(spacing)
        return stack
    }

    private func label(_ key: String, color: UIColor, size: CGFloat = 12, weight: UIFont.Weight = .regular) -> UILabel {
        let result = UILabel()
        configureLabel(result, size: size, color: color, weight: weight)
        setText(key.localizedString, on: result, lineHeight: size == 10 ? 14 : 16)
        return result
    }

    private func configureLabel(_ label: UILabel, size: CGFloat, color: UIColor, weight: UIFont.Weight) {
        label.font = .systemFont(ofSize: SCRYFrom(size), weight: weight)
        label.textColor = color
        label.numberOfLines = 0
        label.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)
    }

    private func setText(_ text: String, on label: UILabel, lineHeight: CGFloat = 16) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = SCRYFrom(lineHeight)
        paragraph.alignment = label.textAlignment
        paragraph.lineBreakMode = label.lineBreakMode
        label.attributedText = NSAttributedString(string: text, attributes: [.paragraphStyle: paragraph])
    }

    @objc private func toggleExpansion() {
        guard style == .formDisclosure, rendered?.allowsExpansion == true else { return }
        onToggleExpansion?()
    }
}
