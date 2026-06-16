//
//  EmerFireSelectionCell.swift
//  SunSmart
//
//  Created by Plato Jobs on 2026/4/20.
//

import UIKit
import SnapKit

final class EmerFireSelectionCell: UITableViewCell {

    private var cardPosition: EmerFireCardPosition = .single
    private var topConstraint: Constraint?
    private var bottomConstraint: Constraint?

    private enum Layout {
        static let horizontalInset = SCRXFrom(16)
        static let verticalInset = SCRXFrom(16)
        static let contentRadius = SCRYFrom(5)
    }

    private lazy var cardView: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        return view
    }()

    private lazy var separatorView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor(red: 228 / 255.0, green: 229 / 255.0, blue: 235 / 255.0, alpha: 1)
        view.isHidden = true
        return view
    }()

    private lazy var valueContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = .white
        view.layer.cornerRadius = Layout.contentRadius
        view.layer.borderWidth = 0.5
        view.layer.borderColor = Line_Color1.cgColor
        return view
    }()

    private lazy var titleLabel: UILabel = {
        let label = UILabel(text: nil, textColor: Title_Color, fontSize: 16, fontWeight: .light)
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        label.setContentHuggingPriority(.required, for: .vertical)
        return label
    }()

    private lazy var valueLabel: UILabel = {
        let label = UILabel(text: nil, textColor: Title_Color, fontSize: 13, fontWeight: .light)
        label.numberOfLines = 0
        label.lineBreakMode = .byCharWrapping
        label.textAlignment = .left
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        label.setContentHuggingPriority(.required, for: .vertical)
        return label
    }()

    private lazy var arrowView: UIImageView = {
        let imageView = UIImageView(image: UIImage(named: "arrow_right"))
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        titleLabel.preferredMaxLayoutWidth = max(cardView.bounds.width - SCRXFrom(32), 0)
        valueLabel.preferredMaxLayoutWidth = max(valueContainerView.bounds.width - SCRXFrom(39), 0)
        applyCardStyle()
    }

    func configure(title: String, value: String, cardPosition: EmerFireCardPosition = .single) {
        titleLabel.text = title
        valueLabel.text = value
        self.cardPosition = cardPosition
        topConstraint?.update(offset: cardPosition.topInset)
        bottomConstraint?.update(offset: -cardPosition.bottomInset)
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
        }

        cardView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalToSuperview()
        }

        cardView.addSubview(valueContainerView)
        valueContainerView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(8))
            make.bottom.equalToSuperview().offset(-SCRYFrom(8))
            make.height.equalTo(SCRYFrom(40))
        }

        valueContainerView.addSubview(arrowView)
        arrowView.snp.makeConstraints { make in
            make.right.equalToSuperview().offset(-SCRXFrom(8))
            make.centerY.equalToSuperview()
        }

        valueContainerView.addSubview(valueLabel)
        valueLabel.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.right.equalToSuperview().offset(-SCRXFrom(36))
            make.left.equalToSuperview().offset(SCRXFrom(12))
            make.top.greaterThanOrEqualToSuperview().offset(SCRYFrom(6))
            make.bottom.lessThanOrEqualToSuperview().offset(-SCRYFrom(6))
        }

        cardView.addSubview(separatorView)
        separatorView.snp.makeConstraints { make in
            make.left.right.equalToSuperview().inset(SCRXFrom(16))
            make.bottom.equalToSuperview()
            make.height.equalTo(0.5)
        }
    }

    private func applyCardStyle() {
        separatorView.isHidden = true
    }
}

final class EmerFireRestoreActionCell: UITableViewCell {

    var actionDidChange: ((EmergencyFireRestoreActionType) -> Void)?
    var brightnessDidChange: ((Int) -> Void)?

    private var options: [LinkedEmerFireRestoreActionOption] = []
    private var selectedType: EmergencyFireRestoreActionType = .restoreAuto
    private var brightnessValue = 100
    private var brightnessRange: ClosedRange<Int> = 1...100
    private var cardPosition: EmerFireCardPosition = .single
    private var topConstraint: Constraint?
    private var bottomConstraint: Constraint?
    private var cardMinHeightConstraint: Constraint?
    private var brightnessHeightConstraint: Constraint?
    private var optionsHeightConstraint: Constraint?
    private var progressWidthConstraint: Constraint?
    private var thumbCenterXConstraint: Constraint?
    private var currentOptionsHeight = Layout.optionHeight

