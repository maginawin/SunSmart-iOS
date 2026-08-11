//
//  SiteTimeZoneSelectionCell.swift
//  SunSmart
//
//  Created by One on 2026/8/11.
//

import UIKit

final class SiteTimeZoneSelectionCell: UITableViewCell {

    static let reuseIdentifier = "SiteTimeZoneSelectionCell"

    private let cardView = UIView()
    private let ianaIdLabel = UILabel()
    private let utcOffsetLabel = UILabel()
    private let separatorView = UIView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        entry: SiteTimeZoneCatalogEntry,
        isFirst: Bool,
        isLast: Bool
    ) {
        ianaIdLabel.text = entry.ianaId
        utcOffsetLabel.text = entry.value.displayOffset
        separatorView.isHidden = isLast

        var corners: CACornerMask = []
        if isFirst {
            corners.formUnion([.layerMinXMinYCorner, .layerMaxXMinYCorner])
        }
        if isLast {
            corners.formUnion([.layerMinXMaxYCorner, .layerMaxXMaxYCorner])
        }
        cardView.layer.cornerRadius = corners.isEmpty ? 0 : SCRYFrom(14)
        cardView.layer.maskedCorners = corners
    }

    private func setupUI() {
        selectionStyle = .none
        accessoryType = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        cardView.backgroundColor = .white
        cardView.layer.masksToBounds = true
        contentView.addSubview(cardView)
        cardView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        ianaIdLabel.font = UIFont.systemFont(ofSize: SCRYFrom(14))
        ianaIdLabel.textColor = RGB(27, 20, 37)
        ianaIdLabel.lineBreakMode = .byTruncatingTail
        cardView.addSubview(ianaIdLabel)
        cardView.addSubview(utcOffsetLabel)
        ianaIdLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.centerY.equalToSuperview()
            make.right.lessThanOrEqualTo(utcOffsetLabel.snp.left).offset(SCRXFrom(-8))
        }

        utcOffsetLabel.font = UIFont.systemFont(ofSize: SCRYFrom(14))
        utcOffsetLabel.textColor = RGB(148, 163, 184)
        utcOffsetLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        utcOffsetLabel.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.centerY.equalToSuperview()
        }

        separatorView.backgroundColor = RGB(193, 207, 226, 0.5)
        cardView.addSubview(separatorView)
        separatorView.snp.makeConstraints { make in
            make.left.equalTo(ianaIdLabel)
            make.right.bottom.equalToSuperview()
            make.height.equalTo(0.5)
        }
    }
}
