//
//  SiteEntryGatewayTimeZoneStatusView.swift
//  SunSmart
//
//  Created by One on 2026/8/15.
//

import UIKit
import SnapKit

final class SiteEntryGatewayTimeZoneStatusView: UIView {

    private static let maximumVisibleGatewayCount = 3
    private static let failureTextVerticalInset: CGFloat = 15

    var onPreferredHeightChanged: (() -> Void)?

    private let gatewayCardView = UIView()
    private let gatewayHeaderView = UIView()
    private let gatewayHeaderLabel = UILabel()
    private let gatewayCountLabel = UILabel()
    private let headerDividerView = UIView()
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let emptyStateView = UIView()
    private let emptyHeaderLabel = UILabel()
    private let emptyContentView = UIView()
    private let emptyIconBackgroundView = UIView()
    private let emptyIconImageView = UIImageView()
    private let emptyTitleLabel = UILabel()
    private let emptyMessageLabel = UILabel()
    private let failureSummaryCardView = UIView()
    private let failureIconBackgroundView = UIView()
    private let failureIconImageView = UIImageView()
    private let failureTitleLabel = UILabel()
    private let failureMessageLabel = UILabel()
    private let sizingCell = GatewayTimeZoneStatusCell(
        style: .default,
        reuseIdentifier: nil
    )

    private var items = [SiteGatewayCloudTimeZoneItem]()
    private var gatewayCardTopConstraint: Constraint!
    private var gatewayCardBottomConstraint: Constraint!
    private var emptyStateTopConstraint: Constraint!
    private var emptyStateBottomConstraint: Constraint!
    private var failureSummaryTopConstraint: Constraint!
    private var failureSummaryBottomConstraint: Constraint!
    private var gatewayHeaderHeightConstraint: Constraint!
    private var measuredPreferredHeight = SCRYFrom(89)
    private var measuredMinimumViewportHeight = SCRYFrom(89)
    private var lastMeasuredWidth: CGFloat = 0
    private var needsHeightMeasurement = true
    private var isMeasuringHeight = false

    var preferredHeight: CGFloat {
        measuredPreferredHeight
    }

