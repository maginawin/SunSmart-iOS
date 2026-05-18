//
//  SpaceDebugUARTViewController.swift
//  SunSmart
//
//  Created on 2026/5/16.
//

import UIKit

final class SpaceDebugUARTViewController: UIViewController {
    private enum UARTScrollMode {
        case auto
        case manual
    }

    private let session: DebugBluetoothSession
    private let space: SpaceData
    private let item: SpaceDebugNodeItem
    private let uartKey: SpaceDebugUARTDeviceKey
    private let controlsContainerView = UIView()
    private let modeControl = UISegmentedControl(items: [
        "debug_uart_auto".localizedString,
        "debug_uart_manual".localizedString
    ])
    private let receiveButton = UIButton(type: .system)
    private let clearButton = UIButton(type: .system)
    private let containFilterTextField = UITextField()
    private let ignoreFilterTextField = UITextField()
    private let tableView = UITableView(frame: .zero, style: .plain)

    private let visibleMessageLimit = 2_000
    private let visibleMessageTrimCount = 500
    private let manualScrollSwitchThreshold: CGFloat = 30
    private var messages: [SpaceDebugUARTMessage] = []
    private var displayMessages: [SpaceDebugUARTMessage] = []
    private var scrollMode: UARTScrollMode = .auto
    private var userDragStartContentOffsetY: CGFloat?
    private var hasSwitchedToManualForCurrentDrag = false
    private var containFilterText = ""
    private var ignoreFilterText = ""
    private let previousIdleTimerDisabled: Bool
    private var isShowingDisconnectAlert = false
    private var uartObserverToken: UUID?

