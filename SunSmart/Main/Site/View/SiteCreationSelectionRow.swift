import UIKit

/// Shared layout for the creation form's Time Zone, Site Type and location selectors.
final class SiteCreationSelectionRow: UIControl {
    let valueLabel = UILabel()
    let detailLabel = UILabel()

    init(iconName: String? = nil, showsArrow: Bool = true) {
        super.init(frame: .zero)
        backgroundColor = .white
        layer.cornerRadius = SCRYFrom(10)
        let stack = UIStackView()
        stack.alignment = .center
        stack.spacing = SCRXFrom(8)
        stack.isUserInteractionEnabled = false
        addSubview(stack)
        stack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: 0, left: SCRXFrom(16), bottom: 0, right: SCRXFrom(8)))
        }
        if let iconName {
            layer.borderColor = RGB(220, 220, 220).cgColor
            layer.borderWidth = 0.5
            let icon = UIImageView(image: UIImage(named: iconName))
            icon.contentMode = .scaleAspectFit
            stack.addArrangedSubview(icon)
            icon.snp.makeConstraints { make in make.width.height.equalTo(SCRYFrom(16)) }
        }
        valueLabel.font = UIFont.systemFont(ofSize: SCRYFrom(14), weight: .light)
        valueLabel.textColor = RGB(30, 35, 41)
        valueLabel.lineBreakMode = .byTruncatingMiddle
        stack.addArrangedSubview(valueLabel)
        detailLabel.font = UIFont.systemFont(ofSize: SCRYFrom(14), weight: .light)
        detailLabel.textColor = RGB(100, 116, 139)
        detailLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        detailLabel.isHidden = true
        stack.addArrangedSubview(detailLabel)
        if showsArrow {
            let arrow = UIImageView(image: UIImage(named: "arrow_light_right"))
            arrow.contentMode = .scaleAspectFit
            stack.addArrangedSubview(arrow)
            arrow.snp.makeConstraints { make in make.width.height.equalTo(SCRYFrom(30)) }
        }
        snp.makeConstraints { make in make.height.equalTo(SCRYFrom(44)) }
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
