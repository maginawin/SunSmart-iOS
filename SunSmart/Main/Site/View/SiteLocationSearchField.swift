import UIKit

/// Shared creation form picker. Text only filters; an accepted list tap is the only commit path.
final class SiteLocationSearchField: UIView {
    struct Option { let id: String; let title: String; let detail: String? }
    struct Page { let options: [Option]; let emptyText: String }
    var prepareForInteraction: (() -> Bool)?
    var onSelect: ((Option) -> Bool)?
    var loadOptions: ((String, @escaping (Result<Page, Error>) -> Void) -> Void)?
    var canAcceptResults: (() -> Bool)?
    var onLayoutChanged: (() -> Void)?
    var onCancel: (() -> Void)?
    weak var animationLayoutView: UIView?

    let searchField = UITextField()
    private let panelContainer = UIView()
    private let panel = UIView()
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let emptyLabel = UILabel()
    private let iconName: String
    private let titleKey: String
    private let searchKey: String
    private let accessibilityPrefix: String
    private var selectedTitle: String?
    private var state: SiteLocationSearchState
    private var results: [Option] = []
    private var displayedTicket: SiteLocationSearchState.Ticket?
    private var presentedExpanded = false

    var isExpanded: Bool { state.isExpanded }

    init(iconName: String, titleKey: String, searchKey: String, accessibilityPrefix: String,
         selectedID: String? = nil, selectedTitle: String? = nil, context: String) {
        self.iconName = iconName
        self.titleKey = titleKey
        self.searchKey = searchKey
        self.accessibilityPrefix = accessibilityPrefix
        self.selectedTitle = selectedTitle
        state = SiteLocationSearchState(selectedID: selectedID, context: context)
        super.init(frame: .zero)
        setupLayout()
        updatePresentation(animated: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Used for outside taps, focus changes, Return, backgrounding and submission.
    func cancelSearch(animated: Bool = true) {
        // Close first so resignFirstResponder's didEndEditing callback is harmless.
        state.dismiss()
        onCancel?()
        updatePresentation(animated: animated)
        searchField.resignFirstResponder()
    }

    func replaceSelection(id: String?, title: String?, context: String) {
        state.replaceSelection(id: id, context: context)
        selectedTitle = title
        onCancel?()
        updatePresentation(animated: false)
        searchField.resignFirstResponder()
    }

    private func setupLayout() {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 0
        addSubview(stack)
        stack.snp.makeConstraints { make in make.edges.equalToSuperview() }

        let input = UIView()
        input.backgroundColor = .white
        input.layer.cornerRadius = SCRYFrom(10)
        input.layer.borderWidth = 0.5
        input.layer.borderColor = RGB(220, 220, 220).cgColor
        stack.addArrangedSubview(input)
        input.snp.makeConstraints { make in make.height.equalTo(SCRYFrom(44)) }
        let icon = UIImageView(image: UIImage(named: iconName))
        icon.contentMode = .scaleAspectFit
        input.addSubview(icon)
        icon.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(14))
            make.centerY.equalToSuperview()
            make.width.height.equalTo(SCRYFrom(iconName == "site_create_location" ? 16 : 13.5))
        }

        searchField.font = UIFont.systemFont(ofSize: SCRYFrom(14), weight: .light)
        searchField.textColor = RGB(30, 35, 41)
        searchField.tintColor = Bar_Color
        searchField.clearButtonMode = .whileEditing
        searchField.autocorrectionType = .no
        searchField.spellCheckingType = .no
        searchField.autocapitalizationType = .none
        searchField.returnKeyType = .done
        searchField.accessibilityIdentifier = accessibilityPrefix + "-search"
        searchField.accessibilityLabel = titleKey.localizedString
        searchField.delegate = self
        searchField.addTarget(self, action: #selector(queryChanged), for: .editingChanged)
        input.addSubview(searchField)
        searchField.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(40.5))
            make.top.bottom.equalToSuperview()
            make.right.equalToSuperview().inset(SCRXFrom(10))
        }
        let tap = UITapGestureRecognizer(target: self, action: #selector(focusInput))
        tap.cancelsTouchesInView = false
        tap.delaysTouchesBegan = false
        tap.delaysTouchesEnded = false
        tap.delegate = self
        input.addGestureRecognizer(tap)

        panel.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        panel.layer.cornerRadius = SCRYFrom(8)
        panel.clipsToBounds = true
        panel.alpha = 0
        panel.accessibilityIdentifier = accessibilityPrefix + "-options"
        // Keep the list at its final height and reveal it through a clipping container.
        // Animating this height avoids UIStackView hidden-state races on rapid toggles.
        panelContainer.clipsToBounds = true
        stack.addArrangedSubview(panelContainer)
        panelContainer.snp.makeConstraints { make in make.height.equalTo(0) }
        panelContainer.addSubview(panel)
        panel.snp.makeConstraints { make in
            make.top.equalTo(SCRYFrom(2))
            make.left.right.equalToSuperview()
            make.height.equalTo(SCRYFrom(204))
        }
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = SCRYFrom(40)
        tableView.contentInsetAdjustmentBehavior = .never
        tableView.keyboardDismissMode = .none
        tableView.delaysContentTouches = false
        tableView.sectionHeaderTopPadding = 0
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(SiteLocationSearchCell.self, forCellReuseIdentifier: "option")
        panel.addSubview(tableView)
        tableView.snp.makeConstraints { make in make.edges.equalToSuperview().inset(SCRYFrom(4)) }
        emptyLabel.font = UIFont.systemFont(ofSize: SCRYFrom(13))
        emptyLabel.textColor = .white
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        panel.addSubview(emptyLabel)
        emptyLabel.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.left.right.equalToSuperview().inset(SCRXFrom(20))
        }
    }

    @objc private func focusInput() {
        if !searchField.isFirstResponder { searchField.becomeFirstResponder() }
    }

    @objc private func queryChanged() {
        guard searchField.markedTextRange == nil else { return }
        state.updateQuery(searchField.text ?? "", isComposing: false)
        updateResults()
    }

    private func updateResults() {
        let ticket = state.ticket
        results = []
        displayedTicket = nil
        tableView.reloadData()
        tableView.setContentOffset(.zero, animated: false)
        emptyLabel.text = "site_create_location_loading".localizedString
        emptyLabel.isHidden = false
        loadOptions?(state.query) { [weak self] result in
            guard let self, self.state.accepts(ticket), self.canAcceptResults?() == true else { return }
            switch result {
            case .success(let page):
                self.results = page.options
                self.displayedTicket = ticket
                self.emptyLabel.text = page.emptyText
            case .failure:
                self.results = []
                self.emptyLabel.text = "site_create_location_load_failed".localizedString
            }
            self.tableView.reloadData()
            self.tableView.setContentOffset(.zero, animated: false)
            self.emptyLabel.isHidden = !self.results.isEmpty
        }
    }

    private func updatePresentation(animated: Bool = true) {
        panelContainer.isUserInteractionEnabled = isExpanded
        panelContainer.accessibilityElementsHidden = !isExpanded
        let placeholder = isExpanded ? searchKey : "site_time_zone_not_configured"
        searchField.attributedPlaceholder = NSAttributedString(string: placeholder.localizedString,
                                                               attributes: [.foregroundColor: RGB(148, 163, 184)])
        if isExpanded {
            searchField.text = state.query
        } else {
            searchField.text = selectedTitle
        }

        // Repeated close/focus callbacks must not restart or snap an active transition.
        guard presentedExpanded != isExpanded else { return }
        presentedExpanded = isExpanded
        let expanded = isExpanded
        let layoutView = animationLayoutView ?? superview ?? self
        layoutView.layoutIfNeeded()
        panelContainer.snp.updateConstraints { make in make.height.equalTo(expanded ? SCRYFrom(206) : 0) }
        let updates = {
            self.panel.alpha = expanded ? 1 : 0
            layoutView.layoutIfNeeded()
            self.onLayoutChanged?()
        }
        if animated, window != nil, !UIAccessibility.isReduceMotionEnabled {
            UIView.animate(withDuration: expanded ? 0.24 : 0.20, delay: 0,
                           options: [.curveEaseInOut, .beginFromCurrentState, .allowUserInteraction], animations: updates)
        } else {
            UIView.performWithoutAnimation(updates)
        }
    }
}

