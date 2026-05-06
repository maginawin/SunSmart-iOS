//
//  PJEightKeySwitchActivationAlertView.swift
//  SunSmart
//
//  Created by Plato Jobs.
//

import UIKit
import SnapKit

final class PJEightKeySwitchWaitingSpinnerView: UIView {

    private let trackLayer = CAShapeLayer()
    private let progressLayer = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        layer.addSublayer(trackLayer)
        layer.addSublayer(progressLayer)
        trackLayer.fillColor = UIColor.clear.cgColor
        trackLayer.strokeColor = RGB(223, 227, 245).cgColor
        trackLayer.lineWidth = 1.2
        progressLayer.fillColor = UIColor.clear.cgColor
        progressLayer.strokeColor = RGB(165, 172, 228).cgColor
        progressLayer.lineWidth = 1.8
        progressLayer.lineCap = .round
        progressLayer.strokeStart = 0
        progressLayer.strokeEnd = 0.72
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let radius = min(bounds.width, bounds.height) * 0.5 - 1
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let path = UIBezierPath(arcCenter: center, radius: radius, startAngle: -.pi / 2, endAngle: .pi * 1.5, clockwise: true)
        trackLayer.frame = bounds
        trackLayer.path = path.cgPath
        progressLayer.frame = bounds
        progressLayer.path = path.cgPath
    }

    func startAnimating() {
        guard progressLayer.animation(forKey: "rotation") == nil else { return }
        let animation = CABasicAnimation(keyPath: "transform.rotation.z")
        animation.fromValue = 0
        animation.toValue = CGFloat.pi * 2
        animation.duration = 0.9
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        progressLayer.add(animation, forKey: "rotation")
    }

    func stopAnimating() {
        progressLayer.removeAnimation(forKey: "rotation")
    }
}

final class PJEightKeySwitchActivationAlertView: UIView {

    private enum Constants {
        static let fullContainerHeight = SCRYFrom(356)
        static let bottomSafeAreaCompensation = SCRYFrom(34)
        static let contentHeight = SCRYFrom(266)
        static let buttonHeight = SCRYFrom(53)
        static let statusHeight = SCRYFrom(29)
        static let titleTop = SCRYFrom(18)
        static let titleHorizontalInset = SCRXFrom(24)
        static let messageTop = SCRYFrom(24)
        static let messageHorizontalInset = SCRXFrom(38)
        static let statusTop = SCRYFrom(56)
        static let statusHorizontalInset = SCRXFrom(38)
    }

    private var containerHeightConstraint: Constraint?

