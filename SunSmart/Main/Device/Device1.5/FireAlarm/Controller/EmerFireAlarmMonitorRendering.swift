//
//  EmerFireAlarmMonitorRendering.swift
//  SunSmart
//
//  Created by Plato Jobs on 2026/5/7.
//

import UIKit
import NordicSigMeshSDK

final class EmerFireAlarmResumeTransitionCoordinator {
    private struct ActiveTransition {
        let resumingState: EmerFireAlarmMonitorDisplayState
        let normalState: EmerFireAlarmMonitorDisplayState
        let startedAt: Date
        let finishAt: Date
        var workItem: DispatchWorkItem?
    }

    private var activeTransition: ActiveTransition?

    func schedule(
        resumingState: EmerFireAlarmMonitorDisplayState,
        normalState: EmerFireAlarmMonitorDisplayState,
        delay: TimeInterval,
        onFinish: @escaping () -> Void
    ) {
        let now = Date()
        if let transition = activeTransition, transition.resumingState == resumingState {
            scheduleActiveTransitionIfNeeded(now: now, onFinish: onFinish)
            return
        }

        cancel()
        activeTransition = ActiveTransition(
            resumingState: resumingState,
            normalState: normalState,
            startedAt: now,
            finishAt: now.addingTimeInterval(max(0, delay)),
            workItem: nil
        )
        scheduleActiveTransitionIfNeeded(now: now, onFinish: onFinish)
    }

    func cancel() {
        activeTransition?.workItem?.cancel()
        activeTransition = nil
    }

    private func scheduleActiveTransitionIfNeeded(now: Date, onFinish: @escaping () -> Void) {
        guard var transition = activeTransition else { return }
        transition.workItem?.cancel()
        let remainingDelay = max(0, transition.finishAt.timeIntervalSince(now))
        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  self.activeTransition?.resumingState == transition.resumingState else {
                return
            }
            self.activeTransition = nil
            onFinish()
        }
        transition.workItem = workItem
        activeTransition = transition
        DispatchQueue.main.asyncAfter(deadline: .now() + remainingDelay, execute: workItem)
    }
}

extension EmerFireAlarmMonitorVC {
    func updateEmptyViewLayout() {
        guard let emptyView = collectionView?.emptyView else {
            return
        }
        emptyView.frame = collectionView.bounds
        emptyView.setNeedsLayout()
        emptyView.layoutIfNeeded()
    }

    func updateEmptyUI() {
        if collectionView.frame == .zero {
            view.layoutIfNeeded()
        }

        if isAllEmergencyFunctionsDisabled {
            deviceCountLabel.isHidden = true
            collectionView.showEmptyDataView(frame: collectionView.bounds, imageName: "device_state_offline", title: "Emergency & Fire Alarm are all disabled".localizedString, buttonText: "Setting".localizedString, position: .center) { [weak self] in
                self?.openEditSettings()
            }
            if let emptyView = collectionView.emptyView {
                emptyView.button.backgroundColor = .clear
                emptyView.button.titleLabel?.font = FONTS(16)
                emptyView.button.setTitleColor(Bar_Color, for: .normal)
                emptyView.button.snp.updateConstraints { make in
                    make.top.equalTo(emptyView.titleLabel.snp.bottom).offset(SCRYFrom(24))
                }
                emptyView.button.isHidden = !canConfigureDevice
            }
            return
        }

        if groups.isEmpty {
            deviceCountLabel.isHidden = true
            collectionView.hideEmptyDataView()
            collectionView.showEmptyDataView(frame: collectionView.bounds, title: "Not associate with Group(s) !".localizedString, buttonText: "Setting".localizedString, position: .center) { [weak self] in
                self?.openEditSettings()
            }
            if let emptyView = collectionView.emptyView {
                emptyView.button.backgroundColor = .clear
                emptyView.button.titleLabel?.font = FONTS(16)
                emptyView.button.setTitleColor(Bar_Color, for: .normal)
                emptyView.button.snp.updateConstraints { make in
                    make.top.equalTo(emptyView.titleLabel.snp.bottom).offset(SCRYFrom(24))
                }
                emptyView.button.isHidden = !(space?.deviceOperates.contains(.edit) ?? false)
            }
        }else {
            deviceCountLabel.isHidden = false
            collectionView.hideEmptyDataView()
        }
    }

