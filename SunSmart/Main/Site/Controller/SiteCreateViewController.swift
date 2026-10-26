import UIKit

final class SiteCreateViewController: UIViewController {
    private var draft: SiteCreationDraft
    private let onCreated: (SiteData) -> Void
    private let account = UserData.currentUserId
    private let region = UserData.currentServerRegion
    private let allowsSiteType = FeatureVisibility.shared.canSelectSiteType
    private let scrollView = UIScrollView()
    private let form = UIStackView()
    private let footer = UIView()
    private let createButton = UIButton(type: .system)
    private let nameField = UITextField()
    private let nameTip = UILabel()
    private let timeZoneRow = SiteCreationSelectionRow()
    private let typeRow = SiteCreationSelectionRow()
    private let timeZoneCatalog: SiteTimeZoneCatalog?
    private lazy var countryCatalog = try? CountryRegionCatalog.bundled()
    private let cityLoader = CityCatalogLoader()
    private var activeCityCatalog: CityCatalog?
    private var language: String { Bundle.main.preferredLocalizations.first ?? "en" }
    private lazy var countryField = SiteLocationSearchField(
        iconName: "site_create_search", titleKey: "site_create_country", searchKey: "site_create_country_search_placeholder",
        accessibilityPrefix: "site-create-country", selectedID: draft.countryRegionCode,
        selectedTitle: countryCatalog?.displayName(forStoredCode: draft.countryRegionCode, language: language), context: "countries")
    private lazy var cityField = SiteLocationSearchField(
        iconName: "site_create_location", titleKey: "site_create_city", searchKey: "site_create_city_search_placeholder",
        accessibilityPrefix: "site-create-city", context: draft.countryRegionCode ?? "")
    private lazy var locationOutsideTap: UITapGestureRecognizer = {
        let gesture = UITapGestureRecognizer(target: self, action: #selector(cancelLocationSearchFromOutside))
        gesture.cancelsTouchesInView = false
        gesture.delaysTouchesBegan = false
        gesture.delaysTouchesEnded = false
        gesture.delegate = self
        return gesture
    }()
    private let localTimeLabel = UILabel()
    private let descriptionView = UITextView()
    private let descriptionPlaceholder = UILabel()
    private let descriptionCounter = UILabel()
    private var textFields: [SiteCreationTextField: UITextField] = [:]
    private let helpBody = UIStackView()
    private let helpArrow = UIImageView(image: UIImage(named: "site_create_disclosure"))
    private let helpButton = UIButton(type: .custom)
    private let flowLayout = UICollectionViewFlowLayout()
    private lazy var icons = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
    private var localTimeTimer: Timer?
    private weak var typeAlert: SiteTypeSelectionAlertView?
    private var isCommitting = false

    init(onCreated: @escaping (SiteData) -> Void) {
        let catalog = try? SiteTimeZoneCatalog.bundled()
        timeZoneCatalog = catalog
        let timezone = catalog?.value(matchingIdentifier: TimeZone.current.identifier)
        draft = SiteCreationDraft(siteName: SiteData.getNextSiteName(), timezone: timezone)
        self.onCreated = onCreated
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        localTimeTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "site_create_title".localizedString
        view.backgroundColor = RGB(248, 250, 252)
        navigationController?.setNavigationBarBackgroundColor(color: .clear)
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(named: "close")?.withRenderingMode(.alwaysOriginal),
            style: .done, target: self, action: #selector(close)
        ).withoutSharedBackground()
        setupLayout()
        setupFields()
        updateTimeZone()
        updateType()
        validateName()
        NotificationCenter.default.addObserver(self, selector: #selector(pauseForBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(resumeClock), name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(revealEditingField), name: UIResponder.keyboardDidChangeFrameNotification, object: nil)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard contextIsCurrent else { close(); return }
        (navigationController?.view ?? view).addGestureRecognizer(locationOutsideTap)
        resumeClock()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopClock()
        cancelLocationSearch(animated: false)
        locationOutsideTap.view?.removeGestureRecognizer(locationOutsideTap)
        typeAlert?.dismiss(animation: false)
    }

    private var contextIsCurrent: Bool {
        account == UserData.currentUserId && region == UserData.currentServerRegion
    }

    private func setupLayout() {
        footer.backgroundColor = .white
        view.addSubview(footer)
        footer.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.bottom.equalTo(view.safeAreaLayoutGuide.snp.bottom)
            make.height.equalTo(SCRYFrom(56))
        }
        let bottom = UIView()
        bottom.backgroundColor = .white
        view.addSubview(bottom)
        bottom.snp.makeConstraints { make in
            make.top.equalTo(footer.snp.bottom)
            make.left.right.bottom.equalToSuperview()
        }
        let line = UIView()
        line.backgroundColor = Line_Color
        footer.addSubview(line)
        line.snp.makeConstraints { make in make.left.right.top.equalToSuperview(); make.height.equalTo(0.5) }
        createButton.setTitle("site_create_action".localizedString, for: .normal)
        createButton.setTitleColor(Title_Color, for: .normal)
        createButton.setTitleColor(RGB(139, 139, 139), for: .disabled)
        createButton.titleLabel?.font = UIFont.systemFont(ofSize: SCRYFrom(16), weight: .light)
        createButton.accessibilityIdentifier = "site-create-submit"
        createButton.addTarget(self, action: #selector(create), for: .touchUpInside)
        footer.addSubview(createButton)
        createButton.snp.makeConstraints { make in make.edges.equalToSuperview() }
        scrollView.keyboardDismissMode = .onDrag
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)
        scrollView.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide)
            make.left.right.equalToSuperview()
            // Only the form follows the keyboard; the footer stays at the screen bottom.
            make.bottom.lessThanOrEqualTo(footer.snp.top)
            make.bottom.equalTo(view.keyboardLayoutGuide.snp.top).priority(.high)
        }
        form.axis = .vertical
        form.spacing = SCRYFrom(16)
        scrollView.addSubview(form)
        form.snp.makeConstraints { make in
            make.edges.equalTo(scrollView.contentLayoutGuide).inset(UIEdgeInsets(top: SCRYFrom(16), left: SCRXFrom(20), bottom: SCRYFrom(20), right: SCRXFrom(20)))
            make.width.equalTo(scrollView.frameLayoutGuide).offset(-SCRXFrom(40))
        }
    }

    private func setupFields() {
        configureInput(nameField, placeholder: nil)
        nameField.text = draft.siteName
        nameField.accessibilityIdentifier = "site-create-name"
        nameField.addTarget(self, action: #selector(nameChanged), for: .editingChanged)
        let nameSection = section("site_create_project_name", required: true, content: nameField)
        nameTip.font = UIFont.systemFont(ofSize: SCRYFrom(12), weight: .light)
        nameTip.textColor = Red_Color
        nameTip.numberOfLines = 0
        nameSection.addArrangedSubview(nameTip)
        form.addArrangedSubview(nameSection)

        setupLocationFields()
        form.addArrangedSubview(section("site_create_country", required: true, content: countryField))
        form.addArrangedSubview(section("site_create_city", required: true, helper: "site_create_city_help", content: cityField))

        timeZoneRow.accessibilityLabel = "site_time_zone_title".localizedString
        timeZoneRow.addTarget(self, action: #selector(selectTimeZone), for: .touchUpInside)
        let timeSection = section("site_time_zone_title", required: true, helper: "site_create_timezone_help", content: timeZoneRow)
        styleHelper(localTimeLabel)
        timeSection.addArrangedSubview(localTimeLabel)
        form.addArrangedSubview(timeSection)
        if allowsSiteType {
            typeRow.accessibilityLabel = "site_type_selection".localizedString
            typeRow.accessibilityIdentifier = "site-create-type"
            typeRow.addTarget(self, action: #selector(selectType), for: .touchUpInside)
            form.addArrangedSubview(section("site_type_selection", content: typeRow))
        }
        setupDescription()
        setupLocationHelp()
        addTextField(.streetAddress, title: "site_create_street", placeholder: "site_create_street_placeholder")
        addTextField(.postalCode, title: "site_create_postal", placeholder: "site_create_postal_placeholder")
        setupCoordinates()
        setupIcons()
    }

    private func section(_ key: String, required: Bool = false, helper: String? = nil, content: UIView) -> UIStackView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = SCRYFrom(8)
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: SCRYFrom(15), weight: .light)
        label.textColor = RGB(39, 37, 54)
        label.numberOfLines = 0
        let title = NSMutableAttributedString(string: key.localizedString)
        if required { title.append(NSAttributedString(string: " *", attributes: [.foregroundColor: RGB(251, 44, 54)])) }
        label.attributedText = title
        stack.addArrangedSubview(label)
        if let helper {
            let hint = UILabel()
            styleHelper(hint)
            hint.text = helper.localizedString
            stack.setCustomSpacing(SCRYFrom(2), after: label)
            stack.addArrangedSubview(hint)
        }
        stack.addArrangedSubview(content)
        return stack
    }

    private func styleHelper(_ label: UILabel) {
        label.font = UIFont.systemFont(ofSize: SCRYFrom(12))
        label.textColor = RGB(154, 164, 183)
        label.numberOfLines = 0
    }

    private func setupLocationFields() {
        for field in [countryField, cityField] {
            field.animationLayoutView = view
            field.onLayoutChanged = { [weak self] in self?.scrollEditingFieldIntoView(animated: false) }
            field.canAcceptResults = { [weak self] in self?.canInteractWithLocation == true }
        }
        countryField.prepareForInteraction = { [weak self] in
            guard let self, self.canInteractWithLocation else { return false }
            self.cityField.cancelSearch()
            self.view.endEditing(true)
            guard self.countryCatalog != nil else {
                XWHUDManager.showErrorTipHUD("site_create_location_load_failed".localizedString)
                return false
            }
            return true
        }
        countryField.loadOptions = { [weak self] query, completion in
            guard let self, let catalog = self.countryCatalog else {
                completion(.failure(CountryRegionCatalog.CatalogError.resourceMissing)); return
            }
            completion(.success(.init(options: catalog.entries(matching: query).map {
                .init(id: $0.code, title: $0.displayName(language: self.language), detail: nil)
            }, emptyText: "site_create_country_empty".localizedString)))
        }
        countryField.onSelect = { [weak self] option in
            guard let self, self.canInteractWithLocation, let entry = self.countryCatalog?.entry(code: option.id) else { return false }
            let changed = self.draft.countryRegionCode != entry.code
            self.draft.selectCountry(entry)
            if changed {
                self.activeCityCatalog = nil
                self.cityField.replaceSelection(id: nil, title: nil, context: entry.code)
                self.updateLocationValues()
            }
            return true
        }
        cityField.prepareForInteraction = { [weak self] in
            guard let self, self.canInteractWithLocation else { return false }
            self.countryField.cancelSearch()
            self.view.endEditing(true)
            guard self.draft.countryRegionCode != nil else {
                XWHUDManager.showErrorTipHUD("site_create_city_country_required".localizedString)
                return false
            }
            return true
        }
        cityField.loadOptions = { [weak self] query, completion in
            guard let self, let countryCode = self.draft.countryRegionCode else { return }
            self.cityLoader.search(countryCode: countryCode, query: query) { [weak self] result in
                guard let self, self.canInteractWithLocation, self.cityField.isExpanded,
                      self.draft.countryRegionCode == countryCode else { return }
                switch result {
                case .success(let (catalog, entries)):
                    self.activeCityCatalog = catalog
                    let countryName = self.countryCatalog?.displayName(forStoredCode: countryCode, language: self.language) ?? countryCode
                    completion(.success(.init(options: entries.map {
                        .init(id: $0.id, title: catalog.displayTitle(for: $0, language: self.language), detail: countryName)
                    }, emptyText: (catalog.entries.isEmpty ? "site_create_city_unavailable" : "site_create_city_empty").localizedString)))
                case .failure(let error): completion(.failure(error))
                }
            }
        }
        cityField.onSelect = { [weak self] option in
            guard let self, self.canInteractWithLocation,
                  self.activeCityCatalog?.countryCode == self.draft.countryRegionCode,
                  let entry = self.activeCityCatalog?.entry(id: option.id) else { return false }
            guard self.draft.selectCity(entry, timezone: self.timeZoneCatalog?.value(matchingIdentifier: entry.timezoneIdentifier)) else {
                XWHUDManager.showErrorTipHUD("site_create_location_load_failed".localizedString)
                return false
            }
            self.updateLocationValues()
            return true
        }
        cityField.onCancel = { [weak self] in self?.cityLoader.cancel() }
    }

    private func updateLocationValues() {
        // CREATE collects these actual controls; never leave stale pre-selection coordinates there.
        for field in [SiteCreationTextField.latitude, .longitude] { textFields[field]?.text = draft.text[field] }
        updateTimeZone()
        if draft.timezone == nil { stopClock() } else { resumeClock() }
    }

    private func cancelLocationSearch(animated: Bool = true) {
        countryField.cancelSearch(animated: animated)
        cityField.cancelSearch(animated: animated)
    }

    private func configureInput(_ field: UITextField, placeholder: String?) {
        field.font = UIFont.systemFont(ofSize: SCRYFrom(14), weight: .light)
        field.textColor = RGB(30, 35, 41)
        field.backgroundColor = .white
        field.layer.cornerRadius = SCRYFrom(10)
        field.leftView = UIView(frame: CGRect(x: 0, y: 0, width: SCRXFrom(16), height: 1))
        field.leftViewMode = .always
        field.rightView = UIView(frame: CGRect(x: 0, y: 0, width: SCRXFrom(12), height: 1))
        field.rightViewMode = .unlessEditing
        field.clearButtonMode = .whileEditing
        if let placeholder {
            field.attributedPlaceholder = NSAttributedString(string: placeholder.localizedString, attributes: [.foregroundColor: RGB(148, 163, 184)])
        }
        field.returnKeyType = .done
        field.delegate = self
        field.snp.makeConstraints { make in make.height.equalTo(SCRYFrom(44)) }
    }

    @discardableResult
    private func addTextField(_ field: SiteCreationTextField, title: String, placeholder: String, to stack: UIStackView? = nil) -> UITextField {
        let input = UITextField()
        configureInput(input, placeholder: placeholder)
        input.accessibilityIdentifier = "site-create-" + field.rawValue
        input.accessibilityLabel = title.localizedString
        input.addTarget(self, action: #selector(textChanged(_:)), for: .editingChanged)
        if field != .streetAddress {
            input.autocorrectionType = .no
            input.autocapitalizationType = .none
        }
        textFields[field] = input
        let helper = field == .latitude || field == .longitude ? "site_create_decimal" : nil
        (stack ?? form).addArrangedSubview(section(title, helper: helper, content: input))
        return input
    }

    private func setupDescription() {
        descriptionView.font = UIFont.systemFont(ofSize: SCRYFrom(14), weight: .light)
        descriptionView.textColor = RGB(30, 35, 41)
        descriptionView.backgroundColor = .white
        descriptionView.layer.cornerRadius = SCRYFrom(10)
        descriptionView.layer.borderColor = RGB(220, 220, 220).cgColor
        descriptionView.layer.borderWidth = 0.5
        descriptionView.textContainerInset = UIEdgeInsets(top: SCRYFrom(12), left: SCRXFrom(12), bottom: SCRYFrom(12), right: SCRXFrom(12))
        descriptionView.textContainer.lineFragmentPadding = 0
        descriptionView.isScrollEnabled = true
        descriptionView.delegate = self
        descriptionView.accessibilityLabel = "site_create_description".localizedString
        descriptionView.accessibilityIdentifier = "site-create-description"
        descriptionView.snp.makeConstraints { make in make.height.equalTo(SCRYFrom(85)) }
        descriptionPlaceholder.text = "site_create_description_placeholder".localizedString
        descriptionPlaceholder.font = descriptionView.font
        descriptionPlaceholder.textColor = RGB(148, 163, 184)
        descriptionPlaceholder.numberOfLines = 0
        descriptionView.addSubview(descriptionPlaceholder)
        descriptionPlaceholder.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(SCRYFrom(12))
            make.left.equalToSuperview().offset(SCRXFrom(12))
            make.width.equalTo(descriptionView).offset(-SCRXFrom(24))
        }
        let block = section("site_create_description", content: descriptionView)
        styleHelper(descriptionCounter)
        descriptionCounter.textAlignment = .right
        descriptionCounter.text = "0/300"
        block.addArrangedSubview(descriptionCounter)
        form.addArrangedSubview(block)
    }

    private func setupLocationHelp() {
        let container = UIView()
        container.backgroundColor = RGB(244, 245, 251)
        container.layer.cornerRadius = SCRYFrom(10)
        container.layer.borderColor = RGB(220, 220, 220).cgColor
        container.layer.borderWidth = 0.5
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = SCRYFrom(12)
        container.addSubview(stack)
        stack.snp.makeConstraints { make in make.edges.equalToSuperview().inset(UIEdgeInsets(top: SCRYFrom(12), left: SCRXFrom(16), bottom: SCRYFrom(12), right: SCRXFrom(16))) }
        let header = UIStackView()
        header.alignment = .center
        header.spacing = SCRXFrom(8)
        header.isUserInteractionEnabled = false
        let info = UIImageView(image: UIImage(named: "site_create_info"))
        header.addArrangedSubview(info)
        info.snp.makeConstraints { make in make.width.height.equalTo(SCRYFrom(16)) }
        let title = UILabel()
        title.text = "site_create_location_help".localizedString
        title.font = UIFont.systemFont(ofSize: SCRYFrom(14))
        title.textColor = RGB(102, 103, 171)
        title.numberOfLines = 0
        header.addArrangedSubview(title)
        header.addArrangedSubview(helpArrow)
        helpArrow.snp.makeConstraints { make in make.width.height.equalTo(SCRYFrom(16)) }
        helpButton.addSubview(header)
        header.snp.makeConstraints { make in make.edges.equalToSuperview() }
        helpButton.accessibilityLabel = title.text
        helpButton.accessibilityIdentifier = "site-create-location-help"
        helpButton.addTarget(self, action: #selector(toggleHelp), for: .touchUpInside)
        helpButton.snp.makeConstraints { make in make.height.greaterThanOrEqualTo(SCRYFrom(20)) }
        stack.addArrangedSubview(helpButton)
        helpBody.axis = .vertical
        helpBody.spacing = SCRYFrom(6)
        for index in 1...4 {
            let label = UILabel()
            label.numberOfLines = 0
            let paragraph = NSMutableParagraphStyle()
            paragraph.minimumLineHeight = SCRYFrom(21)
            let text = NSMutableAttributedString(string: "site_create_location_explanation_\(index)".localizedString, attributes: [
                .font: UIFont.systemFont(ofSize: SCRYFrom(12), weight: .light),
                .foregroundColor: RGB(100, 116, 139), .paragraphStyle: paragraph
            ])
            if index < 4 {
                let emphasis = "site_create_location_emphasis_\(index)".localizedString
                let range = (text.string as NSString).range(of: emphasis)
                if range.location != NSNotFound {
                    text.addAttributes([.font: UIFont.systemFont(ofSize: SCRYFrom(12)), .foregroundColor: RGB(30, 35, 41)], range: range)
                }
            }
            label.attributedText = text
            helpBody.addArrangedSubview(label)
        }
        helpBody.isHidden = true
        stack.addArrangedSubview(helpBody)
        form.addArrangedSubview(container)
    }

    private func setupCoordinates() {
        let block = UIStackView()
        block.axis = .vertical
        block.spacing = SCRYFrom(12)
        let actionContainer = UIView()
        let action = SiteCreationLocationButton(type: .custom)
        action.accessibilityIdentifier = "site-create-current-location"
        action.addTarget(self, action: #selector(toggleCurrentLocation(_:)), for: .touchUpInside)
        actionContainer.addSubview(action)
        action.snp.makeConstraints { make in
            make.top.bottom.centerX.equalToSuperview()
            make.left.greaterThanOrEqualToSuperview()
            make.right.lessThanOrEqualToSuperview()
        }
        block.addArrangedSubview(actionContainer)
        let coordinates = UIStackView()
        coordinates.spacing = SCRXFrom(12)
        coordinates.distribution = .fillEqually
        addTextField(.latitude, title: "site_create_latitude", placeholder: "site_create_latitude_placeholder", to: coordinates)
        addTextField(.longitude, title: "site_create_longitude", placeholder: "site_create_longitude_placeholder", to: coordinates)
        block.addArrangedSubview(coordinates)
        form.addArrangedSubview(block)
    }

    private func setupIcons() {
        flowLayout.minimumLineSpacing = SCRXFrom(16)
        flowLayout.minimumInteritemSpacing = SCRXFrom(16)
        icons.backgroundColor = .clear
        icons.isScrollEnabled = false
        icons.dataSource = self
        icons.delegate = self
        icons.register(SiteCreationIconCell.self, forCellWithReuseIdentifier: "icon")
        icons.snp.makeConstraints { make in
            make.height.equalTo(icons.snp.width).multipliedBy(7.0 / 4.0).offset(SCRXFrom(12))
        }
        form.addArrangedSubview(section("site_icon", content: icons))
    }

    @objc private func nameChanged() {
        guard nameField.markedTextRange == nil else { return }
        let exceeded = (nameField.text?.count ?? 0) > 32
        if exceeded { nameField.text = String((nameField.text ?? "").prefix(32)) }
        validateName(showLengthTip: exceeded)
    }

    @discardableResult
    private func validateName(showLengthTip: Bool = false) -> Bool {
        draft.siteName = nameField.text ?? ""
        let duplicate = SiteData.isTautonym(siteName: draft.siteName)
        let valid = draft.isNameValid(isDuplicate: duplicate)
        nameTip.text = showLengthTip ? "text_length_exceeded".localizedString : (duplicate ? "name_already_exists".localizedString : nil)
        nameTip.isHidden = nameTip.text == nil
        createButton.isEnabled = valid && !isCommitting
        return valid
    }

    @objc private func textChanged(_ input: UITextField) {
        guard input.markedTextRange == nil, let field = textFields.first(where: { $0.value === input })?.key else { return }
        let value = field.limitingInput(input.text ?? "")
        if value != input.text { input.text = value }
        draft.editText(field, value: value)
    }

    @objc private func revealEditingField() {
        scrollEditingFieldIntoView(animated: !UIAccessibility.isReduceMotionEnabled)
    }

    private func scrollEditingFieldIntoView(animated: Bool) {
        guard viewIfLoaded?.window != nil, navigationController?.topViewController === self else { return }
        if let field = [countryField, cityField].first(where: { $0.isExpanded }) {
            view.layoutIfNeeded()
            let options = field.convert(field.bounds, to: scrollView).insetBy(dx: 0, dy: -8)
            let input = field.searchField.convert(field.searchField.bounds, to: scrollView).insetBy(dx: 0, dy: -8)
            scrollView.scrollRectToVisible(options.height <= scrollView.bounds.height ? options : input, animated: animated)
            return
        }
        let inputs: [UIView] = [nameField, descriptionView] + textFields.values.map { $0 as UIView }
        guard let input = inputs.first(where: \.isFirstResponder) else { return }
        // keyboardLayoutGuide resizes the viewport; then move the active field into that viewport.
        view.layoutIfNeeded()
        scrollView.scrollRectToVisible(input.convert(input.bounds, to: scrollView).insetBy(dx: 0, dy: -20), animated: animated)
    }

    @objc private func toggleHelp() {
        helpBody.isHidden.toggle()
        helpArrow.transform = helpBody.isHidden ? .identity : CGAffineTransform(rotationAngle: .pi)
        helpButton.accessibilityValue = (helpBody.isHidden ? "site_create_collapsed" : "site_create_expanded").localizedString
    }

    @objc private func toggleCurrentLocation(_ sender: UIButton) {
        guard contextIsCurrent, !isCommitting else { return }
        sender.isSelected.toggle()
    }

    @objc private func selectTimeZone() {
        guard contextIsCurrent, !isCommitting else { return }
        cancelLocationSearch()
        view.endEditing(true)
        guard let controller = SiteTimeZoneSelectionViewController(onSelect: { [weak self] value in
            guard let self, self.contextIsCurrent, !self.isCommitting else { return }
            self.draft.selectManualTimezone(value)
            self.updateTimeZone()
        }) else {
            XWHUDManager.showErrorTipHUD("failed".localizedString)
            return
        }
        navigationController?.pushViewController(controller, animated: true)
    }

    private func updateTimeZone() {
        timeZoneRow.valueLabel.text = draft.timezone?.ianaId ?? "site_create_unknown".localizedString
        timeZoneRow.detailLabel.text = draft.timezone?.displayOffset
        timeZoneRow.detailLabel.isHidden = draft.timezone == nil
        timeZoneRow.accessibilityValue = draft.timezone?.storageValue ?? timeZoneRow.valueLabel.text
        localTimeLabel.isHidden = draft.timezone == nil
        refreshClock()
    }

    private func refreshClock() {
        guard let timezone = draft.timezone else { return }
        localTimeLabel.text = String(format: "site_local_time_format".localizedString, timezone.formattedLocalDate(at: Date())) + " · " + timezone.displayOffset
    }

    @objc private func stopClock() { localTimeTimer?.invalidate(); localTimeTimer = nil }

    @objc private func pauseForBackground() {
        stopClock()
        cancelLocationSearch(animated: false)
    }

    private var canInteractWithLocation: Bool {
        contextIsCurrent && !isCommitting && viewIfLoaded?.window != nil
            && navigationController?.topViewController === self
    }

    @objc private func cancelLocationSearchFromOutside() { cancelLocationSearch() }

    @objc private func resumeClock() {
        guard contextIsCurrent else { if viewIfLoaded?.window != nil { close() }; return }
        guard navigationController?.topViewController === self, viewIfLoaded?.window != nil,
              draft.timezone != nil, localTimeTimer == nil else { return }
        refreshClock()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.refreshClock() }
        RunLoop.main.add(timer, forMode: .common)
        localTimeTimer = timer
    }

    @objc private func selectType() {
        guard contextIsCurrent, allowsSiteType, FeatureVisibility.shared.canSelectSiteType,
              typeAlert == nil, !isCommitting else { return }
        cancelLocationSearch()
        view.endEditing(true)
        let alert = SiteTypeSelectionAlertView.make(selectedType: draft.siteType) { [weak self] selected in
            guard let self, self.contextIsCurrent else { return }
            self.draft.siteType = selected
            self.updateType()
        }
        typeAlert = alert
        alert.show()
    }

    private func updateType() {
        typeRow.valueLabel.text = (draft.siteType == .hdb ? "site_type_hdb" : "site_type_standard").localizedString
        typeRow.accessibilityValue = typeRow.valueLabel.text
    }

    @objc private func close() {
        guard !isCommitting else { return }
        cancelLocationSearch(animated: false)
        typeAlert?.dismiss(animation: false)
        view.endEditing(true)
        navigationController?.dismiss(animated: true)
    }

    @objc private func create() {
        guard contextIsCurrent, !isCommitting else { return }
        cancelLocationSearch(animated: false)
        view.endEditing(true)
        guard validateName() else { return }
        draft.text[.description] = descriptionView.text
        for (field, input) in textFields { draft.text[field] = input.text ?? "" }
        if !FeatureVisibility.shared.canSelectSiteType { draft.siteType = .standard }
        let properties: SiteStandardProperties
        do {
            properties = try draft.standardProperties()
        } catch let error as SiteCreationDraft.InvalidCoordinate {
            textFields[error.field]?.becomeFirstResponder()
            scrollEditingFieldIntoView(animated: !UIAccessibility.isReduceMotionEnabled)
            let key = error.field == .latitude ? "site_create_invalid_latitude" : "site_create_invalid_longitude"
            XWHUDManager.showErrorTipHUD(key.localizedString)
            return
        } catch {
            XWHUDManager.showErrorTipHUD("failed".localizedString)
            return
        }
        isCommitting = true
        createButton.isEnabled = false
        do {
            let site = try SiteData.add(name: draft.siteName, siteType: draft.siteType, imageId: draft.imageId,
                                        timezone: draft.timezone?.storageValue, extensionData: draft.extensionData,
                                        standardProperties: properties)
            let completion = onCreated
            navigationController?.dismiss(animated: true) { completion(site) }
        } catch {
            isCommitting = false
            validateName()
            XWHUDManager.showErrorTipHUD("failed".localizedString)
        }
    }
}

private final class SiteCreationLocationButton: UIButton {
    private let row = UIStackView()
    private let icon = UIImageView(image: UIImage(named: "site_create_current_location"))
    private let currentLocationButton = UIButton(type: .custom)
    private let accuracyButton = UIButton(type: .custom)
    private let selectionColor = RGB(104, 100, 179)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        layer.borderColor = selectionColor.cgColor
        isAccessibilityElement = false
        row.alignment = .center
        row.spacing = SCRXFrom(6)
        row.addArrangedSubview(icon)
        icon.snp.makeConstraints { make in make.width.height.equalTo(SCRYFrom(12)) }
        for (button, key, identifier) in [
            (currentLocationButton, "site_create_current_location", "site-create-location-option-current"),
            (accuracyButton, "site_create_most_accurate", "site-create-location-option-accurate")
        ] {
            let text = key.localizedString
            let title = NSAttributedString(string: text, attributes: [
                .font: UIFont.systemFont(ofSize: SCRYFrom(12), weight: .medium),
                .foregroundColor: selectionColor
            ])
            for state: UIControl.State in [.normal, .selected, .highlighted, [.selected, .highlighted]] {
                button.setAttributedTitle(title, for: state)
            }
            button.accessibilityLabel = text
            button.accessibilityIdentifier = identifier
            button.titleLabel?.textAlignment = .center
            button.contentEdgeInsets = UIEdgeInsets(top: SCRYFrom(2), left: SCRXFrom(6), bottom: SCRYFrom(2), right: SCRXFrom(6))
            button.layer.cornerRadius = SCRYFrom(12)
            button.addTarget(self, action: #selector(selectOption(_:)), for: .touchUpInside)
            row.addArrangedSubview(button)
            // Keep text metrics and padding identical in every selection and press state.
            let titleWidth = ceil(title.size().width)
            button.snp.makeConstraints { make in
                make.width.equalTo(titleWidth + SCRXFrom(12))
                make.height.equalTo(SCRYFrom(24))
            }
        }
        addSubview(row)
        row.snp.makeConstraints { make in
            make.left.right.equalToSuperview().inset(SCRXFrom(12 + 2.0 / 3.0))
            make.top.bottom.equalToSuperview().inset(SCRYFrom(4 + 2.0 / 3.0))
        }
        updateSelection()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isSelected: Bool {
        didSet { updateSelection() }
    }

    private func updateSelection() {
        // The two labels are mutually exclusive options; only the selected label has a badge.
        for (button, selected) in [(currentLocationButton, isSelected), (accuracyButton, !isSelected)] {
            button.isSelected = selected
            button.backgroundColor = selected ? selectionColor.withAlphaComponent(0.1) : .clear
            if selected {
                button.accessibilityTraits.insert(.selected)
            } else {
                button.accessibilityTraits.remove(.selected)
            }
        }
    }

    @objc private func selectOption(_ sender: UIButton) {
        isSelected = sender === currentLocationButton
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Keep the outline on whole physical pixels and the capsule round at any content height.
        let scale = max(traitCollection.displayScale, 1)
        layer.borderWidth = (2.0 / 3.0 * scale).rounded() / scale
        layer.cornerRadius = bounds.height / 2
    }
}

extension SiteCreateViewController: UITextFieldDelegate, UITextViewDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool { textField.resignFirstResponder(); return true }

    func textFieldDidBeginEditing(_ textField: UITextField) {
        cancelLocationSearch()
        revealEditingField()
    }

    func textViewDidBeginEditing(_ textView: UITextView) {
        cancelLocationSearch()
        revealEditingField()
    }

    func textViewDidChange(_ textView: UITextView) {
        descriptionPlaceholder.isHidden = !textView.text.isEmpty
        guard textView.markedTextRange == nil else { return }
        let field = SiteCreationTextField.description
        let limited = field.limitingInput(textView.text)
        if textView.text != limited {
            let selection = textView.selectedRange
            textView.text = limited
            textView.selectedRange = NSRange(location: min(selection.location, (limited as NSString).length), length: 0)
        }
        draft.text[.description] = limited
        descriptionCounter.text = "\(field.normalized(limited)?.count ?? 0)/300"
        descriptionPlaceholder.isHidden = !limited.isEmpty
    }
}

extension SiteCreateViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer === locationOutsideTap, countryField.isExpanded || cityField.isExpanded else { return false }
        // Switching fields is handled before focus changes. An outside-tap callback must not
        // close the newly opened second field later in the same touch sequence.
        return touch.view?.isDescendant(of: countryField) != true && touch.view?.isDescendant(of: cityField) != true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        gestureRecognizer === locationOutsideTap || otherGestureRecognizer === locationOutsideTap
    }
}

