//
//  PJEightKeySwitchMoreSettingsController.swift
//  SunSmart
//
//  Created by Plato Jobs.
//

import UIKit

final class PJEightKeySwitchMoreSettingsController: UIViewController {

    var settingsChanged: ((PJEightKeySwitchMoreSettingsViewModel.State) -> Void)?

    private var viewModel: PJEightKeySwitchMoreSettingsViewModel

    private lazy var scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.backgroundColor = .clear
        scrollView.showsVerticalScrollIndicator = false
        return scrollView
    }()

    private lazy var contentView = UIView()

    private lazy var periodicCardView: UIView = {
        let view = UIView()
        view.backgroundColor = .white
        view.layer.cornerRadius = 12
        return view
    }()

    private lazy var periodicTitleLabel: UILabel = {
        UILabel(text: viewModel.periodicReportingTitle, textColor: Title_Color, fontSize: 16, fontWeight: .light)
    }()

    private lazy var periodicDescriptionLabel: UILabel = {
        let label = UILabel(text: viewModel.periodicReportingDescription, textColor: SubText_Color, fontSize: 14, fontWeight: .light)
        label.numberOfLines = 0
        return label
    }()

    private lazy var periodicSliderView = PJEightKeySwitchPeriodicReportingSliderView(
        options: viewModel.periodicReportingOptions,
        selectedOption: viewModel.state.periodicReporting
    )

    private lazy var ledCardView: UIView = {
        let view = UIView()
        view.backgroundColor = .white
        view.layer.cornerRadius = 12
        return view
    }()

    private lazy var ledTitleLabel: UILabel = {
        UILabel(text: viewModel.ledIndicatorTitle, textColor: Title_Color, fontSize: 16, fontWeight: .light)
    }()

    private lazy var ledDescriptionLabel: UILabel = {
        let label = UILabel(text: viewModel.ledIndicatorDescription, textColor: SubText_Color, fontSize: 14, fontWeight: .light)
        label.numberOfLines = 0
        return label
    }()

    private lazy var ledSwitch: UISwitch = {
        let switchControl = UISwitch()
        switchControl.onTintColor = Bar_Color
        switchControl.isOn = viewModel.state.ledIndicatorEnabled
        switchControl.addTarget(self, action: #selector(ledIndicatorChanged(_:)), for: .valueChanged)
        return switchControl
    }()

    init(state: PJEightKeySwitchMoreSettingsViewModel.State) {
        self.viewModel = PJEightKeySwitchMoreSettingsViewModel(state: state)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupNavigation()
        setupUI()
        bindActions()
    }

    private func setupNavigation() {
        title = "neightkeyswitches_more_settings".localizedString
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "done".localizedString.uppercased(),
            color: RGB(0, 0, 0, 0.85),
            font: UIFont.systemFont(ofSize: 16, weight: .light),
            target: self,
            sel: #selector(doneAction)
        )
    }

    private func setupUI() {
        view.backgroundColor = Background_Color

        view.addSubview(scrollView)
        scrollView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        scrollView.addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
            make.width.equalTo(scrollView)
        }

        contentView.addSubview(periodicCardView)
        periodicCardView.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top).offset(SCRYFrom(16))
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
        }

        periodicCardView.addSubview(periodicTitleLabel)
        periodicTitleLabel.snp.makeConstraints { make in
            make.top.equalTo(SCRYFrom(16))
            make.left.equalTo(SCRXFrom(16))
            make.right.lessThanOrEqualTo(SCRXFrom(-16))
        }

        periodicCardView.addSubview(periodicDescriptionLabel)
        periodicDescriptionLabel.snp.makeConstraints { make in
            make.top.equalTo(periodicTitleLabel.snp.bottom).offset(SCRYFrom(10))
            make.left.right.equalTo(periodicTitleLabel)
        }

        periodicCardView.addSubview(periodicSliderView)
        periodicSliderView.snp.makeConstraints { make in
            make.top.equalTo(periodicDescriptionLabel.snp.bottom).offset(SCRYFrom(20))
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.height.equalTo(SCRYFrom(72))
            make.bottom.equalTo(SCRYFrom(-18))
        }

        contentView.addSubview(ledCardView)
        ledCardView.snp.makeConstraints { make in
            make.top.equalTo(periodicCardView.snp.bottom).offset(SCRYFrom(16))
            make.left.right.equalTo(periodicCardView)
            make.bottom.equalTo(SCRYFrom(-24))
        }

        ledCardView.addSubview(ledTitleLabel)
        ledTitleLabel.snp.makeConstraints { make in
            make.top.equalTo(SCRYFrom(16))
            make.left.equalTo(SCRXFrom(16))
        }

        ledCardView.addSubview(ledSwitch)
        ledSwitch.snp.makeConstraints { make in
            make.centerY.equalTo(ledTitleLabel)
            make.right.equalTo(SCRXFrom(-16))
        }

        ledCardView.addSubview(ledDescriptionLabel)
        ledDescriptionLabel.snp.makeConstraints { make in
            make.top.equalTo(ledTitleLabel.snp.bottom).offset(SCRYFrom(10))
            make.left.equalTo(ledTitleLabel)
            make.right.equalTo(SCRXFrom(-16))
            make.bottom.equalTo(SCRYFrom(-16))
        }
    }

    private func bindActions() {
        periodicSliderView.valueChanged = { [weak self] option in
            self?.viewModel.state.periodicReporting = option
        }
    }

    @objc private func doneAction() {
        settingsChanged?(viewModel.state)
        navigationController?.popViewController(animated: true)
    }

    @objc private func ledIndicatorChanged(_ sender: UISwitch) {
        viewModel.state.ledIndicatorEnabled = sender.isOn
    }
}
