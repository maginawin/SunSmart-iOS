//
//  SiteEntryGatewayTimeZoneStatusView.swift
//  SunSmart
//
//  Created by One on 2026/8/15.
//

import UIKit
import SnapKit

final class SiteEntryGatewayTimeZoneStatusView: UIView {

    private let gatewayCardView = UIView()
    private let gatewayHeaderView = UIView()
    private let gatewayHeaderLabel = UILabel()
    private let gatewayCountLabel = UILabel()
    private let headerDividerView = UIView()
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let emptyStateView = UIView()
    private let emptyIconImageView = UIImageView()
    private let emptyTitleLabel = UILabel()
    private let emptyMessageLabel = UILabel()
    private let failureSummaryCardView = UIView()
    private let failureIconBackgroundView = UIView()
    private let failureIconImageView = UIImageView()
    private let failureTitleLabel = UILabel()
    private let failureMessageLabel = UILabel()

    private var items = [SiteGatewayCloudTimeZoneItem]()
    private var gatewayCardTopConstraint: Constraint!
    private var gatewayCardBottomConstraint: Constraint!
    private var emptyStateTopConstraint: Constraint!
    private var emptyStateBottomConstraint: Constraint!
    private var failureSummaryTopConstraint: Constraint!
    private var failureSummaryBottomConstraint: Constraint!

    var preferredHeight: CGFloat {
        if items.isEmpty {
            return SCRYFrom(152)
        }
        return SCRYFrom(failedCount == 0 ? 176 : 284)
    }

