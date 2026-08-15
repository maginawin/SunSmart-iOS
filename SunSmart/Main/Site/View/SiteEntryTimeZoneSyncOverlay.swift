//
//  SiteEntryTimeZoneSyncOverlay.swift
//  SunSmart
//
//  Created by One on 2026/8/12.
//

import UIKit
import SnapKit

final class SiteEntryTimeZoneSyncOverlay: UIView {

    enum State: Equatable {
        case checking
        case gatewaysNeedSync(SiteEntryTimeZoneResult)
        case result(SiteEntryTimeZoneResult)
    }

    var onGotIt: (() -> Void)?
    var onLater: (() -> Void)?
    var onReviewSync: (() -> Void)?

    private let checkingCardView = UIView()
    private let loadingImageView = UIImageView(
        image: UIImage(named: "site_entry_sync_loading")
    )
    private let resultLargeShadowView = UIView()
    private let resultSmallShadowView = UIView()
    private let resultCardView = UIView()
    private let titleLabel = UILabel()
    private let siteRow = StatusRowView()
    private let gatewayRow = StatusRowView()
    private let footerDividerView = UIView()
    private let footerVerticalDividerView = UIView()
    private let gotItButton = UIButton(type: .system)
    private let laterButton = UIButton(type: .system)
    private let reviewSyncButton = UIButton(type: .system)