    var minimumViewportHeight: CGFloat {
        measuredMinimumViewportHeight
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

    override func layoutSubviews() {
        super.layoutSubviews()

        let width = bounds.width
        guard width > 0 else { return }
        if abs(width - lastMeasuredWidth) > 0.5 {
            needsHeightMeasurement = true
        }
        updateMeasuredHeightsIfNeeded(width: width)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard previousTraitCollection?.preferredContentSizeCategory !=
                traitCollection.preferredContentSizeCategory else {
            return
        }
        tableView.reloadData()
        tableView.setNeedsLayout()
        needsHeightMeasurement = true
        setNeedsLayout()
    }

    func update(_ presentation: SiteTimeZoneGatewayPresentation) {
        switch presentation {
        case .notStarted:
            resetForNotStarted()

        case .unavailable:
            items = []
            updateTableScrolling()
            emptyIconBackgroundView.backgroundColor = .clear
            emptyIconImageView.image = UIImage(named: "gateway_sync_tz_fail")
            emptyTitleLabel.text = "site_time_zone_gateway_check_unavailable_title".localizedString
            emptyMessageLabel.text = "site_time_zone_gateway_check_unavailable_message".localizedString
            emptyContentView.accessibilityLabel = "\(emptyTitleLabel.text ?? ""). \(emptyMessageLabel.text ?? "")"
            configurePresentation(hasGateways: false, hasFailureSummary: false)
            tableView.reloadData()
            needsHeightMeasurement = true
            setNeedsLayout()

        case .batch(let state):
            update(state)
        }
    }

    func update(_ state: SiteGatewayCloudTimeZoneBatchState) {
        emptyIconBackgroundView.backgroundColor = RGB(148, 163, 184, 0.1)
        emptyIconImageView.image = UIImage(named: "gateway_no_space_svg")
        emptyTitleLabel.text = "site_no_gateways".localizedString
        emptyMessageLabel.text = "site_no_gateways_sync_needed".localizedString
        emptyContentView.accessibilityLabel = "\(emptyTitleLabel.text ?? ""). \(emptyMessageLabel.text ?? "")"
        items = state.items
        updateTableScrolling()
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
        needsHeightMeasurement = true
        setNeedsLayout()
    }

    private func updateTableScrolling() {
        let shouldScroll = items.count > Self.maximumVisibleGatewayCount
        tableView.isScrollEnabled = shouldScroll
        tableView.showsVerticalScrollIndicator = shouldScroll
        if !shouldScroll {
            tableView.setContentOffset(.zero, animated: false)
        }
    }

    private func setupUI() {
        setupGatewayCard()
        setupEmptyState()
        setupFailureSummary()
        resetForNotStarted()
    }

    private func setupGatewayCard() {
        gatewayCardView.backgroundColor = RGB(248, 250, 252)
        gatewayCardView.layer.cornerRadius = SCRYFrom(14)
        gatewayCardView.layer.masksToBounds = true
        addSubview(gatewayCardView)
        gatewayCardView.snp.makeConstraints { make in
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
        gatewayHeaderLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        configureDynamicFont(
            gatewayCountLabel,
            baseSize: 12,
            weight: .regular,
            textStyle: .caption1
        )
        gatewayCountLabel.textColor = AssistText_Color
        gatewayCountLabel.textAlignment = .right
        gatewayCountLabel.isAccessibilityElement = false
        gatewayCountLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        gatewayHeaderView.addSubview(gatewayHeaderLabel)
        gatewayHeaderView.addSubview(gatewayCountLabel)
        gatewayHeaderLabel.snp.makeConstraints { make in
            make.left.equalToSuperview().offset(SCRXFrom(16))
            make.right.lessThanOrEqualTo(gatewayCountLabel.snp.left).offset(SCRXFrom(-8))
            make.centerY.equalToSuperview()
            make.top.greaterThanOrEqualToSuperview().offset(SCRYFrom(12))
            make.bottom.lessThanOrEqualToSuperview().offset(SCRYFrom(-12))
        }
        gatewayCountLabel.snp.makeConstraints { make in
            make.right.equalToSuperview().offset(SCRXFrom(-16))
            make.centerY.equalToSuperview()
            make.top.greaterThanOrEqualToSuperview().offset(SCRYFrom(12))
            make.bottom.lessThanOrEqualToSuperview().offset(SCRYFrom(-12))
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
            make.height.greaterThanOrEqualTo(SCRYFrom(44))
        }
        gatewayHeaderHeightConstraint = gatewayHeaderView.snp.prepareConstraints { make in
            make.height.equalTo(SCRYFrom(44))
        }.first
        gatewayHeaderHeightConstraint.activate()
        gatewayHeaderView.isAccessibilityElement = true
        gatewayHeaderView.accessibilityTraits = .header

        tableView.backgroundColor = .clear
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(GatewayTimeZoneStatusCell.self, forCellReuseIdentifier: GatewayTimeZoneStatusCell.reuseIdentifier)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = SCRYFrom(44)
        tableView.separatorStyle = .singleLine
        tableView.separatorColor = RGB(229, 232, 240)
        tableView.separatorInset = UIEdgeInsets(
            top: 0,
            left: SCRXFrom(16),
            bottom: 0,
            right: SCRXFrom(16)
        )
        tableView.isScrollEnabled = false
        tableView.showsVerticalScrollIndicator = false
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
            make.left.right.equalToSuperview()
        }
        emptyStateTopConstraint = emptyStateView.snp.prepareConstraints { make in
            make.top.equalToSuperview()
        }.first
        emptyStateBottomConstraint = emptyStateView.snp.prepareConstraints { make in
            make.bottom.equalToSuperview()
        }.first

        emptyHeaderLabel.text = "site_entry_sync_gateways_header".localizedString
        configureDynamicFont(
            emptyHeaderLabel,
            baseSize: 12,
            weight: .regular,
            textStyle: .caption1
        )
        emptyHeaderLabel.textColor = RGB(100, 116, 139)
        emptyHeaderLabel.isAccessibilityElement = true
        emptyHeaderLabel.accessibilityTraits = .header
        emptyStateView.addSubview(emptyHeaderLabel)
        emptyHeaderLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(SCRYFrom(8))
            make.left.right.equalToSuperview().inset(SCRXFrom(16))
            make.height.greaterThanOrEqualTo(SCRYFrom(21))
        }

        emptyStateView.addSubview(emptyContentView)
        emptyContentView.snp.makeConstraints { make in
            make.top.equalTo(emptyHeaderLabel.snp.bottom)
            make.left.right.equalToSuperview().inset(SCRXFrom(16))
            make.bottom.equalToSuperview().inset(SCRYFrom(8))
        }

        emptyIconBackgroundView.backgroundColor = RGB(148, 163, 184, 0.1)
        emptyIconBackgroundView.layer.cornerRadius = SCRYFrom(16)
        emptyIconBackgroundView.isAccessibilityElement = false
        emptyContentView.addSubview(emptyIconBackgroundView)
        emptyIconBackgroundView.snp.makeConstraints { make in
            make.left.equalToSuperview()
            make.centerY.equalToSuperview()
            make.top.greaterThanOrEqualToSuperview().offset(SCRYFrom(8))
            make.bottom.lessThanOrEqualToSuperview().offset(SCRYFrom(-8))
            make.size.equalTo(SCRYFrom(32))
        }

        emptyIconImageView.image = UIImage(named: "time-zone-sync-status-gateway")
        emptyIconImageView.contentMode = .scaleAspectFit
        emptyIconImageView.isAccessibilityElement = false
        emptyIconBackgroundView.addSubview(emptyIconImageView)
        emptyIconImageView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.size.equalTo(SCRYFrom(16))
        }