    var minimumViewportHeight: CGFloat {
        if items.isEmpty {
            return preferredHeight
        }
        return failedCount == 0 ? SCRYFrom(44) : SCRYFrom(44 + 12 + 96)
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: preferredHeight)
    }

    private var failedCount: Int {
        items.reduce(into: 0) { count, item in
            if item.status == .failed {
                count += 1
            }
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(_ state: SiteGatewayCloudTimeZoneBatchState) {
        items = state.items
        gatewayCountLabel.text = String(state.authorizedCount)
        gatewayHeaderView.accessibilityLabel = "\("site_entry_sync_gateways_header".localizedString), \(state.authorizedCount)"

        if state.failedCount == 1 {
            failureTitleLabel.text = "site_entry_sync_one_gateway_failed".localizedString
        } else {
            failureTitleLabel.text = String(
                format: "site_entry_sync_gateways_failed_format".localizedString,
                state.failedCount
            )
        }
        let failureGuidance = "site_entry_sync_failed_guidance".localizedString
        failureSummaryCardView.accessibilityLabel = "\(failureTitleLabel.text ?? ""). \(failureGuidance)"

        configurePresentation(
            hasGateways: !items.isEmpty,
            hasFailureSummary: state.failedCount > 0
        )
        tableView.reloadData()
        invalidateIntrinsicContentSize()
    }

    private func setupUI() {
        setupGatewayCard()
        setupEmptyState()
        setupFailureSummary()
        configurePresentation(hasGateways: false, hasFailureSummary: false)
    }

    private func setupGatewayCard() {
        gatewayCardView.backgroundColor = RGB(248, 250, 252)
        gatewayCardView.layer.cornerRadius = SCRYFrom(14)
        gatewayCardView.layer.masksToBounds = true
        addSubview(gatewayCardView)
        gatewayCardView.snp.makeConstraints { make in
            make.height.equalTo(SCRYFrom(176)).priority(.high)
            make.left.right.equalToSuperview()
        }
        gatewayCardTopConstraint = gatewayCardView.snp.prepareConstraints { make in
            make.top.equalToSuperview()
        }.first
        gatewayCardBottomConstraint = gatewayCardView.snp.prepareConstraints { make in
            make.bottom.equalToSuperview()
        }.first

        gatewayHeaderLabel.text = "site_entry_sync_gateways_header".localizedString
        configureDynamicFont(
            gatewayHeaderLabel,
            baseSize: 12,
            weight: .semibold,
            textStyle: .caption1
        )
        gatewayHeaderLabel.textColor = RGB(100, 116, 139)
        gatewayHeaderLabel.isAccessibilityElement = false
        gatewayHeaderView.addSubview(gatewayHeaderLabel)
        gatewayHeaderLabel.snp.makeConstraints { make in
            make.left.equalToSuperview().offset(SCRXFrom(16))
            make.centerY.equalToSuperview()
        }

        configureDynamicFont(
            gatewayCountLabel,
            baseSize: 12,
            weight: .regular,
            textStyle: .caption1
        )
        gatewayCountLabel.textColor = AssistText_Color
        gatewayCountLabel.textAlignment = .right
        gatewayCountLabel.isAccessibilityElement = false
        gatewayHeaderView.addSubview(gatewayCountLabel)
        gatewayCountLabel.snp.makeConstraints { make in
            make.right.equalToSuperview().offset(SCRXFrom(-16))
            make.centerY.equalToSuperview()
        }

        headerDividerView.backgroundColor = RGB(229, 232, 240)
        gatewayHeaderView.addSubview(headerDividerView)
        headerDividerView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(0.5)
        }

        gatewayCardView.addSubview(gatewayHeaderView)
        gatewayHeaderView.snp.makeConstraints { make in
            make.top.left.right.equalToSuperview()
            make.height.equalTo(SCRYFrom(44))
        }
        gatewayHeaderView.isAccessibilityElement = true
        gatewayHeaderView.accessibilityTraits = .header

        tableView.backgroundColor = .clear
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(GatewayTimeZoneStatusCell.self, forCellReuseIdentifier: GatewayTimeZoneStatusCell.reuseIdentifier)
        tableView.rowHeight = SCRYFrom(44)
        tableView.separatorStyle = .singleLine
        tableView.separatorColor = RGB(229, 232, 240)
        tableView.separatorInset = UIEdgeInsets(
            top: 0,
            left: SCRXFrom(16),
            bottom: 0,
            right: SCRXFrom(16)
        )
        tableView.isScrollEnabled = true
        tableView.showsVerticalScrollIndicator = true
        gatewayCardView.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.top.equalTo(gatewayHeaderView.snp.bottom)
            make.left.right.bottom.equalToSuperview()
        }
    }

    private func setupEmptyState() {
        emptyStateView.backgroundColor = RGB(248, 250, 252)
        emptyStateView.layer.cornerRadius = SCRYFrom(14)
        addSubview(emptyStateView)
        emptyStateView.snp.makeConstraints { make in
            make.height.equalTo(SCRYFrom(152))
            make.left.right.equalToSuperview()
        }
        emptyStateTopConstraint = emptyStateView.snp.prepareConstraints { make in
            make.top.equalToSuperview()
        }.first
        emptyStateBottomConstraint = emptyStateView.snp.prepareConstraints { make in
            make.bottom.equalToSuperview()
        }.first

        emptyIconImageView.image = UIImage(named: "time-zone-sync-status-gateway")?
            .withTintColor(Yellow_Color, renderingMode: .alwaysOriginal)
        emptyIconImageView.contentMode = .scaleAspectFit
        emptyIconImageView.isAccessibilityElement = false
        emptyStateView.addSubview(emptyIconImageView)
        emptyIconImageView.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(SCRYFrom(20))
            make.centerX.equalToSuperview()
            make.size.equalTo(SCRYFrom(32))
        }

        emptyTitleLabel.text = "site_entry_sync_no_gateways_title".localizedString
        configureDynamicFont(
            emptyTitleLabel,
            baseSize: 14,
            weight: .regular,
            textStyle: .subheadline
        )
        emptyTitleLabel.textColor = TextBlack_Color
        emptyTitleLabel.textAlignment = .center
        emptyTitleLabel.isAccessibilityElement = false
        emptyStateView.addSubview(emptyTitleLabel)
        emptyTitleLabel.snp.makeConstraints { make in
            make.top.equalTo(emptyIconImageView.snp.bottom).offset(SCRYFrom(10))
            make.left.right.equalToSuperview().inset(SCRXFrom(16))
        }

        emptyMessageLabel.text = "site_entry_sync_no_gateways_message".localizedString
        configureDynamicFont(
            emptyMessageLabel,
            baseSize: 12,
            weight: .regular,
            textStyle: .caption1
        )
        emptyMessageLabel.textColor = AssistText_Color
        emptyMessageLabel.textAlignment = .center
        emptyMessageLabel.numberOfLines = 0
        emptyMessageLabel.isAccessibilityElement = false
        emptyStateView.addSubview(emptyMessageLabel)
        emptyMessageLabel.snp.makeConstraints { make in
            make.top.equalTo(emptyTitleLabel.snp.bottom).offset(SCRYFrom(4))
            make.left.right.equalToSuperview().inset(SCRXFrom(16))
            make.bottom.lessThanOrEqualToSuperview().offset(SCRYFrom(-16))
        }
        emptyStateView.isAccessibilityElement = true
        emptyStateView.accessibilityLabel = "\("site_entry_sync_no_gateways_title".localizedString). \("site_entry_sync_no_gateways_message".localizedString)"
        emptyStateView.accessibilityTraits = .staticText
    }

    private func setupFailureSummary() {
        failureSummaryCardView.backgroundColor = RGB(248, 250, 252)
        failureSummaryCardView.layer.cornerRadius = SCRYFrom(14)
        addSubview(failureSummaryCardView)
        failureSummaryCardView.snp.makeConstraints { make in
            make.height.equalTo(SCRYFrom(96))
            make.left.right.equalToSuperview()
        }
        failureSummaryTopConstraint = failureSummaryCardView.snp.prepareConstraints { make in
            make.top.equalTo(gatewayCardView.snp.bottom).offset(SCRYFrom(12))
        }.first
        failureSummaryBottomConstraint = failureSummaryCardView.snp.prepareConstraints { make in
            make.bottom.equalToSuperview()
        }.first

        failureIconBackgroundView.backgroundColor = RGB(255, 72, 49, 0.12)
        failureIconBackgroundView.layer.cornerRadius = SCRYFrom(16)
        failureSummaryCardView.addSubview(failureIconBackgroundView)
        failureIconBackgroundView.snp.makeConstraints { make in
            make.left.equalToSuperview().offset(SCRXFrom(16))
            make.top.equalToSuperview().offset(SCRYFrom(16))
            make.size.equalTo(SCRYFrom(32))
        }

        failureIconImageView.image = UIImage(named: "gateway_sync_tz_fail")
        failureIconImageView.contentMode = .scaleAspectFit
        failureIconImageView.isAccessibilityElement = false
        failureIconBackgroundView.addSubview(failureIconImageView)
        failureIconImageView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.size.equalTo(SCRYFrom(16))
        }

        configureDynamicFont(
            failureTitleLabel,
            baseSize: 14,
            weight: .regular,
            textStyle: .subheadline
        )
        failureTitleLabel.textColor = Error_Red_Color
        failureTitleLabel.isAccessibilityElement = false
        failureSummaryCardView.addSubview(failureTitleLabel)
        failureTitleLabel.snp.makeConstraints { make in
            make.left.equalTo(failureIconBackgroundView.snp.right).offset(SCRXFrom(12))
            make.right.equalToSuperview().offset(SCRXFrom(-16))
            make.top.equalToSuperview().offset(SCRYFrom(15))
        }

        failureMessageLabel.text = "site_entry_sync_failed_guidance".localizedString
        configureDynamicFont(
            failureMessageLabel,
            baseSize: 12,
            weight: .regular,
            textStyle: .caption1
        )
        failureMessageLabel.textColor = AssistText_Color
        failureMessageLabel.numberOfLines = 0
        failureMessageLabel.isAccessibilityElement = false
        failureSummaryCardView.addSubview(failureMessageLabel)
        failureMessageLabel.snp.makeConstraints { make in
            make.left.right.equalTo(failureTitleLabel)
            make.top.equalTo(failureTitleLabel.snp.bottom).offset(SCRYFrom(4))
            make.bottom.lessThanOrEqualToSuperview().offset(SCRYFrom(-16))
        }
        failureSummaryCardView.isAccessibilityElement = true
        failureSummaryCardView.accessibilityTraits = .staticText
    }

    private func configurePresentation(hasGateways: Bool, hasFailureSummary: Bool) {
        [
            gatewayCardTopConstraint,
            gatewayCardBottomConstraint,
            emptyStateTopConstraint,
            emptyStateBottomConstraint,
            failureSummaryTopConstraint,
            failureSummaryBottomConstraint
        ].forEach { $0?.deactivate() }

        gatewayCardView.isHidden = !hasGateways
        emptyStateView.isHidden = hasGateways
        let shouldShowFailureSummary = hasGateways && hasFailureSummary
        failureSummaryCardView.isHidden = !shouldShowFailureSummary

        if hasGateways {
            gatewayCardTopConstraint.activate()
            if shouldShowFailureSummary {
                failureSummaryTopConstraint.activate()
                failureSummaryBottomConstraint.activate()
            } else {
                gatewayCardBottomConstraint.activate()
            }
        } else {
            emptyStateTopConstraint.activate()
            emptyStateBottomConstraint.activate()
        }
    }
}

