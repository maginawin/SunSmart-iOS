import Foundation

enum SiteLocationAuthorization { case notDetermined, authorized, denied, restricted, unavailable }
enum SiteLocationFailure: Error { case denied, unavailable }
enum SiteLocationAccess { case checking, notDetermined, authorized, denied, servicesDisabled, restricted, unavailable }

/// Main-thread access resolution for one provider. The injected service query completes on the main thread.
final class SiteLocationAccessResolver {
    typealias QueryServices = (@escaping (Bool) -> Void) -> Void
    var changed: (() -> Void)?
    private let readAuthorization: () -> SiteLocationAuthorization
    private let queryServices: QueryServices
    private var authorization: SiteLocationAuthorization?
    private var servicesEnabled: Bool?
    private var queryID: UUID?
    private var deniedByLocation = false
    private var cancelled = false

    init(readAuthorization: @escaping () -> SiteLocationAuthorization, queryServices: @escaping QueryServices) {
        self.readAuthorization = readAuthorization
        self.queryServices = queryServices
    }

    func authorizationDidChange() {
        guard !cancelled else { return }
        updateAuthorization()
        // A global services toggle can leave app authorization at denied. It is still a new observation.
        _ = refresh(recheckServices: true)
        changed?()
    }

    func locationWasDenied() {
        guard !cancelled else { return }
        updateAuthorization()
        deniedByLocation = true
        _ = refresh(recheckServices: true)
    }

    private func updateAuthorization() {
        let current = readAuthorization()
        if authorization != current {
            authorization = current
            queryID = nil
            servicesEnabled = nil
            deniedByLocation = false
        }
    }

    func refresh(recheckServices: Bool = false) -> SiteLocationAccess {
        guard !cancelled else { return .unavailable }
        // Unknown initialization is different from the system's actual notDetermined authorization.
        guard authorization != nil else { return .checking }
        updateAuthorization()
        if authorization == .denied || deniedByLocation {
            if recheckServices {
                queryID = nil
                servicesEnabled = nil
            }
            if let servicesEnabled { return servicesEnabled ? .denied : .servicesDisabled }
            if queryID == nil {
                let id = UUID(), observedAuthorization = authorization
                queryID = id
                queryServices { [weak self] enabled in
                    guard let self, !self.cancelled, self.queryID == id else { return }
                    self.queryID = nil
                    if self.readAuthorization() == observedAuthorization {
                        self.servicesEnabled = enabled
                    } else {
                        self.updateAuthorization()
                        _ = self.refresh()
                    }
                    self.changed?()
                }
            }
            return .checking
        }
        switch authorization {
        case .authorized: return .authorized
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        case .unavailable, .none: return .unavailable
        case .denied: return .denied
        }
    }

    func cancel() {
        cancelled = true
        queryID = nil
        changed = nil
    }
}

struct SiteLocationSample {
    let latitude: Double
    let longitude: Double
    let horizontalAccuracy: Double
    let timestamp: Date
    let isReducedAccuracy: Bool

    func isUsable(at date: Date) -> Bool {
        latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude) && (-180...180).contains(longitude)
            && horizontalAccuracy.isFinite && horizontalAccuracy >= 0
            && (isReducedAccuracy || (date.timeIntervalSince(timestamp) >= -5 && date.timeIntervalSince(timestamp) <= 60))
    }
}

/// Each operation owns a fresh provider; callbacks from a cancelled provider cannot belong to its replacement.
protocol SiteCurrentLocationProviding: AnyObject {
    var accessChanged: (() -> Void)? { get set }
    func refreshAccess(recheckServices: Bool) -> SiteLocationAccess
    var result: ((Result<SiteLocationSample, SiteLocationFailure>) -> Void)? { get set }
    func requestAuthorization()
    func requestLocation()
    func cancel()
}

