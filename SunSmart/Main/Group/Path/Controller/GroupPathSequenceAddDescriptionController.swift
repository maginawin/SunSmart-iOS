//
//  GroupPathSequenceAddDescriptionController.swift
//  SunSmart
//
//  Created by Codex on 2026/3/31.
//

import UIKit

enum GroupPathSequenceAddDescriptionMode {
    case quickAdd
    case triggerAdd
    case manuallyAdd

    var title: String {
        switch self {
        case .quickAdd:
            return "quick_add".localizedString
        case .triggerAdd:
            return "trigger_add".localizedString
        case .manuallyAdd:
            return "manually_add".localizedString
        }
    }

    var subtitle: String {
        switch self {
        case .quickAdd:
            return "path_add_description_quick_subtitle".localizedString
        case .triggerAdd:
            return "path_add_description_trigger_subtitle".localizedString
        case .manuallyAdd:
            return "path_add_description_manual_subtitle".localizedString
        }
    }

    var body: String {
        switch self {
        case .quickAdd:
            return "path_add_description_quick_body".localizedString
        case .triggerAdd:
            return "path_add_description_trigger_body".localizedString
        case .manuallyAdd:
            return "path_add_description_manual_body".localizedString
        }
    }

    var steps: [String] {
        switch self {
        case .quickAdd:
            return [
                "path_add_description_quick_step1".localizedString,
                "path_add_description_quick_step2".localizedString,
                "path_add_description_quick_step3".localizedString,
                "path_add_description_quick_step4".localizedString
            ]
        case .triggerAdd:
            return [
                "path_add_description_trigger_step1".localizedString,
                "path_add_description_trigger_step2".localizedString,
                "path_add_description_trigger_step3".localizedString,
                "path_add_description_trigger_step4".localizedString
            ]
        case .manuallyAdd:
            return [
                "path_add_description_manual_step1".localizedString,
                "path_add_description_manual_step2".localizedString,
                "path_add_description_manual_step3".localizedString,
                "path_add_description_manual_step4".localizedString
            ]
        }
    }

    var bestFor: String {
        switch self {
        case .quickAdd:
            return "path_add_description_quick_best_for".localizedString
        case .triggerAdd:
            return "path_add_description_trigger_best_for".localizedString
        case .manuallyAdd:
            return "path_add_description_manual_best_for".localizedString
        }
    }

    var illustrationImageName: String {
        switch self {
        case .quickAdd:
            return "path_quick_add"
        case .triggerAdd:
            return "path_trigger_add"
        case .manuallyAdd:
            return "path_manually_add"
        }
    }
}

final class GroupPathSequenceAddDescriptionController: UIViewController {
    private let mode: GroupPathSequenceAddDescriptionMode
    private let isSequence: Bool

    private var scrollView: UIScrollView!
    private var contentView: UIView!
    private var stackView: UIStackView!

    init(mode: GroupPathSequenceAddDescriptionMode, isSequence: Bool) {
        self.mode = mode
        self.isSequence = isSequence
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    static func push(mode: GroupPathSequenceAddDescriptionMode, isSequence: Bool) {
        guard let visibleVc = UIViewController.getVisibleVc() else {
            return
        }
        let vc = GroupPathSequenceAddDescriptionController(mode: mode, isSequence: isSequence)
        visibleVc.navigationController?.pushViewController(vc, animated: true)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        navigationItem.title = mode.title
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(named: "close")?.withRenderingMode(.alwaysOriginal), style: .plain, target: self, action: #selector(closeAction))
        
        view.backgroundColor = Background_Color
        setupUI()
    }

    @objc private func closeAction() {
        if let nav = navigationController, nav.viewControllers.first !== self {
            nav.popViewController(animated: true)
        } else {
            dismiss(animated: true)
        }
    }

    private func setupUI() {

        scrollView = UIScrollView()
        scrollView.showsVerticalScrollIndicator = false
        view.addSubview(scrollView)
        scrollView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.top.equalTo(view.safeAreaLayoutGuide).offset(SCRYFrom(7))
        }

        contentView = UIView()
        scrollView.addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
            make.width.equalToSuperview()
        }

        stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = SCRYFrom(16)
        contentView.addSubview(stackView)
        stackView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.right.equalTo(SCRXFrom(-20))
            make.top.equalToSuperview().offset(SCRYFrom(4))
            make.bottom.equalToSuperview().offset(SCRYFrom(-24))
        }

        stackView.addArrangedSubview(makeEligibleSection())
        stackView.addArrangedSubview(makeModeSection())
        stackView.addArrangedSubview(makeDivider())
        stackView.addArrangedSubview(makeProfilesSection())
    }

    private func makeEligibleSection() -> UIView {
        let section = UIStackView()
        section.axis = .vertical
        section.spacing = SCRYFrom(8)

        let titleLabel = UILabel(text: "path_add_description_eligible_title".localizedString, textColor: ImportantText_Color, fontSize: 15, fontWeight: .regular)
        titleLabel.numberOfLines = 0
        section.addArrangedSubview(titleLabel)

        let messageKey = isSequence ? "path_add_description_eligible_message_path" : "path_add_description_eligible_message_zone"
        let messageLabel = UILabel(text: messageKey.localizedString, textColor: Title_Color, fontSize: 14, fontWeight: .light, fit: false)
        messageLabel.numberOfLines = 0
        section.addArrangedSubview(messageLabel)

        return section
    }

    private func makeModeSection() -> UIView {
        let section = UIStackView()
        section.axis = .vertical
        section.spacing = SCRYFrom(8)

        let titleRow = UIStackView()
        titleRow.axis = .horizontal
        titleRow.alignment = .lastBaseline
        titleRow.spacing = SCRXFrom(6)

        let titleLabel = UILabel(text: mode.title, textColor: RGB(27, 20, 37), fontSize: 15, fontWeight: .regular)
        titleRow.addArrangedSubview(titleLabel)

        let subtitleLabel = UILabel(text: mode.subtitle, textColor: AssistText_Color, fontSize: 12, fontWeight: .light)
        titleRow.addArrangedSubview(subtitleLabel)
        titleRow.addArrangedSubview(UIView())
        section.addArrangedSubview(titleRow)

        let illustrationView = GroupPathSequenceAddDescriptionIllustrationView(mode: mode)
        section.addArrangedSubview(illustrationView)
        illustrationView.snp.makeConstraints { make in
            make.height.equalTo(SCRYFrom(136))
        }

        let bodyLabel = UILabel(text: mode.body, textColor: Title_Color, fontSize: 14, fontWeight: .light, fit: false)
        bodyLabel.numberOfLines = 0
        section.addArrangedSubview(bodyLabel)

        let stepsView = UIStackView()
        stepsView.axis = .vertical
        stepsView.spacing = SCRYFrom(2)
        for (index, step) in mode.steps.enumerated() {
            let label = UILabel(text: "\(index + 1). \(step)", textColor: AssistText_Color, fontSize: 12, fontWeight: .regular, fit: false)
            label.numberOfLines = 0
            stepsView.addArrangedSubview(label)
        }
        section.addArrangedSubview(stepsView)

        let bestForLabel = UILabel(text: nil, textColor: Message_Color, fontSize: 12, fontWeight: .regular, fit: false)
        bestForLabel.numberOfLines = 0
        bestForLabel.attributedText = mode.bestFor.attributedBestForText

        let bestForContainer = UIView()
        bestForContainer.backgroundColor = RGB(34, 197, 94, 0.06)
        bestForContainer.layer.cornerRadius = SCRYFrom(6)
        bestForContainer.addSubview(bestForLabel)
        bestForLabel.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: SCRYFrom(8), left: SCRXFrom(10), bottom: SCRYFrom(8), right: SCRXFrom(10)))
        }
        section.addArrangedSubview(bestForContainer)

        return section
    }

    private func makeDivider() -> UIView {
        let divider = GroupPathSequenceAddDescriptionDashedDividerView()
        divider.snp.makeConstraints { make in
            make.height.equalTo(1)
        }
        return divider
    }

    private func makeProfilesSection() -> UIView {
        let container = UIView()
        container.backgroundColor = RGB(239, 239, 244, 0.4)
        container.layer.cornerRadius = SCRYFrom(10)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = SCRYFrom(8)
        container.addSubview(stack)
        stack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: SCRYFrom(10), left: SCRXFrom(8), bottom: SCRYFrom(12), right: SCRXFrom(8)))
        }

        let titleLabel = UILabel(text: "path_add_description_profiles_title".localizedString, textColor: Message_Color, fontSize: 14, fontWeight: .regular, fit: false)
        titleLabel.numberOfLines = 0
        stack.addArrangedSubview(titleLabel)

        let tagsStack = UIStackView()
        tagsStack.axis = .vertical
        tagsStack.alignment = .leading
        tagsStack.spacing = SCRYFrom(6)
        tagsStack.addArrangedSubview(makeProfileTag("path_add_description_profile_1".localizedString))
        tagsStack.addArrangedSubview(makeProfileTag("path_add_description_profile_2".localizedString))
        stack.addArrangedSubview(tagsStack)

        return container
    }

    private func makeProfileTag(_ text: String) -> UIView {
        let label = UILabel(text: text, textColor: AssistText_Color, fontSize: 12, fontWeight: .regular)
        let container = UIView()
        container.snp.makeConstraints { make in
            make.width.greaterThanOrEqualTo(SCRXFrom(48))
        }
        container.layer.cornerRadius = SCRYFrom(5)
        container.layer.borderWidth = 1
        container.layer.borderColor = RGB(218, 228, 242).cgColor
        container.addSubview(label)
        label.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: SCRYFrom(3), left: SCRXFrom(8), bottom: SCRYFrom(3), right: SCRXFrom(8)))
        }
        return container
    }
}