    private enum Layout {
        static let horizontalInset = SCRXFrom(16)
        static let verticalInset = SCRXFrom(16)
        static let cardRadius = SCRYFrom(10)
        static let selectedCardHeight = SCRYFrom(224)
        static let compactCardHeight = SCRYFrom(132)
        static let optionHeight = SCRYFrom(56)
        static let brightnessHeight = SCRYFrom(92)
        static let buttonSize = SCRXFrom(24)
        static let thumbSize = SCRXFrom(24)
        static let trackHeight = SCRYFrom(2)
    }

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

    private lazy var titleLabel: UILabel = {
        let label = UILabel(text: "Action", textColor: Title_Color, fontSize: 16, fontWeight: .light)
        label.numberOfLines = 0
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        return label
    }()

    private lazy var optionsContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = RGB(249, 250, 252)
        view.layer.cornerRadius = SCRYFrom(7)
        view.layer.masksToBounds = true
        return view
    }()

    private lazy var optionsFlowView: EmerFireRestoreActionOptionsView = {
        let view = EmerFireRestoreActionOptionsView()
        view.selectionDidChange = { [weak self] type in
            self?.selectOption(type)
        }
        return view
    }()

    private lazy var brightnessContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        return view
    }()

    private lazy var brightnessFieldTitleLabel: UILabel = {
        let label = UILabel(text: "Set Brightness To:", textColor: AssistText_Color, fontSize: 14, fontWeight: .light)
        label.numberOfLines = 1
        return label
    }()

    private lazy var brightnessValueLabel: UILabel = {
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

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        actionDidChange = nil
        brightnessDidChange = nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        titleLabel.preferredMaxLayoutWidth = max(cardView.bounds.width - SCRXFrom(32), 0)
        updateOptionsHeightIfNeeded()
        applyCardStyle()
        updateTrackProgress()
    }

    func configure(
        options: [LinkedEmerFireRestoreActionOption],
        selectedType: EmergencyFireRestoreActionType,
        brightness: Int,
        brightnessRange: ClosedRange<Int>,
        cardPosition: EmerFireCardPosition = .single
    ) {
        self.options = options
        self.selectedType = selectedType
        self.brightnessValue = min(max(brightness, brightnessRange.lowerBound), brightnessRange.upperBound)
        self.brightnessRange = brightnessRange
        self.cardPosition = cardPosition
        topConstraint?.update(offset: cardPosition.topInset)
        bottomConstraint?.update(offset: -cardPosition.bottomInset)
        brightnessValueLabel.text = "\(self.brightnessValue)%"
        updateBrightnessVisibility()
        reloadOptions()
        applyCardStyle()
        setNeedsLayout()
        layoutIfNeeded()
        updateTrackProgress()
        DispatchQueue.main.async { [weak self] in
            self?.updateTrackProgress()
        }
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
            cardMinHeightConstraint = make.height.greaterThanOrEqualTo(Layout.compactCardHeight).constraint
        }

        cardView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.right.equalToSuperview().inset(SCRXFrom(16))
            make.top.equalToSuperview().offset(SCRYFrom(16))
        }

        cardView.addSubview(optionsContainerView)
        optionsContainerView.snp.makeConstraints { make in
            make.left.right.equalToSuperview().inset(SCRXFrom(16))
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(14))
            optionsHeightConstraint = make.height.equalTo(Layout.optionHeight).constraint
        }

        optionsContainerView.addSubview(optionsFlowView)
        optionsFlowView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        cardView.addSubview(brightnessContainerView)
        brightnessContainerView.snp.makeConstraints { make in
            make.left.right.equalToSuperview().inset(SCRXFrom(16))
            make.top.equalTo(optionsContainerView.snp.bottom).offset(SCRYFrom(16))
            make.bottom.equalToSuperview().offset(-SCRYFrom(16))
            brightnessHeightConstraint = make.height.equalTo(Layout.brightnessHeight).constraint
        }

        brightnessContainerView.addSubview(brightnessFieldTitleLabel)
        brightnessContainerView.addSubview(brightnessValueLabel)
        brightnessFieldTitleLabel.isHidden = true
        brightnessFieldTitleLabel.snp.makeConstraints { make in
            make.top.left.equalToSuperview()
            make.right.lessThanOrEqualTo(brightnessValueLabel.snp.left).offset(-SCRXFrom(12))
        }

        brightnessValueLabel.snp.makeConstraints { make in
            make.right.equalToSuperview()
            make.centerY.equalTo(brightnessFieldTitleLabel)
        }

        brightnessContainerView.addSubview(controlsContainerView)
        controlsContainerView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.top.equalTo(brightnessFieldTitleLabel.snp.bottom).offset(SCRYFrom(12))
            make.height.greaterThanOrEqualTo(max(Layout.buttonSize, Layout.thumbSize))
        }

        controlsContainerView.addSubview(minusButton)
        minusButton.snp.makeConstraints { make in
            make.left.equalToSuperview()
            make.top.greaterThanOrEqualToSuperview()
            make.width.height.equalTo(Layout.buttonSize)
            make.bottom.equalToSuperview()
        }

        controlsContainerView.addSubview(plusButton)
        plusButton.snp.makeConstraints { make in
            make.right.equalToSuperview()
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

    private func reloadOptions() {
        optionsFlowView.configure(options: options, selectedType: selectedType)
        setNeedsLayout()
    }

    private func selectOption(_ newType: EmergencyFireRestoreActionType) {
        guard newType != selectedType else { return }
        selectedType = newType
        updateBrightnessVisibility()
        reloadOptions()
        actionDidChange?(newType)
    }

    @objc private func handleMinus() {
        guard brightnessValue > brightnessRange.lowerBound else { return }
        applyBrightnessValue(brightnessValue - 1, notify: true)
    }

    @objc private func handlePlus() {
        guard brightnessValue < brightnessRange.upperBound else { return }
        applyBrightnessValue(brightnessValue + 1, notify: true)
    }

    @objc private func handleThumbPan(_ gesture: UIPanGestureRecognizer) {
        updateBrightnessValue(with: gesture.location(in: sliderContainerView).x)
    }

    @objc private func handleTrackTap(_ gesture: UITapGestureRecognizer) {
        updateBrightnessValue(with: gesture.location(in: sliderContainerView).x)
    }

    private func applyCardStyle() {
        cardView.layer.cornerRadius = Layout.cardRadius
        cardView.layer.maskedCorners = cardPosition.maskedCorners
        separatorView.isHidden = true
    }

    private func updateBrightnessVisibility() {
        let showsBrightness = selectedType == .setBrightness
        let heightExtra = max(currentOptionsHeight - Layout.optionHeight, 0)
        brightnessContainerView.isHidden = !showsBrightness
        brightnessHeightConstraint?.update(offset: showsBrightness ? Layout.brightnessHeight : 0)
        cardMinHeightConstraint?.update(offset: (showsBrightness ? Layout.selectedCardHeight : Layout.compactCardHeight) + heightExtra)
    }

    private func updateOptionsHeightIfNeeded() {
        let width = optionsContainerView.bounds.width
        guard width > 0 else { return }
        let height = optionsFlowView.preferredHeight(for: width)
        guard abs(height - currentOptionsHeight) > 0.5 else { return }
        currentOptionsHeight = height
        optionsHeightConstraint?.update(offset: height)
        updateBrightnessVisibility()
    }

    private func updateTrackProgress() {
        let total = max(brightnessRange.upperBound - brightnessRange.lowerBound, 1)
        let progress = CGFloat(brightnessValue - brightnessRange.lowerBound) / CGFloat(total)
        let trackWidth = trackView.bounds.width
        guard trackWidth > 0 else { return }
        progressWidthConstraint?.update(offset: max(trackWidth * progress, 0))
        thumbCenterXConstraint?.update(offset: trackWidth * progress)
        layoutIfNeeded()
    }

    private func updateBrightnessValue(with locationX: CGFloat) {
        let minX = trackView.frame.minX
        let maxX = trackView.frame.maxX
        let clampedX = min(max(locationX, minX), maxX)
        let ratio = trackView.bounds.width > 0 ? (clampedX - minX) / trackView.bounds.width : 0
        let total = max(brightnessRange.upperBound - brightnessRange.lowerBound, 1)
        let newValue = brightnessRange.lowerBound + Int(round(ratio * CGFloat(total)))
        applyBrightnessValue(newValue, notify: true)
    }

    private func applyBrightnessValue(_ value: Int, notify: Bool) {
        let clampedValue = min(max(value, brightnessRange.lowerBound), brightnessRange.upperBound)
        guard clampedValue != brightnessValue else { return }
        brightnessValue = clampedValue
        brightnessValueLabel.text = "\(clampedValue)%"
        updateTrackProgress()
        if notify {
            brightnessDidChange?(clampedValue)
        }
    }
}