    @objc func handleConfigDidChange(_ notification: Notification) {
        var shouldKeepNotifiedConfig = false
        if let config = notification.object as? LinkedEmerFireConfig {
            if let currentId = viewModel.currentConfig?.deviceId ?? currentDevice?.id,
               config.deviceId != currentId {
                return
            }
            viewModel.currentConfig = config
            shouldKeepNotifiedConfig = true
        }
        reloadCurrentDevice()
        if !shouldKeepNotifiedConfig, let currentDevice {
            viewModel.currentConfig = viewModel.makeConfig(from: currentDevice)
        }
        applySavedConfig()
        refreshRealState()
    }

    func applySavedConfig() {
        viewModel.ensureConfig()
        guard let config = viewModel.currentConfig else {
            title = "EFC 1"
            groups = []
            deviceCountLabel.text = "(0)"
            collectionView?.reloadData()
            updateEmptyUI()
            return
        }

        title = config.deviceName
        configureActions()
        groups = viewModel.displayGroups()
        deviceCountLabel.text = "(\(groups.count))"
        updateStatusSetView()
        collectionView?.reloadData()
        updateMonitorState()
        updateEmptyUI()
        if viewModel.currentDevice?.displayStatus == .onlineBoundDevice || viewModel.currentDevice == nil {
            statusWarningView.isHidden = false
            updateStatusWarningIconVisibility()
        }
    }

    func reloadCurrentDevice() {
        viewModel.reloadCurrentDevice()
    }

    func updateMonitorState() {
        if isAllEmergencyFunctionsDisabled {
            view.hideEmptyDataView()
            setContentHidden(false)
            renderRealState(.disabled)
            updateEmptyUI()
            return
        }

        guard let currentDevice else {
            updateEmptyUI()
            return
        }

        switch currentDevice.displayStatus {
        case .offlineBoundDevice:
            currentState = .offline
            setContentHidden(true)
            view.showEmptyDataView(imageName: "device_state_offline", title: "device_offline_message".localizedString, backgroundColor: Background_Color)
        case .repairRequiredDevice:
            currentState = .repair
            setContentHidden(true)
            view.showEmptyDataView(imageName: "device_state_offline", title: "device_repair_message".localizedString, backgroundColor: Background_Color, buttonText: "repair".localizedString, buttomWidth: SCRXFrom(216), bottomMargin: SCRYFit(-78)) { [weak self] in
                self?.repairBtnClick()
            }
            if let emptyView = view.emptyView {
                if space?.deviceOperates.contains(.edit) ?? false {
                    emptyView.button.snp.updateConstraints { make in
                        make.top.equalTo(emptyView.titleLabel.snp.bottom).offset(SCRYFrom(78))
                    }
                } else {
                    emptyView.button.isHidden = true
                }
            }
        default:
            view.hideEmptyDataView()
            setContentHidden(false)
            updateEmptyUI()
        }
    }

    func observeSceneEvents() {
        sceneEventObserver = NotificationCenter.default.addObserver(forName: .init(emergencyFireControllerSceneEventNotificationName), object: nil, queue: .main) { [weak self] notification in
            guard let self,
                  let event = notification.object as? EmergencyFireControllerSceneEvent else {
                return
            }
            self.handleSceneEvent(event)
        }
    }

    func handleSceneEvent(_ event: EmergencyFireControllerSceneEvent) {
        guard !isAllEmergencyFunctionsDisabled else {
            return
        }
        let matchesNode = currentDevice?.bindNodeAddress.map { $0 == event.nodeAddress } ?? false
        guard event.controllerId == currentDevice?.id || matchesNode else {
            return
        }

        switch event.state {
        case .powerLossTriggered:
            resumeTransitionCoordinator.cancel()
            renderRealState(.emergencyTriggered)
        case .powerLossStopped:
            renderResumingState(.emergencyResuming)
        case .fireAlarmTriggered:
            resumeTransitionCoordinator.cancel()
            renderRealState(.fireTriggered)
        case .fireAlarmStopped:
            renderResumingState(.fireResuming)
        case .clear:
            resumeTransitionCoordinator.cancel()
            renderConfiguredNormalState()
        }
    }