/// Main-thread request lifecycle. Kept independent of UIKit/CoreLocation so production transitions can be exercised.
final class SiteCurrentLocationRequest {
    enum Phase { case idle, checkingAccess, permissionPrompt, settingsPrompt, authorizing, settings, locating }
    private enum AccessPurpose { case start, permission, settingsReturn }
    enum Prompt { case permission, settings }
    enum Failure: String {
        case denied = "site_create_location_denied"
        case unavailable = "site_create_location_failed"
        case servicesDisabled = "site_create_location_services_disabled"
        case restricted = "site_create_location_restricted"
        case settingsUnavailable = "site_create_location_settings_failed"
    }
    typealias ScheduleTimeout = (@escaping () -> Void) -> (() -> Void)

    private(set) var phase: Phase = .idle { didSet { stateChanged?(phase) } }
    var stateChanged: ((Phase) -> Void)?
    var showPrompt: ((Prompt, @escaping (Bool) -> Void) -> Void)?
    var completed: ((Result<SiteLocationSample, Failure>) -> Void)?
    private let makeProvider: () -> SiteCurrentLocationProviding
    private let contextIsValid: () -> Bool
    private let isActive: () -> Bool
    private let openSettings: (@escaping (Bool) -> Void) -> Void
    private let scheduleTimeout: ScheduleTimeout
    private let now: () -> Date
    private var provider: SiteCurrentLocationProviding?
    private var operationID: UUID?
    private var cancelTimeout: (() -> Void)?
    private var timeoutID: UUID?
    private var accessPurpose: AccessPurpose = .start
    private var requestedAuthorization = false
    private var terminalFailure: Failure?
    private var settingsOpened = false
    private var leftForSettings = false
    private var pendingResult: Result<SiteLocationSample, Failure>?

    init(makeProvider: @escaping () -> SiteCurrentLocationProviding,
         contextIsValid: @escaping () -> Bool,
         isActive: @escaping () -> Bool,
         openSettings: @escaping (@escaping (Bool) -> Void) -> Void,
         now: @escaping () -> Date = Date.init,
         scheduleTimeout: @escaping ScheduleTimeout = { action in
             let timer = Timer(timeInterval: 15, repeats: false) { _ in action() }
             RunLoop.main.add(timer, forMode: .common)
             return { timer.invalidate() }
         }) {
        self.makeProvider = makeProvider
        self.contextIsValid = contextIsValid
        self.isActive = isActive
        self.openSettings = openSettings
        self.now = now
        self.scheduleTimeout = scheduleTimeout
    }

    deinit { cancelTimeout?(); provider?.cancel() }

    func start() {
        guard phase == .idle, contextIsValid(), isActive() else { return }
        let id = UUID()
        operationID = id
        accessPurpose = .start
        phase = .checkingAccess
        let source = makeProvider()
        provider = source
        source.accessChanged = { [weak self] in
            guard let self, self.accepts(id) else { return }
            self.advance()
        }
        source.result = { [weak self] result in
            guard let self, self.accepts(id), self.phase == .locating,
                  self.pendingResult == nil, self.terminalFailure == nil else { return }
            switch result {
            case .success(let sample):
                self.pendingResult = sample.isUsable(at: self.now()) ? .success(sample) : .failure(.unavailable)
            case .failure(let error):
                self.pendingResult = .failure(error == .denied ? .denied : .unavailable)
            }
            self.advance()
        }
        ensureTimeout()
        advance()
    }

    private func prompt(_ kind: Prompt, id: UUID) {
        phase = kind == .permission ? .permissionPrompt : .settingsPrompt
        guard let showPrompt else { cancel(); return }
        showPrompt(kind) { [weak self] proceed in
            guard let self, self.accepts(id),
                  self.phase == (kind == .permission ? .permissionPrompt : .settingsPrompt) else { return }
            guard proceed, self.isActive() else { self.cancel(); return }
            if kind == .permission {
                self.phase = .authorizing
                self.accessPurpose = .permission
                self.advance()
            } else {
                self.phase = .settings
                self.openSettings { [weak self] opened in
                    guard let self, self.accepts(id), self.phase == .settings else { return }
                    guard opened else { self.deliver(.failure(.settingsUnavailable)); return }
                    self.settingsOpened = true
                    self.didBecomeActive()
                }
            }
        }
    }

