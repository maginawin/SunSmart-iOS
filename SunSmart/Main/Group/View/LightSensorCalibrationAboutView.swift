//
//  LightSensorCalibrationAboutView.swift
//  SunSmart
//
//  Created by One on 2026/8/21.
//

import UIKit

final class LightSensorCalibrationAboutView: UIView {

    private let titleLabel = UILabel()
    private let arrowImageView = UIImageView()
    private let dividerView = UIView()
    private let bodyView = UIView()
    private let descriptionLabel = UILabel()
    private let bestForDescriptionLabel = UILabel()
    private let avoidIfDescriptionLabel = UILabel()
    private let headerButton = UIButton(type: .custom)

    private var mode: LightSensorCalibrationMode = .plane
    private var isExpanded = true

    override init(frame: CGRect) {
        super.init(frame: frame)

        setupUI()
        updateContent()
        updateExpansionState()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateMode(_ mode: LightSensorCalibrationMode) {
        self.mode = mode
        updateContent()
    }

    @objc private func headerAction() {
        isExpanded.toggle()
        updateExpansionState()
    }

    private func updateContent() {
        titleLabel.text = mode.aboutTitle
        descriptionLabel.attributedText = attributedBodyText(mode.aboutDescription, color: Title_Color, fontSize: 12, lineHeight: 19.5)
        bestForDescriptionLabel.attributedText = attributedBodyText(mode.bestForDescription, color: SubText_Color, fontSize: 11, lineHeight: 17.875)
        avoidIfDescriptionLabel.attributedText = attributedBodyText(mode.avoidIfDescription, color: SubText_Color, fontSize: 11, lineHeight: 17.875)
        headerButton.accessibilityLabel = mode.aboutTitle
    }

    private func updateExpansionState() {
        bodyView.isHidden = !isExpanded
        dividerView.isHidden = !isExpanded
        arrowImageView.image = UIImage(named: isExpanded ? "arrow_up" : "arrow_down")
        headerButton.accessibilityValue = isExpanded ? "expanded".localizedString : "collapsed".localizedString
    }

    private func attributedBodyText(_ text: String, color: UIColor, fontSize: CGFloat, lineHeight: CGFloat) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.minimumLineHeight = SCRYFrom(lineHeight)
        paragraphStyle.maximumLineHeight = SCRYFrom(lineHeight)
        return NSAttributedString(string: text, attributes: [
            .font: UIFont.systemFont(ofSize: SCRYFrom(fontSize), weight: .regular),
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle
        ])
    }

    private func setupUI() {
        backgroundColor = RGB(240, 244, 255)
        layer.cornerRadius = SCRYFrom(16)
        clipsToBounds = true

        let rootStackView = UIStackView()
        rootStackView.axis = .vertical
        rootStackView.spacing = 0
        addSubview(rootStackView)
        rootStackView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        let headerView = UIView()
        rootStackView.addArrangedSubview(headerView)

        arrowImageView.contentMode = .center
        headerView.addSubview(arrowImageView)
        arrowImageView.snp.makeConstraints { make in
            make.top.equalTo(SCRYFrom(12))
            make.right.equalTo(SCRXFrom(-8))
            make.bottom.equalTo(SCRYFrom(-12))
            make.width.height.equalTo(SCRYFrom(30))
        }

        titleLabel.textColor = RGB(74, 85, 120)
        titleLabel.font = UIFont.systemFont(ofSize: SCRYFrom(14), weight: .regular)
        headerView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.centerY.equalToSuperview()
            make.right.lessThanOrEqualTo(arrowImageView.snp.left).offset(SCRXFrom(-8))
        }

        headerButton.addTarget(self, action: #selector(headerAction), for: .touchUpInside)
        headerButton.accessibilityTraits = .button
        headerView.addSubview(headerButton)
        headerButton.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        dividerView.backgroundColor = RGB(221, 227, 245)
        rootStackView.addArrangedSubview(dividerView)
        dividerView.snp.makeConstraints { make in
            make.height.equalTo(1.0 / UIScreen.main.scale).priority(999)
        }

        rootStackView.addArrangedSubview(bodyView)

        descriptionLabel.textColor = Title_Color
        descriptionLabel.numberOfLines = 0

        let bestForView = makeDescriptionSection(
            title: "calibration_about_best_for".localizedString,
            titleColor: RGB(0, 153, 102),
            descriptionLabel: bestForDescriptionLabel
        )
        let avoidIfView = makeDescriptionSection(
            title: "calibration_about_avoid_if".localizedString,
            titleColor: RGB(225, 113, 0),
            descriptionLabel: avoidIfDescriptionLabel
        )

        let bodyStackView = UIStackView(arrangedSubviews: [descriptionLabel, bestForView, avoidIfView])
        bodyStackView.axis = .vertical
        bodyStackView.spacing = 0
        bodyStackView.setCustomSpacing(SCRYFrom(8), after: descriptionLabel)
        bodyStackView.setCustomSpacing(SCRYFrom(8), after: bestForView)
        bodyView.addSubview(bodyStackView)
        bodyStackView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(SCRYFrom(12))
            make.bottom.equalTo(SCRYFrom(-14)).priority(999)
        }
    }

    private func makeDescriptionSection(title: String, titleColor: UIColor, descriptionLabel: UILabel) -> UIView {
        let titleLabel = UILabel()
        titleLabel.text = "•  \(title)"
        titleLabel.textColor = titleColor
        titleLabel.font = UIFont.systemFont(ofSize: SCRYFrom(11), weight: .semibold)

        descriptionLabel.textColor = SubText_Color
        descriptionLabel.numberOfLines = 0

        let stackView = UIStackView(arrangedSubviews: [titleLabel, descriptionLabel])
        stackView.axis = .vertical
        stackView.spacing = SCRYFrom(6)
        return stackView
    }
}