        emptyTitleLabel.text = "site_no_gateways".localizedString
        configureDynamicFont(
            emptyTitleLabel,
            baseSize: 14,
            weight: .light,
            textStyle: .subheadline
        )
        emptyTitleLabel.textColor = RGB(30, 35, 41)
        emptyTitleLabel.textAlignment = .left
        emptyTitleLabel.numberOfLines = 0
        emptyTitleLabel.isAccessibilityElement = false
        emptyContentView.addSubview(emptyTitleLabel)
        emptyTitleLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(SCRYFrom(8))
            make.left.equalTo(emptyIconBackgroundView.snp.right).offset(SCRXFrom(12))
            make.right.equalToSuperview().offset(SCRXFrom(-16))
            make.height.greaterThanOrEqualTo(SCRYFrom(20))
        }

        emptyMessageLabel.text = "site_no_gateways_sync_needed".localizedString
        configureDynamicFont(
            emptyMessageLabel,
            baseSize: 12,
            weight: .regular,
            textStyle: .caption1
        )
        emptyMessageLabel.textColor = AssistText_Color
        emptyMessageLabel.textAlignment = .left
        emptyMessageLabel.numberOfLines = 0
        emptyMessageLabel.isAccessibilityElement = false
        emptyContentView.addSubview(emptyMessageLabel)
        emptyMessageLabel.snp.makeConstraints { make in
            make.top.equalTo(emptyTitleLabel.snp.bottom)
            make.left.right.equalTo(emptyTitleLabel)
            make.height.greaterThanOrEqualTo(SCRYFrom(16))
            make.bottom.equalToSuperview().inset(SCRYFrom(8))
        }
        emptyContentView.isAccessibilityElement = true
        emptyContentView.accessibilityLabel = "\("site_no_gateways".localizedString). \("site_no_gateways_sync_needed".localizedString)"
        emptyContentView.accessibilityTraits = .staticText
    }

    private func setupFailureSummary() {
        failureSummaryCardView.backgroundColor = RGB(248, 250, 252)
        failureSummaryCardView.layer.cornerRadius = SCRYFrom(14)
        addSubview(failureSummaryCardView)
        failureSummaryCardView.snp.makeConstraints { make in
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
            make.bottom.lessThanOrEqualToSuperview().offset(SCRYFrom(-16))
            make.size.equalTo(SCRYFrom(32))
        }

        failureIconImageView.image = UIImage(named: "gateway_sync_tz_fail_circle")
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
            make.top.equalToSuperview().offset(SCRYFrom(Self.failureTextVerticalInset))
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
            make.bottom.equalToSuperview().inset(SCRYFrom(Self.failureTextVerticalInset))
        }
        failureSummaryCardView.isAccessibilityElement = true
        failureSummaryCardView.accessibilityTraits = .staticText
    }

    private func deactivatePresentationConstraints() {
        [
            gatewayCardTopConstraint,
            gatewayCardBottomConstraint,
            emptyStateTopConstraint,
            emptyStateBottomConstraint,
            failureSummaryTopConstraint,
            failureSummaryBottomConstraint
        ].forEach { $0?.deactivate() }
    }

    private func resetForNotStarted() {
        deactivatePresentationConstraints()
        gatewayCardView.isHidden = true
        emptyStateView.isHidden = true
        failureSummaryCardView.isHidden = true

        for case let cell as GatewayTimeZoneStatusCell in tableView.visibleCells {
            cell.stopLoadingAnimation()
        }
        sizingCell.stopLoadingAnimation()
        items.removeAll()
        updateTableScrolling()
        tableView.reloadData()
        needsHeightMeasurement = true
        setNeedsLayout()
    }

    private func configurePresentation(hasGateways: Bool, hasFailureSummary: Bool) {
        deactivatePresentationConstraints()

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

    private func updateMeasuredHeightsIfNeeded(width: CGFloat) {
        guard needsHeightMeasurement, !isMeasuringHeight else { return }
        isMeasuringHeight = true
        defer { isMeasuringHeight = false }

        lastMeasuredWidth = width

        let newPreferredHeight: CGFloat
        let newMinimumViewportHeight: CGFloat
        if items.isEmpty {
            let emptyHeight = fittingHeight(of: emptyStateView, width: width)
            newPreferredHeight = emptyHeight
            newMinimumViewportHeight = emptyHeight
        } else {
            let headerHeight = ceil(max(
                SCRYFrom(44),
                fittingHeight(
                    of: gatewayHeaderView,
                    width: width,
                    temporarilyDeactivating: gatewayHeaderHeightConstraint
                )
            ))
            gatewayHeaderHeightConstraint.update(offset: headerHeight)
            let preferredRowsHeight = items.prefix(Self.maximumVisibleGatewayCount).reduce(
                CGFloat.zero
            ) { height, item in
                height + sizingCell.preferredHeight(
                    for: item,
                    width: width,
                    compatibleWith: traitCollection
                )
            }
            let gatewayCardHeight = headerHeight + preferredRowsHeight

            if failedCount > 0 {
                let failureHeight = ceil(
                    fittingHeight(of: failureSummaryCardView, width: width)
                )
                let summarySpacing = SCRYFrom(12)
                newPreferredHeight = gatewayCardHeight + summarySpacing + failureHeight
                newMinimumViewportHeight = headerHeight + summarySpacing + failureHeight
            } else {
                newPreferredHeight = gatewayCardHeight
                newMinimumViewportHeight = headerHeight
            }
        }

        let normalizedPreferredHeight = ceil(newPreferredHeight)
        let normalizedMinimumViewportHeight = ceil(newMinimumViewportHeight)
        needsHeightMeasurement = false
        guard abs(normalizedPreferredHeight - measuredPreferredHeight) > 0.5 ||
                abs(normalizedMinimumViewportHeight - measuredMinimumViewportHeight) > 0.5 else {
            return
        }
        measuredPreferredHeight = normalizedPreferredHeight
        measuredMinimumViewportHeight = normalizedMinimumViewportHeight
        invalidateIntrinsicContentSize()
        onPreferredHeightChanged?()
    }

    private func fittingHeight(of view: UIView, width: CGFloat) -> CGFloat {
        view.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
    }

    private func fittingHeight(
        of view: UIView,
        width: CGFloat,
        temporarilyDeactivating heightConstraint: Constraint
    ) -> CGFloat {
        heightConstraint.deactivate()
        defer { heightConstraint.activate() }
        return fittingHeight(of: view, width: width)
    }
}

