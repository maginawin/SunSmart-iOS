import UIKit

/// A row never controls a lamp. Selection/settings/Identify have separate hit targets.
final class SceneDeviceSettingsCell: UITableViewCell {
    let checkButton = UIButton(type: .custom)
    let deviceIcon = UIImageView()
    let nameLabel = UILabel()
    let parametersLabel = UILabel()
    let settingsButton = UIButton(type: .custom)
    let identifyButton = UIButton(type: .custom)
    let savedSeparator = UIView()
    var onSelect: (() -> Void)?
    var onSettings: (() -> Void)?
    var onIdentify: (() -> Void)?
    private let row = UIStackView()
    private let labels = UIStackView()
    private let leadingIcons = UIStackView()
    private let actions = UIStackView()
    private var layoutMode: Int?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none; backgroundColor = .clear
        nameLabel.font = .systemFont(ofSize: 12, weight: .light); nameLabel.numberOfLines = 0
        nameLabel.textColor = TextBlack_Color
        parametersLabel.font = .systemFont(ofSize: 12, weight: .light); parametersLabel.numberOfLines = 0
        parametersLabel.textColor = RGB(148, 163, 184)
        deviceIcon.contentMode = .scaleAspectFit
        checkButton.setImage(UIImage(named: "device_select_un"), for: .normal)
        checkButton.setImage(UIImage(named: "device_select"), for: .selected)
        settingsButton.setImage(UIImage(named: "settings"), for: .normal)
        identifyButton.setImage(UIImage(named: "device_identify"), for: .normal)
        settingsButton.accessibilityLabel = "settings".localizedString
        identifyButton.accessibilityLabel = "identify".localizedString
        checkButton.addTarget(self, action: #selector(selectAction), for: .touchUpInside)
        settingsButton.addTarget(self, action: #selector(settingsAction), for: .touchUpInside)
        identifyButton.addTarget(self, action: #selector(identifyAction), for: .touchUpInside)
        labels.addArrangedSubview(nameLabel); labels.addArrangedSubview(parametersLabel)
        labels.axis = .vertical; labels.spacing = 2
        row.alignment = .center
        contentView.addSubview(row)
        savedSeparator.backgroundColor = RGB(193, 207, 226, 0.3)
        savedSeparator.isHidden = true
        contentView.addSubview(savedSeparator)
        savedSeparator.snp.makeConstraints { make in make.left.right.bottom.equalToSuperview(); make.height.equalTo(0.5) }
        configureLayout(editor: false, selecting: false)
    }
    func configureLayout(editor: Bool, selecting: Bool, saved: Bool = false) {
        let mode = saved ? 3 : (editor ? (selecting ? 1 : 2) : 0)
        guard mode != layoutMode else { return }; layoutMode = mode
        [row, leadingIcons, actions].forEach { stack in
            stack.arrangedSubviews.forEach { stack.removeArrangedSubview($0); $0.removeFromSuperview() }
        }
        row.spacing = saved ? 12 : (editor ? 10 : 6)
        labels.spacing = editor || saved ? 0 : 2
        nameLabel.numberOfLines = editor ? 1 : 0
        parametersLabel.numberOfLines = editor ? 1 : 0
        nameLabel.snp.remakeConstraints { make in
            if saved { make.height.greaterThanOrEqualTo(20) }
            else if editor { make.height.equalTo(20) }
        }
        parametersLabel.snp.remakeConstraints { make in
            if saved { make.height.greaterThanOrEqualTo(16) }
            else if editor { make.height.equalTo(16).priority(999) }
        }
        savedSeparator.isHidden = !saved
        [checkButton, settingsButton, identifyButton].forEach { $0.isHidden = saved }
        if saved {
            [deviceIcon, labels].forEach(row.addArrangedSubview)
            onSelect = nil; onSettings = nil; onIdentify = nil
        } else if editor {
            if selecting { leadingIcons.addArrangedSubview(checkButton) }
            leadingIcons.addArrangedSubview(deviceIcon)
            actions.spacing = 8
            actions.addArrangedSubview(settingsButton)
            if !selecting { actions.addArrangedSubview(checkButton) }
            actions.addArrangedSubview(identifyButton)
            [leadingIcons, labels, actions].forEach(row.addArrangedSubview)
        } else {
            [checkButton, deviceIcon, labels, settingsButton, identifyButton].forEach(row.addArrangedSubview)
        }
        row.snp.remakeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: saved ? 12 : 8, left: editor || saved ? 16 : 12,
                bottom: saved ? 12 : 8, right: editor || saved ? 16 : 12))
        }
        [checkButton, settingsButton, identifyButton].forEach { button in
            button.snp.remakeConstraints { make in make.width.equalTo(editor ? 30 : 36); make.height.equalTo(editor ? 30 : 44) }
            button.imageView?.contentMode = .scaleAspectFit
        }
        deviceIcon.snp.remakeConstraints { make in make.width.height.equalTo(editor || saved ? 30 : 26) }
        settingsButton.setImage(UIImage(named: editor ? "scene_editor_settings" : "settings"), for: .normal)
        identifyButton.setImage(UIImage(named: editor ? "scene_editor_identify" : "device_identify"), for: .normal)
        backgroundColor = saved ? .white : (editor ? RGB(250, 250, 252) : .clear)
        clipsToBounds = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func prepareForReuse() { super.prepareForReuse(); onSelect = nil; onSettings = nil; onIdentify = nil }
    @objc private func selectAction() { onSelect?() }
    @objc private func settingsAction() { onSettings?() }
    @objc private func identifyAction() { onIdentify?() }
}
