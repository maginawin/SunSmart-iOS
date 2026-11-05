import UIKit

/// Common Create/Edit form; subclasses own persistence and navigation after submission.
class SiteFormViewController: UIViewController {
    private(set) var formDraft: SiteFormDraft
    let editingSite: SiteData?
    private let notSyncedButton = UIButton(type: .system)
    private var modalDismissalStateBeforeTimeZone: Bool?
    private let account = UserData.currentUserId
    private let region = UserData.currentServerRegion
    private let allowsSiteType = FeatureVisibility.shared.canSelectSiteType
    private let scrollView = UIScrollView()
    private let form = UIStackView()
    private let footer = UIView()
    private let createButton = UIButton(type: .system)
    private let nameField = UITextField()
    private let nameTip = UILabel()
    private let timeZoneRow = SiteCreationSelectionRow(allowsMultilineDetail: true)
    private let daylightSavingTimeView = SiteDaylightSavingTimeView()
    private var daylightSavingTimePresentation = SiteDaylightSavingTimePresentation()
    private lazy var typeRow = SiteCreationSelectionRow(showsArrow: editingSite == nil)
    private let timeZoneCatalog: SiteTimeZoneCatalog?
    private let countryCatalogStore = CountryRegionCatalogStore.shared
    private var countryCatalogObservation: UUID?
    private var countryCatalog: CountryRegionCatalog? { countryCatalogStore.catalog }
    private let cityLoader = CityCatalogLoader()
    private let cityCatalogStore = CityCatalogStore.shared
    private var cityCatalogObservation: UUID?
    private var observedCityCountry: String?
    private var language: String { Bundle.main.preferredLocalizations.first ?? "en" }
    private lazy var countryField = SiteLocationSearchField(
        iconName: "site_create_search", titleKey: "site_create_country", searchKey: "site_create_country_search_placeholder",
        accessibilityPrefix: "site-create-country", selectedID: formDraft.countryRegionCode,
        selectedTitle: countryCatalog?.displayName(forStoredCode: formDraft.countryRegionCode, language: language) ?? formDraft.countryRegionCode,
        context: "countries")
    private lazy var cityField = SiteLocationSearchField(
        iconName: "site_create_location", titleKey: "site_create_city", searchKey: "site_create_city_search_placeholder",
        accessibilityPrefix: "site-create-city", selectedID: formDraft.cityID.map { "geonames:\($0)" },
        selectedTitle: nil, context: formDraft.countryRegionCode ?? "")
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
    private var coordinateTips: [SiteCreationTextField: UILabel] = [:]
    private var coordinateInputs: [SiteCreationTextField: SiteCreationCoordinateInputView] = [:]
    private let helpBody = UIStackView()
    private let helpArrow = UIImageView(image: UIImage(named: "site_create_disclosure"))
    private let helpButton = UIButton(type: .custom)
    private let flowLayout = UICollectionViewFlowLayout()
    private lazy var icons = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
    private var timeZoneObservation: UUID?
    private var observedTimeZoneID: String?
    private var localTimeTimer: Timer?
    private weak var typeAlert: SiteTypeSelectionAlertView?
    private var isNameValid = false
    var isCommitting = false {
        didSet {
            guard isViewLoaded else { return }
            updateCreateButtonState()
            form.isUserInteractionEnabled = !isCommitting
            if !isCommitting { countryCatalogDidChange(); cityCatalogDidChange() }
        }
    }
    private let currentLocationButton = SiteCreationLocationButton(type: .custom)
    private weak var locationPermissionAlert: SiteLocationPermissionAlertView?
    private lazy var currentLocationRequest: SiteCurrentLocationRequest = {
        let request = SiteCurrentLocationRequest(
            makeProvider: { SiteCurrentLocationProvider() },
            contextIsValid: { [weak self] in self?.canInteractWithLocation == true },
            isActive: { UIApplication.shared.applicationState == .active },
            openSettings: { completion in
                guard let url = URL(string: UIApplication.openSettingsURLString) else { completion(false); return }
                UIApplication.shared.open(url, options: [:]) { opened in
                    DispatchQueue.main.async { completion(opened) }
                }
            })
        request.stateChanged = { [weak self] phase in
            self?.currentLocationButton.isEnabled = phase == .idle
            self?.currentLocationButton.isLoading = phase == .checkingAccess || phase == .locating
        }
        request.showPrompt = { [weak self] prompt, completion in
            guard let self, self.canInteractWithLocation else { completion(false); return }
            let alert = SiteLocationPermissionAlertView.make(prompt: prompt, onDecision: completion)
            self.locationPermissionAlert = alert
            alert.show()
        }
        request.completed = { [weak self] result in
            guard let self, self.canInteractWithLocation else { return }
            switch result {
            case .success(let sample):
                guard self.formDraft.applyCurrentLocation(latitude: sample.latitude, longitude: sample.longitude) else { return }
                self.updateCoordinateInputs()
                ToastStatusView.show(
                    in: self.view,
                    message: "site_create_location_detected".localizedString,
                    type: .success,
                    appearance: .siteUpdate
                )
            case .failure(let failure): XWHUDManager.showErrorTipHUD(failure.rawValue.localizedString)
            }
        }
        return request
    }()

