//
//  SiteTimeZoneSyncStatusView.swift
//  SunSmart
//
//  Created by One on 2026/8/11.
//

import UIKit

final class SiteTimeZoneSyncStatusView: UIView {

    enum State {
        case saving
        case success
        case failure
    }

    private let sheetView = UIView()
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private let statusIconView = UIImageView()
    private let statusIconBackground = UIView()
    private let statusSubtitleLabel = UILabel()
    private let gatewayCard = UIView()
    private let doneButton = UIButton()

    private(set) var state: State = .saving

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
        update(state: .saving)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(in parentView: UIView? = nil) {
        let targetView = parentView ?? Self.activeWindow
        guard let targetView = targetView else { return }
        targetView.addSubview(self)
        snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }

    func update(state: State) {
        self.state = state
        doneButton.isHidden = state == .saving
        gatewayCard.isHidden = state != .success

        switch state {
        case .saving:
            activityIndicator.startAnimating()
            activityIndicator.isHidden = false
            statusIconView.isHidden = true
            statusIconBackground.backgroundColor = RGB(102, 103, 171, 0.1)
            statusSubtitleLabel.text = "site_time_zone_saving_to_server".localizedString
            statusSubtitleLabel.textColor = RGB(148, 163, 184)
            sheetView.snp.updateConstraints { make in
                make.height.equalTo(SCRYFrom(190) + (isIPad ? 0 : kSafeAreaBottomHeight))
            }

        case .success:
            activityIndicator.stopAnimating()
            activityIndicator.isHidden = true
            statusIconView.isHidden = false
            statusIconView.image = UIImage(systemName: "checkmark.circle")
            statusIconView.tintColor = RGB(16, 185, 129)
            statusIconBackground.backgroundColor = RGB(16, 185, 129, 0.1)
            statusSubtitleLabel.text = "site_time_zone_saved_successfully".localizedString
            statusSubtitleLabel.textColor = RGB(16, 185, 129)
            sheetView.snp.updateConstraints { make in
                make.height.equalTo(SCRYFrom(347) + (isIPad ? 0 : kSafeAreaBottomHeight))
            }

        case .failure:
            activityIndicator.stopAnimating()
            activityIndicator.isHidden = true
            statusIconView.isHidden = false
            statusIconView.image = UIImage(systemName: "xmark.circle")
            statusIconView.tintColor = RGB(255, 72, 49)
            statusIconBackground.backgroundColor = RGB(255, 72, 49, 0.1)
            statusSubtitleLabel.text = "site_time_zone_saved_failed".localizedString
            statusSubtitleLabel.textColor = RGB(255, 72, 49)
            sheetView.snp.updateConstraints { make in
                make.height.equalTo(SCRYFrom(246) + (isIPad ? 0 : kSafeAreaBottomHeight))
            }
        }
        setNeedsLayout()
        layoutIfNeeded()
    }

    private func setupUI() {
        backgroundColor = RGB(0, 0, 0, 0.3)

        sheetView.backgroundColor = .white
        sheetView.layer.cornerRadius = SCRYFrom(20)
        sheetView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        sheetView.layer.masksToBounds = true
        addSubview(sheetView)
        sheetView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(SCRYFrom(190) + (isIPad ? 0 : kSafeAreaBottomHeight))
        }