    let backgroundView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.52)
        return view
    }()

    let containerView: UIView = {
        let view = UIView()
        view.backgroundColor = .white
        view.layer.cornerRadius = 16
        view.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        view.clipsToBounds = true
        return view
    }()

    private let contentSectionView: UIView = {
        let view = UIView()
        view.backgroundColor = RGB(251, 251, 254)
        return view
    }()

    private let buttonSectionView = UIView()

    let titleLabel: UILabel = {
        let label = UILabel(text: "neightkeyswitches_save_after_activation".localizedString, textColor: RGB(80, 87, 126), fontSize: 17, fontWeight: .medium, fit: false)
        label.textAlignment = .center
        return label
    }()

    let messageLabel: UILabel = {
        let label = UILabel()
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    let statusContainerView: UIView = {
        let view = UIView()
        view.layer.cornerRadius = 4
        return view
    }()

    let waitingSpinnerView = PJEightKeySwitchWaitingSpinnerView()

    let statusIconView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.isHidden = true
        return view
    }()

    let statusLabel: UILabel = {
        let label = UILabel(text: nil, textColor: RGB(124, 133, 164), fontSize: 14, fontWeight: .light, fit: false)
        label.textAlignment = .left
        return label
    }()

    let buttonTopLineView: UIView = {
        let view = UIView()
        view.backgroundColor = Line_Color
        return view
    }()

    let buttonMiddleLineView: UIView = {
        let view = UIView()
        view.backgroundColor = Line_Color
        view.isHidden = true
        return view
    }()

    let cancelButton = UIButton(title: "cancel".localizedString.uppercased(), titleSize: 16, titleWeight: .light, titleColor: Title_Done_Color, target: nil, action: nil)
    let retryButton = UIButton(title: "retry".localizedString.uppercased(), titleSize: 16, titleWeight: .light, titleColor: Title_Done_Color, target: nil, action: nil)

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        updateContainerHeight()
    }

    func updateMessage(_ message: String) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineSpacing = SCRYFrom(2)
        paragraphStyle.minimumLineHeight = SCRYFrom(17)
        paragraphStyle.maximumLineHeight = SCRYFrom(17)
        messageLabel.attributedText = NSAttributedString(
            string: message,
            attributes: [
                .foregroundColor: RGB(189, 194, 213),
                .font: UIFont.systemFont(ofSize: 14, weight: .light),
                .paragraphStyle: paragraphStyle
            ]
        )
    }

    func applyWaitingLayout() {
        buttonMiddleLineView.isHidden = true
        retryButton.isHidden = true
        cancelButton.snp.remakeConstraints { make in
            make.left.right.top.equalToSuperview()
            make.height.equalTo(Constants.buttonHeight)
        }
    }

    func applyDualButtonLayout() {
        buttonMiddleLineView.isHidden = false
        retryButton.isHidden = false
        cancelButton.snp.remakeConstraints { make in
            make.left.top.equalToSuperview()
            make.right.equalTo(buttonMiddleLineView.snp.left)
            make.height.equalTo(Constants.buttonHeight)
        }
    }

    private func setupUI() {
        backgroundColor = .clear

        addSubview(backgroundView)
        backgroundView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        addSubview(containerView)
        containerView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            containerHeightConstraint = make.height.equalTo(Constants.fullContainerHeight).constraint
        }

        containerView.addSubview(contentSectionView)
        contentSectionView.snp.makeConstraints { make in
            make.top.left.right.equalToSuperview()
            make.height.equalTo(Constants.contentHeight)
        }

        containerView.addSubview(buttonSectionView)
        buttonSectionView.snp.makeConstraints { make in
            make.top.equalTo(contentSectionView.snp.bottom)
            make.left.right.equalToSuperview()
            make.bottom.equalTo(containerView.safeAreaLayoutGuide.snp.bottom)
        }

        contentSectionView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.top.equalTo(Constants.titleTop)
            make.left.equalTo(Constants.titleHorizontalInset)
            make.right.equalTo(-Constants.titleHorizontalInset)
        }

        contentSectionView.addSubview(messageLabel)
        messageLabel.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(Constants.messageTop)
            make.left.equalTo(Constants.messageHorizontalInset)
            make.right.equalTo(-Constants.messageHorizontalInset)
        }

        contentSectionView.addSubview(statusContainerView)
        statusContainerView.snp.makeConstraints { make in
            make.top.equalTo(messageLabel.snp.bottom).offset(Constants.statusTop)
            make.centerX.equalToSuperview()
            make.height.equalTo(Constants.statusHeight)
        }

        statusContainerView.addSubview(waitingSpinnerView)
        waitingSpinnerView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(13))
            make.centerY.equalToSuperview()
            make.width.height.equalTo(14)
        }

        statusContainerView.addSubview(statusIconView)
        statusIconView.snp.makeConstraints { make in
            make.center.equalTo(waitingSpinnerView)
            make.width.height.equalTo(16)
        }

        statusContainerView.addSubview(statusLabel)
        statusLabel.snp.makeConstraints { make in
            make.left.equalTo(waitingSpinnerView.snp.right).offset(SCRXFrom(11))
            make.right.equalTo(-SCRXFrom(14))
            make.centerY.equalToSuperview()
        }

        buttonSectionView.addSubview(buttonTopLineView)
        buttonTopLineView.snp.makeConstraints { make in
            make.top.left.right.equalToSuperview()
            make.height.equalTo(1)
        }

        buttonSectionView.addSubview(cancelButton)
        cancelButton.snp.makeConstraints { make in
            make.left.right.top.equalToSuperview()
            make.height.equalTo(Constants.buttonHeight)
        }

        buttonSectionView.addSubview(buttonMiddleLineView)
        buttonMiddleLineView.snp.makeConstraints { make in
            make.top.equalTo(buttonTopLineView.snp.bottom)
            make.bottom.equalToSuperview()
            make.width.equalTo(1)
            make.centerX.equalToSuperview()
        }

        buttonSectionView.addSubview(retryButton)
        retryButton.snp.makeConstraints { make in
            make.top.equalTo(buttonTopLineView.snp.bottom)
            make.right.equalToSuperview()
            make.bottom.equalToSuperview()
            make.left.equalTo(buttonMiddleLineView.snp.right)
            make.height.equalTo(cancelButton)
        }

        retryButton.isHidden = true
        updateContainerHeight()
    }

    private func updateContainerHeight() {
        let targetHeight = safeAreaInsets.bottom > 0
            ? Constants.fullContainerHeight
            : Constants.fullContainerHeight - Constants.bottomSafeAreaCompensation
        containerHeightConstraint?.update(offset: targetHeight)
    }
}