    init(formDraft: SiteFormDraft, editingSite: SiteData? = nil) {
        self.formDraft = formDraft
        self.editingSite = editingSite
        timeZoneCatalog = try? SiteTimeZoneCatalog.bundled()
        super.init(nibName: nil, bundle: nil)
    }

    func submitForm(properties: SiteStandardProperties) {
        preconditionFailure("Create/Edit must supply their own submit action")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        SiteTimeZoneService.shared.removeObserver(timeZoneObservation)
        if let observation = countryCatalogObservation { countryCatalogStore.removeObserver(observation) }
        if let observation = cityCatalogObservation { cityCatalogStore.removeObserver(observation) }
        localTimeTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = (editingSite == nil ? "site_create_title" : "site_edit_title").localizedString
        view.backgroundColor = RGB(248, 250, 252)
        navigationController?.setNavigationBarBackgroundColor(color: .clear)
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(named: "close")?.withRenderingMode(.alwaysOriginal),
            style: .done, target: self, action: #selector(close)
        ).withoutSharedBackground()
        setupLayout()
        setupFields()
        countryCatalogStore.startIfNeeded()
        if let code = formDraft.countryRegionCode { cityCatalogStore.startIfNeeded(countryCode: code) }
        updateTimeZone()
        updateType()
        validateName()
        NotificationCenter.default.addObserver(self, selector: #selector(pauseForBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(resumeAfterActivation), name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(revealEditingField), name: UIResponder.keyboardDidChangeFrameNotification, object: nil)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        updateTimeZone()
        guard contextIsCurrent else { close(); return }
        if countryCatalogObservation == nil {
            countryCatalogObservation = countryCatalogStore.observe { [weak self] in self?.countryCatalogDidChange() }
        }
        countryCatalogDidChange()
        (navigationController?.view ?? view).addGestureRecognizer(locationOutsideTap)
        if let previous = modalDismissalStateBeforeTimeZone {
            navigationController?.isModalInPresentation = previous
            modalDismissalStateBeforeTimeZone = nil
        }
        observeCityCatalog()
        resumeClock()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        SiteTimeZoneService.shared.removeObserver(timeZoneObservation)
        timeZoneObservation = nil
        if let observation = countryCatalogObservation {
            countryCatalogStore.removeObserver(observation)
            countryCatalogObservation = nil
        }
        stopClock()
        if let observation = cityCatalogObservation { cityCatalogStore.removeObserver(observation) }
        cityCatalogObservation = nil
        observedCityCountry = nil
        cancelCurrentLocation()
        cancelLocationSearch(animated: false)
        locationOutsideTap.view?.removeGestureRecognizer(locationOutsideTap)
        typeAlert?.dismiss(animation: false)
    }

