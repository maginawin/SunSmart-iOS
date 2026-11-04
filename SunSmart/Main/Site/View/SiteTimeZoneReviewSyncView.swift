//
//  SiteTimeZoneReviewSyncView.swift
//  SunSmart
//
//  Created by One on 2026/8/13.
//

import UIKit
import SnapKit

final class SiteTimeZoneReviewSyncView: UIView {

    var onReviewSync: (() -> Void)?

    private let iconView = UIImageView(
        image: UIImage(named: "site_entry_sync_warning")
    )
    private let messageLabel = UILabel()
    private let reviewButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(
        serverTimezone: SiteTimeZoneValue,
        gatewayCount: Int
    ) {
        messageLabel.attributedText = Self.message(timezone: serverTimezone, gatewayCount: gatewayCount)
    }

    static func preferredHeight(width: CGFloat, state: SiteTimeZoneReviewState) -> CGFloat {
        guard case .review(let timezone, let count) = state else { return 0 }
        let text = message(timezone: timezone, gatewayCount: count)
        let textWidth = max(1, width - SCRXFrom(151))
        let size = text.boundingRect(with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
                                     options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        return max(SCRYFrom(56), ceil(size.height) + SCRYFrom(24))
    }

    private static func message(timezone: SiteTimeZoneValue, gatewayCount: Int) -> NSAttributedString {
        let format = gatewayCount == 1
            ? "site_time_zone_review_sync_single".localizedString
            : "site_time_zone_review_sync_multiple".localizedString
        let text = gatewayCount == 1
            ? String(format: format, timezone.displayOffset)
            : String(format: format, timezone.displayOffset, gatewayCount)
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = SCRYFrom(16)
        paragraph.maximumLineHeight = SCRYFrom(16)
        return NSAttributedString(string: text, attributes: [
            .paragraphStyle: paragraph, .font: UIFont.systemFont(ofSize: SCRYFrom(12))
        ])
    }

    private func setupUI() {
        backgroundColor = RGB(255, 249, 239)
        layer.cornerRadius = SCRYFrom(14)

        iconView.contentMode = .scaleAspectFit
        addSubview(iconView)
        iconView.snp.makeConstraints { make in
            make.left.equalToSuperview().offset(SCRXFrom(12))
            make.centerY.equalToSuperview()
            make.size.equalTo(SCRYFrom(16))
        }

        reviewButton.backgroundColor = .white
        reviewButton.layer.cornerRadius = SCRYFrom(10)
        reviewButton.setTitle(
            "site_time_zone_review_sync_action".localizedString,
            for: .normal
        )
        reviewButton.setTitleColor(RGB(151, 60, 0), for: .normal)
        reviewButton.titleLabel?.font = UIFont.systemFont(
            ofSize: SCRYFrom(12),
            weight: .semibold
        )
        reviewButton.addTarget(
            self,
            action: #selector(reviewButtonDidTap),
            for: .touchUpInside
        )
        addSubview(reviewButton)
        reviewButton.snp.makeConstraints { make in
            make.right.equalToSuperview().offset(SCRXFrom(-12))
            make.centerY.equalToSuperview()
            make.height.equalTo(SCRYFrom(28))
            make.width.greaterThanOrEqualTo(SCRXFrom(87))
        }

        messageLabel.font = UIFont.systemFont(ofSize: SCRYFrom(12))
        messageLabel.textColor = RGB(100, 116, 139)
        messageLabel.numberOfLines = 0
        messageLabel.lineBreakMode = .byWordWrapping
        addSubview(messageLabel)
        messageLabel.snp.makeConstraints { make in
            make.left.equalTo(iconView.snp.right).offset(SCRXFrom(12))
            make.right.equalTo(reviewButton.snp.left).offset(SCRXFrom(-12))
            make.centerY.equalToSuperview()
        }
    }

    @objc private func reviewButtonDidTap() {
        onReviewSync?()
    }
}
