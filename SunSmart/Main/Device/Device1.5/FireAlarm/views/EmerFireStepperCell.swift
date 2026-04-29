//
//  EmerFireStepperCell.swift
//  SunSmart
//
//  Created by Plato Jobs on 2026/4/20.
//

import UIKit
import SnapKit

final class EmerFireStepperCell: UITableViewCell {

    private enum Layout {
        static let horizontalInset = SCRXFrom(12)
        static let verticalInset = SCRYFrom(4)
        static let cardRadius = SCRYFrom(10)
        static let buttonSize = SCRXFrom(24)
        static let thumbSize = SCRXFrom(24)
        static let trackHeight = SCRYFrom(2)
    }

    var valueDidChange: ((Int) -> Void)?

    private var currentValue = 0
    private var currentRange: ClosedRange<Int> = 0...100
    private var currentSuffix = ""
    private var cardPosition: EmerFireCardPosition = .single
    private var topConstraint: Constraint?
    private var bottomConstraint: Constraint?

    private lazy var cardView: UIView = {
        let view = UIView()
        view.backgroundColor = .white
        view.layer.cornerRadius = Layout.cardRadius
        view.layer.masksToBounds = true
        return view
    }()

    private lazy var separatorView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor(red: 228 / 255.0, green: 229 / 255.0, blue: 235 / 255.0, alpha: 1)
        view.isHidden = true
        return view
    }()

    private lazy var headerContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        return view
    }()

    private lazy var controlsContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        return view
    }()

    private lazy var titleLabel: UILabel = {
        let label = UILabel(text: nil, textColor: Title_Color, fontSize: 14, fontWeight: .light)
        label.numberOfLines = 0
        return label
    }()

    private lazy var valueLabel: UILabel = {
        let label = UILabel(text: nil, textColor: AssistText_Color, fontSize: 14, fontWeight: .light)
        label.textAlignment = .right
        return label
    }()

    private lazy var minusButton: UIButton = {
        let button = UIButton(normalImageName: "scene_data_value_minus", target: self, action: #selector(handleMinus))
       // button.setTitle("-", for: .normal)
       // button.setTitleColor(Purple_Color, for: .normal)
       // button.titleLabel?.font = FONTS(15)
       // button.layer.cornerRadius = Layout.buttonSize / 2
       // button.layer.borderWidth = 1
      // button.layer.borderColor = Purple_Color.cgColor
        return button
    }()

    private lazy var plusButton: UIButton = {
        let button = UIButton(normalImageName: "scene_data_value_add", target: self, action: #selector(handlePlus))
//        button.setTitle("+", for: .normal)
//        button.setTitleColor(Purple_Color, for: .normal)
//        button.titleLabel?.font = FONTS(15)
//        button.layer.cornerRadius = Layout.buttonSize / 2
//        button.layer.borderWidth = 1
//        button.layer.borderColor = Purple_Color.cgColor
        return button
    }()

    private lazy var sliderContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = true
        return view
    }()

    private lazy var trackView: UIView = {
        let view = UIView()
        view.backgroundColor = Line_Color1
        view.layer.cornerRadius = Layout.trackHeight / 2
        view.isUserInteractionEnabled = true
        return view
    }()

    private lazy var progressView: UIView = {
        let view = UIView()
        view.backgroundColor = RGB(233, 195, 98)
        view.layer.cornerRadius = Layout.trackHeight / 2
        return view
    }()

    private lazy var thumbView: UIImageView = {
        let imageView = UIImageView()
        imageView.isUserInteractionEnabled = true
        imageView.contentMode = .scaleAspectFit
        imageView.image = UIImage(named: "Knob")?.withRenderingMode(.alwaysOriginal)
        imageView.backgroundColor = imageView.image == nil ? RGB(233, 195, 98) : .clear
        //imageView.layer.cornerRadius = Layout.thumbSize / 2
        return imageView
    }()

    private var progressWidthConstraint: Constraint?
    private var thumbLeadingConstraint: Constraint?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        valueDidChange = nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
     //   thumbView.layer.cornerRadius = Layout.thumbSize / 2
     //   thumbView.layer.masksToBounds = true
        updateTrackProgress()
    }

    func configure(title: String, value: Int, range: ClosedRange<Int>, suffix: String, cardPosition: EmerFireCardPosition = .single) {
        titleLabel.text = title
        currentValue = value
        currentRange = range
        currentSuffix = suffix
        valueLabel.text = "\(value)\(suffix)"
        self.cardPosition = cardPosition
        topConstraint?.update(offset: cardPosition.topInset)
        bottomConstraint?.update(offset: -cardPosition.bottomInset)
        applyCardStyle()
        updateTrackProgress()
    }

    @objc private func handleMinus() {
        guard currentValue > currentRange.lowerBound else { return }
        applyValue(currentValue - 1, notify: true)
    }

    @objc private func handlePlus() {
        guard currentValue < currentRange.upperBound else { return }
        applyValue(currentValue + 1, notify: true)
    }

    @objc private func handleThumbPan(_ gesture: UIPanGestureRecognizer) {
        updateValue(with: gesture.location(in: sliderContainerView).x)
    }

    @objc private func handleTrackTap(_ gesture: UITapGestureRecognizer) {
        updateValue(with: gesture.location(in: sliderContainerView).x)
    }

    private func updateTrackProgress() {
        let total = max(currentRange.upperBound - currentRange.lowerBound, 1)
        let progress = CGFloat(currentValue - currentRange.lowerBound) / CGFloat(total)
        let width = max(sliderContainerView.bounds.width * progress, 0)
        progressWidthConstraint?.update(offset: width)
        let thumbOffset = min(
            max(sliderContainerView.bounds.width * progress - Layout.thumbSize / 2, 0),
            max(sliderContainerView.bounds.width - Layout.thumbSize, 0)
        )
        thumbLeadingConstraint?.update(offset: thumbOffset)
        layoutIfNeeded()
    }

    private func setupUI() {
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        contentView.addSubview(cardView)
        cardView.snp.makeConstraints { make in
            topConstraint = make.top.equalToSuperview().offset(Layout.verticalInset).constraint
            make.left.right.equalToSuperview().inset(Layout.horizontalInset)
            bottomConstraint = make.bottom.equalToSuperview().offset(-Layout.verticalInset).constraint
        }

        cardView.addSubview(headerContainerView)
        headerContainerView.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(SCRYFrom(12))
            make.left.right.equalToSuperview()
        }

        headerContainerView.addSubview(titleLabel)
        headerContainerView.addSubview(valueLabel)

        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.equalToSuperview()
            make.bottom.equalToSuperview()
            make.right.lessThanOrEqualTo(valueLabel.snp.left).offset(-SCRXFrom(12))
        }

        valueLabel.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.centerY.equalTo(titleLabel)
        }

        cardView.addSubview(controlsContainerView)
        controlsContainerView.snp.makeConstraints { make in
            make.top.equalTo(headerContainerView.snp.bottom).offset(SCRYFrom(12))
            make.left.right.equalToSuperview()
            make.bottom.equalToSuperview().offset(-SCRYFrom(12))
            make.height.greaterThanOrEqualTo(max(Layout.buttonSize, Layout.thumbSize))
        }

        controlsContainerView.addSubview(minusButton)
        minusButton.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.greaterThanOrEqualToSuperview()
            make.width.height.equalTo(Layout.buttonSize)
            make.bottom.equalToSuperview()
        }

        controlsContainerView.addSubview(plusButton)
        plusButton.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.centerY.width.height.equalTo(minusButton)
        }

        controlsContainerView.addSubview(sliderContainerView)
        sliderContainerView.snp.makeConstraints { make in
            make.left.equalTo(minusButton.snp.right).offset(SCRXFrom(8))
            make.right.equalTo(plusButton.snp.left).offset(-SCRXFrom(8))
            make.centerY.equalTo(minusButton)
            make.height.equalTo(max(Layout.buttonSize, Layout.thumbSize) + SCRYFrom(12))
        }

        sliderContainerView.addSubview(trackView)
        trackView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.centerY.equalToSuperview()
            make.height.equalTo(Layout.trackHeight)
        }

        trackView.addSubview(progressView)
        progressView.snp.makeConstraints { make in
            make.left.top.bottom.equalToSuperview()
            progressWidthConstraint = make.width.equalTo(0).constraint
        }

        sliderContainerView.addSubview(thumbView)
        thumbView.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            thumbLeadingConstraint = make.left.equalToSuperview().constraint
            make.width.height.equalTo(Layout.thumbSize)
        }
        sliderContainerView.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(handleThumbPan(_:))))
        sliderContainerView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTrackTap(_:))))

        cardView.addSubview(separatorView)
        separatorView.snp.makeConstraints { make in
            make.left.right.equalToSuperview().inset(SCRXFrom(16))
            make.bottom.equalToSuperview()
            make.height.equalTo(0.5)
        }
    }

    private func applyCardStyle() {
        cardView.layer.cornerRadius = Layout.cardRadius
        cardView.layer.maskedCorners = cardPosition.maskedCorners
        separatorView.isHidden = true
    }

    private func updateValue(with locationX: CGFloat) {
        let clampedX = min(max(locationX, 0), sliderContainerView.bounds.width)
        let ratio = sliderContainerView.bounds.width > 0 ? clampedX / sliderContainerView.bounds.width : 0
        let total = max(currentRange.upperBound - currentRange.lowerBound, 1)
        let newValue = currentRange.lowerBound + Int(round(ratio * CGFloat(total)))
        let clampedValue = min(max(newValue, currentRange.lowerBound), currentRange.upperBound)
        applyValue(clampedValue, notify: true)
    }

    private func applyValue(_ value: Int, notify: Bool) {
        let clampedValue = min(max(value, currentRange.lowerBound), currentRange.upperBound)
        guard clampedValue != currentValue else { return }
        currentValue = clampedValue
        valueLabel.text = "\(clampedValue)\(currentSuffix)"
        updateTrackProgress()
        if notify {
            valueDidChange?(clampedValue)
        }
    }
}