    func renderResumingState(_ state: EmerFireAlarmMonitorDisplayState) {
        guard let normalState = viewModel.normalState(afterResuming: state),
              let delay = viewModel.restoreDelaySeconds(for: state) else {
            renderRealState(state)
            return
        }

        guard currentState != normalState else {
            return
        }

        renderRealState(state)
        resumeTransitionCoordinator.schedule(
            resumingState: state,
            normalState: normalState,
            delay: delay
        ) { [weak self] in
            guard let self, self.currentState == state else {
                return
            }
            self.renderRealState(normalState)
        }
    }

    func refreshRealState() {
        requestGeneration += 1
        let generation = requestGeneration

        guard currentWorkMode != .allDisabled else {
            renderRealState(.disabled)
            return
        }

        guard let currentDevice else {
            renderRealState(.offline)
            return
        }
        guard let node = currentDevice.bindNode else {
            renderUnlinkedState()
            return
        }
        guard node.isKeybindComplete else {
            renderRealState(.repair)
            return
        }
        guard node.state else {
            renderRealState(.offline)
            return
        }
        guard let vendorModel = node.sunricherVendorModel else {
            renderRealState(.offline)
            return
        }

        renderRealState(.loading)
        loadCurrentModeStatus(vendorModel: vendorModel, retryCount: 0, generation: generation)
    }

    func loadCurrentModeStatus(vendorModel: Model, retryCount: Int, generation: Int) {
        guard generation == requestGeneration else { return }
        MeshAPI.sendMessage(message: SunricherVendorGet(function: .emergencyCurrentModeStatus), model: vendorModel, timeout: 5) { [weak self] response in
            guard let self, generation == self.requestGeneration else { return }
            guard let statusMessage = response as? SunricherVendorStatus,
                  statusMessage.status.isSuccessful,
                  case .emergencyCurrentModeStatus(let status)? = statusMessage.status.parameters else {
                self.handleModeStatusFailure(vendorModel: vendorModel, retryCount: retryCount, generation: generation)
                return
            }
            self.renderRealState(self.viewModel.monitorDisplayState(mode: status.mode, active: status.active))
        }
    }

    func handleModeStatusFailure(vendorModel: Model, retryCount: Int, generation: Int) {
        guard generation == requestGeneration else { return }
        guard retryCount < 2 else {
            renderRealState(.offline)
            return
        }
        loadCurrentModeStatus(vendorModel: vendorModel, retryCount: retryCount + 1, generation: generation)
    }

    func renderConfiguredNormalState() {
        renderRealState(viewModel.configuredNormalState())
    }

    var currentWorkMode: EmergencyFireControllerWorkMode {
        viewModel.currentWorkMode
    }