    private func accepts(_ id: UUID) -> Bool {
        guard operationID == id else { return false }
        guard contextIsValid() else { cancel(); return false }
        return true
    }

    private func accessFailure(_ access: SiteLocationAccess) -> Failure? {
        switch access {
        case .denied: return .denied
        case .servicesDisabled: return .servicesDisabled
        case .restricted: return .restricted
        case .unavailable: return .unavailable
        case .notDetermined: return phase == .locating ? .denied : nil
        case .authorized, .checking: return nil
        }
    }

    private func advance() {
        guard let id = operationID, accepts(id), let provider else { return }
        if let terminalFailure { deliver(.failure(terminalFailure)); return }
        let access = provider.refreshAccess(recheckServices: false)
        if phase == .locating {
            if access == .checking { ensureTimeout(); return }
            if let failure = accessFailure(access) { deliver(.failure(failure)); return }
            if let pendingResult { deliver(pendingResult) }
            return
        }
        guard phase == .checkingAccess || phase == .authorizing else { return }
        if access == .checking {
            phase = .checkingAccess
            ensureTimeout()
            return
        }
        stopTimeout() // Waiting for the user or for active is not an automatic check timeout.
        guard isActive() else { return }
        switch accessPurpose {
        case .start:
            switch access {
            case .authorized: locate()
            case .notDetermined: prompt(.permission, id: id)
            case .denied: prompt(.settings, id: id)
            default: deliver(.failure(accessFailure(access) ?? .unavailable))
            }
        case .permission:
            if access == .authorized { locate() }
            else if access == .notDetermined {
                phase = .authorizing
                if !requestedAuthorization {
                    requestedAuthorization = true
                    provider.requestAuthorization()
                }
            } else { deliver(.failure(accessFailure(access) ?? .unavailable)) }
        case .settingsReturn:
            if access == .authorized { locate() } else { cancel() }
        }
    }

    private func locate() {
        guard phase != .locating, isActive(), let provider else { return }
        phase = .locating
        ensureTimeout()
        provider.requestLocation()
    }

    private func ensureTimeout() {
        guard cancelTimeout == nil, let id = operationID else { return }
        let timeout = UUID()
        timeoutID = timeout
        cancelTimeout = scheduleTimeout { [weak self] in
            guard let self, self.accepts(id), self.timeoutID == timeout else { return }
            self.deliver(.failure(.unavailable))
        }
    }

    private func stopTimeout() {
        timeoutID = nil
        cancelTimeout?(); cancelTimeout = nil
    }

    func didEnterBackground() {
        guard phase != .idle else { return }
        if phase == .settings { leftForSettings = true } else { cancel() }
    }

    func didBecomeActive() {
        guard let id = operationID, accepts(id), isActive() else { return }
        if let terminalFailure { deliver(.failure(terminalFailure)); return }
        if phase == .settings {
            guard settingsOpened, leftForSettings else { return }
            settingsOpened = false
            leftForSettings = false
            accessPurpose = .settingsReturn
            phase = .checkingAccess
            ensureTimeout()
        }
        _ = provider?.refreshAccess(recheckServices: true)
        advance()
    }

    private func deliver(_ result: Result<SiteLocationSample, Failure>) {
        guard let id = operationID, accepts(id) else { return }
        // A sample can expire while inactive, so validate both received and resumed results.
        let result = result.flatMap { sample in
            sample.isUsable(at: now()) ? .success(sample) : .failure(.unavailable)
        }
        if !isActive() {
            if case .failure(let failure) = result { terminalFailure = failure }
            else { pendingResult = result }
            stopTimeout()
            return
        }
        cancel()
        completed?(result)
    }

    func cancel() {
        operationID = nil
        stopTimeout()
        provider?.accessChanged = nil
        provider?.result = nil
        provider?.cancel(); provider = nil
        settingsOpened = false
        leftForSettings = false
        pendingResult = nil
        terminalFailure = nil
        requestedAuthorization = false
        phase = .idle
    }
}

extension SiteCurrentLocationRequest.Failure: Error {}