        let titleLabel = UILabel()
        titleLabel.text = "site_time_zone_sync_status".localizedString
        titleLabel.textColor = RGB(30, 35, 41)
        titleLabel.font = UIFont.systemFont(ofSize: SCRYFrom(16))
        titleLabel.textAlignment = .center
        sheetView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.right.top.equalToSuperview()
            make.height.equalTo(SCRYFrom(56))
        }

        let siteCard = makeSiteCard()
        sheetView.addSubview(siteCard)
        siteCard.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(titleLabel.snp.bottom)
            make.height.equalTo(SCRYFrom(88))
        }

        setupGatewayCard()
        sheetView.addSubview(gatewayCard)
        gatewayCard.snp.makeConstraints { make in
            make.left.right.equalTo(siteCard)
            make.top.equalTo(siteCard.snp.bottom).offset(SCRYFrom(12))
            make.height.equalTo(SCRYFrom(88))
        }

        doneButton.setTitle("done".localizedString, for: .normal)
        doneButton.setTitleColor(RGB(64, 79, 102), for: .normal)
        doneButton.titleLabel?.font = UIFont.systemFont(ofSize: SCRYFrom(16), weight: .light)
        doneButton.addTarget(self, action: #selector(doneButtonDidTap), for: .touchUpInside)
        sheetView.addSubview(doneButton)
        doneButton.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.bottom.equalTo(sheetView.safeAreaLayoutGuide.snp.bottom)
            make.height.equalTo(SCRYFrom(56))
        }

        let actionLine = UIView()
        actionLine.backgroundColor = Line_Color
        sheetView.addSubview(actionLine)
        actionLine.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.bottom.equalTo(doneButton.snp.top)
            make.height.equalTo(0.5)
        }
    }

    private func makeSiteCard() -> UIView {
        let card = UIView()
        card.backgroundColor = RGB(248, 250, 252)
        card.layer.cornerRadius = SCRYFrom(14)

        let sectionLabel = makeSectionLabel(text: "site_sync_section_site".localizedString)
        card.addSubview(sectionLabel)
        sectionLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(SCRYFrom(8))
            make.height.equalTo(SCRYFrom(21))
        }

        statusIconBackground.layer.cornerRadius = SCRYFrom(16)
        card.addSubview(statusIconBackground)
        statusIconBackground.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.equalTo(sectionLabel.snp.bottom).offset(SCRYFrom(4))
            make.size.equalTo(SCRYFrom(32))
        }

        activityIndicator.color = Bar_Color
        statusIconBackground.addSubview(activityIndicator)
        activityIndicator.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }

        statusIconView.contentMode = .scaleAspectFit
        statusIconBackground.addSubview(statusIconView)
        statusIconView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.size.equalTo(SCRYFrom(16))
        }

        let nameLabel = UILabel()
        nameLabel.text = "site_time_zone_row_title".localizedString
        nameLabel.textColor = RGB(27, 20, 37)
        nameLabel.font = UIFont.systemFont(ofSize: SCRYFrom(14), weight: .light)
        card.addSubview(nameLabel)
        nameLabel.snp.makeConstraints { make in
            make.left.equalTo(statusIconBackground.snp.right).offset(SCRXFrom(12))
            make.top.equalTo(statusIconBackground)
            make.right.equalTo(SCRXFrom(-16))
            make.height.equalTo(SCRYFrom(20))
        }

        statusSubtitleLabel.font = UIFont.systemFont(ofSize: SCRYFrom(12))
        card.addSubview(statusSubtitleLabel)
        statusSubtitleLabel.snp.makeConstraints { make in
            make.left.right.equalTo(nameLabel)
            make.top.equalTo(nameLabel.snp.bottom)
            make.height.equalTo(SCRYFrom(16))
        }
        return card
    }

    private func setupGatewayCard() {
        gatewayCard.backgroundColor = RGB(248, 250, 252)
        gatewayCard.layer.cornerRadius = SCRYFrom(14)

        let sectionLabel = makeSectionLabel(text: "site_sync_section_gateways".localizedString)
        gatewayCard.addSubview(sectionLabel)
        sectionLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(SCRYFrom(8))
            make.height.equalTo(SCRYFrom(21))
        }

        let iconBackground = UIView()
        iconBackground.backgroundColor = RGB(245, 158, 11, 0.1)
        iconBackground.layer.cornerRadius = SCRYFrom(16)
        gatewayCard.addSubview(iconBackground)
        iconBackground.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.equalTo(sectionLabel.snp.bottom).offset(SCRYFrom(4))
            make.size.equalTo(SCRYFrom(32))
        }

        let icon = UIImageView(image: UIImage(named: "time-zone-sync-status-gateway"))
        icon.tintColor = RGB(245, 158, 11)
        icon.contentMode = .scaleAspectFit
        iconBackground.addSubview(icon)
        icon.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.size.equalTo(SCRYFrom(18))
        }

        let title = UILabel()
        title.text = "site_no_gateways".localizedString
        title.textColor = RGB(30, 35, 41)
        title.font = UIFont.systemFont(ofSize: SCRYFrom(14), weight: .light)
        gatewayCard.addSubview(title)
        title.snp.makeConstraints { make in
            make.left.equalTo(iconBackground.snp.right).offset(SCRXFrom(12))
            make.top.equalTo(iconBackground)
            make.right.equalTo(SCRXFrom(-16))
            make.height.equalTo(SCRYFrom(20))
        }

        let message = UILabel()
        message.text = "site_no_gateways_sync_needed".localizedString
        message.textColor = RGB(148, 163, 184)
        message.font = UIFont.systemFont(ofSize: SCRYFrom(12))
        message.adjustsFontSizeToFitWidth = true
        message.minimumScaleFactor = 0.8
        gatewayCard.addSubview(message)
        message.snp.makeConstraints { make in
            make.left.right.equalTo(title)
            make.top.equalTo(title.snp.bottom)
            make.height.equalTo(SCRYFrom(16))
        }
    }

    private func makeSectionLabel(text: String) -> UILabel {
        let label = UILabel()
        label.text = text.uppercased()
        label.textColor = RGB(100, 116, 139)
        label.font = UIFont.systemFont(ofSize: SCRYFrom(12))
        return label
    }

    @objc private func doneButtonDidTap() {
        guard state != .saving else { return }
        removeFromSuperview()
    }

    private static var activeWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
    }
}