private final class EmerFireRestoreActionOptionsView: UIView {

    var selectionDidChange: ((EmergencyFireRestoreActionType) -> Void)?

    private var options: [LinkedEmerFireRestoreActionOption] = []
    private var selectedType: EmergencyFireRestoreActionType = .restoreAuto
    private var buttons: [UIButton] = []

    private enum Layout {
        static let horizontalInset = SCRXFrom(6)
        static let verticalInset = SCRXFrom(16)
        static let itemHeight = SCRYFrom(40)
        static let itemSpacing = SCRXFrom(8)
        static let rowSpacing = SCRYFrom(0)
        static let imageTitleSpacing = SCRXFrom(6)
    }

    func configure(options: [LinkedEmerFireRestoreActionOption], selectedType: EmergencyFireRestoreActionType) {
        self.options = options
        self.selectedType = selectedType
        buttons.forEach { $0.removeFromSuperview() }
        buttons = options.enumerated().map { index, option in
            let button = UIButton(type: .custom)
            button.tag = index
            button.contentHorizontalAlignment = .left
            button.titleLabel?.font = FONTS(12)
            button.titleLabel?.numberOfLines = 1
            button.titleLabel?.lineBreakMode = .byClipping
            button.titleLabel?.textAlignment = .left
            button.titleLabel?.adjustsFontSizeToFitWidth = false
            button.setTitle(option.title, for: .normal)
            button.setTitleColor(Title_Color, for: .normal)
            button.setImage(UIImage(named: option.type == selectedType ? "select" : "select_un"), for: .normal)
            button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
            button.imageEdgeInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: Layout.imageTitleSpacing)
            button.titleEdgeInsets = UIEdgeInsets(top: 0, left: Layout.imageTitleSpacing, bottom: 0, right: 0)
            button.addTarget(self, action: #selector(optionAction(_:)), for: .touchUpInside)
            addSubview(button)
            return button
        }
        setNeedsLayout()
    }

