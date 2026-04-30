//
//  PJEightKeySwitchPanelView.swift
//  SunSmart
//
//  Created by Plato Jobs.
//

import UIKit

final class PJEightKeySwitchPanelView: UIView {

    enum Mode {
        case preview
        case interactive(action: (PJEightKeySwitchPanelDefinition.ActionKind) -> Void)
    }

    private let containerView: UIView = {
        let view = UIView()
        view.backgroundColor = .white
        view.layer.cornerRadius = 12
        return view
    }()

    private let previewImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.isHidden = true
        return imageView
    }()

    private let leftTopStack = UIStackView()
    private let leftMiddleStack = UIStackView()
    private let leftBottomStack = UIStackView()
    private let rightTopStack = UIStackView()
    private let rightMiddleStack = UIStackView()
    private let rightBottomStack = UIStackView()

    private let centerPanelView: UIView = {
        let view = UIView()
        view.backgroundColor = .white
        view.layer.cornerRadius = 8
        view.layer.borderWidth = 1
        view.layer.borderColor = RGB(220, 227, 236).cgColor
        return view
    }()

    private lazy var topKeyLabels: [UILabel] = [
        makeCenterLabel("1"),
        makeCenterLabel("2")
    ]

    private lazy var middleKeyLabels: [UILabel] = [
        makeCenterLabel("3"),
        makeCenterLabel("4")
    ]

    private lazy var arrowLabel = makeCenterLabel("⌃")
    private lazy var dividerLabel = makeCenterLabel("⌄")
    private lazy var onLabel = makeCenterLabel("ON")
    private lazy var offLabel = makeCenterLabel("OFF")

    private var currentDefinition: PJEightKeySwitchPanelDefinition?
    private var mode: Mode = .preview

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(definition: PJEightKeySwitchPanelDefinition, mode: Mode = .preview) {
        currentDefinition = definition
        self.mode = mode

        let previewImage = UIImage(named: definition.previewImageName)
        previewImageView.image = previewImage
        let shouldShowPreviewImage: Bool
        switch mode {
        case .preview:
            shouldShowPreviewImage = previewImage != nil
        case .interactive:
            shouldShowPreviewImage = false
        }
        previewImageView.isHidden = !shouldShowPreviewImage
        setGeneratedLayoutHidden(shouldShowPreviewImage)

        topKeyLabels[0].text = definition.topLabels[safe: 0]
        topKeyLabels[1].text = definition.topLabels[safe: 1]
        middleKeyLabels[0].text = definition.middleLabels[safe: 0]
        middleKeyLabels[1].text = definition.middleLabels[safe: 1]
        onLabel.text = definition.bottomLabels[safe: 0]
        offLabel.text = definition.bottomLabels[safe: 1]

        apply(items: definition.zoneItems[.leftTop] ?? [], to: leftTopStack)
        apply(items: definition.zoneItems[.rightTop] ?? [], to: rightTopStack)
        apply(items: definition.zoneItems[.leftMiddle] ?? [], to: leftMiddleStack)
        apply(items: definition.zoneItems[.rightMiddle] ?? [], to: rightMiddleStack)
        apply(items: definition.zoneItems[.leftBottom] ?? [], to: leftBottomStack)
        apply(items: definition.zoneItems[.rightBottom] ?? [], to: rightBottomStack)
    }

    func preferredHeight(for width: CGFloat) -> CGFloat {
        if let definition = currentDefinition,
           case .preview = mode,
           let image = UIImage(named: definition.previewImageName),
           image.size.width > 0 {
            return width * image.size.height / image.size.width
        }
        return max(SCRYFrom(320), width * 0.72)
    }

    private func setupUI() {
        backgroundColor = .clear

        addSubview(containerView)
        containerView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        containerView.addSubview(previewImageView)
        previewImageView.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: SCRYFrom(8), left: SCRXFrom(8), bottom: SCRYFrom(8), right: SCRXFrom(8)))
        }

        [leftTopStack, leftMiddleStack, leftBottomStack, rightTopStack, rightMiddleStack, rightBottomStack].forEach {
            $0.axis = .vertical
            $0.spacing = SCRYFrom(12)
            $0.alignment = .fill
            containerView.addSubview($0)
        }

        containerView.addSubview(centerPanelView)
        centerPanelView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.centerY.equalToSuperview()
            make.width.equalTo(SCRXFrom(74))
            make.height.equalTo(SCRYFrom(176))
        }

        leftTopStack.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(18))
            make.top.equalTo(SCRYFrom(24))
            make.right.lessThanOrEqualTo(centerPanelView.snp.left).offset(-SCRXFrom(16))
        }
        rightTopStack.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-18))
            make.top.equalTo(leftTopStack)
            make.left.greaterThanOrEqualTo(centerPanelView.snp.right).offset(SCRXFrom(16))
        }
        leftMiddleStack.snp.makeConstraints { make in
            make.left.equalTo(leftTopStack)
            make.centerY.equalToSuperview()
            make.right.lessThanOrEqualTo(centerPanelView.snp.left).offset(-SCRXFrom(16))
        }
        rightMiddleStack.snp.makeConstraints { make in
            make.right.equalTo(rightTopStack)
            make.centerY.equalTo(leftMiddleStack)
            make.left.greaterThanOrEqualTo(centerPanelView.snp.right).offset(SCRXFrom(16))
        }
        leftBottomStack.snp.makeConstraints { make in
            make.left.equalTo(leftTopStack)
            make.bottom.equalTo(SCRYFrom(-24))
            make.right.lessThanOrEqualTo(centerPanelView.snp.left).offset(-SCRXFrom(16))
        }
        rightBottomStack.snp.makeConstraints { make in
            make.right.equalTo(rightTopStack)
            make.bottom.equalTo(leftBottomStack)
            make.left.greaterThanOrEqualTo(centerPanelView.snp.right).offset(SCRXFrom(16))
        }

        setupCenterPanel()
    }

    private func setGeneratedLayoutHidden(_ hidden: Bool) {
        [leftTopStack, leftMiddleStack, leftBottomStack, rightTopStack, rightMiddleStack, rightBottomStack, centerPanelView].forEach {
            $0.isHidden = hidden
        }
    }

    private func setupCenterPanel() {
        let horizontalLine1 = UIView()
        horizontalLine1.backgroundColor = Line_Color
        let horizontalLine2 = UIView()
        horizontalLine2.backgroundColor = Line_Color
        let horizontalLine3 = UIView()
        horizontalLine3.backgroundColor = Line_Color
        let verticalLine = UIView()
        verticalLine.backgroundColor = Line_Color

        [horizontalLine1, horizontalLine2, horizontalLine3, verticalLine].forEach {
            centerPanelView.addSubview($0)
        }

        verticalLine.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.bottom.equalToSuperview()
            make.width.equalTo(1)
        }
        horizontalLine1.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(SCRYFrom(44))
            make.height.equalTo(1)
        }
        horizontalLine2.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(SCRYFrom(88))
            make.height.equalTo(1)
        }
        horizontalLine3.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(SCRYFrom(132))
            make.height.equalTo(1)
        }

        let labels = topKeyLabels + middleKeyLabels + [arrowLabel, dividerLabel, onLabel, offLabel]
        labels.forEach(centerPanelView.addSubview)

        topKeyLabels[0].snp.makeConstraints { make in
            make.centerX.equalTo(centerPanelView.snp.centerX).offset(-SCRXFrom(18))
            make.centerY.equalTo(SCRYFrom(22))
        }
        topKeyLabels[1].snp.makeConstraints { make in
            make.centerX.equalTo(centerPanelView.snp.centerX).offset(SCRXFrom(18))
            make.centerY.equalTo(topKeyLabels[0])
        }
        middleKeyLabels[0].snp.makeConstraints { make in
            make.centerX.equalTo(topKeyLabels[0])
            make.centerY.equalTo(SCRYFrom(66))
        }
        middleKeyLabels[1].snp.makeConstraints { make in
            make.centerX.equalTo(topKeyLabels[1])
            make.centerY.equalTo(middleKeyLabels[0])
        }
        arrowLabel.snp.makeConstraints { make in
            make.centerX.equalTo(topKeyLabels[0])
            make.centerY.equalTo(SCRYFrom(110))
        }
        dividerLabel.snp.makeConstraints { make in
            make.centerX.equalTo(topKeyLabels[1])
            make.centerY.equalTo(arrowLabel)
        }
        onLabel.snp.makeConstraints { make in
            make.centerX.equalTo(topKeyLabels[0])
            make.centerY.equalTo(SCRYFrom(154))
        }
        offLabel.snp.makeConstraints { make in
            make.centerX.equalTo(topKeyLabels[1])
            make.centerY.equalTo(onLabel)
        }
    }

    private func apply(items: [PJEightKeySwitchPanelDefinition.Item], to stackView: UIStackView) {
        stackView.arrangedSubviews.forEach {
            stackView.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        items.forEach { item in
            stackView.addArrangedSubview(makeActionItemView(item))
        }
    }

    private func makeActionItemView(_ item: PJEightKeySwitchPanelDefinition.Item) -> UIView {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(named: item.style == .shortPress ? "switch_press" : "switch_press_long")
        configuration.title = item.title
        configuration.imagePadding = SCRXFrom(6)
        configuration.contentInsets = .zero
        configuration.baseForegroundColor = SubText_Color
        configuration.titleLineBreakMode = .byWordWrapping
        configuration.imagePlacement = .leading

        let button = UIButton(configuration: configuration, primaryAction: nil)
        button.contentHorizontalAlignment = .left
        button.contentVerticalAlignment = .top
        button.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .light)
        button.titleLabel?.numberOfLines = 0
        button.semanticContentAttribute = .forceLeftToRight
        button.isUserInteractionEnabled = false

        if case .interactive = mode {
            button.isUserInteractionEnabled = true
            button.addAction(UIAction(handler: { [weak self] _ in
                guard let self else { return }
                if case .interactive(let action) = self.mode {
                    action(item.actionKind)
                }
            }), for: .touchUpInside)
        }

        button.snp.makeConstraints { make in
            make.height.greaterThanOrEqualTo(SCRYFrom(28))
        }

        return button
    }

    private func makeCenterLabel(_ text: String) -> UILabel {
        let label = UILabel(text: text, textColor: Title_Color, fontSize: 13, fontWeight: .light)
        label.textAlignment = .center
        return label
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