private func configureDynamicFont(
    _ label: UILabel,
    baseSize: CGFloat,
    weight: UIFont.Weight,
    textStyle: UIFont.TextStyle
) {
    label.font = UIFontMetrics(forTextStyle: textStyle).scaledFont(
        for: UIFont.systemFont(ofSize: SCRYFrom(baseSize), weight: weight)
    )
    label.adjustsFontForContentSizeCategory = true
    label.maximumContentSizeCategory = .large
}

extension SiteEntryGatewayTimeZoneStatusView: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        items.count
    }

    func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: GatewayTimeZoneStatusCell.reuseIdentifier,
            for: indexPath
        ) as? GatewayTimeZoneStatusCell else {
            return UITableViewCell()
        }
        cell.update(items[indexPath.row])
        return cell
    }
}

private final class GatewayTimeZoneStatusCell: UITableViewCell {

    static let reuseIdentifier = "GatewayTimeZoneStatusCell"

    private let gatewayImageView = UIImageView()
    private let nameLabel = UILabel()
    private let statusImageView = UIImageView()
    private let statusLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        stopLoadingAnimation()
        statusImageView.isHidden = false
        accessibilityLabel = nil
        accessibilityValue = nil
    }

    func update(_ item: SiteGatewayCloudTimeZoneItem) {
        stopLoadingAnimation()
        nameLabel.text = item.displayName.isEmpty ? item.requestMAC : item.displayName

        switch item.status {
        case .pushing:
            gatewayImageView.image = UIImage(named: "time-zone-sync-status-gateway")
            statusImageView.image = UIImage(named: "site_entry_sync_loading")
            statusImageView.isHidden = false
            statusLabel.text = "site_entry_sync_gateway_pushing".localizedString
            statusLabel.textColor = Purple_Color
            startLoadingAnimation()
        case .synced:
            gatewayImageView.image = UIImage(named: "time-zone-sync-status-gateway")
            statusImageView.image = UIImage(named: "site_entry_sync_success")
            statusImageView.isHidden = false
            statusLabel.text = "site_entry_sync_gateway_synced".localizedString
            statusLabel.textColor = Green_Color
        case .failed:
            gatewayImageView.image = UIImage(named: "gateway_sync_tz_fail")
            statusImageView.image = nil
            statusImageView.isHidden = true
            statusLabel.text = "site_entry_sync_gateway_failed".localizedString
            statusLabel.textColor = Error_Red_Color
        }
        accessibilityLabel = item.displayName.isEmpty ? item.requestMAC : item.displayName
        accessibilityValue = statusLabel.text
    }

    private func setupUI() {
        backgroundColor = .clear
        selectionStyle = .none

        gatewayImageView.contentMode = .scaleAspectFit
        gatewayImageView.isAccessibilityElement = false
        contentView.addSubview(gatewayImageView)
        gatewayImageView.snp.makeConstraints { make in
            make.left.equalToSuperview().offset(SCRXFrom(16))
            make.centerY.equalToSuperview()
            make.size.equalTo(SCRYFrom(16))
        }

        configureDynamicFont(
            nameLabel,
            baseSize: 14,
            weight: .regular,
            textStyle: .subheadline
        )
        nameLabel.textColor = TextBlack_Color
        nameLabel.numberOfLines = 1
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.isAccessibilityElement = false
        contentView.addSubview(nameLabel)
        nameLabel.snp.makeConstraints { make in
            make.left.equalTo(gatewayImageView.snp.right).offset(SCRXFrom(8))
            make.centerY.equalToSuperview()
        }

        configureDynamicFont(
            statusLabel,
            baseSize: 12,
            weight: .regular,
            textStyle: .caption1
        )
        statusLabel.textAlignment = .right
        statusLabel.isAccessibilityElement = false
        contentView.addSubview(statusLabel)
        statusLabel.snp.makeConstraints { make in
            make.right.equalToSuperview().offset(SCRXFrom(-16))
            make.centerY.equalToSuperview()
        }

        statusImageView.contentMode = .scaleAspectFit
        statusImageView.isAccessibilityElement = false
        contentView.addSubview(statusImageView)
        statusImageView.snp.makeConstraints { make in
            make.right.equalTo(statusLabel.snp.left).offset(SCRXFrom(-6))
            make.centerY.equalToSuperview()
            make.size.equalTo(SCRYFrom(16))
            make.left.greaterThanOrEqualTo(nameLabel.snp.right).offset(SCRXFrom(8))
        }

        isAccessibilityElement = true
        accessibilityTraits = .staticText
    }

    private func startLoadingAnimation() {
        guard statusImageView.layer.animation(forKey: "siteEntrySyncLoading") == nil else { return }
        let animation = CABasicAnimation(keyPath: "transform.rotation.z")
        animation.fromValue = 0
        animation.toValue = Double.pi * 2
        animation.duration = 1
        animation.repeatCount = .infinity
        statusImageView.layer.add(animation, forKey: "siteEntrySyncLoading")
    }

    private func stopLoadingAnimation() {
        statusImageView.layer.removeAnimation(forKey: "siteEntrySyncLoading")
    }
}