extension SiteLocationSearchField: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // UITextField owns its text/clear touches. Only the icon and margins need forwarding;
        // forwarding a rejected text-field tap as well would show the country-required tip twice.
        touch.view?.isDescendant(of: searchField) != true
    }
}

extension SiteLocationSearchField: UITextFieldDelegate {
    func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool { prepareForInteraction?() == true }

    func textFieldDidBeginEditing(_ textField: UITextField) {
        state.beginSearch()
        updateResults()
        updatePresentation()
    }

    func textFieldDidEndEditing(_ textField: UITextField) { cancelSearch() }

    func textFieldShouldClear(_ textField: UITextField) -> Bool {
        // UIKit clears the text; reset only the filter and keep the confirmed identity.
        state.updateQuery("", isComposing: false)
        updateResults()
        return true
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        cancelSearch()
        return true
    }
}

extension SiteLocationSearchField: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { results.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "option", for: indexPath) as! SiteLocationSearchCell
        let entry = results[indexPath.row]
        cell.configure(name: entry.title, detail: entry.detail, identifier: accessibilityPrefix + "-" + entry.id,
                       selected: entry.id == state.selectedID, isLast: indexPath.row == results.count - 1,
                       width: tableView.bounds.width)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard isExpanded, displayedTicket == state.ticket, canAcceptResults?() == true,
              results.indices.contains(indexPath.row) else { return }
        let entry = results[indexPath.row]
        // The owner checks account/context and writes its draft before presentation closes.
        guard onSelect?(entry) == true else { cancelSearch(); return }
        selectedTitle = entry.title
        state.select(id: entry.id)
        updatePresentation()
        searchField.resignFirstResponder()
    }
}