private final class SiteCreationIconCell: ImageCollectionViewCell {
    private let selectionOutline = UIView()

    var showsSelection = false {
        didSet { selectionOutline.isHidden = !showsSelection }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        selectionOutline.isUserInteractionEnabled = false
        selectionOutline.isHidden = true
        selectionOutline.layer.borderColor = Bar_Color.cgColor
        // Keep the outline above the image and inside the cell's clipping boundary.
        contentView.addSubview(selectionOutline)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = max(traitCollection.displayScale, 1)
        let inset = 1 / scale
        let outlineBounds = contentView.bounds.insetBy(dx: inset, dy: inset)
        selectionOutline.frame = CGRect(
            x: ceil(outlineBounds.minX * scale) / scale,
            y: ceil(outlineBounds.minY * scale) / scale,
            width: max(0, floor(outlineBounds.width * scale) / scale),
            height: max(0, floor(outlineBounds.height * scale) / scale)
        )
        selectionOutline.layer.cornerRadius = max(0, layer.cornerRadius - inset)
        selectionOutline.layer.borderWidth = ceil(0.5 * scale) / scale
    }
}

extension SiteCreateViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { 28 }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "icon", for: indexPath) as! SiteCreationIconCell
        cell.imageView.image = UIImage(named: "site_\(indexPath.item + 1)")
        cell.showsSelection = draft.imageId == indexPath.item + 1
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard draft.imageId != indexPath.item + 1 else { return }
        let previous = IndexPath(item: draft.imageId - 1, section: 0)
        draft.imageId = indexPath.item + 1
        UIView.performWithoutAnimation {
            collectionView.reloadItems(at: [previous, indexPath])
        }
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let width = floor((collectionView.bounds.width - flowLayout.minimumInteritemSpacing * 3) / 4 * 100) / 100
        return CGSize(width: width, height: width)
    }
}