    private(set) var state: State = .checking

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
        update(state: .checking)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        [resultLargeShadowView, resultSmallShadowView].forEach { shadowView in
            shadowView.layer.shadowPath = UIBezierPath(
                roundedRect: shadowView.bounds,
                cornerRadius: SCRYFrom(24)
            ).cgPath
        }
    }

    func showChecking(in container: UIView) {
        update(state: .checking)
        if superview !== container {
            removeFromSuperview()
            container.addSubview(self)
            snp.makeConstraints { make in
                make.edges.equalToSuperview()
            }
        }
    }

    func showResult(_ result: SiteEntryTimeZoneResult) {
        if result.site == .failedToUpdateServer {
            update(state: .result(result))
            return
        }
        switch result.gateway {
        case .pending:
            update(state: .gatewaysNeedSync(result))
        case .noGateways, .inSync:
            update(state: .result(result))
        }
    }

    func dismiss() {
        loadingImageView.layer.removeAnimation(forKey: "siteEntrySyncLoading")
        removeFromSuperview()
    }

    private func setupUI() {
        backgroundColor = UIColor.black.withAlphaComponent(0.4)
        accessibilityViewIsModal = true
        setupCheckingCard()
        setupResultCard()
    }

    private func setupCheckingCard() {
        checkingCardView.backgroundColor = UIColor.white.withAlphaComponent(0.9)
        checkingCardView.layer.cornerRadius = SCRYFrom(20)
        checkingCardView.layer.shadowColor = UIColor.black.cgColor
        checkingCardView.layer.shadowOpacity = 0.1
        checkingCardView.layer.shadowOffset = CGSize(width: 0, height: SCRYFrom(5))
        checkingCardView.layer.shadowRadius = SCRYFrom(4)
        addSubview(checkingCardView)
        checkingCardView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.equalTo(SCRXFrom(302)).priority(.high)
            make.height.greaterThanOrEqualTo(SCRYFrom(188))
            make.left.greaterThanOrEqualTo(safeAreaLayoutGuide.snp.left).offset(SCRXFrom(8))
            make.right.lessThanOrEqualTo(safeAreaLayoutGuide.snp.right).offset(SCRXFrom(-8))
        }

        loadingImageView.contentMode = .scaleAspectFit
        checkingCardView.addSubview(loadingImageView)
        loadingImageView.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(SCRYFrom(26))
            make.centerX.equalToSuperview()
            make.size.equalTo(SCRYFrom(39))
        }

        let checkingTitle = makeLabel(
            text: "site_entry_sync_checking_title".localizedString,
            size: 18,
            color: RGB(30, 35, 41),
            alignment: .center
        )
        let checkingMessage = makeLabel(
            text: "site_entry_sync_checking_message".localizedString,
            size: 15,
            color: RGB(100, 116, 139),
            alignment: .center
        )
        checkingCardView.addSubview(checkingTitle)
        checkingCardView.addSubview(checkingMessage)
        checkingTitle.snp.makeConstraints { make in
            make.top.equalTo(loadingImageView.snp.bottom).offset(SCRYFrom(12))
            make.left.right.equalToSuperview().inset(SCRXFrom(24))
        }
        checkingMessage.snp.makeConstraints { make in
            make.top.equalTo(checkingTitle.snp.bottom).offset(SCRYFrom(8))
            make.left.right.equalToSuperview().inset(SCRXFrom(24))
            make.bottom.lessThanOrEqualToSuperview().offset(SCRYFrom(-20))
        }
    }

    private func setupResultCard() {
        configureShadow(
            resultLargeShadowView,
            offset: CGSize(width: 0, height: SCRYFrom(20)),
            radius: SCRYFrom(12.5)
        )
        configureShadow(
            resultSmallShadowView,
            offset: CGSize(width: 0, height: SCRYFrom(8)),
            radius: SCRYFrom(5)
        )

        resultCardView.backgroundColor = .white
        resultCardView.layer.cornerRadius = SCRYFrom(24)
        resultCardView.layer.masksToBounds = true
        addSubview(resultCardView)
        resultCardView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.equalTo(SCRXFrom(343)).priority(.high)
            make.height.greaterThanOrEqualTo(SCRYFrom(296))
            make.left.greaterThanOrEqualTo(safeAreaLayoutGuide.snp.left).offset(SCRXFrom(8))
            make.right.lessThanOrEqualTo(safeAreaLayoutGuide.snp.right).offset(SCRXFrom(-8))
            make.top.greaterThanOrEqualTo(safeAreaLayoutGuide.snp.top).offset(SCRYFrom(8))
            make.bottom.lessThanOrEqualTo(safeAreaLayoutGuide.snp.bottom).offset(SCRYFrom(-8))
        }
        for shadowView in [resultLargeShadowView, resultSmallShadowView] {
            shadowView.snp.makeConstraints { make in
                make.edges.equalTo(resultCardView)
            }
        }

        titleLabel.text = "site_entry_sync_status_title".localizedString
        titleLabel.font = scaledFont(size: 16)
        titleLabel.textColor = RGB(30, 35, 41)
        titleLabel.textAlignment = .center
        titleLabel.adjustsFontForContentSizeCategory = true
        resultCardView.addSubview(titleLabel)
        resultCardView.addSubview(siteRow)
        resultCardView.addSubview(gatewayRow)

        titleLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(SCRYFrom(24))
            make.left.right.equalToSuperview().inset(SCRXFrom(24))
        }
        siteRow.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(16))
            make.left.right.equalToSuperview().inset(SCRXFrom(15))
            make.height.greaterThanOrEqualTo(SCRYFrom(64))
        }
        gatewayRow.snp.makeConstraints { make in
            make.top.equalTo(siteRow.snp.bottom).offset(SCRYFrom(8))
            make.left.right.equalTo(siteRow)
            make.height.greaterThanOrEqualTo(SCRYFrom(64))
        }

        configureFooter()
    }

    private func configureShadow(
        _ shadowView: UIView,
        offset: CGSize,
        radius: CGFloat
    ) {
        shadowView.layer.shadowColor = UIColor.black.cgColor
        shadowView.layer.shadowOpacity = 0.1
        shadowView.layer.shadowOffset = offset
        shadowView.layer.shadowRadius = radius
        addSubview(shadowView)
    }

    private func configureFooter() {
        configureButton(gotItButton, key: "site_entry_sync_got_it")
        configureButton(laterButton, key: "site_entry_sync_later")
        configureButton(reviewSyncButton, key: "site_entry_sync_review_sync")
        gotItButton.setTitleColor(RGB(102, 103, 171), for: .normal)
        laterButton.setTitleColor(RGB(64, 79, 102), for: .normal)
        reviewSyncButton.setTitleColor(RGB(102, 103, 171), for: .normal)
        gotItButton.addTarget(self, action: #selector(gotItDidTap), for: .touchUpInside)
        laterButton.addTarget(self, action: #selector(laterDidTap), for: .touchUpInside)
        reviewSyncButton.addTarget(self, action: #selector(reviewSyncDidTap), for: .touchUpInside)

        [gotItButton, laterButton, reviewSyncButton, footerDividerView,
         footerVerticalDividerView].forEach(resultCardView.addSubview)
        gotItButton.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.top.equalTo(gatewayRow.snp.bottom).offset(SCRYFrom(12))
            make.height.greaterThanOrEqualTo(SCRYFrom(60))
        }
        laterButton.snp.makeConstraints { make in
            make.left.bottom.equalToSuperview()
            make.top.equalTo(gotItButton)
            make.width.equalToSuperview().multipliedBy(0.5)
        }
        reviewSyncButton.snp.makeConstraints { make in
            make.right.bottom.equalToSuperview()
            make.top.equalTo(gotItButton)
            make.width.equalToSuperview().multipliedBy(0.5)
        }
        footerDividerView.backgroundColor = UIColor.black.withAlphaComponent(0.03)
        footerDividerView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(gotItButton)
            make.height.equalTo(SCRYFrom(1))
        }
        footerVerticalDividerView.backgroundColor = UIColor.black.withAlphaComponent(0.03)
        footerVerticalDividerView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.bottom.equalTo(laterButton)
            make.width.equalTo(SCRXFrom(1))
        }
    }

    private func configureButton(_ button: UIButton, key: String) {
        button.setTitle(key.localizedString, for: .normal)
        button.titleLabel?.font = scaledFont(size: 15)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.titleLabel?.numberOfLines = 0
        button.titleLabel?.textAlignment = .center
    }

    private func update(state: State) {
        self.state = state
        let isChecking = state == .checking
        checkingCardView.isHidden = !isChecking
        resultLargeShadowView.isHidden = isChecking
        resultSmallShadowView.isHidden = isChecking
        resultCardView.isHidden = isChecking

        guard !isChecking else {
            loadingImageView.layer.addRotationAnimation(
                duration: 1.2,
                repeatCount: .max,
                animationKey: "siteEntrySyncLoading"
            )
            return
        }
        loadingImageView.layer.removeAnimation(forKey: "siteEntrySyncLoading")

        let result: SiteEntryTimeZoneResult
        let needsSync: Bool
        switch state {
        case .checking:
            return
        case .gatewaysNeedSync(let value):
            result = value
            needsSync = true
        case .result(let value):
            result = value
            needsSync = false
        }
        gotItButton.isHidden = needsSync
        laterButton.isHidden = !needsSync
        reviewSyncButton.isHidden = !needsSync
        footerVerticalDividerView.isHidden = !needsSync

        siteRow.update(
            title: "\("site_entry_sync_site_time_zone".localizedString) · \(result.timezone.displayOffset)",
            message: siteMessage(result.site),
            style: result.site == .failedToUpdateServer ? .failure : .success
        )
        let gatewayMessage: String
        switch result.gateway {
        case .noGateways, .inSync:
            gatewayMessage = "site_entry_sync_no_gateways".localizedString
        case .pending(let count):
            gatewayMessage = String(
                format: "site_entry_sync_gateways_need_sync".localizedString,
                count
            )
        }
        gatewayRow.update(
            title: "site_entry_sync_gateway_time_zone".localizedString,
            message: gatewayMessage,
            style: needsSync ? .warning : .success
        )
    }

    private func siteMessage(_ result: SiteEntryTimeZoneSiteResult) -> String {
        switch result {
        case .alreadyInSync:
            return "site_entry_sync_already_in_sync_with_server".localizedString
        case .updatedFromServer:
            return "site_entry_sync_updated_from_server".localizedString
        case .updatedToServer:
            return "site_entry_sync_updated_to_server".localizedString
        case .failedToUpdateServer:
            return "site_entry_sync_failed_to_update_server".localizedString
        }
    }

    private func makeLabel(
        text: String,
        size: CGFloat,
        color: UIColor,
        alignment: NSTextAlignment
    ) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = scaledFont(size: size)
        label.textColor = color
        label.textAlignment = alignment
        label.numberOfLines = 0
        label.adjustsFontForContentSizeCategory = true
        return label
    }

    private func scaledFont(size: CGFloat) -> UIFont {
        UIFontMetrics.default.scaledFont(
            for: UIFont.systemFont(ofSize: SCRYFrom(size), weight: .light)
        )
    }

    @objc private func gotItDidTap() {
        guard case .result = state else { return }
        onGotIt?()
    }

    @objc private func laterDidTap() {
        guard case .gatewaysNeedSync = state else { return }
        onLater?()
    }

    @objc private func reviewSyncDidTap() {
        guard case .gatewaysNeedSync = state else { return }
        onReviewSync?()
    }
}

