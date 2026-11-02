import UIKit

/// Both permission explanations share the existing alert lifecycle; every dismissal resolves exactly once.
final class SiteLocationPermissionAlertView: SRAlertView {
    private var decision = false
    private var isFinishing = false
    private var onDecision: ((Bool) -> Void)?

    static func make(prompt: SiteCurrentLocationRequest.Prompt,
                     onDecision: @escaping (Bool) -> Void) -> SiteLocationPermissionAlertView {
        weak var current: SiteLocationPermissionAlertView?
        let allow = SRAlertAction(title: "site_create_location_allow".localizedString,
                                  titleColor: RGB(0, 122, 255), titleFont: .systemFont(ofSize: 17, weight: .semibold),
                                  closeAlert: false) { _ in current?.resolve(true) }
        let deny = SRAlertAction(title: "site_create_location_dont_allow".localizedString,
                                 titleColor: RGB(0, 122, 255), titleFont: .systemFont(ofSize: 17),
                                 closeAlert: false) { _ in current?.resolve(false) }
        let settings = SRAlertAction(title: "site_create_location_denied_action".localizedString,
                                     titleColor: RGB(251, 44, 54), titleFont: .systemFont(ofSize: 13),
                                     closeAlert: false) { _ in current?.resolve(true) }
        let alert = SiteLocationPermissionAlertView(
            title: String(format: "site_create_location_permission_title".localizedString, appName),
            titleColor: RGB(30, 35, 41), titleFont: .systemFont(ofSize: 13, weight: .semibold),
            message: "site_create_location_permission_message".localizedString,
            messageColor: RGB(60, 60, 67, 0.6), messageFont: .systemFont(ofSize: 12),
            tapBackgroundHide: false, actionHeight: 49.5,
            actions: prompt == .permission ? [deny, allow] : [settings])
        current = alert
        alert.onDecision = onDecision
        alert.configure(prompt: prompt)
        return alert
    }

    override func show() {
        frame = UIApplication.shared.keyWindow().bounds
        super.show()
        snp.remakeConstraints { make in make.edges.equalToSuperview() }
    }

    override func dismiss(animation: Bool = true, completion: (() -> Void)? = nil) {
        guard !isFinishing else { return }
        isFinishing = true
        let callback = onDecision
        onDecision = nil
        let result = decision
        super.dismiss(animation: animation) {
            completion?()
            callback?(result)
        }
    }

    private func resolve(_ decision: Bool) {
        guard !isFinishing else { return }
        self.decision = decision
        dismiss()
    }

    @objc private func cancelFromBackground() { resolve(false) }

    private func configure(prompt: SiteCurrentLocationRequest.Prompt) {
        accessibilityIdentifier = "site-location-permission-alert"
        accessibilityViewIsModal = true
        shadeView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(cancelFromBackground)))
        contentView.layer.cornerRadius = 18
        contentView.layer.masksToBounds = false
        contentView.layer.shadowColor = UIColor.black.cgColor
        contentView.layer.shadowOpacity = 0.25
        contentView.layer.shadowRadius = 25
        contentView.layer.shadowOffset = CGSize(width: 0, height: 25)
        contentView.snp.remakeConstraints { make in
            make.center.equalTo(safeAreaLayoutGuide)
            make.width.equalTo(343).priority(999)
            make.width.lessThanOrEqualTo(343)
            make.width.lessThanOrEqualTo(safeAreaLayoutGuide).offset(-32)
        }
        let badge = UIView()
        badge.backgroundColor = RGB(104, 100, 179)
        badge.layer.cornerRadius = 14
        contentView.addSubview(badge)
        badge.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(24)
            make.centerX.equalToSuperview()
            make.width.height.equalTo(56)
        }
        let icon = UIImageView(image: UIImage(named: "site_location_permission"))
        badge.addSubview(icon)
        icon.snp.makeConstraints { make in make.center.equalToSuperview(); make.width.height.equalTo(28) }
        titleLabel.snp.remakeConstraints { make in
            make.top.equalTo(badge.snp.bottom).offset(12)
            make.left.right.equalToSuperview().inset(20)
        }
        messageLabel.lineBreakMode = .byWordWrapping
        messageLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        messageLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        messageLabel.snp.remakeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(8)
            make.left.right.equalToSuperview().inset(20)
        }
        for (label, lineHeight) in [(titleLabel!, CGFloat(17.875)), (messageLabel!, CGFloat(16))] {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            paragraph.minimumLineHeight = lineHeight
            paragraph.maximumLineHeight = lineHeight
            label.attributedText = NSAttributedString(string: label.text ?? "", attributes: [
                .font: label.font!, .foregroundColor: label.textColor!, .paragraphStyle: paragraph
            ])
        }
        hLineView.backgroundColor = RGB(229, 229, 234)
        hLineView.snp.remakeConstraints { make in
            make.top.equalTo(messageLabel.snp.bottom).offset(24)
            make.left.right.equalToSuperview()
            make.height.equalTo(0.5)
        }
        firstBtn.accessibilityIdentifier = prompt == .permission ? "site-location-dont-allow" : "site-location-settings"
        secondBtn.accessibilityIdentifier = "site-location-allow"
        // The shared alert's horizontal actions default to 60pt, independent of actionHeight.
        firstBtn.snp.updateConstraints { make in make.height.equalTo(49.5) }
        if prompt == .settings {
            firstBtn.setImage(UIImage(named: "site_location_denied"), for: .normal)
            var configuration = UIButton.Configuration.plain()
            configuration.imagePadding = 8
            configuration.baseForegroundColor = RGB(251, 44, 54)
            configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                var attributes = attributes
                attributes.font = UIFont.systemFont(ofSize: 13)
                return attributes
            }
            firstBtn.configuration = configuration
        }
    }
}