    init(session: DebugBluetoothSession, space: SpaceData, item: SpaceDebugNodeItem) {
        self.session = session
        self.space = space
        self.item = item
        self.uartKey = SpaceDebugUARTManager.shared.key(space: space, node: item.node)
        self.previousIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "debug_uart_messages".localizedString
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "square.and.arrow.up"),
            style: .plain,
            target: self,
            action: #selector(shareButtonTapped)
        )
        view.backgroundColor = Background_Color
        setupUI()
        SpaceDebugUARTManager.shared.setActiveSpace(space)
        messages = SpaceDebugUARTManager.shared.cachedMessages(for: uartKey)
        rebuildDisplayMessages()
        tableView.reloadData()
        bindUARTManager()
        updateReceiveButton()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        UIApplication.shared.isIdleTimerDisabled = true
        installDisconnectHandler()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard isMovingFromParent || navigationController?.isBeingDismissed == true else {
            return
        }
        UIApplication.shared.isIdleTimerDisabled = previousIdleTimerDisabled
    }

    deinit {
        SpaceDebugUARTManager.shared.removeObserver(uartObserverToken)
        UIApplication.shared.isIdleTimerDisabled = previousIdleTimerDisabled
    }

    private func setupUI() {
        controlsContainerView.backgroundColor = Background_Color
        view.addSubview(controlsContainerView)
        controlsContainerView.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top)
            make.left.right.equalToSuperview()
        }

        modeControl.selectedSegmentIndex = 0
        modeControl.addTarget(self, action: #selector(modeControlChanged(_:)), for: .valueChanged)
        controlsContainerView.addSubview(modeControl)

        receiveButton.setTitle("debug_uart_stop".localizedString, for: .normal)
        receiveButton.addTarget(self, action: #selector(receiveButtonTapped), for: .touchUpInside)
        controlsContainerView.addSubview(receiveButton)

        clearButton.setTitle("debug_uart_clear".localizedString, for: .normal)
        clearButton.setTitleColor(.systemRed, for: .normal)
        clearButton.addTarget(self, action: #selector(clearButtonTapped), for: .touchUpInside)
        controlsContainerView.addSubview(clearButton)

        configureFilterTextField(containFilterTextField, placeholder: "debug_uart_contain_placeholder".localizedString)
        controlsContainerView.addSubview(containFilterTextField)

        configureFilterTextField(ignoreFilterTextField, placeholder: "debug_uart_ignore_placeholder".localizedString)
        controlsContainerView.addSubview(ignoreFilterTextField)

        modeControl.snp.makeConstraints { make in
            make.top.equalTo(SCRYFrom(8))
            make.left.equalTo(SCRXFrom(16))
        }

        clearButton.snp.makeConstraints { make in
            make.centerY.equalTo(modeControl)
            make.right.equalTo(SCRXFrom(-16))
        }

        receiveButton.snp.makeConstraints { make in
            make.centerY.equalTo(modeControl)
            make.right.equalTo(clearButton.snp.left).offset(SCRXFrom(-30))
        }

        containFilterTextField.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.equalTo(modeControl.snp.bottom).offset(SCRYFrom(8))
            make.height.equalTo(SCRYFrom(36))
            make.bottom.equalTo(SCRYFrom(-8))
        }

        ignoreFilterTextField.snp.makeConstraints { make in
            make.left.equalTo(containFilterTextField.snp.right).offset(SCRXFrom(8))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(containFilterTextField)
            make.bottom.equalTo(containFilterTextField)
            make.width.equalTo(containFilterTextField)
        }

        tableView.backgroundColor = Background_Color
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = SCRYFrom(48)
        tableView.contentInset = UIEdgeInsets(top: SCRYFrom(4), left: 0, bottom: SCRYFrom(8), right: 0)
        tableView.register(SpaceDebugUARTMessageCell.self, forCellReuseIdentifier: SpaceDebugUARTMessageCell.reuseIdentifier)
        tableView.dataSource = self
        tableView.delegate = self
        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.top.equalTo(controlsContainerView.snp.bottom)
            make.left.right.bottom.equalToSuperview()
        }
    }

    private func configureFilterTextField(_ textField: UITextField, placeholder: String) {
        textField.placeholder = placeholder
        textField.borderStyle = .roundedRect
        textField.clearButtonMode = .always
        textField.keyboardType = .asciiCapable
        textField.returnKeyType = .done
        textField.autocorrectionType = .no
        textField.spellCheckingType = .no
        textField.smartQuotesType = .no
        textField.smartDashesType = .no
        textField.smartInsertDeleteType = .no
        textField.delegate = self
        textField.addTarget(self, action: #selector(filterTextFieldChanged(_:)), for: .editingChanged)
    }

    private func bindUARTManager() {
        uartObserverToken = SpaceDebugUARTManager.shared.observe { [weak self] event in
            guard let self = self else {
                return
            }
            self.updateReceiveButton()
            switch event {
            case .messageAppended(let key, let message) where key == self.uartKey:
                self.handleAppendedMessage(message)
            case .bufferChanged(let key) where key == self.uartKey:
                self.reloadMessagesFromManager(scrollIfNeeded: self.scrollMode == .auto)
            case .allCleared:
                self.reloadMessagesFromManager(scrollIfNeeded: false)
            case .stateChanged, .messageAppended, .bufferChanged:
                break
            }
        }
    }

    private func handleAppendedMessage(_ message: SpaceDebugUARTMessage) {
        let shouldScroll = scrollMode == .auto && messageMatchesFilter(message)
        let previousMessageCount = messages.count
        messages = SpaceDebugUARTManager.shared.cachedMessages(for: uartKey)
        if messages.count < previousMessageCount {
            rebuildDisplayMessages()
            tableView.reloadData()
        } else if appendDisplayMessageIfNeeded(message) {
            tableView.reloadData()
        }
        if shouldScroll {
            scrollToLatestVisibleMessage(animated: true)
        }
    }

    private func reloadMessagesFromManager(scrollIfNeeded: Bool) {
        messages = SpaceDebugUARTManager.shared.cachedMessages(for: uartKey)
        rebuildDisplayMessages()
        tableView.reloadData()
        if scrollIfNeeded {
            scrollToLatestVisibleMessage(animated: false)
        }
    }

    private func startMessages() {
        SpaceDebugUARTManager.shared.setReceiveEnabled(true, space: space)
        updateReceiveButton()
    }

    private func stopMessages() {
        SpaceDebugUARTManager.shared.setReceiveEnabled(false, space: space)
        updateReceiveButton()
    }

    private func updateReceiveButton() {
        let title = SpaceDebugUARTManager.shared.isReceiveEnabled ? "debug_uart_stop".localizedString : "debug_uart_start".localizedString
        receiveButton.setTitle(title, for: .normal)
    }

    private func rebuildDisplayMessages() {
        var latestMessages: [SpaceDebugUARTMessage] = []

        for message in messages.reversed() {
            guard messageMatchesFilter(message) else {
                continue
            }
            latestMessages.append(message)
            if latestMessages.count == visibleMessageLimit {
                break
            }
        }

        displayMessages = Array(latestMessages.reversed())
    }

    @discardableResult
    private func appendDisplayMessageIfNeeded(_ message: SpaceDebugUARTMessage) -> Bool {
        guard messageMatchesFilter(message) else {
            return false
        }

        displayMessages.append(message)
        if displayMessages.count > visibleMessageLimit {
            displayMessages.removeFirst(min(visibleMessageTrimCount, displayMessages.count))
        }
        return true
    }

    private func scrollToLatestVisibleMessage(animated: Bool) {
        guard !displayMessages.isEmpty else {
            return
        }
        let indexPath = IndexPath(row: displayMessages.count - 1, section: 0)
        tableView.scrollToRow(at: indexPath, at: .bottom, animated: animated)
    }

    private var canScrollMessagesVertically: Bool {
        let verticalInset = tableView.adjustedContentInset.top + tableView.adjustedContentInset.bottom
        return tableView.contentSize.height + verticalInset > tableView.bounds.height
    }

    private func switchToManualModeForUserDragIfNeeded(currentOffsetY: CGFloat) {
        guard scrollMode == .auto,
              !hasSwitchedToManualForCurrentDrag,
              let dragStartContentOffsetY = userDragStartContentOffsetY else {
            return
        }

        let dragDistance = abs(currentOffsetY - dragStartContentOffsetY)
        guard dragDistance > manualScrollSwitchThreshold else {
            return
        }

        scrollMode = .manual
        modeControl.selectedSegmentIndex = 1
        hasSwitchedToManualForCurrentDrag = true
    }

    private func resetUserDragTracking() {
        userDragStartContentOffsetY = nil
        hasSwitchedToManualForCurrentDrag = false
    }

    private func messageMatchesFilter(_ message: SpaceDebugUARTMessage) -> Bool {
        if !containFilterText.isEmpty,
           message.text.range(of: containFilterText, options: [.caseInsensitive, .diacriticInsensitive]) == nil {
            return false
        }

        if !ignoreFilterText.isEmpty,
           message.text.range(of: ignoreFilterText, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
            return false
        }

        return true
    }

    private func clearMessages() {
        SpaceDebugUARTManager.shared.clearMessages(for: uartKey)
        messages.removeAll()
        displayMessages.removeAll()
        tableView.reloadData()
    }

    private func installDisconnectHandler() {
        session.onUnexpectedDisconnect = { [weak self] node in
            guard let self = self, node.primaryUnicastAddress == self.item.node.primaryUnicastAddress else {
                return
            }
            self.handleUnexpectedDisconnect()
        }
    }

    private func handleUnexpectedDisconnect() {
        updateReceiveButton()
        showDisconnectedAlert()
    }

    private func showDisconnectedAlert() {
        guard !isShowingDisconnectAlert else {
            return
        }
        isShowingDisconnectAlert = true
        SRAlertView(title: "notification".localizedString, message: "debug_connection_disconnected_message".localizedString, actions: [
            SRAlertAction(title: "alert_item_cancel".localizedString, style: .cancel, actionHandler: { [weak self] _ in
                self?.isShowingDisconnectAlert = false
            }),
            SRAlertAction(title: "debug_reconnect".localizedString, actionHandler: { [weak self] _ in
                self?.isShowingDisconnectAlert = false
                self?.reconnect()
            })
        ]).show()
    }

    private func reconnect() {
        session.reconnect { [weak self] success in
            guard let self = self else {
                return
            }
            if success {
                SpaceDebugUARTManager.shared.evaluateCurrentProxy(space: self.space)
            } else {
                self.showReconnectFailedAlert()
            }
        }
    }

    private func showReconnectFailedAlert() {
        guard !isShowingDisconnectAlert else {
            return
        }
        isShowingDisconnectAlert = true
        SRAlertView(title: "failed".localizedString, message: "debug_reconnect_failed_message".localizedString, actions: [
            SRAlertAction(title: "alert_item_cancel".localizedString, style: .cancel, actionHandler: { [weak self] _ in
                self?.isShowingDisconnectAlert = false
            }),
            SRAlertAction(title: "debug_reconnect".localizedString, actionHandler: { [weak self] _ in
                self?.isShowingDisconnectAlert = false
                self?.reconnect()
            })
        ]).show()
    }

    @objc private func modeControlChanged(_ sender: UISegmentedControl) {
        view.endEditing(true)
        scrollMode = sender.selectedSegmentIndex == 0 ? .auto : .manual
        if scrollMode == .auto {
            scrollToLatestVisibleMessage(animated: true)
        }
    }

    @objc private func receiveButtonTapped() {
        view.endEditing(true)
        if SpaceDebugUARTManager.shared.isReceiveEnabled {
            stopMessages()
        } else {
            startMessages()
        }
    }

    @objc private func clearButtonTapped() {
        view.endEditing(true)
        SRAlertView(title: "debug_uart_clear".localizedString, message: "debug_uart_clear_message".localizedString, actions: [
            .cancelAction,
            SRAlertAction(title: "debug_uart_clear".localizedString, actionHandler: { [weak self] _ in
                self?.clearMessages()
            })
        ]).show()
    }

    private func updateFilterText(from textField: UITextField) {
        let trimmedText = textField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if textField === containFilterTextField {
            containFilterText = trimmedText
        } else if textField === ignoreFilterTextField {
            ignoreFilterText = trimmedText
        }
    }

    private func refreshMessagesAfterFilterChange() {
        rebuildDisplayMessages()
        tableView.reloadData()
        if scrollMode == .auto {
            scrollToLatestVisibleMessage(animated: false)
        }
    }

    @objc private func filterTextFieldChanged(_ sender: UITextField) {
        updateFilterText(from: sender)
        refreshMessagesAfterFilterChange()
    }

    @objc private func shareButtonTapped() {
        view.endEditing(true)
        let context = makeExportContext()
        let cachedMessages = SpaceDebugUARTManager.shared.cachedMessages(for: uartKey)

        do {
            let fileURL = try SpaceDebugUARTLogExporter.makeFileURL(context: context, messages: cachedMessages)
            let controller = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
            if let popoverController = controller.popoverPresentationController {
                popoverController.barButtonItem = navigationItem.rightBarButtonItem
                popoverController.sourceView = view
                popoverController.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            }
            present(controller, animated: true)
        } catch {
            XWHUDManager.showErrorTipHUD("debug_uart_export_failed_message".localizedString)
        }
    }

    private func makeExportContext() -> SpaceDebugUARTLogExportContext {
        let siteName = SiteData.load(siteId: space.siteId)?.name ?? "--"
        let node = item.node
        return SpaceDebugUARTLogExportContext(
            siteName: siteName,
            spaceName: space.name,
            groupName: item.groupName,
            deviceName: item.nodeName,
            macAddress: node.macAddressResult ?? node.macAddress ?? "--",
            companyID: node.companyIdentifier.map { String(format: "0x%04X", $0) } ?? "--",
            productID: node.productIdentifier.map { String(format: "0x%04X", $0) } ?? "--",
            address: "\(node.primaryUnicastAddress)",
            versionIdentifier: "\(node.versionSEQ)",
            model: node.modelName ?? "--",
            deviceType: item.category.title,
            firmwareVersion: node.firmwareVersion ?? node.distributionVersion ?? "--",
            droppedMessageCount: SpaceDebugUARTManager.shared.droppedMessageCount(for: uartKey),
            generatedAt: Date()
        )
    }

    private func showUARTUnavailableAlert(state: SpaceDebugUARTSupportViewState) {
        let message: String
        switch state {
        case .unsupported:
            message = "debug_uart_unsupported_message".localizedString
        case .disconnected:
            message = "debug_connection_disconnected_message".localizedString
        case .failed(let error):
            message = error
        case .checking, .supported:
            return
        }
        SRAlertView(title: "debug_uart".localizedString, message: message, actions: [
            SRAlertAction(title: "ok".localizedString, actionHandler: { [weak self] _ in
                self?.navigationController?.popViewController(animated: true)
            })
        ]).show()
    }
}

extension SpaceDebugUARTViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return displayMessages.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: SpaceDebugUARTMessageCell.reuseIdentifier, for: indexPath) as! SpaceDebugUARTMessageCell
        let message = displayMessages[indexPath.row]
        cell.update(message: message)
        return cell
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        guard scrollView === tableView, canScrollMessagesVertically else {
            resetUserDragTracking()
            return
        }

        userDragStartContentOffsetY = scrollView.contentOffset.y
        hasSwitchedToManualForCurrentDrag = false
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === tableView, scrollView.isDragging else {
            return
        }

        switchToManualModeForUserDragIfNeeded(currentOffsetY: scrollView.contentOffset.y)
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard scrollView === tableView, !decelerate else {
            return
        }

        resetUserDragTracking()
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        guard scrollView === tableView else {
            return
        }

        resetUserDragTracking()
    }
}

extension SpaceDebugUARTViewController: UITextFieldDelegate {
    func textFieldShouldClear(_ textField: UITextField) -> Bool {
        textField.text = ""
        updateFilterText(from: textField)
        refreshMessagesAfterFilterChange()
        return false
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}
