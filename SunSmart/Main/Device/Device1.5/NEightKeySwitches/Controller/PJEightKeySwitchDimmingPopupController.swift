//
//  PJEightKeySwitchDimmingPopupController.swift
//  SunSmart
//
//  Created by Plato Jobs.
//

import UIKit
import SnapKit

final class PJEightKeySwitchDimmingPopupController: UIViewController {

    var brightnessEndedAction: ((Int) -> Void)?

    private enum Layout {
        static let cardHorizontalInset = SCRXFrom(8)
        static let cardBottomInset = SCRYFrom(32)
        static let cardHeight = SCRYFrom(144)
        static let cardCornerRadius = SCRYFrom(26)
        static let titleTop = SCRYFrom(24)
        static let titleLeftInset = SCRXFrom(20)
        static let sliderTop = SCRYFrom(22)
        static let sliderHorizontalInset = SCRXFrom(36)
        static let sliderHeight = SCRYFrom(45)
        static let sliderBottomInset = SCRYFrom(34)
    }

    private let dimmingView = UIView()
    private let sheetView = UIView()
    private let titleLabel = UILabel(
        text: "neightkeyswitches_dimming".localizedString,
        textColor: Title_Color,
        fontSize: 15,
        fontWeight: .medium,
        fit: false
    )
    private let sliderView = BuoySliderView(frame: .zero, functionType: .level())

    init() {
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        sliderView.value = 50
    }

    private func setupUI() {
        view.backgroundColor = .clear

        dimmingView.backgroundColor = UIColor.black.withAlphaComponent(0.36)
        view.addSubview(dimmingView)
        dimmingView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissSelf))
        dimmingView.addGestureRecognizer(tapGesture)

        sheetView.backgroundColor = .white
        sheetView.layer.cornerRadius = Layout.cardCornerRadius
        sheetView.clipsToBounds = true
        view.addSubview(sheetView)
        sheetView.snp.makeConstraints { make in
            make.left.equalToSuperview().offset(Layout.cardHorizontalInset)
            make.right.equalToSuperview().offset(-Layout.cardHorizontalInset)
            make.bottom.equalTo(view.safeAreaLayoutGuide).offset(-Layout.cardBottomInset)
            make.height.equalTo(Layout.cardHeight)
        }

        titleLabel.textAlignment = .left
        sheetView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(Layout.titleTop)
            make.left.equalToSuperview().offset(Layout.titleLeftInset)
            make.right.lessThanOrEqualToSuperview().offset(-Layout.titleLeftInset)
        }

        sheetView.addSubview(sliderView)
        sliderView.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(Layout.sliderTop)
            make.left.equalToSuperview().offset(Layout.sliderHorizontalInset)
            make.right.equalToSuperview().offset(-Layout.sliderHorizontalInset)
            make.height.equalTo(Layout.sliderHeight)
            make.bottom.lessThanOrEqualToSuperview().offset(-Layout.sliderBottomInset)
        }
        sliderView.valueThrottleChangedCallback = { [weak self] value, ended in
            guard ended else {
                return
            }
            self?.brightnessEndedAction?(value)
        }
    }

    @objc private func dismissSelf() {
        dismiss(animated: true)
    }
}
