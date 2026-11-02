import CoreLocation

/// Never shared between attempts or with WiFiSSIDProvider.
final class SiteCurrentLocationProvider: NSObject, SiteCurrentLocationProviding, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var accessChanged: (() -> Void)?
    var result: ((Result<SiteLocationSample, SiteLocationFailure>) -> Void)?
    private lazy var accessResolver: SiteLocationAccessResolver = {
        let resolver = SiteLocationAccessResolver(
            readAuthorization: { [weak self] in self?.authorization ?? .unavailable },
            queryServices: { Self.queryServicesEnabled(completion: $0) })
        resolver.changed = { [weak self] in self?.accessChanged?() }
        return resolver
    }()

    override init() {
        super.init()
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.delegate = self
    }

    private var authorization: SiteLocationAuthorization {
        switch manager.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .authorizedAlways, .authorizedWhenInUse: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        @unknown default: return .unavailable
        }
    }

    func refreshAccess(recheckServices: Bool) -> SiteLocationAccess {
        accessResolver.refresh(recheckServices: recheckServices)
    }

    static func queryServicesEnabled(read: @escaping () -> Bool = CLLocationManager.locationServicesEnabled,
                                     completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let enabled = read()
            DispatchQueue.main.async { completion(enabled) }
        }
    }

    func requestAuthorization() { manager.requestWhenInUseAuthorization() }
    func requestLocation() { manager.requestLocation() }
    func cancel() { accessResolver.cancel(); manager.stopUpdatingLocation(); manager.delegate = nil }
    deinit { manager.stopUpdatingLocation() }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard manager === self.manager else { return }
        accessResolver.authorizationDidChange()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard manager === self.manager else { return }
        let samples = locations.sorted { $0.timestamp > $1.timestamp }.map {
            SiteLocationSample(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude,
                               horizontalAccuracy: $0.horizontalAccuracy, timestamp: $0.timestamp,
                               isReducedAccuracy: manager.accuracyAuthorization == .reducedAccuracy)
        }
        guard let sample = samples.first(where: { $0.isUsable(at: Date()) }) else {
            result?(.failure(.unavailable)); return
        }
        result?(.success(sample))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard manager === self.manager else { return }
        let denied = (error as? CLError)?.code == .denied
        if denied { accessResolver.locationWasDenied() }
        result?(.failure(denied ? .denied : .unavailable))
    }
}