private final class StatusRowView: UIView {
    enum Style {
        case success
        case warning
        case failure
    }

    private let iconBackgroundView = UIView()
    private let iconImageView = UIImageView()
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = RGB(246, 248, 255)
        layer.cornerRadius = SCRYFrom(16)

        iconBackgroundView.layer.cornerRadius = SCRYFrom(16)
        addSubview(iconBackgroundView)
        iconBackgroundView.addSubview(iconImageView)
        iconImageView.contentMode = .scaleAspectFit
        iconBackgroundView.snp.makeConstraints { make in
            make.left.equalToSuperview().offset(SCRXFrom(16))
            make.centerY.equalToSuperview()
            make.size.equalTo(SCRYFrom(32))
        }
        iconImageView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.size.equalTo(SCRYFrom(16))
        }

        titleLabel.font = scaledFont(size: 14)
        titleLabel.textColor = RGB(30, 35, 41)
        messageLabel.font = scaledFont(size: 12)
        for label in [titleLabel, messageLabel] {
            label.numberOfLines = 1
            label.adjustsFontForContentSizeCategory = true
        }
        let stack = UIStackView(arrangedSubviews: [titleLabel, messageLabel])
        stack.axis = .vertical
        stack.spacing = 0
        addSubview(stack)
        stack.snp.makeConstraints { make in
            make.left.equalTo(iconBackgroundView.snp.right).offset(SCRXFrom(12))
            make.right.equalToSuperview().offset(SCRXFrom(-16))
            make.top.greaterThanOrEqualToSuperview().offset(SCRYFrom(8))
            make.bottom.lessThanOrEqualToSuperview().offset(SCRYFrom(-8))
            make.centerY.equalToSuperview()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(title: String, message: String, style: Style) {
        titleLabel.text = title
        messageLabel.text = message
        switch style {
        case .success:
            iconImageView.image = UIImage(named: "site_entry_sync_success")
            iconImageView.tintColor = nil
            iconBackgroundView.backgroundColor = RGB(0, 209, 124).withAlphaComponent(0.1)
            messageLabel.textColor = RGB(0, 122, 85)
        case .warning:
            iconImageView.image = UIImage(named: "site_entry_sync_warning")
            iconImageView.tintColor = nil
            iconBackgroundView.backgroundColor = RGB(225, 113, 0).withAlphaComponent(0.1)
            messageLabel.textColor = RGB(225, 113, 0)
        case .failure:
            iconImageView.image = UIImage(systemName: "exclamationmark.circle")
            iconImageView.tintColor = RGB(255, 72, 49)
            iconBackgroundView.backgroundColor = RGB(255, 72, 49).withAlphaComponent(0.1)
            messageLabel.textColor = RGB(255, 72, 49)
        }
        accessibilityLabel = "\(title). \(message)"
    }

    private func scaledFont(size: CGFloat) -> UIFont {
        UIFontMetrics.default.scaledFont(
            for: UIFont.systemFont(ofSize: SCRYFrom(size), weight: .light)
        )
    }
}
