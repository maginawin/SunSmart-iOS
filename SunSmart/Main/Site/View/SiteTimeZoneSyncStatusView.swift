//
//  SiteTimeZoneSyncStatusView.swift
//  SunSmart
//
//  Created by One on 2026/8/11.
//

import UIKit
import SnapKit

final class SiteTimeZoneSyncStatusView: UIView {

    var onDone: (() -> Void)?

    private let checkingCardView = UIView()
    private let resultLargeShadowView = UIView()
    private let resultSmallShadowView = UIView()
    private let resultCardView = UIView()
    private let bottomSafeAreaBackgroundView = UIView()
    private let resultContentScrollView = UIScrollView()
    private let resultContentView = UIView()
    private let loadingContainerView = UIView()
    private let loadingImageView = UIImageView(image: UIImage(named: "site_entry_sync_loading"))
    private let workingTitleLabel = UILabel()
    private let workingMessageLabel = UILabel()

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
    private var gatewayStatusTopConstraint: Constraint!
    private var gatewayStatusHeightConstraint: Constraint!
    private var footerHeightConstraint: Constraint!
    private var isResultCardHeightConstraintActive = false

    private(set) var state: SiteTimeZoneSyncPresentationState = .working(.savingSite)

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
        update(state: state)
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

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard previousTraitCollection?.preferredContentSizeCategory !=
                traitCollection.preferredContentSizeCategory else {
            return
        }

        [
            workingTitleLabel,
            workingMessageLabel,
            resultTitleLabel,
            siteValueLabel,
            siteStatusLabel
        ].forEach { $0.invalidateIntrinsicContentSize() }
        checkingCardView.invalidateIntrinsicContentSize()
        siteStatusCardView.invalidateIntrinsicContentSize()
        gatewayStatusView.invalidateIntrinsicContentSize()
        setNeedsLayout()