    var contextIsCurrent: Bool {
        account == UserData.currentUserId && region == UserData.currentServerRegion
            && (editingSite.map { $0.region == region && $0.state == .normal && $0.permissionOperates.contains(.edit) } ?? true)
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
        createButton.setTitle((editingSite == nil ? "site_create_action" : "done").localizedString, for: .normal)
        createButton.setTitleColor(Title_Color, for: .normal)
        createButton.setTitleColor(RGB(139, 139, 139), for: .disabled)
        createButton.titleLabel?.font = UIFont.systemFont(ofSize: SCRYFrom(16), weight: .light)
        createButton.accessibilityIdentifier = editingSite == nil ? "site-create-submit" : "site-edit-submit"
        createButton.addTarget(self, action: #selector(submit), for: .touchUpInside)
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
        nameField.text = formDraft.siteName
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
        if let site = editingSite {
            notSyncedButton.setTitle("site_not_synced_to_server".localizedString, for: .normal)
            notSyncedButton.setTitleColor(RGB(255, 72, 49), for: .normal)
            notSyncedButton.titleLabel?.font = UIFont.systemFont(ofSize: SCRYFrom(12), weight: .light)
            notSyncedButton.contentHorizontalAlignment = .left
            notSyncedButton.isHidden = !site.pendingSitePropsMask.contains(.timezone)
            notSyncedButton.addTarget(self, action: #selector(submit), for: .touchUpInside)
            notSyncedButton.snp.makeConstraints { $0.height.greaterThanOrEqualTo(SCRYFrom(44)) }
            timeSection.addArrangedSubview(notSyncedButton)
        }
        form.addArrangedSubview(timeSection)
        daylightSavingTimeView.onToggleExpansion = { [weak self] in
            guard let self, self.contextIsCurrent, !self.isCommitting else { return }
            self.daylightSavingTimePresentation.toggleExpansion()
            self.daylightSavingTimeView.render(self.daylightSavingTimePresentation)
        }
        daylightSavingTimeView.onLayoutChanged = { [weak self] in
            self?.scrollEditingFieldIntoView(animated: false)
        }
        form.addArrangedSubview(daylightSavingTimeView)
        if allowsSiteType {
            typeRow.accessibilityLabel = "site_type_selection".localizedString
            typeRow.accessibilityIdentifier = "site-create-type"
            typeRow.isUserInteractionEnabled = editingSite == nil
            typeRow.accessibilityTraits = editingSite == nil ? .button : .staticText
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
        countryField.failureText = "site_create_country_load_failed".localizedString
        cityField.failureText = "site_create_city_load_failed".localizedString
        for field in [countryField, cityField] {
            field.animationLayoutView = view
            field.onLayoutChanged = { [weak self] in self?.scrollEditingFieldIntoView(animated: false) }
            field.canAcceptResults = { [weak self] in
                self?.canInteractWithLocation == true && UIApplication.shared.applicationState == .active
            }
        }
        countryField.prepareForInteraction = { [weak self] in
            guard let self, self.canInteractWithLocation else { return false }
            self.cityField.cancelSearch()
            self.view.endEditing(true)
            self.countryCatalogStore.retryIfUnavailable()
            return true
        }
        countryField.onActiveInputTap = { [weak self] in
            guard let self, self.canInteractWithLocation else { return }
            self.countryCatalogStore.retryIfUnavailable()
        }
        countryField.loadOptions = { [weak self] query, completion in
            guard let self else { return }
            guard let catalog = self.countryCatalog else {
                if self.countryCatalogStore.phase == .failed {
                    completion(.failure(CountryRegionCatalog.CatalogError.invalidCatalog))
                }
                // While initializing/requesting, keep Loading. The store observer reloads the
                // current query when data arrives, so cancelled/old query closures are not retained.
                return
            }
            completion(.success(.init(options: catalog.entries(matching: query).map {
                .init(id: $0.code, title: $0.displayName(language: self.language), detail: nil)
            }, emptyText: "site_create_country_empty".localizedString)))
        }
        countryField.onSelect = { [weak self] option in
            guard let self, self.canInteractWithLocation, let entry = self.countryCatalog?.entry(code: option.id) else { return false }
            let changed = self.formDraft.countryRegionCode != entry.code
            if changed { self.cancelCurrentLocation() }
            self.formDraft.selectCountry(entry)
            if changed {
                self.cityField.replaceSelection(id: nil, title: nil, context: entry.code)
                self.updateLocationValues()
                self.observeCityCatalog()
            }
            return true
        }
        countryField.onCancel = { [weak self] in self?.updateCountryTitle() }
        cityField.prepareForInteraction = { [weak self] in
            guard let self, self.canInteractWithLocation else { return false }
            self.countryField.cancelSearch()
            self.view.endEditing(true)
            guard let code = self.formDraft.countryRegionCode else {
                XWHUDManager.showErrorTipHUD("site_create_city_country_required".localizedString)
                return false
            }
            self.cityCatalogStore.startIfNeeded(countryCode: code)
            self.cityCatalogStore.retryIfUnavailable(countryCode: code)
            return true
        }
        cityField.onActiveInputTap = { [weak self] in
            guard let self, self.canInteractWithLocation, let code = self.formDraft.countryRegionCode else { return }
            self.cityCatalogStore.retryIfUnavailable(countryCode: code)
        }
        cityField.loadOptions = { [weak self] query, completion in
            guard let self, let countryCode = self.formDraft.countryRegionCode else { return }
            guard let catalog = self.cityCatalogStore.catalog(countryCode: countryCode) else {
                if !self.cityCatalogStore.isLoading(countryCode: countryCode) {
                    completion(.failure(CityCatalog.CatalogError.invalidCatalog))
                }
                return // Store notifications reload the current query when a snapshot arrives.
            }
            let revision = self.cityCatalogStore.revision(countryCode: countryCode)
            self.cityLoader.search(catalog: catalog, query: query) { [weak self] entries in
                guard let self, self.canInteractWithLocation, UIApplication.shared.applicationState == .active, self.cityField.isExpanded,
                      self.formDraft.countryRegionCode == countryCode,
                      self.cityCatalogStore.revision(countryCode: countryCode) == revision else { return }
                let countryName = self.countryCatalog?.displayName(forStoredCode: countryCode, language: self.language) ?? countryCode
                completion(.success(.init(options: entries.map {
                    .init(id: $0.id, title: catalog.displayTitle(for: $0, language: self.language), detail: countryName)
                }, emptyText: (catalog.entries.isEmpty ? "site_create_city_unavailable" : "site_create_city_empty").localizedString)))
            }
        }
        cityField.onSelect = { [weak self] option in
            guard let self, self.canInteractWithLocation,
                  let code = self.formDraft.countryRegionCode,
                  let entry = self.cityCatalogStore.catalog(countryCode: code)?.entry(id: option.id) else { return false }
            if self.formDraft.cityID != entry.record.id { self.cancelCurrentLocation() }
            guard self.formDraft.selectCity(entry, timezone: self.timeZoneCatalog?.value(matchingIdentifier: entry.timezoneIdentifier)) else {
                XWHUDManager.showErrorTipHUD("site_create_location_load_failed".localizedString)
                return false
            }
            self.updateLocationValues()
            return true
        }
        cityField.onCancel = { [weak self] in self?.cityLoader.cancel(); self?.updateCityTitle() }
    }

    private func updateCountryTitle() {
        guard canInteractWithLocation, UIApplication.shared.applicationState == .active else { return }
        let code = formDraft.countryRegionCode
        countryField.updateSelectedTitle(id: code, title: countryCatalog?.displayName(forStoredCode: code, language: language) ?? code)
    }

    private func countryCatalogDidChange() {
        guard canInteractWithLocation, UIApplication.shared.applicationState == .active else { return }
        updateCountryTitle()
        // Replacement removes old candidates immediately; reload also invalidates old tickets.
        countryField.reloadOptions()
        cityField.reloadOptions() // Country detail labels use the same new directory.
    }

    private func updateLocationValues() {
        updateCoordinateInputs()
        updateTimeZone()
        if formDraft.timezone == nil { stopClock() } else { resumeClock() }
    }

    private func updateCoordinateInputs() {
        // A city/GPS replacement clears stale errors; a preserved manual value keeps its validation.
        for field in [SiteCreationTextField.latitude, .longitude] {
            textFields[field]?.text = formDraft.text[field]
            validateCoordinate(field)
        }
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
        input.text = formDraft.text[field]
        input.accessibilityIdentifier = "site-create-" + field.rawValue
        input.accessibilityLabel = title.localizedString
        input.addTarget(self, action: #selector(textChanged(_:)), for: .editingChanged)
        if field != .streetAddress {
            input.autocorrectionType = .no
            input.autocapitalizationType = .none
        }
        textFields[field] = input
        let helper = field == .latitude || field == .longitude ? "site_create_decimal" : nil
        let content: UIView
        if helper != nil {
            let container = SiteCreationCoordinateInputView(input: input)
            coordinateInputs[field] = container
            content = container
        } else {
            content = input
        }
        let inputSection = section(title, helper: helper, content: content)
        if helper != nil {
            let tip = UILabel()
            tip.font = UIFont.systemFont(ofSize: SCRYFrom(11))
            tip.textColor = Error_Red_Color
            tip.numberOfLines = 0
            tip.isHidden = true
            tip.accessibilityIdentifier = "site-create-" + field.rawValue + "-error"
            coordinateTips[field] = tip
            inputSection.setCustomSpacing(SCRYFrom(4), after: content)
            inputSection.addArrangedSubview(tip)
        }
        (stack ?? form).addArrangedSubview(inputSection)
        return input
    }

    private func validateCoordinate(_ field: SiteCreationTextField) {
        let key: String?
        switch formDraft.coordinateValidation(for: field) {
        case .empty, .valid: key = nil
        case .invalidNumber, .outOfRange:
            key = field == .latitude ? "site_create_latitude_range" : "site_create_longitude_range"
        }
        setCoordinateError(field, key: key)
    }

    private func setCoordinateError(_ field: SiteCreationTextField, key: String?) {
        guard let tip = coordinateTips[field], let input = coordinateInputs[field] else { return }
        if let key {
            let paragraph = NSMutableParagraphStyle()
            paragraph.minimumLineHeight = SCRYFrom(16)
            paragraph.maximumLineHeight = SCRYFrom(16)
            tip.attributedText = NSAttributedString(string: key.localizedString, attributes: [.paragraphStyle: paragraph])
        } else {
            tip.attributedText = nil
        }
        tip.isHidden = key == nil
        input.showsError = key != nil
        updateCreateButtonState()
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
        descriptionView.text = formDraft.text[.description] ?? ""
        descriptionView.delegate = self
        descriptionView.accessibilityLabel = "site_create_description".localizedString
        descriptionView.accessibilityIdentifier = "site-create-description"
        descriptionView.snp.makeConstraints { make in make.height.equalTo(SCRYFrom(85)) }
        descriptionPlaceholder.isHidden = !descriptionView.text.isEmpty
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
        descriptionCounter.text = "\(SiteCreationTextField.description.normalized(descriptionView.text)?.count ?? 0)/300"
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
        let action = currentLocationButton
        action.accessibilityIdentifier = "site-create-current-location"
        action.addTarget(self, action: #selector(requestCurrentLocation), for: .touchUpInside)
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
        coordinates.alignment = .top
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
        formDraft.siteName = nameField.text ?? ""
        let duplicate = SiteData.isTautonym(siteName: formDraft.siteName, excludingSiteID: editingSite?.id)
        let valid = formDraft.isNameValid(isDuplicate: duplicate)
        nameTip.text = showLengthTip ? "text_length_exceeded".localizedString : (duplicate ? "name_already_exists".localizedString : nil)
        nameTip.isHidden = nameTip.text == nil
        isNameValid = valid
        updateCreateButtonState()
        return valid
    }

    private func updateCreateButtonState() {
        let showsCoordinateError = coordinateTips.values.contains { !$0.isHidden }
        createButton.isEnabled = SiteFormDraft.canSubmit(isNameValid: isNameValid,
            showsCoordinateError: showsCoordinateError, isCommitting: isCommitting)
        notSyncedButton.isEnabled = createButton.isEnabled
    }

    @objc private func textChanged(_ input: UITextField) {
        guard input.markedTextRange == nil, let field = textFields.first(where: { $0.value === input })?.key else { return }
        let value = field.limitingInput(input.text ?? "")
        if value != input.text { input.text = value }
        formDraft.editText(field, value: value)
        setCoordinateError(field, key: nil)
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
        var rect = input.convert(input.bounds, to: scrollView)
        if let field = textFields.first(where: { $0.value === input })?.key,
           let tip = coordinateTips[field], !tip.isHidden {
            rect = rect.union(tip.convert(tip.bounds, to: scrollView))
        }
        scrollView.scrollRectToVisible(rect.insetBy(dx: 0, dy: -20), animated: animated)
    }

    @objc private func toggleHelp() {
        helpBody.isHidden.toggle()
        helpArrow.transform = helpBody.isHidden ? .identity : CGAffineTransform(rotationAngle: .pi)
        helpButton.accessibilityValue = (helpBody.isHidden ? "site_create_collapsed" : "site_create_expanded").localizedString
    }

    @objc private func requestCurrentLocation() {
        guard canInteractWithLocation else { return }
        cancelLocationSearch()
        view.endEditing(true)
        currentLocationRequest.start()
    }

    private func cancelCurrentLocation() {
        currentLocationRequest.cancel()
        locationPermissionAlert?.dismiss(animation: false)
    }

    @objc private func resumeAfterActivation() {
        currentLocationRequest.didBecomeActive()
        countryCatalogDidChange()
        cityCatalogDidChange()
        resumeClock()
    }

    @objc private func selectTimeZone() {
        guard contextIsCurrent, !isCommitting else { return }
        cancelLocationSearch()
        view.endEditing(true)
        guard let controller = SiteTimeZoneSelectionViewController(onSelect: { [weak self] value in
            guard let self, self.contextIsCurrent, !self.isCommitting else { return }
            self.formDraft.selectManualTimezone(value)
            self.updateTimeZone()
        }) else {
            XWHUDManager.showErrorTipHUD("failed".localizedString)
            return
        }
        if editingSite != nil, let navigationController {
            modalDismissalStateBeforeTimeZone = navigationController.isModalInPresentation
            navigationController.isModalInPresentation = true
        }
        navigationController?.pushViewController(controller, animated: true)
    }

    private func updateTimeZone() {
        let identifier = formDraft.timezone?.ianaId
        if identifier != observedTimeZoneID || timeZoneObservation == nil {
            SiteTimeZoneService.shared.removeObserver(timeZoneObservation)
            observedTimeZoneID = identifier
            timeZoneObservation = formDraft.timezone.map { value in
                SiteTimeZoneService.shared.observe(value) { [weak self] in
                    guard let self, self.contextIsCurrent, self.formDraft.timezone?.ianaId == value.ianaId else { return }
                    self.updateTimeZone()
                }
            }
        }
        timeZoneRow.valueLabel.text = formDraft.timezone?.ianaId ?? "site_create_unknown".localizedString
        timeZoneRow.detailLabel.text = formDraft.timezone?.displayOffset
        timeZoneRow.detailLabel.isHidden = formDraft.timezone == nil
        timeZoneRow.accessibilityValue = [timeZoneRow.valueLabel.text, timeZoneRow.detailLabel.text].compactMap { $0 }.joined(separator: ", ")
        localTimeLabel.isHidden = formDraft.timezone == nil
        daylightSavingTimePresentation.update(identifier: identifier,
            snapshot: identifier.flatMap { SiteTimeZoneService.shared.store.snapshot(for: $0) }, at: Date())
        daylightSavingTimeView.render(daylightSavingTimePresentation)
        refreshClock()
    }

    private func refreshClock() {
        guard let timezone = formDraft.timezone else { return }
        let now = Date()
        let offset = timezone.effectiveOffset(at: now).map(SiteTimeZoneValue.formatOffset)
            ?? "site_time_zone_refresh_required".localizedString
        localTimeLabel.text = String(format: "site_local_time_format".localizedString, timezone.formattedLocalDate(at: now)) + " · " + offset
    }

    @objc private func stopClock() { localTimeTimer?.invalidate(); localTimeTimer = nil }

    @objc private func pauseForBackground() {
        currentLocationRequest.didEnterBackground()
        locationPermissionAlert?.dismiss(animation: false)
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
              formDraft.timezone != nil, localTimeTimer == nil else { return }
        refreshClock()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.refreshClock() }
        RunLoop.main.add(timer, forMode: .common)
        localTimeTimer = timer
    }

    @objc private func selectType() {
        guard editingSite == nil, contextIsCurrent, allowsSiteType, FeatureVisibility.shared.canSelectSiteType,
              typeAlert == nil, !isCommitting else { return }
        cancelLocationSearch()
        view.endEditing(true)
        let alert = SiteTypeSelectionAlertView.make(selectedType: formDraft.siteType) { [weak self] selected in
            guard let self, self.contextIsCurrent else { return }
            self.formDraft.siteType = selected
            self.updateType()
        }
        typeAlert = alert
        alert.show()
    }

    private func updateType() {
        typeRow.valueLabel.text = (formDraft.siteType == .hdb ? "site_type_hdb" : "site_type_standard").localizedString
        typeRow.accessibilityValue = typeRow.valueLabel.text
    }

    @objc func close() {
        guard !isCommitting else { return }
        cancelCurrentLocation()
        cancelLocationSearch(animated: false)
        typeAlert?.dismiss(animation: false)
        view.endEditing(true)
        if navigationController?.presentingViewController != nil {
            navigationController?.dismiss(animated: true)
        } else {
            navigationController?.popViewController(animated: true)
        }
    }

    @objc private func submit() {
        guard contextIsCurrent, !isCommitting else { return }
        cancelCurrentLocation()
        cancelLocationSearch(animated: false)
        view.endEditing(true)
        guard validateName() else { return }
        formDraft.text[.description] = descriptionView.text
        for (field, input) in textFields { formDraft.text[field] = input.text ?? "" }
        if editingSite == nil, !FeatureVisibility.shared.canSelectSiteType { formDraft.siteType = .standard }
        let properties: SiteStandardProperties
        do {
            properties = try formDraft.standardProperties()
        } catch let error as SiteFormDraft.InvalidCoordinate {
            textFields[error.field]?.becomeFirstResponder()
            // Focusing hides old feedback; restore both errors after focus for this submit attempt.
            for field in [SiteCreationTextField.latitude, .longitude] { validateCoordinate(field) }
            scrollEditingFieldIntoView(animated: !UIAccessibility.isReduceMotionEnabled)
            return
        } catch {
            XWHUDManager.showErrorTipHUD("failed".localizedString)
            return
        }
        submitForm(properties: properties)
    }

    private func observeCityCatalog() {
        let code = formDraft.countryRegionCode
        if observedCityCountry != code || cityCatalogObservation == nil {
            if let observation = cityCatalogObservation { cityCatalogStore.removeObserver(observation) }
            cityCatalogObservation = nil
            observedCityCountry = code
            if let code {
                cityCatalogObservation = cityCatalogStore.observe(countryCode: code) { [weak self] in self?.cityCatalogDidChange() }
            }
        }
        if let code { cityCatalogStore.startIfNeeded(countryCode: code) }
        cityCatalogDidChange()
    }

    private func updateCityTitle() {
        guard canInteractWithLocation, UIApplication.shared.applicationState == .active else { return }
        let catalog = formDraft.countryRegionCode.flatMap { cityCatalogStore.catalog(countryCode: $0) }
        let title = formDraft.resolvedCity(in: catalog).flatMap { catalog?.displayTitle(for: $0, language: language) }
        cityField.updateSelectedTitle(id: formDraft.cityID.map { "geonames:\($0)" }, title: title)
    }

    private func cityCatalogDidChange() {
        guard canInteractWithLocation, UIApplication.shared.applicationState == .active else { return }
        updateCityTitle()
        cityField.reloadOptions() // Invalidates displayed/search tickets without clearing the user's query.
    }

}

private final class SiteCreationCoordinateInputView: UIView {
    private let outline = CAShapeLayer()
    var showsError = false {
        didSet { outline.isHidden = !showsError }
    }

    init(input: UITextField) {
        super.init(frame: .zero)
        backgroundColor = .white
        layer.cornerRadius = SCRYFrom(10)
        input.borderStyle = .none
        input.backgroundColor = .clear
        input.layer.cornerRadius = 0
        addSubview(input)
        input.snp.makeConstraints { make in make.edges.equalToSuperview() }
        outline.fillColor = UIColor.clear.cgColor
        outline.strokeColor = Error_Red_Color.cgColor
        outline.isHidden = true
        layer.addSublayer(outline)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = max(traitCollection.displayScale, 1)
        let width = max(1, (0.5 * scale).rounded()) / scale
        let inset = width / 2
        // Keep the entire stroke inside the container and use a whole number of physical pixels.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        outline.contentsScale = scale
        outline.frame = bounds
        outline.lineWidth = width
        outline.path = UIBezierPath(
            roundedRect: bounds.insetBy(dx: inset, dy: inset),
            cornerRadius: max(0, layer.cornerRadius - inset)
        ).cgPath
        CATransaction.commit()
    }
}

private final class SiteCreationLocationButton: UIButton {
    private let capsule = UIView()
    private let icon = UIImageView(image: UIImage(named: "site_create_current_location"))
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let selectionColor = RGB(104, 100, 179)
    var isLoading = false {
        didSet {
            icon.isHidden = isLoading
            if isLoading { spinner.startAnimating() } else { spinner.stopAnimating() }
            accessibilityValue = isLoading ? "site_create_location_locating".localizedString : nil
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = "site_create_current_location".localizedString
        capsule.isUserInteractionEnabled = false
        capsule.layer.borderColor = selectionColor.cgColor
        addSubview(capsule)
        capsule.snp.makeConstraints { make in
            make.left.right.centerY.equalToSuperview()
            make.top.greaterThanOrEqualToSuperview()
            make.bottom.lessThanOrEqualToSuperview()
        }
        snp.makeConstraints { make in
            make.height.greaterThanOrEqualTo(44)
            make.height.equalTo(44).priority(.low)
        }
        let row = UIStackView()
        let iconSize = SCRYFrom(12)
        let iconSpacing = SCRXFrom(6)
        let titleSpacing = SCRXFrom(10)
        let capsuleInsets = UIEdgeInsets(top: SCRYFrom(4 + 2.0 / 3.0), left: SCRXFrom(12 + 2.0 / 3.0), bottom: SCRYFrom(4 + 2.0 / 3.0), right: SCRXFrom(12 + 2.0 / 3.0))
        let tagInsets = UIEdgeInsets(top: SCRYFrom(2), left: SCRXFrom(6), bottom: SCRYFrom(2), right: SCRXFrom(6))
        row.alignment = .center
        row.spacing = iconSpacing
        capsule.addSubview(row)
        let iconSlot = UIView()
        iconSlot.addSubview(icon)
        icon.snp.makeConstraints { make in make.edges.equalToSuperview() }
        spinner.color = selectionColor
        spinner.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
        iconSlot.addSubview(spinner)
        spinner.snp.makeConstraints { make in make.center.equalToSuperview() }
        iconSlot.snp.makeConstraints { make in make.width.height.equalTo(iconSize) }
        row.addArrangedSubview(iconSlot)
        let title = UILabel()
        title.text = "site_create_current_location".localizedString
        title.font = .systemFont(ofSize: SCRYFrom(12), weight: .medium)
        title.textColor = selectionColor
        title.numberOfLines = 0
        title.lineBreakMode = .byWordWrapping
        title.setContentCompressionResistancePriority(.required, for: .vertical)
        row.addArrangedSubview(title)
        row.setCustomSpacing(titleSpacing, after: title)
        let tag = UIView()
        tag.backgroundColor = selectionColor.withAlphaComponent(0.1)
        tag.layer.cornerRadius = SCRYFrom(4)
        let accuracy = UILabel()
        accuracy.text = "site_create_most_accurate".localizedString
        accuracy.font = .systemFont(ofSize: SCRYFrom(10), weight: .semibold)
        accuracy.textColor = selectionColor
        accuracy.numberOfLines = 1
        accuracy.setContentHuggingPriority(.required, for: .horizontal)
        accuracy.setContentCompressionResistancePriority(.required, for: .horizontal)
        for (label, lineHeight) in [(title, CGFloat(16)), (accuracy, CGFloat(13.333))] {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            paragraph.minimumLineHeight = SCRYFrom(lineHeight)
            label.attributedText = NSAttributedString(string: label.text ?? "", attributes: [
                .font: label.font!, .foregroundColor: selectionColor, .paragraphStyle: paragraph,
                .kern: label === accuracy ? SCRXFrom(0.1172) : 0
            ])
        }
        tag.addSubview(accuracy)
        accuracy.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(tagInsets)
        }
        row.addArrangedSubview(tag)
        row.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(capsuleInsets)
        }
        // Prefer the complete single-line content width; the container bounds take precedence.
        let contentWidth = iconSize + iconSpacing + ceil(title.intrinsicContentSize.width)
            + titleSpacing + ceil(accuracy.intrinsicContentSize.width)
            + tagInsets.left + tagInsets.right + capsuleInsets.left + capsuleInsets.right
        snp.makeConstraints { make in
            make.width.equalTo(contentWidth).priority(999)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = max(traitCollection.displayScale, 1)
        capsule.layer.borderWidth = (2.0 / 3.0 * scale).rounded() / scale
        capsule.layer.cornerRadius = capsule.bounds.height / 2
    }
}

extension SiteFormViewController: UITextFieldDelegate, UITextViewDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool { textField.resignFirstResponder(); return true }

    func textFieldDidBeginEditing(_ textField: UITextField) {
        if let field = textFields.first(where: { $0.value === textField })?.key, coordinateTips[field] != nil {
            cancelCurrentLocation()
            setCoordinateError(field, key: nil)
        }
        cancelLocationSearch()
        revealEditingField()
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        guard let field = textFields.first(where: { $0.value === textField })?.key, coordinateTips[field] != nil else { return }
        // Merely focusing/defocusing a city-derived coordinate must not mark it as a manual edit.
        formDraft.text[field] = textField.text ?? ""
        validateCoordinate(field)
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
        formDraft.text[.description] = limited
        descriptionCounter.text = "\(field.normalized(limited)?.count ?? 0)/300"
        descriptionPlaceholder.isHidden = !limited.isEmpty
    }
}

extension SiteFormViewController: UIGestureRecognizerDelegate {
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

extension SiteFormViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { 28 }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "icon", for: indexPath) as! SiteCreationIconCell
        cell.imageView.image = UIImage(named: "site_\(indexPath.item + 1)")
        cell.showsSelection = formDraft.imageId == indexPath.item + 1
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard formDraft.imageId != indexPath.item + 1 else { return }
        let previous = IndexPath(item: formDraft.imageId - 1, section: 0)
        formDraft.imageId = indexPath.item + 1
        UIView.performWithoutAnimation {
            collectionView.reloadItems(at: (0..<28).contains(previous.item) ? [previous, indexPath] : [indexPath])
        }
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let width = floor((collectionView.bounds.width - flowLayout.minimumInteritemSpacing * 3) / 4 * 100) / 100
        return CGSize(width: width, height: width)
    }
}

final class SiteCreateViewController: SiteFormViewController {
    private let onCreated: (SiteData) -> Void

    init(onCreated: @escaping (SiteData) -> Void) {
        self.onCreated = onCreated
        let timezone = (try? SiteTimeZoneCatalog.bundled())?.value(matchingIdentifier: TimeZone.current.identifier)
        super.init(formDraft: SiteFormDraft(siteName: SiteData.getNextSiteName(), timezone: timezone))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func submitForm(properties: SiteStandardProperties) {
        isCommitting = true
        do {
            let site = try SiteData.add(name: formDraft.siteName, siteType: formDraft.siteType, imageId: formDraft.imageId,
                                        timezone: formDraft.timezone?.storageValue, extensionData: formDraft.extensionData,
                                        standardProperties: properties)
            let completion = onCreated
            navigationController?.dismiss(animated: true) { completion(site) }
        } catch {
            isCommitting = false
            XWHUDManager.showErrorTipHUD("failed".localizedString)
        }
    }
}
