//
//  SyncGatewaysSupportingViews.swift
//  SunSmart
//
//  Created by One on 2026/8/13.
//

import UIKit
import SnapKit

enum SyncGatewaysCopy {
    static let pageBackgroundColor = RGB(246, 247, 251)

    static var nearbyTitle: String {
        "site_sync_gateways_nearby_title".localizedString
    }

    static var nearbyEmpty: String {
        "site_sync_gateways_nearby_empty".localizedString
    }

    static var otherTitle: String {
        "site_sync_gateways_other_title".localizedString
    }

    static func gatewayName(_ item: SyncGatewayItemState) -> String {
        if let displayName = item.displayName, !displayName.isEmpty {
            return displayName
        }
        return String(
            format: "site_sync_gateways_gateway_fallback".localizedString,
            item.remoteOrder + 1
        )
    }

    static func attention(_ count: Int) -> String {
        if count == 1 {
            return "site_sync_gateways_attention_single".localizedString
        }
        return String(
            format: "site_sync_gateways_attention_multiple".localizedString,
            count
        )
    }

    static func toast(success: Bool, gatewayName: String) -> String {
        let format = success
            ? "site_sync_gateways_success_toast".localizedString
            : "site_sync_gateways_failure_toast".localizedString
        return String(format: format, gatewayName)
    }
}

final class SyncGatewaysOnSiteAlertView: UIView {
    private let iconView = UIImageView(image: UIImage(named: "site_entry_sync_warning"))
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        backgroundColor = RGB(255, 249, 239)
        layer.cornerRadius = SCRYFrom(16)

        iconView.contentMode = .scaleAspectFit
        addSubview(iconView)
        iconView.snp.makeConstraints { make in
            make.left.equalToSuperview().offset(SCRXFrom(16))
            make.top.equalToSuperview().offset(SCRYFrom(14))
            make.size.equalTo(SCRYFrom(20))
        }

        titleLabel.text = "site_sync_gateways_onsite_title".localizedString
        titleLabel.font = UIFont.systemFont(ofSize: SCRYFrom(14), weight: .regular)
        titleLabel.textColor = RGB(117, 82, 31)
        addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(iconView.snp.right).offset(SCRXFrom(12))
            make.right.equalToSuperview().offset(SCRXFrom(-16))
            make.top.equalToSuperview().offset(SCRYFrom(12))
            make.height.greaterThanOrEqualTo(SCRYFrom(20))
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = SCRYFrom(20)
        paragraph.maximumLineHeight = SCRYFrom(20)
        messageLabel.attributedText = NSAttributedString(
            string: "site_sync_gateways_onsite_message".localizedString,
            attributes: [.paragraphStyle: paragraph]
        )
        messageLabel.font = UIFont.systemFont(ofSize: SCRYFrom(12), weight: .light)
        messageLabel.textColor = RGB(100, 116, 139)
        messageLabel.numberOfLines = 0
        addSubview(messageLabel)
        messageLabel.snp.makeConstraints { make in
            make.left.right.equalTo(titleLabel)
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(4))
            make.bottom.equalToSuperview().offset(SCRYFrom(-12))
        }
    }
}

final class SyncGatewaysSectionHeaderView: UIView {
    private let titleLabel = UILabel()
    private let loadingImageView = UIImageView(image: UIImage(named: "site_entry_sync_loading"))

    init(titleKey: String, showsSearching: Bool) {
        super.init(frame: .zero)
        titleLabel.text = titleKey.localizedString
        loadingImageView.isHidden = !showsSearching
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func startSearchingAnimation() {
        guard loadingImageView.layer.animation(forKey: "syncGatewaysSearching") == nil else { return }
        let animation = CABasicAnimation(keyPath: "transform.rotation.z")
        animation.fromValue = 0
        animation.toValue = Double.pi * 2
        animation.duration = 1
        animation.repeatCount = .infinity
        loadingImageView.layer.add(animation, forKey: "syncGatewaysSearching")
    }

    func stopSearchingAnimation() {
        loadingImageView.layer.removeAnimation(forKey: "syncGatewaysSearching")
    }

    private func setupUI() {
        titleLabel.font = UIFont.systemFont(ofSize: SCRYFrom(14), weight: .regular)
        titleLabel.textColor = RGB(30, 35, 41)
        addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalToSuperview().offset(SCRXFrom(8))
            make.centerY.equalToSuperview()
        }

        loadingImageView.contentMode = .scaleAspectFit
        addSubview(loadingImageView)
        loadingImageView.snp.makeConstraints { make in
            make.right.equalToSuperview().offset(SCRXFrom(-8))
            make.centerY.equalToSuperview()
            make.size.equalTo(SCRYFrom(24))
        }
    }
}

final class SyncGatewaysMessageView: UIView {
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.font = UIFont.systemFont(ofSize: SCRYFrom(14), weight: .regular)
        label.textColor = RGB(148, 163, 184)
        label.textAlignment = .center
        label.numberOfLines = 0
        addSubview(label)
        label.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(
                top: SCRYFrom(12),
                left: SCRXFrom(4),
                bottom: SCRYFrom(12),
                right: SCRXFrom(4)
            ))
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(text: String, fontSize: CGFloat = 12) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = SCRYFrom(20)
        paragraph.maximumLineHeight = SCRYFrom(20)
        paragraph.alignment = .center
        label.font = UIFont.systemFont(ofSize: SCRYFrom(fontSize), weight: .regular)
        label.attributedText = NSAttributedString(
            string: text,
            attributes: [.paragraphStyle: paragraph]
        )
    }
}

final class SyncGatewaysBottomActionBar: UIView {
    var onDone: (() -> Void)?

    private let doneButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .white

        let divider = UIView()
        divider.backgroundColor = RGB(243, 243, 243)
        addSubview(divider)
        divider.snp.makeConstraints { make in
            make.top.left.right.equalToSuperview()
            make.height.equalTo(0.5)
        }

        doneButton.setTitle("site_sync_gateways_done".localizedString, for: .normal)
        doneButton.setTitleColor(RGB(30, 35, 41), for: .normal)
        doneButton.titleLabel?.font = UIFont.systemFont(ofSize: SCRYFrom(16), weight: .light)
        doneButton.addTarget(self, action: #selector(doneDidTap), for: .touchUpInside)
        addSubview(doneButton)
        doneButton.snp.makeConstraints { make in
            make.top.left.right.equalToSuperview()
            make.height.equalTo(SCRYFrom(56))
        }

        snp.makeConstraints { make in
            make.height.equalTo(SCRYFrom(90))
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func doneDidTap() {
        onDone?()
    }
}