        if case let .result(_, gateways) = state {
            updateResultSheetLayout(for: gateways)
        }
    }

    func show(in parentView: UIView? = nil) {
        let targetView = parentView ?? Self.activeWindow
        guard let targetView else { return }
        targetView.addSubview(self)
        snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }

    func update(state: SiteTimeZoneSyncPresentationState) {
        let wasDismissible = self.state.canDismiss
        let wasWorking = self.state.isWorking
        self.state = state

        checkingCardView.isHidden = !state.isWorking
        resultLargeShadowView.isHidden = state.isWorking
        resultSmallShadowView.isHidden = state.isWorking
        resultCardView.isHidden = state.isWorking
        bottomSafeAreaBackgroundView.isHidden = state.isWorking

        switch state {
        case .working(let stage):
            if !wasWorking {
                resultContentScrollView.setContentOffset(.zero, animated: false)
            }
            if isResultCardHeightConstraintActive {
                resultCardHeightConstraint.deactivate()
                isResultCardHeightConstraintActive = false
            }
            updateWorkingCopy(stage)
            doneButton.isHidden = true
            footerDividerView.isHidden = true
            footerContainerView.isHidden = true
            footerHeightConstraint.update(offset: 0)
            loadingImageView.layer.addRotationAnimation(
                duration: 1.2,
                repeatCount: .max,
                animationKey: "siteEntrySyncLoading"
            )
            accessibilityLabel = workingTitleLabel.text

        case let .result(site, gateways):
            loadingImageView.layer.removeAnimation(forKey: "siteEntrySyncLoading")
            updateSiteStatus(site)
            gatewayStatusView.update(gateways)
            switch gateways {
            case .notStarted:
                gatewayStatusView.isHidden = true
            case .unavailable, .batch:
                gatewayStatusView.isHidden = false
            }
            if !isResultCardHeightConstraintActive {
                resultCardHeightConstraint.activate()
                isResultCardHeightConstraintActive = true
            }
            doneButton.isHidden = !state.canDismiss
            footerDividerView.isHidden = !state.canDismiss
            footerContainerView.isHidden = !state.canDismiss
            footerHeightConstraint.update(offset: state.canDismiss ? SCRYFrom(61) : 0)
            updateResultSheetLayout(for: gateways)
            accessibilityLabel = "site_time_zone_sync_status".localizedString

            if !wasDismissible && state.canDismiss, superview != nil {
                UIView.animate(withDuration: 0.25) {
                    self.layoutIfNeeded()
                }
            }
        }
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
            make.center.equalTo(safeAreaLayoutGuide)
            make.width.equalTo(SCRXFrom(302)).priority(.high)
            make.height.greaterThanOrEqualTo(SCRYFrom(188))
            make.left.greaterThanOrEqualTo(safeAreaLayoutGuide.snp.left).offset(SCRXFrom(8))
            make.right.lessThanOrEqualTo(safeAreaLayoutGuide.snp.right).offset(SCRXFrom(-8))
            make.top.greaterThanOrEqualTo(safeAreaLayoutGuide.snp.top).offset(SCRYFrom(8))
            make.bottom.lessThanOrEqualTo(safeAreaLayoutGuide.snp.bottom).offset(SCRYFrom(-8))
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

        configureLabel(
            workingTitleLabel,
            size: 18,
            weight: .regular,
            color: RGB(30, 35, 41),
            alignment: .center
        )
        checkingCardView.addSubview(workingTitleLabel)
        workingTitleLabel.snp.makeConstraints { make in
            make.top.equalTo(loadingContainerView.snp.bottom).offset(SCRYFrom(10))
            make.left.right.equalToSuperview().inset(SCRXFrom(26))
            make.height.greaterThanOrEqualTo(SCRYFrom(26))
        }

        configureLabel(
            workingMessageLabel,
            size: 15,
            weight: .light,
            color: RGB(100, 116, 139),
            alignment: .center
        )
        checkingCardView.addSubview(workingMessageLabel)
        workingMessageLabel.snp.makeConstraints { make in
            make.top.equalTo(workingTitleLabel.snp.bottom).offset(SCRYFrom(10))
            make.left.right.equalToSuperview().inset(SCRXFrom(26))
            make.height.greaterThanOrEqualTo(SCRYFrom(44))
            make.bottom.equalToSuperview().inset(SCRYFrom(24))
        }
    }

    private func setupResultSheet() {
        bottomSafeAreaBackgroundView.backgroundColor = .white
        addSubview(bottomSafeAreaBackgroundView)
        bottomSafeAreaBackgroundView.snp.makeConstraints { make in
            make.top.equalTo(safeAreaLayoutGuide.snp.bottom)
            make.left.right.bottom.equalToSuperview()
        }

        resultCardView.backgroundColor = .white
        resultCardView.layer.cornerRadius = SCRYFrom(24)
        resultCardView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        resultCardView.layer.masksToBounds = true
        addSubview(resultCardView)
        resultCardView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.bottom.equalTo(safeAreaLayoutGuide.snp.bottom)
            make.top.greaterThanOrEqualTo(safeAreaLayoutGuide.snp.top).offset(SCRYFrom(16))
            make.height.lessThanOrEqualTo(safeAreaLayoutGuide.snp.height).offset(-SCRYFrom(16))
        }
        resultCardHeightConstraint = resultCardView.snp.prepareConstraints { make in
            make.height.equalTo(0).priority(.high)
        }.first
        configureResultShadows()
        bringSubviewToFront(resultCardView)

        configureResultContentScrollView()
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
            insertSubview(shadowView, belowSubview: bottomSafeAreaBackgroundView)
            shadowView.snp.makeConstraints { make in
                make.edges.equalTo(resultCardView)
            }
        }
    }

    private func configureResultContentScrollView() {
        resultContentScrollView.alwaysBounceVertical = false
        resultContentScrollView.showsVerticalScrollIndicator = true
        resultContentScrollView.contentInsetAdjustmentBehavior = .never
        resultCardView.addSubview(resultContentScrollView)
        resultContentScrollView.snp.makeConstraints { make in
            make.top.left.right.equalToSuperview()
        }

        resultContentScrollView.addSubview(resultContentView)
        resultContentView.snp.makeConstraints { make in
            make.edges.equalTo(resultContentScrollView.contentLayoutGuide)
            make.width.equalTo(resultContentScrollView.frameLayoutGuide)
        }
    }

    private func configureResultTitle() {
        resultTitleLabel.text = "site_time_zone_sync_status".localizedString
        resultTitleLabel.font = scaledFont(size: 16, weight: .regular)
        resultTitleLabel.textColor = RGB(30, 35, 41)
        resultTitleLabel.textAlignment = .center
        resultTitleLabel.adjustsFontForContentSizeCategory = true
        resultTitleLabel.numberOfLines = 0
        resultContentView.addSubview(resultTitleLabel)
        resultTitleLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(SCRYFrom(24))
            make.left.right.equalToSuperview().inset(SCRXFrom(24))
            make.height.greaterThanOrEqualTo(SCRYFrom(25))
        }
    }

    private func configureSiteStatusCard() {
        siteStatusCardView.backgroundColor = RGB(246, 248, 255)
        siteStatusCardView.layer.cornerRadius = SCRYFrom(16)
        resultContentView.addSubview(siteStatusCardView)
        siteStatusCardView.snp.makeConstraints { make in
            make.top.equalTo(resultTitleLabel.snp.bottom).offset(SCRYFrom(16))
            make.left.right.equalToSuperview().inset(SCRXFrom(15))
            make.height.greaterThanOrEqualTo(SCRYFrom(64))
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
        siteValueLabel.numberOfLines = 0

        siteStatusLabel.font = scaledFont(size: 12, weight: .light)
        siteStatusLabel.adjustsFontForContentSizeCategory = true
        siteStatusLabel.numberOfLines = 0

        let textStack = UIStackView(arrangedSubviews: [siteValueLabel, siteStatusLabel])
        textStack.axis = .vertical
        textStack.alignment = .fill
        textStack.spacing = 0
        siteStatusCardView.addSubview(textStack)
        textStack.snp.makeConstraints { make in
            make.left.equalTo(siteIconBackgroundView.snp.right).offset(SCRXFrom(12))
            make.right.equalToSuperview().offset(SCRXFrom(-16))
            make.top.bottom.equalToSuperview().inset(SCRYFrom(14))
        }
    }

    private func configureGatewayStatusView() {
        gatewayStatusView.onPreferredHeightChanged = { [weak self] in
            guard let self,
                  case let .result(_, gateways) = self.state else {
                return
            }
            self.updateResultSheetLayout(for: gateways)
        }
        resultContentView.addSubview(gatewayStatusView)
        gatewayStatusView.snp.makeConstraints { make in
            make.left.right.equalTo(siteStatusCardView)
            make.bottom.equalToSuperview().inset(SCRYFrom(16))
        }
        gatewayStatusTopConstraint = gatewayStatusView.snp.prepareConstraints { make in
            make.top.equalTo(siteStatusCardView.snp.bottom).offset(SCRYFrom(12))
        }.first
        gatewayStatusTopConstraint.activate()
        gatewayStatusHeightConstraint = gatewayStatusView.snp.prepareConstraints { make in
            make.height.equalTo(gatewayStatusView.preferredHeight)
        }.first
        gatewayStatusHeightConstraint.activate()
    }

    private func configureDoneFooter() {
        footerContainerView.clipsToBounds = true
        resultCardView.addSubview(footerContainerView)
        footerContainerView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
        }
        footerHeightConstraint = footerContainerView.snp.prepareConstraints { make in
            make.height.equalTo(0)
        }.first
        footerHeightConstraint.activate()
        resultContentScrollView.snp.makeConstraints { make in
            make.bottom.equalTo(footerContainerView.snp.top)
        }

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

    private func updateWorkingCopy(_ stage: SiteTimeZoneSyncWorkingStage) {
        switch stage {
        case .checkingSite:
            workingTitleLabel.text = "site_entry_sync_checking_title".localizedString
            workingMessageLabel.text = "site_entry_sync_checking_message".localizedString
        case .savingSite:
            workingTitleLabel.text = "site_time_zone_sync_status".localizedString
            workingMessageLabel.text = "site_time_zone_saving_to_server".localizedString
        }
    }

    private func updateResultSheetLayout(for gateways: SiteTimeZoneGatewayPresentation) {
        let showsGateway = gateways.showsStatus
        gatewayStatusTopConstraint.update(offset: showsGateway ? SCRYFrom(12) : 0)
        let gatewayHeight = showsGateway ? gatewayStatusView.preferredHeight : 0
        gatewayStatusHeightConstraint.update(offset: gatewayHeight)
        let measuredContentHeight = measuredResultContentHeight(showsGateway: showsGateway)
        let availableResultHeight = safeAreaLayoutGuide.layoutFrame.height - SCRYFrom(16)
        let requestedFooterHeight = state.canDismiss ? SCRYFrom(61) : 0
        let layout = SiteTimeZoneSyncResultLayoutPolicy.makeLayout(
            contentHeight: measuredContentHeight,
            availableHeight: availableResultHeight,
            requestedFooterHeight: requestedFooterHeight
        )
        resultContentScrollView.isScrollEnabled = layout.contentScrolls
        resultCardHeightConstraint.update(offset: layout.resultCardHeight)
    }

    private func measuredResultContentHeight(showsGateway: Bool) -> CGFloat {
        let laidOutWidth = resultCardView.bounds.width
        let fallbackWidth = bounds.width > 0 ? bounds.width : UIScreen.main.bounds.width
        let resultWidth = laidOutWidth > 0 ? laidOutWidth : fallbackWidth
        let measuredResultTitleHeight = fittingHeight(
            of: resultTitleLabel,
            width: max(0, resultWidth - SCRXFrom(48))
        )
        let measuredSiteStatusCardHeight = fittingHeight(
            of: siteStatusCardView,
            width: max(0, resultWidth - SCRXFrom(30))
        )
        let gatewaySpacing = showsGateway ? SCRYFrom(12) : 0
        let gatewayHeight = showsGateway ? gatewayStatusView.preferredHeight : 0
        return SCRYFrom(24) +
            measuredResultTitleHeight +
            SCRYFrom(16) +
            measuredSiteStatusCardHeight +
            gatewaySpacing +
            gatewayHeight +
            SCRYFrom(16)
    }

    private func fittingHeight(of view: UIView, width: CGFloat) -> CGFloat {
        ceil(view.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height)
    }

    private func updateSiteStatus(_: SiteTimeZoneSyncSitePresentation) {
        siteValueLabel.text = "site_time_zone_row_title".localizedString
        siteStatusLabel.text = "site_time_zone_saved_successfully".localizedString
        updateStatusIndicator()
        siteStatusLabel.textColor = RGB(0, 122, 85)
    }

    private func updateStatusIndicator() {
        siteIconImageView.image = UIImage(named: "site_entry_sync_success")
        siteIconImageView.tintColor = nil
        siteIconBackgroundView.backgroundColor = RGB(0, 209, 124).withAlphaComponent(0.1)
    }

    private func configureLabel(
        _ label: UILabel,
        size: CGFloat,
        weight: UIFont.Weight,
        color: UIColor,
        alignment: NSTextAlignment
    ) {
        label.font = scaledFont(size: size, weight: weight)
        label.textColor = color
        label.textAlignment = alignment
        label.numberOfLines = 0
        label.adjustsFontForContentSizeCategory = true
    }

    private func scaledFont(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        UIFontMetrics.default.scaledFont(
            for: UIFont.systemFont(ofSize: SCRYFrom(size), weight: weight)
        )
    }

    @objc private func doneButtonDidTap() {
        guard state.canDismiss else { return }
        if let onDone {
            onDone()
        } else {
            removeFromSuperview()
        }
    }

    private static var activeWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
    }
}

private extension SiteTimeZoneSyncPresentationState {

    var isWorking: Bool {
        if case .working = self {
            return true
        }
        return false
    }
}

private extension SiteTimeZoneGatewayPresentation {

    var showsStatus: Bool {
        if case .notStarted = self {
            return false
        }
        return true
    }
}
