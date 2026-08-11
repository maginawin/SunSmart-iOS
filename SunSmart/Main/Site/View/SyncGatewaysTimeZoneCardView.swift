//
//  SyncGatewaysTimeZoneCardView.swift
//  SunSmart
//
//  Created by One on 2026/8/13.
//

import UIKit
import SnapKit

final class SyncGatewaysTimeZoneCardView: UIView {

    private let titleLabel = UILabel()
    private let offsetLabel = UILabel()
    private let progressLabel = UILabel()
    private let progressTrackView = UIView()
    private let progressFillView = UIView()
    private var progressWidthConstraint: Constraint?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(
        siteName: String,
        timeZone: SiteTimeZoneValue,
        progress: SyncGatewaysProgress
    ) {
        titleLabel.text = String(
            format: "site_sync_gateways_timezone_title_format".localizedString,
            siteName
        )
        offsetLabel.text = timeZone.displayOffset
        progressLabel.text = String(
            format: "site_sync_gateways_progress_format".localizedString,
            progress.updated,
            progress.total
        )
        let ratio = progress.total > 0
            ? CGFloat(progress.updated) / CGFloat(progress.total)
            : 0
        progressWidthConstraint?.deactivate()
        progressFillView.snp.makeConstraints { make in
            progressWidthConstraint = make.width.equalTo(progressTrackView.snp.width)
                .multipliedBy(max(0, min(1, ratio)))
                .constraint
        }
    }

    private func setupUI() {
        backgroundColor = RGB(255, 255, 255)
        layer.cornerRadius = SCRYFrom(16)

        titleLabel.font = UIFont.systemFont(ofSize: SCRYFrom(14), weight: .regular)
        titleLabel.textColor = RGB(101, 120, 152)
        addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.top.left.right.equalToSuperview().inset(SCRYFrom(16))
            make.height.greaterThanOrEqualTo(SCRYFrom(20))
        }

        offsetLabel.font = UIFont.systemFont(ofSize: SCRYFrom(20), weight: .regular)
        offsetLabel.textColor = RGB(27, 20, 37)
        addSubview(offsetLabel)
        offsetLabel.snp.makeConstraints { make in
            make.left.equalTo(titleLabel)
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(4))
            make.height.greaterThanOrEqualTo(SCRYFrom(32))
        }

        progressLabel.font = UIFont.systemFont(ofSize: SCRYFrom(14), weight: .light)
        progressLabel.textColor = RGB(100, 116, 139)
        progressLabel.textAlignment = .right
        addSubview(progressLabel)
        progressLabel.snp.makeConstraints { make in
            make.right.equalTo(titleLabel)
            make.centerY.equalTo(offsetLabel)
            make.left.greaterThanOrEqualTo(offsetLabel.snp.right).offset(SCRXFrom(12))
        }

        progressTrackView.backgroundColor = RGB(229, 232, 240)
        progressTrackView.layer.cornerRadius = SCRYFrom(2)
        progressTrackView.clipsToBounds = true
        addSubview(progressTrackView)
        progressTrackView.snp.makeConstraints { make in
            make.left.right.equalTo(titleLabel)
            make.top.equalTo(offsetLabel.snp.bottom).offset(SCRYFrom(16))
            make.height.equalTo(SCRYFrom(4))
            make.bottom.equalToSuperview().inset(SCRYFrom(16))
        }

        progressFillView.backgroundColor = RGB(104, 100, 179)
        progressTrackView.addSubview(progressFillView)
        progressFillView.snp.makeConstraints { make in
            make.left.top.bottom.equalToSuperview()
            progressWidthConstraint = make.width.equalTo(0).constraint
        }
    }
}

