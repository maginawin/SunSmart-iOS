//
//  SpaceDebugUARTMessageCell.swift
//  SunSmart
//
//  Created on 2026/5/16.
//

import UIKit

final class SpaceDebugUARTMessageCell: UITableViewCell {
    static let reuseIdentifier = "SpaceDebugUARTMessageCell"

    private static let dateFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return dateFormatter
    }()

    private let timestampLabel = UILabel()
    private let bubbleView = UIView()
    private let bubbleLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(message: SpaceDebugUARTMessage) {
        timestampLabel.isHidden = false
        timestampLabel.text = Self.dateFormatter.string(from: message.timestamp)
        bubbleLabel.text = message.text
    }

    private func setupUI() {
        backgroundColor = .clear
        selectionStyle = .none

        timestampLabel.font = FONTS(SCRXFrom(12))
        timestampLabel.textColor = SubText_Color
        contentView.addSubview(timestampLabel)
        timestampLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.lessThanOrEqualTo(SCRXFrom(-16))
            make.top.equalTo(SCRYFrom(4))
        }

        bubbleLabel.font = FONTS(SCRXFrom(15))
        bubbleLabel.textColor = Title_Color
        bubbleLabel.numberOfLines = 0
        
        bubbleView.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.75)
        bubbleView.layer.cornerRadius = SCRXFrom(9)
        bubbleView.layer.masksToBounds = true
        contentView.addSubview(bubbleView)
        bubbleView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.equalTo(timestampLabel.snp.bottom).offset(SCRYFrom(2))
            make.width.lessThanOrEqualToSuperview().multipliedBy(0.72)
            make.bottom.equalTo(SCRYFrom(-4))
        }

        bubbleView.addSubview(bubbleLabel)
        bubbleLabel.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: SCRYFrom(6), left: SCRXFrom(12), bottom: SCRYFrom(6), right: SCRXFrom(12)))
        }
    }
}