    func preferredHeight(for width: CGFloat) -> CGFloat {
        let frames = layoutFrames(for: width)
        guard let maxY = frames.map(\.maxY).max() else { return SCRYFrom(56) }
        return max(SCRYFrom(56), maxY + Layout.verticalInset)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let frames = layoutFrames(for: bounds.width)
        zip(buttons, frames).forEach { button, frame in
            button.frame = frame
        }
    }

    @objc private func optionAction(_ sender: UIButton) {
        guard options.indices.contains(sender.tag) else { return }
        selectionDidChange?(options[sender.tag].type)
    }

    private func layoutFrames(for width: CGFloat) -> [CGRect] {
        guard width > 0 else { return [] }
        let rightLimit = width - Layout.horizontalInset
        let availableWidth = max(width - Layout.horizontalInset * 2, 0)
        var x = Layout.horizontalInset
        var y = Layout.verticalInset
        var frames: [CGRect] = []

        for button in buttons {
            let itemWidth = min(max(preferredWidth(for: button), SCRXFrom(48)), availableWidth)
            if x > Layout.horizontalInset && x + itemWidth > rightLimit {
                x = Layout.horizontalInset
                y += Layout.itemHeight + Layout.rowSpacing
            }
            frames.append(CGRect(x: x, y: y, width: itemWidth, height: Layout.itemHeight))
            x += itemWidth + Layout.itemSpacing
        }

        return frames
    }

    private func preferredWidth(for button: UIButton) -> CGFloat {
        let title = button.title(for: .normal) ?? ""
        let font = button.titleLabel?.font ?? FONTS(12)
        let titleWidth = ceil((title as NSString).size(withAttributes: [.font: font]).width)
        let imageWidth = button.image(for: .normal)?.size.width ?? SCRXFrom(16)
        return titleWidth + imageWidth + Layout.imageTitleSpacing + SCRXFrom(12)
    }
}
