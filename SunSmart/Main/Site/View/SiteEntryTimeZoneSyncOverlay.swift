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
        case result(
            site: SiteEntryTimeZoneResult,
            gateways: SiteGatewayCloudTimeZoneBatchState
        )
    }

    var onDone: (() -> Void)?

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
    private let gatewayStatusView = SiteEntryGatewayTimeZoneStatusView()
    private let footerContainerView = UIView()
    private let footerDividerView = UIView()
    private let doneButton = UIButton(type: .system)

    private var resultCardHeightConstraint: Constraint!
    private var gatewayStatusHeightConstraint: Constraint!
    private var footerHeightConstraint: Constraint!
    private var isResultCardHeightConstraintActive = false

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

        if case let .result(_, gateways) = state {
            updateResultSheetLayout(for: gateways)
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

    func showResult(
        _ site: SiteEntryTimeZoneResult,
        gateways: SiteGatewayCloudTimeZoneBatchState
    ) {
        update(state: .result(site: site, gateways: gateways))
    }

    private func setupUI() {
        backgroundColor = UIColor.black.withAlphaComponent(0.4)
        accessibilityViewIsModal = true

        setupCheckingCard()
        setupResultSheet()
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

    private func setupResultSheet() {
        resultCardView.backgroundColor = .white
        resultCardView.layer.cornerRadius = SCRYFrom(24)
        resultCardView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        resultCardView.layer.masksToBounds = true
        addSubview(resultCardView)
        resultCardView.snp.makeConstraints { make in
            make.width.equalTo(SCRXFrom(343)).priority(.high)
            make.left.greaterThanOrEqualTo(safeAreaLayoutGuide.snp.left).offset(SCRXFrom(8))
            make.right.lessThanOrEqualTo(safeAreaLayoutGuide.snp.right).offset(SCRXFrom(-8))
            make.centerX.equalToSuperview()
            make.bottom.equalTo(safeAreaLayoutGuide.snp.bottom)
            make.top.greaterThanOrEqualTo(safeAreaLayoutGuide.snp.top).offset(SCRYFrom(16))
            make.height.lessThanOrEqualTo(safeAreaLayoutGuide.snp.height).offset(-SCRYFrom(16))
        }
        resultCardHeightConstraint = resultCardView.snp.prepareConstraints { make in
            make.height.equalTo(0).priority(.high)
        }.first
        configureResultShadows()
        bringSubviewToFront(resultCardView)

        configureResultTitle()
        configureSiteStatusCard()
        configureGatewayStatusView()
        configureDoneFooter()
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
                make.edges.equalTo(resultCardView)
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
            make.left.right.equalToSuperview().inset(SCRXFrom(24))
            make.height.equalTo(SCRYFrom(25))
        }
    }

    private func configureSiteStatusCard() {
        siteStatusCardView.backgroundColor = RGB(246, 248, 255)
        siteStatusCardView.layer.cornerRadius = SCRYFrom(16)
        resultCardView.addSubview(siteStatusCardView)
        siteStatusCardView.snp.makeConstraints { make in
            make.top.equalTo(resultTitleLabel.snp.bottom).offset(SCRYFrom(16))
            make.left.right.equalToSuperview().inset(SCRXFrom(15))
            make.height.equalTo(SCRYFrom(64))
        }

        siteIconBackgroundView.backgroundColor = RGB(0, 209, 124).withAlphaComponent(0.1)
        siteIconBackgroundView.layer.cornerRadius = SCRYFrom(16)
        siteStatusCardView.addSubview(siteIconBackgroundView)
        siteIconBackgroundView.snp.makeConstraints { make in
            make.left.equalToSuperview().offset(SCRXFrom(16))
            make.centerY.equalToSuperview()
            make.size.equalTo(SCRYFrom(32))
        }

        siteIconImageView.contentMode = .scaleAspectFit
        siteIconBackgroundView.addSubview(siteIconImageView)
        siteIconImageView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.size.equalTo(SCRYFrom(16))
        }

        siteValueLabel.font = scaledFont(size: 14, weight: .light)
        siteValueLabel.textColor = RGB(30, 35, 41)
        siteValueLabel.adjustsFontForContentSizeCategory = true
        siteValueLabel.numberOfLines = 1

        siteStatusLabel.font = scaledFont(size: 12, weight: .light)
        siteStatusLabel.adjustsFontForContentSizeCategory = true
        siteStatusLabel.numberOfLines = 1

        let textStack = UIStackView(arrangedSubviews: [siteValueLabel, siteStatusLabel])
        textStack.axis = .vertical
        textStack.alignment = .fill
        textStack.spacing = 0
        siteStatusCardView.addSubview(textStack)
        textStack.snp.makeConstraints { make in
            make.left.equalTo(siteIconBackgroundView.snp.right).offset(SCRXFrom(12))
            make.right.equalToSuperview().offset(SCRXFrom(-16))
            make.centerY.equalToSuperview()
            make.height.equalTo(SCRYFrom(36))
        }
        siteValueLabel.snp.makeConstraints { make in
            make.height.equalTo(SCRYFrom(20))
        }
        siteStatusLabel.snp.makeConstraints { make in
            make.height.equalTo(SCRYFrom(16))
        }
    }

    private func configureGatewayStatusView() {
        resultCardView.addSubview(gatewayStatusView)
        gatewayStatusView.snp.makeConstraints { make in
            make.top.equalTo(siteStatusCardView.snp.bottom).offset(SCRYFrom(12))
            make.left.right.equalTo(siteStatusCardView)
        }
        gatewayStatusHeightConstraint = gatewayStatusView.snp.prepareConstraints { make in
            make.height.equalTo(gatewayStatusView.preferredHeight)
        }.first
        gatewayStatusHeightConstraint.activate()
    }

    private func configureDoneFooter() {
        footerContainerView.clipsToBounds = true
        resultCardView.addSubview(footerContainerView)
        footerContainerView.snp.makeConstraints { make in
            make.top.equalTo(gatewayStatusView.snp.bottom).offset(SCRYFrom(16))
            make.left.right.equalToSuperview()
        }
        footerHeightConstraint = footerContainerView.snp.prepareConstraints { make in
            make.height.equalTo(0)
        }.first
        footerHeightConstraint.activate()

        footerDividerView.backgroundColor = UIColor.black.withAlphaComponent(0.03)
        footerContainerView.addSubview(footerDividerView)
        footerDividerView.snp.makeConstraints { make in
            make.top.left.right.equalToSuperview()
            make.height.equalTo(SCRYFrom(1))
        }

        doneButton.setTitle("site_entry_sync_done".localizedString, for: .normal)
        doneButton.setTitleColor(RGB(102, 103, 171), for: .normal)
        doneButton.backgroundColor = .clear
        doneButton.titleLabel?.font = scaledFont(size: 15, weight: .light)
        doneButton.titleLabel?.adjustsFontForContentSizeCategory = true
        doneButton.addTarget(self, action: #selector(doneButtonDidTap), for: .touchUpInside)
        footerContainerView.addSubview(doneButton)
        doneButton.snp.makeConstraints { make in
            make.top.equalTo(footerDividerView.snp.bottom)
            make.left.right.equalToSuperview()
            make.height.equalTo(SCRYFrom(60))
        }
    }

    private func update(state: State) {
        let wasDismissible: Bool
        if case let .result(_, gateways) = self.state {
            wasDismissible = gateways.canDismiss
        } else {
            wasDismissible = false
        }

        self.state = state
        checkingCardView.isHidden = state != .checking
        resultLargeShadowView.isHidden = state == .checking
        resultSmallShadowView.isHidden = state == .checking
        resultCardView.isHidden = state == .checking

        switch state {
        case .checking:
            if isResultCardHeightConstraintActive {
                resultCardHeightConstraint.deactivate()
                isResultCardHeightConstraintActive = false
            }
            doneButton.isHidden = true
            footerDividerView.isHidden = true
            footerContainerView.isHidden = true
            footerHeightConstraint.update(offset: 0)
            loadingImageView.layer.addRotationAnimation(
                duration: 1.2,
                repeatCount: .max,
                animationKey: "siteEntrySyncLoading"
            )
            accessibilityLabel = "site_entry_sync_checking_title".localizedString

        case let .result(site, gateways):
            loadingImageView.layer.removeAnimation(forKey: "siteEntrySyncLoading")
            updateSiteStatus(site)
            gatewayStatusView.update(gateways)
            if !isResultCardHeightConstraintActive {
                resultCardHeightConstraint.activate()
                isResultCardHeightConstraintActive = true
            }
            doneButton.isHidden = !gateways.canDismiss
            footerDividerView.isHidden = !gateways.canDismiss
            footerContainerView.isHidden = !gateways.canDismiss
            footerHeightConstraint.update(offset: gateways.canDismiss ? SCRYFrom(61) : 0)
            updateResultSheetLayout(for: gateways)
            accessibilityLabel = "site_entry_sync_status_title".localizedString

            if !wasDismissible && gateways.canDismiss, superview != nil {
                UIView.animate(withDuration: 0.25) {
                    self.layoutIfNeeded()
                }
            }
        }
    }

    private func updateResultSheetLayout(for gateways: SiteGatewayCloudTimeZoneBatchState) {
        let gatewayHeight = availableGatewayViewportHeight(for: gateways)
        gatewayStatusHeightConstraint.update(offset: gatewayHeight)
        resultCardHeightConstraint.update(offset: resultCardHeight(
            gatewayHeight: gatewayHeight,
            showsFooter: gateways.canDismiss
        ))
    }

    private func availableGatewayViewportHeight(
        for gateways: SiteGatewayCloudTimeZoneBatchState
    ) -> CGFloat {
        let preferredHeight = gatewayStatusView.preferredHeight
        let availableResultHeight = safeAreaLayoutGuide.layoutFrame.height - SCRYFrom(16)
        guard availableResultHeight > 0 else { return preferredHeight }

        let availableGatewayHeight = availableResultHeight - fixedResultContentHeight(
            showsFooter: gateways.canDismiss
        )
        return min(
            preferredHeight,
            max(gatewayStatusView.minimumViewportHeight, availableGatewayHeight)
        )
    }

    private func resultCardHeight(gatewayHeight: CGFloat, showsFooter: Bool) -> CGFloat {
        fixedResultContentHeight(showsFooter: showsFooter) + gatewayHeight
    }

    private func fixedResultContentHeight(showsFooter: Bool) -> CGFloat {
        let footerHeight = showsFooter ? SCRYFrom(61) : 0
        return SCRYFrom(24 + 25 + 16 + 64 + 12 + 16) + footerHeight
    }

    private func updateSiteStatus(_ result: SiteEntryTimeZoneResult) {
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
        updateStatusIndicator(failed: siteUpdateFailed)
        siteStatusLabel.textColor = siteUpdateFailed ? RGB(255, 72, 49) : RGB(0, 122, 85)
    }

    private func updateStatusIndicator(failed: Bool) {
        if failed {
            siteIconImageView.image = UIImage(systemName: "exclamationmark.circle")
            siteIconImageView.tintColor = RGB(255, 72, 49)
            siteIconBackgroundView.backgroundColor = RGB(255, 72, 49).withAlphaComponent(0.1)
        } else {
            siteIconImageView.image = UIImage(named: "site_entry_sync_success")
            siteIconImageView.tintColor = nil
            siteIconBackgroundView.backgroundColor = RGB(0, 209, 124).withAlphaComponent(0.1)
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

    @objc private func doneButtonDidTap() {
        guard case let .result(_, gateways) = state, gateways.canDismiss else { return }
        onDone?()
    }
}
