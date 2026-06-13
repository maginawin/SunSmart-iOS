//
//  UpDownLightView.swift
//  SunSmart
//
//  Created by SunSmart on 2026/6/13.
//

import UIKit
import NordicSigMeshSDK

final class UpDownLightView: UIControl {

    struct Configuration: Equatable {
        let isOn: Bool
        let brightnessPercent: Int
        let temperaturePercent: Int
        let supportsCCT: Bool
        let upRatio: Int
        let downRatio: Int
    }

    static var preferredSize: CGSize {
        let height = isIPad ? SCRYFit(238) : SCRYFit(200)
        return CGSize(width: height * 210.0 / 200.0, height: height)
    }

    private let upGrayImageView = UIImageView(image: UIImage(named: "up cct image")?.withTintColor(RGB(216, 216, 216), renderingMode: .alwaysOriginal))
    private let downGrayImageView = UIImageView(image: UIImage(named: "down cct image")?.withTintColor(RGB(216, 216, 216), renderingMode: .alwaysOriginal))
    private let upImageView = UIImageView(image: UIImage(named: "up cct image"))
    private let downImageView = UIImageView(image: UIImage(named: "down cct image"))
    private let separatorImageView = UIImageView(image: UIImage(named: "up down cct separator image"))
    private let upTagView = RatioTagView(iconName: "up cct tag icon")
    private let downTagView = RatioTagView(iconName: "down cct tag icon")

    private var configuration: Configuration?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(_ configuration: Configuration) {
        if self.configuration == configuration {
            return
        }
        self.configuration = configuration

        let upRatio = max(0, min(100, configuration.upRatio))
        let downRatio = max(0, min(100, configuration.downRatio))
        let brightnessPercent = max(0, min(100, configuration.brightnessPercent))
        let temperaturePercent = max(0, min(100, configuration.temperaturePercent))

        upTagView.valueText = "\(Self.ratioValueText(ratio: upRatio, brightnessPercent: brightnessPercent))%"
        downTagView.valueText = "\(Self.ratioValueText(ratio: downRatio, brightnessPercent: brightnessPercent))%"

        if configuration.isOn && brightnessPercent > 0 {
            let progress = CGFloat(brightnessPercent) / 100.0 * 0.5
            var imageAlpha = 0.5 + progress
            var grayAlpha: CGFloat = 0

            if configuration.supportsCCT {
                let tintColor = Node.getCctMixColor(temperature100: temperaturePercent)
                upImageView.image = UIImage(named: "up cct image")?.withTintColor(tintColor, renderingMode: .alwaysOriginal)
                downImageView.image = UIImage(named: "down cct image")?.withTintColor(tintColor, renderingMode: .alwaysOriginal)
                if (45...55).contains(temperaturePercent) {
                    grayAlpha = 0.5
                }
            } else {
                upImageView.image = UIImage(named: "up cct image")
                downImageView.image = UIImage(named: "down cct image")
            }

            upImageView.alpha = imageAlpha * CGFloat(upRatio) / 100.0
            downImageView.alpha = imageAlpha * CGFloat(downRatio) / 100.0
            upGrayImageView.alpha = grayAlpha * CGFloat(upRatio) / 100.0
            downGrayImageView.alpha = grayAlpha * CGFloat(downRatio) / 100.0
        } else {
            let offColor = RGB(216, 216, 216)
            upImageView.image = UIImage(named: "up cct image")?.withTintColor(offColor, renderingMode: .alwaysOriginal)
            downImageView.image = UIImage(named: "down cct image")?.withTintColor(offColor, renderingMode: .alwaysOriginal)
            upImageView.alpha = CGFloat(upRatio) / 100.0
            downImageView.alpha = CGFloat(downRatio) / 100.0
            upGrayImageView.alpha = 0
            downGrayImageView.alpha = 0
        }
    }

    private static func ratioValueText(ratio: Int, brightnessPercent: Int) -> Int {
        Int((Double(ratio) * Double(brightnessPercent) / 100.0).rounded())
    }

    private func setupUI() {
        [upGrayImageView, downGrayImageView, upImageView, downImageView].forEach { imageView in
            imageView.contentMode = .scaleToFill
            imageView.isUserInteractionEnabled = false
            addSubview(imageView)
        }

        separatorImageView.contentMode = .scaleToFill
        separatorImageView.isUserInteractionEnabled = false
        addSubview(separatorImageView)

        [upTagView, downTagView].forEach { tagView in
            tagView.isUserInteractionEnabled = false
            addSubview(tagView)
        }

        let scale = Self.preferredSize.height / 200.0

        upGrayImageView.snp.makeConstraints { make in
            make.left.equalToSuperview().offset(5 * scale)
            make.top.equalToSuperview()
            make.width.equalTo(200 * scale)
            make.height.equalTo(94 * scale)
        }
        upImageView.snp.makeConstraints { make in
            make.edges.equalTo(upGrayImageView)
        }

        downGrayImageView.snp.makeConstraints { make in
            make.left.width.height.equalTo(upGrayImageView)
            make.top.equalToSuperview().offset(106 * scale)
        }
        downImageView.snp.makeConstraints { make in
            make.edges.equalTo(downGrayImageView)
        }

        separatorImageView.snp.makeConstraints { make in
            make.left.equalToSuperview()
            make.top.equalToSuperview().offset(96 * scale)
            make.width.equalTo(210 * scale)
            make.height.equalTo(8 * scale)
        }

        upTagView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalToSuperview().offset(62 * scale)
            make.width.equalTo(64 * scale)
            make.height.equalTo(24 * scale)
        }

        downTagView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalToSuperview().offset(114 * scale)
            make.width.equalTo(64 * scale)
            make.height.equalTo(24 * scale)
        }
    }
}

private final class RatioTagView: UIView {

    var valueText: String {
        get {
            valueLabel.text ?? ""
        }
        set {
            valueLabel.text = newValue
        }
    }

    private let backgroundView = UIView()
    private let iconView: UIImageView
    private let valueLabel = UILabel(text: "50%", textColor: RGB(39, 37, 54), fontSize: 12, fontWeight: .light)

    init(iconName: String) {
        iconView = UIImageView(image: UIImage(named: iconName))
        super.init(frame: .zero)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        let scale = UpDownLightView.preferredSize.height / 200.0

        backgroundView.backgroundColor = UIColor.white.withAlphaComponent(0.75)
        backgroundView.layer.cornerRadius = 10 * scale
        backgroundView.clipsToBounds = true
        addSubview(backgroundView)
        backgroundView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        iconView.contentMode = .scaleAspectFit
        addSubview(iconView)
        iconView.snp.makeConstraints { make in
            make.left.equalToSuperview().offset(10 * scale)
            make.centerY.equalToSuperview()
            make.width.equalTo(6 * scale)
            make.height.equalTo(8 * scale)
        }

        valueLabel.textAlignment = .center
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.8
        addSubview(valueLabel)
        valueLabel.snp.makeConstraints { make in
            make.left.equalToSuperview().offset(20 * scale)
            make.centerY.equalToSuperview().offset(0.5 * scale)
            make.width.equalTo(36 * scale)
            make.height.equalTo(17 * scale)
        }
    }
}
