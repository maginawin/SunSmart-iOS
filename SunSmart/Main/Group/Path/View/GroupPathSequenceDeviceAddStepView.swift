//
//  GroupPathSequenceDeviceAddStepView.swift
//  SunSmart
//
//  Created by yuankehong on 2025/5/21.
//

import UIKit

class GroupPathSequenceDeviceAddStepView: UIView {

    enum LayoutStyle {
        case legacy
        case equalColumns
    }

    private enum LayoutMetrics {
        static let equalColumnSpacing: CGFloat = 16
        static let equalColumnHorizontalInset: CGFloat = 16
        static let equalColumnTopInset: CGFloat = 40
        static let equalColumnTitleSpacing: CGFloat = 8
        static let cornerRadius: CGFloat = 10
    }

    struct StepItem {
        let imageName: String
        let title: String
        let textColor: UIColor
    }
    
    let stackView = UIStackView()
    
    private var stepViews: [StepFunctionView] = []
    private var lineViews: [UIView] = []
    private let layoutStyle: LayoutStyle
    
    var lineWidth: CGFloat
    
    var steps: [StepItem] = [] {
        didSet {
            buildSteps()
        }
    }

    init(
        frame: CGRect = .zero,
        steps: [StepItem],
        layoutStyle: LayoutStyle = .legacy
    ) {
        self.layoutStyle = layoutStyle
        lineWidth = layoutStyle == .equalColumns ? 40 : SCRXFrom(40)
        super.init(frame: frame)
        
        self.steps = steps
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        switch layoutStyle {
        case .legacy:
            backgroundColor = .white
            layer.cornerRadius = SCRYFrom(LayoutMetrics.cornerRadius)
        case .equalColumns:
            backgroundColor = .clear
            layer.cornerRadius = 0
        }

        stackView.alignment = .top
        configureStackView()
        addSubview(stackView)
        constrainStackView()

        buildSteps()
    }

    private func configureStackView() {
        switch layoutStyle {
        case .legacy:
            stackView.distribution = .fill
            stackView.spacing = isIPad ? SCRXFrom(30) : SCRXFrom(20)
        case .equalColumns:
            stackView.distribution = .fillEqually
            stackView.spacing = LayoutMetrics.equalColumnSpacing
        }
    }

    private func constrainStackView() {
        stackView.snp.makeConstraints { make in
            switch layoutStyle {
            case .legacy:
                make.centerY.equalToSuperview()
                make.top.greaterThanOrEqualToSuperview()
                make.bottom.lessThanOrEqualToSuperview()
                make.centerX.equalToSuperview()
                make.left.greaterThanOrEqualTo(SCRXFrom(10))
                make.right.lessThanOrEqualTo(SCRXFrom(-10))
                make.width.lessThanOrEqualTo(isIPad ? SCRXFrom(600) : SCRXFrom(320))
            case .equalColumns:
                make.top.equalToSuperview().offset(LayoutMetrics.equalColumnTopInset)
                make.bottom.lessThanOrEqualToSuperview()
                make.left.right.equalToSuperview().inset(LayoutMetrics.equalColumnHorizontalInset)
            }
        }
    }

    private func buildSteps() {
        
        stepViews.forEach { $0.removeFromSuperview() }
        lineViews.forEach { $0.removeFromSuperview() }
        
        stepViews.removeAll()
        lineViews.removeAll()
        let titleSpacing = layoutStyle == .equalColumns ? LayoutMetrics.equalColumnTitleSpacing : SCRYFrom(8)
        
        for step in steps {
            let view = StepFunctionView(
                imageName: step.imageName,
                title: step.title,
                titleColor: step.textColor,
                constrainsWidth: layoutStyle == .legacy,
                titleSpacing: titleSpacing
            )
            stackView.addArrangedSubview(view)
            stepViews.append(view)
        }
        
//        layoutIfNeeded()
        addLines()
    }

    private func addLines() {

        guard stepViews.count > 1 else { return }

        for i in 0..<(stepViews.count - 1) {

            let line = UIView()
            line.backgroundColor = AssistText_Color
            addSubview(line)
            lineViews.append(line)

            let left = stepViews[i]

            line.snp.makeConstraints { make in
                make.centerY.equalTo(left.imageView.snp.centerY)
                make.width.equalTo(lineWidth)
                if layoutStyle == .equalColumns {
                    make.centerX.equalTo(left.snp.right).offset(LayoutMetrics.equalColumnSpacing / 2)
                } else {
                    make.centerX.equalTo(left.snp.right)
                }
                make.height.equalTo(1)
            }
        }
    }

    func preferredHeight(fittingWidth width: CGFloat) -> CGFloat {
        layoutIfNeeded()
        let targetWidth = max(width, 0)
        let size = systemLayoutSizeFitting(
            CGSize(width: targetWidth, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        return ceil(size.height)
    }
}

class StepFunctionView: UIView {

    let imageView = UIImageView()
    private let titleLabel = UILabel()
    private let minWidth: CGFloat = SCRXFrom(68)
    private let maxWidth: CGFloat = isIPad ? SCRXFrom(150) : SCRXFrom(107)

    init(
        imageName: String,
        title: String,
        titleColor: UIColor,
        constrainsWidth: Bool = true,
        titleSpacing: CGFloat
    ) {
        super.init(frame: .zero)

        if constrainsWidth {
            snp.makeConstraints { make in
                make.width.greaterThanOrEqualTo(minWidth)
                make.width.lessThanOrEqualTo(maxWidth).priority(.required)
            }
        }
        
        imageView.image = UIImage(named: imageName)
        addSubview(imageView)
        imageView.snp.makeConstraints { make in
            make.centerX.top.equalToSuperview()
            make.width.height.equalTo(20)
        }

        titleLabel.text = title
        titleLabel.textColor = titleColor
        titleLabel.font = .systemFont(ofSize: 12, weight: .light)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0

        addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.top.equalTo(imageView.snp.bottom).offset(titleSpacing)
            make.leading.trailing.bottom.equalToSuperview()
        }
    }

//    override func layoutSubviews() {
//        super.layoutSubviews()
//        titleLabel.preferredMaxLayoutWidth = bounds.width
//    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
