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
        static let horizontalInset = SCRXFrom(16)
        static let verticalInset = SCRXFrom(8)
        static let cardRadius = SCRYFrom(10)
        static let buttonSize = SCRXFrom(24)
        static let thumbSize = SCRXFrom(24)
        static let trackHeight = SCRYFrom(2)
        static let cardHeight = SCRYFrom(140)
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

    private lazy var fieldTitleLabel: UILabel = {
        let label = UILabel(text: nil, textColor: AssistText_Color, fontSize: 14, fontWeight: .light)
        label.numberOfLines = 1
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
    private var thumbCenterXConstraint: Constraint?

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

    func configure(title: String, fieldTitle: String? = nil, value: Int, range: ClosedRange<Int>, suffix: String, cardPosition: EmerFireCardPosition = .single) {
        titleLabel.text = title
        fieldTitleLabel.text = fieldTitle ?? " "
        currentValue = value
        currentRange = range
        currentSuffix = suffix
        valueLabel.text = "\(value)\(suffix)"
        self.cardPosition = cardPosition
        topConstraint?.update(offset: cardPosition.topInset)
        bottomConstraint?.update(offset: -cardPosition.bottomInset)
        applyCardStyle()
        setNeedsLayout()
        layoutIfNeeded()
        updateTrackProgress()
        DispatchQueue.main.async { [weak self] in
            self?.updateTrackProgress()
        }
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
        let trackWidth = trackView.bounds.width
        guard trackWidth > 0 else { return }
        let width = max(trackWidth * progress, 0)
        progressWidthConstraint?.update(offset: width)
        let thumbCenterOffset = trackWidth * progress
        thumbCenterXConstraint?.update(offset: thumbCenterOffset)
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
            make.height.greaterThanOrEqualTo(Layout.cardHeight)
        }

        cardView.addSubview(headerContainerView)
        headerContainerView.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(SCRYFrom(16))
            make.left.right.equalToSuperview()
        }

        headerContainerView.addSubview(titleLabel)

        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.equalToSuperview()
            make.bottom.equalToSuperview()
            make.right.equalTo(SCRXFrom(-16))
        }

        cardView.addSubview(fieldTitleLabel)
        cardView.addSubview(valueLabel)
        fieldTitleLabel.snp.makeConstraints { make in
            make.left.equalToSuperview().offset(SCRXFrom(16))
            make.right.lessThanOrEqualTo(valueLabel.snp.left).offset(-SCRXFrom(12))
            make.top.equalTo(headerContainerView.snp.bottom).offset(SCRYFrom(24))
        }

        valueLabel.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.centerY.equalTo(fieldTitleLabel)
        }

        cardView.addSubview(controlsContainerView)
        controlsContainerView.snp.makeConstraints { make in
            make.top.greaterThanOrEqualTo(headerContainerView.snp.bottom).offset(SCRYFrom(32))
            make.top.greaterThanOrEqualTo(fieldTitleLabel.snp.bottom).offset(SCRYFrom(12))
            make.left.right.equalToSuperview()
            make.bottom.equalToSuperview().offset(-SCRYFrom(16))
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
            make.left.right.equalToSuperview().inset(Layout.thumbSize / 2)
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
            thumbCenterXConstraint = make.centerX.equalTo(trackView.snp.left).constraint
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
        let minX = trackView.frame.minX
        let maxX = trackView.frame.maxX
        let clampedX = min(max(locationX, minX), maxX)
        let ratio = trackView.bounds.width > 0 ? (clampedX - minX) / trackView.bounds.width : 0
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

final class EmerFireDualStepperCell: UITableViewCell {

    var valueDidChange: ((LinkedEmerFireEditRow, Int) -> Void)?

    private var firstRow: LinkedEmerFireEditRow = .restoreResuming
    private var secondRow: LinkedEmerFireEditRow = .restoreSendCount
    private var cardPosition: EmerFireCardPosition = .single
    private var topConstraint: Constraint?
    private var bottomConstraint: Constraint?

    private enum Layout {
        static let horizontalInset = SCRXFrom(16)
        static let verticalInset = SCRXFrom(8)
        static let cardRadius = SCRYFrom(10)
        static let stepperGroupHeight = SCRYFrom(108)
        static let cardHeight = SCRYFrom(280)
    }

    private lazy var cardView: UIView = {
        let view = UIView()
        view.backgroundColor = .white
        view.layer.cornerRadius = Layout.cardRadius
        view.layer.masksToBounds = true
        return view
    }()

    private lazy var firstStepperView = EmerFireStepperRowView()
    private lazy var secondStepperView = EmerFireStepperRowView()

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
        firstStepperView.valueDidChange = nil
        secondStepperView.valueDidChange = nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        applyCardStyle()
    }

    func configure(
        firstRow: LinkedEmerFireEditRow,
        firstConfiguration: LinkedEmerFireStepperConfiguration,
        secondRow: LinkedEmerFireEditRow,
        secondConfiguration: LinkedEmerFireStepperConfiguration,
        cardPosition: EmerFireCardPosition = .single
    ) {
        self.firstRow = firstRow
        self.secondRow = secondRow
        self.cardPosition = cardPosition
        topConstraint?.update(offset: cardPosition.topInset)
        bottomConstraint?.update(offset: -cardPosition.bottomInset)

        firstStepperView.configure(firstConfiguration)
        secondStepperView.configure(secondConfiguration)
        firstStepperView.valueDidChange = { [weak self] value in
            guard let self else { return }
            self.valueDidChange?(self.firstRow, value)
        }
        secondStepperView.valueDidChange = { [weak self] value in
            guard let self else { return }
            self.valueDidChange?(self.secondRow, value)
        }
        applyCardStyle()
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
            make.height.greaterThanOrEqualTo(Layout.cardHeight)
        }

        cardView.addSubview(firstStepperView)
        cardView.addSubview(secondStepperView)

        firstStepperView.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(SCRYFrom(16))
            make.left.right.equalToSuperview()
            make.height.equalTo(Layout.stepperGroupHeight)
        }

        secondStepperView.snp.makeConstraints { make in
            make.top.equalTo(firstStepperView.snp.bottom).offset(SCRYFrom(32))
            make.left.right.equalToSuperview()
            make.height.equalTo(Layout.stepperGroupHeight)
            make.bottom.equalToSuperview().offset(-SCRYFrom(16))
        }
    }

    private func applyCardStyle() {
        cardView.layer.cornerRadius = Layout.cardRadius
        cardView.layer.maskedCorners = cardPosition.maskedCorners
    }
}

