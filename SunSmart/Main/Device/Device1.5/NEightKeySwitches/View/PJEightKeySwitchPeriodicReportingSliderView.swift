//
//  PJEightKeySwitchPeriodicReportingSliderView.swift
//  SunSmart
//
//  Created by Plato Jobs.
//

import UIKit
import SnapKit

final class PJEightKeySwitchPeriodicReportingSliderView: UIView {

    var valueChanged: ((PJEightKeySwitchMoreSettingsViewModel.PeriodicReportingOption) -> Void)?

    private let options: [PJEightKeySwitchMoreSettingsViewModel.PeriodicReportingOption]
    private var thumbCenterXConstraint: Constraint?
    private var markerCenterXs: [CGFloat] = []

    private(set) var selectedOption: PJEightKeySwitchMoreSettingsViewModel.PeriodicReportingOption {
        didSet {
            guard oldValue != selectedOption else { return }
            updateThumbPosition(animated: true)
            valueChanged?(selectedOption)
        }
    }

    private lazy var trackView: UIView = {
        let view = UIView()
        view.backgroundColor = Bar_Color.withAlphaComponent(0.35)
        view.layer.cornerRadius = 1
        return view
    }()

    private lazy var thumbView: UIView = {
        let view = UIView()
        view.backgroundColor = .white
        view.layer.cornerRadius = SCRXFrom(12)
        view.layer.shadowColor = UIColor.black.withAlphaComponent(0.12).cgColor
        view.layer.shadowOpacity = 1
        view.layer.shadowRadius = 8
        view.layer.shadowOffset = CGSize(width: 0, height: 2)
        return view
    }()

    private lazy var markerContainerStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.alignment = .fill
        stackView.distribution = .fillEqually
        return stackView
    }()

    private var markerViews: [UIView] = []

    init(
        options: [PJEightKeySwitchMoreSettingsViewModel.PeriodicReportingOption],
        selectedOption: PJEightKeySwitchMoreSettingsViewModel.PeriodicReportingOption
    ) {
        self.options = options
        self.selectedOption = selectedOption
        super.init(frame: .zero)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateMarkerCenters()
        updateThumbPosition(animated: false)
    }

    func setSelectedOption(_ option: PJEightKeySwitchMoreSettingsViewModel.PeriodicReportingOption) {
        guard selectedOption != option else { return }
        selectedOption = option
    }

    private func setupUI() {
        backgroundColor = .clear

        addSubview(trackView)
        trackView.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(SCRYFrom(26))
            make.left.equalTo(SCRXFrom(14))
            make.right.equalTo(SCRXFrom(-14))
            make.height.equalTo(2)
        }

        addSubview(markerContainerStackView)
        markerContainerStackView.snp.makeConstraints { make in
            make.left.right.equalTo(trackView)
            make.centerY.equalTo(trackView)
        }

        for option in options {
            let itemView = makeMarkerItemView(title: option.title)
            markerContainerStackView.addArrangedSubview(itemView)
        }

        addSubview(thumbView)
        thumbView.snp.makeConstraints { make in
            make.centerY.equalTo(trackView)
            make.width.height.equalTo(SCRXFrom(24))
            thumbCenterXConstraint = make.centerX.equalTo(trackView.snp.left).constraint
        }

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tapGesture)

        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        thumbView.addGestureRecognizer(panGesture)
    }

    private func makeMarkerItemView(title: String) -> UIView {
        let containerView = UIView()

        let markerView = UIView()
        markerView.backgroundColor = .white
        markerView.layer.borderWidth = 1
        markerView.layer.borderColor = Bar_Color.withAlphaComponent(0.7).cgColor
        markerView.layer.cornerRadius = SCRXFrom(4)
        markerViews.append(markerView)

        let titleLabel = UILabel(text: title, textColor: SubText_Color, fontSize: 14, fontWeight: .light)
        titleLabel.textAlignment = .center

        containerView.addSubview(markerView)
        markerView.snp.makeConstraints { make in
            make.top.centerX.equalToSuperview()
            make.width.height.equalTo(SCRXFrom(8))
        }

        containerView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.top.equalTo(markerView.snp.bottom).offset(SCRYFrom(12))
            make.left.right.bottom.equalToSuperview()
        }

        return containerView
    }

    private func updateMarkerCenters() {
        markerCenterXs = markerViews.map { markerView in
            convert(markerView.center, from: markerView.superview).x
        }
    }

    private func updateThumbPosition(animated: Bool) {
        guard
            let index = options.firstIndex(of: selectedOption),
            markerCenterXs.indices.contains(index)
        else {
            return
        }

        thumbCenterXConstraint?.update(offset: markerCenterXs[index] - trackView.frame.minX)
        let animations = { self.layoutIfNeeded() }
        if animated {
            UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseOut]) {
                animations()
            }
        } else {
            animations()
        }
    }

    private func updateSelection(for locationX: CGFloat) {
        guard !markerCenterXs.isEmpty else { return }
        let nearestIndex = markerCenterXs.enumerated().min { lhs, rhs in
            abs(lhs.element - locationX) < abs(rhs.element - locationX)
        }?.offset ?? 0
        setSelectedOption(options[nearestIndex])
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        updateSelection(for: gesture.location(in: self).x)
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let locationX = gesture.location(in: self).x
        updateSelection(for: locationX)
    }
}
