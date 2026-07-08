//
//  ELControllerFunctionTestView.swift
//  SunSmart
//
//  Created by SunSmart on 2026/6/25.
//

import UIKit

final class ELControllerFunctionTestView: UIView {

    enum Kind {
        case functionTest
        case rxTxCable
    }

    enum FunctionTestState {
        case idle
        case awaiting
        case passed
        case faults(lamp: Bool, battery: Bool, circuit: Bool)
        case invalid
        case failed
        case normalModeRequired
    }

    enum RxTxState {
        case unknown
        case checking
        case normal
        case fault
    }

    private enum DisplayStyle {
        case neutral
        case waiting
        case success
        case warning
        case fault
    }

    private struct DisplayRow {
        let titleKey: String
        let style: DisplayStyle
    }

    private struct DisplayState {
        let buttonTitleKey: String
        let buttonAlpha: CGFloat
        let rows: [DisplayRow]
        let showsSpinner: Bool
    }

    private enum Constants {
        static let horizontalInset = SCRXFrom(16)
        static let headerTop = SCRYFrom(16)
        static let headerBottom = SCRYFrom(12)
        static let stateBottom = SCRYFrom(16)
        static let iconSize = SCRYFrom(16)
        static let tagHeight = SCRYFrom(20)
        static let buttonHeight = SCRYFrom(28)
        static let buttonMinWidth = SCRXFrom(56)
        static let buttonHorizontalPadding = SCRXFrom(18)
        static let singleStateHeight = SCRYFrom(52)
        static let faultStateHeight = SCRYFrom(40)
        static let rowSpacing = SCRYFrom(6)
        static let stateCornerRadius = SCRYFrom(14)
        static let cardCornerRadius = SCRYFrom(16)
        static let spinnerSize = SCRYFrom(24)
    }

    private let kind: Kind
    var onAction: (() -> Void)?
    private var currentState: DisplayState
    private let headerView = UIView()
    private let titleContainerView = UIView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let tagLabel = UILabel()
    private let actionButton = UIButton(type: .system)
    private let stateStackView = UIStackView()

    private static func functionTestDisplayState(_ state: FunctionTestState) -> DisplayState {
        switch state {
        case .idle:
            return .init(
                buttonTitleKey: "el_controller_function_test_start_button",
                buttonAlpha: 1,
                rows: [.init(titleKey: "el_controller_function_test_start_prompt", style: .neutral)],
                showsSpinner: false
            )
        case .awaiting:
            return .init(
                buttonTitleKey: "el_controller_function_test_testing_button",
                buttonAlpha: 0.6,
                rows: [.init(titleKey: "el_controller_function_test_awaiting", style: .waiting)],
                showsSpinner: true
            )
        case .passed:
            return .init(
                buttonTitleKey: "el_controller_function_test_start_button",
                buttonAlpha: 1,
                rows: [.init(titleKey: "el_controller_function_test_passed", style: .success)],
                showsSpinner: false
            )
        case .faults(let lamp, let battery, let circuit):
            var rows: [DisplayRow] = []
            if lamp {
                rows.append(.init(titleKey: "el_controller_function_test_lamp_fault", style: .warning))
            }
            if battery {
                rows.append(.init(titleKey: "el_controller_function_test_battery_fault", style: .fault))
            }
            if circuit {
                rows.append(.init(titleKey: "el_controller_function_test_circuit_fault", style: .fault))
            }
            return .init(
                buttonTitleKey: "el_controller_function_test_start_button",
                buttonAlpha: 1,
                rows: rows.isEmpty ? [.init(titleKey: "el_controller_function_test_passed", style: .success)] : rows,
                showsSpinner: false
            )
        case .invalid:
            return .init(
                buttonTitleKey: "el_controller_function_test_start_button",
                buttonAlpha: 1,
                rows: [.init(titleKey: "el_controller_function_test_invalid", style: .warning)],
                showsSpinner: false
            )
        case .failed:
            return .init(
                buttonTitleKey: "el_controller_function_test_start_button",
                buttonAlpha: 1,
                rows: [.init(titleKey: "el_controller_function_test_failed", style: .fault)],
                showsSpinner: false
            )
        case .normalModeRequired:
            return .init(
                buttonTitleKey: "el_controller_function_test_start_button",
                buttonAlpha: 1,
                rows: [.init(titleKey: "el_controller_function_test_normal_mode_required", style: .fault)],
                showsSpinner: false
            )
        }
    }

    private static func rxTxDisplayState(_ state: RxTxState) -> DisplayState {
        switch state {
        case .unknown:
            return .init(
                buttonTitleKey: "el_controller_rxtx_check_button",
                buttonAlpha: 1,
                rows: [.init(titleKey: "el_controller_rxtx_start_prompt", style: .neutral)],
                showsSpinner: false
            )
        case .checking:
            return .init(
                buttonTitleKey: "el_controller_rxtx_checking_button",
                buttonAlpha: 0.6,
                rows: [.init(titleKey: "el_controller_rxtx_checking_connection", style: .waiting)],
                showsSpinner: true
            )
        case .normal:
            return .init(
                buttonTitleKey: "el_controller_rxtx_check_button",
                buttonAlpha: 1,
                rows: [.init(titleKey: "el_controller_rxtx_connection_normal", style: .success)],
                showsSpinner: false
            )
        case .fault:
            return .init(
                buttonTitleKey: "el_controller_rxtx_check_button",
                buttonAlpha: 1,
                rows: [.init(titleKey: "el_controller_rxtx_connection_fault", style: .fault)],
                showsSpinner: false
            )
        }
    }