private final class EmerFireStepperRowView: UIView {

    var valueDidChange: ((Int) -> Void)?

    private var currentValue = 0
    private var currentRange: ClosedRange<Int> = 0...100
    private var currentSuffix = ""
    private var progressWidthConstraint: Constraint?
    private var thumbCenterXConstraint: Constraint?

    private enum Layout {
        static let buttonSize = SCRXFrom(24)
        static let thumbSize = SCRXFrom(24)
        static let trackHeight = SCRYFrom(2)
    }

    private lazy var titleLabel: UILabel = {
        let label = UILabel(text: nil, textColor: Title_Color, fontSize: 14, fontWeight: .light)
        label.numberOfLines = 0
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        return label
    }()

    private lazy var fieldTitleLabel: UILabel = {
        let label = UILabel(text: nil, textColor: AssistText_Color, fontSize: 14, fontWeight: .light)
        label.numberOfLines = 1
        return label
    }()

    private lazy var valueLabel: UILabel = {
        let label = UILabel(text: nil, textColor: AssistText_Color, fontSize: 14, fontWeight: .light)
        label.textAlignment = .right
        return label
    }()

    private lazy var controlsContainerView: UIView = {
        UIView()
    }()

    private lazy var minusButton: UIButton = {
        UIButton(normalImageName: "scene_data_value_minus", target: self, action: #selector(handleMinus))
    }()

    private lazy var plusButton: UIButton = {
        UIButton(normalImageName: "scene_data_value_add", target: self, action: #selector(handlePlus))
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
        return imageView
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateTrackProgress()
    }

    func configure(_ configuration: LinkedEmerFireStepperConfiguration) {
        titleLabel.text = configuration.title
        fieldTitleLabel.text = configuration.fieldTitle ?? " "
        currentValue = configuration.value
        currentRange = configuration.range
        currentSuffix = configuration.suffix
        valueLabel.text = "\(configuration.value)\(configuration.suffix)"
        setNeedsLayout()
        layoutIfNeeded()
        updateTrackProgress()
        DispatchQueue.main.async { [weak self] in
            self?.updateTrackProgress()
        }
    }

    private func setupUI() {
        addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.top.equalToSuperview()
            make.left.right.equalToSuperview().inset(SCRXFrom(16))
        }

        addSubview(fieldTitleLabel)
        addSubview(valueLabel)
        fieldTitleLabel.snp.makeConstraints { make in
            make.left.equalToSuperview().offset(SCRXFrom(16))
            make.right.lessThanOrEqualTo(valueLabel.snp.left).offset(-SCRXFrom(12))
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(24))
        }
        valueLabel.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.centerY.equalTo(fieldTitleLabel)
        }

        addSubview(controlsContainerView)
        controlsContainerView.snp.makeConstraints { make in
            make.top.greaterThanOrEqualTo(titleLabel.snp.bottom).offset(SCRYFrom(32))
            make.top.greaterThanOrEqualTo(fieldTitleLabel.snp.bottom).offset(SCRYFrom(12))
            make.left.right.bottom.equalToSuperview()
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
            make.left.right.equalToSuperview().inset(Layout.thumbSize / 2)
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
            thumbCenterXConstraint = make.centerX.equalTo(trackView.snp.left).constraint
            make.width.height.equalTo(Layout.thumbSize)
        }
        sliderContainerView.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(handleThumbPan(_:))))
        sliderContainerView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTrackTap(_:))))
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
        let trackWidth = trackView.bounds.width
        guard trackWidth > 0 else { return }
        progressWidthConstraint?.update(offset: max(trackWidth * progress, 0))
        thumbCenterXConstraint?.update(offset: trackWidth * progress)
        layoutIfNeeded()
    }

    private func updateValue(with locationX: CGFloat) {
        let minX = trackView.frame.minX
        let maxX = trackView.frame.maxX
        let clampedX = min(max(locationX, minX), maxX)
        let ratio = trackView.bounds.width > 0 ? (clampedX - minX) / trackView.bounds.width : 0
        let total = max(currentRange.upperBound - currentRange.lowerBound, 1)
        let newValue = currentRange.lowerBound + Int(round(ratio * CGFloat(total)))
        applyValue(newValue, notify: true)
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
