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
    private let trackHorizontalInset = SCRXFrom(14)
    private let thumbSize = SCRXFrom(24)
    private let markerSize = SCRXFrom(6)
    private let trackHeight = SCRYFrom(2)
    private let markerLineTop = SCRYFrom(22)
    private let labelTopSpacing = SCRYFrom(18)

    private var markerCenterXs: [CGFloat] = []
    private var isDraggingThumb = false

    private(set) var selectedOption: PJEightKeySwitchMoreSettingsViewModel.PeriodicReportingOption {
        didSet {
            guard oldValue != selectedOption else { return }
            updateSelectionAppearance()
            valueChanged?(selectedOption)
        }
    }

    private lazy var trackView: UIView = {
        let view = UIView()
        view.backgroundColor = Bar_Color.withAlphaComponent(0.45)
        view.layer.cornerRadius = trackHeight * 0.5
        view.isUserInteractionEnabled = false
        return view
    }()

    private lazy var thumbView: UIView = {
        let view = UIView()
        view.backgroundColor = .white
        view.layer.cornerRadius = thumbSize * 0.5
        view.layer.shadowColor = UIColor.black.withAlphaComponent(0.14).cgColor
        view.layer.shadowOpacity = 1
        view.layer.shadowRadius = 8
        view.layer.shadowOffset = CGSize(width: 0, height: 2)
        view.isUserInteractionEnabled = false
        return view
    }()

    private var markerViews: [UIView] = []
    private var titleLabels: [UILabel] = []

    init(
        options: [PJEightKeySwitchMoreSettingsViewModel.PeriodicReportingOption],
        selectedOption: PJEightKeySwitchMoreSettingsViewModel.PeriodicReportingOption
    ) {
        self.options = options
        self.selectedOption = selectedOption
        super.init(frame: .zero)
        setupUI()
        setupGestures()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutTrackAndMarkers()
        updateSelectionAppearance()
    }

    func setSelectedOption(_ option: PJEightKeySwitchMoreSettingsViewModel.PeriodicReportingOption) {
        guard selectedOption != option else { return }
        selectedOption = option
    }

    private func setupUI() {
        backgroundColor = .clear

        addSubview(trackView)

        for option in options {
            let markerView = UIView()
            markerView.backgroundColor = .white
            markerView.layer.borderWidth = 1
            markerView.layer.borderColor = Bar_Color.withAlphaComponent(0.75).cgColor
            markerView.layer.cornerRadius = markerSize * 0.5
            markerView.isUserInteractionEnabled = false
            addSubview(markerView)
            markerViews.append(markerView)

            let titleLabel = UILabel(
                text: option.title,
                textColor: SubText_Color,
                fontSize: 12,
                fontWeight: .light
            )
            titleLabel.textAlignment = .center
            titleLabel.numberOfLines = 1
            titleLabel.isUserInteractionEnabled = false
            addSubview(titleLabel)
            titleLabels.append(titleLabel)
        }

        addSubview(thumbView)
    }

    private func setupGestures() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tapGesture)

        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGesture.cancelsTouchesInView = true
        addGestureRecognizer(panGesture)
    }

    private func layoutTrackAndMarkers() {
        let availableWidth = max(bounds.width - (trackHorizontalInset * 2), 0)
        let centerY = markerLineTop

        trackView.frame = CGRect(
            x: trackHorizontalInset,
            y: centerY - (trackHeight * 0.5),
            width: availableWidth,
            height: trackHeight
        )

        guard options.count > 1 else {
            markerCenterXs = [trackHorizontalInset + (availableWidth * 0.5)]
            return
        }

        let step = availableWidth / CGFloat(options.count - 1)
        markerCenterXs = options.indices.map { index in
            trackHorizontalInset + (CGFloat(index) * step)
        }

        for (index, markerView) in markerViews.enumerated() {
            let centerX = markerCenterXs[index]
            markerView.frame = CGRect(
                x: centerX - (markerSize * 0.5),
                y: centerY - (markerSize * 0.5),
                width: markerSize,
                height: markerSize
            )
        }

        let labelWidth = max(SCRXFrom(44), step + SCRXFrom(10))
        for (index, titleLabel) in titleLabels.enumerated() {
            let centerX = markerCenterXs[index]
            titleLabel.frame = CGRect(
                x: centerX - (labelWidth * 0.5),
                y: centerY + labelTopSpacing,
                width: labelWidth,
                height: SCRYFrom(20)
            )
        }
    }

    private func updateSelectionAppearance() {
        guard
            let index = options.firstIndex(of: selectedOption),
            markerCenterXs.indices.contains(index)
        else {
            return
        }

        let selectedCenterX = markerCenterXs[index]
        thumbView.frame = CGRect(
            x: selectedCenterX - (thumbSize * 0.5),
            y: markerLineTop - (thumbSize * 0.5),
            width: thumbSize,
            height: thumbSize
        )

        for (markerIndex, markerView) in markerViews.enumerated() {
            markerView.backgroundColor = .white
            markerView.layer.borderColor = Bar_Color.withAlphaComponent(0.75).cgColor
            markerView.alpha = markerIndex == index ? 0 : 1
        }

        bringSubviewToFront(thumbView)
    }

    private func updateSelection(for locationX: CGFloat) {
        guard !markerCenterXs.isEmpty else { return }
        let clampedX = min(max(locationX, markerCenterXs.first ?? locationX), markerCenterXs.last ?? locationX)
        let nearestIndex = markerCenterXs.enumerated().min { lhs, rhs in
            abs(lhs.element - clampedX) < abs(rhs.element - clampedX)
        }?.offset ?? 0
        setSelectedOption(options[nearestIndex])
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        updateSelection(for: gesture.location(in: self).x)
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let location = gesture.location(in: self)
        switch gesture.state {
        case .began:
            isDraggingThumb = thumbView.frame.insetBy(dx: -SCRXFrom(18), dy: -SCRYFrom(18)).contains(location)
                || trackView.frame.insetBy(dx: 0, dy: -SCRYFrom(14)).contains(location)
        case .changed:
            guard isDraggingThumb else { return }
            updateSelection(for: location.x)
        case .ended, .cancelled, .failed:
            guard isDraggingThumb else { return }
            updateSelection(for: location.x)
            isDraggingThumb = false
        default:
            break
        }
    }
}