    init(kind: Kind) {
        self.kind = kind
        switch kind {
        case .functionTest:
            self.currentState = Self.functionTestDisplayState(.idle)
        case .rxTxCable:
            self.currentState = Self.rxTxDisplayState(.unknown)
        }
        super.init(frame: .zero)
        setupUI()
        applyCurrentState()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: Constants.cardCornerRadius).cgPath
    }

    private func setupUI() {
        backgroundColor = .white
        layer.cornerRadius = Constants.cardCornerRadius
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.07
        layer.shadowOffset = CGSize(width: 0, height: 2)
        layer.shadowRadius = 4

        setupHeader()
        setupStateStackView()
    }

    private func setupHeader() {
        addSubview(headerView)
        headerView.snp.makeConstraints { make in
            make.top.left.right.equalToSuperview()
            make.height.equalTo(Constants.headerTop + Constants.buttonHeight + Constants.headerBottom)
        }

        setupActionButton()
        setupTitleContainer()
    }

    private func setupActionButton() {
        actionButton.titleLabel?.font = UIFont.systemFont(ofSize: SCRYFrom(12), weight: .regular)
        actionButton.titleLabel?.adjustsFontSizeToFitWidth = true
        actionButton.titleLabel?.minimumScaleFactor = 0.8
        actionButton.setTitleColor(.white, for: .normal)
        actionButton.backgroundColor = RGB(102, 103, 171)
        actionButton.layer.cornerRadius = Constants.buttonHeight * 0.5
        actionButton.contentEdgeInsets = UIEdgeInsets(
            top: 0,
            left: Constants.buttonHorizontalPadding * 0.5,
            bottom: 0,
            right: Constants.buttonHorizontalPadding * 0.5
        )
        actionButton.setContentHuggingPriority(.required, for: .horizontal)
        actionButton.addTarget(self, action: #selector(actionButtonTapped), for: .touchUpInside)
        headerView.addSubview(actionButton)
        actionButton.snp.makeConstraints { make in
            make.right.equalToSuperview().offset(-Constants.horizontalInset)
            make.top.greaterThanOrEqualTo(Constants.headerTop)
            make.bottom.lessThanOrEqualToSuperview().offset(-Constants.headerBottom)
            make.centerY.equalToSuperview().offset((Constants.headerTop - Constants.headerBottom) * 0.5)
            make.height.equalTo(Constants.buttonHeight)
            make.width.greaterThanOrEqualTo(Constants.buttonMinWidth)
        }
    }

    private func setupTitleContainer() {
        headerView.addSubview(titleContainerView)
        titleContainerView.snp.makeConstraints { make in
            make.left.equalTo(Constants.horizontalInset)
            make.top.equalTo(Constants.headerTop)
            make.bottom.equalToSuperview().offset(-Constants.headerBottom)
            make.right.lessThanOrEqualTo(actionButton.snp.left).offset(SCRXFrom(-12))
        }

        iconView.contentMode = .scaleAspectFit
        iconView.image = UIImage(named: iconImageName)
        titleContainerView.addSubview(iconView)
        iconView.snp.makeConstraints { make in
            make.left.centerY.equalToSuperview()
            make.width.height.equalTo(Constants.iconSize)
        }

        titleLabel.text = titleKey.localizedString
        titleLabel.textColor = RGB(30, 35, 41)
        titleLabel.font = UIFont.systemFont(ofSize: SCRYFrom(14), weight: .regular)
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.8
        titleContainerView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(iconView.snp.right).offset(SCRXFrom(8))
            make.centerY.equalToSuperview()
        }

        if kind == .functionTest {
            setupTagLabel()
        } else {
            titleLabel.snp.makeConstraints { make in
                make.right.equalToSuperview()
            }
        }
    }

    private func setupTagLabel() {
        tagLabel.text = "el_controller_function_test_tag".localizedString
        tagLabel.textColor = RGB(102, 103, 171)
        tagLabel.font = UIFont.systemFont(ofSize: SCRYFrom(12), weight: .regular)
        tagLabel.textAlignment = .center
        tagLabel.backgroundColor = RGB(102, 103, 171, 0.12)
        tagLabel.layer.cornerRadius = Constants.tagHeight * 0.5
        tagLabel.clipsToBounds = true
        titleContainerView.addSubview(tagLabel)
        tagLabel.snp.makeConstraints { make in
            make.left.equalTo(titleLabel.snp.right).offset(SCRXFrom(8))
            make.centerY.equalToSuperview()
            make.height.equalTo(Constants.tagHeight)
            make.width.equalTo(SCRXFrom(28))
            make.right.equalToSuperview()
        }
    }

    private func setupStateStackView() {
        stateStackView.axis = .vertical
        stateStackView.spacing = Constants.rowSpacing
        addSubview(stateStackView)
        stateStackView.snp.makeConstraints { make in
            make.top.equalTo(headerView.snp.bottom)
            make.left.equalTo(Constants.horizontalInset)
            make.right.equalToSuperview().offset(-Constants.horizontalInset)
            make.bottom.equalToSuperview().offset(-Constants.stateBottom)
        }
    }

    private var iconImageName: String {
        switch kind {
        case .functionTest:
            return "function_test_icon"
        case .rxTxCable:
            return "rx_tx_cable_icon"
        }
    }

    private var titleKey: String {
        switch kind {
        case .functionTest:
            return "el_controller_function_test_title"
        case .rxTxCable:
            return "el_controller_rxtx_title"
        }
    }

    func applyFunctionTestState(_ state: FunctionTestState) {
        guard kind == .functionTest else { return }
        currentState = Self.functionTestDisplayState(state)
        applyCurrentState()
    }

    func applyRxTxState(_ state: RxTxState) {
        guard kind == .rxTxCable else { return }
        currentState = Self.rxTxDisplayState(state)
        applyCurrentState()
    }

    @objc private func actionButtonTapped() {
        guard actionButton.isEnabled else { return }
        onAction?()
    }

    private func applyCurrentState() {
        let state = currentState
        actionButton.setTitle(state.buttonTitleKey.localizedString, for: .normal)
        actionButton.alpha = state.buttonAlpha
        actionButton.isEnabled = !state.showsSpinner
        rebuildRows(state.rows, showsSpinner: state.showsSpinner)
        setNeedsLayout()
    }

    private func rebuildRows(_ rows: [DisplayRow], showsSpinner: Bool) {
        stateStackView.arrangedSubviews.forEach { view in
            stateStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        rows.enumerated().forEach { index, row in
            let isSingleRow = rows.count == 1
            let rowView = makeRowView(row, showsSpinner: showsSpinner && index == 0, isSingleRow: isSingleRow)
            stateStackView.addArrangedSubview(rowView)
            rowView.snp.makeConstraints { make in
                make.height.equalTo(isSingleRow ? Constants.singleStateHeight : Constants.faultStateHeight)
            }
        }
    }

    private func makeRowView(_ row: DisplayRow, showsSpinner: Bool, isSingleRow: Bool) -> UIView {
        let rowView = UIView()
        rowView.backgroundColor = backgroundColor(for: row.style)
        rowView.layer.cornerRadius = Constants.stateCornerRadius
        rowView.clipsToBounds = true

        let contentStack = UIStackView()
        contentStack.axis = .horizontal
        contentStack.alignment = .center
        contentStack.spacing = SCRXFrom(8)
        rowView.addSubview(contentStack)
        contentStack.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.left.greaterThanOrEqualToSuperview().offset(SCRXFrom(16))
            make.right.lessThanOrEqualToSuperview().offset(SCRXFrom(-16))
        }

        if showsSpinner {
            let spinner = PJEightKeySwitchWaitingSpinnerView()
            spinner.setContentHuggingPriority(.required, for: .horizontal)
            contentStack.addArrangedSubview(spinner)
            spinner.snp.makeConstraints { make in
                make.width.height.equalTo(Constants.spinnerSize)
            }
            spinner.startAnimating()
        }

        let label = UILabel()
        label.text = row.titleKey.localizedString
        label.textColor = textColor(for: row.style)
        label.font = UIFont.systemFont(ofSize: SCRYFrom(fontSize(for: row.style, isSingleRow: isSingleRow)), weight: .regular)
        label.textAlignment = .center
        label.numberOfLines = 1
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.75
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        contentStack.addArrangedSubview(label)

        return rowView
    }

    private func fontSize(for style: DisplayStyle, isSingleRow: Bool) -> CGFloat {
        switch style {
        case .neutral, .waiting:
            return 12
        case .success, .warning, .fault:
            return isSingleRow ? 14 : 14
        }
    }

    private func backgroundColor(for style: DisplayStyle) -> UIColor {
        switch style {
        case .neutral:
            return RGB(239, 239, 244)
        case .waiting:
            return RGB(102, 103, 171, 0.08)
        case .success:
            return RGB(52, 199, 89, 0.10)
        case .warning:
            return RGB(255, 149, 0, 0.10)
        case .fault:
            return RGB(255, 59, 48, 0.10)
        }
    }

    private func textColor(for style: DisplayStyle) -> UIColor {
        switch style {
        case .neutral:
            return RGB(148, 163, 184)
        case .waiting:
            return RGB(102, 103, 171)
        case .success:
            return RGB(0, 209, 124)
        case .warning:
            return RGB(255, 149, 0)
        case .fault:
            return RGB(255, 72, 49)
        }
    }
}