    func renderRealState(_ state: EmerFireAlarmMonitorDisplayState) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.renderRealState(state)
            }
            return
        }
        currentState = state
        statusSetView.title = "Status Set".localizedString
        updateStatusSetRows(for: state)
        updateStatusWarningIconVisibility()
        configureActions()
        switch state {
        case .loading:
            statusWarningView.config(statusLab: "Loading...".localizedString, textColor: Title_Color)
        case .repair:
            statusWarningView.config(statusLab: "repair".localizedString, textColor: Title_Color)
        case .offline:
            statusWarningView.config(statusLab: "device_offline".localizedString, textColor: Title_Color)
        case .disabled:
            statusWarningView.config(statusLab: "Normal State".localizedString, textColor: Title_Color, underlined: false)
        case .emergencyTriggered:
            statusWarningView.config(statusLab: "Power Outage Emergency".localizedString, textColor: RGB(237, 154, 0))
        case .emergencyNormal:
            statusWarningView.config(statusLab: "Normal State".localizedString, textColor: Title_Color, underlined: false)
        case .emergencyResuming:
            statusWarningView.config(statusLab: "Resuming".localizedString, textColor: RGB(164, 224, 89))
        case .fireTriggered:
            statusWarningView.config(statusLab: "Fire Alarm Emergency".localizedString, textColor: RGB(255, 72, 49))
        case .fireNormal:
            statusWarningView.config(statusLab: "Normal State".localizedString, textColor: Title_Color, underlined: false)
        case .fireResuming:
            statusWarningView.config(statusLab: "Resuming".localizedString, textColor: RGB(164, 224, 89))
        }
    }

    func renderUnlinkedState() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.renderUnlinkedState()
            }
            return
        }
        currentState = .disabled
        statusSetView.title = "Status Set".localizedString
        updateStatusSetRows(for: .disabled)
        updateStatusWarningIconVisibility()
        configureActions()
        statusWarningView.config(statusLab: "Unlinked".localizedString, textColor: Title_Color, underlined: false)
    }

    func updateStatusSetRows(for state: EmerFireAlarmMonitorDisplayState) {
        let disabled: EmerFireAlarmStatusSetView.RowStatus = .disabled
        let inactive: EmerFireAlarmStatusSetView.RowStatus = .inactive
        var powerLossTrigger = disabled
        var powerLossStop = disabled
        var fireTrigger = disabled
        var fireStop = disabled

        switch currentWorkMode {
        case .powerLossEmergency:
            powerLossTrigger = inactive
            powerLossStop = inactive
            switch state {
            case .emergencyTriggered:
                powerLossStop = .triggered
            case .emergencyResuming:
                powerLossStop = .resume
            case .loading, .repair, .offline, .disabled, .emergencyNormal, .fireTriggered, .fireNormal, .fireResuming:
                break
            }
        case .fireAlarmEmergency:
            fireTrigger = inactive
            fireStop = inactive
            switch state {
            case .fireTriggered:
                fireStop = .triggered
            case .fireResuming:
                fireStop = .resume
            case .loading, .repair, .offline, .disabled, .emergencyTriggered, .emergencyNormal, .emergencyResuming, .fireNormal:
                break
            }
        case .allDisabled:
            break
        }

        statusSetView.updateRowStatuses(
            powerLossTrigger: powerLossTrigger,
            powerLossStop: powerLossStop,
            fireTrigger: fireTrigger,
            fireStop: fireStop
        )
    }

    func renderNodeAvailabilityChange(_ node: Node) {
        guard node.primaryUnicastAddress == currentDevice?.bindNodeAddress else { return }
        guard !isAllEmergencyFunctionsDisabled else { return }

        if !node.isKeybindComplete {
            requestGeneration += 1
            renderRealState(.repair)
            updateMonitorState()
            return
        }

        if !node.state {
            requestGeneration += 1
            renderRealState(.offline)
            updateMonitorState()
            return
        }

        switch currentState {
        case .repair, .offline, .loading:
            refreshRealState()
        case .disabled, .emergencyTriggered, .emergencyNormal, .emergencyResuming, .fireTriggered, .fireNormal, .fireResuming:
            break
        }
    }

    func setContentHidden(_ hidden: Bool) {
        collectionView?.isHidden = hidden
        pageControl?.isHidden = hidden
        deviceCountLabel?.isHidden = hidden || groups.isEmpty
        moniView.isHidden = hidden
        statusSetView.isHidden = hidden
        statusWarningView.isHidden = hidden
    }

    func updateStatusSetView() {
        statusSetView.updateItems(viewModel.statusItems())
        updateStatusSetRows(for: currentState)
    }

    func updateStatusWarningIconVisibility() {
        statusWarningView.icon.isHidden = !shouldShowGatewayWarning
    }

    var shouldShowGatewayWarning: Bool {
        currentConfig?.reportToGateway == false || currentDevice?.reportToGateway == false
    }

    func activeAssociatedGroupAddresses() -> [UInt16] {
        viewModel.activeAssociatedGroupAddresses()
    }

    var activeAssociatedGroupsContainDevices: Bool {
        viewModel.activeAssociatedGroupsContainDevices
    }
    
}