private func configureDynamicFont(
    _ label: UILabel,
    baseSize: CGFloat,
    weight: UIFont.Weight,
    textStyle: UIFont.TextStyle,
    compatibleWith traitCollection: UITraitCollection? = nil
) {
    label.font = UIFontMetrics(forTextStyle: textStyle).scaledFont(
        for: UIFont.systemFont(ofSize: SCRYFrom(baseSize), weight: weight),
        compatibleWith: traitCollection
    )
    label.adjustsFontForContentSizeCategory = true
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
        accessibilityLabel = nil
        accessibilityValue = nil
    }

    func update(_ item: SiteGatewayCloudTimeZoneItem) {
        stopLoadingAnimation()
        nameLabel.text = item.displayName.isEmpty ? item.requestMAC : item.displayName

        switch item.status {
        case .pushing:
            gatewayImageView.image = UIImage(named: "site_entry_sync_loading")
            statusLabel.text = "site_entry_sync_gateway_pushing".localizedString
            statusLabel.textColor = Purple_Color
            startLoadingAnimation()
        case .synced:
            gatewayImageView.image = UIImage(named: "site_entry_sync_success")
            statusLabel.text = "site_entry_sync_gateway_synced".localizedString
            statusLabel.textColor = Green_Color
        case .failed:
            gatewayImageView.image = UIImage(named: "gateway_sync_tz_fail_circle")
            statusLabel.text = "site_entry_sync_gateway_failed".localizedString
            statusLabel.textColor = Error_Red_Color
        }
        accessibilityLabel = item.displayName.isEmpty ? item.requestMAC : item.displayName
        accessibilityValue = statusLabel.text
    }

    func preferredHeight(
        for item: SiteGatewayCloudTimeZoneItem,
        width: CGFloat,
        compatibleWith traitCollection: UITraitCollection
    ) -> CGFloat {
        configureFonts(compatibleWith: traitCollection)
        update(item)
        defer { stopLoadingAnimation() }
        bounds = CGRect(x: 0, y: 0, width: width, height: SCRYFrom(44))
        contentView.bounds = bounds
        setNeedsLayout()
        layoutIfNeeded()

        let height = contentView.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        return max(SCRYFrom(44), ceil(height))
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
            make.top.greaterThanOrEqualToSuperview().offset(SCRYFrom(14))
            make.bottom.lessThanOrEqualToSuperview().offset(SCRYFrom(-14))
            make.size.equalTo(SCRYFrom(16))
        }

        configureFonts()
        nameLabel.textColor = TextBlack_Color
        nameLabel.numberOfLines = 1
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.isAccessibilityElement = false
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        contentView.addSubview(nameLabel)
        nameLabel.snp.makeConstraints { make in
            make.left.equalTo(gatewayImageView.snp.right).offset(SCRXFrom(8))
            make.centerY.equalToSuperview()
            make.top.greaterThanOrEqualToSuperview().offset(SCRYFrom(12))
            make.bottom.lessThanOrEqualToSuperview().offset(SCRYFrom(-12))
        }

        statusLabel.textAlignment = .right
        statusLabel.numberOfLines = 0
        statusLabel.isAccessibilityElement = false
        statusLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        contentView.addSubview(statusLabel)
        statusLabel.snp.makeConstraints { make in
            make.right.equalToSuperview().offset(SCRXFrom(-16))
            make.centerY.equalToSuperview()
            make.top.greaterThanOrEqualToSuperview().offset(SCRYFrom(12))
            make.bottom.lessThanOrEqualToSuperview().offset(SCRYFrom(-12))
        }
        nameLabel.snp.makeConstraints { make in
            make.right.lessThanOrEqualTo(statusLabel.snp.left).offset(SCRXFrom(-8))
        }

        isAccessibilityElement = true
        accessibilityTraits = .staticText
    }

    private func configureFonts(compatibleWith traitCollection: UITraitCollection? = nil) {
        configureDynamicFont(
            nameLabel,
            baseSize: 14,
            weight: .regular,
            textStyle: .subheadline,
            compatibleWith: traitCollection
        )
        configureDynamicFont(
            statusLabel,
            baseSize: 12,
            weight: .regular,
            textStyle: .caption1,
            compatibleWith: traitCollection
        )
    }

    private func startLoadingAnimation() {
        guard gatewayImageView.layer.animation(forKey: "siteEntrySyncLoading") == nil else { return }
        let animation = CABasicAnimation(keyPath: "transform.rotation.z")
        animation.fromValue = 0
        animation.toValue = Double.pi * 2
        animation.duration = 1
        animation.repeatCount = .infinity
        gatewayImageView.layer.add(animation, forKey: "siteEntrySyncLoading")
    }

    fileprivate func stopLoadingAnimation() {
        gatewayImageView.layer.removeAnimation(forKey: "siteEntrySyncLoading")
    }
}