private final class SiteLocationSearchCell: UITableViewCell {
    private let nameLabel = UILabel()
    private let detailLabel = UILabel()
    private let labels = UIStackView()
    private let highlight = UIView()
    private var measuredWidth: CGFloat?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none
        highlight.layer.cornerRadius = SCRYFrom(5)
        highlight.isUserInteractionEnabled = false
        contentView.addSubview(highlight)
        highlight.snp.makeConstraints { make in
            make.top.left.right.equalToSuperview()
            make.bottom.equalToSuperview().offset(-SCRYFrom(4))
        }
        for label in [nameLabel, detailLabel] {
            label.font = UIFont.systemFont(ofSize: SCRYFrom(13))
            label.numberOfLines = 0
            label.lineBreakMode = .byWordWrapping
            label.setContentCompressionResistancePriority(.required, for: .vertical)
        }
        nameLabel.textColor = .white
        detailLabel.textColor = UIColor.white.withAlphaComponent(0.6)
        detailLabel.textAlignment = .right
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        detailLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        labels.axis = .horizontal
        // Both labels get the full measured text height. UILabel centers shorter text vertically.
        labels.alignment = .fill
        labels.spacing = SCRXFrom(12)
        labels.addArrangedSubview(nameLabel)
        labels.addArrangedSubview(detailLabel)
        contentView.addSubview(labels)
        detailLabel.snp.makeConstraints { make in make.width.equalTo(0) }
        labels.snp.makeConstraints { make in
            make.left.right.equalToSuperview().inset(SCRXFrom(20))
            make.top.equalTo(SCRYFrom(7))
            make.bottom.equalToSuperview().offset(-SCRYFrom(11))
            make.height.equalTo(SCRYFrom(22))
        }
        isAccessibilityElement = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func systemLayoutSizeFitting(_ targetSize: CGSize,
                                         withHorizontalFittingPriority horizontalFittingPriority: UILayoutPriority,
                                         verticalFittingPriority: UILayoutPriority) -> CGSize {
        updateTextLayout(width: targetSize.width)
        return super.systemLayoutSizeFitting(targetSize, withHorizontalFittingPriority: horizontalFittingPriority,
                                             verticalFittingPriority: verticalFittingPriority)
    }

    override func layoutSubviews() {
        updateTextLayout(width: bounds.width)
        super.layoutSubviews()
    }

    private func updateTextLayout(width: CGFloat) {
        guard width > SCRXFrom(40), measuredWidth != width else { return }
        measuredWidth = width
        let availableWidth = width - SCRXFrom(40)
        // Measure the country first, then give the remaining width to the full city title.
        // Do not let a previous reuse/width's intrinsic size determine either column's height.
        detailLabel.preferredMaxLayoutWidth = 0
        let detailWidth = detailLabel.isHidden ? 0 : min(availableWidth * 0.45, ceil(detailLabel.sizeThatFits(
            CGSize(width: availableWidth * 0.45, height: .greatestFiniteMagnitude)).width))
        let nameWidth = max(1, availableWidth - detailWidth - (detailLabel.isHidden ? 0 : labels.spacing))
        nameLabel.preferredMaxLayoutWidth = nameWidth
        detailLabel.preferredMaxLayoutWidth = detailWidth
        let nameHeight = nameLabel.sizeThatFits(CGSize(width: nameWidth, height: .greatestFiniteMagnitude)).height
        let detailHeight = detailLabel.isHidden ? 0 : detailLabel.sizeThatFits(
            CGSize(width: detailWidth, height: .greatestFiniteMagnitude)).height
        detailLabel.snp.updateConstraints { make in make.width.equalTo(detailWidth) }
        labels.snp.updateConstraints { make in make.height.equalTo(ceil(max(SCRYFrom(22), nameHeight, detailHeight))) }
    }

    func configure(name: String, detail: String?, identifier: String, selected: Bool, isLast: Bool, width: CGFloat) {
        nameLabel.text = name
        detailLabel.isHidden = detail == nil
        detailLabel.text = detail
        measuredWidth = nil
        updateTextLayout(width: width)
        highlight.backgroundColor = selected ? UIColor.white.withAlphaComponent(0.1) : .clear
        highlight.snp.updateConstraints { make in make.bottom.equalToSuperview().offset(isLast ? 0 : -SCRYFrom(4)) }
        labels.snp.updateConstraints { make in make.bottom.equalToSuperview().offset(-SCRYFrom(isLast ? 7 : 11)) }
        accessibilityLabel = [name, detail].compactMap { $0 }.joined(separator: ", ")
        accessibilityIdentifier = identifier
        accessibilityTraits = selected ? [.button, .selected] : .button
    }
}