private extension String {
    var attributedBestForText: NSAttributedString {
        let fullText = self
        let attributedText = NSMutableAttributedString(
            string: fullText,
            attributes: [
                .foregroundColor: Message_Color,
                .font: UIFont.systemFont(ofSize: 12, weight: .regular)
            ]
        )

        let separators = ["：", ":"]
        if let separator = separators.first(where: { fullText.contains($0) }),
           let range = fullText.range(of: separator) {
            let prefix = String(fullText[..<range.upperBound])
            attributedText.addAttributes(
                [.foregroundColor: TextBlack_Color],
                range: NSRange(location: 0, length: prefix.count)
            )
        }

        return attributedText
    }
}

private final class GroupPathSequenceAddDescriptionIllustrationView: UIView {
    private let mode: GroupPathSequenceAddDescriptionMode
    private let imageView = UIImageView()

    init(mode: GroupPathSequenceAddDescriptionMode) {
        self.mode = mode
        super.init(frame: .zero)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        imageView.image = UIImage(named: mode.illustrationImageName)
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        addSubview(imageView)
        imageView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }
}

private final class GroupPathSequenceAddDescriptionDashedDividerView: UIView {
    private let dashedLayer = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        dashedLayer.strokeColor = RGB(226, 232, 240).cgColor
        dashedLayer.fillColor = UIColor.clear.cgColor
        dashedLayer.lineWidth = 1
        dashedLayer.lineDashPattern = [2, 2]
        layer.addSublayer(dashedLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        dashedLayer.frame = bounds
        let y = bounds.height / 2
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 0, y: y))
        path.addLine(to: CGPoint(x: bounds.width, y: y))
        dashedLayer.path = path.cgPath
    }
}
