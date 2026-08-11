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
    private let resultLargeShadowView = UIView()
    private let resultSmallShadowView = UIView()
    private let resultCardView = UIView()
    private let loadingContainerView = UIView()
    private let loadingImageView = UIImageView(image: UIImage(named: "site_entry_sync_loading"))

    private let resultTitleLabel = UILabel()
    private let siteStatusCardView = UIView()
    private let siteIconBackgroundView = UIView()
    private let siteIconImageView = UIImageView()
    private let siteValueLabel = UILabel()
    private let siteStatusLabel = UILabel()
    private let gatewayStatusCardView = UIView()
    private let gatewayIconBackgroundView = UIView()
    private let gatewayIconImageView = UIImageView()
    private let gatewayTitleLabel = UILabel()
    private let gatewayStatusLabel = UILabel()
    private let gotItButton = UIButton(type: .system)
    private let laterButton = UIButton(type: .system)
    private let reviewSyncButton = UIButton(type: .system)
    private let footerDividerView = UIView()
    private let footerVerticalDividerView = UIView()

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

        checkingCardView.layer.shadowPath = UIBezierPath(
            roundedRect: checkingCardView.bounds,
            cornerRadius: SCRYFrom(20)
        ).cgPath

        let resultBounds = resultCardView.bounds
        resultLargeShadowView.layer.shadowPath = UIBezierPath(
            roundedRect: resultBounds.insetBy(dx: SCRXFrom(5), dy: SCRYFrom(5)),
            cornerRadius: SCRYFrom(19)
        ).cgPath
        resultSmallShadowView.layer.shadowPath = UIBezierPath(
            roundedRect: resultBounds.insetBy(dx: SCRXFrom(6), dy: SCRYFrom(6)),
            cornerRadius: SCRYFrom(18)
        ).cgPath
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
            make.width.equalTo(SCRXFrom(302))
            make.height.equalTo(SCRYFrom(188))
            make.left.greaterThanOrEqualTo(safeAreaLayoutGuide.snp.left).offset(SCRXFrom(8))
            make.right.lessThanOrEqualTo(safeAreaLayoutGuide.snp.right).offset(SCRXFrom(-8))
        }

        loadingContainerView.addSubview(loadingImageView)
        checkingCardView.addSubview(loadingContainerView)
        loadingContainerView.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(SCRYFrom(18))
            make.centerX.equalToSuperview()
            make.size.equalTo(SCRYFrom(56))
        }
        loadingImageView.contentMode = .scaleAspectFit
        loadingImageView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.size.equalTo(SCRYFrom(39))
        }

        let titleLabel = makeLabel(
            text: "site_entry_sync_checking_title".localizedString,
            size: 18,
            weight: .regular,
            color: RGB(30, 35, 41),
            alignment: .center
        )
        checkingCardView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.top.equalTo(loadingContainerView.snp.bottom).offset(SCRYFrom(10))
            make.left.right.equalToSuperview().inset(SCRXFrom(26))
            make.height.equalTo(SCRYFrom(26))
        }

        let messageLabel = makeLabel(
            text: "site_entry_sync_checking_message".localizedString,
            size: 15,
            weight: .light,
            color: RGB(100, 116, 139),
            alignment: .center
        )
        checkingCardView.addSubview(messageLabel)
        messageLabel.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(10))
            make.left.right.equalToSuperview().inset(SCRXFrom(26))
            make.height.equalTo(SCRYFrom(44))
        }
    }

    private func setupResultCard() {
        configureResultShadows()

        resultCardView.backgroundColor = .white
        resultCardView.layer.cornerRadius = SCRYFrom(24)
        resultCardView.layer.masksToBounds = true
        addSubview(resultCardView)
        resultCardView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.equalTo(SCRXFrom(343)).priority(.high)
            make.height.equalTo(SCRYFrom(296))
            make.left.greaterThanOrEqualTo(safeAreaLayoutGuide.snp.left).offset(SCRXFrom(8))
            make.right.lessThanOrEqualTo(safeAreaLayoutGuide.snp.right).offset(SCRXFrom(-8))
        }

        configureResultTitle()
        configureStatusCard(
            siteStatusCardView,
            iconBackgroundView: siteIconBackgroundView,
            iconImageView: siteIconImageView,
            primaryLabel: siteValueLabel,
            secondaryLabel: siteStatusLabel
        )
        configureStatusCard(
            gatewayStatusCardView,
            iconBackgroundView: gatewayIconBackgroundView,
            iconImageView: gatewayIconImageView,
            primaryLabel: gatewayTitleLabel,
            secondaryLabel: gatewayStatusLabel
        )

        resultCardView.addSubview(siteStatusCardView)
        resultCardView.addSubview(gatewayStatusCardView)
        siteStatusCardView.snp.makeConstraints { make in
            make.top.equalTo(resultTitleLabel.snp.bottom).offset(SCRYFrom(16))
            make.left.equalToSuperview().offset(SCRXFrom(15))
            make.width.equalTo(SCRXFrom(313)).priority(.high)
            make.right.lessThanOrEqualToSuperview().offset(SCRXFrom(-15))
            make.height.equalTo(SCRYFrom(64))
        }
        gatewayStatusCardView.snp.makeConstraints { make in
            make.top.equalTo(siteStatusCardView.snp.bottom).offset(SCRYFrom(8))
            make.left.equalToSuperview().offset(SCRXFrom(15))
            make.width.equalTo(SCRXFrom(313)).priority(.high)
            make.right.lessThanOrEqualToSuperview().offset(SCRXFrom(-15))
            make.height.equalTo(SCRYFrom(64))
        }

        configureFooterButtons()
    }

    private func configureResultShadows() {
        resultLargeShadowView.layer.shadowColor = UIColor.black.cgColor
        resultLargeShadowView.layer.shadowOpacity = 0.1
        resultLargeShadowView.layer.shadowOffset = CGSize(width: 0, height: SCRYFrom(20))
        resultLargeShadowView.layer.shadowRadius = SCRYFrom(12.5)

        resultSmallShadowView.layer.shadowColor = UIColor.black.cgColor
        resultSmallShadowView.layer.shadowOpacity = 0.1
        resultSmallShadowView.layer.shadowOffset = CGSize(width: 0, height: SCRYFrom(8))
        resultSmallShadowView.layer.shadowRadius = SCRYFrom(5)

        for shadowView in [resultLargeShadowView, resultSmallShadowView] {
            addSubview(shadowView)
            shadowView.snp.makeConstraints { make in
                make.center.equalToSuperview()
                make.width.equalTo(SCRXFrom(343))
                make.height.equalTo(SCRYFrom(296))
            }
        }
    }

    private func configureResultTitle() {
        resultTitleLabel.text = "site_entry_sync_status_title".localizedString
        resultTitleLabel.font = scaledFont(size: 16, weight: .regular)
        resultTitleLabel.textColor = RGB(30, 35, 41)
        resultTitleLabel.textAlignment = .center
        resultTitleLabel.adjustsFontForContentSizeCategory = true
        resultCardView.addSubview(resultTitleLabel)
        resultTitleLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(SCRYFrom(24))
            make.left.equalToSuperview().offset(SCRXFrom(24))
            make.width.equalTo(SCRXFrom(313)).priority(.high)
            make.right.lessThanOrEqualToSuperview().offset(SCRXFrom(-6))
            make.height.equalTo(SCRYFrom(25))
        }
    }

    private func configureStatusCard(
        _ card: UIView,
        iconBackgroundView: UIView,
        iconImageView: UIImageView,
        primaryLabel: UILabel,
        secondaryLabel: UILabel
    ) {
        card.backgroundColor = RGB(246, 248, 255)
        card.layer.cornerRadius = SCRYFrom(16)

        iconBackgroundView.backgroundColor = RGB(0, 209, 124).withAlphaComponent(0.1)
        iconBackgroundView.layer.cornerRadius = SCRYFrom(16)
        card.addSubview(iconBackgroundView)
        iconBackgroundView.snp.makeConstraints { make in
            make.left.equalToSuperview().offset(SCRXFrom(16))
            make.centerY.equalToSuperview()
            make.size.equalTo(SCRYFrom(32))
        }

        iconImageView.image = UIImage(named: "site_entry_sync_success")
        iconImageView.contentMode = .scaleAspectFit
        iconBackgroundView.addSubview(iconImageView)
        iconImageView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.size.equalTo(SCRYFrom(16))
        }

        primaryLabel.font = scaledFont(size: 14, weight: .light)
        primaryLabel.textColor = RGB(30, 35, 41)
        primaryLabel.adjustsFontForContentSizeCategory = true
        primaryLabel.numberOfLines = 1

        secondaryLabel.font = scaledFont(size: 12, weight: .light)
        secondaryLabel.textColor = RGB(0, 122, 85)
        secondaryLabel.adjustsFontForContentSizeCategory = true
        secondaryLabel.numberOfLines = 1

        let textStack = UIStackView(arrangedSubviews: [primaryLabel, secondaryLabel])
        textStack.axis = .vertical
        textStack.alignment = .fill
        textStack.spacing = 0
        card.addSubview(textStack)
        textStack.snp.makeConstraints { make in
            make.left.equalTo(iconBackgroundView.snp.right).offset(SCRXFrom(12))
            make.right.equalToSuperview().offset(SCRXFrom(-16))
            make.centerY.equalToSuperview()
            make.height.equalTo(SCRYFrom(36))
        }
        primaryLabel.snp.makeConstraints { make in
            make.height.equalTo(SCRYFrom(20))
        }
        secondaryLabel.snp.makeConstraints { make in
            make.height.equalTo(SCRYFrom(16))
        }
    }

    private func configureFooterButtons() {
        gotItButton.setTitle("site_entry_sync_got_it".localizedString, for: .normal)
        gotItButton.setTitleColor(RGB(102, 103, 171), for: .normal)
        gotItButton.backgroundColor = .clear
        gotItButton.titleLabel?.font = scaledFont(size: 15, weight: .light)
        gotItButton.titleLabel?.adjustsFontForContentSizeCategory = true
        gotItButton.addTarget(self, action: #selector(gotItButtonDidTap), for: .touchUpInside)
        resultCardView.addSubview(gotItButton)
        gotItButton.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(SCRYFrom(60))
        }

        laterButton.setTitle("site_entry_sync_later".localizedString, for: .normal)
        laterButton.setTitleColor(RGB(64, 79, 102), for: .normal)
        laterButton.backgroundColor = .clear
        laterButton.titleLabel?.font = scaledFont(size: 15, weight: .light)
        laterButton.titleLabel?.adjustsFontForContentSizeCategory = true
        laterButton.addTarget(self, action: #selector(laterButtonDidTap), for: .touchUpInside)
        resultCardView.addSubview(laterButton)
        laterButton.snp.makeConstraints { make in
            make.left.bottom.equalToSuperview()
            make.width.equalToSuperview().multipliedBy(0.5)
            make.height.equalTo(SCRYFrom(60))
        }

        reviewSyncButton.setTitle("site_entry_sync_review_sync".localizedString, for: .normal)
        reviewSyncButton.setTitleColor(RGB(102, 103, 171), for: .normal)
        reviewSyncButton.backgroundColor = .clear
        reviewSyncButton.titleLabel?.font = scaledFont(size: 15, weight: .light)
        reviewSyncButton.titleLabel?.adjustsFontForContentSizeCategory = true
        reviewSyncButton.addTarget(
            self,
            action: #selector(reviewSyncButtonDidTap),
            for: .touchUpInside
        )
        resultCardView.addSubview(reviewSyncButton)
        reviewSyncButton.snp.makeConstraints { make in
            make.right.bottom.equalToSuperview()
            make.width.equalToSuperview().multipliedBy(0.5)
            make.height.equalTo(SCRYFrom(60))
        }

        footerDividerView.backgroundColor = UIColor.black.withAlphaComponent(0.03)
        resultCardView.addSubview(footerDividerView)
        footerDividerView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(gotItButton.snp.top)
            make.height.equalTo(SCRYFrom(1))
        }

        footerVerticalDividerView.backgroundColor = UIColor.black.withAlphaComponent(0.03)
        resultCardView.addSubview(footerVerticalDividerView)
        footerVerticalDividerView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.bottom.equalTo(laterButton)
            make.width.equalTo(SCRXFrom(1))
        }
    }

    private func update(state: State) {
        self.state = state
        checkingCardView.isHidden = state != .checking
        resultLargeShadowView.isHidden = state == .checking
        resultSmallShadowView.isHidden = state == .checking
        resultCardView.isHidden = state == .checking

        let gatewaysNeedSync: Bool
        switch state {
        case .gatewaysNeedSync:
            gatewaysNeedSync = true
        case .checking, .result:
            gatewaysNeedSync = false
        }
        gotItButton.isHidden = state == .checking || gatewaysNeedSync
        laterButton.isHidden = !gatewaysNeedSync
        reviewSyncButton.isHidden = !gatewaysNeedSync
        footerVerticalDividerView.isHidden = !gatewaysNeedSync

        switch state {
        case .checking:
            loadingImageView.layer.addRotationAnimation(
                duration: 1.2,
                repeatCount: .max,
                animationKey: "siteEntrySyncLoading"
            )
            accessibilityLabel = "site_entry_sync_checking_title".localizedString

        case .gatewaysNeedSync(let result), .result(let result):
            loadingImageView.layer.removeAnimation(forKey: "siteEntrySyncLoading")
            siteValueLabel.text = "\("site_entry_sync_site_time_zone".localizedString) · \(result.timezone.displayOffset)"

            let siteUpdateFailed: Bool
            switch result.site {
            case .alreadyInSync:
                siteUpdateFailed = false
                siteStatusLabel.text = "site_entry_sync_already_in_sync_with_server".localizedString
            case .updatedFromServer:
                siteUpdateFailed = false
                siteStatusLabel.text = "site_entry_sync_updated_from_server".localizedString
            case .updatedToServer:
                siteUpdateFailed = false
                siteStatusLabel.text = "site_entry_sync_updated_to_server".localizedString
            case .failedToUpdateServer:
                siteUpdateFailed = true
                siteStatusLabel.text = "site_entry_sync_failed_to_update_server".localizedString
            }
            updateStatusIndicator(
                iconImageView: siteIconImageView,
                backgroundView: siteIconBackgroundView,
                failed: siteUpdateFailed
            )
            siteStatusLabel.textColor = siteUpdateFailed ? RGB(255, 72, 49) : RGB(0, 122, 85)

            gatewayTitleLabel.text = "site_entry_sync_gateway_time_zone".localizedString
            switch result.gateway {
            case .noGateways:
                gatewayStatusLabel.text = "site_entry_sync_no_gateways".localizedString
            case .pending(let count):
                gatewayStatusLabel.text = String(
                    format: "site_entry_sync_gateways_need_sync".localizedString,
                    count
                )
            case .inSync:
                gatewayStatusLabel.text = "site_entry_sync_gateways_in_sync".localizedString
            }
            if gatewaysNeedSync {
                gatewayStatusLabel.textColor = RGB(225, 113, 0)
                gatewayIconImageView.image = UIImage(named: "site_entry_sync_warning")
                gatewayIconImageView.tintColor = nil
                gatewayIconBackgroundView.backgroundColor = RGB(225, 113, 0).withAlphaComponent(0.1)
            } else {
                gatewayStatusLabel.textColor = RGB(0, 122, 85)
                updateStatusIndicator(
                    iconImageView: gatewayIconImageView,
                    backgroundView: gatewayIconBackgroundView,
                    failed: false
                )
            }
            accessibilityLabel = "site_entry_sync_status_title".localizedString
        }
    }

    private func updateStatusIndicator(
        iconImageView: UIImageView,
        backgroundView: UIView,
        failed: Bool
    ) {
        if failed {
            iconImageView.image = UIImage(systemName: "exclamationmark.circle")
            iconImageView.tintColor = RGB(255, 72, 49)
            backgroundView.backgroundColor = RGB(255, 72, 49).withAlphaComponent(0.1)
        } else {
            iconImageView.image = UIImage(named: "site_entry_sync_success")
            iconImageView.tintColor = nil
            backgroundView.backgroundColor = RGB(0, 209, 124).withAlphaComponent(0.1)
        }
    }

    private func makeLabel(
        text: String,
        size: CGFloat,
        weight: UIFont.Weight,
        color: UIColor,
        alignment: NSTextAlignment
    ) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = scaledFont(size: size, weight: weight)
        label.textColor = color
        label.textAlignment = alignment
        label.numberOfLines = 0
        label.adjustsFontForContentSizeCategory = true
        return label
    }

    private func scaledFont(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        UIFontMetrics.default.scaledFont(
            for: UIFont.systemFont(ofSize: SCRYFrom(size), weight: weight)
        )
    }

    @objc private func gotItButtonDidTap() {
        guard case .result = state else { return }
        onGotIt?()
    }

    @objc private func laterButtonDidTap() {
        guard case .gatewaysNeedSync = state else { return }
        onLater?()
    }

    @objc private func reviewSyncButtonDidTap() {
        guard case .gatewaysNeedSync = state else { return }
        onReviewSync?()
    }
}
